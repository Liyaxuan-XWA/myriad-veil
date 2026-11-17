#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""幽冥灵墟区域总览图（世界区域面板背景）。

和赤金丹霞同一套：遮罩 + 三套 tile 按 1/8 重算，再把西 / 南两条外沿带按实机
密度压上去；北接丹霞、东邻青岚，两条接缝也按实机位置各铺一条。
区域中心压一枚灵墟山门剪影 + 青色幽火晕，让总览一眼认出这座地标。
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
OUT_PNG = os.path.join(ROOT, "assets", "ui", "facilities", "world_map_youming.png")
SCALE = M.SCALE


def _band_tile(path: str, size: tuple[int, int]) -> Image.Image:
    return Image.open(path).convert("RGBA").resize(size, Image.LANCZOS)


def _glow(size: int, color: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2.0
    for i in range(18, 0, -1):
        r = c * i / 18.0
        a = int(5 + 26 * (1.0 - i / 18.0) ** 2)
        d.ellipse((c - r, c - r, c + r, c + r), fill=(*color, a))
    return img.filter(ImageFilter.GaussianBlur(7))


def bake() -> int:
    mask = M._load(os.path.join(TILE_DIR, "youming_mask.png"))
    h, w = mask.shape[:2]
    t = mask[:, :, :3] / np.maximum(mask[:, :, :3].sum(axis=2, keepdims=True), 1e-4)

    # 总览用调色板而不是直接缩 tile：896→64 的降采样会把碎石的细节抽成噪点，
    # 色相从真实 tile 的均值取，只保留「草 / 路 / 墟土」三块可分。
    def _mean_tile(name: str) -> np.ndarray:
        a = M._load(os.path.join(TILE_DIR, name))[:, :, :3]
        return a.reshape(-1, 3).mean(axis=0)

    grass_c = _mean_tile("youming_grass.png")
    road_c = _mean_tile("youming_road.png")
    forest_c = _mean_tile("youming_forestfloor.png")
    col = grass_c * t[:, :, 0:1] + road_c * t[:, :, 1:2] + forest_c * t[:, :, 2:3]
    decal = mask[:, :, 3:]
    col = col * (1.0 - 0.10 * decal)
    # 一点点低频纹理，避免整张图像色块；用重度模糊的草地亮度，不会带回碎石噪点
    from PIL import ImageFilter as _F
    tex_img = Image.open(os.path.join(TILE_DIR, "youming_grass.png")).convert("L")
    tex_img = tex_img.filter(_F.GaussianBlur(12)).resize((w, h), Image.LANCZOS)
    tex = np.asarray(tex_img, dtype=np.float32) / 255.0
    col = col * (0.90 + 0.18 * tex[:, :, None])
    base = Image.fromarray((np.clip(col, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)).convert("RGBA")

    def layer() -> Image.Image:
        return Image.new("RGBA", (w, h), (0, 0, 0, 0))

    # 南带：沿 x 重复，贴底边
    s = Image.open(os.path.join(TILE_DIR, "youming_band_south.png")).convert("RGBA")
    s_cell = int(round(s.width / SCALE))
    s_depth = int(round(s.height / M.BAND_DENSITY / SCALE))
    s_tile = _band_tile(os.path.join(TILE_DIR, "youming_band_south.png"), (s_cell, s_depth))
    s_layer = layer()
    for x in range(0, w, s_cell):
        s_layer.paste(s_tile, (x, h - s_depth))
    base = Image.alpha_composite(base, s_layer)

    # 西带：沿 y 重复，贴左边
    we = Image.open(os.path.join(TILE_DIR, "youming_band_west.png")).convert("RGBA")
    w_depth = int(round(we.width / M.BAND_DENSITY / SCALE))
    w_cell = int(round(we.height / SCALE))
    w_tile = _band_tile(os.path.join(TILE_DIR, "youming_band_west.png"), (w_depth, w_cell))
    w_layer = layer()
    for y in range(0, h, w_cell):
        w_layer.paste(w_tile, (0, y))
    base = Image.alpha_composite(base, w_layer)

    # 北侧横向接缝（丹霞 → 幽冥）：沿 x 重复，圆心压在北边界上
    n = Image.open(os.path.join(TILE_DIR, "seam_transition_youming_north.png")).convert("RGBA")
    n_depth = int(round(n.height / M.BAND_DENSITY / SCALE))
    n_cell = int(round(n.width / SCALE))
    n_tile = _band_tile(os.path.join(TILE_DIR, "seam_transition_youming_north.png"),
                        (n_cell, n_depth))
    n_layer = layer()
    for x in range(0, w, n_cell):
        n_layer.paste(n_tile, (x, -n_depth // 2))
    base = Image.alpha_composite(base, n_layer)

    # 东侧竖向接缝（幽冥 → 青岚）：沿 y 重复，圆心压在东边界上
    v = Image.open(os.path.join(TILE_DIR, "seam_transition_youming_east.png")).convert("RGBA")
    v_depth = int(round(v.width / M.BAND_DENSITY / SCALE))
    v_cell = int(round(v.height / SCALE))
    v_tile = _band_tile(os.path.join(TILE_DIR, "seam_transition_youming_east.png"),
                        (v_depth, v_cell))
    v_layer = layer()
    for y in range(0, h, v_cell):
        v_layer.paste(v_tile, (w - v_depth // 2, y))
    base = Image.alpha_composite(base, v_layer)

    # 区域中心的灵墟山门：剪影 + 幽火晕
    gate = Image.open(os.path.join(ROOT, "assets", "scenes", "youming_gate.png")).convert("RGBA")
    gh = 84
    gw = max(1, round(gate.width * gh / gate.height))
    gate = gate.resize((gw, gh), Image.LANCZOS)
    glow = _glow(int(gh * 1.6), (70, 214, 210))
    cx, cy = w // 2, h // 2
    base.alpha_composite(glow, (cx - glow.width // 2, cy - glow.height // 2))
    base.alpha_composite(gate, (cx - gw // 2, cy - gh // 2 + 8))

    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    base.convert("RGB").save(OUT_PNG)
    rgb = np.asarray(base.convert("RGB"), dtype=np.float32) / 255.0
    lum = rgb.mean(axis=2)
    print(f"{os.path.relpath(OUT_PNG, ROOT)}  {w}x{h}  亮度均值 {lum.mean():.3f}  p05/p95 "
          f"{np.percentile(lum, 5):.3f}/{np.percentile(lum, 95):.3f}")
    print(f"   南带深 {s_depth}  西带深 {w_depth}  北接缝深 {n_depth}  东接缝深 {v_depth}")
    return 0


if __name__ == "__main__":
    sys.exit(bake())
