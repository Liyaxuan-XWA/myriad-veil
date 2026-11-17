#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""两仪真人「阴阳双鱼」的弹体贴图（2026-10-29）。

双鱼原来走 boss_projectile 的占位方块（金/蓝 18px），局内像两块色板。
这里画一对朝右的鱼形符箓：阳鱼暖金、阴鱼青蓝，透明底、加法友好。
用法：python tools/gen_liangyi_fish.py
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

OUT = "assets/effects/skills"
S = 4  # 超采样倍数
W, H = 512, 256


def _glow(mask: Image.Image, color: tuple[int, int, int], blur: int, alpha: int) -> Image.Image:
    layer = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    solid = Image.new("RGBA", mask.size, (color[0], color[1], color[2], alpha))
    layer.paste(solid, (0, 0), mask)
    return layer.filter(ImageFilter.GaussianBlur(blur))


def build(body: tuple[int, int, int], line: tuple[int, int, int],
          ink: tuple[int, int, int], name: str) -> None:
    w, h = W * S, H * S
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)

    def p(x: float, y: float) -> tuple[float, float]:
        return x * S, y * S

    body_pts = [p(455, 128), p(392, 86), p(302, 62), p(222, 72),
                p(166, 100), p(150, 128), p(166, 156), p(222, 184),
                p(302, 198), p(392, 170)]
    tail_pts = [p(150, 128), p(54, 54), p(94, 128), p(54, 202)]
    dorsal = [p(300, 72), p(340, 24), p(362, 78)]
    belly = [p(300, 188), p(332, 232), p(356, 178)]
    pectoral = [p(318, 148), p(366, 166), p(332, 186)]

    md.polygon(tail_pts, fill=255)
    md.polygon(dorsal, fill=255)
    md.polygon(belly, fill=255)
    md.polygon(pectoral, fill=255)
    md.polygon(body_pts, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.6 * S))

    c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    c = Image.alpha_composite(c, _glow(mask, line, 20 * S, 90))
    d = ImageDraw.Draw(c)

    # 身体：亮色平涂 + 暗墨内纹，远看是一尾发光的鱼
    d.polygon(tail_pts, fill=(*body, 235), outline=(*ink, 235), width=2 * S)
    d.polygon(dorsal, fill=(*body, 225), outline=(*ink, 235), width=2 * S)
    d.polygon(belly, fill=(*body, 225), outline=(*ink, 235), width=2 * S)
    d.polygon(pectoral, fill=(*line, 230), outline=(*ink, 235), width=2 * S)
    d.polygon(body_pts, fill=(*body, 238), outline=(*ink, 245), width=3 * S)

    # 尾鳍分叉、背鳍纹
    d.line([p(96, 128), p(142, 128)], fill=(*ink, 220), width=2 * S)
    for a, b in ((p(330, 34), p(344, 70)), (p(316, 190), p(338, 210))):
        d.line([a, b], fill=(*ink, 170), width=2 * S)

    # 鳃弧 + 眼睛（阳鱼金瞳 / 阴鱼青瞳）
    d.arc([p(354, 94), p(414, 162)], 250, 110, fill=(*ink, 220), width=3 * S)
    d.ellipse([p(392, 104), p(412, 124)], fill=(*ink, 245))
    d.ellipse([p(397, 108), p(407, 118)], fill=(*line, 255))

    # 身体上的太极 S 纹：一条亮线，两枚鱼眼点
    d.arc([p(214, 88), p(346, 168)], 90, 270, fill=(*line, 210), width=3 * S)
    d.arc([p(248, 88), p(380, 168)], 270, 90, fill=(*ink, 190), width=3 * S)
    d.ellipse([p(258, 116), p(272, 130)], fill=(*line, 235))
    d.ellipse([p(322, 126), p(334, 138)], fill=(*ink, 210))

    c = c.resize((W, H), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    c.save(os.path.join(OUT, name))
    print("fish", name, c.size)


def main() -> int:
    build((244, 202, 108), (255, 238, 176), (28, 24, 18), "liangyi_fish_yang.png")
    build((96, 194, 212), (176, 240, 248), (10, 30, 34), "liangyi_fish_yin.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
