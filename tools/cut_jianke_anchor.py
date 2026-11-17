#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""剑客定妆图预处理：品红抠图 → 抹水印 → 归一化到画布。

为什么单独一个脚本（而不是并进 build_*_rig.py）：
  定妆图是**一次性输入**，而拆件参数要反复调。分开之后，调拆件不用重复抠图，
  也能把「这张图怎么变成画布的」写死成可复现的一步。

⚠ 水印不能靠「裁掉底部 N 像素」：这把靴底和水印在竖直方向重叠（靴底更高），
  裁多了直接切脚。水印只压在品红背景上，所以按**矩形**抹掉 alpha 最稳。

用法：
    python tools/cut_jianke_anchor.py
输出：
    vibe_images/boss_work/boss_jianke/_canvas.png   900x720 画布（内容高 590、脚底 y=700）
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_boss_sprite_frames import key_out  # noqa: E402

SRC = ("vibe_images/boss_work/boss_jianke/"
       "_背景_高饱和荧光品红纯色平涂__FF00FF_量级_R_与_2026-10-26T05-09-43.png")
OUT = "vibe_images/boss_work/boss_jianke/_canvas.png"

FRAME_W, FRAME_H = 900, 720
CONTENT_H = 590.0
FOOT_MARGIN = 20
## 水印矩形（源图像素，含边界）。实测「AI生成 / WORKBUDDY」占 x≥858 y≥1432，
## 角色在该区域的最近部件是靴子（x≤720），所以整块抹掉是安全的。
WM_BOX = (858, 1432, 1024, 1536)


def main() -> int:
    im = Image.open(SRC).convert("RGB")
    cut = np.array(key_out(im))

    x0, y0, x1, y1 = WM_BOX
    cut[y0:y1, x0:x1, 3] = 0
    print(f"抹水印 ({x0},{y0})-({x1},{y1})")

    a = cut[..., 3]
    ys, xs = np.nonzero(a > 128)
    bx0, bx1, by0, by1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    bw, bh = bx1 - bx0 + 1, by1 - by0 + 1
    s = CONTENT_H / float(bh)
    print(f"内容 bbox {bw}x{bh}  缩放 {s:.4f}")

    crop = Image.fromarray(cut).crop((bx0, by0, bx1 + 1, by1 + 1))
    crop = crop.resize((max(1, round(bw * s)), max(1, round(bh * s))), Image.LANCZOS)
    canvas = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    left = int(round(FRAME_W * 0.5 - crop.size[0] * 0.5))
    top = int(round((FRAME_H - FOOT_MARGIN) - CONTENT_H))
    canvas.alpha_composite(crop, (left, top))
    canvas.save(OUT)
    print(f"画布 → {OUT}  粘贴于 ({left},{top})  尺寸 {crop.size}  脚底 y={FRAME_H - FOOT_MARGIN}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
