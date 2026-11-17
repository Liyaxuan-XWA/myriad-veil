#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""云隐谷区域总览图（给世界区域面板当背景）。

遮罩 + tile 按 1/8 重算，再把东 / 北 / 接缝三条林带按实机密度压上去。
接缝带中间留南口。林带用 PIL 的 alpha_composite，避免手写混合时通道错位。
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_region_minimap as M  # noqa: E402

ROOT = M.ROOT
TILE_DIR = M.TILE_DIR
OUT_PNG = os.path.join(ROOT, "assets", "ui", "facilities", "world_map_zhuji.png")
SCALE = M.SCALE


def _band_tile(path: str, size: tuple[int, int]) -> Image.Image:
    return Image.open(path).convert("RGBA").resize(size, Image.LANCZOS)


def bake() -> int:
    mask = M._load(os.path.join(TILE_DIR, "zhuji_mask.png"))
    h, w = mask.shape[:2]
    t = mask[:, :, :3] / np.maximum(mask[:, :, :3].sum(axis=2, keepdims=True), 1e-4)

    # 总览图用调色板而不是直接缩 tile：896→64 的降采样会把草叶/针叶抽成横条纹，
    # 而总览要的是「路网 / 林缘 / 草地」三块可分，细节交给实机地形。
    grass_c = np.array([0.17, 0.23, 0.235], dtype=np.float32)
    road_c = np.array([0.38, 0.39, 0.37], dtype=np.float32)
    forest_c = np.array([0.095, 0.145, 0.16], dtype=np.float32)
    col = grass_c * t[:, :, 0:1] + road_c * t[:, :, 1:2] + forest_c * t[:, :, 2:3]
    decal = mask[:, :, 3:]
    col = col * (1.0 - 0.10 * decal)
    # 一点点低频纹理，避免整张图像色块；用重度模糊的草地亮度，不会带回条纹
    tex_img = Image.open(os.path.join(TILE_DIR, "zhuji_grass.png")).convert("L")
    tex_img = tex_img.filter(ImageFilter.GaussianBlur(12)).resize((w, h), Image.LANCZOS)
    tex = np.asarray(tex_img, dtype=np.float32) / 255.0
    col = col * (0.93 + 0.14 * tex[:, :, None])
    base = Image.fromarray((np.clip(col, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)).convert("RGBA")

    # 北带：沿 x 重复，贴在顶边
    n = Image.open(os.path.join(TILE_DIR, "zhuji_band_north.png")).convert("RGBA")
    n_cell = int(round(n.width / SCALE))
    n_depth = int(round(n.height / M.BAND_DENSITY / SCALE))
    n_tile = _band_tile(os.path.join(TILE_DIR, "zhuji_band_north.png"), (n_cell, n_depth))
    n_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for x in range(0, w, n_cell):
        n_layer.paste(n_tile, (x, 0))
    base = Image.alpha_composite(base, n_layer)

    # 东带：沿 y 重复，贴在右边
    e = Image.open(os.path.join(TILE_DIR, "zhuji_band_east.png")).convert("RGBA")
    e_depth = int(round(e.width / M.BAND_DENSITY / SCALE))
    e_cell = int(round(e.height / SCALE))
    e_tile = _band_tile(os.path.join(TILE_DIR, "zhuji_band_east.png"), (e_depth, e_cell))
    e_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y in range(0, h, e_cell):
        e_layer.paste(e_tile, (w - e_depth, y))
    base = Image.alpha_composite(base, e_layer)

    # 接缝带：沿 x 重复，贴在底边；中间掏空南口
    s = Image.open(os.path.join(TILE_DIR, "zhuji_band_seam.png")).convert("RGBA")
    s_cell = int(round(s.width / SCALE))
    s_depth = int(round(s.height / M.BAND_DENSITY / SCALE))
    s_tile = _band_tile(os.path.join(TILE_DIR, "zhuji_band_seam.png"), (s_cell, s_depth))
    s_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for x in range(0, w, s_cell):
        s_layer.paste(s_tile, (x, h - s_depth))
    gap_half = int(round(360.0 / SCALE))
    mid = w // 2
    ImageDraw.Draw(s_layer).rectangle(
        [mid - gap_half, 0, mid + gap_half, h], fill=(0, 0, 0, 0))
    base = Image.alpha_composite(base, s_layer)

    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    base.convert("RGB").save(OUT_PNG)
    rgb = np.asarray(base.convert("RGB"), dtype=np.float32) / 255.0
    lum = rgb.mean(axis=2)
    print(f"{os.path.relpath(OUT_PNG, ROOT)}  {w}x{h}  亮度均值 {lum.mean():.3f}  p05/p95 "
          f"{np.percentile(lum, 5):.3f}/{np.percentile(lum, 95):.3f}")
    print(f"   北带深 {n_depth}  东带深 {e_depth}  接缝深 {s_depth}  南口 ±{gap_half}px")
    return 0


if __name__ == "__main__":
    sys.exit(bake())
