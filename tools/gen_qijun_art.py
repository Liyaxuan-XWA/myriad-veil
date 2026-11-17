"""太虚气君（冲和界第 3 位）程序化美术（2026-10-28）。

生图配额未确认时先出可用的替代件：立绘 / 图鉴卡 / 云石战场 / 气环贴图 / 14 张图标。
全部由 PIL 绘制，风格锚点 = 赛璐璐人形（两仪、定阵同一档），色板 = 石青 / 素白 / 淡金。
后续有配额时：覆盖同名 PNG 即可，文件名与 ItemDB / ArtDB / SkillDB 已对齐。
"""
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

BOSS = "assets/characters/boss"
FX = "assets/effects/skills"
ICON = "assets/ui/icon"
CARD = "assets/ui/codex"
SCENES = "assets/scenes"

INK = (16, 22, 30, 255)
INK2 = (30, 44, 56, 255)
WHITE = (232, 240, 242, 255)
WHITE2 = (248, 252, 252, 255)
CYAN = (92, 196, 222, 255)
CYAN_L = (170, 232, 246, 255)
CYAN_D = (34, 92, 112, 255)
GOLD = (196, 158, 82, 255)
GOLD_L = (240, 214, 146, 255)
SKIN = (226, 208, 194, 255)
SKIN_D = (188, 160, 146, 255)


def ensure():
    for d in (BOSS, FX, ICON, CARD, SCENES):
        os.makedirs(d, exist_ok=True)


def glow(size, color, radius, alpha=120):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size
    d.ellipse([w * 0.5 - radius, h * 0.5 - radius, w * 0.5 + radius, h * 0.5 + radius],
              fill=(color[0], color[1], color[2], alpha))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.4))


# ===================== 气环贴图 =====================
def qi_ring():
    size = 256
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = size // 2
    for r, a, w in ((118, 150, 6), (100, 90, 3), (76, 50, 2)):
        d.arc([cx - r, cy - r, cx + r, cy + r], 0, 360, fill=(CYAN[0], CYAN[1], CYAN[2], a), width=w)
    # 三段旋弧：读作"气在转"
    for k in range(3):
        a0 = 20 + k * 120
        d.arc([cx - 110, cy - 110, cx + 110, cy + 110], a0, a0 + 52,
              fill=(CYAN_L[0], CYAN_L[1], CYAN_L[2], 220), width=6)
    d.arc([cx - 88, cy - 88, cx + 88, cy + 88], 180, 300,
          fill=(CYAN_L[0], CYAN_L[1], CYAN_L[2], 140), width=3)
    img = ac.polish(img, grain=0.08, rim_alpha=0.10)
    img.save(os.path.join(FX, "qi_ring.png"))
    print("qi_ring")


# ===================== 立绘 =====================
def boss_art():
    w, h = 900, 720
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # 背后的气环
    halo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for r, a, wd in ((250, 36, 8), (232, 60, 3), (200, 30, 2)):
        hd.arc([450 - r, 300 - r, 450 + r, 300 + r], 0, 360,
               fill=(CYAN[0], CYAN[1], CYAN[2], a), width=wd)
    for k in range(3):
        a0 = 30 + k * 120
        hd.arc([450 - 240, 300 - 240, 450 + 240, 300 + 240], a0, a0 + 44,
               fill=(CYAN_L[0], CYAN_L[1], CYAN_L[2], 150), width=5)
    img = Image.alpha_composite(img, halo.filter(ImageFilter.GaussianBlur(1.2)))
    d = ImageDraw.Draw(img)
    # 云尾（没有腿：下摆化成三缕云）
    for i, (dx, ww, hh, col) in enumerate([(0, 210, 250, (206, 224, 228, 255)),
                                           (-70, 150, 190, (176, 204, 212, 255)),
                                           (80, 140, 170, (190, 214, 220, 255))]):
        base = 500 + i * 18
        d.polygon([(450 + dx - ww * 0.5, base), (450 + dx + ww * 0.5, base),
                   (450 + dx + ww * 0.18, base + hh), (450 + dx - ww * 0.22, base + hh * 0.86)],
                  fill=col)
    # 主袍
    robe = [(450, 120), (520, 156), (556, 300), (540, 500), (360, 500), (344, 300), (380, 156)]
    d.polygon(robe, fill=(228, 238, 240, 255))
    d.polygon([(450, 120), (520, 156), (556, 300), (540, 500), (450, 500)], fill=(244, 250, 250, 255))
    # 衣褶
    for x0, x1, col in ((400, 430, (196, 214, 220, 255)), (470, 500, (204, 222, 228, 255))):
        d.line([(x0, 190), (x1, 480)], fill=col, width=10)
    # 腰封
    d.rectangle([372, 330, 528, 372], fill=(46, 96, 112, 255))
    d.rectangle([372, 330, 528, 338], fill=GOLD)
    d.rectangle([444, 330, 460, 372], fill=GOLD_L)
    # 双臂与广袖
    d.polygon([(388, 176), (330, 240), (276, 388), (336, 410), (382, 286)], fill=(214, 230, 234, 255))
    d.polygon([(512, 176), (576, 236), (628, 380), (566, 406), (520, 286)], fill=(240, 248, 248, 255))
    d.line([(276, 388), (336, 410)], fill=CYAN_D, width=5)
    d.line([(628, 380), (566, 406)], fill=(200, 220, 226, 255), width=5)
    # 袖口里的手
    d.ellipse([300, 372, 344, 414], fill=SKIN)
    d.ellipse([560, 368, 604, 410], fill=SKIN)
    d.line([(322, 392), (306, 352)], fill=SKIN_D, width=5)
    # 领口
    d.polygon([(410, 140), (450, 196), (490, 140), (466, 126), (450, 160), (434, 126)], fill=CYAN_D)
    d.line([(410, 140), (490, 140)], fill=GOLD, width=4)
    # 头 / 发
    d.ellipse([404, 52, 496, 150], fill=SKIN)
    d.polygon([(396, 70), (408, 40), (450, 28), (492, 40), (504, 70), (496, 104),
               (480, 66), (420, 66)], fill=(238, 244, 246, 255))
    d.polygon([(400, 66), (392, 180), (420, 168), (414, 92)], fill=(240, 246, 248, 255))
    d.polygon([(500, 66), (508, 176), (480, 166), (486, 92)], fill=(226, 236, 240, 255))
    # 玉冠
    d.rectangle([426, 22, 474, 50], fill=(52, 116, 132, 255))
    d.line([(426, 34), (474, 34)], fill=GOLD_L, width=3)
    d.ellipse([442, 26, 458, 42], fill=CYAN_L)
    # 眼（半阖）
    d.line([(422, 104), (440, 100)], fill=INK, width=3)
    d.line([(460, 100), (478, 104)], fill=INK, width=3)
    d.line([(436, 126), (464, 126)], fill=(180, 120, 110, 255), width=2)
    # 腰带垂下的气纹
    for x in (434, 466):
        d.line([(x, 372), (x, 470)], fill=(150, 200, 216, 200), width=3)
    img = ac.polish(img, grain=0.07, rim_alpha=0.16)
    img.save(os.path.join(BOSS, "boss_qijun.png"))
    print("boss_qijun")


# ===================== 云石战场 =====================
def arena():
    rng = random.Random(43)
    w, h = 1200, 676
    cx, cy = w * 0.5, h * 0.52
    img = Image.new("RGBA", (w, h), (18, 26, 32, 255))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=(int(40 + (14 - 40) * t), int(50 + (20 - 50) * t),
                                       int(58 + (26 - 58) * t), 255))
    # 12 圈云石扇形
    R = 760
    for i in range(12):
        a0 = i * 30 - 90
        shade = rng.randint(-7, 7)
        d.pieslice([cx - R, cy - R, cx + R, cy + R], a0, a0 + 30,
                   fill=(52 + shade, 64 + shade, 70 + shade, 255))
    for i in range(12):
        a = math.radians(i * 30 - 90)
        d.line([(cx, cy), (cx + math.cos(a) * R, cy + math.sin(a) * R)],
               fill=(14, 20, 26, 190), width=3)
    for rr, al in ((R - 8, 220), (380, 150), (290, 130)):
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(18, 24, 30, al), width=3)
    # 中央气环刻纹
    ir = 236
    d.ellipse([cx - ir - 8, cy - ir - 8, cx + ir + 8, cy + ir + 8], fill=(26, 34, 40, 255))
    d.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], outline=(120, 200, 214, 110), width=3)
    d.ellipse([cx - ir + 40, cy - ir + 40, cx + ir - 40, cy + ir - 40], outline=(120, 200, 214, 80), width=2)
    for k in range(3):
        a0 = 20 + k * 120
        d.arc([cx - ir + 12, cy - ir + 12, cx + ir - 12, cy + ir - 12], a0, a0 + 48,
              fill=(170, 232, 246, 150), width=5)
    # 云纹：几条柔和弧线
    cloud = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cloud)
    for i in range(16):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(280, R - 60)
        x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.72
        cd.arc([x - 90, y - 30, x + 90, y + 50], 200, 340, fill=(190, 214, 220, 26), width=6)
    img = Image.alpha_composite(img, cloud.filter(ImageFilter.GaussianBlur(8)))
    # 裂纹
    for i in range(7):
        a = rng.uniform(0, math.tau)
        r0 = rng.uniform(320, R - 40)
        x, y = cx + math.cos(a) * r0, cy + math.sin(a) * r0
        pts = [(x, y)]
        for k in range(4):
            a += rng.uniform(-0.35, 0.35)
            r0 -= rng.uniform(24, 52)
            x, y = cx + math.cos(a) * r0, cy + math.sin(a) * r0
            pts.append((x, y))
        d.line(pts, fill=(10, 14, 18, 190), width=3, joint="curve")
    # 冷光 + 暗角
    sheen = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse([-w * 0.1, -h * 0.5, w * 0.8, h * 0.5], fill=(120, 200, 220, 30))
    img = Image.alpha_composite(img, sheen.filter(ImageFilter.GaussianBlur(40)))
    img = Image.alpha_composite(img, ac.vignette((w, h), 0.5))
    img = ac.polish(img, grain=0.09, rim_alpha=0.0)
    img = ImageEnhance.Brightness(img).enhance(0.88)
    img.convert("RGB").save(os.path.join(SCENES, "qijun_arena_ground.png"))
    print("arena")


# ===================== 图鉴卡 =====================
def card():
    cw, ch = 640, 960
    card = Image.new("RGBA", (cw, ch), (8, 14, 20, 255))
    d = ImageDraw.Draw(card)
    for y in range(ch):
        t = y / ch
        d.line([(0, y), (cw, y)], fill=(int(9 + 10 * t), int(16 + 12 * t), int(22 + 14 * t), 255))
    card = Image.alpha_composite(card, ac.radial_glow((cw, ch), (120, 200, 220), 330, 46))
    ring = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rcx, rcy = cw // 2, 400
    for r, a in ((316, 40), (298, 56), (280, 70)):
        rd.ellipse([rcx - r, rcy - r, rcx + r, rcy + r], outline=(120, 200, 220, a), width=2)
    rd.ellipse([rcx - 262, rcy - 262, rcx + 262, rcy + 262], outline=(196, 158, 82, 110), width=3)
    for k in range(3):
        a0 = 20 + k * 120
        rd.arc([rcx - 240, rcy - 240, rcx + 240, rcy + 240], a0, a0 + 46,
               fill=(170, 232, 246, 120), width=4)
    card = Image.alpha_composite(card, ring.filter(ImageFilter.GaussianBlur(0.8)))
    # 人物
    fig = Image.open(os.path.join(BOSS, "boss_qijun.png")).convert("RGBA")
    scale = 1.06
    fig = fig.resize((int(900 * scale), int(720 * scale)), Image.LANCZOS)
    ox = int(cw * 0.5 - 450 * scale)
    oy = 80
    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([cw * 0.5 - 150, oy + 720 * scale - 40, cw * 0.5 + 150, oy + 720 * scale + 30],
               fill=(0, 0, 0, 150))
    card = Image.alpha_composite(card, shadow.filter(ImageFilter.GaussianBlur(18)))
    # 背后青色轮廓光
    rim = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    rim.alpha_composite(fig, (ox, oy))
    gold = Image.new("RGBA", (cw, ch), (170, 232, 246, 255))
    gold.putalpha(rim.getchannel("A").point(lambda v: int(v * 0.45)))
    card = Image.alpha_composite(card, gold.filter(ImageFilter.GaussianBlur(14)))
    card.alpha_composite(fig, (ox, oy))
    # 底部淡出 + 暗角
    fade = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fade)
    for i in range(110):
        fd.line([(0, ch - 1 - i), (cw, ch - 1 - i)], fill=(6, 10, 14, int(160 * (i / 110) ** 2)))
    card = Image.alpha_composite(card, fade)
    card = Image.alpha_composite(card, ac.vignette((cw, ch), 0.5))
    card.convert("RGB").save(os.path.join(CARD, "card_boss_qijun.png"))
    print("card")


# ===================== 图标 =====================
def icon_canvas():
    return Image.new("RGBA", (768, 768), (0, 0, 0, 0))


def save_icon(img, name):
    img = img.resize((256, 256), Image.LANCZOS)
    img = ac.polish(img, grain=0.10, rim_alpha=0.20)
    img.save(os.path.join(ICON, name))
    print("icon", name)


def frame(color):
    c = icon_canvas()
    d = ImageDraw.Draw(c)
    d.ellipse([64, 64, 704, 704], fill=(12, 18, 24, 255), outline=GOLD, width=14)
    d.ellipse([86, 86, 682, 682], outline=color, width=4)
    for r, a in ((250, 18), (210, 24), (170, 30)):
        d.ellipse([384 - r, 384 - r, 384 + r, 384 + r], fill=(color[0], color[1], color[2], a))
    return c


def ring(d, cx, cy, r, width, color, a0=0, a1=360):
    d.arc([cx - r, cy - r, cx + r, cy + r], a0, a1, fill=color, width=width)


def icons():
    # 引气
    c = frame(CYAN)
    d = ImageDraw.Draw(c)
    for r, w in ((160, 8), (120, 6), (80, 5)):
        ring(d, 384, 384, r, w, (CYAN_L[0], CYAN_L[1], CYAN_L[2], 200), 20, 300)
    d.ellipse([354, 354, 414, 414], fill=CYAN_L)
    for k in range(6):
        a = math.radians(k * 60 + 15)
        d.line([(384 + math.cos(a) * 190, 384 + math.sin(a) * 190),
                (384 + math.cos(a) * 240, 384 + math.sin(a) * 240)], fill=(CYAN_L[0], CYAN_L[1], CYAN_L[2], 160), width=5)
    save_icon(c, "skill_qi_gather.png")
    # 裂空
    c = frame(CYAN_L)
    d = ImageDraw.Draw(c)
    for i, (dx, w, a) in enumerate([(-30, 22, 220), (10, 16, 180), (50, 12, 130)]):
        d.polygon([(170 + i * 34, 384 - w * 0.6), (650, 384 - w * 0.2),
                   (650, 384 + w * 0.2), (170 + i * 34, 384 + w * 0.6)],
                  fill=(CYAN[0], CYAN[1], CYAN[2], a))
    d.line([(170, 384), (650, 384)], fill=(240, 252, 252, 220), width=6)
    d.ellipse([640, 344, 712, 424], outline=CYAN_L, width=6)
    save_icon(c, "skill_qi_wave.png")
    # 回旋
    c = frame(CYAN)
    d = ImageDraw.Draw(c)
    ring(d, 384, 384, 210, 18, (CYAN[0], CYAN[1], CYAN[2], 220), 20, 300)
    ring(d, 384, 384, 150, 14, (CYAN_L[0], CYAN_L[1], CYAN_L[2], 200), 200, 120)
    ring(d, 384, 384, 90, 10, (CYAN[0], CYAN[1], CYAN[2], 200), 40, 320)
    d.ellipse([344, 344, 424, 424], fill=(20, 34, 42, 255), outline=CYAN_L, width=5)
    save_icon(c, "skill_qi_spin.png")
    # 缚脉
    c = frame((120, 150, 170))
    d = ImageDraw.Draw(c)
    ring(d, 384, 384, 190, 22, (150, 180, 196, 220))
    for k in range(6):
        a = math.radians(k * 60)
        d.line([(384 + math.cos(a) * 80, 384 + math.sin(a) * 80),
                (384 + math.cos(a) * 200, 384 + math.sin(a) * 200)],
               fill=(70, 100, 120, 230), width=14)
        d.ellipse([384 + math.cos(a) * 200 - 16, 384 + math.sin(a) * 200 - 16,
                   384 + math.cos(a) * 200 + 16, 384 + math.sin(a) * 200 + 16], fill=(190, 220, 230, 255))
    d.ellipse([352, 352, 416, 416], fill=(30, 46, 58, 255), outline=CYAN_L, width=4)
    save_icon(c, "skill_qi_lock.png")
    # 化劲
    c = frame(CYAN_L)
    d = ImageDraw.Draw(c)
    ring(d, 384, 400, 230, 10, (CYAN[0], CYAN[1], CYAN[2], 200), 180, 360)
    d.pieslice([174, 190, 594, 610], 180, 360, fill=(30, 52, 64, 210), outline=(170, 232, 246, 220))
    d.arc([214, 230, 554, 570], 180, 360, fill=(240, 252, 252, 200), width=8)
    for k in range(3):
        a = math.radians(200 + k * 45)
        d.line([(384 + math.cos(a) * 140, 400 + math.sin(a) * 140),
                (384 + math.cos(a) * 240, 400 + math.sin(a) * 240)],
               fill=(170, 232, 246, 140), width=5)
    save_icon(c, "skill_qi_ward.png")
    # 缩地
    c = frame(CYAN)
    d = ImageDraw.Draw(c)
    d.ellipse([250, 470, 520, 600], outline=(170, 232, 246, 160), width=8)
    for i in range(4):
        d.line([(230 + i * 40, 470 - i * 30), (330 + i * 40, 300 - i * 30)],
               fill=(CYAN[0], CYAN[1], CYAN[2], 120 + i * 25), width=12)
    d.polygon([(560, 220), (640, 300), (560, 380)], fill=(170, 232, 246, 220))
    save_icon(c, "skill_qi_step.png")
    # 气爆
    c = frame(CYAN_L)
    d = ImageDraw.Draw(c)
    for r, w, a in ((250, 14, 180), (190, 12, 200), (120, 10, 220)):
        ring(d, 384, 384, r, w, (CYAN_L[0], CYAN_L[1], CYAN_L[2], a))
    for k in range(12):
        a = math.radians(k * 30)
        d.line([(384 + math.cos(a) * 100, 384 + math.sin(a) * 100),
                (384 + math.cos(a) * 260, 384 + math.sin(a) * 260)],
               fill=(150, 230, 246, 170), width=6)
    d.ellipse([344, 344, 424, 424], fill=(240, 252, 252, 230))
    save_icon(c, "skill_qi_burst.png")
    # 吐纳
    c = frame((120, 220, 180))
    d = ImageDraw.Draw(c)
    d.pieslice([270, 300, 500, 530], 0, 180, fill=(30, 60, 52, 220), outline=(150, 230, 190, 220))
    for i in range(4):
        d.arc([330 - i * 8, 250 - i * 30, 440 + i * 8, 400 - i * 30], 200, 340,
              fill=(150, 240, 200, 200 - i * 30), width=8)
    for k in range(4):
        d.ellipse([350 + k * 18, 470 - k * 10, 362 + k * 18, 482 - k * 10], fill=(200, 250, 220, 220))
    save_icon(c, "skill_qi_breath.png")
    # 云履
    c = frame(CYAN)
    d = ImageDraw.Draw(c)
    d.polygon([(240, 300), (330, 260), (380, 430), (300, 500), (220, 460)], fill=(226, 236, 240, 255))
    d.polygon([(380, 430), (520, 380), (560, 430), (470, 520), (300, 500)], fill=(200, 216, 224, 255))
    d.line([(300, 500), (470, 520)], fill=CYAN_D, width=10)
    for i in range(3):
        d.arc([240 + i * 30, 220 + i * 20, 520 + i * 30, 400 + i * 20], 200, 320,
              fill=(170, 232, 246, 150), width=6)
    save_icon(c, "equip_taixu_yunlv.png")
    # 气海玉坠
    c = frame(CYAN_L)
    d = ImageDraw.Draw(c)
    d.line([(384, 120), (384, 220)], fill=GOLD, width=8)
    d.ellipse([300, 210, 468, 378], fill=(30, 110, 126, 255), outline=GOLD, width=10)
    d.ellipse([340, 250, 428, 338], fill=(14, 40, 48, 255), outline=(170, 232, 246, 200), width=5)
    d.arc([310, 220, 458, 368], 200, 320, fill=(190, 240, 250, 200), width=7)
    save_icon(c, "equip_qihai_yuzhui.png")
    # 太虚气晶
    c = frame(CYAN)
    d = ImageDraw.Draw(c)
    d.polygon([(384, 140), (560, 330), (470, 600), (300, 600), (210, 330)], fill=(80, 180, 200, 255), outline=(170, 232, 246, 255))
    d.polygon([(384, 140), (470, 600), (384, 520)], fill=(180, 240, 250, 230))
    d.line([(384, 160), (384, 560)], fill=(240, 252, 252, 200), width=6)
    save_icon(c, "mat_taixu_qijing.png")
    # 元魂
    c = icon_canvas()
    for r, a in ((250, 50), (210, 70), (170, 90)):
        g = Image.new("RGBA", (768, 768), (0, 0, 0, 0))
        gd = ImageDraw.Draw(g)
        gd.ellipse([384 - r, 360 - r, 384 + r, 360 + r], fill=(120, 200, 220, a))
        c = Image.alpha_composite(c, g.filter(ImageFilter.GaussianBlur(r * 0.18)))
    d = ImageDraw.Draw(c)
    # 一缕气：三圈升腾 + 两只眼
    for i in range(3):
        d.arc([260 - i * 20, 380 - i * 60, 508 + i * 20, 640 - i * 60], 190, 350,
              fill=(170, 232, 246, 210 - i * 40), width=14)
    d.ellipse([344, 300, 424, 360], fill=(20, 40, 50, 230), outline=(190, 240, 250, 220), width=5)
    d.ellipse([362, 320, 382, 340], fill=(230, 250, 252, 240))
    d.ellipse([386, 320, 406, 340], fill=(230, 250, 252, 240))
    save_icon(c, "soul_qi.png")
    # 气君令
    c = icon_canvas()
    c = Image.alpha_composite(c, glow((768, 768), CYAN, 250, 80))
    d = ImageDraw.Draw(c)
    cx, cy = 384, 372
    d.ellipse([cx - 160, cy + 190, cx + 160, cy + 258], fill=(0, 0, 0, 85))
    d.line([(cx, cy + 196), (cx, cy + 300)], fill=GOLD, width=10)
    for i in range(5):
        d.line([(cx, cy + 250), (cx - 48 + i * 24, cy + 352)], fill=(120, 96, 50, 230), width=5)
    d.rounded_rectangle([cx - 150, cy - 196, cx + 150, cy + 196], radius=30,
                        fill=INK, outline=GOLD, width=14)
    d.rounded_rectangle([cx - 134, cy - 180, cx + 134, cy + 180], radius=22, outline=GOLD_L, width=3)
    # 三环
    for r, a in ((110, 220), (84, 180), (58, 140)):
        d.arc([cx - r, cy - r, cx + r, cy + r], 20, 300, fill=(CYAN[0], CYAN[1], CYAN[2], a), width=8)
    d.ellipse([cx - 22, cy - 22, cx + 22, cy + 22], fill=CYAN_L)
    d.ellipse([cx - 20, cy - 166, cx + 20, cy - 126], fill=(10, 12, 14, 255), outline=GOLD, width=5)
    save_icon(c, "tr_qi_ling.png")


if __name__ == "__main__":
    ensure()
    qi_ring()
    boss_art()
    arena()
    card()
    icons()
    print("qijun art done")
