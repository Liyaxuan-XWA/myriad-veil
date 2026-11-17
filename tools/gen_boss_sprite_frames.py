"""BOSS 精灵帧处理管线：把图像模型出的「品红底多姿势图」变成能直接接进 SkinVisual 的等宽图集与 .tres。

为什么需要这一整条管线（不是一句抠图）：
  1. 模型给的图里帧与帧**不等宽**、脚底基线会漂、背景还飘着火星碎片。
     SkinVisual 只认「横向等宽图集 + frame_size」，所以必须按内容自动切帧再重排。
  2. 同一只角色的所有动画必须**共用一个缩放**，否则待机 1.0、出手 0.85，播起来像换了个人。
     所以分两遍：先切帧量尺寸，再按全角色统一缩放合成。
  3. 品红底不能只用「离品红多远」来抠：暗色像素离品红也远，会被误判成不透明的边缘。

抠图用的判据（这条是整份脚本里最值得记的东西）：
  背景是品红族 = R 高、B 高、**G 低**。定义 excess = min(r,b) - g。
  纯品红的 excess 最大；灰布、暗甲、橙火这些角色色的 excess 都 ≤ 0。
  因为 alpha 混合对 excess 是线性的，所以 a = 1 - excess/excess_bg 能**精确**还原半透明边缘，
  而灰布（r≈g≈b → excess≈0）不会被误抠掉。最后用 fg=(obs-(1-a)*bg)/a 反解颜色，边缘不留品红毛边。

用法：
  python tools/gen_boss_sprite_frames.py split   <sheet.png> <anim_name> --boss <boss_id> --frames 3 --order N
  python tools/gen_boss_sprite_frames.py preview <boss_id> [--anim-height dash_slash=0.8 ...]
  python tools/gen_boss_sprite_frames.py compose <boss_id> [--anim-height ...]

split 的产物落在 vibe_images/boss_work/<boss_id>/frames/<anim>/frame_NN.png + manifest.json；
preview 出一张各套动作并排在同一基线上的对照图（vibe_images/boss_work/<boss_id>_preview.png），
调 --anim-height 靠它，不要靠包围盒高度猜；
compose 读全角色 manifest，输出 assets/characters/boss/<boss_id>_<anim>.png 与 <boss_id>.tres。
"""

import argparse
import collections
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK_DIR = os.path.join(ROOT, "vibe_images", "boss_work")
OUT_DIR = os.path.join(ROOT, "assets", "characters", "boss")

# 形态学开运算的尺寸：比这个还小的孤立碎片（火星、灰烬）被丢掉。
# 5 是量出来的：披风撕边最细约 8~10px，再大就要啃到角色本体。
SPECK_KERNEL = 5
# 单帧缩放允许偏离全角色中位的幅度。超出就认定「这个姿势本来就蹲/跃」，不再硬拉平。
SCALE_TOLERANCE = 0.10
## 切帧画布底部给脚底留的空白（像素）。anchor_bottom 把画布底边贴地面，
## 所以这 20px 会显示成「脚悬空」，ArtDB 用 offset.y = 20 × scale 把它补回来。
FOOT_MARGIN = 20


def _work_dir(boss_id: str) -> str:
    return os.path.join(WORK_DIR, boss_id)


def _manifest_path(boss_id: str) -> str:
    return os.path.join(_work_dir(boss_id), "manifest.json")


def _load_manifest(boss_id: str) -> dict:
    p = _manifest_path(boss_id)
    if os.path.exists(p):
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"boss": boss_id, "anims": {}}


def _save_manifest(boss_id: str, data: dict) -> None:
    os.makedirs(_work_dir(boss_id), exist_ok=True)
    with open(_manifest_path(boss_id), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


def key_out(img: Image.Image) -> Image.Image:
    """按品红族背景抠图，返回 RGBA。背景色从四角实测，不写死 #FF00FF。"""
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    h, w, _ = rgb.shape
    # 四角 24x24 中位数当背景色（模型偶尔把背景画得略有不均，中位数比均值稳）
    corners = []
    for cy, cx in ((0, 0), (0, w - 24), (h - 24, 0), (h - 24, w - 24)):
        corners.append(rgb[cy:cy + 24, cx:cx + 24].reshape(-1, 3))
    bg = np.median(np.concatenate(corners, axis=0), axis=0)

    def excess_of(a):
        return np.minimum(a[..., 0], a[..., 2]) - a[..., 1]

    bg_ex = float(min(bg[0], bg[2]) - bg[1])
    if bg_ex < 0.15:
        raise SystemExit(
            f"背景不像品红族（实测 corner={np.round(bg,3).tolist()}, excess={bg_ex:.2f}）。"
            "这条管线只服务高饱和纯色底；换背景色请一并改 key_out 的判据。"
        )

    ex = excess_of(rgb)
    alpha = np.clip(1.0 - ex / bg_ex, 0.0, 1.0)
    # 压一下过渡带：让「基本确定是背景」的直接归零，避免留一层极淡的雾
    alpha = np.clip((alpha - 0.04) / 0.92, 0.0, 1.0)

    # 反解前景色：obs = a*fg + (1-a)*bg
    a3 = alpha[..., None]
    fg = (rgb - (1.0 - a3) * bg[None, None, :]) / np.maximum(a3, 1e-4)
    fg = np.clip(fg, 0.0, 1.0)

    # 品红溢色抑制（2026-10-26 虎妖待机表实测）：
    # 半透明像素（妖气墨烟、毛边、尘土）的 alpha 是由「品红度」反推的，估不准；
    # 反解之后会在这些地方残留背景的品红，成片出现就是「粉红色的烟」。
    # 只处理 alpha < 0.85 的软边 —— 实心区域的反解是精确的，动了只会把毛色洗淡。
    # 判据与键色同一套：min(R,B) - G > 0 就是还带品红。
    soft = alpha < 0.85
    spill = np.minimum(fg[..., 0], fg[..., 2]) - fg[..., 1]
    fix = soft & (spill > 0.0)
    if np.any(fix):
        k = np.where(fix, spill * 0.9, 0.0).astype(fg.dtype)
        fg[..., 0] = np.clip(fg[..., 0] - k, 0.0, 1.0)
        fg[..., 2] = np.clip(fg[..., 2] - k, 0.0, 1.0)

    out = np.dstack([fg, alpha])
    return Image.fromarray((out * 255.0).round().astype(np.uint8), "RGBA")


def _corner_color(img: Image.Image) -> tuple:
    """四角 24×24 的中位数当背景色，与 key_out 同一套取法。"""
    rgb = np.asarray(img.convert("RGB"))
    h, w, _ = rgb.shape
    parts = [rgb[0:24, 0:24], rgb[0:24, w - 24:w], rgb[h - 24:h, 0:24], rgb[h - 24:h, w - 24:w]]
    med = np.median(np.concatenate([p.reshape(-1, 3) for p in parts], axis=0), axis=0)
    return tuple(int(v) for v in med)


def _row_seams(img: Image.Image, rows: int) -> list:
    """多行姿势表的切缝：在等分点 ±12% 内找「背景占比最高」的一行，返回 [0, ...切点..., h]。

    ⚠ 等分切必然踩到脚掌（2×2 里上下两排的爪几乎相连）。找空行切才安全；
    各行高度允许不等，由调用方按最大行高补齐。
    """
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    bg = np.array(_corner_color(img), dtype=np.float32)
    is_bg = np.abs(a - bg).max(axis=2) < 30
    ratio = is_bg.mean(axis=1)
    h = a.shape[0]
    cuts = [0]
    for k in range(1, rows):
        center = int(h * k / rows)
        span = max(4, int(h * 0.12))
        lo, hi = max(1, center - span), min(h - 1, center + span)
        cuts.append(lo + int(np.argmax(ratio[lo:hi])))
    cuts.append(h)
    return cuts


def split_by_columns(rgba: Image.Image, expect: int):
    """退化路径：角色彼此粘连时，按「每列 alpha 能量」的最低点下刀，切成 expect 段。

    ⚠ 什么时候会走到这里：AI 把 3 个姿势画得前爪相触、尾巴互搭，连通块就并成一块，
    `split_frames` 只能拿到 1 个块（实测 slash_single / element_orb 整张切成 1479px 一条）。
    重抽一张能解决，但要花积分且不保证下次不粘；按列切是确定性的，宁可多这条兜底。

    切缝在「等分位置 ±1/6 格宽」范围内找 alpha 最低的列 —— 姿势之间即使相触，
    接触处也只是一条细颈，能量远低于躯干，所以最低点基本就是真接缝。
    """
    arr = np.asarray(rgba)
    alpha = arr[..., 3].astype(np.float32) / 255.0
    h, w = alpha.shape
    col = alpha.sum(axis=0)
    cuts = [0]
    for k in range(1, expect):
        center = int(w * k / expect)
        span = max(4, w // (expect * 6))
        lo, hi = max(1, center - span), min(w - 1, center + span)
        cuts.append(lo + int(np.argmin(col[lo:hi])))
    cuts.append(w)
    print(f"  ! 连通块不足，改按列切：x={cuts[1:-1]}")
    frames = []
    for i in range(len(cuts) - 1):
        seg = alpha[:, cuts[i]:cuts[i + 1]]
        mask = seg > 0.05
        if not mask.any():
            print(f"  ! 第 {i} 段是空的，跳过", file=sys.stderr)
            continue
        rows = np.where(mask.any(axis=1))[0]
        cols = np.where(mask.any(axis=0))[0]
        box = (cuts[i] + int(cols[0]), int(rows[0]),
               cuts[i] + int(cols[-1]) + 1, int(rows[-1]) + 1)
        out = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
        out.paste(rgba.crop(box), (0, 0), rgba.crop(box))
        frames.append(out)
    return frames


def rigid_shift(ref: np.ndarray, cur: np.ndarray) -> tuple:
    """相位相关求 (dx, dy)：把 cur 平移这么多后与 ref 的 alpha 重叠最大。

    为什么不用「包围盒中心」或「腿脚质心」对齐：
      四足走路时四条腿一直迈，腿脚质心每帧都在漂（虎妖实测 41px/1000px 画布），
      身体于是在自己格子里左右滑 —— 这就是"摆动"。
      整幅 alpha 掩码做互相关，压住的是「整只动物」，腿的局部摆动被平均掉，身体稳。
    """
    a = ref.astype(np.float32)
    b = cur.astype(np.float32)
    cross = np.fft.rfft2(a) * np.conj(np.fft.rfft2(b))
    den = np.abs(cross)
    den[den < 1e-9] = 1e-9
    r = np.fft.irfft2(cross / den, s=a.shape)
    dy, dx = np.unravel_index(int(np.argmax(r)), r.shape)
    if dy > a.shape[0] // 2:
        dy -= a.shape[0]
    if dx > a.shape[1] // 2:
        dx -= a.shape[1]
    return int(dx), int(dy)


def upper_body_cx(mask: np.ndarray) -> float:
    """取「躯干主体」的横坐标：上半身 alpha 列能量最密的那一列（带抛物线加权取峰）。

    ⚠ 这里用密度峰而不是质心（2026-10-26 第二次返工）：
      质心会随姿势改变而漂 —— 头往前探时质心前移，锚定算法就把整个精灵往后挪，
      躯干反而左右动，肉眼看到的就是"身子在抽"。
      上半身里最密的一列永远是躯干（胸腔+肩），头和尾只是两端的小质量，
      对峰位影响很小，所以锚它才稳。
    """
    ys, xs = np.nonzero(mask > 0.15)
    if len(ys) == 0:
        return -1.0
    top, bot = int(ys.min()), int(ys.max())
    band = mask[top:top + max(1, int((bot - top) * 0.55))]
    col = band.sum(axis=0).astype(np.float64)
    if col.sum() <= 0:
        return -1.0
    # 三列滑动平均再取峰：单列噪声会让峰在相邻列之间跳，平滑后峰位稳定得多
    k = np.ones(9) / 9.0
    smooth = np.convolve(col, k, mode="same")
    return float(np.argmax(smooth))


def drop_specks(rgba: Image.Image) -> Image.Image:
    """开运算找主体，把比主体细碎得多的孤立碎片（火星/灰烬）抹掉。"""
    arr = np.asarray(rgba)
    mask = Image.fromarray((arr[..., 3] > 128).astype(np.uint8) * 255, "L")
    body = mask.filter(ImageFilter.MinFilter(SPECK_KERNEL)).filter(
        ImageFilter.MaxFilter(SPECK_KERNEL + 4))
    keep = np.asarray(body) > 0
    out = arr.copy()
    out[..., 3] = np.where(keep, out[..., 3], 0)
    return Image.fromarray(out, "RGBA")


def _maxpool(a: np.ndarray, s: int) -> np.ndarray:
    h, w = a.shape
    return a[:h // s * s, :w // s * s].reshape(h // s, s, w // s, s).max(axis=(1, 3))


def _label_components(mask: np.ndarray) -> np.ndarray:
    """两遍扫描 + 并查集给二值图打连通块标号（本机没装 scipy，只能手写）。"""
    hh, ww = mask.shape
    par = list(range(hh * ww))

    def find(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x

    def union(x, y):
        rx, ry = find(x), find(y)
        if rx != ry:
            par[ry] = rx

    for y in range(hh):
        row = mask[y]
        for x in range(ww):
            if not row[x]:
                continue
            i = y * ww + x
            if x and row[x - 1]:
                union(i, i - 1)
            if y and mask[y - 1][x]:
                union(i, i - ww)
    return np.array([find(i) if mask.flat[i] else -1 for i in range(hh * ww)],
                    dtype=np.int64).reshape(hh, ww)


def split_frames(rgba: Image.Image, expect: int):
    """按连通块切帧：每块整体归到离它质心最近的那一格，返回紧贴内容的 RGBA 列表。

    为什么不切列：模型会把相邻两帧画得**在 x 上重叠**（palm_project 实测
    第 2 帧 x 536~1232、第 3 帧 x 1144~1760，中间根本没有一条空列）。
    竖着一刀切下去必然把某人的刀尖劈进隔壁格，游戏里就看见一截没人握的刀刃跟着别的帧飘。
    连通块天然没有这个问题：一个人是一个整块，质心落在哪格就归哪格，
    包围盒在 x 上互相溢出也无所谓 —— 反正拼图集时是按脚底 + 腿质心定位的。
    """
    arr = np.asarray(rgba)
    alpha = arr[..., 3].astype(np.float32) / 255.0
    h, w = alpha.shape
    if alpha.max() <= 0:
        raise SystemExit("image is empty after keying - wrong background key colour?")
    # 4x 降采样做连通块：纯 Python 并查集在全分辨率上太慢，降采样后 1.8M -> 11 万像素。
    # 用 max 池化而不是均值：细刀尖在均值里会被稀释到阈值以下，max 保住它。
    S = 4
    small = _maxpool((alpha > 0.25).astype(np.uint8), S)
    lab = _label_components(small)
    areas = np.bincount(lab[lab >= 0].ravel(), minlength=int(lab.max()) + 1)
    keep = [int(i) for i in np.where(areas >= max(12, areas.max() * 0.02))[0]]
    if len(keep) < expect:
        # 粘连时连通块数对不上，直接走按列切的退化路径（确定性，不用重抽）
        return split_by_columns(rgba, expect)
    slot_x = [w * (k + 0.5) / expect for k in range(expect)]
    slot_mask = np.zeros((expect, h, w), dtype=bool)
    owners = {}
    for c in keep:
        sel = lab == c
        cx = float(np.where(sel)[1].mean()) * S
        k = int(np.argmin([abs(cx - sx) for sx in slot_x]))
        owners.setdefault(k, []).append(round(cx))
        # ⚠ _maxpool 用向下取整：图高/宽不是 S 的倍数时，反推回来的掩码会比原图小一到两像素，
        #   直接拿去索引 slot_mask 会 IndexError（源图尺寸一变就复发）。这里补边再裁。
        big = np.repeat(np.repeat(sel, S, axis=0), S, axis=1)
        big = np.pad(big, ((0, max(0, h - big.shape[0])), (0, max(0, w - big.shape[1]))))[:h, :w]
        slot_mask[k][big] = True
    slot_mask &= alpha > 0.05
    frames = []
    for k in range(expect):
        band = slot_mask[k] if k in owners else None
        if band is None or not band.any():
            print(f"  ! slot {k} got no component (centroid x per slot: "
                  f"{ {o: cs for o, cs in owners.items()} }) - skipped", file=sys.stderr)
            continue
        rows = np.where(band.any(axis=1))[0]
        cols = np.where(band.any(axis=0))[0]
        box = (int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1)
        # 必须按掩码抠，不能直接裁矩形：两格的包围盒在 x 上会互相溢出
        # （palm_project 实测第 2 块 x 536~1240、第 3 块 1140~1764，重叠 100px）。
        # 直接裁的话第 3 格的矩形里就混进第 2 格的刀尖，游戏里看见一截没人握的刀刃在飘。
        out = arr.copy()
        out[..., 3] = np.where(slot_mask[k], arr[..., 3], 0).astype(np.uint8)
        frames.append(Image.fromarray(out, "RGBA").crop(box))
    return frames


def cmd_split(args) -> None:
    src = args.sheet
    if not os.path.exists(src):
        raise SystemExit(f"source sheet not found: {src}")
    boss_id = args.boss or args.anim.split("_")[0]
    img = Image.open(src)
    if args.crop_bottom > 0:
        # ⚠ 只在抠图前裁：水印是叠在品红底上的文字，键色抠不掉它，会被当成一片孤立前景。
        img = img.crop((0, 0, img.size[0], max(1, img.size[1] - args.crop_bottom)))
        print(f"  crop bottom {args.crop_bottom}px -> {img.size[0]}x{img.size[1]}")
    if args.unstack_rows > 1:
        # 模型很喜欢把 N 个姿势排成 2×2。切帧是按「横向槽位 + 连通块质心」分配的，
        # 上下两排的 x 完全重叠，不拆行就会被并成两格。这里按阅读顺序（左→右，上→下）
        # 把每一行横向接起来，得到一个单行长条 —— 姿势顺序不变。
        #
        # ⚠ 不能等分切：2×2 里上下两排的脚掌几乎贴在一起，正中一刀必然把脚切掉
        #   （实测第一版 walk_side 四帧全部缺爪）。改为在预期切点 ±12% 范围内
        #   找「背景占比最高的一行」当刀口，切出来各行高度可以不等，按最大值补齐。
        w, h = img.size
        cuts = _row_seams(img, args.unstack_rows)
        bands = [img.crop((0, cuts[i], w, cuts[i + 1])) for i in range(len(cuts) - 1)]
        band_h = max(b.size[1] for b in bands)
        strip = Image.new("RGB", (w * len(bands), band_h), _corner_color(img))
        for r, b in enumerate(bands):
            strip.paste(b, (r * w, band_h - b.size[1]))
        img = strip
        print(f"  unstack {args.unstack_rows} rows at y={cuts[1:-1]} -> {img.size[0]}x{img.size[1]}")
    print(f"split {os.path.basename(src)}  {img.size[0]}x{img.size[1]}  ->  {boss_id}/{args.anim}")
    keyed = drop_specks(key_out(img))
    frames = split_frames(keyed, args.frames)
    if not frames:
        raise SystemExit("no frame extracted.")

    out_dir = os.path.join(_work_dir(boss_id), "frames", args.anim)
    os.makedirs(out_dir, exist_ok=True)
    man = _load_manifest(boss_id)
    prev = man["anims"].get(args.anim) or {}
    # --append：一张图只放得下 3~4 个姿势，6~8 帧的套要分两张切。
    # 第二张接着第一张的帧号往后排、不删旧帧 —— 否则前半程会被后半程覆盖掉。
    if args.append and prev.get("frames"):
        entries = list(prev["frames"])
        base_i = len(entries)
        print(f"  append：保留已有 {base_i} 帧，从 frame_{base_i:02d} 往后排")
    else:
        for old in os.listdir(out_dir):
            if old.endswith(".png"):
                os.remove(os.path.join(out_dir, old))
        entries = []
        base_i = 0
    hs = [f.size[1] for f in frames]
    for i, f in enumerate(frames):
        p = os.path.join(out_dir, f"frame_{base_i + i:02d}.png")
        f.save(p)
        entries.append({"file": os.path.relpath(p, _work_dir(boss_id)).replace("\\", "/"),
                        "w": f.size[0], "h": f.size[1]})
    # 重切同一套动作时留住上次目视调好的高度倍率（换姿势表才需要 --height 显式清账）
    man["anims"][args.anim] = {"frames": entries, "order": args.order,
                               "height": args.height if args.height else prev.get("height", 1.0),
                               "flip_x": prev.get("flip_x", False) if args.flip_x is None
                               else bool(args.flip_x)}
    _save_manifest(boss_id, man)
    print(f"  {len(frames)} frames  content h min/med/max = "
          f"{min(hs)}/{int(np.median(hs))}/{max(hs)}  w = {[f.size[0] for f in frames]}  "
          f"height x{man['anims'][args.anim]['height']:g}"
          f"{'  flip_x' if man['anims'][args.anim]['flip_x'] else ''}")


def anim_order_of(man: dict) -> list:
    return sorted(man["anims"].keys(),
                  key=lambda a: (man["anims"][a].get("order", 99), a))


def resolve_anim_height(man: dict, items: list) -> dict:
    """每套动作的高度倍率：CLI 覆盖 manifest，manifest 里是上次目视调出来的结果。

    为什么要落到 manifest 里：这些倍率不是命令行参数那种可有可无的装饰，而是**素材的一部分**。
    漏写一次 --anim-height，重跑 compose 就会把 dash_slash 打回大 40%，
    而且画面照样跑得起来，等于把调好的比例悄悄改坏了。
    """
    ah = {a: float(m.get("height", 1.0)) for a, m in man["anims"].items()}
    for item in items:
        name, sep, val = item.partition("=")
        if not sep or name not in man["anims"]:
            raise SystemExit(f"--anim-height wants ANIM=FACTOR on a split anim, got {item!r}")
        ah[name] = float(val)
    return ah


def compute_factors(man: dict, content_h: float, frame_w: int, frame_h: int,
                    anim_height: dict, quiet: bool = False,
                    tolerance: float = None) -> dict:
    """每帧一个缩放系数。返回 {(anim, frame_index): factor}。
    # 缩放分两层，各治一种病：
    #  1) 动画内部：每帧算一个「拉到目标内容高」的系数，再夹到**本动画**中位的 ±TOL 内。
    #     不夹就会这样：模型把待机第 3 帧画矮 6%，播放时整只 BOSS 跟着呼吸一起缩。
    #  2) 动画之间：用**本动画自己的**中位做归一，不是全角色共用一个中位。
    #     因为模型每张姿势表都把人物画成不同大小（待机内容高 778、行走 671、横斩 591），
    #     拿全局中位去夹会把后生成的整批动作压成小一号 —— 换动画时 BOSS 肉眼可见地跳大小。
    # 姿势本身该矮的（下砸 / 踏地）用 --anim-height 单独压，不靠全局夹。
    注意 content_h 量的是**包围盒高**，分不清「蹲下去」和「模型把人画小了」，
    所以跨姿势表的比例一定要用 preview 子命令目视对一遍再定 anim_height。
    """
    all_fr = [(anim, i, e) for anim in man["anims"]
              for i, e in enumerate(man["anims"][anim]["frames"])]
    ideal = {anim: [content_h / e["h"] for e in man["anims"][anim]["frames"]]
             for anim in man["anims"]}
    factors = {}
    tol = SCALE_TOLERANCE if tolerance is None else float(tolerance)
    for anim, vals in ideal.items():
        med = float(np.median(vals))
        lo, hi = med * (1.0 - tol), med * (1.0 + tol)
        k = anim_height.get(anim, 1.0)
        for i, f in enumerate(vals):
            factors[(anim, i)] = min(max(f, lo), hi) * k
    # 画布高度兜底（**逐套**，不是全局）：某套动作里有帧放大后顶到画布上沿，就只把这一套整体缩进可用高度。
    # 为什么按套：竖劈下砸会把刀举过头顶，那一套的包围盒天然比待机高一大截；
    #   全局退让会因为一个举刀动作把九套动画一起缩小，等于为了一帧牺牲整套素材的压迫感。
    # 不兜就会这样：smash_v 第 1 帧内容高 691 > 可用 620，刀尖被画布上沿直接切平，
    #   游戏里前摇抬手时那把刀是缺了半截的 —— 而这正是玩家判断「要下砸了」的唯一依据。
    headroom = frame_h - FOOT_MARGIN
    for anim in man["anims"]:
        entries = man["anims"][anim]["frames"]
        over = max((factors[(anim, i)] * e["h"]) / headroom
                   for i, e in enumerate(entries))
        if over > 1.0:
            shrink = 1.0 / over
            if not quiet:
                print(f"  ! {anim}: tallest frame overflows canvas by "
                      f"{(over - 1) * 100:.0f}%, this anim shrunk {(1 - shrink) * 100:.1f}% "
                      f"- raise --frame-h to avoid it")
            for i in range(len(entries)):
                factors[(anim, i)] *= shrink
    # 画布宽度兜底：任何一帧按自己的系数放大后不许超出画布，超了就整体等比退让
    over = max((f * e["w"]) / (frame_w - 8) for (anim, i, e) in all_fr
               for f in [factors[(anim, i)]])
    if over > 1.0:
        shrink = 1.0 / over
        if not quiet:
            print(f"  ! canvas too narrow, whole set shrunk {(1 - shrink) * 100:.0f}% "
                  f"- raise --frame-w to keep the target height")
        factors = {k: v * shrink for k, v in factors.items()}
    return factors


def drop_small_components(img: Image.Image, tag: str = "",
                          min_ratio: float = 0.015, min_px: int = 24) -> Image.Image:
    """丢掉相对最大连通块太小的碎片（保留最大块）。

    为什么必须有这一步：切帧是按「槽位矩形」裁的，但姿势表里相邻两格的包围盒
    在 x 上会重叠近 100px，邻格的刀尖会落进本槽。掩码感知裁切只能保证不把
    **别的槽**的像素带进来，管不了「本槽矩形里本来就有的邻格残留」——
    palm_project 第 3 帧就因此飘着一截 1124px 的断刀（占角色 0.8%）。
    定一条比例规则比逐个手修可靠：实测全部碎片除了它都 ≤6px，
    所以「小于最大块 1.5%」既清得掉断刀，也不会啃到披风 / 刀穗这类真部件。

    会打印丢了什么 —— 不能静默丢：将来若某套动作真有独立的刀气/飘带，
    这行警告就是唯一线索。
    """
    arr = np.asarray(img).copy()
    mask = arr[..., 3] > 24
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    sizes = [0]
    cur = 0
    for y0, x0 in zip(*np.nonzero(mask)):
        y0, x0 = int(y0), int(x0)
        if lab[y0, x0]:
            continue
        cur += 1
        lab[y0, x0] = cur
        q = collections.deque([(y0, x0)])
        n = 0
        while q:
            y, x = q.popleft()
            n += 1
            for dy in (-1, 0, 1):
                yy = y + dy
                if yy < 0 or yy >= h:
                    continue
                row = lab[yy]
                mrow = mask[yy]
                for dx in (-1, 0, 1):
                    xx = x + dx
                    if 0 <= xx < w and mrow[xx] and not row[xx]:
                        row[xx] = cur
                        q.append((yy, xx))
        sizes.append(n)
    if len(sizes) <= 2:
        return img
    limit = max(min_px, max(sizes) * min_ratio)
    dropped = [s for s in sizes[1:] if s < limit]
    if not dropped:
        return img
    for c in range(1, len(sizes)):
        if sizes[c] < limit:
            arr[lab == c, 3] = 0
    print(f"    ! {tag}: dropped {len(dropped)} fragment(s) "
          f"{sorted(dropped, reverse=True)[:4]} (limit {limit:.0f}px)")
    return Image.fromarray(arr, "RGBA")


def cmd_compose(args) -> None:
    boss_id = args.boss
    man = _load_manifest(boss_id)
    if not man["anims"]:
        raise SystemExit(f"{boss_id}: nothing split yet.")
    base = _work_dir(boss_id)
    anim_height = resolve_anim_height(man, args.anim_height)
    for anim, v in anim_height.items():
        man["anims"][anim]["height"] = v
    _save_manifest(boss_id, man)
    factors = compute_factors(man, args.content_h, args.frame_w, args.frame_h, anim_height,
                              tolerance=args.scale_tolerance)
    baseline = args.frame_h - FOOT_MARGIN
    anim_order = anim_order_of(man)
    print(f"compose {boss_id}: per-anim normalisation, tolerance clamp "
          f"+/-{args.scale_tolerance * 100:.0f}%  canvas {args.frame_w}x{args.frame_h}  "
          f"baseline y={baseline}  (heights persisted into manifest.json)")
    for anim in anim_order:
        hs = [e["h"] * factors[(anim, i)]
              for i, e in enumerate(man["anims"][anim]["frames"])]
        note = f"  height x{anim_height[anim]:g}" if anim_height[anim] != 1.0 else ""
        if man["anims"][anim].get("flip_x"):
            note += "  flip_x"
        print(f"  {anim:<14} content h {min(hs):.0f}-{max(hs):.0f}{note}")

    os.makedirs(OUT_DIR, exist_ok=True)
    anim_rows = []
    for anim in anim_order:
        entries = man["anims"][anim]["frames"]
        strip = Image.new("RGBA", (args.frame_w * len(entries), args.frame_h), (0, 0, 0, 0))
        placed = []
        for j, e in enumerate(entries):
            fr = Image.open(os.path.join(base, e["file"])).convert("RGBA")
            # 先清掉邻格漏进来的刀尖等碎片，再做镜像/缩放/居中 —— 否则碎屑会跟着一起被放大
            fr = drop_small_components(fr, tag=f"{anim}#{j}")
            # 姿势表里这套的朝向跟别的套相反（walk_side 原图是往左走的，招式全是朝右）。
            # 项目约定美术一律朝右、朝向靠 Visual.scale.x 翻，所以在这里镜像掉，
            # 而不是回去重 roll 一张 —— 重 roll 会连带把已经调好的比例和抠图全换掉。
            if man["anims"][anim].get("flip_x"):
                fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
            f = factors[(anim, j)]
            w = max(1, int(round(e["w"] * f)))
            h = max(1, int(round(e["h"] * f)))
            fr = fr.resize((w, h), Image.LANCZOS)
            arr = np.asarray(fr)
            # 水平位置直接按「上半身质心落在格子中心」算 —— 一步到位，不再先按腿脚摆再修正。
            # 这样每帧的躯干都钉在同一处，播起来身体不晃；腿和尾照常动。
            # ⚠ 别改回「下半 25% 腿脚质心」：四足迈腿时那个质心每帧漂 40px 以上。
            cx = upper_body_cx(arr[..., 3].astype(np.float32) / 255.0)
            if cx < 0:
                cx = w * 0.5
            placed.append({"fr": fr, "w": w, "h": h,
                           "px": int(round(args.frame_w * (j + 0.5) - cx)),
                           "py": int(baseline - h), "j": j})

        # ---- 锚定自检（2026-10-26）----
        # 摆放时已把上半身质心钉在格子中心，这里只做验证并把偏差打出来：
        # 正常情况下每帧的 cx 都应该 ≈ 格子中心，偏差 >2px 说明该帧被钳过格。
        if len(placed) > 1:
            devs = []
            for p in placed:
                m = np.zeros((args.frame_h, args.frame_w), np.float32)
                a = np.asarray(p["fr"])[..., 3]
                # ⚠ 用「格子内局部坐标」：px 是整条图集上的全局 x，第 2 帧起就 ≥ frame_w，
                #   直接拿去切 frame_w 宽的掩码会整片切空（第一版就是这么静默对齐成 0 的）。
                lx = p["px"] - p["j"] * args.frame_w
                x0, y0 = max(0, lx), max(0, p["py"])
                x1 = min(args.frame_w, lx + p["w"])
                y1 = min(args.frame_h, p["py"] + p["h"])
                if x1 > x0 and y1 > y0:
                    m[y0:y1, x0:x1] = a[y0 - p["py"]:y1 - p["py"],
                                        x0 - lx:x1 - lx] / 255.0
                cx = upper_body_cx(m)
                # cx 是格子内的局部坐标，所以基准也用格心（frame_w/2），不能再加 j*frame_w
                devs.append(round(cx - args.frame_w * 0.5, 1) if cx >= 0 else None)
            print(f"  {anim:<14} 上半身偏离格心 {devs} px")

        for p in placed:
            j = p["j"]
            fr, w, h, px, py = p["fr"], p["w"], p["h"], p["px"], p["py"]
            # 必须把这一帧钳在自己的格子里：SpriteFrames 是按 frame_w 机械切图的，
            # 溢出到下一格就会凭空多出一截没人握的刀 / 一条断腿
            # （palm_project 第 2 帧实测溢出 37px）。这里只挡溢出，正常对齐不受影响。
            cell_l = j * args.frame_w
            if w > args.frame_w:
                print(f"    ! {anim}#{j}: 帧宽 {w} > 画布 {args.frame_w}，会被横向截断")
                px = cell_l
            elif px < cell_l or px + w > cell_l + args.frame_w:
                px = min(max(px, cell_l), cell_l + args.frame_w - w)
                print(f"    ! {anim}#{j}: 对齐后跨格，已钳进本格 (x={px})")
            if h > args.frame_h:
                print(f"    ! {anim}#{j}: 帧高 {h} > 画布 {args.frame_h}，会被纵向截断")
                py = 0
            elif py < 0:
                print(f"    ! {anim}#{j}: 顶部溢出 {-py}px，已下移")
                py = 0
            strip.paste(fr, (px, py), fr)
        out_png = os.path.join(OUT_DIR, f"{boss_id}_{anim}.png")
        strip.save(out_png)
        loop = 1 if anim in ("idle", "walk_side") else 0
        speed = {"idle": 5.0, "walk_side": 10.0}.get(anim, 24.0)
        anim_rows.append({"name": anim, "file": f"{boss_id}_{anim}.png",
                          "count": len(entries), "loop": loop, "speed": speed,
                          "region_w": args.frame_w, "region_h": args.frame_h})
        print(f"  {anim:16s} {len(entries)} frames -> {os.path.basename(out_png)}")

    write_tres(boss_id, anim_rows)
    print(f"  .tres -> assets/characters/boss/{boss_id}.tres")


def write_tres(boss_id: str, anim_rows: list) -> None:
    """手写 SpriteFrames .tres —— 只填 path 不填 uid，Godot 会按路径解析。"""
    lines = ['[gd_resource type="SpriteFrames" format=3]', ""]
    for r_i, r in enumerate(anim_rows):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/characters/boss/{r["file"]}" '
                     f'id="{r_i + 1}_tex"]')
    lines.append("")
    sub_ids = []
    for r_i, r in enumerate(anim_rows):
        for f_i in range(r["count"]):
            sid = f"AtlasTexture_{r_i + 1}_{f_i}"
            sub_ids.append((r["name"], sid))
            lines.append(f'[sub_resource type="AtlasTexture" id="{sid}"]')
            lines.append(f'atlas = ExtResource("{r_i + 1}_tex")')
            lines.append(f'region = Rect2({f_i * r["region_w"]}, 0, {r["region_w"]}, {r["region_h"]})')
            lines.append("")
    lines.append("[resource]")
    lines.append("animations = [")
    for r_i, r in enumerate(anim_rows):
        lines.append("{")
        lines.append('"frames": [')
        frames = [sid for (nm, sid) in sub_ids if nm == r["name"]]
        for k, sid in enumerate(frames):
            tail = "" if k == len(frames) - 1 else ","
            lines.append('{')
            lines.append('"duration": 1.0,')
            lines.append(f'"texture": SubResource("{sid}")')
            lines.append('}' + tail)
        lines.append("],")
        lines.append(f'"loop": {r["loop"]},')
        lines.append(f'"name": &"{r["name"]}",')
        lines.append(f'"speed": {r["speed"]}')
        lines.append("}" + ("," if r_i < len(anim_rows) - 1 else ""))
    lines.append("]")
    p = os.path.join(OUT_DIR, f"{boss_id}.tres")
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    # 缩放写在 ArtDB 的 scale 字段里，.tres 不携带任何尺寸语义


def cmd_preview(args) -> None:
    """把所有动画按同一显示倍率画到一条共同基线上，用来看跨姿势表的人体大小跳不跳。

    为什么需要这一步：compose 的比例尺是**包围盒高**，而包围盒高被刀的位置牵着走 ——
    举刀过顶的姿势包围盒 780、沉身下蹲 590，归一化会把它们全拉成一样高，
    于是「模型把人画小了」和「这个人真的蹲下去了」这两种情况根本分不开。
    只有把各套动作并排画在同一条地平线上，眼睛才能判出该给哪套加 --anim-height。
    """
    boss_id = args.boss
    man = _load_manifest(boss_id)
    if not man["anims"]:
        raise SystemExit(f"{boss_id}: nothing split yet.")
    base = _work_dir(boss_id)
    anim_height = resolve_anim_height(man, args.anim_height)
    factors = compute_factors(man, args.content_h, args.frame_w, args.frame_h, anim_height, quiet=True)
    ds = args.display
    slot = int(args.frame_w * ds)
    row_h = int(args.content_h * ds * 1.9)
    pad_l = 190
    ground = int(row_h * 0.92)
    canvas = Image.new("RGB", (pad_l + slot * max(len(m["frames"]) for m in man["anims"].values()) + 20,
                               row_h * len(man["anims"]) + 30), (34, 32, 38))
    draw = ImageDraw.Draw(canvas)
    # 每 50 世界像素一条刻度：跳 10% 就是 59px ≈ 12 显示 px，肉眼在这种刻度下看得出来的
    for anim_i, anim in enumerate(anim_order_of(man)):
        y0 = 20 + row_h * anim_i
        for k in range(0, 9):
            gy = y0 + ground - k * int(50 * ds)
            if gy < y0:
                break
            draw.line([(pad_l, gy), (canvas.width, gy)],
                      fill=(60, 58, 66) if k else (150, 120, 60), width=1)
        draw.text((12, y0 + ground - int(args.content_h * ds) + 6),
                  f"{anim} x{anim_height.get(anim, 1.0):.2f}", fill=(220, 210, 200))
        # 玩家窗高那条蓝线：硬指标是「BOSS 体型 ≥ 玩家 2 倍」，画出来直接量
        py = y0 + ground - int(args.player_h * ds)
        draw.line([(pad_l, py), (canvas.width, py)], fill=(80, 140, 190), width=1)
        for j, e in enumerate(man["anims"][anim]["frames"]):
            fr = Image.open(os.path.join(base, e["file"])).convert("RGBA")
            f = factors[(anim, j)] * ds
            w, h = max(1, int(round(e["w"] * f))), max(1, int(round(e["h"] * f)))
            fr = fr.resize((w, h), Image.LANCZOS)
            arr = np.asarray(fr)
            band = arr[int(h * 0.75):, ..., 3].astype(np.float32)
            total = band.sum()
            cx = float((band.sum(axis=0) * np.arange(w)).sum() / total) if total > 1 else w * 0.5
            px = int(pad_l + slot * j + slot * 0.5 - cx)
            canvas.paste(fr, (px, y0 + ground - h), fr)
    out = os.path.join(WORK_DIR, f"{boss_id}_preview.png")
    canvas.save(out)
    print(f"preview {boss_id}: {len(man['anims'])} anims, display x{ds}, "
          f"grid every 50 world px -> {os.path.basename(out)}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("split", help="抠图 + 切帧 + 量尺寸")
    s.add_argument("sheet")
    s.add_argument("anim")
    s.add_argument("--boss", default="")
    s.add_argument("--frames", type=int, default=4)
    s.add_argument("--order", type=int, default=1)
    s.add_argument("--height", type=float, default=0.0,
                   help="这套动作的高度倍率；不填则沿用 manifest 里上次的值")
    s.add_argument("--flip-x", dest="flip_x", action="store_true", default=None,
                   help="这套姿势表画的是朝左，合成时水平镜像成项目约定的朝右；不填则沿用上次的值")
    s.add_argument("--crop-bottom", type=int, default=0,
                   help="抠图前先裁掉底部 N 像素：AI 出图右下角带「AI生成」水印，不裁会变成一个多余的连通块")
    s.add_argument("--unstack-rows", type=int, default=1,
                   help="模型把 N 个姿势画成多行网格时，按阅读顺序拆成单行再切（2 = 上下两行各两个）")
    s.add_argument("--append", action="store_true",
                   help="接在已有帧后面继续排（6~8 帧的套要分两张切，第二张加这个）")
    s.set_defaults(func=cmd_split)
    c = sub.add_parser("compose", help="按动画各自归一合成等宽图集 + 出 .tres")
    c.add_argument("boss")
    c.add_argument("--content-h", type=float, default=590.0)
    c.add_argument("--frame-w", type=int, default=900)
    c.add_argument("--frame-h", type=int, default=720,
                   help="切帧画布高；必须容得下最高的那一帧（举刀过头），否则该套会被逐套兜底缩小")
    c.add_argument("--scale-tolerance", type=float, default=SCALE_TOLERANCE,
                   help="逐帧缩放相对本套中位的允许偏差（默认 0.10）。"
                        "拆两张表的动作两批可能画得大小差一倍，那时要放大到 0.6~0.8 才能拉齐")
    c.add_argument("--anim-height", nargs="*", default=[], metavar="ANIM=FACTOR",
                   help="某套动作整体高矮倍率（下砸 / 踏地这类真该矮一档的姿势），"
                        "如 --anim-height smash_v=0.86 stomp_aoe=0.92")
    c.set_defaults(func=cmd_compose)
    p = sub.add_parser("preview", help="各套动作并排画到同一基线上，目视校 --anim-height")
    p.add_argument("boss")
    p.add_argument("--content-h", type=float, default=590.0)
    p.add_argument("--frame-w", type=int, default=900)
    p.add_argument("--frame-h", type=int, default=720)
    p.add_argument("--anim-height", nargs="*", default=[], metavar="ANIM=FACTOR")
    p.add_argument("--player-h", type=float, default=270.0,
                   help="玩家切窗高，用来在每行画一条参照线（默认 270 = ArtDB 里 player_liqingyun 的窗高）")
    p.add_argument("--display", type=float, default=0.24, help="显示倍率，只影响出图大小")
    p.set_defaults(func=cmd_preview)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
