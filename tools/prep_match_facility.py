#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""万界棋坛（卡片自走棋入口，facility_id = "match"）主城地标收片。

现役是场景里一块 120×80 的青色 ColorRect 占位，art_db 里连 facility_match 条目都没有
→ get_facility_visual("match") 一路回落到 facility_generic。这张脚本把它换成正式地标。

管线和图标那批同一套（见 tools/mat_icon_plate.py 的 key_magenta：搬色不反解 + 去紫偏），
只是最后放进 **2048²** 画布并按现有 9 张设施的内容高占比对齐，因为
skin_visual._apply_auto_fit 读的是非透明区域高度，target_length 才是显示高度。

用法：
  python tools/prep_match_facility.py                 # 只出对照表，不落盘
  python tools/prep_match_facility.py --write         # 落盘 assets/scenes/facilities/match.png
  python tools/prep_match_facility.py --pick v4       # 换候选
"""
import argparse
import glob
import os
import shutil
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from mat_icon_plate import key_magenta, VIBE  # noqa: E402

OUT = os.path.join(ROOT, "assets", "scenes", "facilities", "match.png")
FAC = os.path.join(ROOT, "assets", "scenes", "facilities")
CANVAS = 2048
# 现有 9 张的非透明内容高占比 0.56~0.93，中位约 0.74（arena/alchemy/forge/warehouse 都在这附近）
TARGET_H = 0.74
# 轮廓搬色带宽。0 = 沿用图标那批的口径（<=24px 搬色、之外反解）。
# 实测收窄到 4~6px 会让光晕走反解、而反解在淡紫底光上过冲成**纯绿**（中位 (140,255,204)、63.6% 偏绿），
# 所以这里保持 0， pale 的问题交给 grade_glow 统一配色解决。
EDGE_PROP = 0


GLOW_LO = 8         # 光晕带的 alpha 下界
GLOW_HI = 230       # 上界：物件轮廓的羽化边也在这带里，一起校正好
REF_GLOWS = ["arena", "memory", "tower", "gateway", "warehouse"]


def glow_reference():
    """现有地标光晕的中位色 —— 在运行时量，不写死，换参照件会自动跟。"""
    acc = []
    for f in REF_GLOWS:
        p = os.path.join(FAC, f + ".png")
        if not os.path.exists(p):
            continue
        a = np.asarray(Image.open(p).convert("RGBA")).astype(np.float64)
        m = (a[..., 3] > GLOW_LO) & (a[..., 3] <= 120)
        if m.sum() < 500:
            continue
        acc.append(np.median(a[m][:, :3], axis=0))
    if not acc:
        raise SystemExit("量不到参照地标的光晕色")
    return np.mean(np.stack(acc), axis=0)


def grade_glow(im, ref):
    """把新地标的光晕色按通道增益配到参照中位色。

    生图给的光晕是 (182,178,229) 这类**发白的淡紫**，而现有 9 张全是 (35~68, 46~88, 65~106)
    的暗青 —— 差 3 倍亮度，铺在深色地面上就是一块发光的垫子，一眼就是「另一档美术」。
    """
    a = np.asarray(im.convert("RGBA")).astype(np.float64)
    m = (a[..., 3] > GLOW_LO) & (a[..., 3] <= GLOW_HI)
    if m.sum() < 500:
        return im, None, None
    src = np.median(a[m][:, :3], axis=0)
    gain = np.clip(ref / np.maximum(src, 1.0), 0.12, 3.0)
    # ⚠ 只在光晕带上施加：早先写成整图乘 gain，把不透明的物件本体一起压到
    #   中位亮度 49（现有 9 张是 99~130），地标直接沉进地面里了。
    a[..., :3] = np.clip(a[..., :3] * (1.0 + (gain[None, None, :] - 1.0) * m[..., None]), 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA"), src, gain


def find(pick):
    ps = sorted(glob.glob(os.path.join(VIBE, "facility_match_%s*.png" % pick)),
                key=os.path.getmtime)
    if not ps:
        raise SystemExit("找不到候选：vibe_images/facility_match_%s*.png" % pick)
    return ps[-1]


def assemble(path, edge_prop_px=EDGE_PROP):
    """键色原片 → 光晕配色 → 透明底 → 按内容包围盒裁 → 内容高 CANVAS×TARGET_H 居中放进 2048²。"""
    keyed = key_magenta(Image.open(path).convert("RGB"), edge_prop_px)
    keyed, _src, _gain = grade_glow(keyed, glow_reference())
    a = np.asarray(keyed)
    ys, xs = np.where(a[..., 3] > 12)
    if len(xs) == 0:
        raise SystemExit("整张都是键色，判不出内容")
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    crop = keyed.crop(box)
    s = (CANVAS * TARGET_H) / crop.size[1]
    w, h = int(round(crop.size[0] * s)), int(round(crop.size[1] * s))
    if max(w, h) > CANVAS - 24:                      # 宽物件别顶穿画布，留 12px 边
        k = (CANVAS - 24) / max(w, h)
        w, h = int(w * k), int(h * k)
    crop = crop.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(crop, ((CANVAS - w) // 2, (CANVAS - h) // 2))
    return canvas, box, (w, h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="落盘 match.png")
    ap.add_argument("--pick", default="v5", help="候选前缀（v1/v4/v5…）")
    args = ap.parse_args()

    src = find(args.pick)
    canvas, box, size = assemble(src)
    ca = np.asarray(canvas)
    print("候选      :", os.path.basename(src))
    ref = glow_reference()
    m = (ca[..., 3] > GLOW_LO) & (ca[..., 3] <= 120)
    print("光晕中位色 : %s   参照（现有地标）%s" % (
        np.median(ca[m][:, :3], 0).astype(int) if m.sum() > 500 else "无", ref.astype(int)))
    print("内容包围盒 : %dx%d（原片 1024²）" % (box[2] - box[0], box[3] - box[1]))
    print("放进画布后 : %dx%d  高占比 %.2f 宽占比 %.2f" % (size[0], size[1],
          size[1] / CANVAS, size[0] / CANVAS))
    print("alpha      : 实心>200 %.1f%%  全透 %.1f%%  均值 %.0f" % (
        100 * (ca[..., 3] > 200).mean(), 100 * (ca[..., 3] == 0).mean(), ca[..., 3].mean()))
    rgb = ca[..., :3].astype(int)
    vis = ca[..., 3] > 60
    pink = vis & (rgb[..., 0] > rgb[..., 1] + 40) & (rgb[..., 2] > rgb[..., 1] + 20)
    print("偏粉残留   : %.2f%% 可见像素" % (100 * pink.sum() / max(vis.sum(), 1)))

    # 对照表：新地标 vs 现有 9 张，同一底色同一尺寸
    S = 300
    ps = sorted(glob.glob(os.path.join(FAC, "*.png")))
    ncol = 4
    rows = (len(ps) + 1 + ncol - 1) // ncol
    sheet = Image.new("RGB", (S * ncol, S * rows), (44, 46, 52))
    items = [(os.path.basename(p), Image.open(p).convert("RGBA")) for p in ps]
    items.insert(0, ("match.png ← 新", canvas))
    for i, (name, im) in enumerate(items):
        bb = im.getchannel("A").getbbox() or (0, 0, im.size[0], im.size[1])
        t = im.crop(bb)
        t.thumbnail((S - 16, S - 16), Image.LANCZOS)
        cell = Image.new("RGBA", (S, S), (52, 54, 60, 255))
        cell.alpha_composite(t, ((S - t.size[0]) // 2, (S - t.size[1]) // 2))
        sheet.paste(cell.convert("RGB"), ((i % ncol) * S, (i // ncol) * S))
    out = os.path.join(ROOT, "output", "match_facility_sheet.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print("对照表（左上=新地标，其余=现有 9 张）：", out)

    if args.write:
        bk = os.path.join(ROOT, "assets", "_backup", "match_facility_20261104")
        os.makedirs(bk, exist_ok=True)
        if os.path.exists(OUT):
            shutil.copy2(OUT, os.path.join(bk, "match.png"))
        canvas.save(OUT)
        print("已落盘", OUT)


if __name__ == "__main__":
    main()
