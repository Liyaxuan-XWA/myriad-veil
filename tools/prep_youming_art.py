#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""幽冥灵墟：废墟外沿带 + 中央残门 + 两隻阴兽的抠图整形（2026-10-31）。

品红键色口径和练气 / 丹霞一致：键底 → 只反解有溢色的像素 → 裁内容 → 压平 → 对齐亮度。
差别：
  · 南沿用 1536×1024 的横向废墟墙（墙底、上方透明）；
  · 西沿另出一张 1024×1792 的连续墙立面（墙从左沿贯到上下边缘、无天空/地面），
    横带旋转 90° 会把塔楼放倒；带塔顶和天空的竖图在 y 向接缝处会拼出一条横板。
  · 残门 / 两隻兽是单帧立绘，底边锚地。
  · 水印只在品红底或暗岩上，用左邻同高纹理羽化盖掉（沿用水印贴块口径）。

用法：
    python tools/prep_youming_art.py
随后本地无缝化（sprite-gen，零凭据）：
    background-tile --source output/tiles/youming/youming_band_south.png \
        --out assets/scenes/tiles/youming_band_south.png --period 1536 --axis x --overlap 128
    background-tile --source output/tiles/youming/youming_band_west.png \
        --out assets/scenes/tiles/youming_band_west.png --period 1536 --axis y --overlap 128
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_region_bands as R  # noqa: E402
from gen_boss_sprite_frames import key_out  # noqa: E402
from prep_zhuji_core_art import despill  # noqa: E402

ROOT = R.ROOT
SRC_DIR = os.path.join(ROOT, "vibe_images")
WORK_DIR = os.path.join(ROOT, "output", "tiles", "youming")
SCENE_DIR = os.path.join(ROOT, "assets", "scenes")
CHAR_DIR = os.path.join(ROOT, "assets", "characters", "world")

BAND = os.path.join(SRC_DIR, "youming_band_wall_1793451802256_17488df9.png")
BAND_WM = (1340, 968, 1520, 1018)
BAND_WEST = os.path.join(SRC_DIR, "youming_band_west_v3_1793453202007_5766bb62.png")
BAND_WEST_WM = (866, 1726, 1016, 1778)
GATE = os.path.join(SRC_DIR, "youming_gate_v2_1793451863080_123617a5.png")
GATE_WM = (838, 1456, 1018, 1514)
FENGYA = os.path.join(SRC_DIR, "youming_beast_fengya_1793451921267_36e074b7.png")
JIANJIA = os.path.join(SRC_DIR, "youming_beast_jianjia_v2_1793451998887_25a39e66.png")

# 工作图：南带 1664 = period 1536 + overlap 128；高 818/1.75 ≈ 467 世界像素，
# 南沿墙 355 能被盖住；西带旋转后同尺寸。
H_WORK = (1664, 818)
V_WORK = (818, 1664)
GATE_H = 1450
BEAST_H = {"fengya": 240, "jianjia": 256}


def _gamma_to(rgb: np.ndarray, alpha: np.ndarray, target: float) -> tuple[np.ndarray, float]:
    fg = alpha > 0.5
    lo, hi = 0.05, 20.0
    gamma = 1.0
    for _ in range(28):
        gamma = 0.5 * (lo + hi)
        if np.power(np.clip(rgb, 1e-4, 1.0), gamma).mean(axis=2)[fg].mean() < target:
            hi = gamma
        else:
            lo = gamma
    return np.power(np.clip(rgb, 1e-4, 1.0), gamma), gamma


def _key_with_ref(rgb: np.ndarray, bg: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """key_out 的逻辑，但底色从「品红像素中位色」取。

    竖带原图上沿是塔楼、左下是岩体，四角里只有两个是品红，key_out 取四角
    中位数会拿到暗岩色。这里只换底色的取法，反合成与软边去溢色不变。
    """
    bg_ex = float(min(bg[0], bg[2]) - bg[1])
    if bg_ex < 0.15:
        raise SystemExit(f"品红底估计失败：{np.round(bg, 3)}")
    ex = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    alpha = np.clip(1.0 - ex / bg_ex, 0.0, 1.0)
    alpha = np.clip((alpha - 0.04) / 0.92, 0.0, 1.0)
    a3 = alpha[..., None]
    fg = (rgb - (1.0 - a3) * bg[None, None, :]) / np.maximum(a3, 1e-4)
    fg = np.clip(fg, 0.0, 1.0)
    soft = alpha < 0.85
    spill = np.minimum(fg[..., 0], fg[..., 2]) - fg[..., 1]
    fix = soft & (spill > 0.0)
    if np.any(fix):
        k = np.where(fix, spill * 0.9, 0.0).astype(fg.dtype)
        fg[..., 0] = np.clip(fg[..., 0] - k, 0.0, 1.0)
        fg[..., 2] = np.clip(fg[..., 2] - k, 0.0, 1.0)
    return fg, alpha


def _resize_rgba(rgb: np.ndarray, alpha: np.ndarray, size: tuple[int, int]):
    h, w = rgb.shape[:2]
    tw, th = size
    out = np.zeros((th, tw, 4), dtype=np.float32)
    for ch in range(3):
        im = Image.fromarray((rgb[:, :, ch] * 255.0 + 0.5).astype(np.uint8))
        out[:, :, ch] = np.asarray(im.resize((tw, th), Image.LANCZOS), dtype=np.float32) / 255.0
    a = Image.fromarray((alpha * 255.0 + 0.5).astype(np.uint8))
    out[:, :, 3] = np.asarray(a.resize((tw, th), Image.LANCZOS), dtype=np.float32) / 255.0
    return out[:, :, :3], out[:, :, 3]


def _save(rgba: np.ndarray, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray((np.clip(rgba, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)).save(path)
    print(f"  -> {os.path.relpath(path, ROOT)}  {rgba.shape[1]}x{rgba.shape[0]}")


def _bleed_edge(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """半透明/透明像素的 RGB 换成同行最近的不透明颜色（边缘延展）。

    林带贴图 repeat_enable：板边 uv→1 会绕回第 0 列采样，双线性再和透明边混。
    抠图后透明区的 RGB 还留着品红/金光底，实测在西墙内侧拉出一条 1px 亮线。
    阈值取 0.6：连羽化带一起换成实心岩色，羽化只留 alpha，不再带底色。
    """
    out = rgb.copy()
    a = alpha > 0.6
    h, w = a.shape
    xs_all = np.arange(w)
    solid_rows = np.where(a.any(axis=1))[0]
    for y in range(h):
        xs = np.where(a[y])[0]
        if len(xs) == 0:
            continue
        left = xs[np.clip(np.searchsorted(xs, xs_all) - 1, 0, len(xs) - 1)]
        right = xs[np.clip(np.searchsorted(xs, xs_all), 0, len(xs) - 1)]
        pick = np.where(np.abs(xs_all - left) <= np.abs(right - xs_all), left, right)
        hole = ~a[y]
        out[y, hole] = rgb[y, pick[hole]]
    if len(solid_rows) > 0:
        for y in range(h):
            if a[y].any():
                continue
            near = solid_rows[np.argmin(np.abs(solid_rows - y))]
            out[y] = rgb[near]
    return out


def band() -> None:
    img = Image.open(BAND).convert("RGB")
    rgb = np.asarray(img, dtype=np.float32) / 255.0
    rgb, cast, ink = R._patch_watermark(rgb, BAND_WM)
    ## 这张墙的岩体带青苔与幽火反光，R._key 的反合成会把岩缝的青绿放大成荧光边
    ## （实测 9 万像素 g 高出 r/b 0.08 以上）；走 sprite 的 key_out 保留原色。
    cut = np.array(key_out(Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8))))
    rgb = cut[..., :3].astype(np.float32) / 255.0
    alpha = cut[..., 3].astype(np.float32) / 255.0
    rgb, alpha, _ = R._crop_to_content(rgb, alpha)
    rgb, alpha = _resize_rgba(rgb, alpha, H_WORK)
    rgb = R._flatten_rgb(rgb, alpha)
    rgb, gamma = _gamma_to(rgb, alpha, 0.185)
    rgb = _bleed_edge(rgb, alpha)
    fg = alpha > 0.5
    print(f"[band] 水印色差={cast:.4f} 墨比={ink:.3f}")
    print(f"  前景 {fg.mean() * 100:.1f}%  亮度 {rgb.mean(axis=2)[fg].mean():.3f} gamma={gamma:.3f}")
    _save(np.dstack([rgb, alpha]), os.path.join(WORK_DIR, "youming_band_south.png"))

    west()


def west() -> None:
    img = Image.open(BAND_WEST).convert("RGB")
    rgb = np.asarray(img, dtype=np.float32) / 255.0
    rgb, alpha = _key_with_ref(rgb, R._bg_ref(rgb))
    ## 水印压在右下角品红底上，贴块会借到墙沿的暗岩（实测留下一块黑方砖）；
    ## 直接键掉后把水印盒清零，盒内只有品红和字，墙不到这里。
    x0, y0, x1, y1 = BAND_WEST_WM
    alpha[y0:y1, x0:x1] = 0.0
    alpha[alpha < 0.03] = 0.0
    rgb, alpha, _ = R._crop_to_content(rgb, alpha)
    rgb, alpha = _resize_rgba(rgb, alpha, V_WORK)
    rgb = R._flatten_rgb(rgb, alpha)
    rgb, gamma = _gamma_to(rgb, alpha, 0.17)
    rgb = _bleed_edge(rgb, alpha)
    fg = alpha > 0.5
    print("[band-west] 水印直接清 alpha")
    print(f"  前景 {fg.mean() * 100:.1f}%  亮度 {rgb.mean(axis=2)[fg].mean():.3f} gamma={gamma:.3f}")
    _save(np.dstack([rgb, alpha]), os.path.join(WORK_DIR, "youming_band_west.png"))


def _cut_sprite(path: str, wm_box=None) -> Image.Image:
    img = Image.open(path).convert("RGB")
    if wm_box is not None:
        rgb = np.asarray(img, dtype=np.float32) / 255.0
        rgb, cast, ink = R._patch_watermark(rgb, wm_box)
        print(f"  水印色差={cast:.4f} 墨比={ink:.3f}")
        img = Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8))
    cut = np.array(key_out(img))
    a = cut[..., 3]
    a[a < 12] = 0
    cut[..., 3] = a
    cut = despill(cut)
    ys, xs = np.nonzero(a > 48)
    return Image.fromarray(cut).crop(
        (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def _save_height(crop: Image.Image, out: str, target_h: int, pad: int = 4) -> None:
    s = target_h / float(crop.size[1])
    size = (max(1, round(crop.size[0] * s)), target_h)
    crop = crop.resize(size, Image.LANCZOS)
    crop = Image.fromarray(despill(np.array(crop)))
    canvas = Image.new("RGBA", (crop.size[0] + pad * 2, crop.size[1] + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(crop, (pad, pad))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print(f"  {os.path.relpath(out, ROOT)}: {canvas.size}")


def main() -> int:
    print("[band]")
    band()
    print("[gate]")
    gate = _cut_sprite(GATE, GATE_WM)
    _save_height(gate, os.path.join(SCENE_DIR, "youming_gate.png"), GATE_H)
    print("[beasts]")
    _save_height(_cut_sprite(FENGYA), os.path.join(CHAR_DIR, "youming_beast_fengya.png"),
                 BEAST_H["fengya"])
    _save_height(_cut_sprite(JIANJIA), os.path.join(CHAR_DIR, "youming_beast_jianjia.png"),
                 BEAST_H["jianjia"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
