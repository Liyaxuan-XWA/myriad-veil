"""三灾轮特效贴图（2026-10-29）。

给 SkillFx 的 calamity_wheel_at / calamity_warn_at 用：512² 透明底，
三段断环 + 中央三灾眼。线条要比 boss 背后的实体劫环更亮、更薄，
叠在暗色地面上才像「术法阵」而不是一块铁。
"""
from PIL import Image, ImageDraw, ImageFilter
import math

S = 1024  # 2× 超采样
OUT = "assets/effects/skills/calamity_wheel.png"
C = S / 2
COLORS = [(132, 208, 200), (236, 150, 92), (184, 150, 240)]


def arc(d, r, a0, a1, fill, width, ink=150):
    box = [C - r, C - r, C + r, C + r]
    d.arc(box, a0, a1, fill=(16, 14, 20, ink), width=width + 8)
    d.arc(box, a0, a1, fill=fill + (225,), width=width)


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 外 / 中 / 内三段断环，缺口错开
    arc(d, 452, 8, 108, COLORS[0], 9)
    arc(d, 452, 130, 224, COLORS[0], 9)
    arc(d, 452, 246, 338, COLORS[0], 9)
    arc(d, 386, 26, 122, COLORS[1], 7)
    arc(d, 386, 152, 244, COLORS[1], 7)
    arc(d, 386, 268, 348, COLORS[1], 7)
    arc(d, 318, 0, 88, COLORS[2], 7)
    arc(d, 318, 118, 206, COLORS[2], 7)
    arc(d, 318, 236, 326, COLORS[2], 7)
    # 环上刻度
    for i in range(24):
        ang = math.radians(i * 15)
        ca, sa = math.cos(ang), math.sin(ang)
        for r, col, ln in ((452, COLORS[0], 26), (386, COLORS[1], 20), (318, COLORS[2], 16)):
            d.line([(C + ca * (r + 16), C + sa * (r + 16)),
                    (C + ca * (r + 16 + ln), C + sa * (r + 16 + ln))],
                   fill=col + (150,), width=4)
    # 中央三灾眼：三角框 + 三个点 + 一条竖缝
    tri = []
    for i in range(3):
        ang = -math.pi / 2 + i * math.tau / 3.0
        tri.append((C + math.cos(ang) * 150, C + math.sin(ang) * 150))
    d.polygon(tri, outline=(226, 220, 208, 200))
    for p in tri:
        d.ellipse([p[0] - 9, p[1] - 9, p[0] + 9, p[1] + 9], fill=(226, 220, 208, 220))
    d.line([(C, C - 92), (C, C - 20)], fill=(226, 220, 208, 210), width=9)
    d.line([(C, C + 20), (C, C + 92)], fill=(226, 220, 208, 210), width=9)
    d.polygon([(C - 30, C + 8), (C + 30, C + 8), (C, C - 26)], fill=(226, 220, 208, 215))

    img = img.resize((512, 512), Image.LANCZOS)
    glow = img.filter(ImageFilter.GaussianBlur(7))
    glow.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.55)))
    out = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    out.alpha_composite(glow)
    out.alpha_composite(img)
    out.save(OUT)
    print("saved", OUT)


if __name__ == "__main__":
    main()
