"""离照：物品图标 / 卡面 / 战场 / 日轮贴图（2026-10-29）。"""
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

ITEM_SHEET = "vibe_images/lizhao_item_sheet_1793230826327_d2332b34.png"
CARD_SRC = "vibe_images/card_lizhao_src_1793230792511_1ed55e4e.png"
ARENA_SRC = "vibe_images/lizhao_arena_plain_src_1793231189407_9a1bcdb2.png"

ITEM_NAMES = [
    "equip_jinwen_zhanpao", "equip_zhuri_lv", "mat_chixiao_risui",
    "soul_lizhao", "tr_huozheng_ling",
]
ITEM_CROPS = [
    (0, 20, 435, 505),
    (420, 60, 765, 465),
    (805, 50, 1024, 485),
    (25, 485, 415, 980),
    (595, 500, 945, 965),
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
    al = res.getchannel("A").filter(ImageFilter.GaussianBlur(0.7)).point(
        lambda v: 0 if v < 96 else 255)
    res.putalpha(al)
    return res


def items():
    im = Image.open(ITEM_SHEET).convert("RGBA")
    os.makedirs(ICON, exist_ok=True)
    for idx, name in enumerate(ITEM_NAMES):
        cell = key_out(im.crop(ITEM_CROPS[idx]))
        bbox = cell.getbbox()
        if bbox:
            cell = cell.crop(bbox)
        scale = min(240.0 / cell.width, 240.0 / cell.height)
        nw, nh = max(1, int(cell.width * scale)), max(1, int(cell.height * scale))
        cell = cell.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        canvas.alpha_composite(cell, ((256 - nw) // 2, (256 - nh) // 2))
        canvas.save(os.path.join(ICON, name + ".png"))
        print("item icon", name, (nw, nh))


def card():
    im = Image.open(CARD_SRC).convert("RGB")
    # 中心竖裁到 2:3 再缩到 640×960，避免人物被压扁
    target_ratio = 2.0 / 3.0
    w, h = im.size
    if w / h > target_ratio:
        nw = int(h * target_ratio)
        x0 = (w - nw) // 2
        im = im.crop((x0, 0, x0 + nw, h))
    elif w / h < target_ratio:
        nh = int(w / target_ratio)
        y0 = (h - nh) // 2
        im = im.crop((0, y0, w, y0 + nh))
    im = im.resize((640, 960), Image.LANCZOS)
    os.makedirs(CARD, exist_ok=True)
    im.save(os.path.join(CARD, "card_boss_lizhao.png"))
    print("card", im.size)


def arena():
    im = Image.open(ARENA_SRC).convert("RGB")
    cw, ch = 1200, 676
    x0 = (im.width - cw) // 2
    y0 = (im.height - ch) // 2
    im = im.crop((x0, y0, x0 + cw, y0 + ch))
    os.makedirs(SCENES, exist_ok=True)
    im.save(os.path.join(SCENES, "lizhao_arena_ground.png"))
    print("arena", im.size)


def sun_orb():
    size = 256
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) * 0.5
    for y in range(size):
        for x in range(size):
            nx = (x - c) / c
            ny = (y - c) / c
            d = math.sqrt(nx * nx + ny * ny)
            ang = math.atan2(ny, nx)
            core = math.exp(-d * d * 18.0) * 1.10
            corona = math.exp(-d * d * 3.2) * (0.34 + 0.12 * math.sin(ang * 7.0 + 1.1))
            rays = (max(0.0, math.cos(ang * 10.0 + math.sin(ang * 3.0) * 0.5)) ** 14.0) \
                * math.exp(-d * 4.2) * 0.55
            a = max(0.0, min(1.0, core + corona + rays))
            px[x, y] = (255, 255, 255, int(a * 255))
    img.save(os.path.join(FX, "lizhao_sun_orb.png"))
    print("sun orb")


def sun_seal():
    size = 512
    gold = (206, 158, 84, 150)
    gold_l = (246, 214, 150, 120)
    red = (200, 72, 28, 125)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = size // 2
    for r, col, wd in ((234, gold, 4), (214, gold_l, 2), (176, red, 2), (150, gold, 1)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=wd)
    # 十六道扇骨：外长内短，读作日轮而不是雷印
    for k in range(16):
        a = 2 * math.pi * float(k) / 16.0 - math.pi * 0.5
        r0 = 150.0 if k % 2 == 0 else 176.0
        r1 = 228.0 if k % 2 == 0 else 210.0
        x0 = cx + math.cos(a) * r0
        y0 = cy + math.sin(a) * r0
        x1 = cx + math.cos(a) * r1
        y1 = cy + math.sin(a) * r1
        d.line([(x0, y0), (x1, y1)], fill=(gold if k % 2 == 0 else red), width=5 if k % 2 == 0 else 3)
    # 中央小日核
    d.ellipse([cx - 22, cy - 22, cx + 22, cy + 22], outline=gold_l, width=3)
    d.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=gold_l)
    img = img.filter(ImageFilter.GaussianBlur(0.4))
    halo = img.filter(ImageFilter.GaussianBlur(8))
    halo.putalpha(halo.getchannel("A").point(lambda v: int(v * 0.45)))
    img = Image.alpha_composite(halo, img)
    img.save(os.path.join(FX, "lizhao_sun_seal.png"))
    print("sun seal")


def main():
    os.makedirs(FX, exist_ok=True)
    items()
    card()
    arena()
    sun_orb()
    sun_seal()


if __name__ == "__main__":
    main()
