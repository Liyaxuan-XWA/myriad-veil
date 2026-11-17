#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""赤金丹霞·霞心日轮祭坛：抠图 + 去品红/绿边 + 压暗中心日斑（2026-10-29）。

原图是品红底圆形祭坛，键色后外沿石块上残留一圈荧光绿/品红像素（出图过饱和边缘），
直接铺在暗红地表上会读成「发光噪点」。这里只处理彩边像素，不动石块本体；
再把中心日斑压暗一点，免得 BOSS 站上去被白斑吃掉轮廓。
输出覆盖 assets/scenes/jiedan_sun_altar.png。
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_boss_sprite_frames import key_out  # noqa: E402

SRC = "vibe_images/jiedan_arena_ring_1793269809430_da8f5548.png"
OUT = "assets/scenes/jiedan_sun_altar.png"
SIZE = 900


def main() -> int:
    cut = np.array(key_out(Image.open(SRC).convert("RGB")))
    h0, w0 = cut.shape[:2]
    cut[int(h0 * 0.93):, int(w0 * 0.79):, 3] = 0  # 右下角水印在圆盘外缘之外，盒子别切到石圈
    rgb = cut[..., :3].astype(np.float32) / 255.0
    a = cut[..., 3]

    # 品红 / 荧光绿彩边：往暗石色收，不整体去饱和（石块本身要保留红金）
    mag = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    grn = rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])
    fringe = ((mag > 0.06) | (grn > 0.06)) & (a > 0)
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    stone = np.stack([lum * 1.02, lum * 0.84, lum * 0.70], axis=2)
    strength = np.clip((np.maximum(mag, grn) - 0.02) / 0.16, 0.0, 1.0)
    mix = (fringe * strength)[..., None]
    rgb = rgb * (1.0 - mix) + stone * mix

    # 中心日斑压暗 22%：越靠中心越暗，边缘平滑过渡，不影响外圈石纹
    h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - w * 0.5, yy - h * 0.5) / (min(w, h) * 0.5)
    dim = 0.78 + 0.22 * np.clip((r - 0.30) / 0.10, 0.0, 1.0)
    rgb *= dim[..., None]

    out = cut.copy()
    out[..., :3] = np.clip(rgb * 255.0, 0, 255).round().astype(np.uint8)
    im = Image.fromarray(out)
    if im.size != (SIZE, SIZE):
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im.save(OUT)
    print(f"  {OUT}: {im.size} 彩边修正 {int(fringe.sum())} px")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())