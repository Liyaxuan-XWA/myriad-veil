#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""云隐苍角：谷心苔石圈 + 苔甲片整形（2026-10-29）。

输入是 ImageGen 的品红底原图，输出透明 PNG：
  品红抠图 → 去溢色 → 抹右下角水印 → 按内容裁切 → 缩放到世界显示尺寸的 1.8 倍。
谷心石圈铺在 z=-8 当贴地地标；苔甲片挂在 BOSS 角侧，三击碎一片。
用法：
    python tools/prep_zhuji_core_art.py
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_boss_sprite_frames import key_out  # noqa: E402

RING_SRC = "vibe_images/zhuji_stone_ring_1793213913681_8a535ae4.png"
RING_OUT = "assets/scenes/zhuji_stone_ring.png"
SHARD_SRC = "vibe_images/stag_plate_shard_1793213931026_06270337.png"
SHARD_OUT = "assets/effects/skills/stag_plate.png"
STAG_SRC = "vibe_images/cangjiao_cel_v2_1793214583012_097dab94.png"
STAG_OUT = "assets/characters/boss/cangjiao.png"
ARMOR_ICON_SRC = "vibe_images/cangjiao_armor_icon_1793215328935_6ae28d0f.png"
ARMOR_ICON_OUT = "assets/ui/icon/equip_cangjiao_jia.png"
TRIM_ALPHA = 64
FLOOR_ALPHA = 12


def despill(cut: np.ndarray) -> np.ndarray:
    rgb = cut[..., :3].astype(np.float32)
    spill = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    k = np.where(spill > 0.0, spill * 0.92, 0.0)
    rgb[..., 0] = np.clip(rgb[..., 0] - k, 0.0, 255.0)
    rgb[..., 2] = np.clip(rgb[..., 2] - k, 0.0, 255.0)
    out = cut.copy()
    out[..., :3] = rgb.round().astype(np.uint8)
    return out


def cutout(src: str, wm_box=None, rotate: float = 0.0) -> Image.Image:
    im = Image.open(src).convert("RGB")
    cut = np.array(key_out(im))
    if wm_box is not None:
        x0, y0, x1, y1 = wm_box
        cut[y0:y1, x0:x1, 3] = 0
    a = cut[..., 3]
    a[a < FLOOR_ALPHA] = 0
    cut[..., 3] = a
    cut = despill(cut)

    ys, xs = np.nonzero(a > TRIM_ALPHA)
    crop = Image.fromarray(cut).crop(
        (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    if rotate:
        crop = crop.rotate(rotate, resample=Image.BICUBIC, expand=True)
        arr = np.array(crop)
        ys, xs = np.nonzero(arr[..., 3] > TRIM_ALPHA)
        crop = crop.crop(
            (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    return crop


def save(crop: Image.Image, out: str, target_w: int = 0, target_h: int = 0,
         pad: int = 2) -> None:
    s = (target_w / float(crop.size[0])) if target_w else (target_h / float(crop.size[1]))
    size = (max(1, round(crop.size[0] * s)), max(1, round(crop.size[1] * s)))
    crop = crop.resize(size, Image.LANCZOS)
    crop = Image.fromarray(despill(np.array(crop)))
    canvas = Image.new("RGBA", (crop.size[0] + pad * 2, crop.size[1] + pad * 2),
                       (0, 0, 0, 0))
    canvas.alpha_composite(crop, (pad, pad))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print(f"  {out}: {canvas.size}")


def fade_ring_floor(img: Image.Image) -> Image.Image:
    """石圈内部原图是一潭深色雾水，直接铺地会读成「水面不能走」。
    把中心压到 55% 透明、外沿保持实心，让草地从缝里透出来，读成湿苔空地。"""
    w, h = img.size
    cx, cy = w / 2.0, h / 2.0
    r_outer = min(w, h) / 2.0
    arr = np.array(img)
    ys, xs = np.mgrid[0:h, 0:w]
    r = np.hypot(xs - cx, ys - cy) / r_outer
    factor = np.clip((r - 0.62) / 0.18, 0.0, 1.0) * 0.45 + 0.55
    arr[..., 3] = (arr[..., 3].astype(np.float32) * factor).round().astype(np.uint8)
    return Image.fromarray(arr)


def save_square(crop: Image.Image, out: str, content: int = 232,
                canvas_size: int = 256) -> None:
    s = content / float(max(crop.size))
    size = (max(1, round(crop.size[0] * s)), max(1, round(crop.size[1] * s)))
    crop = crop.resize(size, Image.LANCZOS)
    crop = Image.fromarray(despill(np.array(crop)))
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    canvas.alpha_composite(crop, ((canvas_size - crop.size[0]) // 2,
                                  (canvas_size - crop.size[1]) // 2))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print(f"  {out}: {canvas.size}")


def main() -> int:
    print("[stag]")
    save(cutout(STAG_SRC), STAG_OUT, target_h=1400)
    print("[armor icon]")
    save_square(cutout(ARMOR_ICON_SRC, wm_box=(840, 960, 1024, 1024)), ARMOR_ICON_OUT)
    print("[ring]")
    save(fade_ring_floor(cutout(RING_SRC, wm_box=(800, 975, 1024, 1024))), RING_OUT, 900)
    print("[shard]")
    save(cutout(SHARD_SRC, rotate=26.0), SHARD_OUT, 108)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
