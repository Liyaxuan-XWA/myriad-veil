#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""赤金火麟：立绘抠图 + 骨骼拆件源（2026-10-29）。

输入是 ImageGen 的品红底定妆图（3/4 朝右），输出透明 PNG：
  品红抠图 → 去溢色 → 抹右下角水印 → 按内容裁切 → 缩放到目标高度。
产物同时喂给 tools/build_world_boss_rigs.py 的 qilin 条目做分件。

用法：
    python tools/prep_qilin_art.py
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_boss_sprite_frames import key_out  # noqa: E402

SRC = "vibe_images/qilin_boss_art_1793269592016_72cf4aa7.png"
OUT = "assets/characters/boss/qilin.png"
GRID = "output/qilin_rig_grid.png"
CARD_SRC = "vibe_images/qilin_codex_card_1793283189183_79580483.png"
CARD_OUT = "assets/ui/codex/card_boss_core_qilin.png"
CARD_SIZE = (640, 960)
ICON_SRC = "vibe_images/huolin_jia_icon_1793283206446_6837e2b4.png"
ICON_OUT = "assets/ui/icon/equip_huolin_jia.png"
TRIM_ALPHA = 64
FLOOR_ALPHA = 12
TARGET_H = 1400


def despill(cut: np.ndarray) -> np.ndarray:
    rgb = cut[..., :3].astype(np.float32)
    spill = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    k = np.where(spill > 0.0, spill * 0.92, 0.0)
    rgb[..., 0] = np.clip(rgb[..., 0] - k, 0.0, 255.0)
    rgb[..., 2] = np.clip(rgb[..., 2] - k, 0.0, 255.0)
    out = cut.copy()
    out[..., :3] = rgb.round().astype(np.uint8)
    return out


def cutout(src: str, wm_box=None) -> Image.Image:
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
    return Image.fromarray(cut).crop(
        (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def patch_watermark(im: Image.Image, box=(800, 1430, 1024, 1535)) -> Image.Image:
    """右下角「Qoder AI生成」压在丹霞岩壁上：用同行的左侧岩块镜像覆盖，
    边界做 20px 羽化，避免出现一块颜色一致的补丁。"""
    arr = np.array(im).astype(np.float32)
    x0, y0, x1, y1 = box
    w = x1 - x0
    src = arr[y0:y1, x0 - w - 20:x1 - w - 20].copy()
    src = src[:, ::-1]
    feather = 20
    mask = np.ones((y1 - y0, w, 1), dtype=np.float32)
    for i in range(feather):
        a = float(i) / feather
        mask[i, :, 0] *= a
        mask[-(i + 1), :, 0] *= a
    for i in range(feather):
        a = float(i) / feather
        mask[:, i, 0] *= a
        mask[:, -(i + 1), 0] *= a
    arr[y0:y1, x0:x1] = arr[y0:y1, x0:x1] * (1.0 - mask) + src * mask
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def prep_card() -> None:
    im = Image.open(CARD_SRC).convert("RGB")
    im = patch_watermark(im)
    if im.size != CARD_SIZE:
        im = im.resize(CARD_SIZE, Image.LANCZOS)
    os.makedirs(os.path.dirname(CARD_OUT), exist_ok=True)
    im.save(CARD_OUT)
    print(f"  {CARD_OUT}: {im.size}")


def prep_icon() -> None:
    cut = np.array(key_out(Image.open(ICON_SRC).convert("RGB")))
    cut[930:1024, 880:1024, 3] = 0  # 右下角水印落在留白里，直接抹掉
    cut = despill(cut)
    a = cut[..., 3]
    a[a < FLOOR_ALPHA] = 0
    cut[..., 3] = a
    ys, xs = np.nonzero(a > TRIM_ALPHA)
    crop = Image.fromarray(cut).crop(
        (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    s = 232.0 / float(max(crop.size))
    crop = crop.resize((max(1, round(crop.size[0] * s)),
                        max(1, round(crop.size[1] * s))), Image.LANCZOS)
    crop = Image.fromarray(despill(np.array(crop)))
    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    canvas.alpha_composite(crop, ((256 - crop.size[0]) // 2, (256 - crop.size[1]) // 2))
    os.makedirs(os.path.dirname(ICON_OUT), exist_ok=True)
    canvas.save(ICON_OUT)
    print(f"  {ICON_OUT}: {canvas.size}")


def main() -> int:
    art = cutout(SRC, wm_box=(820, 1440, 1024, 1536))
    s = TARGET_H / float(art.size[1])
    size = (max(1, round(art.size[0] * s)), TARGET_H)
    art = Image.fromarray(despill(np.array(art.resize(size, Image.LANCZOS))))
    canvas = Image.new("RGBA", (art.size[0] + 4, art.size[1] + 4), (0, 0, 0, 0))
    canvas.alpha_composite(art, (2, 2))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    canvas.save(OUT)
    print(f"  {OUT}: {canvas.size}")

    # 标尺图：给拆件定关节用（每 50px 一条细线，每 100px 标数字）
    from PIL import ImageDraw
    grid = Image.new("RGBA", canvas.size, (24, 24, 28, 255))
    grid.alpha_composite(canvas)
    d = ImageDraw.Draw(grid)
    w, h = grid.size
    for x in range(0, w, 50):
        d.line([(x, 0), (x, h)], fill=(255, 255, 0, 60), width=1)
    for y in range(0, h, 50):
        d.line([(0, y), (w, y)], fill=(255, 255, 0, 60), width=1)
    for x in range(0, w, 100):
        d.text((x + 2, 2), str(x), fill=(255, 255, 120, 255))
        d.text((x + 2, h - 14), str(x), fill=(255, 255, 120, 255))
    for y in range(0, h, 100):
        d.text((2, y + 1), str(y), fill=(120, 255, 255, 255))
        d.text((w - 40, y + 1), str(y), fill=(120, 255, 255, 255))
    os.makedirs(os.path.dirname(GRID), exist_ok=True)
    grid.save(GRID)
    print(f"  {GRID}: {grid.size}")
    prep_card()
    prep_icon()
    return 0


if __name__ == "__main__":
    sys.exit(main())
