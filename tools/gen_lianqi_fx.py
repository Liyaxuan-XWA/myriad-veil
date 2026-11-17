#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""青岚古猿的投射物贴图（2026-10-28）。

两只兽共用虎妖的程序化语言，但古猿是木/石属性：
  · ape_boulder  崩石 / 乱石：青灰石 + 苔藓，区别于虎妖的土黄投石
  · ape_orb      青岚灵爆：碧玉色内旋球，没有虎妖的竖瞳
由 tools/gen_skill_fx.py 的同一批 helper 生成，风格与现有技能贴图一致。
用法：python tools/gen_lianqi_fx.py
"""
from __future__ import annotations

import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_skill_fx as gs  # noqa: E402


def gen_ape_boulder() -> None:
    size = 128
    s = 4
    big = size * s
    canvas = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(canvas)
    cx, cy = big * 0.5, big * 0.52
    random.seed(31)
    pts = []
    for i in range(9):
        a = i / 9.0 * math.tau
        rad = big * random.uniform(0.24, 0.39)
        pts.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad * 0.93))
    d.polygon(pts, fill=255)
    mask = np.asarray(canvas.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0
    mask = gs.clamp01(gs.blur(mask, 0.5))
    x, y = gs.grid(size, size)
    light = gs.clamp01(0.60 - (x * 0.48 + y * 0.52) * 0.55)
    n = gs.fbm(size, size, 10.0, 4, 71)
    rgb = gs.mix_color(np.array([0.09, 0.12, 0.10], np.float32),
                       np.array([0.36, 0.42, 0.36], np.float32),
                       gs.clamp01(light * 0.92 + n * 0.24))
    rgb = rgb + np.array([0.72, 0.82, 0.64], np.float32)[None, None, :] \
        * (gs.clamp01(light - 0.48) * 0.45)[..., None]
    # 苔藓：偏上、成片，不盖满整块石头
    moss_n = gs.fbm(size, size, 7.0, 4, 83)
    moss = gs.smoothstep(0.58, 0.82, moss_n * 0.9 + (1.0 - gs.clamp01(y * 0.5 + 0.5)) * 0.22)
    moss *= mask
    rgb = gs.mix_color(rgb, np.array([0.30, 0.50, 0.16], np.float32), moss * 0.72)
    # 苔藓的亮边
    moss_edge = gs.clamp01(moss - gs.blur(moss, 1.4))
    rgb = rgb + np.array([0.62, 0.86, 0.34], np.float32)[None, None, :] * (moss_edge * 0.5)[..., None]
    # 左上轮廓的冷绿边光
    rim = gs.clamp01(mask - gs.blur(mask, 2.2)) * gs.clamp01(0.22 - x - y * 0.3)
    rgb = rgb + np.array([0.68, 0.92, 0.60], np.float32)[None, None, :] * (rim * 1.4)[..., None]
    # 裂纹
    crack_canvas = Image.new("L", (big, big), 0)
    dc = ImageDraw.Draw(crack_canvas)
    for _ in range(4):
        px, py = cx + random.uniform(-big * 0.18, big * 0.18), cy + random.uniform(-big * 0.15, big * 0.15)
        for _seg in range(4):
            nx = px + random.uniform(-big * 0.09, big * 0.09)
            ny = py + random.uniform(-big * 0.09, big * 0.09)
            dc.line([(px, py), (nx, ny)], fill=random.randint(70, 150), width=2)
            px, py = nx, ny
    crack = np.asarray(crack_canvas.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0
    crack *= mask
    rgb = rgb + np.array([0.68, 0.88, 0.50], np.float32)[None, None, :] * (crack * 0.45)[..., None]
    # 外部青绿尘
    halo = gs.clamp01(gs.blur(mask, 7.0) - mask)
    rgb = rgb + np.array([0.30, 0.52, 0.24], np.float32)[None, None, :] * (halo * 0.32)[..., None]
    alpha = gs.clamp01(mask * (0.92 + n * 0.15) + crack * 0.30 + moss * 0.25 + halo * 0.20)
    gs.save("ape_boulder.png", rgb, alpha, cut=0.03)


def gen_ape_orb() -> None:
    size = 160
    x, y = gs.grid(size, size)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    n = gs.fbm(size, size, 11.0, 4, 97)
    n2 = gs.fbm(size, size, 30.0, 3, 101)
    body = gs.smoothstep(0.68, 0.30, r) * (0.55 + 0.45 * n)
    smoke = gs.smoothstep(1.0, 0.35, r) * (0.18 + 0.45 * n2)
    core = np.exp(-((r / 0.17) ** 2))
    iris = np.exp(-((r / 0.30) ** 2)) * (0.7 + 0.3 * n2)
    # 两股缠绕的木叶气流：不是虎妖的金色条纹，也没有竖瞳
    swirl = np.zeros((size, size), np.float32)
    for i in range(2):
        phase = i * math.pi
        band = np.sin(th * 2.0 + np.sin(r * 6.0 + phase) * 1.6 + phase)
        swirl = np.maximum(swirl, gs.smoothstep(0.74, 0.99, band))
    swirl *= gs.smoothstep(0.64, 0.22, r) * (0.55 + 0.45 * n2)
    rim = np.exp(-((r - 0.60) / 0.075) ** 2) * (0.45 + 0.55 * n)
    rgb = gs.mix_color(np.array([0.01, 0.08, 0.05], np.float32),
                       np.array([0.05, 0.36, 0.18], np.float32),
                       gs.clamp01(body * 1.3 + smoke * 0.4))
    rgb = rgb + np.array([0.22, 0.86, 0.36], np.float32)[None, None, :] * (iris * 0.55)[..., None]
    rgb = rgb + np.array([0.78, 1.0, 0.66], np.float32)[None, None, :] * (core * 0.80)[..., None]
    rgb = rgb + np.array([0.50, 0.96, 0.40], np.float32)[None, None, :] * (swirl * 0.60)[..., None]
    rgb = rgb + np.array([0.72, 1.0, 0.56], np.float32)[None, None, :] * (rim * 0.32)[..., None]
    rgb = rgb + np.array([0.16, 0.42, 0.14], np.float32)[None, None, :] * (smoke * 0.35)[..., None]
    alpha = gs.clamp01(body * 0.95 + smoke * 0.5 + core * 0.9 + swirl * 0.55 + rim * 0.35)
    alpha *= gs.smoothstep(1.0, 0.82, r) * gs.edge_window(size, size, 0.06)
    sparks = []
    for _ in range(10):
        a = random.uniform(0, math.tau)
        rad = random.uniform(0.55, 0.92)
        sparks.append((0.5 + math.cos(a) * rad * 0.5, 0.5 + math.sin(a) * rad * 0.5,
                       random.uniform(0.005, 0.012), random.uniform(0.25, 0.7)))
    glints = gs.add_sparks(alpha * 0.16, sparks, np.array([0.60, 1.0, 0.40], np.float32), 1.0)
    rgb = rgb + np.array([0.60, 1.0, 0.40], np.float32)[None, None, :] * glints[..., None] * 0.5
    alpha = gs.clamp01(alpha + glints * 0.4)
    gs.save("ape_orb.png", rgb, alpha, cut=0.08)



def gen_ape_crack() -> None:
    """青岚古猿的砸地裂纹：透明底 + 放射裂痕，不带虎妖那张裂纹贴图的大片灰底。
    虎妖的 heaven_crack_fan 背景是一整块不透明雾，染成绿色会把整个判定圈糊成绿云；
    古猿单独一张，亮痕 + 暗边，贴在地面上读得出是「裂开」而不是「冒烟」。"""
    size = 512
    s = 2
    big = size * s
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    glow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dg = ImageDraw.Draw(glow)
    c = big * 0.5
    random.seed(20261028)
    rays = 8
    for i in range(rays):
        ang = (i / rays) * math.tau + random.uniform(-0.10, 0.10)
        px, py = c, c
        segs = 6
        for k in range(segs):
            t = k / float(segs)
            step = big * random.uniform(0.075, 0.105)
            a2 = ang + random.uniform(-0.20, 0.20)
            nx = px + math.cos(a2) * step
            ny = py + math.sin(a2) * step
            w = max(2, int(big * (0.015 - 0.0022 * k)))
            dark = (8, 26, 13, 210)
            dg.line([(px, py), (nx, ny)], fill=(60, 220, 90, 90), width=w * 3 + 4)
            d.line([(px, py), (nx, ny)], fill=dark, width=w + 2)
            d.line([(px, py), (nx, ny)], fill=(190, 255, 170, 235), width=max(1, w - 1))
            # 分叉
            if 1 <= k <= 3 and random.random() < 0.60:
                b_ang = a2 + random.choice([-1.0, 1.0]) * random.uniform(0.45, 0.95)
                bx = nx + math.cos(b_ang) * step * 0.55
                by = ny + math.sin(b_ang) * step * 0.55
                dg.line([(nx, ny), (bx, by)], fill=(60, 220, 90, 70), width=w * 2 + 3)
                d.line([(nx, ny), (bx, by)], fill=dark, width=max(1, w - 2) + 2)
                d.line([(nx, ny), (bx, by)], fill=(170, 245, 155, 200), width=max(1, w - 3))
            px, py = nx, ny
    glow = glow.filter(ImageFilter.GaussianBlur(big * 0.010))
    out = Image.alpha_composite(glow, img)
    # 碎裂的细屑
    px = np.asarray(out).astype(np.float32)
    for _ in range(90):
        a = random.uniform(0, math.tau)
        r = random.uniform(0.12, 0.46) * big
        xx = int(c + math.cos(a) * r)
        yy = int(c + math.sin(a) * r)
        if 0 <= xx < big and 0 <= yy < big:
            px[yy, xx] = np.array([200, 255, 180, 190], np.float32)
    out = Image.fromarray(px.clip(0, 255).astype(np.uint8), "RGBA")
    out = out.resize((size, size), Image.LANCZOS)
    out.save(os.path.join(gs.OUT, "ape_crack.png"))
    print("saved ape_crack.png", size, "x", size)


def main() -> int:
    random.seed(20261028)
    gen_ape_boulder()
    gen_ape_orb()
    gen_ape_crack()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
