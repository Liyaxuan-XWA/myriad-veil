#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""赤金丹霞区域总览图（世界区域面板背景）。

和云隐谷同一套：遮罩 + 三套 tile 按 1/8 重算，再把西 / 北 / 南三条崖壁带
按实机密度压上去；东沿没有崖壁，铺一条沿 y 重复的竖向接缝（丹霞红 → 云隐冷绿）。
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_region_minimap as M  # noqa: E402

ROOT = M.ROOT
TILE_DIR = M.TILE_DIR
OUT_PNG = os.path.join(ROOT, "assets", "ui", "facilities", "world_map_jiedan.png")
SCALE = M.SCALE


def _band_tile(path: str, size: tuple[int, int]) -> Image.Image:
    return Image.open(path).convert("RGBA").resize(size, Image.LANCZOS)


def bake() -> int:
    mask = M._load(os.path.join(TILE_DIR, "jiedan_mask.png"))
    h, w = mask.shape[:2]
    t = mask[:, :, :3] / np.maximum(mask[:, :, :3].sum(axis=2, keepdims=True), 1e-4)

    # 总览用调色板而不是直接缩 tile：896→64 的降采样会把丹霞的水平岩层抽成
    # 一条条横纹（实测首版整张图像百叶窗）。色相从真实 tile 的均值取，只保留
    # 「草 / 路 / 焦土」三块可分，细节交给实机地形。
    def _mean_tile(name: str) -> np.ndarray:
        a = M._load(os.path.join(TILE_DIR, name))[:, :, :3]
        return a.reshape(-1, 3).mean(axis=0)

    grass_c = _mean_tile("jiedan_grass.png")
    road_c = _mean_tile("jiedan_road.png")
    forest_c = _mean_tile("jiedan_forestfloor.png")
    col = grass_c * t[:, :, 0:1] + road_c * t[:, :, 1:2] + forest_c * t[:, :, 2:3]
    decal = mask[:, :, 3:]
    col = col * (1.0 - 0.10 * decal)
    # 一点点低频纹理，避免整张图像色块；用重度模糊的草地亮度，不会带回条纹
    from PIL import ImageFilter
    tex_img = Image.open(os.path.join(TILE_DIR, "jiedan_grass.png")).convert("L")
    tex_img = tex_img.filter(ImageFilter.GaussianBlur(12)).resize((w, h), Image.LANCZOS)
    tex = np.asarray(tex_img, dtype=np.float32) / 255.0
    col = col * (0.93 + 0.14 * tex[:, :, None])
    base = Image.fromarray((np.clip(col, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)).convert("RGBA")

    def layer() -> Image.Image:
        return Image.new("RGBA", (w, h), (0, 0, 0, 0))

    # 北带：沿 x 重复，贴顶边
    n = Image.open(os.path.join(TILE_DIR, "jiedan_band_north.png")).convert("RGBA")
    n_cell = int(round(n.width / SCALE))
    n_depth = int(round(n.height / M.BAND_DENSITY / SCALE))
    n_tile = _band_tile(os.path.join(TILE_DIR, "jiedan_band_north.png"), (n_cell, n_depth))
    n_layer = layer()
    for x in range(0, w, n_cell):
        n_layer.paste(n_tile, (x, 0))
    base = Image.alpha_composite(base, n_layer)

    # 南带：沿 x 重复，贴底边
    s = Image.open(os.path.join(TILE_DIR, "jiedan_band_south.png")).convert("RGBA")
    s_cell = int(round(s.width / SCALE))
    s_depth = int(round(s.height / M.BAND_DENSITY / SCALE))
    s_tile = _band_tile(os.path.join(TILE_DIR, "jiedan_band_south.png"), (s_cell, s_depth))
    s_layer = layer()
    for x in range(0, w, s_cell):
        s_layer.paste(s_tile, (x, h - s_depth))
    base = Image.alpha_composite(base, s_layer)

    # 西带：沿 y 重复，贴左边
    we = Image.open(os.path.join(TILE_DIR, "jiedan_band_west.png")).convert("RGBA")
    w_depth = int(round(we.width / M.BAND_DENSITY / SCALE))
    w_cell = int(round(we.height / SCALE))
    w_tile = _band_tile(os.path.join(TILE_DIR, "jiedan_band_west.png"), (w_depth, w_cell))
    w_layer = layer()
    for y in range(0, h, w_cell):
        w_layer.paste(w_tile, (0, y))
    base = Image.alpha_composite(base, w_layer)

    # 东侧竖向接缝：沿 y 重复，圆心压在东边界上
    v = Image.open(os.path.join(TILE_DIR, "seam_transition_west.png")).convert("RGBA")
    v_depth = int(round(v.width / M.BAND_DENSITY / SCALE))
    v_cell = int(round(v.height / SCALE))
    v_tile = _band_tile(os.path.join(TILE_DIR, "seam_transition_west.png"), (v_depth, v_cell))
    v_layer = layer()
    for y in range(0, h, v_cell):
        v_layer.paste(v_tile, (w - v_depth // 2, y))
    base = Image.alpha_composite(base, v_layer)

    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    base.convert("RGB").save(OUT_PNG)
    rgb = np.asarray(base.convert("RGB"), dtype=np.float32) / 255.0
    lum = rgb.mean(axis=2)
    print(f"{os.path.relpath(OUT_PNG, ROOT)}  {w}x{h}  亮度均值 {lum.mean():.3f}  p05/p95 "
          f"{np.percentile(lum, 5):.3f}/{np.percentile(lum, 95):.3f}")
    print(f"   北带深 {n_depth}  南带深 {s_depth}  西带深 {w_depth}  接缝深 {v_depth}")
    return 0


if __name__ == "__main__":
    sys.exit(bake())
