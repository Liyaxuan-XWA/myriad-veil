#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""练气区怪物 / 首领美术整形（2026-10-28）。

输入是 ImageGen 的品红底立绘，输出是 ArtDB 直接可用的透明 PNG：
  品红抠图 → 去溢色 → 抹右下角水印 → 清掉极淡的键色残雾 → 按内容裁切 → 统一高度缩放
  → 居中放进带透明边的画布（SkinVisual 的 target_length 读内容高度，画布留白只是防锯齿）。

⚠ 水印是白字，白色对「品红度」判据的 excess = min(R,B)-G = 0，会被判成**实心前景**，
  所以不能只靠抠图；三张图的右下角都按矩形整块抹掉（实测身体最低点 y≈832，抹 y≥920 安全）。
⚠ 高度口径：输出图的内容高度 = 显示高度的 4 倍，给显示器缩放留采样余量；
  真正显示多大由 ArtDB.VISUALS 的 target_length 决定，本脚本不写死显示尺寸。
用法：
    python tools/prep_lianqi_art.py
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_boss_sprite_frames import key_out  # noqa: E402

OUT_DIR = "assets/characters/world"
CARD_DIR = "assets/ui/codex"

## src / 输出名 / 内容高度（输出像素） / 水印矩形
SPRITES = [
    ("vibe_images/beast_fengya_sprite_1793196732366_8a562bb9.png",
     "beast_fengya.png", 216, (820, 880, 1024, 1024)),
    ("vibe_images/beast_jianjia_sprite_1793196747645_f5a5d5b3.png",
     "beast_jianjia.png", 232, (820, 880, 1024, 1024)),
    ("vibe_images/ape_qinglan_sprite_cel_1793197036704_f9b80b68.png",
     "ape_qinglan.png", 504, None),
]
CARD_SRC = "vibe_images/card_boss_core_ape_1793196812674_f8534f45.png"
CARD_OUT = "card_boss_core_ape.png"
CARD_SIZE = (640, 960)
PAD = 6
TRIM_ALPHA = 64
FLOOR_ALPHA = 12


def despill(cut: np.ndarray) -> np.ndarray:
    """把品红残留从 R/B 里扣掉；背景透明像素的彩色底也会在缩放时被混进边缘，故缩放后再跑一遍。"""
    rgb = cut[..., :3].astype(np.float32)
    spill = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    k = np.where(spill > 0.0, spill * 0.92, 0.0)
    rgb[..., 0] = np.clip(rgb[..., 0] - k, 0.0, 255.0)
    rgb[..., 2] = np.clip(rgb[..., 2] - k, 0.0, 255.0)
    out = cut.copy()
    out[..., :3] = rgb.round().astype(np.uint8)
    return out


def process(src: str, out_name: str, target_h: int, wm_box) -> None:
    im = Image.open(src).convert("RGB")
    cut = np.array(key_out(im))
    if wm_box is not None:
        x0, y0, x1, y1 = wm_box
        cut[y0:y1, x0:x1, 3] = 0
        print(f"  抹水印 ({x0},{y0})-({x1},{y1})")
    a = cut[..., 3]
    a[a < FLOOR_ALPHA] = 0
    cut[..., 3] = a
    cut = despill(cut)

    ys, xs = np.nonzero(a > TRIM_ALPHA)
    bx0, bx1, by0, by1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    bw, bh = bx1 - bx0 + 1, by1 - by0 + 1
    s = target_h / float(bh)
    crop = Image.fromarray(cut).crop((bx0, by0, bx1 + 1, by1 + 1))
    crop = crop.resize((max(1, round(bw * s)), target_h), Image.LANCZOS)
    crop = Image.fromarray(despill(np.array(crop)))

    canvas = Image.new("RGBA", (crop.size[0] + PAD * 2, crop.size[1] + PAD * 2),
                       (0, 0, 0, 0))
    canvas.alpha_composite(crop, (PAD, PAD))
    path = os.path.join(OUT_DIR, out_name)
    canvas.save(path)
    print(f"  {out_name}: 内容 {bw}x{bh} → {crop.size}  画布 {canvas.size}  → {path}")


def process_card() -> None:
    im = Image.open(CARD_SRC).convert("RGB")
    if im.size != CARD_SIZE:
        im = im.resize(CARD_SIZE, Image.LANCZOS)
    path = os.path.join(CARD_DIR, CARD_OUT)
    im.save(path)
    print(f"  {CARD_OUT}: {im.size} → {path}")


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(CARD_DIR, exist_ok=True)
    for src, name, target_h, wm in SPRITES:
        print(f"[sprite] {src}")
        process(src, name, target_h, wm)
    print(f"[card] {CARD_SRC}")
    process_card()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
