#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""林带 / 接缝长条贴图的「重复轴端点」修补（2026-11-02）。

实机症状：每条横带的重复轴上，每隔一个贴图宽度就出现一道半透明竖条；
赤金南崖最重（端点 alpha 只有 0.40），青岚南崖 0.72。根因是出图裁切时
长轴两端被羽化过，而 shader 在长轴上 repeat：镜像只能保证取样坐标连续，
挡不住「端点整列只有 40%~70% 不透明度」——每格边界两侧都逼近同一个半透明列。

做两件事：
1. **颜色外扩**：alpha < 0.9 的像素 RGB 换成最近不透明像素的颜色。
   mipmap 对 RGB 和 alpha 是分开平均的，透明区里的浅灰/白 RGB 会在中远景
   把树冠边缘糊出一圈灰白光晕（幽冥南带透明区 RGB≈0.29 灰，实机最明显）。
2. **端点换芯**：从贴图 42% 处取一条 128 texel 的干净窄条，反向放到低端、
   正向放到高端，各自在 128 texel 内与原图交叉淡入。两端最外列因此逐像素
   相同（alpha + RGB），镜像边界处不再出现半透明列，也不会有颜色跳变。
   只动长轴两端，短轴（内缘羽化 / 林线）与原图完全一致。

贴图按宽高自动判重复轴：宽 ≥ 高 → 沿 x；否则沿 y。原图备份在
output/backup_2026-11-02_tiling/。可重复执行（结果幂等）。
"""
from __future__ import annotations

import os
import shutil

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")
BACKUP_DIR = os.path.join(ROOT, "output", "backup_2026-11-02_tiling")

FILES = [
    # 横向（沿 x 重复）
    "lianqi_band_south.png",
    "zhuji_band_seam.png",
    "zhuji_band_north.png",
    "jiedan_band_south.png",
    "jiedan_band_north.png",
    "youming_band_south.png",
    "seam_transition.png",
    "seam_transition_youming_north.png",
    # 竖向（沿 y 重复）
    "lianqi_band_east.png",
    "zhuji_band_east.png",
    "jiedan_band_west.png",
    "seam_transition_west.png",
    "seam_transition_youming_east.png",
]

WRAP_W = 128


def load(name: str) -> np.ndarray:
    return np.asarray(Image.open(os.path.join(TILE_DIR, name)).convert("RGBA"),
                      dtype=np.float32) / 255.0


def save(arr: np.ndarray, name: str) -> None:
    out = (np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(TILE_DIR, name))


def bleed_color(arr: np.ndarray) -> np.ndarray:
    """半透明/全透明像素的 RGB 取最近的不透明像素颜色，alpha 不动。"""
    rgb = arr[:, :, :3]
    a = arr[:, :, 3]
    opaque = a >= 0.90
    if opaque.all():
        return arr
    if not opaque.any():
        return arr
    inds = distance_transform_edt(~opaque, return_distances=False, return_indices=True)
    out = arr.copy()
    need = ~opaque
    out[:, :, :3][need] = rgb[inds[0], inds[1]][need]
    return out


def wrap_ends(arr: np.ndarray) -> np.ndarray:
    """把重复轴两端换成同一条 128 texel 窄条（反向/正向各一次），交叉淡入原图。"""
    h, w = arr.shape[:2]
    along_x = w >= h
    tex = arr if along_x else np.transpose(arr, (1, 0, 2))
    n = tex.shape[1]
    width = min(WRAP_W, n // 4)
    if width < 8:
        return arr
    # 挑一条内容最实、空洞最少的窄条当端点芯：空洞会回来变成半透明竖条。
    # 用 95 分位而不是均值挑列：侧视树带的树梢行本来就半透明，均值会把好列压低。
    lo = int(n * 0.25)
    hi = max(lo + 1, int(n * 0.75) - width)
    best_x, best_score = lo, -1.0
    for x in range(lo, hi, 8):
        col = tex[:, x:x + width, 3]
        score = float(np.percentile(col, 95))
        if score > best_score:
            best_score, best_x = score, x
    x0 = best_x
    donor = tex[:, x0:x0 + width].copy()
    t = np.linspace(0.0, 1.0, width, dtype=np.float32)
    ramp = t * t * (3.0 - 2.0 * t)          # 0 → 1
    w_low = (1.0 - ramp)[None, :, None]     # 1 at x=0 → 0 at x=width-1
    w_high = ramp[None, :, None]            # 0 at x=n-width → 1 at x=n-1

    low = tex[:, :width].copy()
    high = tex[:, n - width:].copy()
    tex[:, :width] = low * (1.0 - w_low) + donor[:, ::-1] * w_low
    tex[:, n - width:] = high * (1.0 - w_high) + donor * w_high

    # 两端最外列逐像素一致：镜像格边界两侧都取这一列
    tex[:, n - 1] = tex[:, 0]
    return tex if along_x else np.transpose(tex, (1, 0, 2))


def edge_alpha(arr: np.ndarray) -> tuple[float, float]:
    """重复轴两端「有内容的像素」的平均不透明度（透明处不参与平均）。"""
    a = arr[:, :, 3]
    if arr.shape[1] >= arr.shape[0]:
        first, last = a[:, 0], a[:, -1]
    else:
        first, last = a[0, :], a[-1, :]
    f = first[first > 0.5]
    l = last[last > 0.5]
    return (float(f.mean()) if f.size else 0.0,
            float(l.mean()) if l.size else 0.0)


def main() -> None:
    os.makedirs(BACKUP_DIR, exist_ok=True)
    for name in FILES:
        path = os.path.join(TILE_DIR, name)
        if not os.path.exists(path):
            print(f"  skip (missing): {name}")
            continue
        backup = os.path.join(BACKUP_DIR, name)
        if not os.path.exists(backup):
            shutil.copy2(path, backup)
        arr = load(name)
        before = edge_alpha(arr)
        arr = bleed_color(arr)
        arr = wrap_ends(arr)
        save(arr, name)
        after = edge_alpha(arr)
        print(f"  {name:36s} edge alpha {before[0]:.2f}/{before[1]:.2f}"
              f" -> {after[0]:.2f}/{after[1]:.2f}")


if __name__ == "__main__":
    main()
