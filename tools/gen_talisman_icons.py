# -*- coding: utf-8 -*-
"""符箓元素图标生成器（技能栏 Q/E/R/T 用，256×256 RGB）。

为什么要自己画：局外七张卡面是 program 生成的，但技能栏小图一直是「金色空白卡框」，
四格摆在一起完全分不出哪张是哪张（实机截图验证过）。AI 出图在 48px 下会糊成色块，
所以这 10 个图标改成**程序化矢量符号**：深墨底 + 元素色笔意符号 + 元素色细边，
保证 48px 下也一眼能认。

统一语言：
  · 深墨圆角底（#191722 → #221f2b），四角压暗，模拟符纸叠在暗处的观感
  · 中央符号走「毛笔中锋」：元素色描边 + 中心提亮 + 外发光
  · 右下角一枚朱砂小印：十张共用，是「这是一张符」的统一记号

用法：
  python tools/gen_talisman_icons.py            # 预览到 output/talisman_icons_preview/
  python tools/gen_talisman_icons.py --apply    # 覆盖 assets/ui/icon/tal_element_*.png
"""

from __future__ import annotations

import math
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "output" / "talisman_icons_preview"
DST = ROOT / "assets" / "ui" / "icon"

W = 256
SS = 4               # 超采样倍数（画布 1024，最后缩到 256）
C = W * SS // 2

# 元素主色（与 ArtDB.ELEMENT_COLORS 同源，改了那边记得同步这里）
PALETTE = {
    "metal": (240, 219, 158),
    "wood": (143, 219, 148),
    "water": (122, 199, 240),
    "fire": (245, 133, 71),
    "earth": (204, 173, 122),
    "wind": (158, 230, 204),
    "thunder": (194, 153, 255),
    "ice": (168, 230, 255),
    "light": (255, 235, 158),
    "dark": (158, 117, 194),
}


# ----------------------------------------------------------------- 基础层
def _rounded_mask(size: int, radius: int) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius, fill=255)
    return m


def base_card() -> Image.Image:
    """深墨圆角底：上浅下深，四角压暗。"""
    size = W * SS
    img = Image.new("RGB", (size, size), (25, 23, 32))
    top = (36, 33, 46)
    bot = (20, 18, 26)
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / float(size - 1)
        col = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=col)
    # 四角压暗，像符纸边缘的阴影
    vig = Image.new("L", (size, size), 0)
    ImageDraw.Draw(vig).rounded_rectangle(
        (int(size * 0.06), int(size * 0.06), int(size * 0.94), int(size * 0.94)),
        int(size * 0.16), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(size * 0.10))
    img = Image.composite(img, Image.new("RGB", (size, size), (12, 11, 16)), vig)
    return img


def stamp_seal(img: Image.Image) -> None:
    """右下角朱砂小印：十张共用的统一记号。"""
    size = W * SS
    d = ImageDraw.Draw(img)
    s = int(size * 0.115)
    x0 = size - int(size * 0.135) - s
    y0 = size - int(size * 0.135) - s
    red = (176, 62, 48)
    d.rounded_rectangle((x0, y0, x0 + s, y0 + s), int(s * 0.22),
                        outline=red, width=max(2, int(s * 0.10)))
    # 印里两道短横（篆书感的抽象笔迹，不写字免得糊）
    for i in range(2):
        y = y0 + int(s * (0.38 + 0.24 * i))
        d.line([(x0 + int(s * 0.24), y), (x0 + s - int(s * 0.24), y)],
               fill=red, width=max(2, int(s * 0.09)))


# ----------------------------------------------------------------- 符号笔画
def _stroke(d: ImageDraw.ImageDraw, pts, width: int, color=255,
            taper: bool = True) -> None:
    """折线/曲线描边；taper 时首尾各收窄一段，做出毛笔起收笔。"""
    if len(pts) < 2:
        return
    n = len(pts)
    for i in range(n - 1):
        w = width
        if taper:
            t = i / float(max(n - 2, 1))
            w = int(width * (0.55 + 0.45 * math.sin(math.pi * min(1.0, t + 0.12))))
        d.line([pts[i], pts[i + 1]], fill=color, width=max(2, w))
    if not taper:
        r = width // 2
        for p in (pts[0], pts[-1]):
            d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=color)


def _arc_pts(cx, cy, rx, ry, a0, a1, n=40):
    return [(cx + rx * math.cos(a0 + (a1 - a0) * i / (n - 1.0)),
             cy + ry * math.sin(a0 + (a1 - a0) * i / (n - 1.0))) for i in range(n)]


# ----------------------------------------------------------------- 十种符胆
def motif_metal(d, u):
    """金锋：一柄竖剑（窄刃 + 护手 + 柄）。"""
    cx, s = C, u
    d.polygon([(cx, C - s * 0.95), (cx + s * 0.20, C - s * 0.62),
               (cx + s * 0.20, C + s * 0.28), (cx - s * 0.20, C + s * 0.28),
               (cx - s * 0.20, C - s * 0.62)], fill=255)
    d.rectangle((cx - s * 0.62, C + s * 0.28, cx + s * 0.62, C + s * 0.40),
                fill=255)
    d.rectangle((cx - s * 0.13, C + s * 0.40, cx + s * 0.13, C + s * 0.86),
                fill=255)
    # 剑脊暗线，让刃有厚度
    d.line([(cx, C - s * 0.86), (cx, C + s * 0.22)], fill=100, width=int(s * 0.07))


def _leaf_pts(cx, cy, ln, wd, ang):
    """柳叶轮廓：沿轴 u、横向 v 的正弦包络，两头收尖。"""
    ca, sa = math.cos(ang), math.sin(ang)
    out = []
    for k in (1, -1):
        rng = range(13) if k > 0 else range(12, -1, -1)
        for i in rng:
            t = i / 12.0
            u = -ln * 0.5 + ln * t
            v = k * wd * 0.5 * math.sin(math.pi * t) ** 0.72
            out.append((cx + u * ca - v * sa, cy + u * sa + v * ca))
    return out


def motif_wood(d, u):
    """木缚：一根竖枝 + 一片大柳叶（48px 下叶片形状比藤蔓更好认）。"""
    cx, s = C, u
    # 主干：从下往上，微微右弯
    _stroke(d, [(cx - s * 0.30, C + s * 0.92), (cx - s * 0.16, C + s * 0.30),
                (cx - s * 0.02, C - s * 0.18)], int(s * 0.20))
    # 大叶：从主干顶端斜向右上
    d.polygon(_leaf_pts(cx + s * 0.16, C - s * 0.10, s * 1.34, s * 0.62,
                        math.radians(-34)), fill=255)
    # 叶脉（半透，让底色透出来形成暗线）
    d.line([(cx - s * 0.12, C - s * 0.02), (cx + s * 0.62, C - s * 0.52)],
           fill=100, width=int(s * 0.09))
    # 根须：两道短斜线
    for sx in (-1, 1):
        _stroke(d, [(cx - s * 0.28, C + s * 0.86),
                    (cx - s * 0.28 + sx * s * 0.34, C + s * 1.02)],
                int(s * 0.11), taper=True)


def _wave_pts(cx, cy, half_w, amp, cycles=1.35, n=52):
    """正弦波浪线：两道浪尖，两端收到同一水平，像水流。"""
    out = []
    for i in range(n):
        t = i / (n - 1.0)
        x = cx - half_w + 2.0 * half_w * t
        y = cy + amp * math.sin(2.0 * math.pi * cycles * t) * math.sin(math.pi * t) ** 0.5
        out.append((x, y))
    return out


def motif_water(d, u):
    """水愈：三道波浪（正弦，不是平弧 —— 平弧在 48px 下像三条横线）。"""
    cx, s = C, u
    for i, (hw, yy, amp, wd) in enumerate([
            (0.56, -0.48, 0.13, 0.150),
            (0.72, 0.00, 0.16, 0.175),
            (0.86, 0.48, 0.19, 0.200)]):
        _stroke(d, _wave_pts(cx, C + s * yy, s * hw, s * amp), int(s * wd))


def motif_fire(d, u):
    """火球：外焰 + 内焰，外焰偏一笔。"""
    cx, s = C, u
    outer = [(cx, C - s * 0.92),
             (cx + s * 0.44, C - s * 0.24), (cx + s * 0.54, C + s * 0.34),
             (cx + s * 0.22, C + s * 0.80),
             (cx - s * 0.30, C + s * 0.80),
             (cx - s * 0.58, C + s * 0.30), (cx - s * 0.34, C - s * 0.26),
             (cx - s * 0.10, C - s * 0.06)]
    d.polygon(outer, fill=255)
    inner = [(cx + s * 0.02, C - s * 0.20),
             (cx + s * 0.26, C + s * 0.16), (cx + s * 0.16, C + s * 0.54),
             (cx - s * 0.16, C + s * 0.54), (cx - s * 0.26, C + s * 0.16)]
    d.polygon(inner, fill=100)


def motif_earth(d, u):
    """石附：三层山岳 + 一道地线。"""
    cx, s = C, u
    d.polygon([(cx - s * 0.90, C + s * 0.56), (cx - s * 0.30, C - s * 0.52),
               (cx + s * 0.16, C + s * 0.56)], fill=255)
    d.polygon([(cx - s * 0.10, C + s * 0.56), (cx + s * 0.36, C - s * 0.26),
               (cx + s * 0.90, C + s * 0.56)], fill=255)
    d.rectangle((cx - s * 0.92, C + s * 0.62, cx + s * 0.92, C + s * 0.76),
                fill=255)


def _rot(pts, cx, cy, ang):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca)
            for x, y in pts]


def motif_wind(d, u):
    """风疾：三道「彡」字风纹，整体上扬 15° + 右端大卷钩。
    ⚠ 别画成水平波浪 —— 那会和水符（蓝色三道浪）撞脸，实机并列时认错。"""
    cx, s = C, u
    for hw, yy, wd, hook in [(0.62, -0.46, 0.155, 0.24),
                             (0.72, 0.00, 0.175, 0.27),
                             (0.62, 0.46, 0.155, 0.24)]:
        y = C + s * yy
        body = _arc_pts(cx - s * 0.06, y, s * hw, s * hw * 0.34,
                        math.radians(203), math.radians(342), 26)
        tail = _arc_pts(cx + s * hw * 0.72, y - s * hook * 0.62,
                        s * hook, s * hook, math.radians(70), math.radians(330), 22)
        pts = _rot(body, cx, y, math.radians(-14)) + _rot(tail, cx, y, math.radians(-14))
        _stroke(d, body, int(s * wd))
        _stroke(d, tail, int(s * wd * 0.80))


def motif_thunder(d, u):
    """引雷：一道标准 Z 形闪电（不画分叉 —— 48px 下分叉会糊成一团）。"""
    cx, s = C, u
    main = [(cx + s * 0.34, C - s * 0.95), (cx - s * 0.06, C - s * 0.08),
            (cx + s * 0.30, C - s * 0.08), (cx - s * 0.26, C + s * 0.95),
            (cx - s * 0.02, C + s * 0.12), (cx - s * 0.34, C + s * 0.12)]
    d.polygon(main, fill=255)


def motif_ice(d, u):
    """凝霜：六角冰晶 + 每角分叉。"""
    cx, s = C, u
    for i in range(6):
        a = math.radians(60 * i - 90)
        tip = (cx + math.cos(a) * s * 0.92, C + math.sin(a) * s * 0.92)
        _stroke(d, [(cx, C), tip], int(s * 0.17), taper=False)
        # 分叉
        for k in (0.52, 0.76):
            base = (cx + math.cos(a) * s * 0.92 * k, C + math.sin(a) * s * 0.92 * k)
            for da in (-40, 40):
                b = a + math.radians(da)
                end = (base[0] + math.cos(b) * s * 0.26, base[1] + math.sin(b) * s * 0.26)
                _stroke(d, [base, end], int(s * 0.10), taper=True)
    d.ellipse((cx - s * 0.12, C - s * 0.12, cx + s * 0.12, C + s * 0.12),
              fill=255)


def motif_light(d, u):
    """折光：菱形棱镜 + 四射光芒。"""
    cx, s = C, u
    d.polygon([(cx, C - s * 0.52), (cx + s * 0.44, C),
               (cx, C + s * 0.52), (cx - s * 0.44, C)], fill=255)
    for i in range(8):
        a = math.radians(45 * i)
        r0 = s * (0.62 if i % 2 == 0 else 0.56)
        r1 = s * (0.94 if i % 2 == 0 else 0.82)
        _stroke(d, [(cx + math.cos(a) * r0, C + math.sin(a) * r0),
                    (cx + math.cos(a) * r1, C + math.sin(a) * r1)],
                int(s * (0.14 if i % 2 == 0 else 0.09)), taper=True)


def motif_dark(d, u):
    """噬元：阿基米德螺线旋涡 + 中心暗核。"""
    cx, s = C, u
    pts = []
    turns = 2.6
    n = 90
    for i in range(n):
        t = i / float(n - 1)
        a = turns * 2.0 * math.pi * t - math.pi * 0.5
        r = s * (0.10 + 0.84 * t)
        pts.append((cx + math.cos(a) * r, C + math.sin(a) * r))
    for i in range(len(pts) - 1):
        t = i / float(len(pts) - 2)
        w = int(s * 0.26 * (1.0 - 0.72 * t))
        d.line([pts[i], pts[i + 1]], fill=255, width=max(3, w))
    d.ellipse((cx - s * 0.20, C - s * 0.20, cx + s * 0.20, C + s * 0.20),
              fill=255)


MOTIFS = {
    "metal": motif_metal, "wood": motif_wood, "water": motif_water, "fire": motif_fire,
    "earth": motif_earth, "wind": motif_wind, "thunder": motif_thunder,
    "ice": motif_ice, "light": motif_light, "dark": motif_dark,
}


# ----------------------------------------------------------------- 合成
def render(elem: str) -> Image.Image:
    size = W * SS
    rgb = PALETTE[elem]
    img = base_card()

    # 1) 符号画到独立掩膜（白=墨迹）
    sig = Image.new("L", (size, size), 0)
    MOTIFS[elem](ImageDraw.Draw(sig), size * 0.30)

    # 2) 外发光：掩膜模糊后按元素色铺一层
    glow = sig.filter(ImageFilter.GaussianBlur(size * 0.055)).point(lambda v: int(v * 0.85))
    glow_layer = Image.new("RGB", (size, size), rgb)
    img = Image.composite(glow_layer, img, glow.point(lambda v: int(v * 0.55)))

    # 3) 墨迹本体：中心提亮（符胆中间发光的观感）
    core = Image.new("RGB", (size, size), rgb)
    hot = tuple(min(255, int(c + (255 - c) * 0.55)) for c in rgb)
    radial = Image.new("L", (size, size), 0)
    rd = ImageDraw.Draw(radial)
    for i in range(28):
        t = i / 27.0
        r = size * (0.50 * (1.0 - t) + 0.06)
        v = int(255 * (1.0 - t))
        rd.ellipse((C - r, C - r, C + r, C + r), fill=v)
    radial = radial.filter(ImageFilter.GaussianBlur(size * 0.05))
    core = Image.composite(Image.new("RGB", (size, size), hot), core, radial)
    img = Image.composite(core, img, sig)

    # 4) 元素色细边：框住图标，48px 下四格颜色一眼可分
    edge = Image.new("L", (size, size), 0)
    ImageDraw.Draw(edge).rounded_rectangle(
        (int(size * 0.035), int(size * 0.035), int(size * 0.965), int(size * 0.965)),
        int(size * 0.13), outline=255, width=max(2, int(size * 0.014)))
    edge = edge.point(lambda v: int(v * 0.72))
    img = Image.composite(Image.new("RGB", (size, size), rgb), img, edge)

    stamp_seal(img)
    return img.resize((W, W), Image.LANCZOS)


def main(argv=None) -> None:
    apply_now = "--apply" in (argv if argv is not None else sys.argv[1:])
    dst = DST if apply_now else OUT
    dst.mkdir(parents=True, exist_ok=True)
    for elem in MOTIFS:
        img = render(elem)
        path = dst / ("tal_element_%s.png" % elem)
        img.save(path, "PNG", optimize=True)
        print("  · %-22s %s %.1fKB" % (path.name, img.size, os.path.getsize(path) / 1024.0))
    if not apply_now:
        print("（预览模式：正式图标未改动。加 --apply 才覆盖 assets/ui/icon/）")


if __name__ == "__main__":
    main()
