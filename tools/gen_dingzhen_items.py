"""定阵先生 · 阵旗令图标（2026-10-28）。

程序化绘制，与既有「BOSS 令」同一版式：黑漆令牌 + 金边 + 穗子；
本体换成朱砂红 + 三面小旗连成阵线的纹样，避免和两仪令的太极混淆。
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

ICON = "assets/ui/icon"

INK = (18, 20, 24, 255)
GOLD = (196, 154, 70, 255)
GOLD_L = (240, 210, 132, 255)
CINNABAR = (168, 58, 48, 255)
CINNABAR_L = (214, 92, 72, 255)


def soft_glow(size, color, radius=40, alpha=140):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size
    d.ellipse([w * 0.5 - radius, h * 0.5 - radius, w * 0.5 + radius, h * 0.5 + radius],
              fill=(color[0], color[1], color[2], alpha))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.35))


def save_icon(img, name):
    img = img.resize((256, 256), Image.LANCZOS)
    img = ac.polish(img, grain=0.12, rim_alpha=0.22)
    os.makedirs(ICON, exist_ok=True)
    img.save(os.path.join(ICON, name))
    print("icon", name)


def icon_token_zhenqi():
    c = Image.new("RGBA", (768, 768), (0, 0, 0, 0))
    c = Image.alpha_composite(c, soft_glow((768, 768), CINNABAR, 250, 85))
    d = ImageDraw.Draw(c)
    cx, cy = 384, 372
    # 投影
    d.ellipse([cx - 170, cy + 200, cx + 170, cy + 268], fill=(0, 0, 0, 85))
    # 穗子（比令牌窄、比之前长，读得出"系着"）
    d.line([(cx, cy + 196), (cx, cy + 300)], fill=GOLD, width=10)
    for i in range(5):
        d.line([(cx, cy + 250), (cx - 48 + i * 24, cy + 352)], fill=(120, 96, 50, 230), width=5)
    d.ellipse([cx - 14, cy + 292, cx + 14, cy + 320], fill=GOLD)
    # 令牌：横宽黑漆牌（不要做成手机）
    d.rounded_rectangle([cx - 156, cy - 196, cx + 156, cy + 196], radius=30,
                        fill=INK, outline=GOLD, width=14)
    d.rounded_rectangle([cx - 140, cy - 180, cx + 140, cy + 180], radius=22,
                        outline=GOLD_L, width=3)
    # 中央柔光：让朱砂大旗从黑底里浮出来
    glow = Image.new("RGBA", (768, 768), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - 132, cy - 150, cx + 132, cy + 150], fill=(214, 92, 72, 60))
    c = Image.alpha_composite(c, glow.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(c)
    # 大旗：金枪头 + 旗杆 + 朱砂旗面（三角 + 内折线）
    pole_x = cx - 54
    d.line([(pole_x, cy - 118), (pole_x, cy + 126)], fill=GOLD, width=10)
    d.polygon([(pole_x, cy - 150), (pole_x - 16, cy - 108), (pole_x + 16, cy - 108)], fill=GOLD_L)
    d.polygon([(pole_x + 4, cy - 112), (cx + 118, cy - 66), (pole_x + 4, cy + 14)],
              fill=CINNABAR)
    d.polygon([(pole_x + 4, cy - 78), (cx + 82, cy - 62), (pole_x + 4, cy - 8)],
              fill=CINNABAR_L)
    d.line([(pole_x + 4, cy - 112), (cx + 118, cy - 66)], fill=(255, 206, 176, 170), width=4)
    # 阵线：大旗底下连三枚旗钉（机制纹样）
    dots = [(cx - 96, cy + 96), (cx + 6, cy + 132), (cx + 96, cy + 84)]
    for a, b in ((0, 1), (1, 2)):
        d.line([dots[a], dots[b]], fill=(214, 92, 72, 235), width=7)
    for i, (px, py) in enumerate(dots):
        d.ellipse([px - 15, py - 15, px + 15, py + 15], fill=(18, 20, 24, 235),
                  outline=GOLD, width=4)
        d.ellipse([px - 7, py - 7, px + 7, py + 7], fill=CINNABAR_L if i != 1 else GOLD_L)
    # 顶部穿绳孔
    d.ellipse([cx - 20, cy - 166, cx + 20, cy - 126], fill=(10, 12, 14, 255),
              outline=GOLD, width=5)
    # 高光
    d.arc([cx - 156, cy - 196, cx + 156, cy + 196], 198, 244, fill=(255, 240, 200, 120), width=6)
    save_icon(c, "tr_zhenqi_ling.png")


if __name__ == "__main__":
    icon_token_zhenqi()
