#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""赤金丹霞 → 云隐谷的竖向接缝地面（2026-10-29）。

不再用出图：直接拿**两区现在真正在用的草皮 tile** 逐像素混合，
所以不管哪一侧换图，接缝颜色永远接得上（旧版是单独出的一张红过渡图，
丹霞草皮换成 v4 之后它就成了一条过饱和的红带子）。

  · 左 = 赤金丹霞草皮，右 = 云隐谷草皮
  · 过渡带用 smoothstep + 低频噪声扰动边界，避免看到一条笔直的斜线
  · 尺寸 735 × 1664（世界深 420px @1.75 texel/px；1536 + 128 overlap）

用法：
    python tools/prep_jiedan_seam.py
然后本地无缝化（sprite-gen，零凭据）：
    cd E:/skill/game/sprite-gen-main/sprite-gen-main
    python -m sprite_gen.cli background-tile \
        --source <work> --out assets/scenes/tiles/seam_transition_west.png \
        --period 1536 --axis y --overlap 128
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEST = os.path.join(ROOT, "assets", "scenes", "tiles", "jiedan_grass.png")
EAST = os.path.join(ROOT, "assets", "scenes", "tiles", "zhuji_grass.png")
OUT = os.path.join(ROOT, "output", "tiles", "prep", "seam_transition_west_work.png")

WORLD_DEPTH = 420.0
TEXELS_PER_WORLD = 1.75
PERIOD = 1536
OVERLAP = 128
SOFT = 0.34          # 过渡带占宽度的比例（越窄越像一条硬线）


def tile_field(path: str, h: int, w: int) -> np.ndarray:
    """按 tile 平铺取样（896 的图模到目标尺寸，保持原生分辨率）。"""
    src = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    th, tw = src.shape[:2]
    yy = np.mod(np.arange(h), th)
    xx = np.mod(np.arange(w), tw)
    return src[np.ix_(yy, xx)]


def meander(h: int, seed: int = 20261029) -> np.ndarray:
    """沿 y 的低频起伏（首尾相接，配合 y 向无缝化）：让边界蜿蜒而不是一条直线。"""
    rng = np.random.default_rng(seed)
    prof = rng.random(h)
    prof = gaussian_filter(prof, sigma=h / 9.0, mode="wrap") \
        * 0.7 + gaussian_filter(prof, sigma=h / 22.0, mode="wrap") * 0.3
    lo, hi = prof.min(), prof.max()
    return (prof - (lo + hi) * 0.5) / max(hi - lo, 1e-4)


def main() -> int:
    w = int(round(WORLD_DEPTH * TEXELS_PER_WORLD))          # 735
    h = PERIOD + OVERLAP                                    # 1664
    west = tile_field(WEST, h, w)
    east = tile_field(EAST, h, w)
    x = (np.arange(w)[None, :] + 0.5) / w
    shift = meander(h)[:, None] * 0.30
    # smoothstep 只在 0..1 上成立：先把 u 归一，再取 S 曲线
    u = np.clip((x - 0.5 - shift) / (SOFT * 2.0), 0.0, 1.0)
    t = u * u * (3.0 - 2.0 * u)
    rgb = west * (1.0 - t[..., None]) + east * t[..., None]
    alpha = np.ones((h, w), dtype=np.float32)
    out = (np.dstack([rgb, alpha]) * 255.0).round().astype(np.uint8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(out, "RGBA").save(OUT)
    print(f"  {OUT}: {(w, h)}  左均值 {west.mean(axis=(0, 1)).round(3).tolist()}"
          f"  右均值 {east.mean(axis=(0, 1)).round(3).tolist()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
