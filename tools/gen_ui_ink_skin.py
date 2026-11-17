"""生成全局水墨按钮皮肤：墨签 / 朱印 / 纸签 / 印章 / 笔刷线。

使用方式：python tools/gen_ui_ink_skin.py
输出到 assets/ui/panel/，Godot 编辑器扫描后自动导入。
9-patch 贴图中心保持均匀，粗糙边缘全部落在拉伸边距内。

口径：设施界面统一「水墨纸本」方向；按钮是墨签而不是金属/塑料方框。
"""
from pathlib import Path
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path("assets/ui/panel")
OUT.mkdir(parents=True, exist_ok=True)
BRUSH = "assets/fonts/sanji_pomo.ttf"

W, H = 384, 96
MARGIN_X, MARGIN_Y = 40, 12


def noise_layer(seed: int, scale: float = 2.2) -> np.ndarray:
    rng = np.random.default_rng(seed)
    small = rng.normal(0, 1, (H // 8 + 2, W // 8 + 2)).astype(np.float32)
    img = Image.fromarray(np.uint8(np.clip(small * 34 + 128, 0, 255)))
    img = img.resize((W, H), Image.BICUBIC)
    arr = np.asarray(img, np.float32) - 128.0
    return arr * scale


def rounded_mask(radius: int = 12, inset: int = 2) -> Image.Image:
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle((inset, inset, W - 1 - inset, H - 1 - inset),
                        radius=radius, fill=255)
    # 只在边缘附近做粗糙化，中心保持不透，拉伸时不出接缝
    edge = Image.new("L", (W, H), 255)
    d2 = ImageDraw.Draw(edge)
    d2.rounded_rectangle((inset + 2, inset + 2, W - 3 - inset, H - 3 - inset),
                         radius=max(2, radius - 1), fill=0)
    rng = np.random.default_rng(7)
    grain = Image.fromarray(
        np.uint8(np.clip(rng.normal(0, 42, (H, W)) + 160, 0, 255))
    ).filter(ImageFilter.GaussianBlur(1.1))
    gmask = np.asarray(grain, np.float32) / 255.0
    edge_arr = np.asarray(edge, np.float32) / 255.0
    mask = np.asarray(m, np.float32) / 255.0
    rough = np.clip(mask * (1.0 - edge_arr) + mask * edge_arr * (gmask > 0.52), 0, 1)
    return Image.fromarray(np.uint8(np.clip(rough, 0, 1) * 255))


def mottle(size, base, seed, amount=5.0):
    rng = np.random.default_rng(seed)
    arr = np.zeros((size[1], size[0], 3), np.float32)
    arr[:] = base
    small = rng.normal(0, amount, (size[1] // 8 + 2, size[0] // 8 + 2))
    sm = Image.fromarray(np.uint8(np.clip(small + 128, 0, 255))).resize(size, Image.BICUBIC)
    arr += (np.asarray(sm, np.float32) - 128.0)[:, :, None] * 0.6
    return Image.fromarray(np.uint8(np.clip(arr, 0, 255))).convert("RGBA")


def fibers(img, rgba, count=90, seed=3, alpha=(8, 22)):
    rng = random.Random(seed)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        x = rng.randint(4, W - 10)
        y = rng.randint(4, H - 6)
        ln = rng.randint(5, 46)
        a = rng.randint(*alpha)
        d.line((x, y, x + ln, y + rng.choice([-1, 0, 0, 0, 1])), fill=rgba + (a,), width=1)
    return Image.alpha_composite(img, layer)


def dry_specks(img, rgba, count=50, seed=4, bounds=None):
    rng = random.Random(seed)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = bounds or (4, 4, W - 4, H - 4)
    for _ in range(count):
        x = rng.randint(x0, x1)
        y = rng.randint(y0, y1)
        r = rng.choice([1, 1, 1, 2])
        d.ellipse((x - r, y - r, x + r, y + r), fill=rgba + (rng.randint(14, 54),))
    return Image.alpha_composite(img, layer)


def border(img, color, inset=2, alpha=120, width=1):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((inset, inset, W - 1 - inset, H - 1 - inset),
                        radius=11, outline=color + (alpha,), width=width)
    return Image.alpha_composite(img, layer)


def make_button(name, base, kind):
    img = mottle((W, H), base, seed={"ink": 11, "seal": 22, "paper": 33}[kind])
    if kind == "ink":
        img = dry_specks(img, (250, 238, 208), count=38, seed=5, bounds=(4, 4, 60, H - 4))
        img = dry_specks(img, (250, 238, 208), count=38, seed=6, bounds=(W - 60, 4, W - 4, H - 4))
        img = fibers(img, (220, 205, 172), count=60, seed=8, alpha=(4, 12))
        img = border(img, (196, 164, 96), inset=2, alpha=145)
        img = border(img, (86, 72, 48), inset=4, alpha=80)
    elif kind == "seal":
        img = dry_specks(img, (48, 16, 14), count=80, seed=9, bounds=(4, 4, 70, H - 4))
        img = dry_specks(img, (48, 16, 14), count=80, seed=10, bounds=(W - 70, 4, W - 4, H - 4))
        img = fibers(img, (255, 205, 150), count=40, seed=12, alpha=(4, 14))
        img = border(img, (236, 194, 118), inset=2, alpha=155)
        img = border(img, (66, 22, 18), inset=4, alpha=110)
    else:
        img = fibers(img, (122, 104, 78), count=150, seed=13, alpha=(7, 20))
        img = fibers(img, (255, 250, 232), count=80, seed=14, alpha=(12, 30))
        img = dry_specks(img, (128, 104, 74), count=45, seed=15)
        img = border(img, (92, 76, 54), inset=2, alpha=120)

    mask = rounded_mask(radius=12, inset=2)
    img.putalpha(mask)
    img.save(OUT / name)
    print("saved", OUT / name, img.size)


def make_seal():
    size = 96
    img = mottle((size, size), (150, 46, 36), seed=77, amount=8)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((6, 6, size - 7, size - 7), radius=8,
                        outline=(255, 226, 184, 105), width=2)
    d.rounded_rectangle((13, 13, size - 14, size - 14), radius=4,
                        outline=(255, 226, 184, 80), width=1)
    # 印章文字：留白刻痕，避免在 12px 缩放时糊成一团
    try:
        font = ImageFont.truetype(BRUSH, 40)
        d.text((size / 2, size / 2 - 2), "令", font=font, anchor="mm",
               fill=(255, 230, 190, 185))
    except Exception:
        pass
    img = Image.alpha_composite(img, layer)
    arr = np.asarray(img).astype(np.uint8)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((4, 4, size - 5, size - 5), radius=9, fill=255)
    rng = np.random.default_rng(31)
    grain = rng.normal(0, 45, (size, size))
    rough = np.asarray(mask, np.float32) / 255.0
    rough = np.clip(rough * ((grain + 128) / 255.0 > 0.20), 0, 1)
    arr[:, :, 3] = np.uint8(np.clip(rough, 0, 1) * 200)
    Image.fromarray(arr).save(OUT / "seal_mark.png")
    print("saved", OUT / "seal_mark.png")


def make_brush_line():
    w, h = 256, 16
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = []
    for i in range(0, w + 1, 4):
        t = i / w
        # 两端收锋，中间略厚；一点点抖动让它像手写
        y = h / 2 + math.sin(t * math.pi * 1.3) * 0.7 + random.uniform(-0.35, 0.35)
        pts.append((i, y))
    for pass_i in range(3):
        p = [(x, y + random.uniform(-1.2, 1.2)) for x, y in pts]
        d.line(p, fill=(255, 255, 255, 255), width=4 - pass_i, joint="curve")
    # 干笔缺口
    px = np.asarray(layer).copy()
    rng = np.random.default_rng(21)
    alpha = px[:, :, 3].astype(np.float32)
    mask = (rng.random((h, w)) > 0.10).astype(np.float32)
    alpha *= mask
    px[:, :, 3] = np.uint8(np.clip(alpha, 0, 255))
    Image.fromarray(px).save(OUT / "brush_line.png")
    print("saved", OUT / "brush_line.png")


if __name__ == "__main__":
    random.seed(5)
    make_button("button_ink_9p.png", (24, 23, 29), "ink")
    make_button("button_seal_9p.png", (128, 42, 35), "seal")
    make_button("button_paper_9p.png", (223, 213, 190), "paper")
    make_seal()
    make_brush_line()


def make_talisman_paper():
    """符纸专用纹理：竖长米纸 + 纤维 + 折痕，不带边框/文字（边框由 TalismanCanvas 画）"""
    w, h = 384, 640
    rng = np.random.default_rng(123)
    arr = np.zeros((h, w, 3), np.float32)
    arr[:] = (228, 216, 190)
    fine = rng.normal(0, 4.2, (h, w, 1))
    arr += fine
    small = rng.normal(0, 12, (h // 12 + 2, w // 12 + 2))
    sm = Image.fromarray(np.uint8(np.clip(small + 128, 0, 255))).resize((w, h), Image.BICUBIC)
    arr += (np.asarray(sm, np.float32) - 128.0)[:, :, None] * 0.35
    # 边缘略暗，像一张被翻旧的纸
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(xx, w - 1 - xx) / (w * 0.12),
                      np.minimum(yy, h - 1 - yy) / (h * 0.08))
    arr *= (0.86 + 0.14 * np.clip(edge, 0, 1))[:, :, None]
    img = Image.fromarray(np.uint8(np.clip(arr, 0, 255))).convert("RGBA")

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(260):
        x = rng.integers(6, w - 6)
        y = rng.integers(6, h - 6)
        ln = rng.integers(8, 54)
        alpha = int(rng.integers(5, 14))
        d.line((x, y, x + ln, y + rng.choice([-1, 0, 0, 0, 1])),
               fill=(120, 100, 72, alpha), width=1)
    # 两道很淡的竖折痕
    for fx in (w / 3, w * 2 / 3):
        d.line((fx, 10, fx, h - 10), fill=(110, 92, 66, 22), width=1)
        d.line((fx + 1, 10, fx + 1, h - 10), fill=(255, 250, 236, 26), width=1)
    # 少量旧渍
    for _ in range(7):
        x = rng.integers(20, w - 20)
        y = rng.integers(20, h - 20)
        r = rng.integers(3, 11)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(130, 100, 60, rng.integers(4, 10)))
    img = Image.alpha_composite(img, layer)
    img.save(OUT / "talisman_paper.png")
    print("saved", OUT / "talisman_paper.png")
