"""烘虎妖水墨卡的「笔势方向 / 相位 / 权重 / 保护」数据图。

方向图 RGBA：R/G = 方向编码（0.5 为中心），B = 局部相位，A = 流动权重。
保护图 L：眼、牙、爪、耳尖越接近 1 越不让墨流走。
数据图只给 ink_card.gdshader 用，不是玩家可见美术。
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "ui" / "codex" / "holo" / "boss_huyao_ink.png"
FLOW = ROOT / "assets" / "ui" / "codex" / "holo" / "boss_huyao_ink_flow.png"
GUARD = ROOT / "assets" / "ui" / "codex" / "holo" / "boss_huyao_ink_guard.png"
PREVIEW = ROOT / "output" / "huyao_ink_flow_preview.png"
GUARD_PREVIEW = ROOT / "output" / "huyao_ink_guard_preview.png"

# 只在这些点位给强流转；其余区域只留很轻的呼吸，避免整张画一直在动
# (cx, cy, rx, ry, strength) —— 坐标按 v4 640×960 原画
FLOW_SPOTS = [
    (420, 470, 132, 132, 1.00),   # 颈侧鬃毛
    (330, 480, 124, 120, 1.00),   # 肩背条纹
    (185, 400, 100, 168, 1.00),   # 尾梢
    (320, 335, 128, 80, 0.80),    # 背脊雾气 / 鬃尖
    (505, 800, 168, 80, 0.70),    # 岩台边缘
]
BASE_WEIGHT = 0.20
# 眼、牙口、耳尖、可见爪（2026-10-30 按 v4 原画重对位）
GUARD_ELLIPSES = [
    (508, 442, 30, 25), (553, 444, 29, 24),  # 眼及眼窝
    (536, 505, 46, 62),                       # 牙口 / 下颚
    (458, 382, 28, 34), (536, 390, 28, 34),  # 耳尖
    (129, 716, 35, 29),                       # 后左爪
    (329, 756, 56, 33),                       # 前左爪
    (520, 752, 46, 35),                       # 前右爪
]


def _guard_mask(size):
    canvas = Image.new("L", size, 0)
    draw = ImageDraw.Draw(canvas)
    for cx, cy, rx, ry in GUARD_ELLIPSES:
        draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    return np.asarray(canvas.filter(ImageFilter.GaussianBlur(11)), np.float32) / 255.0


def _normalize(a):
    lo, hi = float(a.min()), float(a.max())
    if hi <= lo + 1e-6:
        return np.zeros_like(a, np.float32)
    return ((a - lo) / (hi - lo)).astype(np.float32)


def _phase_field(size):
    rng = np.random.default_rng(20261030)
    raw = rng.normal(size=size).astype(np.float32)
    broad = _normalize(gaussian_filter(raw, 82.0))
    medium = _normalize(gaussian_filter(raw[::-1, ::-1], 34.0))
    return np.clip(0.62 * broad + 0.38 * medium, 0.0, 1.0).astype(np.float32)


def _direction_field(lum):
    smooth = gaussian_filter(lum, 1.7)
    gy, gx = np.gradient(smooth)
    # 结构张量：先模糊，保证同一块虎毛 / 山石里的笔触方向大致同向
    jxx = gaussian_filter(gx * gx, 8.0)
    jxy = gaussian_filter(gx * gy, 8.0)
    jyy = gaussian_filter(gy * gy, 8.0)
    theta = 0.5 * np.arctan2(2.0 * jxy, jxx - jyy) + np.pi * 0.5
    vx = np.cos(theta).astype(np.float32)
    vy = np.sin(theta).astype(np.float32)
    # 线方向天然有 180° 歧义：统一朝右下，避免相邻区域各自反向
    flip = vx * 0.16 + vy * 1.0 < 0.0
    vx[flip] *= -1.0
    vy[flip] *= -1.0
    # 轻度平滑一次带符号向量；低幅区域用右下基准兜底
    vx = gaussian_filter(vx, 2.0)
    vy = gaussian_filter(vy, 2.0)
    mag = np.sqrt(vx * vx + vy * vy)
    fallback = mag < 0.22
    vx[fallback] = 0.16
    vy[fallback] = 1.0
    mag = np.maximum(np.sqrt(vx * vx + vy * vy), 1e-5)
    return vx / mag, vy / mag


def _draw_arrows(base, vx, vy, ink, guard, weight):
    out = base.copy()
    draw = ImageDraw.Draw(out)
    step = 18
    for y in range(12, base.height, step):
        for x in range(12, base.width, step):
            if ink[y, x] < 0.10 or guard[y, x] > 0.55:
                continue
            dx, dy = float(vx[y, x]), float(vy[y, x])
            ln = 6.5
            c = (35, 96, 205) if weight[y, x] < 0.7 else (205, 52, 40)
            draw.line((x - dx * ln, y - dy * ln, x + dx * ln, y + dy * ln),
                      fill=c, width=1)
            draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=c)
    return out


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    if im.size != (640, 960):
        raise SystemExit(f"unexpected source size: {im.size}")
    size = (im.width, im.height)
    lum = np.asarray(im.convert("L"), np.float32) / 255.0
    ink = 1.0 - lum
    vx, vy = _direction_field(lum)
    phase = _phase_field((size[1], size[0]))
    yy, xx = np.mgrid[0:size[1], 0:size[0]].astype(np.float32)
    focus = np.zeros((size[1], size[0]), np.float32)
    for cx, cy, rx, ry, strength in FLOW_SPOTS:
        sx = max(rx * 0.62, 1.0)
        sy = max(ry * 0.62, 1.0)
        g = np.exp(-((xx - cx) ** 2 / (2.0 * sx * sx)
                     + (yy - cy) ** 2 / (2.0 * sy * sy))).astype(np.float32)
        focus = np.maximum(focus, strength * g)
    weight = np.clip(BASE_WEIGHT + focus, 0.0, 1.0)
    guard = _guard_mask(size)

    flow = np.zeros((size[1], size[0], 4), np.uint8)
    flow[..., 0] = np.clip((vx * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    flow[..., 1] = np.clip((vy * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    flow[..., 2] = np.clip(phase * 255.0 + 0.5, 0, 255).astype(np.uint8)
    flow[..., 3] = np.clip(weight * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(flow, "RGBA").save(FLOW, optimize=True)
    Image.fromarray(np.clip(guard * 255.0 + 0.5, 0, 255).astype(np.uint8), "L") \
        .save(GUARD, optimize=True)

    preview = _draw_arrows(im, vx, vy, ink, guard, weight)
    preview.save(PREVIEW)
    gprev = im.copy()
    red = Image.new("RGB", size, (210, 50, 38))
    gprev = Image.composite(red, gprev, Image.fromarray(
        (np.clip(guard, 0, 1) * 170).astype(np.uint8), "L"))
    gprev.save(GUARD_PREVIEW)
    print(f"saved {FLOW.relative_to(ROOT)}")
    print(f"saved {GUARD.relative_to(ROOT)}")
    print(f"saved {PREVIEW.relative_to(ROOT)}")
    print(f"saved {GUARD_PREVIEW.relative_to(ROOT)}")
    print("phase range", float(phase.min()), float(phase.max()))
    print("weight range", float(weight.min()), float(weight.max()))


if __name__ == "__main__":
    main()
