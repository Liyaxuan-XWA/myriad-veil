"""为「赫连霄之后」的守关者做四卡对照图（2026-11-02）

标准：赫连霄及之前的万界主线 BOSS 四张卡是同一张原画的四种处理。
上面一行四张全卡并排，下面一行把每张的**上半 40%** 放大并排 ——
脸、发冠、道具形状的差异在全卡里看不出来，只有对齐放大才暴露。
"""

import os
from PIL import Image, ImageDraw

ROOT = r"D:\GodotProjects\myriad-veil"
CARDS = os.path.join(ROOT, "output", "cards")
OUT = os.path.join(ROOT, "output")

BOSS = [
    ("boss_03_b", "离照"),
    ("boss_03_c", "晏无咎"),
    ("boss_04", "观澜"),
    ("boss_04_b", "执烛"),
    ("boss_04_c", "叠纸"),
    ("world_core_lianqi", "青岚古猿"),
    ("world_core_zhuji", "云隐苍角"),
    ("world_core_jiedan", "赤金火麟"),
    ("world_core_shihou", "幽冥石犼"),
]
VARIANTS = ["scene", "portrait", "plain", "ink"]
HEADS = ["1 华彩·有背景", "2 普通卡", "3 纯华彩·无背景", "4 纸本水墨"]
W, H = 300, 450          # 全卡
HW, HH = 300, 180        # 上半放大


def find(boss, idx, label):
    p = os.path.join(CARDS, "%s_%02d_%s.png" % (boss, idx, label))
    if os.path.exists(p):
        return p
    for f in sorted(os.listdir(CARDS)):
        if f.startswith("%s_%02d_" % (boss, idx)):
            return os.path.join(CARDS, f)
    return None


def main():
    for boss, cname in BOSS:
        sheet = Image.new("RGB", (W * 4 + 30, H + HH + 78), (16, 17, 22))
        d = ImageDraw.Draw(sheet)
        d.text((8, 6), "%s  %s" % (cname, boss), fill=(236, 214, 158))
        for i in range(4):
            p = find(boss, i, VARIANTS[i])
            x = 8 + i * (W + 4)
            d.text((x + 4, 24), HEADS[i], fill=(200, 206, 220))
            if p is None:
                d.text((x + 4, 60), "缺图", fill=(240, 120, 120))
                continue
            im = Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS)
            sheet.paste(im, (x, 44))
            # 上半 40% 放大到同宽，横向对齐比脸
            top = Image.open(p).convert("RGB").crop((0, 0, im.width, int(im.height * 0.40)))
            top = top.resize((W, HH), Image.LANCZOS)
            sheet.paste(top, (x, 44 + H + 14))
        d.text((8, 44 + H + 2), "↑ 上半放大（比脸 / 发冠 / 道具形状）", fill=(150, 158, 176))
        out = os.path.join(OUT, "card_cmp_%s.png" % boss)
        sheet.save(out)
        print("cmp", cname, sheet.size)


main()
