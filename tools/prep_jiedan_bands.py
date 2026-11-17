#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""赤金丹霞（结丹区）三条外沿带 + 东侧竖向接缝过渡的整形器。

和云隐谷同一套口径：品红键 → 反合成去溢色 → 裁内容 → 压平 → 对齐亮度，
之后交给 sprite-gen background-tile 做单轴无缝。差别：
  · 南/北共用同一张丹霞崖壁（沿 x 重复），崖顶透明、崖体压到画面底边；
  · 西沿是一条竖版崖壁（沿 y 重复），悬崖在左、透明在右；
  · 东侧与筑基区相接，没有林带，改铺一条 420 世界像素宽的竖向地面过渡。

用法：
    python tools/prep_jiedan_bands.py            # 出到 output/tiles/jiedan/
    python tools/prep_jiedan_bands.py --check
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_region_bands as R  # noqa: E402  品红键 / 压平 / 裁切共用

ROOT = R.ROOT
SRC_DIR = os.path.join(ROOT, "vibe_images")
OUT_DIR = os.path.join(ROOT, "output", "tiles", "jiedan")
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")

SOUTH = os.path.join(SRC_DIR, "jiedan_band_south_1793269544089_fa639510.png")
NORTH = os.path.join(SRC_DIR, "jiedan_band_north_1793270572903_657d0c87.png")
WEST = os.path.join(SRC_DIR, "jiedan_band_west_1793270088569_c0a2b863.png")
SEAM = os.path.join(SRC_DIR, "jiedan_seam_west_1793270132981_b245beaf.png")

# 崖壁工作图：横向 1664 = period 1536 + overlap 128；高度 818/1.75 ≈ 467 世界像素。
# 南沿墙 355、北沿墙 480，两条都能被这条带盖住。
H_WORK = (1664, 818)
# 竖带：818 宽 / 1664 高，同理深度 467 世界像素。
V_WORK = (818, 1664)
# 接缝条：735/1.75 = 420 世界像素宽，1536/1.75 ≈ 878 世界像素一圈。
S_WORK = (735, 1664)
SEAM_TARGET_H = 1536


def _mean(path: str) -> np.ndarray:
    arr = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    return arr.mean(axis=(0, 1))


def _resize_rgba(rgb: np.ndarray, alpha: np.ndarray, size: tuple[int, int]):
    h, w = rgb.shape[:2]
    tw, th = size
    out = np.zeros((th, tw, 4), dtype=np.float32)
    for ch in range(3):
        im = Image.fromarray((rgb[:, :, ch] * 255.0 + 0.5).astype(np.uint8))
        out[:, :, ch] = np.asarray(im.resize((tw, th), Image.LANCZOS), dtype=np.float32) / 255.0
    a = Image.fromarray((alpha * 255.0 + 0.5).astype(np.uint8))
    out[:, :, 3] = np.asarray(a.resize((tw, th), Image.LANCZOS), dtype=np.float32) / 255.0
    return out[:, :, :3], out[:, :, 3]


def _key(rgb: np.ndarray, ref: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """品红键 + 只在真正有品红溢色的像素上反合成。

    照搬 R._key 会把整张图的半透明雾也当成「与品红线性混合」去解：雾的
    到品红距离中等，覆盖率算出来只有 0.5~0.8，减掉品红后蓝色被拉低，
    整片暖雾变成青绿（首版实测崖壁亮部因此泛黄绿）。只有 r、b 同时高于 g
    的像素才可能带品红溢色，其余保留观测色，雾和岩石的暖调不动。
    """
    d = np.sqrt(((rgb - ref) ** 2).sum(axis=2))
    t = np.clip((d - R.KEY_LO) / (R.KEY_HI - R.KEY_LO), 0.0, 1.0)
    alpha = t * t * (3.0 - 2.0 * t)
    full = float(np.median(d[d > R.KEY_HI]))
    c = np.clip(d / max(full, 1e-3), 0.0, 1.0)
    den = np.maximum(c, R.UNMIX_MIN)[:, :, None]
    fg = (rgb - ref[None, None, :] * (1.0 - c)[:, :, None]) / den
    fg = np.clip(fg, 0.0, 1.0)
    spill = (rgb[:, :, 0] > rgb[:, :, 1] + 0.02) & (rgb[:, :, 2] > rgb[:, :, 1] + 0.02)
    rgb = np.where(spill[:, :, None], fg, rgb)
    # 崖底投影是「岩石黑 + 品红」的暗紫，到品红的距离不小，光靠距离键不掉，
    # 会沿轮廓留下一条紫边（北带首版实测）。品红污染的判据是 r、b 同时高出 g 的
    # 那截，按这截把 alpha 压掉，再把剩余溢色往 g 收 —— 只动紫边，暖岩石不动。
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mag = np.minimum(r - g, b - g)
    kill = np.clip((mag - 0.02) / 0.08, 0.0, 1.0)
    alpha *= 1.0 - kill
    desat = np.clip((mag - 0.01) / 0.12, 0.0, 1.0) * 0.9
    rgb = np.stack([
        r - (r - g) * desat,
        g,
        b - (b - g) * desat,
    ], axis=2)
    return np.clip(rgb, 0.0, 1.0), alpha


def _band(name: str, path: str, size: tuple[int, int], wm: tuple[int, int, int, int] | None,
          target: float) -> None:
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    ref = R._bg_ref(rgb)
    if wm is not None:
        rgb, cast, ink = R._patch_watermark(rgb, wm)
    else:
        cast, ink = 0.0, 0.0
    rgb, alpha = _key(rgb, ref)
    rgb, alpha, box = R._crop_to_content(rgb, alpha)
    rgb, alpha = _resize_rgba(rgb, alpha, size)
    rgb = R._flatten_rgb(rgb, alpha)
    fg = alpha > 0.5
    # gamma 只在前景上解：透明区的黑像素会把整图均值拖下去，解出来的 gamma 反而更亮。
    lo, hi = 0.05, 20.0
    gamma = 1.0
    for _ in range(28):
        gamma = 0.5 * (lo + hi)
        if np.power(np.clip(rgb, 1e-4, 1.0), gamma).mean(axis=2)[fg].mean() < target:
            hi = gamma
        else:
            lo = gamma
    rgb = np.power(np.clip(rgb, 1e-4, 1.0), gamma)
    lum = rgb.mean(axis=2)
    rgba = np.concatenate([rgb, alpha[:, :, None]], axis=2)
    os.makedirs(OUT_DIR, exist_ok=True)
    dst = os.path.join(OUT_DIR, f"{name}.png")
    Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8)).save(dst)
    print(f"[{name}] {os.path.basename(path)} ref={np.round(ref, 3)} 水印色差={cast:.4f}")
    print(f"  -> {size[0]}x{size[1]}  前景 {fg.mean() * 100:.1f}%  亮度 {lum[fg].mean():.3f} "
          f"(目标 {target:.3f}) gamma={gamma:.3f}  {os.path.relpath(dst, ROOT)}")


def _seam() -> None:
    img = Image.open(SEAM).convert("RGB").resize(S_WORK, Image.LANCZOS)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    h, w = arr.shape[:2]
    k = max(2, int(w * 0.10))
    ref_l = _mean(os.path.join(TILE_DIR, "jiedan_grass.png"))
    ref_r = _mean(os.path.join(TILE_DIR, "zhuji_grass.png"))
    x = np.linspace(0.0, 1.0, w)[None, :, None]
    t = x * x * (3.0 - 2.0 * x)
    for _ in range(2):
        cur_l = arr[:, :k].mean(axis=(0, 1))
        cur_r = arr[:, -k:].mean(axis=(0, 1))
        gain = (ref_l / np.maximum(cur_l, 1e-4)) * (1.0 - t) + \
               (ref_r / np.maximum(cur_r, 1e-4)) * t
        arr = np.clip(arr * gain, 0.0, 1.0)
    # 左右各留一条 alpha 羽化，压进两侧地形时不出现硬直边。
    alpha = np.ones((h, w), dtype=np.float32)
    ramp = np.linspace(0.0, 1.0, 70, dtype=np.float32)
    ramp = ramp * ramp * (3.0 - 2.0 * ramp)
    alpha[:, :70] *= ramp[None, :]
    alpha[:, -70:] *= ramp[::-1][None, :]
    # 竖向无缝：顶边与底边做 40px 交叉渐变，background-tile 再做一次精细处理。
    out = np.dstack([arr, alpha])
    os.makedirs(OUT_DIR, exist_ok=True)
    dst = os.path.join(OUT_DIR, "jiedan_seam_west.png")
    Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA").save(dst)
    print(f"[seam] -> {w}x{h} 左/右参照 {np.round(ref_l, 3)} / {np.round(ref_r, 3)}  "
          f"{os.path.relpath(dst, ROOT)}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.check:
        print("check 模式仍会写工作图（无缝化需要文件），只看指标。")
    # 南/北各一张崖壁：南沿崖体压底、透明在上；北沿崖体贴顶、透明在下。
    _band("jiedan_cliff_s", SOUTH, H_WORK, (1370, 965, 1530, 1015), 0.185)
    _band("jiedan_cliff_n", NORTH, H_WORK, (1370, 965, 1530, 1015), 0.185)
    _band("jiedan_cliff_y", WEST, V_WORK, None, 0.185)
    _seam()
    print("next:")
    print(f"  background-tile --source {os.path.join(OUT_DIR, 'jiedan_cliff_s.png')} "
          f"--out {os.path.join(TILE_DIR, 'jiedan_band_south.png')} --period 1536 --axis x --overlap 128")
    print(f"  background-tile --source {os.path.join(OUT_DIR, 'jiedan_cliff_n.png')} "
          f"--out {os.path.join(TILE_DIR, 'jiedan_band_north.png')} --period 1536 --axis x --overlap 128")
    print(f"  background-tile --source {os.path.join(OUT_DIR, 'jiedan_cliff_y.png')} "
          f"--out {os.path.join(TILE_DIR, 'jiedan_band_west.png')} --period 1536 --axis y --overlap 128")
    print(f"  background-tile --source {os.path.join(OUT_DIR, 'jiedan_seam_west.png')} "
          f"--out {os.path.join(TILE_DIR, 'seam_transition_west.png')} --period {SEAM_TARGET_H} --axis y --overlap 128")
    return 0


if __name__ == "__main__":
    sys.exit(main())
