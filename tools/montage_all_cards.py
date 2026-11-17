"""把 output/cards 里 60 张卡面按位面拼成分组总览（2026-11-02）

一行一位守关者，四列按图鉴卡序：华彩·有背景 / 普通卡 / 纯华彩·无背景 / 纸本水墨。
单张原生 600×900，缩到 240×360 排版；要看细节直接开 output/cards/ 里的原图。
"""

import os
from PIL import Image, ImageDraw

ROOT = r"D:\GodotProjects\myriad-veil"
CARDS = os.path.join(ROOT, "output", "cards")
CW, CH = 240, 360
PAD_L = 132          # 左侧留一列写 BOSS 名
VARIANTS = ["scene", "portrait", "plain", "ink"]
HEADS = ["华彩·有背景", "普通卡", "纯华彩·无背景", "纸本水墨"]

GROUPS = [
    ("凡界", ["boss_huyao", "boss_01", "boss_01_c"]),
    ("冲和界", ["boss_02", "boss_02_b", "boss_02_c"]),
    ("赤霄界", ["boss_03", "boss_03_b", "boss_03_c"]),
    ("照影界", ["boss_04", "boss_04_b", "boss_04_c"]),
    ("大陆核心首领", ["world_core_lianqi", "world_core_zhuji",
                    "world_core_jiedan", "world_core_shihou"]),
]

NAMES = {
    "boss_huyao": "虎妖", "boss_01": "刀客", "boss_01_c": "剑客",
    "boss_02": "两仪真人", "boss_02_b": "定阵先生", "boss_02_c": "太虚气君",
    "boss_03": "赫连霄", "boss_03_b": "离照", "boss_03_c": "晏无咎",
    "boss_04": "观澜", "boss_04_b": "执烛", "boss_04_c": "叠纸",
    "world_core_lianqi": "青岚·古猿", "world_core_zhuji": "云隐·苍角",
    "world_core_jiedan": "赤金·火麟", "world_core_shihou": "幽冥·石犼",
}


def find(boss_id: str, idx: int, label: str):
    """文件名里的变体 id 与图鉴常量不一定逐字相同，先按序号再按名字兜底。"""
    for p in (os.path.join(CARDS, "%s_%02d_%s.png" % (boss_id, idx, label)),
              os.path.join(CARDS, "%s_%02d_%s.png" % (boss_id, idx, "holo"))):
        if os.path.exists(p):
            return p
    for f in sorted(os.listdir(CARDS)):
        if f.startswith("%s_%02d_" % (boss_id, idx)):
            return os.path.join(CARDS, f)
    return None


def main():
    cols = len(VARIANTS)
    for gi, (title, bosses) in enumerate(GROUPS, 1):
        rows = len(bosses)
        sheet = Image.new("RGB", (PAD_L + cols * CW, 40 + rows * (CH + 6)), (14, 15, 20))
        d = ImageDraw.Draw(sheet)
        for c in range(cols):
            d.text((PAD_L + c * CW + 6, 14), HEADS[c], fill=(210, 214, 226))
        for r, boss in enumerate(bosses):
            y = 40 + r * (CH + 6)
            d.text((8, y + CH // 2 - 8), NAMES.get(boss, boss), fill=(228, 206, 150))
            for c in range(cols):
                p = find(boss, c, VARIANTS[c])
                if p is None:
                    d.rectangle([PAD_L + c * CW, y, PAD_L + (c + 1) * CW - 4, y + CH],
                                outline=(90, 60, 60))
                    d.text((PAD_L + c * CW + 10, y + 10), "缺", fill=(230, 120, 120))
                    continue
                im = Image.open(p).convert("RGB").resize((CW - 4, CH), Image.LANCZOS)
                sheet.paste(im, (PAD_L + c * CW, y))
        out = os.path.join(ROOT, "output", "card_sheet_%d.png" % gi)
        sheet.save(out)
        print("sheet %d  %s  %d 位  %s" % (gi, title, rows, sheet.size))


main()
