"""锻造工坊·墨夜炉火：宽幅舞台 + 木架/纸签/铜牌/纸卷控件贴图。

生成 assets/ui/forge/ 下的 9-patch 控件与 PIL 版舞台 stage_night_pil.png。
（正式舞台 stage_night.png 由 tools/grade_forge_stage.py 从 AI 原片调色生成，本脚本不再写它。）
舞台以 assets/scenes/facilities/forge.png 的手绘笔触为唯一风格基准：
镜像裁切出「左炉 / 中砧 / 右剑架」的 16:9 近景，再补墨墙、石地、木梁、烟尘与炉光。
"""
from pathlib import Path
import math
import random

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

OUT = Path("assets/ui/forge")
OUT.mkdir(parents=True, exist_ok=True)
SRC = Path("assets/scenes/facilities/forge.png")
BRUSH = "assets/fonts/sanji_pomo.ttf"
W, H = 1792, 1008


def noise(shape, seed, scale=2.0):
    rng = np.random.default_rng(seed)
    small = rng.normal(0, 1, (shape[0] // 10 + 2, shape[1] // 10 + 2)).astype(np.float32)
    im = Image.fromarray(np.uint8(np.clip(small * 40 + 128, 0, 255)))
    im = im.resize((shape[1], shape[0]), Image.BICUBIC)
    return (np.asarray(im, np.float32) - 128.0) * scale


def paper_grain(size, base, seed=1, amount=0.08, fibers=90):
    w, h = size
    arr = np.zeros((h, w, 3), np.float32)
    arr[:] = base
    arr += noise((h, w), seed, amount)[..., None]
    img = Image.fromarray(np.uint8(np.clip(arr, 0, 255))).convert("RGBA")
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rng = random.Random(seed + 7)
    for _ in range(fibers):
        x, y = rng.randint(4, w - 10), rng.randint(4, h - 6)
        ln = rng.randint(5, max(8, w // 5))
        col = (68, 54, 38, rng.randint(4, 12)) if rng.random() < 0.5 \
            else (255, 248, 232, rng.randint(4, 10))
        d.line((x, y, x + ln, y + rng.choice([-1, 0, 0, 1])), fill=col, width=1)
    return Image.alpha_composite(img, layer)


def rounded_alpha(size, radius, inset=2, rough=0.0, seed=3):
    w, h = size
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle((inset, inset, w - 1 - inset, h - 1 - inset),
                        radius=radius, fill=255)
    if rough > 0:
        arr = np.asarray(m, np.float32) / 255.0
        edge = np.asarray(m.filter(ImageFilter.FIND_EDGES), np.float32) / 255.0
        edge = np.clip(edge * 4.0, 0, 1)
        rng = np.random.default_rng(seed)
        grain = rng.normal(0.5, 0.28, (h, w))
        arr = arr * (1.0 - edge * 0.4) + arr * edge * (grain > 0.34)
        m = Image.fromarray(np.uint8(np.clip(arr, 0, 1) * 255))
    return m


def add_vignette(img, strength=0.55):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-w * 0.18, -h * 0.25, w * 1.18, h * 1.25), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(150))
    dark = Image.new("RGBA", (w, h), (4, 4, 6, 255))
    dark.putalpha(mask.point(lambda v: int((255 - v) * strength)))
    return Image.alpha_composite(img.convert("RGBA"), dark)


def radial_glow(img, center, radius, color, alpha=0.55):
    w, h = img.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(14, 0, -1):
        r = radius * i / 14.0
        a = int(alpha * 255 * (1.0 - i / 15.0) ** 2 * 0.25)
        d.ellipse((center[0] - r, center[1] - r * 0.8,
                   center[0] + r, center[1] + r * 0.8), fill=color + (a,))
    layer = layer.filter(ImageFilter.GaussianBlur(38))
    return Image.alpha_composite(img.convert("RGBA"), layer)


def brush_circle(img, center, radius, color, alpha=30, width=9, seed=9):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    for k in range(4):
        pts = []
        for i in range(0, 181):
            a = math.radians(i * 2.0 + rng.uniform(-0.5, 0.5))
            rr = radius * (1.0 + rng.uniform(-0.012, 0.012)) + rng.uniform(-2, 2)
            pts.append((center[0] + math.cos(a) * rr,
                        center[1] + math.sin(a) * rr * 0.86))
        d.line(pts, fill=color + (max(4, alpha // (k + 1)),), width=max(2, width - k * 2), joint="curve")
    layer = layer.filter(ImageFilter.GaussianBlur(1.2))
    return Image.alpha_composite(img.convert("RGBA"), layer)


def draw_wall_and_floor(img):
    w, h = img.size
    d = ImageDraw.Draw(img)
    # stone floor slabs
    rng = random.Random(11)
    for row in range(5):
        y0 = int(h * (0.58 + row * 0.085))
        y1 = int(h * (0.58 + (row + 1) * 0.085)) + 3
        x = -40
        while x < w + 40:
            ww = rng.randint(170, 300)
            shade = rng.randint(30, 46) + row * 3
            d.polygon([(x, y0), (x + ww, y0 - rng.randint(0, 5)),
                       (x + ww + rng.randint(-10, 10), y1),
                       (x + rng.randint(-8, 8), y1 + rng.randint(-4, 6))],
                      fill=(shade, shade - 3, shade + 2), outline=(12, 11, 13))
            # subtle cracks
            if rng.random() < 0.7:
                sx = rng.randint(x + 20, x + ww - 20)
                d.line((sx, y0 + 6, sx + rng.randint(-20, 20), y1 - 6),
                       fill=(18, 17, 18, 160), width=1)
            x += ww - 4
    # wall blocks
    for row in range(6):
        y0 = int(h * (0.05 + row * 0.09))
        y1 = int(h * (0.05 + (row + 1) * 0.09))
        x = -60
        while x < w + 60:
            ww = rng.randint(120, 230)
            shade = rng.randint(23, 35)
            d.rectangle((x, y0, x + ww, y1), fill=(shade, shade - 2, shade + 3),
                        outline=(10, 10, 12))
            x += ww + rng.randint(-4, 6)
    # ceiling beams
    for x, ww in [(-30, 420), (440, 520), (1000, 430), (1470, 380)]:
        d.rectangle((x, -30, x + ww, 130), fill=(24, 18, 14), outline=(8, 6, 6))
        for k in range(12):
            yy = rng.randint(8, 114)
            d.line((x + 8, yy, x + ww - 8, yy + rng.randint(-3, 3)),
                   fill=(42, 30, 22, 120), width=1)
    # chains far right
    for cx in (1680, 1712, 1742):
        d.line((cx, -20, cx + rng.randint(-6, 6), 300), fill=(45, 42, 38), width=3)
        for yy in range(0, 300, 14):
            d.ellipse((cx - 3, yy, cx + 3, yy + 9), outline=(70, 64, 54), width=1)
    return img


def build_stage():
    src = Image.open(SRC).convert("RGBA")
    sw, sh = src.size
    crop = src.crop((int(sw * 0.04), int(sh * 0.26), int(sw * 0.96), int(sh * 0.78)))
    crop = crop.transpose(Image.FLIP_LEFT_RIGHT).resize((W, H), Image.LANCZOS)
    # 去除抠图时残留的半透明底：内部保持实体，轮廓保留 1~2px 柔边
    a = np.asarray(crop.getchannel("A"), np.float32)
    a = np.clip((a - 6.0) / 46.0, 0.0, 1.0) * 255.0
    crop.putalpha(Image.fromarray(np.uint8(a)).filter(ImageFilter.GaussianBlur(0.6)))

    bg = Image.new("RGBA", (W, H), (18, 17, 20, 255))
    bg = draw_wall_and_floor(bg)
    # ink wash texture / soot
    arr = np.asarray(bg.convert("RGB"), np.float32)
    arr += noise((H, W), 21, 0.22)[..., None]
    bg = Image.fromarray(np.uint8(np.clip(arr, 0, 255))).convert("RGBA")
    bg = radial_glow(bg, (int(W * 0.22), int(H * 0.57)), int(W * 0.34),
                     (255, 160, 70), 0.55)
    bg = brush_circle(bg, (int(W * 0.50), int(H * 0.48)), int(W * 0.115),
                      (208, 180, 132), 34, 8, seed=5)
    # smoke
    smoke = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(smoke)
    rng = random.Random(31)
    for _ in range(9):
        cx, cy = rng.randint(0, W), rng.randint(120, H - 80)
        rx, ry = rng.randint(120, 360), rng.randint(50, 150)
        sd.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(154, 148, 138, 16))
    smoke = smoke.filter(ImageFilter.GaussianBlur(55))
    bg = Image.alpha_composite(bg, smoke)

    # hand-drawn forge, mirrored and close-up
    bg.alpha_composite(crop, (0, 0))
    # 原画石台上躺着一把旧锤子（镜像后落到舞台右侧），会和交互锤撞成「两把锤」。
    erase_old_hammer(bg)
    # 砧面压出一圈长期使用的黑印，装备图标放上去才不会被亮金属糊住
    make_anvil_scorch(bg)

    # darken right edge for the weapon rack UI
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for x in range(int(W * 0.68), W):
        a = int(150 * max(0.0, (x - W * 0.68) / (W * 0.32)) ** 1.3)
        gd.rectangle((x, 0, x + 1, H), fill=(8, 7, 9, a))
    bg = Image.alpha_composite(bg, grad)

    # warm light bloom on the anvil face / furnace
    bg = radial_glow(bg, (int(W * 0.20), int(H * 0.55)), int(W * 0.14),
                     (255, 138, 52), 0.38)
    bg = radial_glow(bg, (int(W * 0.50), int(H * 0.43)), int(W * 0.10),
                     (255, 192, 120), 0.12)

    # foreground soot / vignette
    bg = add_vignette(bg, 0.46)
    # bottom shadow for UI
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for i in range(6):
        a = 18 - i * 2
        sd.rectangle((0, H - 150 + i * 18, W, H - 120 + i * 18),
                     fill=(5, 4, 6, max(0, a)))
    bg = Image.alpha_composite(bg, shadow)
    # 正式舞台已由 grade_forge_stage.py 的 AI 调色版接管，这里只留 PIL 备选版，
    # 同名输出会在重跑时把接进游戏的那张冲掉。
    bg.convert("RGB").save(OUT / "stage_night_pil.png")
    print("saved", OUT / "stage_night_pil.png", bg.size)


# ===================== 9-patch controls =====================

def wood_texture(size, base=(46, 32, 23), seed=1):
    w, h = size
    rng = np.random.default_rng(seed)
    arr = np.zeros((h, w, 3), np.float32)
    arr[:] = base
    arr += noise((h, w), seed, 0.12)[..., None]
    img = Image.fromarray(np.uint8(np.clip(arr, 0, 255))).convert("RGBA")
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = random.Random(seed + 3)
    for _ in range(max(20, h // 4)):
        y = r.randint(2, h - 3)
        amp = r.uniform(1.0, 5.0)
        pts = []
        for x in range(0, w, 6):
            pts.append((x, y + math.sin(x * 0.02 + r.random() * 2) * amp))
        d.line(pts, fill=(28, 19, 14, r.randint(50, 110)), width=1)
    for _ in range(3):
        cx, cy = r.randint(20, w - 20), r.randint(10, h - 10)
        for k in range(4):
            d.ellipse((cx - 13 - k * 3, cy - 5 - k, cx + 13 + k * 3, cy + 5 + k),
                      outline=(24, 16, 12, 80), width=1)
    return Image.alpha_composite(img, layer)


def nine_patch(name, size, base, radius, border, content_inset, wood=False, metal=False):
    w, h = size
    if wood:
        img = wood_texture(size, base, seed=7)
    else:
        img = paper_grain(size, base, seed=4, amount=0.08)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((2, 2, w - 3, h - 3), radius=radius,
                        outline=border + (220,), width=2)
    if metal:
        # rivets
        for x, y in [(18, 18), (w - 19, 18), (18, h - 19), (w - 19, h - 19)]:
            d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=(112, 88, 45, 255),
                      outline=(32, 24, 14, 255), width=2)
            d.ellipse((x - 3, y - 4, x + 2, y + 1), fill=(196, 164, 92, 160))
    mask = rounded_alpha(size, radius, 2, rough=0.0)
    img.putalpha(mask)
    img.save(OUT / name)
    print("saved", OUT / name, size)


def make_brass_plaque():
    """锻打铭牌：用旧黄铜，不用亮黄色。

    整块平涂的 mustard 色在墨色舞台里像贴了张便利贴，所以做上上亮下暗的锻打
    渐变、氧化斑和拉丝，四角留铆钉。尺寸和圆角要和 nine_patch 版保持一致，
    面板那边的 9-patch 边距才不用改。

    氧化斑和拉丝必须画在单独的图层上再 alpha_composite：ImageDraw 在 RGBA 底图
    上是「覆盖」而不是「混合」，fill 里的 alpha 只会被写进 alpha 通道，末尾
    putalpha 一盖，斑和纹就变成实心的绿块与白线。
    """
    w, h = 512, 256
    rng = np.random.default_rng(31)
    top = np.array((108, 88, 46), np.float32)
    bot = np.array((56, 44, 24), np.float32)
    g = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None, None]
    arr = np.broadcast_to(top[None, None, :] * (1 - g) + bot[None, None, :] * g,
                          (h, w, 3)).copy()
    arr += noise((h, w), 31, 0.05)[..., None]
    arr += noise((h, w), 57, 0.025)[..., None]
    img = Image.fromarray(np.uint8(np.clip(arr, 0, 255))).convert("RGBA")
    detail = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(detail)
    # 氧化斑：暗绿褐的不规则块，压在铜面上
    for _ in range(8):
        cx, cy = int(rng.integers(10, w - 10)), int(rng.integers(8, h - 8))
        rx, ry = int(rng.integers(8, 18)), int(rng.integers(5, 11))
        tone = (52, 60, 40, int(rng.integers(14, 30)))
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=tone)
    # 拉丝：横向细纹
    for _ in range(28):
        y = int(rng.integers(4, h - 4))
        x0 = int(rng.integers(0, w - 40))
        ln = int(rng.integers(18, 52))
        d.line((x0, y, min(w - 3, x0 + ln), y),
               fill=(246, 224, 176, int(rng.integers(6, 14))), width=1)
    # 边缘磨损：内缩几圈暗边
    for i in range(5):
        inset = 3 + i * 3
        d.rounded_rectangle((inset, inset, w - 1 - inset, h - 1 - inset),
                            radius=12, outline=(26, 20, 11, 46 - i * 7), width=2)
    d.rounded_rectangle((2, 2, w - 3, h - 3), radius=12,
                        outline=(140, 112, 56, 200), width=2)
    for x, y in [(18, 18), (w - 19, 18), (18, h - 19), (w - 19, h - 19)]:
        d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=(92, 73, 36, 255),
                  outline=(24, 18, 10, 255), width=2)
        d.ellipse((x - 3, y - 4, x + 2, y + 1), fill=(178, 149, 88, 150))
    detail = detail.filter(ImageFilter.GaussianBlur(0.6))
    img.alpha_composite(detail)
    img.putalpha(rounded_alpha((w, h), 12, 2, rough=0.0))
    img.save(OUT / "brass_plaque_9p.png")
    print("saved", OUT / "brass_plaque_9p.png", (w, h))


def make_scroll():
    w, h = 720, 540
    img = paper_grain((w, h), (196, 180, 150), seed=12, amount=0.09, fibers=180)
    d = ImageDraw.Draw(img)
    for i in range(6):
        inset = 8 + i * 2
        d.rounded_rectangle((inset, inset, w - 1 - inset, h - 1 - inset),
                            radius=10, outline=(120, 94, 62, max(10, 50 - i * 7)), width=1)
    d.line((36, 30, 34, h - 30), fill=(128, 94, 56, 28), width=2)
    d.line((w - 36, 30, w - 34, h - 30), fill=(128, 94, 56, 28), width=2)
    _scroll_vignette(img)
    mask = rounded_alpha((w, h), 12, 2)
    img.putalpha(mask)
    img.save(OUT / "paper_scroll_9p.png")
    print("saved", OUT / "paper_scroll_9p.png")


def _scroll_vignette(img):
    """四周压暗一圈：整张平白的纸在夜里像一块灯板，压出边缘才像被炉火照着的纸。

    同样要画在独立图层上再 composite，直接在 RGBA 底图上画会把 alpha 写花。
    """
    w, h = img.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx - (w - 1) * 0.5) / ((w - 1) * 0.5)
    ny = (yy - (h - 1) * 0.5) / ((h - 1) * 0.5)
    # 9-patch 会把四边拉伸，所以暗边只允许落在 texture_margin 之内（约 42/36 像素）
    edge = np.maximum(np.abs(nx) * (w * 0.5 - 46.0) / (w * 0.5),
                      np.abs(ny) * (h * 0.5 - 40.0) / (h * 0.5))
    fall = np.clip((edge - 0.82) / 0.18, 0.0, 1.0) ** 1.8
    dark = Image.fromarray(np.uint8(fall * 66.0)).convert("L")
    tint = Image.new("RGBA", (w, h), (58, 44, 28, 255))
    tint.putalpha(dark)
    img.alpha_composite(tint)


def make_tag():
    w, h = 176, 220
    img = paper_grain((w, h), (220, 206, 178), seed=22, amount=0.08, fibers=60)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((8, 28, w - 9, h - 10), radius=8,
                        outline=(128, 98, 58, 160), width=2)
    d.rounded_rectangle((13, 33, w - 14, h - 15), radius=5,
                        outline=(150, 118, 70, 70), width=1)
    # punched hole
    d.ellipse((w / 2 - 7, 12, w / 2 + 7, 26), fill=(30, 24, 18, 255),
              outline=(198, 166, 104, 200), width=2)
    d.line((w / 2, 8, w / 2, 18), fill=(120, 92, 54, 220), width=2)
    mask = rounded_alpha((w, h), 10, 2)
    img.putalpha(mask)
    img.save(OUT / "paper_tag_9p.png")
    print("saved", OUT / "paper_tag_9p.png")


def make_dish():
    w, h = 220, 140
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((10, 54, w - 10, h - 10), fill=(36, 29, 22, 255),
              outline=(118, 92, 48, 255), width=4)
    d.ellipse((20, 46, w - 20, h - 28), fill=(54, 42, 30, 255),
              outline=(172, 136, 70, 220), width=2)
    d.arc((26, 52, w - 26, h - 36), 200, 340, fill=(224, 188, 112, 160), width=2)
    for x, y, r in [(70, 96, 8), (94, 102, 6), (118, 93, 7), (140, 102, 5)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=(92, 154, 170, 255),
                  outline=(190, 228, 230, 190), width=1)
    img.save(OUT / "crystal_dish.png")
    print("saved", OUT / "crystal_dish.png")


def make_beam():
    w, h = 1024, 100
    img = wood_texture((w, h), (40, 28, 20), seed=44)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 4, w, 8), fill=(86, 64, 38, 180))
    d.rectangle((0, h - 8, w, h - 4), fill=(20, 14, 10, 210))
    for x in (60, w - 60):
        d.ellipse((x - 10, h / 2 - 10, x + 10, h / 2 + 10),
                  fill=(106, 84, 44, 255), outline=(24, 18, 12, 255), width=2)
    img.save(OUT / "wood_beam_9p.png")
    print("saved", OUT / "wood_beam_9p.png")


def make_toast():
    w, h = 640, 76
    img = paper_grain((w, h), (222, 208, 180), seed=51, amount=0.08, fibers=90)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((8, 8, w - 9, h - 9), radius=6, outline=(120, 90, 54, 190), width=2)
    for i in range(3):
        d.line((24 + i * 3, 18, 20 + i * 3, h - 18), fill=(120, 90, 54, 26), width=1)
        d.line((w - 24 - i * 3, 18, w - 20 - i * 3, h - 18), fill=(120, 90, 54, 26), width=1)
    mask = rounded_alpha((w, h), 8, 2)
    img.putalpha(mask)
    img.save(OUT / "toast_paper_9p.png")
    print("saved", OUT / "toast_paper_9p.png")


def make_melt_tray():
    w, h = 720, 300
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # shadow
    d.rounded_rectangle((16, 24, w - 12, h - 8), radius=24, fill=(4, 4, 5, 150))
    # iron tray
    d.rounded_rectangle((14, 8, w - 14, h - 22), radius=22,
                        fill=(38, 33, 28, 250), outline=(12, 10, 9, 255), width=4)
    d.rounded_rectangle((28, 20, w - 28, h - 36), radius=16,
                        outline=(152, 116, 62, 130), width=2)
    d.rounded_rectangle((38, 28, w - 38, h - 46), radius=12,
                        fill=(28, 24, 21, 220), outline=(84, 64, 40, 150), width=1)
    for x, y in [(40, 32), (w - 40, 32), (40, h - 54), (w - 40, h - 54)]:
        d.ellipse((x - 8, y - 8, x + 8, y + 8), fill=(120, 94, 52, 255),
                  outline=(22, 16, 12, 255), width=2)
    # soot / heat
    for i in range(7):
        d.ellipse((80 + i * 78, 190, 170 + i * 78, 250), fill=(255, 96, 24, 8))
    img.save(OUT / "melt_tray_9p.png")
    print("saved", OUT / "melt_tray_9p.png")


def erase_old_hammer(bg):
    """补掉原画石台上那把旧锤子，否则它会和交互锤撞成「两把锤」。

    这块在画面最右、兵器架后面，本来就被压暗，所以按「墨墙 + 石台」的取样色
    重铺一层就够了；硬贴一块原画会带进右侧的斑驳暗块，反而更脏。
    石台与墨墙的交界取斜率 0.46 的直线，和周围走势一致。
    """
    x0, x1, y0, y1 = 1176, 1552, 386, 634
    w, h = x1 - x0, y1 - y0
    a = np.asarray(bg.convert("RGB"), np.float32)

    def mean(box):
        return a[box[1]:box[3], box[0]:box[2]].reshape(-1, 3).mean(0)

    wall_l, wall_r = mean((1300, 190, 1400, 300)), mean((1600, 300, 1700, 420))
    slab_l, slab_r = mean((1300, 650, 1380, 700)), mean((1560, 650, 1660, 700))
    t = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :, None]
    wall_c = wall_l[None, None, :] * (1 - t) + wall_r[None, None, :] * t
    slab_c = slab_l[None, None, :] * (1 - t) + slab_r[None, None, :] * t

    xs = np.arange(x0, x1)
    yb = np.clip(np.round(447 + (xs - 1245) * 0.46), y0 + 10, y1 - 14)
    rows = np.arange(y0, y1, dtype=np.float32)[:, None]
    is_wall = rows < yb[None, :]
    # 石台靠近交界处压一道接触阴影，别像一块平色纸
    depth = np.clip((rows - yb[None, :]) / 165.0, 0.0, 1.0)
    shade = np.where(is_wall, 1.0, 0.62 + 0.33 * depth)
    patch = np.where(is_wall[..., None], wall_c, slab_c) * shade[..., None]
    patch += noise((h, w), 77, 0.16)[..., None]
    patch += noise((h, w), 91, 0.05)[..., None]

    img = Image.fromarray(np.uint8(np.clip(patch, 0, 255))).convert("RGBA")
    # 墨墙那半边要接上原有的砖纹，否则只剩一片噪点，和右侧的砖层对不上。
    # 现场量出来：横缝每 80 像素一道（y=407 起），竖缝每 125 像素、隔行错半格。
    lines = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    for y in range(y0 - y0 % 80, y1, 80):
        if y % 80 == 407 % 80:
            ld.line((0, y - y0, w, y - y0), fill=(14, 14, 18, 255), width=3)
    row = (y0 - y0 % 80) // 80
    for y in range(y0 - y0 % 80, y1, 80):
        off = 1268 + (62 if row % 2 else 0)
        while off - 125 >= x0:
            off -= 125
        while off < x1:
            ld.line((off - x0, y - y0, off - x0, y - y0 + 80),
                    fill=(14, 14, 18, 255), width=3)
            off += 125
        row += 1
    lines = lines.filter(ImageFilter.GaussianBlur(1.6))
    wall_m = Image.fromarray(np.uint8(np.clip(is_wall * 255, 0, 255))).filter(
        ImageFilter.GaussianBlur(4))
    r, g, b, al = lines.split()
    lines.putalpha(ImageChops.multiply(al, wall_m))
    img.alpha_composite(lines)
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rectangle((20, 20, w - 20, h - 20), fill=255)
    # y0 取在铁砧犄角尖的下缘之外，只剩一小块角需要护住，免得补色啃掉犄角
    ImageDraw.Draw(m).polygon([(0, 0), (66, 0), (66, 4), (0, 16)], fill=0)
    m = m.filter(ImageFilter.GaussianBlur(13))
    img.putalpha(m)
    bg.alpha_composite(img, (x0, y0))


def make_anvil_scorch(bg):
    """砧面中央压一道烧黑的使用痕迹。

    原画砧面是亮金属，装备图标直接放上去会糊成一片；有了这块黑印，
    图标有了对比底，也顺手告诉玩家「东西就该落在这」。坐标按舞台像素量自砧面。
    """
    layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((930 - 158, 300 - 62, 930 + 158, 300 + 62), fill=(14, 12, 13, 178))
    d.ellipse((905 - 112, 296 - 40, 905 + 112, 296 + 40), fill=(9, 8, 10, 155))
    for cx, cy, r in ((848, 288, 13), (962, 306, 16), (1022, 292, 11)):
        d.ellipse((cx - r, cy - r * 0.55, cx + r, cy + r * 0.55),
                  fill=(6, 5, 7, 120))
    layer = layer.rotate(-6.0, resample=Image.BICUBIC, center=(930, 300))
    layer = layer.filter(ImageFilter.GaussianBlur(9))
    bg.alpha_composite(layer)


def make_hammer_shadow():
    w, h = 260, 90
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((18, 26, w - 18, h - 18), fill=(6, 5, 7, 120))
    img = img.filter(ImageFilter.GaussianBlur(14))
    img.save(OUT / "hammer_shadow.png")
    print("saved", OUT / "hammer_shadow.png")


if __name__ == "__main__":
    make_hammer_shadow()
    build_stage()
    make_beam()
    nine_patch("wood_plaque_9p.png", (512, 128), (49, 34, 24), 14,
               (150, 112, 62), 24, wood=True)
    nine_patch("paper_tag_9p.png", (176, 220), (220, 206, 178), 10,
               (128, 98, 58), 24)
    make_tag()
    make_brass_plaque()
    make_scroll()
    nine_patch("button_wood_9p.png", (320, 96), (48, 34, 24), 12,
               (146, 108, 58), 22, wood=True)
    nine_patch("button_paper_9p.png", (320, 96), (220, 204, 174), 12,
               (116, 86, 52), 22)
    nine_patch("button_seal_9p.png", (320, 96), (128, 42, 35), 12,
               (218, 172, 100), 22, metal=True)
    make_dish()
    make_toast()
    make_melt_tray()
    nine_patch("socket_bronze_9p.png", (192, 192), (54, 42, 30), 18,
               (146, 112, 58), 30, metal=True)
    nine_patch("rail_spine_9p.png", (80, 720), (42, 29, 20), 12,
               (106, 78, 42), 16, wood=True)
