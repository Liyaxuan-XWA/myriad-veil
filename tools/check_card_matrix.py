"""四张一致性修复的前置对照：现有普通卡 vs 母图（bg + art 1:1 合成）。

对照标准是赫连霄 boss_03 —— 他的普通卡和华彩合成是同一张插画。
"""
from __future__ import annotations
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
HOLO = ROOT / "assets" / "ui" / "codex" / "holo"
CODEX = ROOT / "assets" / "ui" / "codex"
OUT = ROOT / "output"
W, H = 640, 960

ROWS = [
    ("赫连霄 boss_03 (标准)", "boss_03", "card_boss_heilianxiao.png"),
    ("离照 boss_03_b", "boss_03_b", "card_boss_lizhao.png"),
    ("青岚·古猿 world_core_lianqi", "world_core_lianqi", "card_boss_core_ape.png"),
    ("云隐·苍角 world_core_zhuji", "world_core_zhuji", "card_boss_core_stag.png"),
    ("赤金·火麟 world_core_jiedan", "world_core_jiedan", "card_boss_core_qilin.png"),
]


def source(name):
    art = Image.open(HOLO / f"{name}_art.png").convert("RGBA")
    bg = Image.open(HOLO / f"{name}_bg.png").convert("RGB")
    flat = bg.copy()
    flat.paste(art, (0, 0), art)
    return art, bg, flat.convert("RGB")


def band(img, y0, y1):
    return img.crop((0, y0, W, y1))


def main():
    labels = ["现有普通卡", "背景层 _bg", "角色层 _art", "母图合成 bg+art"]
    cw, ch = 320, 480
    lh = 34
    sheet = Image.new("RGB", (cw * 4 + 10 * 5, (ch + lh) * len(ROWS) + 10 * (len(ROWS) + 1)), (16, 16, 20))
    d = ImageDraw.Draw(sheet)
    for r, (title, name, portrait) in enumerate(ROWS):
        p = CODEX / portrait
        cards = []
        cards.append(Image.open(p).convert("RGB") if p.exists() else Image.new("RGB", (W, H), (90, 20, 20)))
        art, bg, flat = source(name)
        cards.append(bg)
        a = Image.new("RGB", (W, H), (30, 30, 34))
        a.paste(art, (0, 0), art)
        cards.append(a)
        cards.append(flat)
        arr = np.array(art)
        al = arr[..., 3]
        ys, xs = np.nonzero(al > 24)
        cov = (al > 24).mean() * 100
        y0 = 34 + r * (ch + lh + 10)
        d.text((10, y0 - 26), title, fill=(235, 235, 235))
        for c, (lab, im) in enumerate(zip(labels, cards)):
            x = 10 + c * (cw + 10)
            sheet.paste(im.resize((cw, ch), Image.LANCZOS), (x, y0))
            d.text((x + 2, y0 + ch + 2), lab, fill=(200, 200, 200))
        d.text((10 + 3 * (cw + 10) + 130, y0 - 26),
               "alpha覆盖 %.1f%%  bbox x[%d,%d] y[%d,%d]" % (cov, xs.min(), xs.max(), ys.min(), ys.max()),
               fill=(255, 210, 120))
    out = OUT / "card_matrix_before.png"
    sheet.save(out)
    print("wrote", out, sheet.size)


main()
