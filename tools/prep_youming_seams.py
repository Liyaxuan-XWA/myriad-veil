#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""幽冥灵墟的两条地面接缝（2026-10-31）。

北接赤金丹霞、东邻青岚野，都不种墙，直接拿**两区现在在用的草皮 tile** 逐像素
过渡，换图后颜色自动接得上：

  · seam_transition_youming_north.png：1664×735，上 = 丹霞红土，下 = 幽冥草地
  · seam_transition_youming_east.png ：735×1664，左 = 幽冥草地，右 = 青岚草地

北接缝的板顶压在世界边界以北 140，即贴图 u≈0.33 以上被丹霞南侧崖带盖住；
所以过渡必须在 u=0.33 前就走完，否则可见区会剩一条橙土带（实机踩过）。
u=0.33 起再压一层接触阴影，让崖脚落在暗紫里，而不是亮橙贴暗崖。

两侧 alpha 羽化：贴图板四边按短边淡出，边缘与底下地形无缝。
过渡带用 smoothstep + 低频噪声扰动边界，避免看到一条笔直的线。

用法：
    python tools/prep_youming_seams.py
随后本地无缝化（sprite-gen，零凭据）：
    background-tile --source output/tiles/youming/seam_transition_youming_north.png \
        --out assets/scenes/tiles/seam_transition_youming_north.png \
        --period 1536 --axis x --overlap 128
    background-tile --source output/tiles/youming/seam_transition_youming_east.png \
        --out assets/scenes/tiles/seam_transition_youming_east.png \
        --period 1536 --axis y --overlap 128
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")
WORK_DIR = os.path.join(ROOT, "output", "tiles", "youming")

JIEDAN = os.path.join(TILE_DIR, "jiedan_grass.png")
YOUMING = os.path.join(TILE_DIR, "youming_grass.png")
LIANQI = os.path.join(TILE_DIR, "lianqi_grass.png")

PERIOD = 1536
OVERLAP = 128
DEPTH = 735          # 420 世界像素 × 1.75 texel/px
MEANDER = 0.20       # 边界起伏幅度（占短边比例）
## 北接缝：板顶 y=-140，u=0.333 才是世界边界；过渡必须在可见区之前走完
NORTH_START, NORTH_END = 0.04, 0.41
## 东接缝：两侧都露在可见区，过渡居中
EAST_START, EAST_END = 0.30, 0.72


def tile_field(path: str, h: int, w: int) -> np.ndarray:
    src = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    th, tw = src.shape[:2]
    yy = np.mod(np.arange(h), th)
    xx = np.mod(np.arange(w), tw)
    return src[np.ix_(yy, xx)]


def meander(n: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    prof = rng.random(n)
    prof = gaussian_filter(prof, sigma=n / 9.0, mode="wrap") * 0.7 \
        + gaussian_filter(prof, sigma=n / 22.0, mode="wrap") * 0.3
    lo, hi = prof.min(), prof.max()
    return (prof - (lo + hi) * 0.5) / max(hi - lo, 1e-4)


def blend(a: np.ndarray, b: np.ndarray, axis: int, seed: int,
          start: float, end: float) -> np.ndarray:
    """axis=0：a 在上、b 在下；axis=1：a 在左、b 在右。"""
    h, w = a.shape[:2]
    k = h if axis == 0 else w
    u = (np.arange(k, dtype=np.float32) + 0.5) / k
    # 起伏沿接缝方向走：横向带随 x 起伏，竖向带随 y 起伏
    if axis == 1:
        shift = (meander(h, seed) * MEANDER)[:, None]
    else:
        shift = (meander(w, seed) * MEANDER)[None, :]
    if axis == 1:
        u = u[None, :]
    else:
        u = u[:, None]
    t = np.clip((u - start - shift) / (end - start), 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    return a * (1.0 - t[..., None]) + b * t[..., None]


def edge_alpha(h: int, w: int, axis: int, lo: float, hi: float) -> np.ndarray:
    """沿 axis 两侧淡出：0..lo 淡入、hi..1 淡出。"""
    n = h if axis == 0 else w
    u = (np.arange(n, dtype=np.float32) + 0.5) / n
    a = np.clip(u / max(lo, 1e-4), 0.0, 1.0) \
        * np.clip((1.0 - u) / max(1.0 - hi, 1e-4), 0.0, 1.0)
    a = a * a * (3.0 - 2.0 * a)
    if axis == 0:
        return np.repeat(a[:, None], w, axis=1)
    return np.repeat(a[None, :], h, axis=0)


def save(rgb: np.ndarray, alpha: np.ndarray, name: str) -> None:
    h, w = rgb.shape[:2]
    out = (np.dstack([rgb, alpha]) * 255.0 + 0.5).astype(np.uint8)
    os.makedirs(WORK_DIR, exist_ok=True)
    path = os.path.join(WORK_DIR, name)
    Image.fromarray(out, "RGBA").save(path)
    print(f"  {os.path.relpath(path, ROOT)}  {w}x{h}  "
          f"上/左 {rgb[0].mean(axis=0).round(3).tolist()}  "
          f"下/右 {rgb[-1].mean(axis=0).round(3).tolist()}  "
          f"alpha {alpha.min():.2f}..{alpha.max():.2f}")


def main() -> int:
    # 北接缝：横向带，上丹霞、下幽冥
    h, w = DEPTH, PERIOD + OVERLAP
    north = blend(tile_field(JIEDAN, h, w), tile_field(YOUMING, h, w), 0, 20261031,
                  NORTH_START, NORTH_END)
    # 崖脚接触阴影：世界边界在 u≈0.333，从那里往南压暗，收在 +100 世界像素左右
    v = (np.arange(h, dtype=np.float32) + 0.5) / h
    shade = 0.72 + 0.28 * np.clip((v - 0.33) / (0.58 - 0.33), 0.0, 1.0)
    north *= shade[:, None, None]
    north_alpha = edge_alpha(h, w, 0, 0.03, 0.88)
    save(north, north_alpha, "seam_transition_youming_north.png")
    # 东接缝：竖向带，左幽冥、右青岚
    h, w = PERIOD + OVERLAP, DEPTH
    east = blend(tile_field(YOUMING, h, w), tile_field(LIANQI, h, w), 1, 20261032,
                 EAST_START, EAST_END)
    east_alpha = edge_alpha(h, w, 1, 0.09, 0.91)
    save(east, east_alpha, "seam_transition_youming_east.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
