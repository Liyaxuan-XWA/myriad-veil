"""Generate procedural VFX textures for player skills.

Run from the project root:
    python tools/gen_skill_fx.py

All images are saved into assets/effects/skills/. They are soft, additive-friendly
RGBA sprites; the project can later replace any of them without touching code.
"""

from __future__ import annotations

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "effects", "skills")
os.makedirs(OUT, exist_ok=True)

RNG = np.random.default_rng(20261025)
random.seed(20261025)


def clamp01(a):
    return np.clip(a, 0.0, 1.0)


def smoothstep(e0, e1, x):
    denom = e1 - e0
    if abs(denom) < 1e-6:
        denom = 1e-6 if denom >= 0.0 else -1e-6
    t = np.clip((x - e0) / denom, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    if isinstance(a, np.ndarray) or isinstance(b, np.ndarray):
        return a + (b - a) * t
    return a + (b - a) * t


def mix_color(a, b, t):
    a = np.asarray(a, dtype=np.float32)
    b = np.asarray(b, dtype=np.float32)
    if a.ndim == 1:
        a = a[None, None, :]
    if b.ndim == 1:
        b = b[None, None, :]
    return a + (b - a) * t[..., None]


def grid(w, h):
    xs = np.linspace(-1.0, 1.0, w, dtype=np.float32)
    ys = np.linspace(-1.0, 1.0, h, dtype=np.float32)
    return np.meshgrid(xs, ys)


def value_noise(w, h, cells, seed):
    rng = np.random.default_rng(seed)
    gw = max(2, int(cells))
    gh = max(2, int(cells * h / max(w, 1)))
    small = (rng.random((gh, gw)) * 255).astype(np.uint8)
    img = Image.fromarray(small).resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def fbm(w, h, cells=8.0, octaves=4, seed=0):
    total = np.zeros((h, w), dtype=np.float32)
    amp = 0.5
    norm = 0.0
    for i in range(octaves):
        total += value_noise(w, h, cells / (2 ** i), seed + i * 17) * amp
        norm += amp
        amp *= 0.5
    return total / max(norm, 1e-6)


def blur(a, radius):
    img = Image.fromarray(np.uint8(clamp01(a) * 255))
    img = img.filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(img, dtype=np.float32) / 255.0


def edge_window(h, w, margin=0.05):
    xs = np.linspace(0.0, 1.0, w, dtype=np.float32)
    ys = np.linspace(0.0, 1.0, h, dtype=np.float32)
    fx = smoothstep(0.0, margin, xs) * smoothstep(1.0, 1.0 - margin, xs)
    fy = smoothstep(0.0, margin, ys) * smoothstep(1.0, 1.0 - margin, ys)
    return fy[:, None] * fx[None, :]


def save(name, rgb, alpha, cut=0.0):
    rgb = clamp01(np.asarray(rgb, dtype=np.float32))
    alpha = clamp01(np.asarray(alpha, dtype=np.float32))
    if cut > 0.0:
        # 去掉极低 alpha 的暗红雾底，避免整张方图在游戏里读成“黑方块”
        alpha = clamp01((alpha - cut) / max(1.0 - cut, 1e-6))
    if rgb.ndim == 2:
        rgb = np.dstack([rgb, rgb, rgb])
    rgba = np.dstack([rgb, alpha])
    Image.fromarray((rgba * 255.0).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))
    print("saved", name, rgba.shape[1], "x", rgba.shape[0])


def add_sparks(dst, positions, color, strength=1.0):
    """Small gaussian glints, positions are (x, y) in 0..1."""
    h, w = dst.shape
    ys = np.arange(h, dtype=np.float32)[:, None]
    xs = np.arange(w, dtype=np.float32)[None, :]
    for px, py, r, a in positions:
        cx, cy = px * (w - 1), py * (h - 1)
        rad = max(r * w, 1.0)
        g = np.exp(-(((xs - cx) ** 2 + (ys - cy) ** 2) / (rad * rad)))
        dst += g * a * strength
    return dst


def compose_glow(color_a, color_b, energy, core, core_color, alpha_extra=0.0):
    """Blend a body color with a hot core, returning rgb + alpha."""
    body = mix_color(color_a, color_b, clamp01(energy * 1.15))
    rgb = body + np.asarray(core_color, dtype=np.float32)[None, None, :] * core[..., None]
    alpha = clamp01(energy * 0.85 + core * 0.9 + alpha_extra)
    return rgb, alpha


# ---------------------------------------------------------------- blade qi
def gen_blade_qi():
    w = h = 256
    x, y = grid(w, h)
    cx, cy = 0.0, -0.04
    dx = x - cx
    dy = y - cy
    r = np.sqrt(dx * dx + dy * dy)
    theta = np.degrees(np.arctan2(dy, dx))
    n = fbm(w, h, 42.0, 3, 11)
    n2 = fbm(w, h, 15.0, 3, 31)
    # Jagged, slightly asymmetric wake instead of a perfect smile.
    rr = r + (n - 0.5) * 0.045
    ang = smoothstep(2.0, 24.0, theta) * (1.0 - smoothstep(158.0, 178.0, theta))
    ang *= 0.72 + 0.42 * fbm(w, h, 20.0, 2, 13)
    ang = clamp01(ang)
    edge = smoothstep(1.02, 0.92, r) * smoothstep(0.22, 0.34, r)
    lead = np.exp(-(((rr - 0.835) / 0.026) ** 2)) * ang
    hot = np.exp(-(((rr - 0.78) / 0.058) ** 2)) * ang
    body = np.exp(-(((rr - 0.70) / 0.115) ** 2)) * ang * (0.42 + 0.82 * n)
    inner = np.exp(-(((rr - 0.55) / 0.21) ** 2)) * ang * (0.22 + 0.6 * n2)
    # The blade's wake streaming back from the leading edge.
    wake = np.exp(-((x / 0.075) ** 2)) * smoothstep(0.62, -0.64, y) * (0.35 + 0.65 * n2)
    wake *= 0.75
    # Two sharp horns / licks.
    licks = np.exp(-(((np.abs(dx) - 0.43) / 0.055) ** 2)) * smoothstep(-0.1, -0.8, dy) * 0.35
    licks *= 0.45 + 0.65 * n2
    energy = (body * 0.85 + inner * 0.30 + wake * 0.55 + licks * 0.6) * edge
    core = (lead * (0.50 + 0.50 * n) + wake * 0.25) * edge
    deep = np.array([0.30, 0.045, 0.02], np.float32)
    ember = np.array([1.0, 0.34, 0.06], np.float32)
    orange = np.array([1.0, 0.53, 0.14], np.float32)
    gold = np.array([1.0, 0.80, 0.36], np.float32)
    rgb = mix_color(deep, ember, clamp01(energy * 1.5))
    rgb = rgb + orange[None, None, :] * (energy * 0.4)[..., None]
    rgb = rgb + gold[None, None, :] * (core * 0.9)[..., None]
    rgb = rgb + np.array([1.0, 0.97, 0.88], np.float32)[None, None, :] * (core * 0.5)[..., None]
    alpha = clamp01(energy * 0.95 + core * 1.2 + licks * 0.4)
    alpha *= edge
    sparks = []
    for _ in range(12):
        t = random.uniform(0.15, 0.85)
        th = math.radians(18 + t * 144)
        rad = random.uniform(0.74, 0.97)
        sparks.append((0.5 + math.cos(th) * rad * 0.5, 0.5 + math.sin(th) * rad * 0.5,
                       random.uniform(0.005, 0.011), random.uniform(0.35, 0.9)))
    glints = add_sparks(alpha * 0.22, sparks, gold, 1.0)
    rgb = rgb + gold[None, None, :] * glints[..., None] * 0.65
    alpha = clamp01(alpha + glints * 0.55)
    alpha *= edge_window(h, w, 0.055)
    save("blade_qi.png", rgb, alpha, cut=0.10)


# ---------------------------------------------------------------- sword light
def gen_sword_light():
    w, h = 128, 384
    x = np.linspace(-1.0, 1.0, w, dtype=np.float32)[None, :]
    y = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    n = fbm(w, h, 18.0, 3, 5)
    # A long, cold blade of light: tail above, hot tip near the bottom.
    width = 0.055 + 0.045 * np.sin(np.pi * np.clip(y, 0, 1) * 0.9)
    taper = 1.0 - smoothstep(0.86, 0.965, y)
    core = np.exp(-((x / width) ** 2)) * (0.28 + 0.72 * smoothstep(0.05, 0.78, y)) * taper
    halo = np.exp(-((x / 0.24) ** 2)) * (0.15 + 0.5 * smoothstep(0.2, 0.82, y)) * taper
    tip = np.exp(-((x / 0.11) ** 2) - (((y - 0.88) / 0.055) ** 2))
    mist = np.exp(-((x / 0.42) ** 2)) * (0.10 + 0.28 * n) * (1.0 - smoothstep(0.55, 1.0, y))
    energy = core * 0.9 + halo * 0.55 + mist * 0.35
    white = np.array([0.92, 0.99, 1.0], np.float32)
    jade = np.array([0.34, 0.78, 1.0], np.float32)
    ice = np.array([0.64, 0.94, 1.0], np.float32)
    rgb = mix_color(jade, ice, clamp01(energy * 1.2)) + white[None, None, :] * (tip * 0.55)[..., None]
    alpha = clamp01(energy * 0.95 + tip * 0.9)
    # Fine star glints along the blade.
    sparks = [
        (0.5 + random.uniform(-0.05, 0.05), random.uniform(0.25, 0.85),
         random.uniform(0.008, 0.018), random.uniform(0.25, 0.7)) for _ in range(7)
    ]
    glow = add_sparks(alpha * 0.25, sparks, white, 1.0)
    rgb = rgb + white[None, None, :] * glow[..., None] * 0.35
    alpha = clamp01(alpha + glow * 0.45)
    save("sword_light.png", rgb, alpha, cut=0.10)


# ---------------------------------------------------------------- tiger rock
def gen_tiger_rock():
    size = 128
    s = 4
    big = size * s
    canvas = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(canvas)
    cx, cy = big * 0.5, big * 0.52
    pts = []
    random.seed(17)
    for i in range(10):
        a = i / 10.0 * math.tau
        rad = big * random.uniform(0.23, 0.40)
        pts.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad * 0.92))
    d.polygon(pts, fill=255)
    mask = np.asarray(canvas.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0
    mask = clamp01(blur(mask, 0.5))
    x, y = grid(size, size)
    light = clamp01(0.58 - (x * 0.50 + y * 0.55) * 0.55)
    n = fbm(size, size, 10.0, 4, 29)
    dark = np.array([0.15, 0.10, 0.07], np.float32)
    brown = np.array([0.42, 0.27, 0.15], np.float32)
    ochre = np.array([0.80, 0.56, 0.27], np.float32)
    rgb = mix_color(dark, brown, clamp01(light * 0.9 + n * 0.25))
    rgb = rgb + ochre[None, None, :] * (clamp01(light - 0.45) * 0.5)[..., None]
    # rim light along the upper-left contour
    rim = clamp01(mask - blur(mask, 2.2)) * clamp01(0.2 - x - y * 0.3)
    rgb = rgb + np.array([1.0, 0.76, 0.42], np.float32)[None, None, :] * (rim * 1.5)[..., None]
    # cracks: a few jagged bright lines inside the rock
    crack_canvas = Image.new("L", (big, big), 0)
    dc = ImageDraw.Draw(crack_canvas)
    for _ in range(4):
        px, py = cx + random.uniform(-big * 0.18, big * 0.18), cy + random.uniform(-big * 0.15, big * 0.15)
        for _seg in range(4):
            nx = px + random.uniform(-big * 0.09, big * 0.09)
            ny = py + random.uniform(-big * 0.09, big * 0.09)
            dc.line([(px, py), (nx, ny)], fill=random.randint(80, 160), width=2)
            px, py = nx, ny
    crack = np.asarray(crack_canvas.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0
    crack *= mask
    rgb = rgb + np.array([1.0, 0.72, 0.32], np.float32)[None, None, :] * (crack * 0.55)[..., None]
    # dust / ochre halo outside the silhouette
    halo = clamp01(blur(mask, 7.0) - mask)
    rgb = rgb + np.array([0.60, 0.38, 0.18], np.float32)[None, None, :] * (halo * 0.35)[..., None]
    alpha = clamp01(mask * (0.92 + n * 0.15) + crack * 0.35 + halo * 0.22)
    save("tiger_rock.png", rgb, alpha, cut=0.03)


# ---------------------------------------------------------------- tiger orb
def gen_tiger_orb():
    size = 160
    x, y = grid(size, size)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    n = fbm(size, size, 11.0, 4, 43)
    n2 = fbm(size, size, 30.0, 3, 47)
    body = smoothstep(0.68, 0.30, r) * (0.55 + 0.45 * n)
    smoke = smoothstep(1.0, 0.35, r) * (0.18 + 0.45 * n2)
    core = np.exp(-((r / 0.19) ** 2))
    iris = np.exp(-((r / 0.30) ** 2)) * (0.7 + 0.3 * n2)
    # Soft tiger stripes: four wavy gold bands wrapped around the orb.
    stripes = np.zeros((size, size), np.float32)
    for i in range(4):
        phase = i * 0.9
        band = np.sin(th * 3.0 + np.sin(r * 7.0 + phase) * 1.3 + phase)
        stripes = np.maximum(stripes, smoothstep(0.72, 0.98, band))
    stripes *= smoothstep(0.62, 0.25, r) * (0.55 + 0.45 * n2)
    # A dark vertical slit pupil set into the gold iris.
    pupil = np.exp(-((x / 0.035) ** 2) - ((y / 0.15) ** 2)) * smoothstep(0.34, 0.15, r)
    rim = np.exp(-((r - 0.60) / 0.075) ** 2) * (0.45 + 0.55 * n)
    rgb = mix_color(np.array([0.12, 0.015, 0.02], np.float32),
                    np.array([0.58, 0.055, 0.035], np.float32), clamp01(body * 1.3 + smoke * 0.4))
    rgb = rgb + np.array([1.0, 0.46, 0.10], np.float32)[None, None, :] * (iris * 0.55)[..., None]
    rgb = rgb + np.array([1.0, 0.78, 0.28], np.float32)[None, None, :] * (core * 0.75)[..., None]
    rgb = rgb + np.array([1.0, 0.70, 0.20], np.float32)[None, None, :] * (stripes * 0.65)[..., None]
    rgb = rgb + np.array([1.0, 0.80, 0.30], np.float32)[None, None, :] * (rim * 0.32)[..., None]
    rgb = rgb * (1.0 - 0.72 * pupil[..., None])
    rgb = rgb + np.array([0.55, 0.14, 0.04], np.float32)[None, None, :] * (smoke * 0.35)[..., None]
    alpha = clamp01(body * 0.95 + smoke * 0.5 + core * 0.9 + stripes * 0.55 + rim * 0.35)
    alpha *= smoothstep(1.0, 0.82, r) * edge_window(size, size, 0.06)
    # A few orbiting sparks.
    sparks = []
    for _ in range(9):
        a = random.uniform(0, math.tau)
        rad = random.uniform(0.55, 0.92)
        sparks.append((0.5 + math.cos(a) * rad * 0.5, 0.5 + math.sin(a) * rad * 0.5,
                       random.uniform(0.005, 0.011), random.uniform(0.25, 0.7)))
    glints = add_sparks(alpha * 0.16, sparks, np.array([1.0, 0.72, 0.25], np.float32), 1.0)
    rgb = rgb + np.array([1.0, 0.72, 0.25], np.float32)[None, None, :] * glints[..., None] * 0.5
    alpha = clamp01(alpha + glints * 0.4)
    save("tiger_orb.png", rgb, alpha, cut=0.08)


# ---------------------------------------------------------------- blade scar
def gen_blade_scar():
    size = 256
    x, y = grid(size, size)
    random.seed(2026)
    pts = []
    for i in range(13):
        t = i / 12.0
        px = -0.70 + t * 1.42 + random.uniform(-0.055, 0.055)
        py = 0.64 - t * 1.26 + random.uniform(-0.075, 0.075)
        pts.append((px, py))
    dist = np.full((size, size), 9.0, dtype=np.float32)
    seg_t = np.zeros((size, size), dtype=np.float32)
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        vx, vy = bx - ax, by - ay
        seg_len2 = max(vx * vx + vy * vy, 1e-6)
        t = np.clip(((x - ax) * vx + (y - ay) * vy) / seg_len2, 0.0, 1.0)
        dx = x - (ax + vx * t)
        dy = y - (ay + vy * t)
        d = np.sqrt(dx * dx + dy * dy)
        take = d < dist
        dist = np.where(take, d, dist)
        seg_t = np.where(take, (i + t) / (len(pts) - 1), seg_t)
    n = fbm(size, size, 20.0, 4, 71)
    n2 = fbm(size, size, 7.0, 3, 73)
    jag = (n - 0.5) * 0.045
    d = np.maximum(0.0, dist + jag)
    # Width varies along the gash, with occasional hot breaks.
    width = 0.65 + 0.75 * smoothstep(0.2, 0.8, n2)
    core = np.exp(-((d / (0.008 * width)) ** 2))
    hot = np.exp(-((d / (0.032 * width)) ** 2))
    glow = np.exp(-((d / 0.14) ** 2))
    char = np.exp(-((d / 0.34) ** 2))
    breaks = smoothstep(0.37, 0.62, fbm(size, size, 12.0, 3, 79))
    core *= 0.55 + 0.45 * breaks
    hot *= 0.65 + 0.35 * breaks
    # A couple of thin branching cracks off the main gash.
    branch = np.zeros_like(d)
    for i in range(3, 10):
        ax, ay = pts[i]
        ang = random.uniform(-1.5, 1.5)
        length = random.uniform(0.12, 0.30)
        bx = ax + math.cos(ang) * length
        by = ay + math.sin(ang) * length
        vx, vy = bx - ax, by - ay
        t = np.clip(((x - ax) * vx + (y - ay) * vy) / max(vx * vx + vy * vy, 1e-6), 0.0, 1.0)
        bd = np.sqrt((x - (ax + vx * t)) ** 2 + (y - (ay + vy * t)) ** 2)
        branch = np.maximum(branch, np.exp(-((bd / 0.022) ** 2)) * (1.0 - t * 0.7))
    char_col = np.array([0.035, 0.022, 0.018], np.float32)
    ember = np.array([0.82, 0.16, 0.04], np.float32)
    gold = np.array([1.0, 0.55, 0.14], np.float32)
    white = np.array([1.0, 0.92, 0.70], np.float32)
    rgb = np.zeros((size, size, 3), np.float32)
    rgb = mix_color(rgb, char_col, clamp01(char * 0.95))
    rgb = rgb + ember[None, None, :] * (glow * 0.62)[..., None]
    rgb = rgb + gold[None, None, :] * (hot * 0.8)[..., None]
    rgb = rgb + white[None, None, :] * (core * 0.9)[..., None]
    rgb = rgb + gold[None, None, :] * (branch * 0.55)[..., None]
    alpha = clamp01(char * 0.88 + glow * 0.48 + hot * 0.85 + core * 1.0 + branch * 0.45)
    sparks = []
    for _ in range(18):
        t = random.random()
        px = -0.55 + t * 1.05 + random.uniform(-0.12, 0.12)
        py = 0.42 - t * 0.8 + random.uniform(-0.20, 0.06)
        sparks.append((0.5 + px * 0.5, 0.5 + py * 0.5, random.uniform(0.004, 0.011), random.uniform(0.25, 0.8)))
    glints = add_sparks(alpha * 0.18, sparks, gold, 1.0)
    rgb = rgb + gold[None, None, :] * glints[..., None] * 0.65
    alpha = clamp01(alpha + glints * 0.5)
    alpha *= smoothstep(1.02, 0.92, np.sqrt(x * x + y * y)) * edge_window(size, size, 0.045)
    save("blade_scar.png", rgb, alpha, cut=0.03)


# ---------------------------------------------------------------- heaven charge / trail
def gen_heaven_charge():
    w, h = 256, 384
    x, y = grid(w, h)
    r = np.sqrt(x * x + y * y)
    n = fbm(w, h, 16.0, 4, 87)
    n2 = fbm(w, h, 42.0, 3, 91)
    core = np.exp(-((r / 0.19) ** 2))
    halo = np.exp(-((r / 0.55) ** 2))
    # vertical body of the charge; strongest near the centre
    beam = np.exp(-((x / 0.20) ** 2)) * (1.0 - smoothstep(0.25, 1.0, y)) * smoothstep(-1.0, -0.6, y)
    beam *= 0.35 + 0.65 * n2
    swirl = np.exp(-((r / 0.62) ** 2)) * clamp01(0.5 + 0.5 * np.sin(np.arctan2(y, x) * 4.0 + r * 9.0 + n * 3.0))
    swirl *= 0.5
    energy = halo * 0.6 + beam * 0.55 + swirl * 0.35
    jade = np.array([0.20, 0.58, 0.95], np.float32)
    ice = np.array([0.72, 0.96, 1.0], np.float32)
    gold = np.array([1.0, 0.86, 0.48], np.float32)
    rgb = mix_color(jade, ice, clamp01(energy * 1.3))
    rgb = rgb + ice[None, None, :] * (core * 0.9)[..., None]
    rgb = rgb + gold[None, None, :] * (core * 0.35 + beam * 0.25)[..., None]
    alpha = clamp01(energy * 0.9 + core * 1.1)
    alpha *= smoothstep(1.02, 0.88, np.sqrt(x * x + (y / 1.5) ** 2))
    sparks = []
    for _ in range(18):
        ang = random.uniform(0, math.tau)
        rad = random.uniform(0.15, 0.95)
        sparks.append((0.5 + math.cos(ang) * rad * 0.4, 0.5 + math.sin(ang) * rad * 0.4,
                       random.uniform(0.004, 0.012), random.uniform(0.3, 0.9)))
    glints = add_sparks(alpha * 0.18, sparks, gold, 1.0)
    rgb = rgb + gold[None, None, :] * glints[..., None] * 0.6
    alpha = clamp01(alpha + glints * 0.5)
    save("heaven_charge.png", rgb, alpha, cut=0.03)


def gen_heaven_trail():
    w, h = 128, 512
    x = np.linspace(-1.0, 1.0, w, dtype=np.float32)[None, :]
    y = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    n = fbm(w, h, 12.0, 3, 111)
    core = np.exp(-((x / 0.055) ** 2))
    halo = np.exp(-((x / 0.22) ** 2))
    body = halo * (0.30 + 0.7 * n) * smoothstep(0.0, 0.2, y) * (1.0 - smoothstep(0.82, 1.0, y))
    body += core * (0.45 + 0.55 * n) * smoothstep(0.05, 0.25, y) * (1.0 - smoothstep(0.86, 1.0, y))
    jade = np.array([0.24, 0.70, 1.0], np.float32)
    ice = np.array([0.78, 0.98, 1.0], np.float32)
    gold = np.array([1.0, 0.88, 0.50], np.float32)
    rgb = mix_color(jade, ice, clamp01(body * 1.3))
    rgb = rgb + gold[None, None, :] * (core * body * 0.18)[..., None]
    alpha = clamp01(body * 0.9)
    save("heaven_trail.png", rgb, alpha, cut=0.03)


# ---------------------------------------------------------------- cracks
def segment_distance(x, y, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    t = np.clip(((x - ax) * vx + (y - ay) * vy) / max(vx * vx + vy * vy, 1e-6), 0.0, 1.0)
    dx = x - (ax + vx * t)
    dy = y - (ay + vy * t)
    return np.sqrt(dx * dx + dy * dy)


def draw_crack_paths(w, h, paths, branches, seed=0):
    x, y = grid(w, h)
    dist = np.full((h, w), 4.0, dtype=np.float32)
    for pts in paths:
        for i in range(len(pts) - 1):
            dist = np.minimum(dist, segment_distance(x, y, *pts[i], *pts[i + 1]))
    bdist = np.full((h, w), 4.0, dtype=np.float32)
    for pts in branches:
        for i in range(len(pts) - 1):
            bdist = np.minimum(bdist, segment_distance(x, y, *pts[i], *pts[i + 1]))
    return dist, bdist


def gen_heaven_cracks():
    # The full variant: a long fissure whose origin is at the left edge.
    w, h = 1024, 256
    x, y = grid(w, h)
    random.seed(303)
    pts = []
    for i in range(17):
        t = i / 16.0
        px = -1.0 + t * 2.0
        py = -0.10 + 0.11 * math.sin(t * 9.0) + random.uniform(-0.05, 0.05)
        pts.append((px, py))
    branches = []
    for i in range(3, 15):
        ax, ay = pts[i]
        for _ in range(2):
            ang = random.uniform(-0.9, 0.9)
            length = random.uniform(0.08, 0.30)
            bx = ax + math.cos(ang) * length
            by = ay + math.sin(ang) * length
            branches.append([(ax, ay), (bx, by)])
    dist, bdist = draw_crack_paths(w, h, [pts], branches)
    n = fbm(w, h, 18.0, 3, 123)
    n2 = fbm(w, h, 6.0, 3, 129)
    jag = (n - 0.5) * 0.02
    d = np.maximum(0.0, dist + jag)
    width = 0.75 + 0.6 * smoothstep(0.2, 0.8, n2)
    core = np.exp(-((d / (0.020 * width)) ** 2))
    hot = np.exp(-((d / (0.070 * width)) ** 2))
    glow = np.exp(-((d / 0.22) ** 2))
    char = np.exp(-((d / 0.48) ** 2))
    branch_hot = np.exp(-((bdist / 0.046) ** 2)) * 0.55
    branch_glow = np.exp(-((bdist / 0.17) ** 2)) * 0.38
    scorch = clamp01(blur(char * 0.9 + branch_glow * 0.5, 5.0) * 0.72)
    # A broad impact bloom near the start of the fissure.
    ix, iy = -0.56, -0.03
    ir = np.sqrt((x - ix) ** 2 + ((y - iy) * 1.8) ** 2)
    impact = np.exp(-((ir / 0.18) ** 2))
    impact_glow = np.exp(-((ir / 0.42) ** 2)) * 0.72
    impact_ring = np.exp(-(((ir - 0.36) / 0.06) ** 2)) * 0.24
    ember = np.array([1.0, 0.62, 0.18], np.float32)
    gold = np.array([1.0, 0.90, 0.62], np.float32)
    white = np.array([1.0, 0.99, 0.92], np.float32)
    cyan = np.array([0.35, 0.80, 1.0], np.float32)
    dark = np.array([0.03, 0.035, 0.045], np.float32)
    rgb = mix_color(np.zeros_like(scorch[..., None]), dark, scorch)
    rgb = rgb + cyan[None, None, :] * (glow * 0.12 + impact_ring * 0.20)[..., None]
    rgb = rgb + ember[None, None, :] * (glow * 0.46 + impact_glow * 0.35)[..., None]
    rgb = rgb + gold[None, None, :] * ((hot + branch_hot + impact_ring) * 0.62)[..., None]
    rgb = rgb + white[None, None, :] * ((core + impact * 0.8) * 0.88)[..., None]
    alpha = clamp01(scorch * 0.82 + glow * 0.46 + hot * 0.6 + core * 0.95
                    + branch_hot * 0.4 + impact * 0.8 + impact_glow * 0.35 + impact_ring * 0.3)
    # rock chips and embers scattered around the fissure
    chips = []
    for _ in range(46):
        chips.append((random.uniform(0.02, 0.98), random.uniform(0.12, 0.88),
                      random.uniform(0.0015, 0.0055), random.uniform(0.2, 0.65)))
    glints = add_sparks(alpha * 0.10, chips, gold, 1.0)
    rgb = rgb + gold[None, None, :] * glints[..., None] * 0.45
    alpha = clamp01(alpha + glints * 0.35)
    xw = np.linspace(0.0, 1.0, w, dtype=np.float32)
    yw = np.linspace(0.0, 1.0, h, dtype=np.float32)
    ey = (1.0 - smoothstep(0.96, 1.0, yw)) * smoothstep(-0.01, 0.02, yw)
    ex = smoothstep(0.0, 0.015, xw) * (1.0 - smoothstep(0.86, 1.0, xw))
    alpha *= ey[:, None] * ex[None, :]
    save("heaven_crack_rect.png", rgb, alpha, cut=0.02)

    # The normal heaven: thick molten cracks and a crater, not a starburst.
    w = h = 512
    x, y = grid(w, h)
    random.seed(404)
    paths = []
    branches = []
    for i in range(7):
        ang = math.radians(-60 + i * 20 + random.uniform(-7, 7))
        length = random.uniform(0.42, 0.82)
        pts = []
        steps = 7
        for s in range(steps):
            t = s / (steps - 1)
            rr = 0.02 + t * length
            aa = ang + math.sin(t * 7.0 + i * 1.4) * 0.05
            pts.append((math.cos(aa) * rr, math.sin(aa) * rr))
        paths.append(pts)
        for s in range(1, steps - 1):
            if random.random() < 0.75:
                ax, ay = pts[s]
                ba = ang + random.uniform(-0.8, 0.8)
                bl = random.uniform(0.07, 0.24)
                branches.append([(ax, ay), (ax + math.cos(ba) * bl, ay + math.sin(ba) * bl)])
    dist, bdist = draw_crack_paths(w, h, paths, branches)
    n = fbm(w, h, 16.0, 3, 127)
    n2 = fbm(w, h, 5.0, 3, 131)
    d = np.maximum(0.0, dist + (n - 0.5) * 0.018)
    r = np.sqrt(x * x + y * y)
    width = 0.8 + 0.55 * smoothstep(0.2, 0.8, n2)
    core = np.exp(-((d / (0.023 * width)) ** 2))
    hot = np.exp(-((d / (0.080 * width)) ** 2))
    glow = np.exp(-((d / 0.24) ** 2))
    char = np.exp(-((d / 0.50) ** 2))
    branch_hot = np.exp(-((bdist / 0.056) ** 2)) * 0.55
    scorch = clamp01(blur(char * 0.9 + glow * 0.45, 7.0) * 0.78)
    crater = np.exp(-((r / 0.24) ** 2))
    crater_ring = np.exp(-(((r - 0.32) / 0.075) ** 2)) * 0.38
    shock = np.exp(-(((r - 0.52) / 0.09) ** 2)) * 0.20
    ground_glow = np.exp(-((r / 0.62) ** 2)) * 0.18
    ember = np.array([1.0, 0.66, 0.20], np.float32)
    gold = np.array([1.0, 0.90, 0.58], np.float32)
    white = np.array([1.0, 0.99, 0.94], np.float32)
    cyan = np.array([0.40, 0.82, 1.0], np.float32)
    dark = np.array([0.03, 0.035, 0.045], np.float32)
    rgb = mix_color(np.zeros_like(scorch[..., None]), dark, scorch)
    rgb = rgb + cyan[None, None, :] * (glow * 0.14 + crater_ring * 0.10)[..., None]
    rgb = rgb + ember[None, None, :] * (glow * 0.48 + ground_glow)[..., None]
    rgb = rgb + gold[None, None, :] * ((hot + branch_hot + crater_ring) * 0.60 + shock * 0.25)[..., None]
    rgb = rgb + white[None, None, :] * ((core + crater * 0.85) * 0.9)[..., None]
    alpha = clamp01(scorch * 0.8 + glow * 0.46 + hot * 0.6 + core * 0.95
                    + branch_hot * 0.4 + crater * 0.9 + crater_ring * 0.42 + shock * 0.25 + ground_glow * 0.5)
    chips = []
    for _ in range(38):
        a = random.uniform(0, math.tau)
        rad = random.uniform(0.05, 0.9)
        chips.append((0.5 + math.cos(a) * rad * 0.5, 0.5 + math.sin(a) * rad * 0.5,
                      random.uniform(0.002, 0.007), random.uniform(0.2, 0.7)))
    glints = add_sparks(alpha * 0.10, chips, gold, 1.0)
    rgb = rgb + gold[None, None, :] * glints[..., None] * 0.45
    alpha = clamp01(alpha + glints * 0.35)
    alpha *= smoothstep(1.0, 0.9, r) * edge_window(h, w, 0.06)
    save("heaven_crack_fan.png", rgb, alpha, cut=0.02)


# ---------------------------------------------------------------- blade field
def gen_skill_field():
    w = h = 512
    x, y = grid(w, h)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    n = fbm(w, h, 9.0, 4, 151)
    n2 = fbm(w, h, 24.0, 4, 157)
    n3 = fbm(w, h, 5.0, 3, 163)
    edge = smoothstep(1.0, 0.76, r)
    # Warm, smoky ground domain (filled; the player remains visible through it).
    base = smoothstep(0.92, 0.18, r) * (0.16 + 0.30 * n)
    smoke = smoothstep(0.96, 0.24, r) * (0.22 + 0.62 * n2) * 0.45
    # Three broad spiral arms.
    spiral = smoothstep(0.15, 0.95, 0.5 + 0.5 * np.sin(th * 3.0 + r * 8.0 + n * 4.0))
    spiral *= smoothstep(0.95, 0.2, r) * 0.42
    spiral = blur(spiral, 3.0)
    # A soft, noisy perimeter wall with faint vertical energy.
    wall = np.exp(-(((r - 0.78) / 0.095) ** 2)) * (0.35 + 0.65 * n3)
    wall += np.exp(-(((r - 0.60) / 0.18) ** 2)) * np.abs(np.sin(th * 18.0 + r * 5.0 + n2 * 4.0)) * 0.12
    wall = blur(wall, 2.0) * 0.55
    # Curved blade glints embedded around the domain (soft, tapered).
    blades = np.zeros((h, w), np.float32)
    for i in range(6):
        ang0 = i / 6.0 * math.tau + 0.42
        rr = 0.48 + (i % 2) * 0.16
        dth = np.arctan2(np.sin(th - ang0), np.cos(th - ang0))
        streak = np.exp(-((dth / 0.055) ** 2)) * np.exp(-(((r - rr) / 0.19) ** 2))
        blades = np.maximum(blades, streak)
    blades *= 0.35 + 0.65 * n2
    blades = blur(blades, 2.2) * 0.6
    energy = base + smoke + spiral + wall + blades * 0.8
    ink = np.array([0.055, 0.038, 0.028], np.float32)
    ember = np.array([0.72, 0.28, 0.075], np.float32)
    gold = np.array([1.0, 0.72, 0.28], np.float32)
    pale = np.array([1.0, 0.92, 0.66], np.float32)
    rgb = mix_color(ink, ember, clamp01(energy * 1.25))
    rgb = rgb + gold[None, None, :] * (clamp01(spiral + wall * 0.6 + blades) * 0.45)[..., None]
    rgb = rgb + pale[None, None, :] * (blades * 0.28)[..., None]
    alpha = clamp01(energy * 0.82 + blades * 0.35) * edge
    alpha *= edge_window(h, w, 0.045)
    # Sparse dust glints.
    sparks = []
    for _ in range(26):
        a = random.uniform(0, math.tau)
        rad = random.uniform(0.15, 0.9)
        sparks.append((0.5 + math.cos(a) * rad * 0.5, 0.5 + math.sin(a) * rad * 0.5,
                       random.uniform(0.002, 0.005), random.uniform(0.2, 0.7)))
    glints = add_sparks(alpha * 0.1, sparks, gold, 1.0)
    rgb = rgb + gold[None, None, :] * glints[..., None] * 0.5
    alpha = clamp01(alpha + glints * 0.35)
    save("skill_field.png", rgb, alpha, cut=0.02)


# ---------------------------------------------------------------- counter ward
def gen_skill_ward():
    w = h = 256
    x, y = grid(w, h)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    n = fbm(w, h, 10.0, 4, 171)
    n2 = fbm(w, h, 32.0, 3, 173)
    # A translucent golden sphere with a soft, irregular shell.
    shell = np.exp(-(((r - 0.70) / 0.11) ** 2)) * (0.45 + 0.55 * n)
    fill = smoothstep(0.88, 0.20, r) * (0.08 + 0.22 * n2)
    # Broad blade-intent arcs wrapping the sphere.
    arcs = np.zeros((h, w), np.float32)
    for i in range(3):
        a0 = i / 3.0 * math.tau + 0.5
        dth = np.arctan2(np.sin(th - a0), np.cos(th - a0))
        arcs = np.maximum(arcs, np.exp(-((dth / 0.16) ** 2)) * np.exp(-(((r - 0.48) / 0.20) ** 2)))
    arcs = blur(arcs, 2.5) * 0.6
    shell = blur(shell, 1.5)
    core = np.exp(-((r / 0.22) ** 2)) * 0.22
    energy = fill + shell * 0.75 + arcs * 0.4 + core
    deep = np.array([0.42, 0.16, 0.035], np.float32)
    gold = np.array([1.0, 0.76, 0.30], np.float32)
    pale = np.array([1.0, 0.95, 0.74], np.float32)
    rgb = mix_color(deep, gold, clamp01(energy * 1.4))
    rgb = rgb + pale[None, None, :] * (shell * 0.35 + arcs * 0.22)[..., None]
    red = np.array([0.90, 0.34, 0.08], np.float32)
    rgb = rgb + red[None, None, :] * (fill * 0.25)[..., None]
    alpha = clamp01(energy * 0.75 + shell * 0.4 + arcs * 0.25)
    alpha *= smoothstep(1.0, 0.88, r) * edge_window(h, w, 0.06)
    sparks = []
    for _ in range(14):
        a = random.uniform(0, math.tau)
        rad = random.uniform(0.55, 0.92)
        sparks.append((0.5 + math.cos(a) * rad * 0.5, 0.5 + math.sin(a) * rad * 0.5,
                       random.uniform(0.003, 0.008), random.uniform(0.25, 0.8)))
    glints = add_sparks(alpha * 0.12, sparks, gold, 1.0)
    rgb = rgb + gold[None, None, :] * glints[..., None] * 0.6
    alpha = clamp01(alpha + glints * 0.4)
    save("skill_ward.png", rgb, alpha, cut=0.02)


if __name__ == "__main__":
    gen_blade_qi()
    gen_sword_light()
    gen_tiger_rock()
    gen_tiger_orb()
    gen_blade_scar()
    gen_heaven_charge()
    gen_heaven_trail()
    gen_heaven_cracks()
    gen_skill_field()
    gen_skill_ward()
