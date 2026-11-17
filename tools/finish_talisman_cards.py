# -*- coding: utf-8 -*-
"""符箓卡面后处理：把 AI 出图修成游戏可直接用的三张符卡（冰 / 光 / 暗）。

和 tools/gen_talisman_cards.py 的关系：
  · 现有 7 张（金木水火土风雷）由该脚本**程序化绘制**，是正式素材，本脚本不碰。
  · 冰 / 光 / 暗三张是试炼专属符，用 ImageGen 按「以 thunder 卡为风格参考」出图，
    再用本脚本做后处理。之所以不上程序化：这三张的符胆（冰晶 / 光棱 / 暗涡）
    靠笔刷叠不出体感，试过 AI 出图明显更接近「符纸画」的观感。
  · 将来若要统一成程序化，把 MOTIFS 里加 ice/light/dark 即可，ArtDB 无需改。

做两件事：
  1. 抹掉 AI 出图右下角的「AI生成 / WORKBUDDY」水印 —— 用**左侧同高度底带水平镜像**
     贴回右侧。朱砂边框转角在左侧 x≈0.03w，镜像后正好落在 x≈0.97w，云纹也跟着
     镜像成右侧云纹，接缝做 26px 羽化，肉眼看不出来。
     ⚠ 别改成「裁掉底部」：会把朱砂底边框切掉，卡面变成开口的。
  2. 统一规格：1024×1536 → 640×960（与现有 7 张一致）+ 轻柔化 + PNG 优化。

用法：python tools/finish_talisman_cards.py
"""

import os
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "output", "tal_cards")
DST_DIR = os.path.join(ROOT, "assets", "ui", "talisman", "cards")

# 源文件（ImageGen 输出，文件名带生成时间）→ 目标文件名
PLAN = [
    ("Traditional_Chinese_Daoist_tal_2026-11-10T03-24-42.png", "talisman_card_ice.png"),
    ("Traditional_Chinese_Daoist_tal_2026-11-10T03-25-18.png", "talisman_card_light.png"),
    ("Traditional_Chinese_Daoist_tal_2026-11-10T03-26-26.png", "talisman_card_dark.png"),
]

BAND_TOP = 0.930   # 水印底带起点（占高度比例）
BAND_W = 0.230     # 镜像底带宽度（占宽度比例）
FEATHER = 26       # 接缝羽化像素


def strip_watermark(im: Image.Image) -> Image.Image:
    w, h = im.size
    y0 = int(h * BAND_TOP)
    bw = int(w * BAND_W)
    band = im.crop((0, y0, bw, h)).transpose(Image.FLIP_LEFT_RIGHT)

    # 羽化只做在接缝那一侧（贴回后是左边缘），否则会出现一条硬边
    alpha = Image.new("L", band.size, 255)
    px = alpha.load()
    for x in range(FEATHER):
        v = int(255 * (x / float(FEATHER)))
        for y in range(band.height):
            px[x, y] = v
    im.paste(band, (w - bw, y0), alpha)
    return im


def main() -> None:
    os.makedirs(DST_DIR, exist_ok=True)
    for src_name, dst_name in PLAN:
        src = os.path.join(SRC_DIR, src_name)
        if not os.path.exists(src):
            print("!! 缺源图：%s" % src)
            continue
        im = Image.open(src).convert("RGB")
        im = strip_watermark(im)
        im = im.resize((640, 960), Image.LANCZOS)
        # 极轻柔化：AI 出图缩到 640 后线条偶尔发硬，0.4px 足够
        im = im.filter(ImageFilter.GaussianBlur(0.4))
        out = os.path.join(DST_DIR, dst_name)
        im.save(out, "PNG", optimize=True)
        print("  · %-24s %s  %.1fKB" % (dst_name, im.size, os.path.getsize(out) / 1024.0))


if __name__ == "__main__":
    main()
