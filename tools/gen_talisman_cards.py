#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""符箓卡面生成器 v2（2026-11-02）

用户反馈：现有 7 张卡面中心是空的（只有装饰外框 / 空白椭圆），或者靠 UI 在中间写字，很突兀。
本脚本按「同一套画风 + 每类符一个符胆」重画，一张符的骨架照真实符箓来：

    符头（三台 + 抬头杠）→ 符胆（该五行的主图案，占满中心）→ 符脚（收笔座）
    外圈：朱砂双框 + 内虚线 + 四角云纹 + 边饰朱点

  · 七张共用同一张做旧宣纸与同一套边框 → 一眼是一家
  · 符胆按五行各不相同：火=焰莲、木=缠枝、水=叠浪、金=剑锋、土=山岳、风=卷风、雷=雷篆
  · 同一种五行的四个境界共用一张图（境界由卡面左上角品阶朱印区分）
  · 底部 12% 与左上角留出安静区：talisman_card_view.gd 会在那里叠名称条 / 数量印 / 品阶印

输出：assets/ui/talisman/cards/talisman_card_<elem>.png（640×960 RGBA）
用法：python tools/gen_talisman_cards.py
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 2                       # 2× 绘制再下采样，笔边才有软折感
W, H = 640 * SS, 960 * SS
OUT = Path("assets/ui/talisman/cards")

INK = (52, 33, 24)
PAPER_HI = (233, 210, 166)
PAPER_LO = (199, 170, 122)
CINNABAR = (171, 47, 34)
GOLD = (199, 152, 74)

ELEMENTS: dict[str, dict[str, tuple[int, int, int]]] = {
    "fire":   {"wash": (223, 88, 40),   "deep": (139, 30, 19),   "glint": (250, 209, 126)},
    "wood":   {"wash": (96, 160, 96),   "deep": (33, 80, 54),    "glint": (206, 228, 146)},
    "water":  {"wash": (76, 149, 201),  "deep": (27, 76, 120),   "glint": (214, 239, 248)},
    "metal":  {"wash": (186, 197, 216), "deep": (83, 92, 112),   "glint": (246, 231, 172)},
    "earth":  {"wash": (183, 141, 80),  "deep": (97, 66, 36),    "glint": (233, 201, 139)},
    "wind":   {"wash": (158, 199, 191), "deep": (66, 101, 102),  "glint": (233, 243, 238)},
    "thunder": {"wash": (159, 133, 227), "deep": (63, 47, 122),  "glint": (240, 235, 255)},
}


# --------------------------------------------------------------------------
# 纸 / 笔触
# --------------------------------------------------------------------------
def value_noise(size, cells, seed):
    rng = np.random.default_rng(seed)
    g = rng.random((max(2, cells), max(2, int(cells * size[1] / size[0]))))
    im = Image.fromarray((g * 255).astype(np.uint8), "L").resize(size, Image.BICUBIC)
    return np.asarray(im, dtype=np.float32) / 255.0


def fbm(size, base_cells, seed, octaves=4):
    acc = np.zeros((size[1], size[0]), dtype=np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        acc += value_noise(size, base_cells * (2 ** o), seed + o * 97) * amp
        total += amp
        amp *= 0.55
    return acc / total


def paper_layer(seed):
    n = fbm((W, H), 6, seed, 5)
    m = fbm((W, H), 22, seed + 11, 4)
    lo = np.array(PAPER_LO, np.float32)
    hi = np.array(PAPER_HI, np.float32)
    t = 0.40 * n + 0.60 * m
    f = hi[None, None, :] * (1 - t[..., None]) + lo[None, None, :] * t[..., None]
    # 纸筋（横向细丝）+ 竖向帘纹
    f *= 1 - 0.05 * (value_noise((W, H), 170, seed + 31) > 0.88)[:, :, None]
    f *= 1 - 0.03 * (value_noise((W, H), 90, seed + 57) > 0.93)[:, :, None]
    f *= np.random.default_rng(seed + 7).normal(1.0, 0.020, (H, W, 1))
    img = Image.fromarray(np.clip(f, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    rng = random.Random(seed)
    for _ in range(60):
        x, y = rng.randint(24, W - 24), rng.randint(24, H - 24)
        r = rng.randint(5, 20)
        d.ellipse([x - r, y - int(r * .65), x + r, y + int(r * .65)],
                  fill=(128, 94, 52, rng.randint(7, 20)))
    return img


def stamp(layer, pts, w0, w1, color, seed=0, taper=1.25, density=2.4):
    """沿折线撒圆点：w0→w1 宽度插值 + sin 剖面 → 起收笔有锋的毛笔条。"""
    if len(pts) < 2:
        return
    a = np.asarray(pts, np.float32)
    seg = np.linalg.norm(np.diff(a, axis=0), axis=1)
    total = float(seg.sum())
    if total <= 1:
        return
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    n = max(8, int(total / (density * SS)))
    rng = random.Random(seed)
    d = ImageDraw.Draw(layer, "RGBA")
    for i in range(n + 1):
        t = i / n
        s = total * t
        k = min(max(int(np.searchsorted(cum, s, "right")) - 1, 0), len(a) - 2)
        p = a[k] + (a[k + 1] - a[k]) * ((s - cum[k]) / max(seg[k], 1e-3))
        prof = math.sin(math.pi * min(max(t, 0.001), 0.999)) ** (1 / taper)
        w = (w0 + (w1 - w0) * t) * (0.35 + 0.65 * prof)
        r = max(0.8, w * 0.5)
        jx = p[0] + rng.uniform(-.4, .4) * SS
        jy = p[1] + rng.uniform(-.4, .4) * SS
        d.ellipse([jx - r, jy - r, jx + r, jy + r], fill=color)


def quad(p0, p1, p2, n=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / n for i in range(n + 1))]


def arc(cx, cy, r, a0, a1, n=48):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n),
             cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def flame_tongue(cx, base_y, tip_y, half_w, bend):
    """一片火舌的轮廓点（左右两条贝塞尔拼成闭合体）。"""
    mid = (base_y + tip_y) * 0.5
    right = quad((cx + half_w * 0.42, base_y), (cx + half_w + bend, mid),
                 (cx + bend * 1.7, tip_y), 26)
    left = list(reversed(quad((cx - half_w * 0.42, base_y),
                              (cx - half_w * 0.9 + bend, mid),
                              (cx + bend * 1.7, tip_y), 26)))
    return right + left


def leaf_poly(cx, cy, ang, ln, wd):
    tip = (cx + math.cos(ang) * ln, cy + math.sin(ang) * ln)
    base = (cx - math.cos(ang) * ln * .1, cy - math.sin(ang) * ln * .1)
    nrm = ang + math.pi / 2
    c1 = (cx + math.cos(ang) * ln * .5 + math.cos(nrm) * wd,
          cy + math.sin(ang) * ln * .5 + math.sin(nrm) * wd)
    c2 = (cx + math.cos(ang) * ln * .5 - math.cos(nrm) * wd,
          cy + math.sin(ang) * ln * .5 - math.sin(nrm) * wd)
    return [base] + quad(base, c1, tip, 14) + list(reversed(quad(base, c2, tip, 14)))


# --------------------------------------------------------------------------
# 符头 / 符脚（真实符箓的上下结构，顺手把「中心空、上下空」补掉）
# --------------------------------------------------------------------------
def draw_head(sig, cx, y, s, deep, wash):
    stamp(sig, [(cx - s * .52, y), (cx + s * .52, y)], 20 * SS * .5, 20 * SS * .5,
          INK + (225,), seed=900)
    for i, ox in enumerate((-.30, 0.0, .30)):
        stamp(sig, [(cx + ox * s, y - s * .20), (cx + ox * s, y + s * .02)],
              15 * SS * .5, 4 * SS * .5, CINNABAR + (225,), seed=910 + i)
    stamp(sig, arc(cx, y - s * .26, s * .17, math.pi * .12, math.pi * .88),
          11 * SS * .5, 11 * SS * .5, wash + (200,), seed=920)


def draw_foot(sig, cx, y, s, deep, wash):
    stamp(sig, [(cx - s * .46, y), (cx + s * .46, y)], 17 * SS * .5, 17 * SS * .5,
          INK + (215,), seed=930)
    for i, ox in enumerate((-.22, .22)):
        stamp(sig, quad((cx + ox * s, y), (cx + ox * s * 1.5, y + s * .12),
                        (cx + ox * s * .6, y + s * .22), 18),
              13 * SS * .5, 2 * SS * .5, deep + (215,), seed=940 + i)
    stamp(sig, [(cx - s * .10, y + s * .03), (cx + s * .12, y + s * .20)],
          12 * SS * .5, 2 * SS * .5, wash + (205,), seed=950)


# --------------------------------------------------------------------------
# 七个符胆（都用「大宽度填色 + 墨线压边 + 高光」叠出体积，不画空心线稿）
# --------------------------------------------------------------------------
def motif_fire(surf, pal, rng, cx, cy, s):
    _, wash, deep, glint = pal
    d = ImageDraw.Draw(surf, "RGBA")
    for k in range(3):  # 莲座
        y = cy + s * (.86 - k * .05)
        stamp(surf, arc(cx, y, s * (.62 - k * .10), math.pi * 1.12, math.pi * 1.88),
              (26 - k * 5) * SS * .5, (26 - k * 5) * SS * .5,
              deep + (min(255, 150 + k * 25),), seed=1000 + k)
    tongues = [(-.44, .52, -.16), (-.20, .74, -.06), (0.0, .96, .02),
               (.20, .74, .10), (.44, .52, .18)]
    for i, (ox, hh, bend) in enumerate(tongues):
        bx = cx + ox * s
        base = cy + s * .78
        tip = cy - s * hh
        hw = s * .17 * (1 - abs(ox) * .45)
        body = flame_tongue(bx, base, tip, hw, bend * s * .35)
        d.polygon(body, fill=wash + (165,))
        inner = flame_tongue(bx, base - s * .06, tip + s * .16, hw * .52, bend * s * .30)
        d.polygon(inner, fill=glint + (150,))
        stamp(surf, body + [body[0]], 9 * SS * .5, 9 * SS * .5, deep + (205,), seed=1010 + i)
    for _ in range(34):  # 上升火星
        x = cx + rng.uniform(-.62, .62) * s
        y = cy + rng.uniform(-1.05, .55) * s
        r = rng.uniform(1.6, 4.6) * SS * .5
        d.ellipse([x - r, y - r, x + r, y + r], fill=glint + (rng.randint(80, 190),))


def motif_wood(surf, pal, rng, cx, cy, s):
    _, wash, deep, glint = pal
    d = ImageDraw.Draw(surf, "RGBA")
    pts = []
    for i in range(141):
        t = i / 140
        ang = -1.9 + t * math.pi * 3.4
        r = s * (.16 + .70 * t)
        pts.append((cx + r * math.cos(ang) * .80, cy - s * .04 + r * math.sin(ang) * .58))
    stamp(surf, pts, 46 * SS * .5, 6 * SS * .5, deep + (215,), seed=2000)
    stamp(surf, pts, 26 * SS * .5, 3 * SS * .5, wash + (205,), seed=2001)
    stamp(surf, pts, 9 * SS * .5, 1 * SS * .5, glint + (120,), seed=2002)
    for k in range(9):
        t = .10 + k * .095
        p = pts[int(t * (len(pts) - 1))]
        side = 1 if k % 2 == 0 else -1
        ang = side * (1.35 - .5 * math.sin(k * 1.7))
        ln = s * (.40 - t * .13)
        d.polygon(leaf_poly(p[0], p[1], ang, ln, ln * .34), fill=wash + (185,))
        d.polygon(leaf_poly(p[0], p[1], ang, ln * .72, ln * .20), fill=deep + (150,))
        stamp(surf, [(p[0], p[1]), (p[0] + math.cos(ang) * ln, p[1] + math.sin(ang) * ln)],
              5 * SS * .5, 1 * SS * .5, INK + (150,), seed=2010 + k)
    for _ in range(16):
        x = cx + rng.uniform(-.6, .6) * s
        y = cy + rng.uniform(-.8, .7) * s
        r = rng.uniform(2.4, 5.6) * SS * .5
        d.ellipse([x - r, y - r, x + r, y + r], fill=glint + (rng.randint(70, 150),))


def motif_water(surf, pal, rng, cx, cy, s):
    _, wash, deep, glint = pal
    d = ImageDraw.Draw(surf, "RGBA")
    for k in range(4):  # 四层叠浪，越上越小
        y0 = cy + s * (.74 - k * .40)
        amp = s * (.30 - k * .045)
        ln = s * (.86 - k * .10)
        top = [(cx - ln + i / 70 * ln * 2,
                y0 - amp * math.sin(i / 70 * math.pi * 1.35 + k * .4)) for i in range(71)]
        bot = [(x, y + s * (.20 - k * .02)) for x, y in reversed(top)]
        d.polygon(top + bot, fill=wash + (150,))
        stamp(surf, top, (24 - k * 3) * SS * .5, 4 * SS * .5, deep + (220,), seed=3000 + k)
        stamp(surf, top, 7 * SS * .5, 1 * SS * .5, glint + (160,), seed=3010 + k)
        head = top[-1]
        stamp(surf, arc(head[0] - s * .02, head[1] - s * .10, s * .15, -.5, 3.6),
              13 * SS * .5, 1.5 * SS * .5, glint + (200,), seed=3020 + k)
    for _ in range(26):
        x = cx + rng.uniform(-.8, .8) * s
        y = cy + rng.uniform(-.9, .8) * s
        r = rng.uniform(2.0, 6.0) * SS * .5
        d.polygon([(x, y - r * 1.5), (x + r, y + r * .4), (x - r, y + r * .4)],
                  fill=wash + (rng.randint(90, 170),))


def motif_metal(surf, pal, rng, cx, cy, s):
    _, wash, deep, glint = pal
    d = ImageDraw.Draw(surf, "RGBA")
    tip, hilt = cy - s * .96, cy + s * .60
    half = lambda y: s * .145 * math.sqrt(max(0.0, (y - tip) / (hilt - tip)))
    left = [(cx - half(y), y) for y in range(int(tip), int(hilt), 6)]
    right = [(cx + half(y), y) for y in range(int(hilt), int(tip), -6)]
    d.polygon([(cx, tip)] + right + left, fill=(226, 232, 242, 242))
    d.polygon([(cx, tip + s * .04), (cx + half(cy) * .45, hilt - 4),
               (cx - half(cy) * .45, hilt - 4)], fill=(252, 253, 255, 200))
    stamp(surf, [(cx, tip), (cx, hilt)], 5 * SS * .5, 5 * SS * .5, deep + (170,), seed=4000)
    d.polygon([(cx, tip), (cx + half(tip + s * .2), tip + s * .2),
               (cx, tip + s * .30), (cx - half(tip + s * .2), tip + s * .2)],
              fill=glint + (150,))
    for y, w in [(hilt, 34), (hilt + s * .09, 15)]:  # 格 + 束
        stamp(surf, [(cx - s * .40, y), (cx + s * .40, y)], w * SS * .5, w * SS * .5,
              GOLD + (235,), seed=int(4010 + y))
    d.rounded_rectangle([cx - s * .07, hilt + s * .12, cx + s * .07, hilt + s * .40],
                        radius=5 * SS, fill=deep + (240,), outline=GOLD + (200,), width=2 * SS)
    d.ellipse([cx - s * .10, hilt + s * .40, cx + s * .10, hilt + s * .60],
              fill=GOLD + (235,))
    for k in range(10):  # 放射剑光
        ang = -math.pi / 2 + (k - 4.5) * .34
        r0, r1 = s * .46, s * (.72 + .12 * (k % 3))
        stamp(surf, [(cx + math.cos(ang) * r0, cy + math.sin(ang) * r0 * .92),
                     (cx + math.cos(ang) * r1, cy + math.sin(ang) * r1 * .92)],
              9 * SS * .5, .8 * SS * .5, glint + (140,), seed=4030 + k)


def motif_earth(surf, pal, rng, cx, cy, s):
    _, wash, deep, glint = pal
    d = ImageDraw.Draw(surf, "RGBA")
    box = s * .80
    for i, (pa, pb) in enumerate([
            ((cx - box, cy - box * 1.16), (cx + box, cy - box * 1.16)),
            ((cx + box, cy - box * 1.16), (cx + box, cy + box * 1.16)),
            ((cx + box, cy + box * 1.16), (cx - box, cy + box * 1.16)),
            ((cx - box, cy + box * 1.16), (cx - box, cy - box * 1.16))]):
        stamp(surf, [pa, pb], 22 * SS * .5, 22 * SS * .5, CINNABAR + (220,), seed=5000 + i)
    ranges = [[(-.90, .78), (-.34, -.30), (.02, .34)],
              [(-.14, .40), (.36, -.86), (.92, .46)]]
    for k, pk in enumerate(ranges):
        poly = [(cx + a * box, cy + b * box) for a, b in pk]
        poly += [(cx + pk[-1][0] * box, cy + .80 * box), (cx + pk[0][0] * box, cy + .80 * box)]
        d.polygon(poly, fill=wash + (185,))
        d.polygon([(p[0], p[1] - box * .10) for p in poly[:3]] + [poly[1]], fill=glint + (70,))
        stamp(surf, [(cx + a * box, cy + b * box) for a, b in pk],
              15 * SS * .5, 5 * SS * .5, deep + (235,), seed=5010 + k)
    for k in range(5):
        y = cy + box * (.30 + k * .12)
        stamp(surf, [(cx - box * .78, y), (cx + box * .78, y - box * .06)],
              6 * SS * .5, 6 * SS * .5, deep + (120,), seed=5020 + k)
    for _ in range(16):
        x = cx + rng.uniform(-.62, .62) * box
        y = cy + rng.uniform(-.92, .55) * box
        stamp(surf, [(x, y), (x + rng.uniform(-16, 16) * SS, y + rng.uniform(8, 22) * SS)],
              5 * SS * .5, 1 * SS * .5, glint + (130,), seed=5030)


def motif_wind(surf, pal, rng, cx, cy, s):
    _, wash, deep, glint = pal
    d = ImageDraw.Draw(surf, "RGBA")
    for k in range(4):  # 四条风带：S 形 + 末端卷涡，带身有厚度
        y0 = cy + s * (.80 - k * .50)
        amp = s * (.20 + k * .02)
        top = [(cx - s * .88 + i / 80 * s * 1.62,
                y0 - amp * math.sin(i / 80 * math.pi * 1.75 + k * .55)) for i in range(81)]
        bot = [(x, y + s * (.10 - k * .012)) for x, y in reversed(top)]
        d.polygon(top + bot, fill=wash + (150,))
        curl = arc(top[-1][0] + s * .05, top[-1][1] - s * .12, s * (.16 - k * .02),
                   -2.7, 1.7)
        stamp(surf, top + curl, (26 - k * 3) * SS * .5, 2 * SS * .5, deep + (215,), seed=6000 + k)
        stamp(surf, top, 6 * SS * .5, 1 * SS * .5, glint + (150,), seed=6010 + k)
    for k, (ox, oy, r) in enumerate([(-.50, -.86, .24), (.46, .82, .20)]):  # 两朵云
        head = arc(cx + ox * s, cy + oy * s, r * s, math.pi * .06, math.pi * 1.66)
        stamp(surf, head, 22 * SS * .5, 4 * SS * .5, deep + (195,), seed=6020 + k)
        stamp(surf, [(head[-1][0], head[-1][1]),
                     (head[-1][0] - r * s * 1.7, head[-1][1] + r * s * .55)],
              14 * SS * .5, 1 * SS * .5, deep + (175,), seed=6030 + k)
    for _ in range(22):
        x = cx + rng.uniform(-.85, .85) * s
        y = cy + rng.uniform(-.95, .95) * s
        stamp(surf, [(x, y), (x + rng.uniform(12, 30) * SS, y - 4 * SS)],
              5 * SS * .5, 1 * SS * .5, glint + (120,), seed=6040)


def motif_thunder(surf, pal, rng, cx, cy, s):
    _, wash, deep, glint = pal
    d = ImageDraw.Draw(surf, "RGBA")
    bolt = [(cx + s * .14, cy - s * 1.02), (cx - s * .26, cy - s * .18),
            (cx + s * .04, cy - s * .12), (cx - s * .30, cy + s * .62),
            (cx + s * .02, cy + s * .06), (cx - s * .14, cy + s * .00),
            (cx + s * .32, cy - s * .58)]
    for w, col, sd in [(54, deep + (225,), 7000), (34, wash + (225,), 7001),
                       (12, glint + (245,), 7002)]:
        stamp(surf, bolt, w * SS * .5, 6 * SS * .5, col, seed=sd, taper=1.05)
    branch = [(cx - s * .20, cy - s * .42), (cx - s * .56, cy - s * .10),
              (cx - s * .34, cy - s * .04), (cx - s * .66, cy + s * .30)]
    for w, col, sd in [(26, deep + (210,), 7010), (13, glint + (220,), 7011)]:
        stamp(surf, branch, w * SS * .5, 2 * SS * .5, col, seed=sd)
    for k, (ox, oy) in enumerate([(-.70, -.74), (.70, -.74), (-.70, .82), (.70, .82)]):
        x, y = cx + ox * s, cy + oy * s
        r = s * .20
        d.ellipse([x - r, y - r, x + r, y + r], fill=deep + (235,),
                  outline=GOLD + (235,), width=3 * SS)
        d.ellipse([x - r * .58, y - r * .58, x + r * .58, y + r * .58], fill=wash + (225,))
        for a in range(4):  # 鼓钉
            ang = a * math.pi / 2 + .4
            rr = r * 1.24
            d.ellipse([x + math.cos(ang) * rr - 4 * SS, y + math.sin(ang) * rr - 4 * SS,
                       x + math.cos(ang) * rr + 4 * SS, y + math.sin(ang) * rr + 4 * SS],
                      fill=GOLD + (230,))
    for _ in range(30):
        x = cx + rng.uniform(-.85, .85) * s
        y = cy + rng.uniform(-1.0, .95) * s
        ln = rng.uniform(8, 26) * SS
        ang = rng.uniform(0, math.pi * 2)
        stamp(surf, [(x, y), (x + math.cos(ang) * ln, y + math.sin(ang) * ln)],
              5 * SS * .5, .6 * SS * .5, glint + (rng.randint(100, 200),), seed=7020)


MOTIFS = {"fire": motif_fire, "wood": motif_wood, "water": motif_water,
          "metal": motif_metal, "earth": motif_earth,
          "wind": motif_wind, "thunder": motif_thunder}


# --------------------------------------------------------------------------
# 边框 / 安静区
# --------------------------------------------------------------------------
def draw_frame(surf, rng):
    m = 30 * SS
    for pad, w, a in [(0, 19, 235), (17, 7, 190)]:
        x0, y0, x1, y1 = m + pad, m + pad, W - m - pad, H - m - pad
        for i, (pa, pb) in enumerate([[(x0, y0), (x1, y0)], [(x1, y0), (x1, y1)],
                                      [(x1, y1), (x0, y1)], [(x0, y1), (x0, y0)]]):
            pts = []
            for k in range(52):
                t = k / 51
                wob = rng.uniform(-1.5, 1.5) * SS
                horiz = abs(pb[0] - pa[0]) > abs(pb[1] - pa[1])
                pts.append((pa[0] + (pb[0] - pa[0]) * t + (0 if horiz else wob),
                            pa[1] + (pb[1] - pa[1]) * t + (wob if horiz else 0)))
            stamp(surf, pts, w * SS * .5, w * SS * .5, CINNABAR + (a,), seed=8000 + i)
    # 内虚线
    di = ImageDraw.Draw(surf, "RGBA")
    mi = m + 30 * SS
    for pos in range(mi, W - mi, int(16 * SS)):
        di.line([(pos, mi), (pos + 7 * SS, mi)], fill=CINNABAR + (120,), width=2 * SS)
        di.line([(pos, H - mi), (pos + 7 * SS, H - mi)], fill=CINNABAR + (120,), width=2 * SS)
    for pos in range(mi, H - mi, int(16 * SS)):
        di.line([(mi, pos), (mi, pos + 7 * SS)], fill=CINNABAR + (120,), width=2 * SS)
        di.line([(W - mi, pos), (W - mi, pos + 7 * SS)], fill=CINNABAR + (120,), width=2 * SS)
    # 四角云纹
    for k, (sx, sy) in enumerate([(1, 1), (-1, 1), (1, -1), (-1, -1)]):
        cx = m + 34 * SS if sx > 0 else W - m - 34 * SS
        cy = m + 34 * SS if sy > 0 else H - m - 34 * SS
        r = 26 * SS
        stamp(surf, arc(cx, cy, r, .3, 2.6), 13 * SS * .5, 3 * SS * .5,
              GOLD + (225,), seed=8100 + k)
        stamp(surf, arc(cx + sx * r * .62, cy + sy * r * .26, r * .46, .2, 4.6),
              9 * SS * .5, 2 * SS * .5, GOLD + (195,), seed=8110 + k)
        stamp(surf, [(cx - sx * r * 1.15, cy + sy * r * 1.0),
                     (cx + sx * r * 1.55, cy + sy * r * 1.0)],
              10 * SS * .5, 2 * SS * .5, CINNABAR + (190,), seed=8120 + k)
    # 边饰朱点
    for k in range(9):
        t = (k + 1) / 10
        for x, y in [(m + 8 * SS, m + (H - 2 * m) * t), (W - m - 8 * SS, m + (H - 2 * m) * t)]:
            di.ellipse([x - 3 * SS, y - 3 * SS, x + 3 * SS, y + 3 * SS],
                       fill=CINNABAR + (150,))


def quiet_zones(surf):
    """底部名称条 + 左上角品阶印留出干净纸面（UI 会在这些地方叠字与印章）。"""
    d = ImageDraw.Draw(surf, "RGBA")
    top = int(H * .872)
    for y in range(top, H):
        t = (y - top) / max(1, H - top)
        d.line([(0, y), (W, y)], fill=(228, 204, 160, int(165 * min(1.0, t * 2.0))))
    d.rounded_rectangle([8 * SS, 8 * SS, 70 * SS, 66 * SS], radius=4 * SS,
                        fill=(226, 202, 158, 120))


def render(elem):
    seed = sum(ord(c) for c in elem) * 13 + 7
    rng = random.Random(seed)
    img = paper_layer(seed)
    e = ELEMENTS[elem]
    pal = (INK, e["wash"], e["deep"], e["glint"])
    cx, cy, s = W * .5, H * .475, H * .255

    # 符胆背后一层极淡的水彩晕（不是糊光球：压到很低透明度并放大到接近整张卡）
    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.ellipse([cx - s * 1.55, cy - s * 1.75, cx + s * 1.55, cy + s * 1.75],
               fill=e["wash"] + (26,))
    halo = halo.filter(ImageFilter.GaussianBlur(70))
    img.alpha_composite(halo)

    sig = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_head(sig, cx, cy - s * 1.16, s, e["deep"], e["wash"])
    MOTIFS[elem](sig, pal, rng, cx, cy, s)
    draw_foot(sig, cx, cy + s * 1.20, s, e["deep"], e["wash"])
    img.alpha_composite(sig)

    draw_frame(img, rng)
    quiet_zones(img)
    grain = Image.effect_noise((W, H), 18).convert("L")
    img = Image.composite(Image.new("RGBA", (W, H), (98, 72, 44, 26)), img,
                          grain.point(lambda v: max(0, v - 172)))
    img = Image.composite(Image.new("RGBA", (W, H), (58, 40, 26, 34)), img,
                          Image.fromarray((fbm((W, H), 5, seed + 71, 3) * 60)
                                          .clip(0, 46).astype(np.uint8), "L"))
    return img.resize((640, 960), Image.LANCZOS).convert("RGBA")


def main(argv=None):
    """默认只写到 output/ 预览，不碰正式素材。
    确认观感可以了再 `python tools/gen_talisman_cards.py --apply` 覆盖卡面。
    （正式卡面没进 git，覆盖不可恢复。）
    """
    apply = "--apply" in (argv if argv is not None else sys.argv[1:])
    dst = OUT if apply else Path("output/talisman_cards_preview")
    dst.mkdir(parents=True, exist_ok=True)
    for elem in ELEMENTS:
        img = render(elem)
        path = dst / f"talisman_card_{elem}.png"
        img.save(path)
        print("  ·", path, img.size)
    if not apply:
        print("（预览模式：正式卡面未改动。加 --apply 才会覆盖）")


if __name__ == "__main__":
    main()
