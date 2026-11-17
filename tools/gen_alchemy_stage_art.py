"""生成丹炉 / 符案的全屏舞台底图（PIL 程序化占位）。

口径与锻造台一致（docs/美术资源接入记录.md §13/§14）：
  · 画布 1792×1008 = 屏幕 1280×720 × 1.4，背景按 KEEP_ASPECT_COVERED 铺满
  · 屏幕坐标 × 1.4 = 画面坐标，界面上的交互矩形就按这个换算画在画上
  · 这张是**占位图**：正式图用 ImageGen 以它为参考图做图生图重绘，同名覆盖即可，代码零改动

跑法（仓库根）：python tools/gen_alchemy_stage_art.py
"""

import os

from PIL import Image, ImageDraw, ImageFilter

SCALE = 1.4
W, H = int(1280 * SCALE), int(720 * SCALE)          # 1792 × 1008
OUT_ROOT = os.path.join("assets", "ui")


def S(x, y=None):
    """屏幕坐标 → 画面坐标（y 可省略，传元组时也能用）"""
    if isinstance(x, (tuple, list)):
        return (x[0] * SCALE, x[1] * SCALE)
    return x * SCALE if y is None else (x * SCALE, y * SCALE)


def _base(tone):
    """墨底 + 地平 + 上下压暗，非写实的「纸本墨色」基调"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(H):
        k = y / H
        r = int(tone[0][0] + (tone[1][0] - tone[0][0]) * k)
        g = int(tone[0][1] + (tone[1][1] - tone[0][1]) * k)
        b = int(tone[0][2] + (tone[1][2] - tone[0][2]) * k)
        d.line([(0, y), (W, y)], fill=(r, g, b, 255))
    # 地平线：脚下一条暖灰，墙上留墨
    horizon = int(H * 0.66)
    d.rectangle((0, horizon, W, H), fill=(26, 24, 22, 255))
    d.line([(0, horizon), (W, horizon)], fill=(96, 84, 66, 120), width=2)
    return img, d, horizon


def _vignette(img, strength=0.55):
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse((-W * 0.18, -H * 0.18, W * 1.18, H * 1.18), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(90))
    dark = Image.new("RGBA", (W, H), (0, 0, 0, int(255 * strength)))
    inv = Image.eval(mask, lambda v: 255 - v)
    img.paste(dark, (0, 0), inv)
    return img


def _ellipse(d, center, radii, fill=None, outline=None, width=1, steps=64):
    cx, cy = S(center[0], center[1])
    rx, ry = radii[0] * SCALE, radii[1] * SCALE
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=fill, outline=outline, width=width)


def _round(d, rect, radius, fill=None, outline=None, width=1):
    x0, y0 = S(rect[0], rect[1])
    x1, y1 = S(rect[2], rect[3])
    d.rounded_rectangle((x0, y0, x1, y1), radius=radius * SCALE,
                        fill=fill, outline=outline, width=int(width * SCALE))


# ===================== 丹炉舞台 =====================

def build_hearth(path):
    img, d, horizon = _base(((20, 26, 26), (10, 12, 14)))

    # 后墙：一道月门形的墨圈，把「丹房」变成一处空间而不是一块背景板
    _ellipse(d, (640, 300), (300, 300), outline=(74, 104, 92, 70), width=3)
    _ellipse(d, (640, 300), (258, 258), outline=(74, 104, 92, 40), width=2)

    # 石台：炉子坐在地上（屏幕 y 430..500）
    _round(d, (368, 430, 912, 500), 18, fill=(34, 38, 38, 255),
           outline=(96, 108, 96, 110), width=2)
    _round(d, (392, 420, 888, 444), 12, fill=(46, 52, 50, 255))

    # 丹炉炉身：三足圆鼎式，屏幕中心 (640, 330)
    body = (492, 236, 788, 424)
    _round(d, body, 78, fill=(44, 46, 44, 255), outline=(126, 138, 122, 150), width=3)
    # 腹上一条青绿釉光
    _round(d, (516, 300, 764, 352), 26, fill=(58, 82, 68, 200))
    # 双耳
    _round(d, (466, 252, 500, 300), 12, fill=(52, 54, 52, 255), outline=(126, 138, 122, 130))
    _round(d, (780, 252, 814, 300), 12, fill=(52, 54, 52, 255), outline=(126, 138, 122, 130))
    # 三足
    for x in (528, 620, 712):
        _round(d, (x, 418, x + 44, 460), 8, fill=(30, 32, 32, 255),
               outline=(90, 100, 90, 120))

    # 炉口（交互落点：屏幕 516,188,248×124 → 中心 640,250，半径 124,62）
    _ellipse(d, (640, 250), (124, 62), fill=(16, 14, 12, 255),
             outline=(176, 190, 168, 210), width=4)
    _ellipse(d, (640, 250), (100, 46), fill=(74, 44, 20, 230))
    _ellipse(d, (640, 252), (70, 30), fill=(172, 92, 34, 210))
    _ellipse(d, (640, 254), (40, 17), fill=(248, 186, 96, 230))

    # 炉腹观火孔：投进去的株数排在这里（屏幕 640,366）
    _ellipse(d, (640, 366), (140, 30), fill=(22, 20, 18, 240),
             outline=(150, 160, 140, 120), width=2)

    # 火候轨（交互区：屏幕 420,546 560×66）：石槽 + 两端铜墩
    _round(d, (420, 546, 980, 612), 12, fill=(30, 32, 34, 250),
           outline=(112, 118, 104, 150), width=2)
    _round(d, (408, 552, 424, 606), 6, fill=(74, 62, 44, 255), outline=(150, 128, 86, 170))
    _round(d, (976, 552, 992, 606), 6, fill=(74, 62, 44, 255), outline=(150, 128, 86, 170))

    # 出炉盘（屏幕 150,448 240×128）：铜盘 + 盘心浅窝
    _ellipse(d, (270, 512), (118, 60), fill=(48, 40, 30, 250),
             outline=(164, 138, 86, 190), width=3)
    _ellipse(d, (270, 512), (86, 42), fill=(30, 26, 20, 230), outline=(120, 100, 62, 130))

    # 药筐（屏幕 948,140 284×316）：竹木格架，三格
    _round(d, (948, 140, 1232, 456), 14, fill=(38, 34, 28, 240),
           outline=(150, 128, 86, 170), width=3)
    for i in range(1, 5):
        y = 140 + 316 * i / 5.0
        d.line((S(958, y), S(1222, y)), fill=(120, 104, 72, 140), width=int(2 * SCALE))
    d.line((S(962, 150), S(962, 446)), fill=(120, 104, 72, 110), width=int(2 * SCALE))
    d.line((S(1218, 150), S(1218, 446)), fill=(120, 104, 72, 110), width=int(2 * SCALE))

    # 药气交给图生图那一版：程序画的椭圆在暗底上只会读成两个洞

    _vignette(img, 0.5).save(path)
    print("wrote", path)


# ===================== 符案舞台 =====================

def build_desk(path):
    img, d, horizon = _base(((26, 20, 20), (11, 9, 10)))

    # 后墙：朱砂印的一轮大圆，像墙上挂的符纸阵列留下的墨迹
    _ellipse(d, (620, 260), (320, 250), outline=(150, 66, 48, 60), width=3)

    # 符案：一整张长案（屏幕 280..960, 96..470）
    _round(d, (280, 96, 960, 470), 16, fill=(46, 30, 26, 255),
           outline=(150, 96, 68, 160), width=3)
    _round(d, (300, 110, 940, 440), 10, fill=(58, 38, 32, 255))
    # 案上的符纸区（玩法画布：屏幕 300,110 640×330）压一块浅墨垫
    _round(d, (340, 128, 900, 424), 8, fill=(40, 30, 28, 220),
           outline=(176, 132, 96, 120), width=2)
    # 案脚
    for x in (300, 900):
        _round(d, (x, 470, x + 46, 520), 6, fill=(34, 22, 20, 255),
               outline=(112, 72, 54, 130))

    # 笔架（案头右上）：一支悬笔
    d.line((S(846, 130), S(906, 176)), fill=(200, 186, 160, 190), width=int(4 * SCALE))
    _ellipse(d, (910, 180), (10, 10), fill=(150, 60, 42, 230))

    # 皮匣（投料口：屏幕 300,470 260×120）：木匣 + 内衬
    _round(d, (300, 470, 560, 590), 14, fill=(34, 26, 22, 250),
           outline=(158, 104, 70, 190), width=3)
    _round(d, (318, 486, 542, 574), 10, fill=(24, 18, 16, 240))

    # 成符盘（屏幕 600,470 260×120）：青玉盘，与皮匣之间留出提示行
    _ellipse(d, (730, 530), (118, 54), fill=(36, 44, 42, 250),
             outline=(140, 164, 148, 180), width=3)
    _ellipse(d, (730, 530), (86, 38), fill=(24, 30, 28, 230), outline=(110, 128, 116, 120))

    # 皮架（屏幕 960,130 272×320）：横杆挂皮
    _round(d, (960, 130, 1232, 450), 12, fill=(32, 26, 24, 240),
           outline=(150, 96, 68, 160), width=3)
    for i in range(1, 5):
        y = 130 + 320 * i / 5.0
        d.line((S(972, y), S(1220, y)), fill=(116, 76, 56, 140), width=int(2 * SCALE))

    # 案角的墨点装饰：压在皮匣下方，不去占左下的提示区
    _ellipse(d, (240, 620), (52, 26), fill=(18, 16, 16, 200),
             outline=(120, 96, 70, 110), width=2)

    _vignette(img, 0.5).save(path)
    print("wrote", path)


def main():
    for sub in ("alchemy", "talisman"):
        os.makedirs(os.path.join(OUT_ROOT, sub), exist_ok=True)
    build_hearth(os.path.join(OUT_ROOT, "alchemy", "stage_hearth.png"))
    build_desk(os.path.join(OUT_ROOT, "talisman", "stage_desk.png"))


if __name__ == "__main__":
    main()
