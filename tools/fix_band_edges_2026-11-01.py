#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""林带贴图的三处定向修正（2026-11-01 边界整改）。

1. lianqi_band_east.png：俯视密冠整体偏青（hue≈188°, sat≈0.87），和南侧
   侧视松林的墨绿（hue≈183°, sat≈0.50）并排时像两块不同画风。降饱和、
   往绿偏 12°，压一点亮度，让东南角两侧接得住。
2. jiedan_band_west.png：抠图残留的橄榄绿雾块（g>r 且 alpha<0.9，共 2456
   像素），实机读成半透明绿斑。按绿度把半透明像素拉回暖尘色，保留 alpha。
3. jiedan_band_south.png：崖脚底边 alpha=1，正好压在世界交界线上。烘一段
   带噪声的底边淡出，配合 shader 的 carve 让崖脚化进南侧接缝。

⚠ 不重跑整条出图管线：这些是定向修补，原图与源片保留在 vibe_images 和
output/backup_2026-11-01_boundary/，要回滚直接拷回。
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")
PREVIEW_DIR = os.path.join(ROOT, "output", "preview_seams")


def load(name: str) -> np.ndarray:
    return np.asarray(Image.open(os.path.join(TILE_DIR, name)).convert("RGBA"),
                      dtype=np.float32) / 255.0


def save(arr: np.ndarray, name: str) -> None:
    out = (np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(TILE_DIR, name))
    h, w = arr.shape[:2]
    rgb, a = arr[:, :, :3], arr[:, :, 3]
    bg = np.zeros((h, w, 3), dtype=np.float32)
    bg[:] = np.array([0.08, 0.09, 0.10], dtype=np.float32)
    comp = np.clip(rgb * a[..., None] + bg * (1.0 - a[..., None]), 0.0, 1.0)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    Image.fromarray((comp * 255.0 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(PREVIEW_DIR, name.replace(".png", "_preview.png")))
    print(f"  {name}  alpha {a.min():.2f}..{a.max():.2f}")


def rgb_to_hsv(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    d = mx - mn
    h = np.zeros_like(mx)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    idx = d > 1e-6
    sel = (mx == r) & idx
    h[sel] = ((g[sel] - b[sel]) / d[sel]) % 6.0
    sel = (mx == g) & idx
    h[sel] = (b[sel] - r[sel]) / d[sel] + 2.0
    sel = (mx == b) & idx
    h[sel] = (r[sel] - g[sel]) / d[sel] + 4.0
    h /= 6.0
    s = d / np.maximum(mx, 1e-6)
    return h, s, mx


def hsv_to_rgb(h: np.ndarray, s: np.ndarray, v: np.ndarray) -> np.ndarray:
    i = np.floor(h * 6.0).astype(np.int32) % 6
    f = h * 6.0 - np.floor(h * 6.0)
    p = v * (1.0 - s)
    q = v * (1.0 - s * f)
    t = v * (1.0 - s * (1.0 - f))
    out = np.zeros(h.shape + (3,), dtype=np.float32)
    for k, (rr, gg, bb) in enumerate(((v, t, p), (q, v, p), (p, v, t),
                                      (p, q, v), (t, p, v), (v, p, q))):
        m = i == k
        out[m, 0], out[m, 1], out[m, 2] = rr[m], gg[m], bb[m]
    return out


def fix_lianqi_east() -> None:
    arr = load("lianqi_band_east.png")
    rgb, a = arr[:, :, :3], arr[:, :, 3]
    h, s, v = rgb_to_hsv(rgb)
    h = (h - 0.035) % 1.0
    s = s * 0.68
    v = v * 0.94
    arr[:, :, :3] = hsv_to_rgb(h, s, v)
    save(arr, "lianqi_band_east.png")
    h2, s2, v2 = rgb_to_hsv(arr[:, :, :3])
    m = a > 0.9
    print(f"    opaque hue {np.median(h2[m]) * 360:.0f}°  sat {s2[m].mean():.2f}  "
          f"val {v2[m].mean():.2f}")


def fix_jiedan_west() -> None:
    arr = load("jiedan_band_west.png")
    rgb, a = arr[:, :, :3], arr[:, :, 3]
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    green = np.clip((g - np.maximum(r, b)) / 0.10, 0.0, 1.0) * (a > 0.02)
    lum = 0.30 * r + 0.59 * g + 0.11 * b
    warm = np.stack([lum * 1.22, lum * 1.00, lum * 0.84], axis=2)
    k = (green * 0.9)[..., None]
    arr[:, :, :3] = np.clip(rgb * (1.0 - k) + warm * k, 0.0, 1.0)
    save(arr, "jiedan_band_west.png")
    print(f"    green px fixed: {(green > 0.05).sum()}")


def fix_jiedan_south() -> None:
    arr = load("jiedan_band_south.png")
    h, w = arr.shape[:2]
    a = arr[:, :, 3]
    # 底边淡出：120 texel ≈ 69 世界像素，边缘用长轴噪声推进推出
    rng = np.random.default_rng(20261101)
    raw = rng.random((h, 48)).astype(np.float32)
    prof = gaussian_filter(raw, sigma=(0.0, 5.0), mode="wrap")[:, 0]
    prof = (prof - prof.min()) / max(prof.max() - prof.min(), 1e-5)
    x = np.linspace(0.0, 1.0, w, dtype=np.float32)
    wobble = np.interp(x, np.linspace(0.0, 1.0, len(prof), dtype=np.float32), prof)
    fade = 120.0
    dist = np.arange(h, dtype=np.float32)[:, None]
    t = np.clip((h - 1 - dist - wobble[None, :] * fade * 0.55) / fade, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    a *= t
    a[-1, :] = 0.0
    arr[:, :, 3] = a
    save(arr, "jiedan_band_south.png")
    print(f"    bottom alpha now {a[-1, :].max():.2f}")


def main() -> int:
    print("fix bands:")
    fix_lianqi_east()
    fix_jiedan_west()
    fix_jiedan_south()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
