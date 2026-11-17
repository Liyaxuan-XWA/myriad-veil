"""执烛（照影界第 2 位）· 替代素材生成 —— 2026-11-02

生图配额暂不可用（ImageGen 返回 403），按约束「先用别的替代，有配额后再换」：
本脚本用 PIL 画出**结构正确的替代立绘 / rig 分件 / 战场地面 /  decals / 图标 / 卡面**，
让骨骼动画、特效、战场、图鉴、卡包、选关字印全链路都能立刻在实机里被验证。
配色与 silhouette 按 docs/照影界第二位BOSS_设计案.md：青黑广袖 + 垂地墨色披影 + 空铜界灯。
配额恢复后用 tools/boss_art_prompts.py 的定妆流程重画并覆盖同名文件即可（脚本不动代码）。
"""

import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter, ImageOps

ROOT = r"D:\GodotProjects\myriad-veil"

INK = (12, 14, 22, 255)
ROBE = (30, 42, 63, 255)
ROBE_DARK = (18, 26, 42, 255)
ROBE_LIGHT = (48, 66, 96, 255)
CAPE = (8, 9, 16, 255)
SILVER = (201, 228, 242, 255)
SILVER_DIM = (130, 158, 186, 255)
BRONZE = (138, 106, 60, 255)
BRONZE_DARK = (92, 68, 36, 255)
SKIN = (232, 223, 210, 255)
HAIR = (16, 18, 28, 255)
EMBER = (250, 232, 176, 255)


def ensure(d):
    os.makedirs(d, exist_ok=True)


def new(w, h=None):
    return Image.new("RGBA", (w, w if h is None else h), (0, 0, 0, 0))


def paste_center(dst, src, cx, cy):
    dst.alpha_composite(src, (int(cx - src.width / 2), int(cy - src.height / 2)))


def outline(dr, pts, color, width=3):
    closed = list(pts) + [pts[0]]
    for i in range(len(closed) - 1):
        dr.line([closed[i], closed[i + 1]], fill=color, width=width)


# ---------------------------------------------------------------- 灯笼（独立件）
def draw_lantern(size=520, pivot=(0.5, 0.5)):
    """pivot：提手在画布里的相对位置，落在画布中心，便于绕手腕旋转。"""
    im = new(size, size)
    dr = ImageDraw.Draw(im)
    cx = size / 2.0
    cy = size / 2.0
    s = size / 520.0
    # 提钩 + 提梁
    dr.arc([cx - 46 * s, cy - 150 * s, cx + 46 * s, cy - 40 * s], 180, 360,
           fill=BRONZE_DARK, width=int(7 * s))
    dr.rectangle([cx - 10 * s, cy - 152 * s, cx + 10 * s, cy - 128 * s], fill=BRONZE_DARK)
    # 顶盖
    dr.polygon([(cx - 58 * s, cy - 96 * s), (cx + 58 * s, cy - 96 * s),
                (cx + 40 * s, cy - 122 * s), (cx - 40 * s, cy - 122 * s)],
               fill=BRONZE, outline=BRONZE_DARK, width=int(3 * s))
    # 六角灯身（框）
    top = cy - 96 * s
    bot = cy + 66 * s
    left_in = cx - 46 * s
    right_in = cx + 46 * s
    left_out = cx - 62 * s
    right_out = cx + 62 * s
    dr.polygon([(left_out, top + 12 * s), (right_out, top + 12 * s),
                (right_in, bot), (left_in, bot)], fill=ROBE_DARK)
    # 灯罩里那团「比周围更黑的暗」
    core = Image.new("RGBA", im.size, (0, 0, 0, 0))
    cdr = ImageDraw.Draw(core)
    cdr.ellipse([cx - 40 * s, top + 26 * s, cx + 40 * s, bot - 12 * s], fill=INK)
    im.alpha_composite(core.filter(ImageFilter.GaussianBlur(6 * s)))
    # 暗的边缘漏一点冷银（灯芯不是火，是光被吃掉的那圈）
    ring = Image.new("RGBA", im.size, (0, 0, 0, 0))
    rdr = ImageDraw.Draw(ring)
    rdr.ellipse([cx - 34 * s, top + 30 * s, cx + 34 * s, bot - 16 * s],
                outline=SILVER, width=int(4 * s))
    im.alpha_composite(ring.filter(ImageFilter.GaussianBlur(2.4 * s)), dest=(0, 0))
    dr = ImageDraw.Draw(im)
    # 竖向 ribs
    for fx in (-46, -18, 14, 46):
        dr.line([(cx + fx * s, top + 12 * s), (cx + fx * s * 0.86, bot)],
                fill=BRONZE_DARK, width=int(4 * s))
    # 底座
    dr.polygon([(left_in - 8 * s, bot), (right_in + 8 * s, bot),
                (right_in - 4 * s, bot + 22 * s), (left_in + 4 * s, bot + 22 * s)],
               fill=BRONZE, outline=BRONZE_DARK, width=int(3 * s))
    outline(dr, [(left_out, top + 12 * s), (right_out, top + 12 * s),
                 (right_in, bot), (left_in, bot)], (0, 0, 0, 255), int(3 * s))
    return im


# ---------------------------------------------------------------- 全身立绘
def draw_figure(with_lantern=True, big=False):
    """900x720 画布，脚在 y=706。big=True 时把影子画得更夸张（卡面用）。"""
    im = new(900, 720)
    dr = ImageDraw.Draw(im)
    cx = 460
    hem_y = 706
    # 1) 垂地披影（最外层墨块）—— 先画，压在袍子后面
    cape = [(cx - 74, 214), (cx - 126, 320), (cx - 178, 470),
            (cx - 196, hem_y - 6), (cx - 108, hem_y + 2), (cx - 46, 500), (cx - 30, 300)]
    if big:
        cape = [(cx - 78, 210), (cx - 150, 330), (cx - 250, 520),
                (cx - 300, hem_y + 4), (cx - 60, hem_y + 6), (cx - 20, 470), (cx - 30, 290)]
    dr.polygon(cape, fill=CAPE)
    # 2) 袍裙
    skirt = [(cx - 60, 424), (cx + 62, 424), (cx + 132, hem_y),
             (cx + 66, hem_y + 8), (cx - 4, hem_y - 4), (cx - 74, hem_y + 8), (cx - 130, hem_y)]
    dr.polygon(skirt, fill=ROBE)
    dr.polygon([(cx - 60, 424), (cx - 4, 430), (cx - 24, hem_y - 2), (cx - 130, hem_y)],
               fill=ROBE_DARK)
    # 3) 躯干
    torso = [(cx - 70, 206), (cx + 76, 206), (cx + 88, 330), (cx + 62, 430),
             (cx - 60, 430), (cx - 86, 330)]
    dr.polygon(torso, fill=ROBE)
    dr.polygon([(cx - 70, 206), (cx - 12, 200), (cx - 26, 430), (cx - 60, 430), (cx - 86, 330)],
               fill=ROBE_DARK)
    # 腰带 + 一枚银扣
    dr.polygon([(cx - 62, 396), (cx + 66, 396), (cx + 64, 424), (cx - 60, 424)], fill=INK)
    dr.ellipse([cx - 12, 398, cx + 16, 422], fill=SILVER_DIM)
    # 4) 左袖（垂袖，宽口）
    sleeve_l = [(cx - 70, 214), (cx - 128, 250), (cx - 168, 420),
                (cx - 120, 452), (cx - 74, 330)]
    dr.polygon(sleeve_l, fill=ROBE_LIGHT)
    outline(dr, sleeve_l, (0, 0, 0, 200), 3)
    # 5) 右臂（提灯臂，向前抬起）
    arm_r = [(cx + 76, 214), (cx + 150, 248), (cx + 206, 300),
             (cx + 188, 330), (cx + 120, 300), (cx + 74, 286)]
    dr.polygon(arm_r, fill=ROBE_LIGHT)
    outline(dr, arm_r, (0, 0, 0, 200), 3)
    dr.ellipse([cx + 196, 300, cx + 226, 330], fill=SKIN)   # 手
    # 6) 颈 / 头 / 发髻
    dr.polygon([(cx - 12, 178), (cx + 16, 178), (cx + 14, 210), (cx - 10, 210)], fill=SKIN)
    dr.ellipse([cx - 36, 92, cx + 40, 188], fill=SKIN)
    dr.polygon([(cx - 40, 120), (cx + 44, 120), (cx + 40, 84), (cx - 36, 84)], fill=HAIR)
    dr.ellipse([cx - 8, 58, cx + 24, 92], fill=HAIR)         # 髻
    dr.line([(cx + 30, 54), (cx + 52, 96)], fill=SILVER_DIM, width=4)  # 银簪
    # 低垂的眼与没有表情的嘴
    dr.line([(cx - 22, 140), (cx - 6, 144)], fill=INK, width=3)
    dr.line([(cx + 10, 144), (cx + 26, 140)], fill=INK, width=3)
    dr.line([(cx - 6, 166), (cx + 10, 166)], fill=(150, 120, 118, 255), width=2)
    outline(dr, torso, (0, 0, 0, 235), 4)
    outline(dr, skirt, (0, 0, 0, 235), 4)
    im = im.filter(ImageFilter.SMOOTH)
    dr = ImageDraw.Draw(im)
    # 袍面上的极淡水纹（只在裙摆内，横着走）
    for i in range(7):
        y = 470 + i * 30
        pts = [(cx - 110 + t, y + math.sin(t / 58.0 + i) * 7) for t in range(0, 221, 10)]
        dr.line(pts, fill=SILVER_DIM[:3] + (30,), width=2)
    if with_lantern:
        lamp = draw_lantern(520)
        paste_center(im, lamp, cx + 240, 330)
    return im


# ---------------------------------------------------------------- 图标件
def icon_canvas(size=256, pad=18):
    im = new(size, size)
    dr = ImageDraw.Draw(im)
    dr.rounded_rectangle([pad - 8, pad - 8, size - pad + 8, size - pad + 8], radius=18,
                         fill=(21, 26, 40, 255))
    dr.rounded_rectangle([pad - 8, pad - 8, size - pad + 8, size - pad + 8], radius=18,
                         outline=SILVER_DIM[:3] + (130,), width=3)
    return im, dr


def tip_glow(im, cx, cy, r, col=SILVER, a=170):
    g = new(im.width, im.height)
    gd = ImageDraw.Draw(g)
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col[:3] + (a,))
    im.alpha_composite(g.filter(ImageFilter.GaussianBlur(r * 0.45)))


def ink_band(dr, x0, y0, x1, y1, w0, w1, col=INK, edge=SILVER_DIM):
    """墨带 + 一道冷银边：图标底板本身是暗的，不描边就会黑压黑看不见。"""
    dx, dy = x1 - x0, y1 - y0
    n = math.hypot(dx, dy) or 1.0
    px, py = -dy / n, dx / n
    pts = [(x0 + px * w0, y0 + py * w0), (x1 + px * w1, y1 + py * w1),
           (x1 - px * w1, y1 - py * w1), (x0 - px * w0, y0 - py * w0)]
    dr.polygon(pts, fill=col)
    if edge is not None:
        outline(dr, pts, edge[:3] + (150,), 2)


def icon_shadow_cut():
    im, dr = icon_canvas()
    ink_band(dr, 60, 190, 200, 78, 12, 30, (16, 18, 30, 255))
    dr.arc([40, 30, 220, 210], 300, 30, fill=SILVER, width=7)
    tip_glow(im, 200, 78, 14)
    return im


def icon_shadow_reach():
    im, dr = icon_canvas()
    ink_band(dr, 38, 170, 214, 96, 8, 22, (14, 16, 26, 255))
    dr.line([(38, 170), (214, 96)], fill=SILVER_DIM[:3] + (150,), width=3)
    tip_glow(im, 214, 96, 18)
    dr.polygon([(38, 170), (60, 160), (52, 190)], fill=INK)
    return im


def icon_shadow_bind():
    im, dr = icon_canvas()
    ink_band(dr, 46, 150, 210, 150, 26, 12, (14, 16, 26, 255))
    for i, ang in enumerate((-50, 0, 50)):
        rad = math.radians(ang)
        x0 = 128 + math.cos(rad) * 14
        y0 = 150 + math.sin(rad) * 14
        dr.polygon([(x0, y0 - 10), (x0 + 60 * math.cos(rad), y0 + 34 - 6),
                    (x0 + 46 * math.cos(rad), y0 + 40), (x0, y0 + 10)],
                   fill=(20, 22, 38, 255))
    dr.ellipse([96, 118, 160, 182], outline=SILVER, width=4)
    tip_glow(im, 128, 150, 12, col=(150, 160, 220, 255), a=120)
    return im


def icon_shadow_step():
    im, dr = icon_canvas()
    for i in range(4):
        ink_band(dr, 44 + i * 12, 196 - i * 8, 176 + i * 10, 150 - i * 10,
                 9 - i, 4, (16, 18, 32, 255 - i * 40))
    dr.polygon([(150, 60), (196, 74), (176, 120), (132, 104)], fill=ROBE_LIGHT)
    outline(dr, [(150, 60), (196, 74), (176, 120), (132, 104)], (0, 0, 0, 235), 3)
    tip_glow(im, 190, 92, 12)
    return im


def icon_shadow_dim():
    im, dr = icon_canvas()
    tip_glow(im, 128, 128, 60, col=(250, 232, 176, 255), a=60)
    lamp = draw_lantern(150).resize((110, 110))
    paste_center(im, lamp, 128, 120)
    dr = ImageDraw.Draw(im)
    dr.ellipse([64, 176, 192, 206], fill=INK)
    dr.line([(56, 56), (200, 200)], fill=(120, 130, 170, 160), width=5)
    return im


def icon_shadow_beam():
    im, dr = icon_canvas()
    dr.line([(56, 196), (206, 60)], fill=SILVER, width=16)
    dr.line([(56, 196), (206, 60)], fill=(255, 255, 255, 220), width=5)
    tip_glow(im, 128, 128, 34, col=(160, 210, 250, 255), a=90)
    dr.ellipse([44, 184, 70, 210], fill=(206, 232, 246, 255))
    return im


def icon_shadow_split():
    im, dr = icon_canvas()
    ink_band(dr, 60, 186, 150, 96, 20, 8, (14, 16, 26, 255))
    for i in range(3):
        sh = new(256, 256)
        sd = ImageDraw.Draw(sh)
        ink_band(sd, 120 + i * 22, 150 - i * 20, 200 + i * 8, 84 - i * 16, 14 - i * 3, 5,
                 (18, 20, 34, 255 - i * 60))
        im.alpha_composite(sh)
    dr.ellipse([52, 170, 92, 210], fill=INK)
    tip_glow(im, 206, 78, 12)
    return im


def icon_shadow_longnight():
    im, dr = icon_canvas()
    lamp = draw_lantern(130).resize((88, 88))
    paste_center(im, lamp, 128, 112)
    dr = ImageDraw.Draw(im)
    for i in range(8):
        ang = i * math.tau / 8.0
        dr.line([(128 + math.cos(ang) * 108, 122 + math.sin(ang) * 92),
                 (128 + math.cos(ang) * 46, 122 + math.sin(ang) * 40)],
                fill=(16, 18, 32, 235), width=9)
    tip_glow(im, 128, 122, 26, col=(170, 200, 250, 255), a=110)
    return im


def icon_shadow_lamp():
    im, dr = icon_canvas()
    lamp = draw_lantern(190).resize((130, 130))
    paste_center(im, lamp, 128, 126)
    tip_glow(im, 128, 126, 44, col=(250, 232, 176, 255), a=70)
    dr = ImageDraw.Draw(im)
    ink_band(dr, 60, 208, 196, 208, 10, 4, (14, 16, 26, 255))
    tip_glow(im, 196, 208, 10)
    return im


# ---------------------------------------------------------------- 物品图标
def icon_weapon_blade():
    im, dr = icon_canvas()
    dr.polygon([(70, 200), (96, 206), (196, 62), (178, 50)], fill=INK)
    dr.polygon([(80, 198), (94, 202), (188, 68), (178, 60)], fill=(28, 32, 48, 255))
    dr.line([(92, 200), (186, 66)], fill=SILVER_DIM[:3] + (140,), width=2)
    dr.rectangle([58, 190, 104, 210], fill=BRONZE, outline=BRONZE_DARK, width=2)
    dr.rounded_rectangle([48, 206, 76, 232], radius=6, fill=BRONZE_DARK)
    tip_glow(im, 190, 60, 12, col=(180, 200, 230, 255), a=120)
    return im


def icon_pendant():
    im, dr = icon_canvas()
    dr.line([(128, 40), (128, 86)], fill=SILVER_DIM[:3] + (200,), width=4)
    dr.polygon([(128, 86), (166, 140), (128, 210), (90, 140)], fill=(20, 22, 36, 255))
    dr.polygon([(128, 96), (156, 140), (128, 196), (100, 140)], fill=INK)
    dr.ellipse([116, 128, 140, 152], fill=(10, 10, 16, 255))
    outline(dr, [(128, 86), (166, 140), (128, 210), (90, 140)], SILVER_DIM[:3] + (150,), 3)
    tip_glow(im, 128, 140, 16, col=(150, 170, 230, 255), a=80)
    return im


def icon_wax_material():
    im, dr = icon_canvas()
    for i, (x, y, r) in enumerate([(110, 120, 26), (150, 156, 20), (128, 190, 16)]):
        dr.polygon([(x, y - r), (x + r * 0.7, y), (x, y + r), (x - r * 0.7, y)],
                   fill=(36, 40, 58, 255))
        dr.polygon([(x, y - r * 0.6), (x + r * 0.4, y), (x, y + r * 0.7),
                    (x - r * 0.4, y)], fill=INK)
    dr.line([(96, 74), (110, 100)], fill=(60, 66, 88, 255), width=6)
    tip_glow(im, 150, 156, 12, col=(170, 190, 220, 255), a=70)
    return im


def icon_soul():
    im, dr = icon_canvas()
    g = new(256)
    gd = ImageDraw.Draw(g)
    gd.ellipse([70, 66, 186, 190], fill=(30, 40, 66, 220))
    im.alpha_composite(g.filter(ImageFilter.GaussianBlur(6)))
    dr = ImageDraw.Draw(im)
    lamp = draw_lantern(120).resize((76, 76))
    paste_center(im, lamp, 128, 120)
    dr = ImageDraw.Draw(im)
    for i in range(3):
        dr.arc([70 - i * 8, 150 - i * 6, 186 + i * 8, 208 + i * 8], 200, 340,
               fill=SILVER_DIM[:3] + (150 - i * 40,), width=3)
    tip_glow(im, 128, 120, 22, col=(170, 200, 240, 255), a=90)
    return im


def icon_token():
    im, dr = icon_canvas()
    dr.ellipse([56, 56, 200, 200], fill=BRONZE, outline=BRONZE_DARK, width=4)
    dr.ellipse([74, 74, 182, 182], fill=(24, 28, 44, 255))
    lamp = draw_lantern(110).resize((66, 66))
    paste_center(im, lamp, 128, 124)
    dr = ImageDraw.Draw(im)
    for i in range(6):
        ang = i * math.tau / 6.0
        dr.line([(128 + math.cos(ang) * 60, 128 + math.sin(ang) * 60),
                 (128 + math.cos(ang) * 70, 128 + math.sin(ang) * 70)],
                fill=SILVER_DIM, width=3)
    dr.polygon([(128, 40), (146, 58), (110, 58)], fill=BRONZE_DARK)
    return im


# ---------------------------------------------------------------- 战场地面
def make_ground(size=1024):
    random.seed(4211)
    im = Image.new("RGBA", (size, size), (8, 10, 16, 255))
    dr = ImageDraw.Draw(im)
    # 灯在偏北：一圈被照亮的银白水痕，向南迅速变暗
    pool = (size * 0.5, size * 0.20)
    for r in range(int(size * 0.72), 0, -3):
        k = r / (size * 0.72)
        lum = int(58 * (1.0 - k) ** 1.5)
        dr.ellipse([pool[0] - r, pool[1] - r * 0.66, pool[0] + r, pool[1] + r * 0.66],
                   fill=(10 + lum, 15 + int(lum * 1.2), 24 + int(lum * 1.45), 255))
    # 石坪六边格：压到几乎看不见（地面 tile 不许有大特征）
    grid = new(size, size)
    gd = ImageDraw.Draw(grid)
    step = 128
    for row in range(-1, size // int(step * 0.86) + 2):
        for col in range(-1, size // step + 2):
            cx = col * step + (step // 2 if row % 2 else 0)
            cy = row * step * 0.86
            d = math.hypot(cx - pool[0], (cy - pool[1]) / 0.66)
            a = int(max(0, 13 - d / 120.0))
            if a <= 0:
                continue
            pts = [(cx + 58 * math.cos(math.tau * i / 6 + 0.5),
                    cy + 58 * math.sin(math.tau * i / 6 + 0.5)) for i in range(6)]
            gd.polygon(pts, outline=(180, 205, 230, a))
    im.alpha_composite(grid.filter(ImageFilter.GaussianBlur(1.4)))
    dr = ImageDraw.Draw(im)
    ov = new(size, size)
    od = ImageDraw.Draw(ov)
    # 同心水痕：只在灯下几圈清晰
    for i in range(24):
        r = 70 + i * 40 + random.randint(-10, 10)
        a = max(0, 96 - i * 6)
        od.ellipse([pool[0] - r, pool[1] - r * 0.6, pool[0] + r, pool[1] + r * 0.6],
                   outline=(180, 220, 250, a), width=random.choice([1, 2, 2, 3]))
    # 被拉长的暗痕：从灯心向外辐射，教玩家「光从北边来、影子朝南铺」
    for i in range(54):
        ang = random.uniform(math.pi * 0.06, math.pi * 0.94)
        r0 = random.uniform(150, 560)
        ln = random.uniform(120, 420)
        x0 = pool[0] + math.cos(ang) * r0
        y0 = pool[1] + math.sin(ang) * r0 * 0.62
        x1 = x0 + math.cos(ang) * ln
        y1 = y0 + math.sin(ang) * ln * 0.62
        od.line([(x0, y0), (x1, y1)], fill=(3, 4, 9, random.randint(46, 104)),
                width=random.randint(8, 26))
    im.alpha_composite(ov.filter(ImageFilter.GaussianBlur(2.6)))
    # 南半边整体压暗（视野重心留在灯下）
    shade = new(size, size)
    sd = ImageDraw.Draw(shade)
    for y in range(size):
        k = max(0.0, (y / size) - 0.42)
        sd.line([(0, y), (size, y)], fill=(2, 3, 7, int(150 * k)))
    im.alpha_composite(shade)
    return im.convert("RGB")


def make_seal(size=512):
    im = new(size)
    dr = ImageDraw.Draw(im)
    c = size / 2
    tip_glow(im, c, c, size * 0.34, col=(150, 190, 230, 255), a=52)
    dr = ImageDraw.Draw(im)
    pts = [(c + size * 0.34 * math.cos(math.tau * i / 6 - math.pi / 2),
            c + size * 0.34 * math.sin(math.tau * i / 6 - math.pi / 2)) for i in range(6)]
    dr.polygon(pts, outline=(170, 208, 236, 150))
    for i in range(6):
        dr.line([pts[i], (c, c)], fill=(150, 186, 216, 70), width=3)
    dr.ellipse([c - size * 0.2, c - size * 0.2, c + size * 0.2, c + size * 0.2],
               outline=(190, 220, 244, 130), width=4)
    dr.ellipse([c - size * 0.1, c - size * 0.1, c + size * 0.1, c + size * 0.1],
               fill=(10, 12, 20, 220), outline=(200, 226, 246, 160), width=3)
    return im.filter(ImageFilter.GaussianBlur(0.6))


# ---------------------------------------------------------------- 卡面
def make_card():
    w, h = 640, 960
    im = Image.new("RGBA", (w, h), (7, 9, 15, 255))
    dr = ImageDraw.Draw(im)
    for y in range(h):
        k = y / h
        dr.line([(0, y), (w, y)], fill=(int(10 + 34 * (1 - k)), int(14 + 46 * (1 - k)),
                                        int(24 + 62 * (1 - k))))
    # 顶上的灯与光池
    tip_glow(im, w * 0.5, h * 0.16, 150, col=(240, 226, 180, 255), a=110)
    dr = ImageDraw.Draw(im)
    for i in range(9):
        r = 60 + i * 42
        dr.ellipse([w * 0.5 - r, h * 0.16 - r * 0.5, w * 0.5 + r, h * 0.16 + r * 0.5],
                   outline=(170, 210, 240, max(0, 70 - i * 8)), width=2)
    lamp = draw_lantern(420).resize((120, 120))
    paste_center(im, lamp, w * 0.5, h * 0.15)
    # 人物：低机位 —— 脚在下方 88% 处，被拉长的影子捅到画面最前
    s = 0.95
    fig = draw_figure(with_lantern=True, big=True).resize(
        (int(900 * s), int(720 * s)), Image.LANCZOS)
    feet_y = int(h * 0.88)
    paste_x = int(w * 0.5 - 460 * s)
    paste_y = int(feet_y - 714 * s)
    sh = new(w, h)
    sd = ImageDraw.Draw(sh)
    ink_band(sd, w * 0.5, feet_y - 20, w * 0.40, h + 40, 78, 168, (5, 6, 11, 255),
             edge=None)
    ink_band(sd, w * 0.5, feet_y - 20, w * 0.74, h - 20, 44, 120, (6, 7, 13, 240),
             edge=None)
    im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(6)))
    im.alpha_composite(fig, (paste_x, paste_y))
    dr = ImageDraw.Draw(im)
    # 水墨扫痕 + 边框
    for i in range(10):
        y = random.Random(70 + i).randint(int(h * 0.7), h - 10)
        dr.line([(0, y), (w, y + random.Random(i).randint(-24, 24))],
                fill=(18, 22, 34, 120), width=random.Random(i * 3).randint(3, 14))
    dr.rectangle([8, 8, w - 9, h - 9], outline=(120, 150, 180, 110), width=2)
    return im.convert("RGBA")


def make_holo_layers(card):
    art = card.copy()
    # bg：把主图压成柔和的大色块（华彩卡的背景层不吃细节）
    bg = card.convert("RGB").resize((card.width // 3, card.height // 3))
    bg = bg.filter(ImageFilter.GaussianBlur(8)).resize(card.size, Image.LANCZOS)
    bg = ImageOps.autocontrast(bg, cutoff=2).convert("RGBA")
    bg.putalpha(bg.split()[3].point(lambda v: int(v * 0.9)))
    # lines：笔势线层（FIND_EDGES 后按亮度留白）
    edges = card.convert("L").filter(ImageFilter.FIND_EDGES)
    edges = edges.point(lambda v: 255 if v > 26 else 0)
    lines = new(card.width, card.height)
    lines.paste(Image.new("RGBA", card.size, (226, 240, 250, 255)), (0, 0), edges)
    return art, bg, lines


# ---------------------------------------------------------------- 落盘
def main():
    random.seed(20261102)
    boss_dir = os.path.join(ROOT, "assets", "characters", "boss")
    rig_dir = os.path.join(rig_dir := os.path.join(boss_dir, "zhizhu_rig"), "")
    scenes = os.path.join(ROOT, "assets", "scenes")
    skills = os.path.join(ROOT, "assets", "effects", "skills")
    weapons = os.path.join(ROOT, "assets", "effects", "weapons")
    icons = os.path.join(ROOT, "assets", "ui", "icon")
    codex = os.path.join(ROOT, "assets", "ui", "codex")
    holo = os.path.join(codex, "holo")
    for d in (boss_dir, rig_dir, scenes, skills, weapons, icons, codex, holo):
        ensure(d)

    fig = draw_figure(True)
    fig.save(os.path.join(boss_dir, "boss_zhizhu.png"))
    body = draw_figure(False)
    body.save(os.path.join(rig_dir, "body.png"))
    draw_lantern(520).save(os.path.join(rig_dir, "lantern.png"))

    with open(os.path.join(rig_dir, "rig.tres"), "w", encoding="utf-8") as fh:
        fh.write("""[gd_resource type="Resource" script_class="BossRigData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/boss_rig_data.gd" id="1_rig"]

[resource]
script = ExtResource("1_rig")
canvas = Vector2i(900, 720)
rig_script = "res://scripts/visual/boss_rig_zhizhu.gd"
order = PackedStringArray("body", "lantern")
part_name = PackedStringArray("body", "lantern")
part_tex = PackedStringArray("res://assets/characters/boss/zhizhu_rig/body.png", "res://assets/characters/boss/zhizhu_rig/lantern.png")
part_parent = PackedStringArray("", "body")
part_joint = PackedVector2Array(0, 0, 196, -66)
part_offset = PackedVector2Array(0, 0, 0, 0)
part_z = PackedInt32Array(0, 3)
muzzle_anim = PackedStringArray()
muzzle_part = PackedStringArray()
muzzle_offset = PackedVector2Array()
""")

    make_ground(1024).save(os.path.join(scenes, "zhaoying_lamp_arena_ground.png"))
    make_seal(512).save(os.path.join(skills, "lamp_seal.png"))

    skill_icons = {
        "skill_shadow_cut": icon_shadow_cut,
        "skill_shadow_reach": icon_shadow_reach,
        "skill_shadow_bind": icon_shadow_bind,
        "skill_shadow_step": icon_shadow_step,
        "skill_shadow_dim": icon_shadow_dim,
        "skill_shadow_beam": icon_shadow_beam,
        "skill_shadow_split": icon_shadow_split,
        "skill_shadow_longnight": icon_shadow_longnight,
        "skill_shadow_lamp": icon_shadow_lamp,
    }
    for name, fn in skill_icons.items():
        fn().save(os.path.join(icons, name + ".png"))

    item_icons = {
        "equip_changye_ren": icon_weapon_blade,
        "equip_zhului_zhui": icon_pendant,
        "mat_zhaoying_zhulei": icon_wax_material,
        "soul_zhizhu": icon_soul,
        "tr_zhizhu_ling": icon_token,
    }
    for name, fn in item_icons.items():
        fn().save(os.path.join(icons, name + ".png"))

    # 局内武器贴图
    wp = new(512)
    blade = icon_weapon_blade().resize((392, 392), Image.LANCZOS)
    paste_center(wp, blade, 256, 256)
    wp.save(os.path.join(weapons, "changye_ren.png"))

    card = make_card()
    card.save(os.path.join(codex, "card_boss_zhizhu.png"))
    art, bg, lines = make_holo_layers(card)
    art.save(os.path.join(holo, "boss_04_b_art.png"))
    bg.save(os.path.join(holo, "boss_04_b_bg.png"))
    lines.save(os.path.join(holo, "boss_04_b_lines.png"))
    print("done: zhizhu placeholders")


main()
