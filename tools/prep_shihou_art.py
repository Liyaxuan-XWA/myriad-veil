#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""镇墟石犼：立绘抠图 + 骨骼拆件源（2026-10-31）。

输入是 ImageGen 的品红底定妆图（3/4 朝右），输出透明 PNG：
  品红抠图 → 去溢色 → 按内容裁切 → 缩放到目标高度。
产物同时喂给 tools/build_world_boss_rigs.py 的 shihou 条目做分件。

用法：
    python tools/prep_shihou_art.py
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_boss_sprite_frames import key_out  # noqa: E402

SRC = "vibe_images/shihou_boss_concept_tail_1793459774540_1b8cc551.png"
OUT = "assets/characters/boss/shihou.png"
GRID = "output/shihou_rig_grid.png"
TRIM_ALPHA = 64
FLOOR_ALPHA = 12
TARGET_H = 1400


def despill(cut: np.ndarray) -> np.ndarray:
    rgb = cut[..., :3].astype(np.float32)
    spill = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    k = np.where(spill > 0.0, spill * 0.92, 0.0)
    rgb[..., 0] = np.clip(rgb[..., 0] - k, 0.0, 255.0)
    rgb[..., 2] = np.clip(rgb[..., 2] - k, 0.0, 255.0)
    out = cut.copy()
    out[..., :3] = rgb.round().astype(np.uint8)
    return out


def main() -> int:
    im = Image.open(SRC).convert("RGB")
    cut = np.array(key_out(im))
    a = cut[..., 3]
    a[a < FLOOR_ALPHA] = 0
    cut[..., 3] = a
    cut = despill(cut)
    ys, xs = np.nonzero(a > TRIM_ALPHA)
    art = Image.fromarray(cut).crop(
        (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    s = TARGET_H / float(art.size[1])
    size = (max(1, round(art.size[0] * s)), TARGET_H)
    art = Image.fromarray(despill(np.array(art.resize(size, Image.LANCZOS))))
    canvas = Image.new("RGBA", (art.size[0] + 4, art.size[1] + 4), (0, 0, 0, 0))
    canvas.alpha_composite(art, (2, 2))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    canvas.save(OUT)
    print(f"  {OUT}: {canvas.size}")

    from PIL import ImageDraw
    grid = Image.new("RGBA", canvas.size, (24, 24, 28, 255))
    grid.alpha_composite(canvas)
    d = ImageDraw.Draw(grid)
    w, h = grid.size
    for x in range(0, w, 50):
        d.line([(x, 0), (x, h)], fill=(255, 255, 0, 60), width=1)
    for y in range(0, h, 50):
        d.line([(0, y), (w, y)], fill=(255, 255, 0, 60), width=1)
    for x in range(0, w, 100):
        d.text((x + 2, 2), str(x), fill=(255, 255, 120, 255))
        d.text((x + 2, h - 14), str(x), fill=(255, 255, 120, 255))
    for y in range(0, h, 100):
        d.text((2, y + 1), str(y), fill=(120, 255, 255, 255))
        d.text((w - 40, y + 1), str(y), fill=(120, 255, 255, 255))
    os.makedirs(os.path.dirname(GRID), exist_ok=True)
    grid.save(GRID)
    print(f"  {GRID}: {grid.size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
