#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""叠纸（boss_04_c）占位美术：纸袍人形 body + 青铜镇尺 rule。

没有生图配额时的替代件（用户 2026-11-02 口径：先占位，之后同名覆盖）。
刻意与执烛（青黑广袖 + 提灯）拉开：月白纸袍 + 硬折棱线 + 手里一把镇尺。
赛璐璐口径：平涂 + 硬边描线，不做柔渐变。
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.__file__))  # unused, kept for clarity
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RIG_DIR = os.path.join(ROOT, "assets", "characters", "boss", "diezhi_rig")

# 纸面主色 / 二阶面 / 折背暗面 / 墨痕描线 / 内衬青灰 / 青铜
PAPER = (220, 217, 206, 255)
PAPER2 = (196, 193, 182, 255)
CREASE = (150, 148, 140, 255)
INK = (26, 28, 32, 255)
LINING = (110, 122, 130, 255)
BRONZE = (138, 106, 60, 255)
BRONZE_HI = (196, 164, 106, 255)
BRONZE_LO = (82, 60, 34, 255)

W, H = 640, 800


def poly_edge(d, pts, width=5, fill=None):
    """硬边赛璐璐：填色 + 粗墨描线"""
    if fill is not None:
        d.polygon(pts, fill=fill)
    d.line(pts + [pts[0]], fill=INK, width=width, joint="curve")


HEAD_ROOM = 108          # 画布顶部到头顶的透明留白，落盘前裁掉


def make_body() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # ---- 袍身：上窄下宽的直棱柱，下摆切成硬折角（不是圆弧）----
    robe = [(300, 232), (368, 236), (402, 430), (430, 700),
            (406, 762), (300, 772), (214, 758), (228, 700), (252, 430)]
    poly_edge(d, robe, 6, PAPER)

    # 右半片受光少一档：折过来那半张纸
    right = [(352, 236), (368, 236), (402, 430), (430, 700), (412, 760), (356, 766)]
    poly_edge(d, right, 0, PAPER2)

    # ---- 硬折棱线：袍面上只有折出来的痕，没有布褶 ----
    for (x0, y0, x1, y1, x2, y2, x3, y3) in [
        (250, 350, 400, 332, 404, 348, 254, 366),
        (238, 520, 418, 498, 420, 514, 240, 536),
        (226, 672, 428, 652, 430, 668, 228, 688),
    ]:
        d.polygon([(x0, y0), (x1, y1), (x2, y2), (x3, y3)], fill=CREASE)

    # ---- 袖：方形大袖，袖口翻出青灰内衬 ----
    sleeve_l = [(268, 248), (236, 258), (186, 424), (232, 444), (268, 300)]
    poly_edge(d, sleeve_l, 5, PAPER)
    d.polygon([(186, 424), (232, 444), (226, 468), (182, 450)], fill=LINING, outline=INK)
    sleeve_r = [(378, 250), (428, 268), (476, 402), (436, 426), (392, 306)]
    poly_edge(d, sleeve_r, 5, PAPER2)
    d.polygon([(476, 402), (436, 426), (442, 450), (482, 426)], fill=LINING, outline=INK)

    # ---- 领：一道交领的硬折 ----
    d.polygon([(306, 236), (356, 240), (338, 300), (318, 296)], fill=CREASE, outline=INK)

    # ---- 头：一张对折的纸当脸，正中一道墨痕 ----
    head = [(334, 108), (386, 140), (380, 212), (330, 238), (290, 208), (296, 138)]
    poly_edge(d, head, 6, PAPER)
    d.line([(334, 108), (330, 238)], fill=INK, width=5)
    # 展开的那半边露出一道墨痕 = 「它在看着你」的唯一提示
    d.ellipse((346, 158, 372, 178), fill=INK)

    # ---- 脚底：纸边直接切地，不给鞋 ----
    d.polygon([(258, 764), (406, 758), (412, 786), (252, 792)], fill=LINING, outline=INK)
    return img


def make_rule() -> Image.Image:
    """青铜镇尺：一根压纸用的直尺，握点在左端（rig 的 part_joint 就挂在这里）"""
    rw, rh = 220, 64
    img = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bar = [(26, 20), (198, 12), (206, 40), (30, 50)]
    poly_edge(d, bar, 4, BRONZE)
    d.polygon([(30, 24), (196, 17), (198, 25), (31, 32)], fill=BRONZE_HI)
    d.polygon([(30, 42), (204, 34), (205, 41), (30, 50)], fill=BRONZE_LO)
    # 近握点的一端压一枚小云纹（读得出是文房器，不是兵器）
    d.ellipse((34, 26, 54, 44), outline=INK, width=3)
    return img


def main() -> None:
    os.makedirs(RIG_DIR, exist_ok=True)
    body_full = make_body()
    # 裁顶：head_top_y 取「贴图满高的一半」，留白不裁掉就会让血条飘在头顶外
    body = body_full.crop((0, HEAD_ROOM, W, H))
    body.save(os.path.join(RIG_DIR, "body.png"))
    make_rule().save(os.path.join(RIG_DIR, "rule.png"))
    # 立绘 = body + rule 合成（口径：立绘与 rig 必须是同一个姿势，不能各画一套）
    body = body_full
    rule = make_rule()
    body.alpha_composite(rule, (300, 300))
    portrait = Image.new("RGBA", (W, H), (238, 234, 224, 255))
    portrait.alpha_composite(body)
    out_dir = os.path.join(ROOT, "assets", "characters", "boss")
    portrait.convert("RGB").save(os.path.join(out_dir, "boss_diezhi.png"))
    print("wrote: %s (%d,%d)" % (os.path.join(RIG_DIR, "body.png"), *body.size))
    print("wrote: %s" % os.path.join(RIG_DIR, "rule.png"))
    print("wrote: %s" % os.path.join(out_dir, "boss_diezhi.png"))


if __name__ == "__main__":
    main()
