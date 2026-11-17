"""把外部生成的「破境材料」图标表与「化神坛」世界素材切进项目（2026-11-02）。

生成方（豆包）给的底不是约定的 #FF00FF，而是一块 ~#A64068 的暗洋红，
且右下角带「豆包AI生成」水印。所以这里：
  1. 先量出该表的众数色当背景，按「与背景色距离 + 与边框连通」两条件清底
     —— 只删掉和格子边界连成一片的像素，晶体本体是闭合形状，不会被误删；
  2. 把右下角水印区先涂成背景色再键出（否则它会撑大内容包围盒）；
  3. 内容裁方 → 256² → polish（颗粒 + 边缘光）→ 透明底 PNG。

用法：
  python -m tools.import_pojing_icons --sheet-a A.png --sheet-b B.png \
         --out output/pojing_icons_staging
  # 确认无误后再落盘（自动备份同名旧图）：
  python -m tools.import_pojing_icons --sheet-a A.png --sheet-b B.png --apply
  python -m tools.import_pojing_icons --altar 坛.png --out output/pojing_icons_staging
  python -m tools.import_pojing_icons --altar 坛.png --apply
"""
from __future__ import annotations

import argparse
import collections
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _art_common import polish  # noqa: E402

ICON_DIR = "assets/ui/icon"
ALTAR_OUT = "assets/scenes/world/huashen_altar.png"
BACKUP_DIR = "tools/pojing_icon_src"

# 表是 2 列 × 3 行，阅读顺序 = 从左到右、从上到下
COLS, ROWS = 2, 3
ORDER_A = [
    "mat_pojing_di_zhuji", "mat_pojing_tian_zhuji",
    "mat_pojing_di_jiedan", "mat_pojing_tian_jiedan",
    "mat_pojing_di_yuanying", "mat_pojing_tian_yuanying",
]
ORDER_B = [
    "mat_pojing_di_huashen", "mat_pojing_tian_huashen",
    "mat_pojing_zhuji", "mat_pojing_jiedan",
    "mat_pojing_yuanying", "mat_pojing_huashen",
]
ICON_SIZE = 256
# 表内每格四周再收一点，避免隔壁格的内容/格线渗进来
CELL_INSET = 0.022


def modal_color(a: np.ndarray) -> np.ndarray:
    """众数色 = 生成图的底色（本次实测约 #A64068）。"""
    flat = a.reshape(-1, 3)
    step = max(1, len(flat) // 20000)
    cnt = collections.Counter(map(tuple, flat[::step].tolist()))
    return np.array(cnt.most_common(1)[0][0], dtype=np.int16)


def kill_watermark(im: Image.Image, bg) -> None:
    """右下角水印涂成背景色，后面键底时一起走。"""
    d = ImageDraw.Draw(im)
    d.rectangle([im.width * 0.74, im.height * 0.90, im.width, im.height],
                fill=(int(bg[0]), int(bg[1]), int(bg[2])))


def key_out(cell: Image.Image, bg, tol: int = 46) -> Image.Image:
    """键底：先按「离底色足够近」删，再只留最大连通块。
    ⚠ 不能沿用旧的「与格子边界连通就删」—— 这批表里晶体几乎顶到格子上下边
    （内容 61×74 / 格子 192×85），那条规则会把整枚晶体一起删光。
    只留最大块顺带解决水印残字、格线和孤点。"""
    a = np.array(cell.convert("RGB")).astype(np.int16)
    near = np.abs(a - bg).sum(axis=2) <= tol
    keep = (~near).astype(np.uint8)
    lab, n = ndimage.label(keep)
    if n == 0:
        return Image.fromarray(np.dstack([a.astype(np.uint8),
                                          np.zeros_like(a[:, :, 0], dtype=np.uint8)]), "RGBA")
    sizes = ndimage.sum(keep, lab, np.arange(1, n + 1))
    biggest = int(np.argmax(sizes)) + 1
    mask = (lab == biggest).astype(np.uint8)
    # 二次通过：把被主体包住的洞补回来（晶体内部常有接近底色的高光缝）
    holes = ndimage.binary_fill_holes(mask.astype(bool)).astype(np.uint8)
    alpha = np.where(holes > 0, 255, 0).astype(np.uint8)
    # 去洋红偏色：半透明边缘会吃掉一块底色，把 r/b 压回灰阶附近
    # （与 tools/slice_wujiu_icons.py 的 keyed() 同一手法）
    gray = ((a[:, :, 0] + a[:, :, 1] + a[:, :, 2]) // 3).astype(np.int16)
    tint = (np.minimum(a[:, :, 0], a[:, :, 2]) - a[:, :, 1]) > 4
    r2 = np.where(tint, np.minimum(a[:, :, 0], gray + 10), a[:, :, 0])
    b2 = np.where(tint, np.minimum(a[:, :, 2], gray + 14), a[:, :, 2])
    out = np.stack([r2, a[:, :, 1], b2, alpha], axis=-1).astype(np.uint8)
    res = Image.fromarray(out, "RGBA")
    # 透明区里残留的底色会随 LANCZOS 渗到边缘：先把最近的不透明颜色「渗」过去
    arr = np.array(res)
    opaque = arr[:, :, 3] > 8
    if opaque.any():
        inds = ndimage.distance_transform_edt(~opaque, return_distances=False,
                                             return_indices=True)
        arr[:, :, :3] = arr[:, :, :3][tuple(inds)]
        res = Image.fromarray(arr, "RGBA")
    return res


def square_trim(img: Image.Image, pad_ratio: float = 0.08) -> Image.Image | None:
    # ⚠ 必须按 alpha 求包围盒：前面把不透明颜色「渗」进了透明区，
    #   RGBA 的 getbbox() 会把整张图当成内容，于是裁方算出的偏移把晶体推出画面。
    bbox = img.getchannel("A").getbbox()
    if not bbox:
        return None
    x0, y0, x1, y1 = bbox
    w, h = x1 - x0, y1 - y0
    side = max(w, h)
    pad = side * pad_ratio
    side = int(side + pad * 2)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    # 让内容中心 (cx, cy) 落在新画布正中：偏移 = 画布中心 - 内容中心
    out.alpha_composite(img, (int(side / 2 - cx), int(side / 2 - cy)))
    return out


def slice_sheet(path: str, ids, out_dir: str, apply: bool) -> list[tuple[str, int, int]]:
    im = Image.open(path).convert("RGB")
    bg = modal_color(np.asarray(im))
    kill_watermark(im, bg)
    cw, ch = im.width / COLS, im.height / ROWS
    report: list[tuple[str, int, int]] = []
    for i, item_id in enumerate(ids):
        r, c = divmod(i, COLS)
        box = (int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch))
        mx = int((box[2] - box[0]) * CELL_INSET)
        my = int((box[3] - box[1]) * CELL_INSET)
        cell = im.crop((box[0] + mx, box[1] + my, box[2] - mx, box[3] - my))
        keyed = key_out(cell, bg)
        trimmed = square_trim(keyed)
        if trimmed is None:
            print("  !! %s 这一格没检测到内容，跳过" % item_id)
            continue
        icon = trimmed.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
        icon = polish(icon, grain=0.10, rim_alpha=0.16)
        target_dir = ICON_DIR if apply else out_dir
        os.makedirs(target_dir, exist_ok=True)
        dst = os.path.join(target_dir, item_id + ".png")
        icon.save(dst)
        filled = int((np.array(icon)[:, :, 3] > 8).sum())
        report.append((item_id, trimmed.width, filled))
        print("  %-28s 原格 %dx%d -> 256px  实心像素 %d" % (item_id, trimmed.width,
                                                          trimmed.height, filled))
    return report


def import_altar(path: str, out_dir: str, apply: bool) -> None:
    im = Image.open(path).convert("RGB")
    bg = modal_color(np.asarray(im))
    keyed = key_out(im, bg)
    trimmed = square_trim(keyed, pad_ratio=0.03)
    if trimmed is None:
        print("  !! 化神坛没检测到内容")
        return
    dst = ALTAR_OUT if apply else os.path.join(out_dir, "huashen_altar.png")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    trimmed.save(dst)
    print("  化神坛 %dx%d → %s" % (trimmed.width, trimmed.height, dst))


def backup_before_apply(ids) -> None:
    stamp = "icons_before_2026-11-02"
    dst_dir = os.path.join(BACKUP_DIR, stamp)
    os.makedirs(dst_dir, exist_ok=True)
    for item_id in ids:
        src = os.path.join(ICON_DIR, item_id + ".png")
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(dst_dir, item_id + ".png"))
    print("  旧图已备份到 %s" % dst_dir)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet-a")
    ap.add_argument("--sheet-b")
    ap.add_argument("--altar")
    ap.add_argument("--out", default="output/pojing_icons_staging")
    ap.add_argument("--apply", action="store_true",
                    help="直接落进 assets/（会先备份同名旧图）")
    args = ap.parse_args()

    if not (args.sheet_a or args.sheet_b or args.altar):
        ap.print_help()
        return 2
    os.makedirs(args.out, exist_ok=True)

    if args.apply and (args.sheet_a or args.sheet_b):
        backup_before_apply(ORDER_A + ORDER_B)
    if args.sheet_a:
        print("Sheet A")
        slice_sheet(args.sheet_a, ORDER_A, args.out, args.apply)
    if args.sheet_b:
        print("Sheet B")
        slice_sheet(args.sheet_b, ORDER_B, args.out, args.apply)
    if args.altar:
        print("化神坛")
        import_altar(args.altar, args.out, args.apply)
    print("完成。目标目录：%s" % (ICON_DIR if args.apply else args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
