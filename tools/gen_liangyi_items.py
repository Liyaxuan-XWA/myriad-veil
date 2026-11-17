"""生成两仪真人的头像卡、物品/技能图标与太极石台地面（2026-10-27）。

全部程序化绘制，不依赖生图配额；输出路径与 ItemDB / SkillDB / CodexDB 已对齐。
"""
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

ICON = "assets/ui/icon"
CARD = "assets/ui/codex"
SCENES = "assets/scenes"
RIG = "assets/characters/boss/liangyi_rig"

INK = (18, 20, 24, 255)
INK2 = (38, 42, 50, 255)
WHITE = (226, 220, 206, 255)
WHITE2 = (244, 240, 228, 255)
GOLD = (196, 154, 70, 255)
GOLD_L = (240, 210, 132, 255)
CYAN = (74, 168, 180, 255)
CYAN_L = (150, 228, 236, 255)
SKIN = (210, 182, 154, 255)
SKIN_D = (176, 144, 118, 255)
RED = (168, 58, 48, 255)


def ensure_dirs():
    for d in (ICON, CARD, SCENES):
        os.makedirs(d, exist_ok=True)


def soft_glow(size, color, radius=40, alpha=140):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size
    d.ellipse([w * 0.5 - radius, h * 0.5 - radius, w * 0.5 + radius, h * 0.5 + radius],
              fill=(color[0], color[1], color[2], alpha))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.35))


def icon_canvas():
    return Image.new("RGBA", (768, 768), (0, 0, 0, 0))


def save_icon(img, name):
    img = img.resize((256, 256), Image.LANCZOS)
    img = ac.polish(img, grain=0.12, rim_alpha=0.22)
    img.save(os.path.join(ICON, name))
    print("icon", name)


def draw_shadow(d, cx, cy, rx, ry, alpha=90):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(0, 0, 0, alpha))


def icon_yujue():
    c = icon_canvas()
    g = soft_glow((768, 768), GOLD, 250, 90)
    c = Image.alpha_composite(c, g)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 384
    # shadow
    draw_shadow(d, cx + 6, cy + 20, 220, 70, 100)
    # outer gold ring
    d.ellipse([cx-230, cy-230, cx+230, cy+230], outline=GOLD, width=20)
    d.ellipse([cx-210, cy-210, cx+210, cy+210], fill=(46, 60, 58, 255), outline=GOLD_L, width=6)
    # split jade halves
    d.pieslice([cx-198, cy-198, cx+198, cy+198], 90, 270, fill=(16, 22, 24, 255))
    d.pieslice([cx-198, cy-198, cx+198, cy+198], -90, 90, fill=(226, 236, 224, 255))
    # inner hole
    d.ellipse([cx-92, cy-92, cx+92, cy+92], fill=(10, 12, 14, 255), outline=GOLD, width=8)
    # taiji dots on the ring
    d.ellipse([cx-152, cy-30, cx-92, cy+30], fill=(226, 236, 224, 255))
    d.ellipse([cx+92, cy-30, cx+152, cy+30], fill=(16, 22, 24, 255))
    d.ellipse([cx-132, cy-6, cx-112, cy+14], fill=(16, 22, 24, 255))
    d.ellipse([cx+112, cy-6, cx+132, cy+14], fill=(226, 236, 224, 255))
    # highlights
    d.arc([cx-210, cy-210, cx+210, cy+210], 200, 250, fill=(255, 255, 240, 180), width=8)
    d.arc([cx-230, cy-230, cx+230, cy+230], 20, 70, fill=(255, 240, 200, 140), width=6)
    save_icon(c, "equip_liangyi_yujue.png")


def icon_robe():
    c = icon_canvas()
    g = soft_glow((768, 768), CYAN, 260, 70)
    c = Image.alpha_composite(c, g)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 390
    draw_shadow(d, cx, cy + 210, 210, 46, 90)
    # robe silhouette
    robe = [(270, 190), (330, 150), (384, 170), (438, 150), (498, 190),
            (560, 430), (530, 620), (238, 620), (208, 430)]
    # black left
    d.polygon([(270,190),(330,150),(384,170),(384,620),(238,620),(208,430)], fill=INK)
    # white right
    d.polygon([(384,170),(438,150),(498,190),(560,430),(530,620),(384,620)], fill=WHITE)
    # gold center seam & hem
    d.line([(384,170),(376,300),(390,450),(384,620)], fill=GOLD, width=10)
    d.line([(242,610),(526,610)], fill=GOLD, width=12)
    d.line([(248,592),(520,592)], fill=GOLD_L, width=4)
    # collar
    d.polygon([(330,160),(384,210),(438,160),(410,144),(384,176),(358,144)], fill=GOLD)
    # sleeves
    d.polygon([(270,190),(208,430),(260,450),(316,240)], fill=INK)
    d.polygon([(498,190),(560,430),(508,450),(452,240)], fill=WHITE)
    d.line([(208,430),(260,450)], fill=GOLD, width=8)
    d.line([(560,430),(508,450)], fill=GOLD, width=8)
    # taiji emblem
    d.ellipse([cx-62, cy-30, cx+62, cy+94], fill=WHITE2, outline=GOLD, width=6)
    d.pieslice([cx-62, cy-30, cx+62, cy+94], 90, 270, fill=INK)
    d.ellipse([cx-31, cy-30, cx+31, cy+32], fill=INK)
    d.ellipse([cx-31, cy+32, cx+31, cy+94], fill=WHITE2)
    d.ellipse([cx-14, cy-10, cx+14, cy+18], fill=WHITE2)
    d.ellipse([cx-14, cy+56, cx+14, cy+84], fill=INK)
    # cloud pattern
    for yy in (470, 540):
        d.line([(270, yy), (310, yy-16), (350, yy), (390, yy-16)], fill=(120, 110, 90, 110), width=5)
    save_icon(c, "equip_xuansu_daopao.png")


def icon_stone():
    c = icon_canvas()
    g = soft_glow((768, 768), CYAN, 260, 100)
    c = Image.alpha_composite(c, g)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 400
    draw_shadow(d, cx, cy + 210, 200, 48, 100)
    shard = [(300, 170), (470, 130), (590, 300), (540, 560), (250, 590), (190, 350)]
    # black half
    d.polygon([(300,170),(470,130),(470,590),(250,590),(190,350)], fill=INK)
    # white half
    d.polygon([(470,130),(590,300),(540,560),(470,590)], fill=WHITE)
    # gold veins
    d.line([(470,130),(430,280),(470,590)], fill=GOLD, width=10)
    d.line([(300,170),(350,300),(250,590)], fill=(120, 96, 50, 200), width=5)
    d.line([(590,300),(500,360),(540,560)], fill=(120, 96, 50, 200), width=5)
    d.line([(330,360),(430,340),(520,380)], fill=GOLD_L, width=4)
    # taiji facet
    d.ellipse([cx-50, cy-20, cx+50, cy+80], fill=WHITE2, outline=GOLD, width=4)
    d.pieslice([cx-50, cy-20, cx+50, cy+80], 90, 270, fill=INK)
    # rim highlight
    d.line([(300,170),(190,350)], fill=(255, 240, 200, 160), width=5)
    d.line([(470,130),(590,300)], fill=(150, 240, 246, 150), width=4)
    save_icon(c, "mat_liangyi_xuanshi.png")


def icon_soul():
    c = icon_canvas()
    # ghostly glow
    for r, a in [(260, 60), (220, 80), (180, 100)]:
        g = Image.new("RGBA", (768, 768), (0,0,0,0))
        d = ImageDraw.Draw(g)
        d.ellipse([384-r, 330-r, 384+r, 330+r], fill=(120, 210, 220, a))
        c = Image.alpha_composite(c, g.filter(ImageFilter.GaussianBlur(r*0.18)))
    d = ImageDraw.Draw(c)
    cx, cy = 384, 380
    # censer base
    d.ellipse([cx-170, cy+130, cx+170, cy+270], fill=(86, 64, 38, 255), outline=GOLD, width=9)
    d.ellipse([cx-150, cy+140, cx+150, cy+230], fill=(52, 40, 28, 255))
    d.rectangle([cx-90, cy+80, cx+90, cy+185], fill=(86, 64, 38, 255))
    d.ellipse([cx-90, cy+60, cx+90, cy+120], fill=(112, 84, 46, 255), outline=GOLD, width=7)
    d.line([(cx-160, cy+220), (cx+160, cy+220)], fill=GOLD_L, width=5)
    # handles
    d.arc([cx-230, cy+120, cx-150, cy+210], 90, 270, fill=GOLD, width=8)
    d.arc([cx+150, cy+120, cx+230, cy+210], -90, 90, fill=GOLD, width=8)
    # flame: half gold, half cyan
    flame = [(cx, cy-190), (cx+74, cy-60), (cx+44, cy+70), (cx-44, cy+70), (cx-74, cy-60)]
    d.polygon(flame, fill=(244, 200, 96, 230))
    d.polygon([(cx, cy-190), (cx-74, cy-60), (cx-44, cy+70), (cx, cy+55)], fill=(70, 180, 190, 230))
    d.polygon([(cx, cy-150), (cx+38, cy-50), (cx+18, cy+40), (cx-18, cy+40), (cx-38, cy-50)],
              fill=(255, 246, 214, 220))
    # eyes / motes
    d.ellipse([cx-24, cy-60, cx-8, cy-44], fill=INK)
    d.ellipse([cx+8, cy-60, cx+24, cy-44], fill=INK)
    save_icon(c, "soul_liangyi.png")


def icon_token():
    c = icon_canvas()
    g = soft_glow((768, 768), GOLD, 240, 80)
    c = Image.alpha_composite(c, g)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 390
    draw_shadow(d, cx, cy + 250, 150, 36, 80)
    # tassel
    d.line([(cx, cy+210), (cx, cy+330)], fill=GOLD, width=8)
    for i in range(5):
        d.line([(cx, cy+260), (cx-34+i*17, cy+350)], fill=(120, 96, 50, 220), width=4)
    # plaque
    d.rounded_rectangle([cx-120, cy-240, cx+120, cy+220], radius=26, fill=INK, outline=GOLD, width=12)
    d.rounded_rectangle([cx-100, cy-220, cx+100, cy+200], radius=18, fill=WHITE, outline=GOLD_L, width=3)
    # black half
    d.pieslice([cx-100, cy-220, cx+100, cy+200], 90, 270, fill=INK)
    # taiji
    d.ellipse([cx-70, cy-70, cx+70, cy+70], fill=WHITE2, outline=GOLD, width=6)
    d.pieslice([cx-70, cy-70, cx+70, cy+70], 90, 270, fill=INK)
    d.ellipse([cx-35, cy-70, cx+35, cy], fill=INK)
    d.ellipse([cx-35, cy, cx+35, cy+70], fill=WHITE2)
    d.ellipse([cx-14, cy-30, cx+14, cy-2], fill=WHITE2)
    d.ellipse([cx-14, cy+2, cx+14, cy+30], fill=INK)
    # hole
    d.ellipse([cx-18, cy-200, cx+18, cy-164], fill=(10,12,14,255), outline=GOLD, width=4)
    save_icon(c, "tr_liangyi_ling.png")


def icon_plate():
    c = icon_canvas()
    for r, a in [(280, 50), (240, 70), (200, 90)]:
        g = Image.new("RGBA", (768, 768), (0,0,0,0))
        d = ImageDraw.Draw(g)
        d.ellipse([384-r, 384-r, 384+r, 384+r], fill=(120, 210, 220, a))
        c = Image.alpha_composite(c, g.filter(ImageFilter.GaussianBlur(r*0.12)))
    d = ImageDraw.Draw(c)
    cx, cy = 384, 384
    draw_shadow(d, cx, cy+200, 230, 50, 90)
    # disc edge
    d.ellipse([cx-250, cy-250, cx+250, cy+250], fill=(30, 34, 40, 255), outline=GOLD, width=16)
    d.ellipse([cx-232, cy-232, cx+232, cy+232], fill=(20, 22, 28, 255), outline=GOLD_L, width=4)
    # taiji
    r = 188
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=WHITE2, outline=GOLD, width=6)
    d.pieslice([cx-r, cy-r, cx+r, cy+r], 90, 270, fill=INK)
    d.ellipse([cx-94, cy-r-47, cx+94, cy-r+47], fill=INK)
    d.ellipse([cx-94, cy+r-47, cx+94, cy+r+47], fill=WHITE2)
    d.ellipse([cx-22, cy-r-22, cx+22, cy-r+22], fill=WHITE2)
    d.ellipse([cx-22, cy+r-22, cx+22, cy+r+22], fill=INK)
    # runes
    for k in range(12):
        a = math.radians(k*30)
        x1 = cx + math.cos(a)*212
        y1 = cy + math.sin(a)*212
        x2 = cx + math.cos(a)*228
        y2 = cy + math.sin(a)*228
        d.line([(x1,y1),(x2,y2)], fill=GOLD_L, width=5)
    save_icon(c, "tr_taiji_pan.png")


def skill_frame(c, color):
    d = ImageDraw.Draw(c)
    d.ellipse([64, 64, 704, 704], fill=(12, 14, 18, 255), outline=GOLD, width=14)
    d.ellipse([84, 84, 684, 684], outline=color, width=4)
    # inner ink wash
    for r, a in [(260, 20), (220, 26), (180, 32)]:
        d.ellipse([384-r, 384-r, 384+r, 384+r], fill=(color[0], color[1], color[2], a))
    return c


def icon_skill_palm():
    c = icon_canvas()
    c = skill_frame(c, GOLD)
    d = ImageDraw.Draw(c)
    # palm silhouette
    d.ellipse([300, 300, 470, 470], fill=SKIN)
    d.polygon([(300, 380), (250, 300), (280, 270), (340, 360)], fill=SKIN)
    for i in range(3):
        x = 330 + i*48
        d.rounded_rectangle([x, 210, x+34, 360], radius=17, fill=SKIN)
    d.rounded_rectangle([452, 300, 500, 420], radius=22, fill=SKIN)
    d.line([(330, 380), (470, 430)], fill=SKIN_D, width=6)
    # gold flame in the palm
    d.polygon([(384, 240), (430, 360), (400, 430), (360, 430), (338, 360)],
              fill=(244, 196, 86, 230))
    d.polygon([(384, 270), (410, 360), (392, 410), (368, 410), (354, 360)],
              fill=(255, 246, 210, 230))
    save_icon(c, "skill_yinyang_palm.png")


def icon_skill_finger():
    c = icon_canvas()
    c = skill_frame(c, CYAN)
    d = ImageDraw.Draw(c)
    # hand
    d.ellipse([290, 360, 450, 520], fill=SKIN)
    d.rounded_rectangle([390, 180, 430, 430], radius=20, fill=SKIN)
    d.rounded_rectangle([338, 300, 380, 430], radius=20, fill=SKIN)
    d.rounded_rectangle([286, 320, 326, 430], radius=20, fill=SKIN)
    # cyan beam from fingertip
    d.polygon([(410, 190), (470, 120), (500, 148), (430, 230)], fill=(74, 190, 204, 230))
    d.line([(410, 190), (500, 120)], fill=(180, 248, 252, 240), width=10)
    for i in range(4):
        d.line([(430+i*18, 160+i*10), (480+i*18, 120+i*10)], fill=(150, 240, 246, 160), width=4)
    save_icon(c, "skill_yinyang_finger.png")


def icon_skill_flip():
    c = icon_canvas()
    c = skill_frame(c, GOLD_L)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 384
    # two curved arrows, gold & cyan
    d.arc([170, 170, 598, 598], 130, 300, fill=GOLD, width=18)
    d.arc([170, 170, 598, 598], -50, 120, fill=CYAN, width=18)
    # arrow heads
    d.polygon([(214, 246), (154, 292), (246, 316)], fill=GOLD)
    d.polygon([(554, 522), (614, 476), (522, 452)], fill=CYAN)
    # center taiji
    d.ellipse([cx-100, cy-100, cx+100, cy+100], fill=WHITE2, outline=GOLD, width=6)
    d.pieslice([cx-100, cy-100, cx+100, cy+100], 90, 270, fill=INK)
    d.ellipse([cx-50, cy-100, cx+50, cy], fill=INK)
    d.ellipse([cx-50, cy, cx+50, cy+100], fill=WHITE2)
    d.ellipse([cx-18, cy-40, cx+18, cy-4], fill=WHITE2)
    d.ellipse([cx-18, cy+4, cx+18, cy+40], fill=INK)
    save_icon(c, "skill_yinyang_flip.png")


def icon_skill_collapse():
    c = icon_canvas()
    c = skill_frame(c, CYAN_L)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 384
    # rays
    for k in range(16):
        a = math.radians(k*22.5)
        r1 = 90
        r2 = 250 + (k%3)*20
        d.line([(cx+math.cos(a)*r1, cy+math.sin(a)*r1),
                (cx+math.cos(a)*r2, cy+math.sin(a)*r2)],
               fill=(240, 206, 120, 150) if k%2==0 else (120, 220, 228, 140), width=6)
    # taiji orb
    d.ellipse([cx-120, cy-120, cx+120, cy+120], fill=WHITE2, outline=GOLD, width=8)
    d.pieslice([cx-120, cy-120, cx+120, cy+120], 90, 270, fill=INK)
    d.ellipse([cx-60, cy-120, cx+60, cy], fill=INK)
    d.ellipse([cx-60, cy, cx+60, cy+120], fill=WHITE2)
    d.ellipse([cx-20, cy-50, cx+20, cy-10], fill=WHITE2)
    d.ellipse([cx-20, cy+10, cx+20, cy+50], fill=INK)
    # shock ring
    d.ellipse([cx-180, cy-180, cx+180, cy+180], outline=(240, 210, 132, 200), width=8)
    save_icon(c, "skill_yinyang_collapse.png")


def _crescent(d, cx, cy, r, top, bot, width, color):
    """一段月牙形刀/掌光：外弧 + 内弧夹出来的闭合带。"""
    pts = []
    for i in range(29):
        a = math.radians(top + (bot - top) * i / 28.0)
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    for i in range(29):
        a = math.radians(bot - (bot - top) * i / 28.0)
        rr = r - width
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=color)


def _fish(d, cx, cy, rx, ry, ang, color, eye):
    """一条阴阳鱼：椭圆身 + 三角尾 + 眼。ang 为机头朝向（度）。"""
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=color)
    # 尾鳍（朝身体后方张开）
    tx, ty = cx - ux * rx * 1.05, cy - uy * rx * 1.05
    d.polygon([(tx, ty),
               (tx - ux * 74 + px * 52, ty - uy * 74 + py * 52),
               (tx - ux * 30, ty - uy * 30),
               (tx - ux * 74 - px * 52, ty - uy * 74 - py * 52)], fill=color)
    d.ellipse([cx + ux * rx * 0.42 - 11, cy + uy * rx * 0.42 - 11,
               cx + ux * rx * 0.42 + 11, cy + uy * rx * 0.42 + 11], fill=eye)


def icon_skill_triple():
    """阳诀·三叠踏：三重前推的掌浪 + 踏步痕。"""
    c = icon_canvas()
    c = skill_frame(c, GOLD_L)
    d = ImageDraw.Draw(c)
    for i, (r, wdt, al) in enumerate([(250, 40, 120), (196, 42, 170), (142, 44, 225)]):
        _crescent(d, 300, 470, r, -100, 8, wdt, (244, 196, 86, al))
    _crescent(d, 300, 470, 132, -100, 8, 12, (255, 248, 220, 235))
    # 三道步痕
    for i in range(3):
        x = 250 + i * 108
        y = 560 - i * 44
        d.rounded_rectangle([x, y, x + 56, y + 30], radius=14,
                            fill=(226, 190, 116, 210))
    # 前冲拖尾
    for i in range(5):
        y = 300 + i * 30
        d.line([(140 + i * 12, y), (260 + i * 26, y)], fill=(240, 214, 146, 90), width=6)
    save_icon(c, "skill_yinyang_triple.png")


def icon_skill_wind():
    """阴诀·蚀骨风：自立身之处盘起的阴风涡 + 骨屑。"""
    c = icon_canvas()
    c = skill_frame(c, CYAN)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 384
    d.ellipse([cx - 240, cy - 240, cx + 240, cy + 240], outline=(74, 168, 180, 150), width=6)
    for k in range(3):
        r = 210 - k * 52
        d.arc([cx - r, cy - r, cx + r, cy + r], 30 + k * 40, 300 + k * 40,
              fill=(120, 214, 224, 210), width=20)
        r2 = r - 34
        d.arc([cx - r2, cy - r2, cx + r2, cy + r2], 200 + k * 40, 400 + k * 40,
              fill=(186, 240, 246, 150), width=8)
    # 涡心
    d.ellipse([cx - 46, cy - 46, cx + 46, cy + 46], fill=(20, 44, 50, 235))
    d.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], fill=(150, 228, 236, 235))
    # 骨屑
    rng = random.Random(7)
    for _ in range(16):
        a = math.radians(rng.uniform(0, 360))
        r = rng.uniform(96, 232)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        d.line([(x, y), (x + math.cos(a) * 16, y + math.sin(a) * 16)],
               fill=(226, 236, 232, 200), width=4)
    save_icon(c, "skill_yinyang_wind.png")


def icon_skill_fish():
    """两仪·双鱼：一阳一阴衔尾互追。"""
    c = icon_canvas()
    c = skill_frame(c, GOLD)
    d = ImageDraw.Draw(c)
    _fish(d, 384, 236, 96, 58, 0, (244, 196, 86, 240), (18, 20, 24, 255))
    _fish(d, 384, 532, 96, 58, 180, (74, 168, 180, 240), (244, 240, 228, 255))
    # 中间的 S 形分界（太极线）
    d.arc([250, 300, 518, 468], 0, 180, fill=(244, 240, 228, 210), width=8)
    d.arc([250, 300, 518, 468], 180, 360, fill=(18, 20, 24, 210), width=8)
    for x, y, col in [(240, 384, (244, 196, 86, 200)), (528, 384, (74, 168, 180, 200))]:
        d.ellipse([x - 16, y - 16, x + 16, y + 16], fill=col)
    save_icon(c, "skill_yinyang_fish.png")


def icon_skill_harmony():
    """被动「负阴抱阳」：背后一道墨环（负阴）+ 怀中一轮宣白（抱阳），外圈三道短槽表示被动槽。"""
    c = icon_canvas()
    c = skill_frame(c, GOLD_L)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 384
    d.arc([166, 166, 602, 602], 100, 260, fill=INK2, width=54)
    for k in range(3):
        a0 = -35 + k * 120
        d.arc([130, 130, 638, 638], a0, a0 + 42, fill=(196, 154, 70, 220), width=16)
    d.ellipse([cx - 96, cy - 96, cx + 96, cy + 96], fill=WHITE2, outline=GOLD, width=8)
    d.ellipse([cx - 40, cy - 40, cx + 40, cy + 40], fill=GOLD_L)
    d.arc([cx - 140, cy - 140, cx + 140, cy + 140], 20, 150, fill=CYAN_L, width=14)
    d.arc([cx - 140, cy - 140, cx + 140, cy + 140], 200, 330, fill=GOLD, width=14)
    save_icon(c, "skill_yinyang_harmony.png")


def icon_skill_counter():
    """两仪·倒悬：仪态倒扣的护罩，同色之力奉还。"""
    c = icon_canvas()
    c = skill_frame(c, CYAN_L)
    d = ImageDraw.Draw(c)
    cx, cy = 384, 400
    # 倒扣的护罩（下半圆张开向上）
    d.pieslice([cx - 220, cy - 190, cx + 220, cy + 210], 180, 360,
               fill=(30, 42, 52, 220), outline=(150, 228, 236, 230))
    d.arc([cx - 172, cy - 148, cx + 172, cy + 172], 180, 360,
          fill=(240, 210, 132, 200), width=10)
    # 罩顶的太极（倒置：阴上阳下）
    r = 76
    d.ellipse([cx - r, cy - 170 - r, cx + r, cy - 170 + r], fill=WHITE2, outline=GOLD, width=6)
    d.pieslice([cx - r, cy - 170 - r, cx + r, cy - 170 + r], 270, 90, fill=INK)
    d.ellipse([cx - r, cy - 170 - r, cx, cy - 170 + r], fill=INK)
    d.ellipse([cx, cy - 170 - r, cx + r, cy - 170 + r], fill=WHITE2)
    d.ellipse([cx - 16, cy - 170 - 44, cx + 16, cy - 170 - 12], fill=WHITE2)
    d.ellipse([cx - 16, cy - 170 + 12, cx + 16, cy - 170 + 44], fill=INK)
    # 奉还的双向弧
    for k, col in [(0, (244, 196, 86, 210)), (1, (150, 228, 236, 210))]:
        rr = 250 + k * 22
        d.arc([cx - rr, cy - rr, cx + rr, cy + rr], 150 + k * 120, 250 + k * 120,
              fill=col, width=12)
    save_icon(c, "skill_yinyang_counter.png")


def make_arena():
    """太极石台（2026-10-28 重做）：放射状石板 + 中央阴阳嵌石 + 八卦刻线 + 湿面反光 + 裂纹 + 暗角。
    仍是 1200×676（战场同比例），覆盖同名文件即可换皮。"""
    rng = random.Random(31)
    w, h = 1200, 676
    cx, cy = w * 0.5, h * 0.53
    img = Image.new("RGBA", (w, h), (15, 17, 21, 255))
    d = ImageDraw.Draw(img)
    # 底：冷黑竖向渐变
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=(int(36 + (10 - 36) * t), int(40 + (12 - 40) * t),
                                       int(47 + (16 - 47) * t), 255))
    # 放射状石板：12 个扇区，逐格亮度抖动（读作一圈石台，而不是地砖）
    R = 780
    for i in range(12):
        a0 = i * 30 - 90
        shade = rng.randint(-8, 8)
        d.pieslice([cx - R, cy - R, cx + R, cy + R], a0, a0 + 30,
                   fill=(47 + shade, 51 + shade, 59 + shade, 255))
    # 扇缝与两道同心台阶
    for i in range(12):
        a = math.radians(i * 30 - 90)
        d.line([(cx, cy), (cx + math.cos(a) * R, cy + math.sin(a) * R)],
               fill=(14, 16, 20, 190), width=3)
    for rr, al in [(R - 8, 220), (382, 170), (300, 150)]:
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(20, 22, 27, al), width=3)
    # 中央阴阳嵌石：宣白 / 墨 两半 + 金边 + 冷青内环
    ir = 244
    d.ellipse([cx - ir - 6, cy - ir - 6, cx + ir + 6, cy + ir + 6], fill=(26, 28, 34, 255))
    d.pieslice([cx - ir, cy - ir, cx + ir, cy + ir], -90, 90, fill=(226, 220, 203, 255))
    d.pieslice([cx - ir, cy - ir, cx + ir, cy + ir], 90, 270, fill=(20, 22, 28, 255))
    hr = ir // 2
    d.ellipse([cx - hr, cy - ir, cx + hr, cy], fill=(20, 22, 28, 255))
    d.ellipse([cx - hr, cy, cx + hr, cy + ir], fill=(226, 220, 203, 255))
    d.ellipse([cx - 22, cy - hr - 22, cx, cy - hr], fill=(226, 220, 203, 255))
    d.ellipse([cx, cy + hr, cx + 22, cy + hr + 22], fill=(20, 22, 28, 255))
    d.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], outline=(196, 154, 70, 235), width=6)
    d.ellipse([cx - ir - 14, cy - ir - 14, cx + ir + 14, cy + ir + 14],
              outline=(120, 206, 214, 70), width=2)
    # 八卦刻线（与特效 / 光环同一套）
    ac.draw_bagua_ring(d, cx, cy, 292, (196, 154, 70, 120), width=2, bar_len=24, bar_gap=11)
    # 裂纹：从外圈向内延伸的折线，暗缝 + 一道亮边
    for i in range(9):
        a = rng.uniform(0, math.tau)
        r0 = rng.uniform(300, R - 40)
        x, y = cx + math.cos(a) * r0, cy + math.sin(a) * r0
        pts = [(x, y)]
        for k in range(4):
            a += rng.uniform(-0.35, 0.35)
            r0 -= rng.uniform(26, 54)
            x, y = cx + math.cos(a) * r0, cy + math.sin(a) * r0
            pts.append((x, y))
        d.line(pts, fill=(11, 12, 15, 200), width=3, joint="curve")
        d.line([(px + 2, py + 2) for px, py in pts], fill=(90, 96, 106, 70), width=1)
    # 湿地反光：左上大面积柔光 + 中央一道竖直反光
    sheen = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse([-w * 0.1, -h * 0.55, w * 0.78, h * 0.46], fill=(120, 190, 205, 34))
    sd.rectangle([cx - 40, cy - 240, cx + 40, cy + 240], fill=(226, 220, 203, 16))
    img = Image.alpha_composite(img, sheen.filter(ImageFilter.GaussianBlur(38)))
    # 苔痕 / 墨渍：贴着外圈的石台边缘
    moss = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    md = ImageDraw.Draw(moss)
    for i in range(14):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(R - 120, R + 30)
        mx, my = cx + math.cos(a) * rr, cy + math.sin(a) * rr
        rx, ry = rng.uniform(20, 60), rng.uniform(12, 30)
        md.ellipse([mx - rx, my - ry, mx + rx, my + ry], fill=(24, 46, 44, rng.randint(40, 80)))
    img = Image.alpha_composite(img, moss.filter(ImageFilter.GaussianBlur(14)))
    # 暗角 + 颗粒
    img = Image.alpha_composite(img, ac.vignette((w, h), 0.55))
    img = ac.polish(img, grain=0.10, rim_alpha=0.0)
    # 地面要退到人物后面：整体压暗一档 + 再补一层暗角
    img = ImageEnhance.Brightness(img).enhance(0.80)
    img = Image.alpha_composite(img, ac.vignette((w, h), 0.35))
    img.convert("RGB").save(os.path.join(SCENES, "liangyi_arena_ground.png"))
    print("arena saved")


def make_card():
    """图鉴 / 入场卡：八卦环 + 冷光 + 润色分件 + 背后金边 + 脚下投影 + 前雾暗角（640×960）"""
    cw, ch = 640, 960
    card = Image.new("RGBA", (cw, ch), (7, 9, 12, 255))
    d = ImageDraw.Draw(card)
    for y in range(ch):
        t = y / ch
        d.line([(0, y), (cw, y)], fill=(int(9 + 10 * t), int(11 + 10 * t), int(16 + 12 * t), 255))
    card = Image.alpha_composite(card, ac.radial_glow((cw, ch), (120, 206, 214), 320, 44))
    # 背景：八卦环 + 双圈
    ring = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rcx, rcy = cw // 2, 420
    for r, a in [(316, 40), (300, 56), (286, 70)]:
        rd.ellipse([rcx - r, rcy - r, rcx + r, rcy + r], outline=(120, 206, 214, a), width=2)
    rd.ellipse([rcx - 268, rcy - 268, rcx + 268, rcy + 268], outline=(196, 154, 70, 120), width=3)
    rd.ellipse([rcx - 252, rcy - 252, rcx + 252, rcy + 252], outline=(196, 154, 70, 60), width=1)
    ac.draw_bagua_ring(rd, rcx, rcy, 232, (206, 170, 92, 110), width=2, bar_len=20, bar_gap=8)
    card = Image.alpha_composite(card, ring.filter(ImageFilter.GaussianBlur(0.8)))
    # 金尘
    rng = random.Random(7)
    dust = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dust)
    for i in range(120):
        x, y = rng.randint(0, cw), rng.randint(0, ch)
        r = rng.choice([1, 1, 2, 2, 3])
        dd.ellipse([x - r, y - r, x + r, y + r], fill=(240, 210, 132, rng.randint(26, 120)))
    card = Image.alpha_composite(card, dust.filter(ImageFilter.GaussianBlur(0.6)))
    # 人物分件（已润色）
    scale = 1.10
    parts = {}
    for name in ["halo", "sash", "leg_back", "body", "leg_front", "arm"]:
        pp = Image.open(os.path.join(RIG, name + ".png")).convert("RGBA")
        parts[name] = pp.resize((int(900 * scale), int(720 * scale)), Image.LANCZOS)
    ox = int(cw * 0.5 - 450 * scale)
    oy = 96
    arm = parts["arm"].rotate(-18, resample=Image.BICUBIC,
                             center=(int(440 * scale), int(280 * scale)))
    body = parts["body"].rotate(-2, resample=Image.BICUBIC,
                               center=(int(450 * scale), int(400 * scale)))
    # 脚下投影：先压一层椭圆暗影，人物才「站」在卡上
    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([cw * 0.5 - 150, oy + 720 * scale - 26, cw * 0.5 + 150, oy + 720 * scale + 34],
               fill=(0, 0, 0, 170))
    card = Image.alpha_composite(card, shadow.filter(ImageFilter.GaussianBlur(16)))
    # 背后金色轮廓光：身体与手臂的 alpha 外扩
    rim_src = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    for layer_img in (body, arm):
        tmp = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        tmp.alpha_composite(layer_img, (ox, oy))
        rim_src = Image.alpha_composite(rim_src, tmp)
    gold = Image.new("RGBA", (cw, ch), (240, 206, 132, 255))
    gold.putalpha(rim_src.getchannel("A").point(lambda v: int(v * 0.55)))
    card = Image.alpha_composite(card, gold.filter(ImageFilter.GaussianBlur(12)))
    for name in ["halo", "sash", "leg_back"]:
        card.alpha_composite(parts[name], (ox, oy))
    card.alpha_composite(body, (ox, oy))
    card.alpha_composite(parts["leg_front"], (ox, oy))
    card.alpha_composite(arm, (ox, oy))
    # 前雾 + 底边淡出 + 暗角
    mist = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    md = ImageDraw.Draw(mist)
    for i, yy in enumerate((640, 760, 860)):
        md.rectangle([0, yy, cw, yy + 150], fill=(140, 180, 195, 14 + i * 6))
    card = Image.alpha_composite(card, mist.filter(ImageFilter.GaussianBlur(30)))
    fade = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fade)
    for i in range(96):
        fd.line([(0, ch - 1 - i), (cw, ch - 1 - i)],
                fill=(6, 7, 10, int(150 * (i / 96) ** 2.0)))
    card = Image.alpha_composite(card, fade)
    card = Image.alpha_composite(card, ac.vignette((cw, ch), 0.5))
    card.convert("RGB").save(os.path.join(CARD, "card_boss_liangyi.png"))
    print("card saved")


if __name__ == "__main__":
    ensure_dirs()
    icon_yujue()
    icon_robe()
    icon_stone()
    icon_soul()
    icon_token()
    icon_plate()
    icon_skill_palm()
    icon_skill_finger()
    icon_skill_flip()
    icon_skill_collapse()
    icon_skill_triple()
    icon_skill_wind()
    icon_skill_fish()
    icon_skill_counter()
    icon_skill_harmony()
    make_arena()
    make_card()
