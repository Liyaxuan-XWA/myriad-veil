#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从遮罩 + tile + 林带反推一张区域总览图，给世界区域面板当背景。

为什么不让面板直接吃 ground_texture：那张「整幅地图」正是这轮要废掉的东西
（6000x4000 的图被拉到 1.46 倍糊在屏幕上）。但面板要的其实只是「一眼看出哪里是路、
哪里是林子」，所以拿同一批素材按 1/8 重算一遍就行 —— 遮罩本来就是这个分辨率。

和实机的差异是有意的：这里把 tile 缩到 64px 再平铺（实机 896 盖 512 世界像素，
遮罩 1px = 8 世界像素，所以一格 tile 正好 64 遮罩像素），细节全糊掉，只留色相和
笔触的疏密。总览图要的就是这个「像地图而不像照片」的读法。

用法：
    python tools/bake_region_minimap.py
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")
OUT_PNG = os.path.join(ROOT, "assets", "ui", "facilities", "world_map_lianqi.png")

SCALE = 8                    # 输出 = 世界 / SCALE，和遮罩同口径
TILE_WORLD = 512.0           # 一张 tile 盖的世界像素（和 region_terrain.gdshader 一致）
BAND_DENSITY = 896.0 / 512.0  # 林带的 texel/世界像素，和 tile 同一密度


def _load(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255.0


def _tiled(src: str, h: int, w: int) -> np.ndarray:
    """把一张可平铺 tile 缩到「一格 = tile_world/SCALE 像素」后铺满 h x w。"""
    cell = int(round(TILE_WORLD / SCALE))
    rgb = _load(src)[: :, :3]
    small = np.asarray(
        Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8)).resize(
            (cell, cell), Image.LANCZOS
        ),
        dtype=np.float32,
    ) / 255.0
    reps = (-(-h // cell), -(-w // cell))          # 向上取整
    return np.tile(small, (reps[0], reps[1], 1))[:h, :w]


def _over(dst: np.ndarray, src: np.ndarray, at: tuple[int, int]) -> None:
    """把带 alpha 的图层按左上角 at 叠到 dst 上（原地改）。"""
    y0, x0 = at
    sh, sw = src.shape[:2]
    win = dst[y0:y0 + sh, x0:x0 + sw]
    a = src[:, :, 3:]
    win[:, :, :3] = src[:, :, :3] * a + win[:, :, :3] * (1.0 - a)


def bake() -> int:
    mask = _load(os.path.join(TILE_DIR, "lianqi_mask.png"))
    h, w = mask.shape[:2]
    t = mask[:, :, :3] / np.maximum(mask[:, :, :3].sum(axis=2, keepdims=True), 1e-4)

    grass = _tiled(os.path.join(TILE_DIR, "lianqi_grass.png"), h, w)
    road = _tiled(os.path.join(TILE_DIR, "lianqi_road.png"), h, w)
    forest = _tiled(os.path.join(TILE_DIR, "lianqi_forestfloor.png"), h, w)
    col = grass * t[:, :, :1] + road * t[:, :, 1:2] + forest * t[:, :, 2:3]

    # 贴花：A 高的地方压暗一点，让总览上的草地不是一块平色板
    decal = mask[:, :, 3:]
    col = col * (1.0 - 0.22 * decal)
    rgba = np.concatenate([col, np.ones((h, w, 1), dtype=np.float32)], axis=2)

    # 林带按实机同样的「短边 = 贴图边长 / 密度」摆到南/东两条边上
    south = _load(os.path.join(TILE_DIR, "lianqi_band_south.png"))
    east = _load(os.path.join(TILE_DIR, "lianqi_band_east.png"))
    s_cell = int(round(south.shape[1] / SCALE))       # 一个周期在总览里占多宽
    s_depth = int(round(south.shape[0] / BAND_DENSITY / SCALE))
    e_depth = int(round(east.shape[1] / BAND_DENSITY / SCALE))
    e_cell = int(round(east.shape[0] / SCALE))

    band_s = np.asarray(
        Image.fromarray((south * 255.0 + 0.5).astype(np.uint8)).resize(
            (s_cell, s_depth), Image.LANCZOS
        ),
        dtype=np.float32,
    ) / 255.0
    for x in range(0, w, s_cell):
        _over(rgba, band_s[:, :min(s_cell, w - x)], (h - s_depth, x))
    band_e = np.asarray(
        Image.fromarray((east * 255.0 + 0.5).astype(np.uint8)).resize(
            (e_depth, e_cell), Image.LANCZOS
        ),
        dtype=np.float32,
    ) / 255.0
    for y in range(0, h, e_cell):
        _over(rgba, band_e[:min(e_cell, h - y)], (y, w - e_depth))

    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    Image.fromarray((np.clip(rgba[:, :, :3], 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)).save(OUT_PNG)
    lum = rgba[:, :, :3].mean(axis=2)
    print(f"{os.path.relpath(OUT_PNG, ROOT)}  {w}x{h}  亮度均值 {lum.mean():.3f}  p05/p95 "
          f"{np.percentile(lum, 5):.3f}/{np.percentile(lum, 95):.3f}")
    print(f"   南带 {band_s.shape[1]}x{band_s.shape[0]}（深 {s_depth}）  "
          f"东带 {band_e.shape[1]}x{band_e.shape[0]}（深 {e_depth}）")
    return 0


if __name__ == "__main__":
    sys.exit(bake())
