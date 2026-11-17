"""生成凡界·换锋符的 4 张图标与 1 张剑气特效贴图（2026-11-07）。

全部程序化绘制，风格沿用 tools/_art_common.py 的润色层与 tools/gen_skill_fx.py
的柔光算法；输出路径与 ItemDB.MATERIALS / TREASURE_TEMPLATES / ArtDB.EFFECTS 对齐。

⚠ 正式美术同名覆盖即可，玩法代码不用改。
用法（项目根）：
    python tools/gen_blade_form_art.py
"""
from __future__ import annotations

import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(ROOT, "assets", "ui", "icon")
FX = os.path.join(ROOT, "assets", "effects", "skills")
os.makedirs(ICON, exist_ok=True)
os.makedirs(FX, exist_ok=True)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

random.seed(20261107)

INK = (18, 22, 28, 255)
PAPER = (232, 224, 202, 255)
PAPER_D = (196, 180, 150, 255)
GOLD = (196, 154, 70, 255)
RED = (168, 58, 48, 255)
CYAN = (120, 206, 232, 255)
CYAN_L = (212, 246, 252, 255)
STEEL = (106, 120, 134, 255)
STEEL_L = (188, 202, 214, 255)
BONE = (234, 226, 202, 255)
BONE_D = (162, 142, 110, 255)


def canvas():
    return Image.new("RGBA", (768, 768), (0, 0, 0, 0))


def add_glow(img, center, radius, color, alpha):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = center
    d.ellipse([x - radius, y - radius, x + radius, y + radius],
              fill=(color[0], color[1], color[2], alpha))
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(radius * 0.45)))


def save_icon(img, name):
    img = img.resize((256, 256), Image.LANCZOS)
    img = ac.polish(img, grain=0.12, rim_alpha=0.20, rim_color=(150, 210, 230))
    # 去掉极低 alpha 的环境雾底：只留主体与边缘一圈柔光，四角必须真透明
    img.putalpha(img.getchannel("A").point(lambda v: 0 if v < 14 else v))
    img.save(os.path.join(ICON, name))
    print("icon", name)


def icon_huya():
    """界门虎牙：一枚微弯的兽牙，根部带界门石屑。"""
    img = add_glow(canvas(), (384, 384), 250, CYAN, 36)
    d = ImageDraw.Draw(img)
    tooth = [(292, 156), (476, 156), (466, 286), (438, 438),
             (400, 606), (360, 452), (326, 292)]
    d.polygon(tooth, fill=BONE, outline=INK, width=9)
    d.polygon([(296, 156), (472, 156), (468, 224), (300, 224)],
              fill=BONE_D, outline=INK, width=7)
    # 牙体高光与纵向纹路
    d.line([(352, 240), (374, 420), (396, 560)], fill=CYAN_L, width=10)
    for i in range(3):
        d.arc([318 + i * 8, 230, 452 - i * 8, 470], 195, 345,
              fill=(196, 182, 152, 255), width=5)
    # 界门石屑
    for _ in range(14):
        x = random.randint(240, 540)
        y = random.randint(600, 690)
        r = random.randint(5, 13)
        d.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)],
                  fill=(126, 132, 138, 255), outline=INK)
    save_icon(img, "mat_fanjie_huya.png")


def icon_duanren():
    """凡铁断刃：斜置的断刀，断口有锯齿，刃口仍亮。"""
    img = add_glow(canvas(), (384, 384), 250, CYAN, 30)
    d = ImageDraw.Draw(img)
    blade = [(176, 556), (204, 300), (470, 158), (548, 196), (300, 574)]
    d.polygon(blade, fill=STEEL, outline=INK, width=10)
    # 亮刃线
    d.line([(210, 306), (474, 166), (544, 198)], fill=STEEL_L, width=14)
    d.line([(214, 322), (472, 186)], fill=CYAN_L, width=5)
    # 断口锯齿（刀身左上）
    jag = [(204, 300), (232, 276), (226, 250), (256, 232), (250, 204), (282, 190)]
    d.line(jag, fill=INK, width=12)
    # 刀柄与铆钉
    d.polygon([(176, 556), (300, 574), (272, 640), (150, 620)],
              fill=(92, 68, 52, 255), outline=INK, width=9)
    for cx, cy in [(196, 590), (246, 600)]:
        d.ellipse([cx - 12, cy - 12, cx + 12, cy + 12], fill=GOLD, outline=INK, width=4)
    save_icon(img, "mat_fanjie_duanren.png")


def icon_jianxie():
    """清风剑屑：三片细长碎屑，冷青白、边缘泛光。"""
    img = add_glow(canvas(), (384, 384), 260, CYAN, 48)
    d = ImageDraw.Draw(img)
    shards = [
        ([(250, 560), (318, 210), (352, 214), (300, 566)], CYAN_L),
        ([(372, 596), (430, 268), (462, 274), (420, 600)], (168, 224, 244, 255)),
        ([(492, 540), (536, 320), (562, 330), (532, 548)], (212, 240, 248, 255)),
    ]
    for pts, col in shards:
        d.polygon(pts, fill=col, outline=INK, width=7)
        d.line([pts[0], pts[1]], fill=(255, 255, 255, 255), width=5)
    for _ in range(18):
        x = random.randint(210, 580)
        y = random.randint(180, 620)
        r = random.randint(3, 7)
        d.ellipse([x - r, y - r, x + r, y + r], fill=CYAN_L)
    save_icon(img, "mat_fanjie_jianxie.png")


def icon_blade_form():
    """凡界·换锋符：符纸上三道由近及远的剑气 + 朱砂印。"""
    img = add_glow(canvas(), (384, 384), 270, CYAN, 40)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([204, 112, 564, 656], radius=30,
                        fill=PAPER, outline=INK, width=12)
    d.rounded_rectangle([228, 136, 540, 632], radius=20,
                        outline=RED, width=8)
    # 三道剑气：长短错落，右端收尖、左端渐隐
    for y, length, col in [(252, 210, (110, 190, 222, 255)),
                           (368, 276, (150, 224, 244, 255)),
                           (484, 226, (196, 240, 252, 255))]:
        for k in range(18):
            t = k / 17.0
            x0 = 262 + t * length
            a = int(205 * (1.0 - t) ** 1.4)
            w = max(2, int(11 * (1.0 - t) + 2))
            d.line([(x0, y), (x0 + length / 18.0 + 8, y)],
                   fill=(col[0], col[1], col[2], a), width=w)
        d.line([(258, y - 13), (258, y + 13)], fill=INK, width=6)
    # 朱印
    d.rounded_rectangle([420, 552, 504, 616], radius=8, fill=RED, outline=INK, width=6)
    d.line([(438, 574), (486, 574)], fill=PAPER, width=6)
    d.line([(438, 592), (486, 592)], fill=PAPER, width=6)
    save_icon(img, "tr_blade_form.png")


def gen_qi():
    """横向 320x96 剑气：左端起手渐隐、右端收尖爆亮，节点中心即长条中心。"""
    w, h = 320, 96
    x = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :]
    y = np.linspace(-1.0, 1.0, h, dtype=np.float32)[:, None]
    along = 0.34 * np.clip(np.sin(np.pi * np.clip(x, 0.0, 1.0)), 0.0, 1.0) ** 1.4 \
        + 0.82 * np.exp(-((x - 0.84) / 0.20) ** 2)
    tip_cut = np.clip((1.0 - x) / 0.09, 0.0, 1.0)
    head_cut = np.clip(x / 0.08, 0.0, 1.0)
    core = np.exp(-((y / 0.15) ** 2)) * along * tip_cut * head_cut
    halo = np.exp(-((y / 0.46) ** 2)) * along * tip_cut * head_cut * 0.44
    tip = np.exp(-((x - 0.90) / 0.055) ** 2 - (y / 0.11) ** 2) * 0.85
    energy = core + halo + tip
    jade = np.array([0.40, 0.79, 1.0], np.float32)
    white = np.array([0.95, 0.99, 1.0], np.float32)
    blend = np.clip(energy * 1.25, 0.0, 1.0)[..., None]
    rgb = jade[None, None, :] + (white - jade)[None, None, :] * blend
    alpha = np.clip(energy * 0.92, 0.0, 1.0)
    # 沿途星点
    for _ in range(9):
        sx = random.uniform(0.25, 0.92)
        sy = random.uniform(-0.34, 0.34)
        r = random.uniform(0.010, 0.024)
        spark = np.exp(-(((x - sx) / r) ** 2 + ((y - sy) / r) ** 2))
        alpha = np.clip(alpha + spark * random.uniform(0.25, 0.55), 0.0, 1.0)
        rgb = rgb + white[None, None, :] * (spark * 0.30)[..., None]
    rgba = np.dstack([np.clip(rgb, 0.0, 1.0), alpha])
    Image.fromarray((rgba * 255.0).astype(np.uint8), "RGBA").save(
        os.path.join(FX, "blade_form_qi.png"))
    print("fx  blade_form_qi.png", w, "x", h)


if __name__ == "__main__":
    icon_huya()
    icon_duanren()
    icon_jianxie()
    icon_blade_form()
    gen_qi()
    print("done: 4 icons + 1 fx")
