"""为整套纸本水墨卡烘三张数据图：reveal / flow / guard。

虎妖那套是手工对位；其余 11 张按同一口径自动生成：
- reveal：从面部/主笔向肩、身、地基扩散的落墨顺序场
- flow：结构张量方向 + 局部笔触热点（自动取 5 处，避开面部）
- guard：高频细节 + 彩色重音（眼、面具、环、核心）保护
产物只给 ink_card.gdshader 用，不是玩家可见美术。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parents[1]
HOLO = ROOT / "assets" / "ui" / "codex" / "holo"
OUTPUT = ROOT / "output"

IDS = [
    "boss_01", "boss_01_c", "boss_02", "boss_02_b", "boss_02_c",
    "boss_03", "boss_03_b", "boss_03_c",
    "world_core_lianqi", "world_core_zhuji", "world_core_jiedan",
    "world_core_shihou",
    "boss_04", "boss_04_b", "boss_04_c",
]

REVEAL_SEEDS = [
    (0.500, 0.340, 0.000),
    (0.355, 0.520, 0.050),
    (0.645, 0.520, 0.060),
    (0.500, 0.700, 0.100),
    (0.500, 0.870, 0.140),
    (0.220, 0.800, 0.165),
    (0.780, 0.800, 0.170),
]
BASE_WEIGHT = 0.18


def _norm(a):
    lo, hi = float(a.min()), float(a.max())
    if hi <= lo + 1e-6:
        return np.zeros_like(a, np.float32)
    return ((a - lo) / (hi - lo)).astype(np.float32)


def _phase_field(size):
    rng = np.random.default_rng(20261030)
    raw = rng.normal(size=size).astype(np.float32)
    broad = _norm(gaussian_filter(raw, 82.0))
    medium = _norm(gaussian_filter(raw[::-1, ::-1], 34.0))
    return np.clip(0.62 * broad + 0.38 * medium, 0.0, 1.0).astype(np.float32)


def _direction_field(lum):
    smooth = gaussian_filter(lum, 1.7)
    gy, gx = np.gradient(smooth)
    jxx = gaussian_filter(gx * gx, 8.0)
    jxy = gaussian_filter(gx * gy, 8.0)
    jyy = gaussian_filter(gy * gy, 8.0)
    theta = 0.5 * np.arctan2(2.0 * jxy, jxx - jyy) + np.pi * 0.5
    vx = np.cos(theta).astype(np.float32)
    vy = np.sin(theta).astype(np.float32)
    flip = vx * 0.16 + vy * 1.0 < 0.0
    vx[flip] *= -1.0
    vy[flip] *= -1.0
    vx = gaussian_filter(vx, 2.0)
    vy = gaussian_filter(vy, 2.0)
    mag = np.sqrt(vx * vx + vy * vy)
    fallback = mag < 0.22
    vx[fallback] = 0.16
    vy[fallback] = 1.0
    mag = np.maximum(np.sqrt(vx * vx + vy * vy), 1e-5)
    return vx / mag, vy / mag


def _guard_field(rgb):
    a = rgb.astype(np.float32) / 255.0
    lum = a @ np.array([0.299, 0.587, 0.114], np.float32)
    chroma = a.max(2) - a.min(2)
    # 只保护「会看错」的小东西：发亮的眼、面具、彩环、核心。
    local = gaussian_filter(lum, 9.0)
    highlight = np.clip((lum - local - 0.035) / 0.09, 0.0, 1.0) \
        * np.clip((lum - 0.55) / 0.25, 0.0, 1.0)
    accent = np.clip((chroma - 0.07) / 0.10, 0.0, 1.0) \
        * np.clip((lum - 0.10) / 0.20, 0.0, 1.0)
    guard = np.clip(highlight * 0.9 + accent * 0.8, 0.0, 1.0)
    guard = gaussian_filter(guard, 7.0)
    guard = np.clip((guard - 0.16) / 0.50, 0.0, 1.0)
    return guard.astype(np.float32)


def _pick_spots(ink, w, h):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    x = xx / w
    y = yy / h
    # 头部/面部（大多在上三分之一）不挂笔触热点，只留基础呼吸
    lower = np.clip((y - 0.34) / 0.10, 0.0, 1.0)
    energy = _norm(gaussian_filter(ink * lower, 5.0))
    energy = gaussian_filter(energy, 26.0) * lower
    spots = []
    tmp = energy.copy()
    for _ in range(5):
        idx = int(np.argmax(tmp))
        cy, cx = divmod(idx, w)
        strength = float(np.clip(tmp[cy, cx] * 2.4, 0.45, 1.0))
        spots.append((cx, cy, int(w * 0.17), int(h * 0.115), strength))
        d2 = ((xx - cx) ** 2 + (yy - cy) ** 2)
        tmp[d2 < (min(w, h) * 0.24) ** 2] = 0.0
    return spots


def _flow_weight(size, ink, guard, spots):
    yy, xx = np.mgrid[0:size[1], 0:size[0]].astype(np.float32)
    focus = np.zeros((size[1], size[0]), np.float32)
    for cx, cy, rx, ry, strength in spots:
        sx = max(rx * 0.62, 1.0)
        sy = max(ry * 0.62, 1.0)
        g = np.exp(-((xx - cx) ** 2 / (2.0 * sx * sx)
                     + (yy - cy) ** 2 / (2.0 * sy * sy))).astype(np.float32)
        focus = np.maximum(focus, strength * g)
    weight = np.clip(BASE_WEIGHT + 0.82 * focus, 0.0, 1.0)
    weight *= 1.0 - 0.55 * guard
    return focus, np.clip(weight, 0.0, 1.0)


def _reveal_field(size):
    h, w = size[1], size[0]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    x = xx / float(w)
    y = yy / float(h)
    field = np.full((h, w), 9.0, np.float32)
    for sx, sy, offset in REVEAL_SEEDS:
        d = np.sqrt((x - sx) ** 2 + (y - sy) ** 2)
        field = np.minimum(field, d + offset)
    rng = np.random.default_rng(20261030)
    noise = gaussian_filter(rng.normal(size=(h, w)).astype(np.float32), 70.0)
    noise = (noise - noise.min()) / (noise.max() - noise.min() + 1e-6)
    field = gaussian_filter(field + (noise - 0.5) * 0.16, 5.0)
    return _norm(field)


def _arrow_preview(im, vx, vy, ink, guard, weight):
    out = im.copy()
    draw = ImageDraw.Draw(out)
    step = 18
    for y in range(12, out.height, step):
        for x in range(12, out.width, step):
            if ink[y, x] < 0.10 or guard[y, x] > 0.55:
                continue
            dx, dy = float(vx[y, x]), float(vy[y, x])
            ln = 6.5
            c = (35, 96, 205) if weight[y, x] < 0.5 else (205, 52, 40)
            draw.line((x - dx * ln, y - dy * ln, x + dx * ln, y + dy * ln),
                      fill=c, width=1)
    return out


def bake(card_id: str) -> Image.Image:
    src = HOLO / f"{card_id}_ink.png"
    im = Image.open(src).convert("RGB")
    if im.size != (640, 960):
        raise SystemExit(f"unexpected {card_id} size {im.size}")
    w, h = im.size
    rgb = np.asarray(im)
    lum = rgb.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32) / 255.0
    ink = 1.0 - lum
    vx, vy = _direction_field(lum)
    guard = _guard_field(rgb)
    spots = _pick_spots(ink, w, h)
    focus, weight = _flow_weight((w, h), ink, guard, spots)
    phase = _phase_field((h, w))

    flow = np.zeros((h, w, 4), np.uint8)
    flow[..., 0] = np.clip((vx * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    flow[..., 1] = np.clip((vy * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    flow[..., 2] = np.clip(phase * 255.0 + 0.5, 0, 255).astype(np.uint8)
    flow[..., 3] = np.clip(weight * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(flow, "RGBA").save(HOLO / f"{card_id}_ink_flow.png", optimize=True)

    guard_img = Image.fromarray(
        np.clip(guard * 255.0 + 0.5, 0, 255).astype(np.uint8), "L")
    guard_img.filter(ImageFilter.GaussianBlur(1)).save(
        HOLO / f"{card_id}_ink_guard.png", optimize=True)

    field = _reveal_field((w, h))
    Image.fromarray((field * 255.0 + 0.5).astype(np.uint8), "L").save(
        HOLO / f"{card_id}_ink_reveal.png", optimize=True)

    preview = _arrow_preview(im, vx, vy, ink, guard, weight).resize((320, 480))
    overlay = Image.new("RGB", (320, 480), (214, 52, 40))
    overlay = Image.composite(
        overlay, preview, guard_img.resize((320, 480)).point(lambda v: int(v * 0.34)))
    return overlay


def main() -> None:
    only = set(sys.argv[1:])
    ids = [cid for cid in IDS if not only or cid in only]
    cols, rows, w, h = 4, 4, 320, 480
    sheet = Image.new("RGB", (cols * w, rows * h), (22, 20, 18))
    for i, cid in enumerate(ids):
        tile = bake(cid)
        sheet.paste(tile, ((i % cols) * w, (i // cols) * h))
        print("baked", cid)
    sheet.save(OUTPUT / "ink_set_maps_preview.png")
    print("saved", (OUTPUT / "ink_set_maps_preview.png").relative_to(ROOT))


if __name__ == "__main__":
    main()
