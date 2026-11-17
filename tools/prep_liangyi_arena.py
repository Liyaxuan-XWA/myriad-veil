"""把两仪真人交接包的两张场地美术处理成引擎可直接用的贴图（2026-10-28）。

  1) 战场石砖 `liangyi_arena_tiles.png` → `assets/scenes/liangyi_arena_ground.png`
     · 裁到 **1200×676**（引擎 `bg_liangyi_arena` 的 target_length 口径）；
     · 裁块从原图左上取，**避开右下角的生图水印**；
     · 做**无缝化**：石砖是平铺的（`map_tiles: 6`），硬裁会在接缝处露馅。

  2) 中央太极贴花 `liangyi_taiji_decal.png` → `assets/scenes/liangyi_taiji_decal.png`
     · 洋红幕抠成透明底（与 `build_liangyi_rig_v2.py` 同一套「洋红度」判据）；
     · 按内容 bbox 居中、四周留 5% 透明余量，保证贴到场地中央是个正圆。

⚠ 无缝化用的是「滚半张 + 接缝羽化」：把图沿轴滚一半，接缝就移到画面正中，
   在接缝两侧各 FEATHER 像素做线性交叉淡化，滚回来的图左右（上下）边缘自然接得上。
   直接对边缘做羽化是错的 —— 那样只是把边缘糊掉，接缝还在。

用法：python tools/prep_liangyi_arena.py
"""
from __future__ import annotations

from PIL import Image, ImageDraw
import numpy as np
from scipy import ndimage
import os

HANDOFF = "vibe_images/art_handoff"
SCENES = "assets/scenes"
GROUND_SRC = os.path.join(HANDOFF, "liangyi_arena_tiles.png")
DECAl_SRC = os.path.join(HANDOFF, "liangyi_taiji_decal.png")
GROUND_OUT = os.path.join(SCENES, "liangyi_arena_ground.png")
DECAL_OUT = os.path.join(SCENES, "liangyi_taiji_decal.png")
CROP = (1200, 676)      # 引擎口径
FEATHER = 96            # 接缝羽化宽度（像素）
MAG_HI, MAG_LO = 90.0, 40.0


def make_tileable(img: Image.Image) -> Image.Image:
    """滚半张 + 接缝羽化，让贴图能无缝平铺"""
    a = np.asarray(img).astype(float)
    for axis in (0, 1):
        n = a.shape[axis]
        half = n // 2
        rolled = np.roll(a, half, axis=axis)
        # 接缝在 half 处：左侧 FEATHER 像素里从「原图」淡入到「滚过的图」
        sl = slice(half, half + FEATHER)
        if axis == 0:
            ramp = np.linspace(0.0, 1.0, FEATHER)[:, None, None]
            a[sl] = a[sl] * (1.0 - ramp) + rolled[sl] * ramp
        else:
            ramp = np.linspace(0.0, 1.0, FEATHER)[None, :, None]
            a[:, sl] = a[:, sl] * (1.0 - ramp) + rolled[:, sl] * ramp
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def prep_ground() -> None:
    im = Image.open(GROUND_SRC).convert("RGB")
    # ⚠ 从左上取，右下角留给水印（生图水印固定躲在那儿）
    im = im.crop((0, 0, CROP[0], CROP[1]))
    im = make_tileable(im)
    im.save(GROUND_OUT)
    print("ground ->", GROUND_OUT, im.size)


def prep_decal() -> None:
    im = Image.open(DECAl_SRC).convert("RGB")
    rgb = np.asarray(im).astype(int)
    corners = np.concatenate([
        rgb[:24, :24].reshape(-1, 3), rgb[:24, -24:].reshape(-1, 3),
        rgb[-24:, :24].reshape(-1, 3), rgb[-24:, -24:].reshape(-1, 3)])
    mag = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    # ⚠ 键色**自适应**：生图给的「洋红」常常是暗红（这张实测四角 (147,31,77)，
    #   洋红度只有 42），写死 MAG_HI=90 就整张抠不动、bbox 返回全画面。
    #   所以阈值按四角的洋红度比例取：背景落在 HI 以上、图形（黑石/白石/金边
    #   的洋红度都 ≤ 0）落在 LO 以下。
    key_mag = float(np.median([mag[:24, :24], mag[:24, -24:], mag[-24:, :24], mag[-24:, -24:]]))
    hi, lo = max(6.0, key_mag * 0.65), max(2.0, key_mag * 0.25)
    print("decal key magenta=%.0f -> threshold hi=%.0f lo=%.0f" % (key_mag, hi, lo))
    alpha = (np.clip((hi - mag) / max(1.0, hi - lo), 0.0, 1.0) * 255).astype(np.uint8)

    # ① 只留最大的连通块：水印是「叠在键色底上的深色字」，洋红度低会被判成
    #    前景，抠完就跟着贴花一起留下（和切件脚本同一个坑，同一套解法）。
    lbl, n = ndimage.label(alpha > 100)
    if n > 1:
        sizes = ndimage.sum(np.ones_like(lbl), lbl, range(1, n + 1))
        keep = int(np.argmax(sizes)) + 1
        alpha = np.where(np.isin(lbl, [i + 1 for i in range(n) if i + 1 != keep]), 0, alpha)
        print("  drop %d stray components (watermark)" % (n - 1))
    # ② 收紧 alpha：半透明的那一圈正是暗红残边，直接压掉（图形边缘会内缩 1~2px，
    #    但贴到场地中央是「只画一次」的装饰，硬边比脏边重要）
    alpha = np.where(alpha < 110, 0, np.clip((alpha.astype(int) - 110) * 255 // 145, 0, 255))
    # 去溢出：C = (P − (1−a)·M)/a，M 用实测的四角中位色
    key = np.median(corners, axis=0)
    af = np.clip(alpha / 255.0, 0.35, 1.0)
    out = rgb.astype(float)
    for ch in range(3):
        out[..., ch] = np.clip((out[..., ch] - (1.0 - af) * key[ch]) / af, 0, 255)
    a = np.dstack([out.astype(np.uint8), alpha])

    # ③ 清边：去溢出只压掉了「混进去的键色比例」，边缘那 1~3px 仍会留一圈暗红。
    #    改成把**实心核心区的颜色向外推**几层，直接盖掉边缘带 —— 贴花是「只画一次」
    #    的场地中央装饰，硬边比脏边重要。
    core = alpha > 240
    band = (alpha > 60) & (alpha <= 240)
    if core.any() and band.any():
        cur = a[..., :3].astype(float)
        valid = core.copy()
        for _ in range(4):
            w = valid.astype(float)
            sw = ndimage.uniform_filter(w, 3)
            num = np.stack([ndimage.uniform_filter(cur[..., c] * w, 3) for c in range(3)], -1)
            ok = band & (sw > 0.05)
            if not ok.any():
                break
            cur[ok] = num[ok] / sw[ok][:, None]
            valid |= ok
        a[..., :3] = np.clip(cur, 0, 255).astype(np.uint8)

    # 按内容 bbox 居中，四周留 5% 透明余量
    ys, xs = np.where(alpha > 60)
    y0, y1, x0, x1 = int(ys.min()), int(ys.max()) + 1, int(xs.min()), int(xs.max()) + 1
    side = max(x1 - x0, y1 - y0)
    pad = int(side * 0.05)
    size = side + pad * 2
    canvas = np.zeros((size, size, 4), dtype=np.uint8)
    oy = (size - (y1 - y0)) // 2
    ox = (size - (x1 - x0)) // 2
    canvas[oy:oy + (y1 - y0), ox:ox + (x1 - x0)] = a[y0:y1, x0:x1]
    Image.fromarray(canvas, "RGBA").resize((1024, 1024), Image.LANCZOS).save(DECAL_OUT)
    print("decal  ->", DECAL_OUT, "content bbox", (x0, y0, x1, y1))


def main() -> int:
    os.makedirs(SCENES, exist_ok=True)
    prep_ground()
    prep_decal()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
