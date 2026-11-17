#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""叠纸卡面与华彩层替代件（无生图配额时先落盘，之后同名覆盖）。

用户口径（2026-11-02 约束原文）：卡面原图**必须有机位紧张感和动作**。
所以这一张不是把人端正贴中间，而是：
  · 低机位仰角（人物往上收，头顶留白压到最小）；
  · 对角线构图 —— 一道真实折痕从左上切到右下，人物在痕的右侧「跨出来」；
  · 痕两侧的画面**错位**（左半边整体下移 18px），这是这套机制本身的样子，
    看一眼就知道这张卡在讲「纸被折起来了」，不是又一个立正摆拍的守关者。
水墨卡 / 华彩三层都从这张主卡派生，保证四张同源（同一个人、同一机位、同一道痕）。
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from build_plain_holo_cards import make_lines  # noqa: E402

CODEX = os.path.join(ROOT, "assets", "ui", "codex")
HOLO = os.path.join(CODEX, "holo")

CARD_W, CARD_H = 640, 960
PAPER = (220, 217, 206)
INK = (26, 28, 32)
MOON = (218, 226, 236)
BRONZE = (138, 106, 60)


def body_layer(wanted_h: int, tilt: float) -> Image.Image:
    """rig 的身体件 + 镇尺合成一个「跨出来」的姿态：整身轻微侧倾并前压"""
    body = Image.open(os.path.join(ROOT, "assets/characters/boss/diezhi_rig/body.png"))
    rule = Image.open(os.path.join(ROOT, "assets/characters/boss/diezhi_rig/rule.png"))
    body = body.convert("RGBA")
    canvas = Image.new("RGBA", body.size, (0, 0, 0, 0))
    canvas.alpha_composite(body)
    canvas.alpha_composite(rule.convert("RGBA"), (300, 296))
    scale = wanted_h / canvas.height
    canvas = canvas.resize((max(1, int(canvas.width * scale)), wanted_h),
                           Image.Resampling.LANCZOS)
    return canvas.rotate(tilt, resample=Image.Resampling.BICUBIC, expand=True)


def card_face(with_figure: bool = True) -> Image.Image:
    """`with_figure=False` 只画场景（背景层），True 才是完整卡面。

    华彩三层要求 art 是真抠像：以前把整张卡面塞进 `_art`，alpha 全 255，
    结果 shader 里 `base*(1-ch.a)` 永远是 0 —— 背景层根本不显示，
    卡1 和卡3 变成同一张图（实测 MAD 5.1）。
    """
    img = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    crease_pt = [(96, 566), (CARD_W - 34, 646)]
    # ---- 底：墨色台面 + 一张摊开的宣纸（华彩层全项目都是暗底亮人，
    #      整幅铺满亮纸会把人像一起冲淡、发光带也无从分层 —— 与观澜 / 执烛同一档）----
    yy = np.linspace(0.0, 1.0, CARD_H)[:, None]
    xx = np.linspace(0.0, 1.0, CARD_W)[None, :]
    g = 0.05 + 0.10 * (1.0 - yy) + 0.04 * np.abs(xx - 0.5)
    base = np.stack([g * 250, g * 258, g * 276], -1)
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    # 那张纸：斜放的一页，边缘撕口；只覆盖人物所在的下半幅
    sheet = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheet)
    pts = [(56, 452), (556, 372), (614, 892), (104, 952)]
    sd.polygon(pts, fill=PAPER + (255,))
    sd.line(pts + [pts[0]], fill=(30, 32, 38, 255), width=6, joint="curve")
    # 撕口：沿纸页右边缘一小段毛边（必须落在纸内，否则在黑底上读成一串虚线）
    for i in range(14):
        t0 = i / 14.0
        x = 556 + (614 - 556) * t0
        y = 372 + (892 - 372) * t0
        sd.line((x - 12, y, x, y + 8), fill=(206, 202, 190, 255), width=4)
    sheet = sheet.rotate(-2.0, resample=Image.Resampling.BICUBIC, center=(CARD_W // 2, CARD_H // 2))
    img.alpha_composite(sheet)
    d = ImageDraw.Draw(img)

    # 纸面纤维与淡墨渍（画在纸上，不画到台面外面）
    grain = Image.effect_noise((CARD_W, CARD_H), 24).convert("L")
    ga = np.asarray(grain).astype(np.float32)[..., None] / 255.0
    arr = np.asarray(img).astype(np.float32)
    inside = np.asarray(sheet).astype(np.float32)[..., 3:4] / 255.0
    arr[..., :3] = arr[..., :3] * (1.0 + 0.10 * (ga - 0.5)) * inside +         arr[..., :3] * (1.0 - inside)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)

    # ---- 人物：站在那条痕的右下侧，像刚从对侧圆牌跨出来 ----
    # 痕上方的那半张纸整体错位 (+10, +18)：这才是「纸被折起来」的样子，
    # 不是给人像加一层运动模糊 —— 看一眼就知道这张卡在讲哪套机制。
    fig = body_layer(760, -7.0)
    fx = CARD_W - fig.width + 46
    fy = CARD_H - fig.height + 62
    above, below = split_by_crease(fig, fx, fy, crease_pt)
    layer = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    layer.alpha_composite(below, (fx, fy))
    layer.alpha_composite(above, (fx + 10, fy + 18))
    if with_figure:
        img.alpha_composite(layer)

    # ---- 脚下：一枚对位圆牌 + 一道拖出去的短棱（读得出「从这儿出来的」）----
    d = ImageDraw.Draw(img)
    cx, cy = int(CARD_W * 0.30), int(CARD_H * 0.86)
    d.ellipse((cx - 44, cy - 20, cx + 44, cy + 20), fill=MOON + (120,),
              outline=INK + (150,), width=4)
    d.line((cx, cy, fx + fig.width // 2, cy + 8), fill=(250, 250, 246, 210), width=7)

    # ---- 顶/底压暗 + 一条字印栏 ----
    vig = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vig)
    for i in range(120):
        a = int(96 * (1 - i / 120.0))
        vd.line((0, i, CARD_W, i), fill=(24, 22, 20, a))
        vd.line((0, CARD_H - 1 - i, CARD_W, CARD_H - 1 - i), fill=(24, 22, 20, a))
    img.alpha_composite(vig)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, CARD_W, 6), fill=INK + (200,))
    d.rectangle((0, CARD_H - 8, CARD_W, CARD_H), fill=INK + (220,))
    # 角色层 = 完整卡面的像素，但只保留人物那部分 alpha。
    # 这样 bg 叠 art 精确等于卡面，且压暗栏/棱线在两层里表现一致。
    art = img.convert("RGBA").copy()
    art.putalpha(layer.split()[3])
    return img.convert("RGB"), art


def split_by_crease(fig: Image.Image, ox: int, oy: int, seg) -> tuple:
    """按卡面坐标里的那条折痕把人物切成两半：痕上方那一片留给错位用"""
    (x0, y0), (x1, y1) = seg
    w, h = fig.size
    xs = np.arange(w)[None, :] + ox
    ys = np.arange(h)[:, None] + oy
    t = np.clip((xs - x0) / max(x1 - x0, 1), 0.0, 1.0)
    line = y0 + (y1 - y0) * t
    above = (ys < line)
    arr = np.asarray(fig.convert("RGBA")).astype(np.uint8)
    out = []
    for keep in (above, ~above):
        a = arr.copy()
        a[..., 3] = np.where(keep, a[..., 3], 0).astype(np.uint8)
        out.append(Image.fromarray(a, "RGBA"))
    return out[0], out[1]


def ink_card(face: Image.Image) -> Image.Image:
    """纸本水墨版：在宣纸上**重画**一遍（去色 + 滤镜不算水墨，用户 11-02 定过口径）。

    画法：人物的剪影只当作「墨块该落在哪儿」的模板，墨本身由笔触生成 ——
    浓墨起笔、淡墨收笔、折棱留白、袍面用几笔飞白擦出来的干笔。
    """
    w, h = face.size
    # 1) 宣纸底：暖白 + 纸纤维 + 四角淡渍
    fib = np.asarray(Image.effect_noise((w, h), 22).convert("L")).astype(np.float32)
    paper = np.full((h, w, 3), 238.0, np.float32)
    paper *= (0.955 + 0.075 * (fib / 255.0))[..., None]
    img = Image.fromarray(np.clip(paper, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    # 2) 取剪影（主卡里比纸面更亮的人与纸页都算「有形」，用它定位墨块）
    g = np.asarray(face.convert("L")).astype(np.float32)
    sil = (g > 120).astype(np.float32)
    from scipy.ndimage import gaussian_filter
    wash = gaussian_filter(sil, 7.0)
    edge = np.clip(wash - gaussian_filter(sil, 1.4), -1.0, 1.0)

    # 3) 三层墨：淡墨打底（水痕）→ 中墨成块 → 浓墨勾轮廓
    ink_layers = []
    for sigma, level, alpha in ((9.0, 150.0, 74), (3.0, 92.0, 128), (0.9, 40.0, 196)):
        m = gaussian_filter(sil, sigma)
        m = np.clip((m - 0.16) / 0.84, 0.0, 1.0)
        ink_layers.append((m, level, alpha))
    arr = np.asarray(img).astype(np.float32)
    for m, level, alpha in ink_layers:
        tone = np.full((h, w, 3), level, np.float32)
        # 墨里带竖向笔势：让每层墨沿笔的方向有浓淡起伏，而不是一团灰
        stroke = 0.82 + 0.36 * np.sin(np.linspace(0, 46.0, w))[None, :]             * np.linspace(0.6, 1.0, h)[:, None]
        a = (m * stroke * (alpha / 255.0))[..., None]
        arr[..., :3] = arr[..., :3] * (1.0 - a) + tone * a
        arr[..., 3] = np.maximum(arr[..., 3], m * alpha)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    # 4) 折棱留白：一笔宽白的枯笔横过袍面（水墨里「亮」是靠留白，不是靠高光）
    blank = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(blank)
    for x in range(70, w - 40, 6):
        y = 566 + (646 - 566) * ((x - 70) / float(w - 110))
        jitter = int(4 * np.sin(x * 0.06))
        bd.line((x, y - 9 + jitter, x + 7, y + 9 + jitter),
                fill=(246, 244, 236, 210), width=5)
    # 袍面的干笔飞白
    for i in range(26):
        x = int(np.random.default_rng(11 + i).integers(120, w - 140))
        y = int(np.random.default_rng(700 + i).integers(470, h - 120))
        bd.line((x, y, x + 26, y + 12), fill=(244, 242, 234, 120), width=3)
    blank = blank.filter(ImageFilter.GaussianBlur(0.7))
    img.alpha_composite(blank)

    # 5) 边缘做破墨：把整张按 wash 的边界压出一圈水痕
    d = ImageDraw.Draw(img)
    edge_band = np.clip(np.abs(edge) * 3.2, 0.0, 1.0)
    a2 = np.asarray(img).astype(np.float32)
    a2[..., 0] -= edge_band * 26
    a2[..., 1] -= edge_band * 24
    a2[..., 2] -= edge_band * 14
    img = Image.fromarray(np.clip(a2, 0, 255).astype(np.uint8), "RGBA")

    out = img.convert("RGB")
    # 6) 一枚淡赭小印压右下角（水墨卡的收笔处，不给金框）
    od = ImageDraw.Draw(out)
    od.rectangle((w - 116, h - 128, w - 62, h - 74), fill=(150, 66, 48), outline=(58, 30, 24))
    for i in range(3):
        od.line((w - 110 + i * 18, h - 122, w - 110 + i * 18, h - 80),
                fill=(232, 216, 200), width=3)
    return out


def main() -> None:
    os.makedirs(HOLO, exist_ok=True)
    face, art = card_face(True)
    scene, _ = card_face(False)
    face.save(os.path.join(CODEX, "card_boss_diezhi.png"), optimize=True)

    # 华彩角色层：真抠像，透明处让背景层透出来
    art.save(os.path.join(HOLO, "boss_04_c_art.png"), optimize=True)

    lines = make_lines(art)
    lines.save(os.path.join(HOLO, "boss_04_c_lines.png"), optimize=True)

    # 背景层：同一张卡面去掉人物的样子（不是模糊缩暗的假背景）
    scene.save(os.path.join(HOLO, "boss_04_c_bg.png"), optimize=True)

    ink_card(face).save(os.path.join(HOLO, "boss_04_c_ink.png"), optimize=True)
    for n in ("card_boss_diezhi.png", "boss_04_c_art.png", "boss_04_c_lines.png",
              "boss_04_c_bg.png", "boss_04_c_ink.png"):
        print("wrote", n)


if __name__ == "__main__":
    main()
