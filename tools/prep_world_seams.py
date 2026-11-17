#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""苍澜大陆四条地面接缝整形（2026-11-01 边界整改）。

旧版问题（实机截图 24 张盘点）：
  · seam_transition_west.png 左右两列 alpha=1，铺出来后是一条矩形板边；
  · 横向接缝的暗林地→草皮分界近乎一条直线，读成「一条黑边压在草地上」；
  · 接缝色阶是旧 tile 时对齐的，换过地表后颜色对不上；
  · 长轴方向直接平铺，同一段过渡每 878 世界像素重复一次。

本脚本不再用「生成图 + 色阶对齐」，而是直接拿两区**现在在用的**地面 tile
逐像素过渡，因此颜色天然接得上。四条接缝的长轴都做周期性起伏/噪声，短轴
alpha 用带噪声的羽化，边缘不出直线。

尺寸口径与运行时一致（1.75 texel/世界像素）：
  · 横向接缝 1536×735 = 878×420 世界像素，沿 x 周期；
  · 竖向接缝 735×1536，沿 y 周期。
长轴方向 alpha 恒为 1（运行时用 shader 的端部淡出处理板端，不能烘进贴图，
否则每周期一道透明缝）。

用法：
    python tools/prep_world_seams.py
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")
PREVIEW_DIR = os.path.join(ROOT, "output", "preview_seams")

H_W, H_H = 1536, 735      # 横向接缝：宽 × 高
V_W, V_H = 735, 1536      # 竖向接缝


def tile(name: str) -> np.ndarray:
    return np.asarray(Image.open(os.path.join(TILE_DIR, name + ".png")).convert("RGB"),
                      dtype=np.float32) / 255.0


def field(src: np.ndarray, h: int, w: int, phase: tuple[int, int] = (0, 0)) -> np.ndarray:
    th, tw = src.shape[:2]
    yy = (np.arange(h) + phase[0]) % th
    xx = (np.arange(w) + phase[1]) % tw
    return src[np.ix_(yy, xx)]


def smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def periodic(n: int, seed: int) -> np.ndarray:
    """长轴上的周期起伏，返回 [-1, 1]。整数倍频率保证首尾相接。"""
    rng = np.random.default_rng(seed)
    x = np.arange(n, dtype=np.float32) / n * 2.0 * np.pi
    out = np.zeros(n, dtype=np.float32)
    for k in (2, 3, 5, 8, 13):
        out += rng.normal() * np.sin(k * x + rng.uniform(0.0, 2.0 * np.pi)) / k
    out /= max(np.max(np.abs(out)), 1e-5)
    return out


def noise2d(h: int, w: int, seed: int, long_axis: str,
            sigma_long: float, sigma_short: float) -> np.ndarray:
    """长轴 wrap、短轴 nearest 的平滑噪声，归一化到 [0, 1]。"""
    rng = np.random.default_rng(seed)
    raw = rng.random((h, w)).astype(np.float32)
    if long_axis == "x":
        sig = (sigma_short, sigma_long)   # 轴 0 = y（短），轴 1 = x（长）
        mode = ("nearest", "wrap")
    else:
        sig = (sigma_long, sigma_short)
        mode = ("wrap", "nearest")
    n = gaussian_filter(raw, sigma=sig, mode=mode)
    lo, hi = float(n.min()), float(n.max())
    return (n - lo) / max(hi - lo, 1e-5)


def short_u(h: int, w: int, long_axis: str) -> np.ndarray:
    if long_axis == "x":
        return ((np.arange(h, dtype=np.float32) + 0.5) / h)[:, None]
    return ((np.arange(w, dtype=np.float32) + 0.5) / w)[None, :]


def blend_axis(a: np.ndarray, b: np.ndarray, h: int, w: int, long_axis: str,
               center: float, width: float, seed: int, meander: float,
               roughness: float) -> np.ndarray:
    """短轴方向从 a 过渡到 b；边界用三个尺度的周期起伏 + 两层噪声揉开。"""
    u = short_u(h, w, long_axis)
    n_long = w if long_axis == "x" else h
    prof = periodic(n_long, seed) \
        + periodic(n_long, seed + 1) * 0.45 \
        + periodic(n_long, seed + 2) * 0.20
    prof /= max(np.max(np.abs(prof)), 1e-5)
    if long_axis == "x":
        u = u - prof[None, :] * meander
    else:
        u = u - prof[:, None] * meander
    n1 = noise2d(h, w, seed + 3, long_axis, 46.0, 22.0)
    n2 = noise2d(h, w, seed + 4, long_axis, 13.0, 8.0)
    t = smooth((u - center) / width
               + (n1 - 0.5) * roughness
               + (n2 - 0.5) * roughness * 0.55)
    return a * (1.0 - t[..., None]) + b * t[..., None]


def interlock(col: np.ndarray, motif: np.ndarray, h: int, w: int, long_axis: str,
              center: float, seed: int, count: int, amount: float,
              spread: float = 0.085, rmin: float = 0.030, rmax: float = 0.075) -> np.ndarray:
    """把两侧地貌互相咬进对方：不是渐变，而是一块块探出去的舌形。"""
    m = blob_mask(h, w, long_axis, count, seed, center, spread, rmin, rmax, stretch=2.3)
    m = np.clip((m - 0.18) / 0.82, 0.0, 1.0)
    return scatter(col, motif, m, amount)


def blob_mask(h: int, w: int, long_axis: str, count: int, seed: int,
              center: float, spread: float, rmin: float, rmax: float,
              stretch: float = 1.7) -> np.ndarray:
    """长轴 wrap 的椭圆斑点，用作叶屑 / 砾石的散落遮罩。"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    long_coord = xx if long_axis == "x" else yy
    long_len = w if long_axis == "x" else h
    short_len = h if long_axis == "x" else w
    short_coord = yy if long_axis == "x" else xx
    out = np.zeros((h, w), dtype=np.float32)
    for _ in range(count):
        cl = rng.uniform(0.0, float(long_len))
        cs = rng.uniform(center - spread, center + spread) * short_len
        rs = rng.uniform(rmin, rmax) * short_len
        rl = rs * stretch * rng.uniform(0.8, 1.6)
        dl = np.abs(long_coord - cl)
        dl = np.minimum(dl, long_len - dl)
        ds = short_coord - cs
        g = np.exp(-0.5 * ((dl / max(rl, 1e-3)) ** 2 + (ds / max(rs, 1e-3)) ** 2))
        out = np.maximum(out, g)
    return np.clip(out, 0.0, 1.0)


def scatter(col: np.ndarray, motif: np.ndarray, mask: np.ndarray, amount: float) -> np.ndarray:
    m = (mask * amount)[..., None]
    return col * (1.0 - m) + motif * m


def edge_alpha(h: int, w: int, long_axis: str, fade_low: float, fade_high: float,
               seed: int) -> np.ndarray:
    """短轴两侧淡出；缺口宽度带长轴周期噪声，边缘不会是一条直线。"""
    u = short_u(h, w, long_axis)
    n_long = w if long_axis == "x" else h
    prof = periodic(n_long, seed) * 0.5 + 0.5
    wobble = 0.35
    if long_axis == "x":
        prof = prof[None, :]
    else:
        prof = prof[:, None]
    low = smooth((u - fade_low * wobble * prof) / max(fade_low, 1e-4))
    high = smooth(((1.0 - u) - fade_high * wobble * prof) / max(fade_high, 1e-4))
    a = low * high
    if long_axis == "x":
        a[0, :] = 0.0
        a[-1, :] = 0.0
    else:
        a[:, 0] = 0.0
        a[:, -1] = 0.0
    return a


def save(rgb: np.ndarray, alpha: np.ndarray, name: str) -> None:
    h, w = rgb.shape[:2]
    out = (np.dstack([np.clip(rgb, 0.0, 1.0), alpha]) * 255.0 + 0.5).astype(np.uint8)
    path = os.path.join(TILE_DIR, name)
    Image.fromarray(out, "RGBA").save(path)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    # 预览铺在亮青底上，方便看暗部 alpha
    bg = np.zeros((h, w, 3), dtype=np.float32)
    bg[:] = np.array([0.10, 0.12, 0.13], dtype=np.float32)
    comp = np.clip(rgb * alpha[..., None] + bg * (1.0 - alpha[..., None]), 0.0, 1.0)
    Image.fromarray((comp * 255.0 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(PREVIEW_DIR, name.replace(".png", "_preview.png")))
    print(f"  {name}  {w}x{h}  alpha {alpha.min():.2f}..{alpha.max():.2f}")


def horizontal_seam(name: str, top_tile: str, bottom_tile: str, litter_tile: str,
                    center: float, width: float, meander: float, roughness: float,
                    litter_center: float, litter_spread: float,
                    litter_amount: float, contact: bool,
                    seed: int) -> None:
    h, w = H_H, H_W
    top = field(tile(top_tile), h, w)
    bottom = field(tile(bottom_tile), h, w)
    litter = field(tile(litter_tile), h, w, (31, 57))
    # 先做出「上区地貌 → 下区地貌」的蜿蜒过渡
    col = blend_axis(top, bottom, h, w, "x", center, width, seed, meander, roughness)
    # 两侧互相咬进对方：草地里探出几块暗地被，地被里也钻出草舌
    col = interlock(col, top, h, w, "x", center, seed + 21, 22, 0.65, 0.11, 0.035, 0.10)
    col = interlock(col, bottom, h, w, "x", center, seed + 22, 20, 0.60, 0.11, 0.035, 0.10)
    # 大块舌形：制造几处明显的海湾，避免整条边读成一条水平线
    col = interlock(col, top, h, w, "x", center, seed + 31, 7, 0.45, 0.14, 0.055, 0.13)
    col = interlock(col, bottom, h, w, "x", center, seed + 32, 6, 0.40, 0.14, 0.055, 0.13)
    # 交界处压一条叶屑/砾石带：宽度随长轴噪声变化，不是直线
    u = short_u(h, w, "x")
    n = noise2d(h, w, seed + 5, "x", 30.0, 14.0)
    rim = np.exp(-0.5 * ((u - center - (n - 0.5) * 0.08) / 0.042) ** 2)
    rim *= np.clip(0.45 + n * 0.8, 0.0, 1.0)
    col = scatter(col, litter, rim, 0.42)
    # 草地里散落的叶屑、地被侧长出的草簇
    litter_blobs = blob_mask(h, w, "x", 30, seed + 7,
                             litter_center, litter_spread, 0.020, 0.055)
    col = scatter(col, litter, litter_blobs, litter_amount)
    grass = field(tile(bottom_tile), h, w, (73, 11))
    tufts = blob_mask(h, w, "x", 18, seed + 9, center - 0.08, 0.05, 0.012, 0.030)
    col = scatter(col, grass, tufts, 0.45)
    if contact:
        # 崖脚接触阴影：只压在世界交界线以下、接缝过渡结束前
        rows = np.arange(h, dtype=np.float32) / h
        shade = 0.70 + 0.30 * np.clip((rows - 0.33) / 0.19, 0.0, 1.0)
        shade = shade[:, None] * (0.94 + n * 0.12)
        col *= shade[..., None]
    alpha = edge_alpha(h, w, "x", 0.03, 0.10, seed + 11)
    save(col, alpha, name)


def vertical_seam(name: str, left_tile: str, right_tile: str, litter_left: str,
                  litter_right: str, center: float, width: float,
                  meander: float, roughness: float, seed: int) -> None:
    h, w = V_H, V_W
    left = field(tile(left_tile), h, w)
    right = field(tile(right_tile), h, w)
    col = blend_axis(left, right, h, w, "y", center, width, seed, meander, roughness)
    col = interlock(col, left, h, w, "y", center, seed + 21, 14, 0.45)
    col = interlock(col, right, h, w, "y", center, seed + 22, 14, 0.45)
    col = interlock(col, left, h, w, "y", center, seed + 31, 6, 0.40, 0.13, 0.050, 0.12)
    col = interlock(col, right, h, w, "y", center, seed + 32, 6, 0.40, 0.13, 0.050, 0.12)
    # 两侧各撒一层本区地被碎屑，交界处再压一层碎石
    lf = field(tile(litter_left), h, w, (17, 43))
    rf = field(tile(litter_right), h, w, (61, 23))
    u = short_u(h, w, "y")
    n = noise2d(h, w, seed + 3, "y", 34.0, 16.0)
    rim = np.exp(-0.5 * ((u - center - (n - 0.5) * 0.06) / 0.040) ** 2)
    rim *= np.clip(0.4 + n * 0.9, 0.0, 1.0)
    col = scatter(col, lf, rim, 0.40)
    col = scatter(col, rf, rim, 0.30)
    bl = blob_mask(h, w, "y", 22, seed + 6, center - 0.10, 0.08, 0.018, 0.045)
    br = blob_mask(h, w, "y", 22, seed + 8, center + 0.10, 0.08, 0.018, 0.045)
    col = scatter(col, lf, bl, 0.32)
    col = scatter(col, rf, br, 0.32)
    alpha = edge_alpha(h, w, "y", 0.09, 0.09, seed + 12)
    save(col, alpha, name)


def main() -> int:
    # 练气 ↔ 筑基：云隐暗林地 → 青岚草
    horizontal_seam("seam_transition.png",
                    "zhuji_forestfloor", "lianqi_grass", "lianqi_forestfloor",
                    center=0.44, width=0.09, meander=0.14, roughness=0.60,
                    litter_center=0.56, litter_spread=0.18, litter_amount=0.50,
                    contact=False, seed=20261101)
    # 结丹 ↔ 幽冥：丹霞红土 → 灵墟冷土；崖脚压接触阴影
    horizontal_seam("seam_transition_youming_north.png",
                    "jiedan_grass", "youming_grass", "jiedan_forestfloor",
                    center=0.45, width=0.075, meander=0.12, roughness=0.60,
                    litter_center=0.38, litter_spread=0.08, litter_amount=0.55,
                    contact=True, seed=20261102)
    # 结丹 ↔ 筑基：丹霞 → 云隐冷绿
    vertical_seam("seam_transition_west.png",
                  "jiedan_grass", "zhuji_grass", "jiedan_forestfloor", "zhuji_forestfloor",
                  center=0.50, width=0.13, meander=0.10, roughness=0.55, seed=20261103)
    # 幽冥 ↔ 练气：灵墟冷土 → 青岚草
    vertical_seam("seam_transition_youming_east.png",
                  "youming_grass", "lianqi_grass", "youming_forestfloor", "lianqi_forestfloor",
                  center=0.50, width=0.13, meander=0.10, roughness=0.55, seed=20261104)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
