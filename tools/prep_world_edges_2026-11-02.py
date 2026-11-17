#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""苍澜大陆外缘林带 / 接缝地垫的俯视整形（2026-11-02 边界整改第二轮）。

上一轮的外缘用的是侧视崖壁 / 侧视树线：放在俯视地图的边上会读成一堵竖墙，
jiedan_band_south 还整条压在丹霞↔幽冥的可行走接缝上。这一轮全部换成
**俯视**素材，并按边烘成四向变体：

  · jiedan_edge       → 赤金丹霞北（翻上）/ 西（左转）
  · youming_edge      → 幽冥灵墟南（原向）/ 西（左转）
  · seam_grass_forest → 青岚野南（原向）/ 东（左转）
  · forest_fringe     → 云隐谷北（原向）/ 东（左转），品红键出林下灌丛

每条带子的内缘（朝活动区的一侧）按该区 tile 的平均色做渐变对色，外缘烘
带噪声的 alpha 淡出 + 压暗，让崖脚 / 林缘化进地图外沿，不再出现直边。

四条接缝地垫（横向 1536×735、竖向 735×1536）四边都做噪声羽化，
两侧分别对到相邻区域的 tile 平均色；由 secret_world 以 z=3 铺在林带之上。

用法：
    python tools/prep_world_edges_2026-11-02.py
    python tools/prep_world_edges_2026-11-02.py --check
"""
from __future__ import annotations

import argparse
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "vibe_images")
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")
PREVIEW = os.path.join(ROOT, "output", "preview_seams")

BAND_H = (1536, 818)
BAND_V = (818, 1536)
SEAM_H = (1536, 735)
SEAM_V = (735, 1536)
CORNER = (1536, 1536)

JIEDAN = os.path.join(SRC, "jiedan_edge_src_1793471746530_cde62f00.png")
YOUMING = os.path.join(SRC, "youming_edge_src_1793471777972_bf2bd021.png")
FOREST_CANOPY = os.path.join(SRC, "forest_canopy_edge_src_1793472704268_8bc3143d.png")


def _load(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def _tile_mean(name: str) -> np.ndarray:
    arr = _load(os.path.join(TILE_DIR, name))
    return arr.mean(axis=(0, 1))


def _smooth_noise(n: int, seed: int, sigma: float = 5.0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    raw = rng.random(n).astype(np.float32)
    im = Image.fromarray((raw * 255.0 + 0.5).astype(np.uint8).reshape(1, n), "L")
    im = im.filter(ImageFilter.GaussianBlur(sigma))
    prof = np.asarray(im, dtype=np.float32)[0] / 255.0
    return (prof - prof.min()) / max(prof.max() - prof.min(), 1e-5)


def _resize(rgb: np.ndarray, alpha: np.ndarray, size: tuple[int, int]):
    tw, th = size
    out = np.zeros((th, tw, 4), dtype=np.float32)
    pm = alpha.min() < 0.999
    src_rgb = rgb * alpha[..., None] if pm else rgb
    for ch in range(3):
        im = Image.fromarray((np.clip(src_rgb[:, :, ch], 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8))
        out[:, :, ch] = np.asarray(im.resize((tw, th), Image.LANCZOS), dtype=np.float32) / 255.0
    a = Image.fromarray((np.clip(alpha, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8))
    out[:, :, 3] = np.asarray(a.resize((tw, th), Image.LANCZOS), dtype=np.float32) / 255.0
    if pm:
        out[:, :, :3] /= np.maximum(out[:, :, 3], 0.02)[..., None]
    return np.clip(out[:, :, :3], 0.0, 1.0), np.clip(out[:, :, 3], 0.0, 1.0)


def _key_magenta(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mag = np.minimum(r - g, b - g)
    t = np.clip((mag - 0.015) / 0.075, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    alpha = 1.0 - t
    # 键色取四角中位数；只在半透明像素上反合成，去紫边。
    corners = np.concatenate([rgb[0:8, 0:8].reshape(-1, 3), rgb[0:8, -8:].reshape(-1, 3)])
    key = np.median(corners, axis=0)
    c = np.clip(alpha, 0.0, 1.0)[:, :, None]
    fg = (rgb - key[None, None, :] * (1.0 - c)) / np.maximum(c, 0.08)
    rgb = np.where(c > 0.0, np.clip(fg, 0.0, 1.0), rgb)
    return rgb, alpha


def _crop_rows(rgb: np.ndarray, alpha: np.ndarray, y0: int, y1: int):
    return rgb[y0:y1], alpha[y0:y1]


def _match_side(rgb: np.ndarray, target: np.ndarray, side: str, reach: float = 0.62,
                iterations: int = 2) -> np.ndarray:
    """把贴图某一侧靠边 12% 的平均色对到 target，往内 reach 距离内渐变回原色。"""
    h, w = rgb.shape[:2]
    axis = 0 if side in ("top", "bottom") else 1
    n = h if axis == 0 else w
    k = max(8, int(n * 0.22))
    s = np.linspace(0.0, 1.0, n, dtype=np.float32)
    if side in ("bottom", "right"):
        s = 1.0 - s
    # s=0 是目标侧，s=1 是另一侧
    wgt = np.clip(1.0 - s / max(reach, 1e-3), 0.0, 1.0)
    wgt = wgt * wgt * (3.0 - 2.0 * wgt)
    out = rgb.copy()
    for _ in range(iterations):
        cur = out[:k].mean(axis=(0, 1)) if side == "top" else \
            out[-k:].mean(axis=(0, 1)) if side == "bottom" else \
            out[:, :k].mean(axis=(0, 1)) if side == "left" else \
            out[:, -k:].mean(axis=(0, 1))
        gain = np.clip(target / np.maximum(cur, 1e-4), 0.30, 2.2)
        if axis == 0:
            out *= (1.0 + (gain[None, :] - 1.0) * wgt[:, None])[:, None, :]
        else:
            out *= (1.0 + (gain[None, :] - 1.0) * wgt[:, None])[None, :, :]
    return np.clip(out, 0.0, 1.0)


def _outer_fade(rgba: np.ndarray, side: str, frac: float = 0.26,
                darken: float = 0.62, seed: int = 7) -> np.ndarray:
    """外缘：带噪声的 alpha 淡出 + 同步压暗，避免半透明亮边发灰。"""
    out = rgba.copy()
    h, w = out.shape[:2]
    axis = 0 if side in ("top", "bottom") else 1
    n = h if axis == 0 else w
    long_n = w if axis == 0 else h
    fade = max(24, int(n * frac))
    prof = _smooth_noise(max(long_n // 6, 64), seed)
    x = np.linspace(0.0, 1.0, long_n, dtype=np.float32)
    wobble = np.interp(x, np.linspace(0.0, 1.0, len(prof), dtype=np.float32), prof)
    dist = np.arange(n, dtype=np.float32)
    if side in ("bottom", "right"):
        dist = dist[::-1]
    t = np.clip((dist[:, None] - wobble[None, :] * fade * 0.55) / fade, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    dark = np.clip(dist[:, None] / (fade * 1.6), 0.0, 1.0)
    dark = dark * dark * (3.0 - 2.0 * dark)
    fac = darken + (1.0 - darken) * dark
    if axis == 0:
        out[:, :, 3] *= t
        out[:, :, :3] *= fac[:, :, None]
    else:
        out[:, :, 3] *= t.T
        out[:, :, :3] *= fac.T[:, :, None]
    return out


def _tile_window(tile: np.ndarray, w: int, h: int, rot: int, seed: int) -> np.ndarray:
    """从可平铺地面图里取一段任意窗口（循环裁剪，两端天然对齐）。rot 为 90° 步数。"""
    if rot:
        tile = np.rot90(tile, rot)
    rng = np.random.default_rng(seed)
    oy = int(rng.integers(0, tile.shape[0]))
    ox = int(rng.integers(0, tile.shape[1]))
    reps_y = int(np.ceil((h + oy) / tile.shape[0]))
    reps_x = int(np.ceil((w + ox) / tile.shape[1]))
    big = np.tile(tile, (reps_y, reps_x, 1))
    return big[oy:oy + h, ox:ox + w]


def _tile_blend(path: str, w: int, h: int, seed: int) -> np.ndarray:
    """同一张 tile 取三种朝向的窗口按噪声权重混合。
    单取一张窗口时，一片叶簇会以 tile 周期（512 世界像素）原样重排，接缝条上
    一眼能数出来；换朝向后同一片叶子不再同向出现，读感接近实地面。"""
    tile = _load(path)
    layers = [_tile_window(tile, w, h, rot, seed + i * 13) for i, rot in enumerate((0, 1, 2))]
    wts = []
    for i in range(3):
        n = _noise_field(h, w, 5, seed + 100 + i * 17)
        wts.append(np.power(np.clip(n, 0.02, 0.98), 3.0))
    total = wts[0] + wts[1] + wts[2]
    out = np.zeros((h, w, 3), dtype=np.float32)
    for i in range(3):
        out += layers[i] * (wts[i] / total)[..., None]
    return np.clip(out, 0.0, 1.0)


def _noise_field(h: int, w: int, cells: int, seed: int) -> np.ndarray:
    """低频有机噪声场（0..1）：先取 cells 级小随机图再放大高斯平滑，边界不直。"""
    rng = np.random.default_rng(seed)
    ch = max(4, h // max(cells, 1))
    cw = max(4, w // max(cells, 1))
    small = (rng.random((ch, cw)) * 255.0 + 0.5).astype(np.uint8)
    im = Image.fromarray(small, "L").resize((w, h), Image.BICUBIC)
    im = im.filter(ImageFilter.GaussianBlur(max(h, w) / 48.0))
    prof = np.asarray(im, dtype=np.float32) / 255.0
    return (prof - prof.min()) / max(prof.max() - prof.min(), 1e-5)


def _depth_feather(rgba: np.ndarray, axis: int, px: int, seed: int = 11) -> np.ndarray:
    """只羽化短轴两端。长轴是平铺方向，烘端部淡出会变成每周期一条透明缝。"""
    out = rgba.copy()
    n = out.shape[axis]
    long_n = out.shape[1] if axis == 0 else out.shape[0]
    prof = _smooth_noise(max(long_n // 6, 64), seed + 4)
    x = np.linspace(0.0, 1.0, long_n, dtype=np.float32)
    wobble = np.interp(x, np.linspace(0.0, 1.0, len(prof), dtype=np.float32), prof)
    dist = np.arange(n, dtype=np.float32)
    t = np.clip((dist[:, None] - wobble[None, :] * px * 0.5) / px, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    t2 = np.clip(((n - 1 - dist)[:, None] - wobble[None, :] * px * 0.5) / px, 0.0, 1.0)
    t2 = t2 * t2 * (3.0 - 2.0 * t2)
    k = np.minimum(t, t2)
    out[:, :, 3] *= k if axis == 0 else k.T
    return out


def _save(rgba: np.ndarray, name: str) -> None:
    arr = np.clip(rgba, 0.0, 1.0)
    out = (arr * 255.0 + 0.5).astype(np.uint8)
    os.makedirs(TILE_DIR, exist_ok=True)
    Image.fromarray(out, "RGBA").save(os.path.join(TILE_DIR, name))
    h, w = out.shape[:2]
    bg = np.zeros((h, w, 3), dtype=np.float32)
    bg[:] = np.array([0.07, 0.08, 0.09], dtype=np.float32)
    a = arr[:, :, 3]
    comp = np.clip(arr[:, :, :3] * a[..., None] + bg * (1.0 - a[..., None]), 0.0, 1.0)
    os.makedirs(PREVIEW, exist_ok=True)
    Image.fromarray((comp * 255.0 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(PREVIEW, name.replace(".png", "_preview.png")))
    lum = (0.3 * arr[:, :, 0] + 0.59 * arr[:, :, 1] + 0.11 * arr[:, :, 2])[a > 0.5]
    print(f"  {name:36s} {w}x{h}  alpha {a.min():.2f}..{a.max():.2f}  "
          f"lam {lum.mean():.3f}")


def _grade(rgb: np.ndarray, mul: float = 1.0, desat: float = 0.0,
           tint: tuple[float, float, float] = (1.0, 1.0, 1.0)) -> np.ndarray:
    lum = (0.3 * rgb[:, :, 0] + 0.59 * rgb[:, :, 1] + 0.11 * rgb[:, :, 2])[:, :, None]
    rgb = lum + (rgb - lum) * (1.0 - desat)
    rgb = rgb * mul * np.array(tint, dtype=np.float32)[None, None, :]
    return np.clip(rgb, 0.0, 1.0)


def _inner_feather(rgba: np.ndarray, side: str, frac: float = 0.26,
                   seed: int = 31) -> np.ndarray:
    """内缘：alpha 从 0 渐入，让林带/崖带化进活动区地面，不留下一条直边。"""
    out = rgba.copy()
    h, w = out.shape[:2]
    axis = 0 if side in ("top", "bottom") else 1
    n = h if axis == 0 else w
    long_n = w if axis == 0 else h
    fade = max(24, int(n * frac))
    prof = _smooth_noise(max(long_n // 6, 64), seed)
    x = np.linspace(0.0, 1.0, long_n, dtype=np.float32)
    wobble = np.interp(x, np.linspace(0.0, 1.0, len(prof), dtype=np.float32), prof)
    dist = np.arange(n, dtype=np.float32)
    if side in ("bottom", "right"):
        dist = dist[::-1]
    t = np.clip((dist[:, None] - wobble[None, :] * fade * 0.5) / fade, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    if axis == 0:
        out[:, :, 3] *= t
    else:
        out[:, :, 3] *= t.T
    return out


def _soften_band_transition(rgb: np.ndarray, side: str, frac: float = 0.55,
                            sigma: float = 80.0,
                            strength: float = 0.95) -> np.ndarray:
    """林带内缘草地与外缘树冠之间做宽幅混色：跨过整条带来渐变，避免树冠边界
    在羽化区末端突然起一堵墙。只在中段替换为强模糊，近内缘保留地面细节。"""
    from scipy.ndimage import gaussian_filter1d

    axis = 0 if side in ("top", "bottom") else 1
    n = rgb.shape[axis]
    d = np.abs(np.arange(n, dtype=np.float32) - (n - 1) * 0.5) / max(n * frac, 1.0)
    wgt = np.clip(1.0 - d, 0.0, 1.0)
    wgt = (wgt * wgt * (3.0 - 2.0 * wgt)) * strength
    blur = gaussian_filter1d(rgb, sigma, axis=axis, mode="nearest")
    if axis == 0:
        rgb = rgb * (1.0 - wgt[:, None, None]) + blur * wgt[:, None, None]
    else:
        rgb = rgb * (1.0 - wgt[None, :, None]) + blur * wgt[None, :, None]
    return np.clip(rgb, 0.0, 1.0)


def build_band(src_path: str, y0: int, y1: int, target_size: tuple[int, int],
               keyed: bool, inner_target: np.ndarray, inner_side: str,
               outer_side: str, name: str, flip: bool = False,
               rotate_cw: bool = False, rotate_ccw: bool = False,
               darken: float = 0.62, mul: float = 1.0,
               desat: float = 0.0,
               tint: tuple[float, float, float] = (1.0, 1.0, 1.0)) -> None:
    rgb = _load(src_path)
    alpha = np.ones(rgb.shape[:2], dtype=np.float32)
    if keyed:
        rgb, alpha = _key_magenta(rgb)
    rgb = _grade(rgb, mul, desat, tint)
    rgb, alpha = _crop_rows(rgb, alpha, y0, y1)
    if flip:
        rgb, alpha = rgb[::-1], alpha[::-1]
    if rotate_cw:
        rgb, alpha = np.rot90(rgb, -1), np.rot90(alpha, -1)
    if rotate_ccw:
        rgb, alpha = np.rot90(rgb, 1), np.rot90(alpha, 1)
    rgb, alpha = _resize(rgb, alpha, target_size)
    rgb = _match_side(rgb, inner_target, inner_side, reach=0.6)
    rgb = _soften_band_transition(rgb, inner_side, frac=0.20, sigma=16.0, strength=0.70)
    rgba = np.dstack([rgb, alpha])
    rgba = _inner_feather(rgba, inner_side, frac=0.32, seed=31)
    rgba = _outer_fade(rgba, outer_side, frac=0.26, darken=darken, seed=17)
    _save(rgba, name)


def build_seam_tiles(low_path: str, high_path: str, name: str,
                     vertical: bool = False, seed: int = 41,
                     wobble: float = 0.18, soft: float = 0.16) -> None:
    """接缝地垫：把两侧**真实地面 tile** 按原生密度直接缝在一起，边界用低频噪声
    推成舌形。不用照片压糊 —— 糊条铺在原生密度的地面上永远读成一层雾。
    low = 低坐标一侧（横缝上边 / 竖缝左边），high = 另一侧。"""
    w, h = SEAM_V if vertical else SEAM_H
    low = _tile_blend(low_path, w, h, seed)
    high = _tile_blend(high_path, w, h, seed + 7)
    depth = w if vertical else h
    along = h if vertical else w
    noise = _noise_field(depth, along, 6, seed + 3)
    jag = _noise_field(depth, along, 24, seed + 11)
    yy = np.arange(depth, dtype=np.float32)[:, None]
    base = depth * (0.5 + (noise - 0.5) * 2.0 * wobble)
    width = np.maximum(depth * soft * (0.55 + 0.9 * jag), 1.0)
    t = np.clip(0.5 + (yy - base) / width, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    if vertical:
        t = t.T
    rgb = low * (1.0 - t[..., None]) + high * t[..., None]
    alpha = np.ones(rgb.shape[:2], dtype=np.float32)
    rgba = _depth_feather(np.dstack([rgb, alpha]), 1 if vertical else 0,
                          max(24, int(depth * 0.30)), seed)
    _save(rgba, name)


def build_corner_fourway(name: str = "corner_fourway_v2.png", seed: int = 131) -> None:
    """四区交汇点（世界 0,0）：四块地面 tile 按噪声边界缝成一张，中心不透明、
    往外径向淡出。四条接缝带在交汇处各自只剩约 50% alpha，地形板块的硬边
    会从缝里透出来；这张补片把直边压掉，读成一整片过渡野地。
    象限顺序与地图一致：左上丹霞 / 右上云隐 / 左下幽冥 / 右下青岚。"""
    w, h = CORNER
    nw = _tile_blend(os.path.join(TILE_DIR, "jiedan_grass.png"), w, h, seed)
    ne = _tile_blend(os.path.join(TILE_DIR, "zhuji_forestfloor.png"), w, h, seed + 3)
    sw = _tile_blend(os.path.join(TILE_DIR, "youming_grass.png"), w, h, seed + 5)
    se = _tile_blend(os.path.join(TILE_DIR, "lianqi_grass.png"), w, h, seed + 7)

    u = np.linspace(-1.0, 1.0, w, dtype=np.float32)[None, :]
    v = np.linspace(-1.0, 1.0, h, dtype=np.float32)[:, None]
    wob_x = (_noise_field(h, w, 8, seed + 11) - 0.5) * 0.18
    wob_y = (_noise_field(h, w, 8, seed + 13) - 0.5) * 0.18
    soft = 0.10
    sx = np.clip((u - wob_x) / soft * 0.5 + 0.5, 0.0, 1.0)
    sy = np.clip((v - wob_y) / soft * 0.5 + 0.5, 0.0, 1.0)
    sx = sx * sx * (3.0 - 2.0 * sx)
    sy = sy * sy * (3.0 - 2.0 * sy)
    rgb = (nw * ((1 - sx) * (1 - sy))[..., None]
           + ne * (sx * (1 - sy))[..., None]
           + sw * ((1 - sx) * sy)[..., None]
           + se * (sx * sy)[..., None])

    # 半径按贴图短边归一化：中边 r=1（≈439 世界像素）。补片只在中心区不透明，
    # 外圈淡出到 0，避免补片自己的方边露出来。
    rad = np.sqrt(u * u + v * v)
    rad += (_noise_field(h, w, 6, seed + 17) - 0.5) * 0.12
    a = np.clip((0.98 - rad) / 0.56, 0.0, 1.0)
    a = a * a * (3.0 - 2.0 * a)
    rgba = np.dstack([rgb, a])
    _save(rgba, name)


def main() -> int:
    lianqi_grass = _tile_mean("lianqi_grass.png")
    zhuji_floor = _tile_mean("zhuji_forestfloor.png")
    jiedan_grass = _tile_mean("jiedan_grass.png")
    youming_grass = _tile_mean("youming_grass.png")
    print("targets: lianqi", np.round(lianqi_grass, 3), "zhuji", np.round(zhuji_floor, 3),
          "jiedan", np.round(jiedan_grass, 3), "youming", np.round(youming_grass, 3))

    print("outer bands:")
    # 赤金丹霞：源图内缘（红土）在上、外缘（岩板 + 黑）在下
    build_band(JIEDAN, 0, 950, BAND_H, False, jiedan_grass, "bottom", "top",
               "jiedan_band_north_v2.png", flip=True, darken=0.58)
    build_band(JIEDAN, 0, 950, BAND_V, False, jiedan_grass, "right", "left",
               "jiedan_band_west_v2.png", rotate_cw=True, darken=0.58)
    # 幽冥灵墟：内缘石板在上、外缘玄武岩在下
    build_band(YOUMING, 0, 950, BAND_H, False, youming_grass, "top", "bottom",
               "youming_band_south_v2.png", darken=0.56)
    build_band(YOUMING, 0, 950, BAND_V, False, youming_grass, "right", "left",
               "youming_band_west_v2.png", rotate_cw=True, darken=0.56)
    # 青岚野：草地 → 俯视松冠（同一张林冠边，按边旋转/翻转）
    build_band(FOREST_CANOPY, 40, 995, BAND_H, False, lianqi_grass, "top", "bottom",
               "lianqi_band_south_v2.png", darken=0.62)
    build_band(FOREST_CANOPY, 40, 995, BAND_V, False, lianqi_grass, "left", "right",
               "lianqi_band_east_v2.png", rotate_ccw=True, darken=0.62)
    # 云隐谷：同一张林冠边压冷压暗，接谷内林地
    build_band(FOREST_CANOPY, 40, 995, BAND_H, False, zhuji_floor, "bottom", "top",
               "zhuji_band_north_v2.png", flip=True, darken=0.58,
               mul=0.78, desat=0.18, tint=(0.86, 0.96, 1.08))
    build_band(FOREST_CANOPY, 40, 995, BAND_V, False, zhuji_floor, "left", "right",
               "zhuji_band_east_v2.png", rotate_ccw=True, darken=0.58,
               mul=0.78, desat=0.18, tint=(0.86, 0.96, 1.08))

    print("seam mats:")
    # 横缝 1：北云隐（林地表） / 南青岚（草）
    build_seam_tiles(os.path.join(TILE_DIR, "zhuji_forestfloor.png"),
                     os.path.join(TILE_DIR, "lianqi_grass.png"),
                     "seam_h_lianqi_zhuji_v2.png", seed=41)
    # 横缝 2：北丹霞（红土） / 南幽冥（石板）
    build_seam_tiles(os.path.join(TILE_DIR, "jiedan_grass.png"),
                     os.path.join(TILE_DIR, "youming_grass.png"),
                     "seam_h_jiedan_youming_v2.png", seed=57)
    # 竖缝 1：左丹霞（红土） / 右云隐（林地表）
    build_seam_tiles(os.path.join(TILE_DIR, "jiedan_grass.png"),
                     os.path.join(TILE_DIR, "zhuji_forestfloor.png"),
                     "seam_v_jiedan_zhuji_v2.png", vertical=True, seed=73)
    # 竖缝 2：左幽冥（石板） / 右青岚（草）
    build_seam_tiles(os.path.join(TILE_DIR, "youming_grass.png"),
                     os.path.join(TILE_DIR, "lianqi_grass.png"),
                     "seam_v_lianqi_youming_v2.png", vertical=True, seed=89)

    print("corner caps:")
    build_corner_fourway()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
