"""赫连霄：物品图标切图 / 卡面 / 战场地面 / 判词雷印 / 场地雷印（2026-10-29）。"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

ICON = "assets/ui/icon"
CARD = "assets/ui/codex"
SCENES = "assets/scenes"
FX = "assets/effects/skills"

ITEM_SHEET = "vibe_images/thunder_item_icons_sheet_1793209282497_9d6b2812.png"
CARD_SRC = "vibe_images/card_boss_heiliao_src_1793209153574_1d9f7aa8.png"
ARENA_SRC = "vibe_images/chixiao_arena_src_1793209179024_cd9d3d0f.png"

ITEM_NAMES = [
    "equip_leiwen_huqi", "equip_panguan_tiebi", "mat_chixiao_leijing",
    "soul_helianxiao", "tr_panguan_ling",
]


def key_out(img):
    a = np.array(img.convert("RGBA")).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mag = np.minimum(r, b) - g
    alpha = np.where(mag > 45, 0, 255).astype(np.uint8)
    gray = ((r + g + b) // 3).astype(np.int16)
    tint = mag > 6
    r2 = np.where(tint, np.minimum(r, gray + 10), r)
    b2 = np.where(tint, np.minimum(b, gray + 14), b)
    out = np.stack([r2, g, b2, alpha], axis=-1).astype(np.uint8)
    res = Image.fromarray(out, "RGBA")
    al = res.getchannel("A").filter(ImageFilter.GaussianBlur(0.7)).point(lambda v: 0 if v < 96 else 255)
    res.putalpha(al)
    return res


def items():
    im = Image.open(ITEM_SHEET).convert("RGBA")
    crops = [
        (10, 80, 590, 440), (600, 20, 1040, 450), (1080, 20, 1536, 520),
        (40, 430, 540, 1010), (640, 480, 1000, 1010),
    ]
    os.makedirs(ICON, exist_ok=True)
    for idx, name in enumerate(ITEM_NAMES):
        cell = key_out(im.crop(crops[idx]))
        bbox = cell.getbbox()
        if bbox:
            cell = cell.crop(bbox)
        # 等比放进 240×240，居中
        scale = min(240.0 / cell.width, 240.0 / cell.height)
        nw, nh = max(1, int(cell.width * scale)), max(1, int(cell.height * scale))
        cell = cell.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        canvas.alpha_composite(cell, ((256 - nw) // 2, (256 - nh) // 2))
        canvas.save(os.path.join(ICON, name + ".png"))
        print("item icon", name, (nw, nh))


def card():
    im = Image.open(CARD_SRC).convert("RGB")
    im = im.resize((640, 960), Image.LANCZOS)
    os.makedirs(CARD, exist_ok=True)
    im.save(os.path.join(CARD, "card_boss_heiliao.png"))
    print("card saved", im.size)


def arena():
    im = Image.open(ARENA_SRC).convert("RGB")
    # 中心裁 1200×676，避开右下角水印
    cw, ch = 1200, 676
    x0 = (im.width - cw) // 2
    y0 = (im.height - ch) // 2
    im = im.crop((x0, y0, x0 + cw, y0 + ch))
    os.makedirs(SCENES, exist_ok=True)
    im.save(os.path.join(SCENES, "chixiao_arena_ground.png"))
    print("arena saved", im.size)


def glow(size, color, radius, alpha=120):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size
    d.ellipse([w * 0.5 - radius, h * 0.5 - radius, w * 0.5 + radius, h * 0.5 + radius],
              fill=(color[0], color[1], color[2], alpha))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.4))


def bolt_polygon(cx, cy, w, h):
    return [
        (cx - w * 0.10, cy - h * 0.50), (cx + w * 0.32, cy - h * 0.50),
        (cx + w * 0.04, cy - h * 0.06), (cx + w * 0.36, cy - h * 0.06),
        (cx - w * 0.26, cy + h * 0.50), (cx - w * 0.04, cy + h * 0.04),
        (cx - w * 0.34, cy + h * 0.04),
    ]


def law_seal():
    size = 256
    gold = (212, 168, 88, 255)
    gold_l = (250, 220, 148, 255)
    purple = (170, 120, 255, 255)
    purple_l = (236, 214, 255, 255)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = size // 2
    # 外双环 + 八枚刻齿
    d.ellipse([cx - 104, cy - 104, cx + 104, cy + 104], outline=gold, width=5)
    d.ellipse([cx - 90, cy - 90, cx + 90, cy + 90], outline=gold_l, width=2)
    for k in range(8):
        a = TAU = 2 * math.pi * float(k) / 8.0 - math.pi * 0.5
        x0 = cx + math.cos(a) * 104.0
        y0 = cy + math.sin(a) * 104.0
        x1 = cx + math.cos(a) * 116.0
        y1 = cy + math.sin(a) * 116.0
        d.line([(x0, y0), (x1, y1)], fill=purple, width=4)
    # 中央雷印
    d.polygon(bolt_polygon(cx, cy + 2, 88, 136), fill=purple)
    d.line(bolt_polygon(cx, cy + 2, 88, 136) + [bolt_polygon(cx, cy + 2, 88, 136)[0]],
           fill=purple_l, width=2)
    d.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=gold_l)
    img = ac.polish(img, grain=0.06, rim_alpha=0.10)
    halo = img.filter(ImageFilter.GaussianBlur(5))
    halo.putalpha(halo.getchannel("A").point(lambda v: int(v * 0.70)))
    img = Image.alpha_composite(halo, img)
    img.save(os.path.join(FX, "thunder_law_seal.png"))
    print("law seal")


def arena_seal():
    size = 512
    gold = (190, 150, 80, 120)
    gold_l = (238, 206, 140, 90)
    purple = (150, 100, 240, 95)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = size // 2
    for r, col, wd in ((232, gold, 4), (214, gold_l, 1), (170, purple, 2), (152, gold, 1)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=wd)
    # 八方雷齿
    for k in range(8):
        a = 2 * math.pi * float(k) / 8.0 - math.pi * 0.5
        x0 = cx + math.cos(a) * 152.0
        y0 = cy + math.sin(a) * 152.0
        x1 = cx + math.cos(a) * 214.0
        y1 = cy + math.sin(a) * 214.0
        d.line([(x0, y0), (x1, y1)], fill=purple, width=4)
        d.line([(x1 - 9, y1 - 9), (x1 + 9, y1 + 9)], fill=gold_l, width=2)
    # 中央雷印只描边 + 极淡填充：它是地面纹样，不是一把巨剑
    pts = bolt_polygon(cx, cy, 112, 168)
    d.polygon(pts, fill=(100, 60, 170, 38))
    d.line(pts + [pts[0]], fill=gold_l, width=3)
    d.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=gold_l)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    halo = img.filter(ImageFilter.GaussianBlur(8))
    halo.putalpha(halo.getchannel("A").point(lambda v: int(v * 0.45)))
    img = Image.alpha_composite(halo, img)
    img.save(os.path.join(FX, "chixiao_seal.png"))
    print("arena seal")


if __name__ == "__main__":
    items()
    card()
    arena()
    law_seal()
    arena_seal()
