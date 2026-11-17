"""切早期三组技能图标（虎妖/刀客/剑客），3x3 黑底圆形徽记。

输出 assets/ui/icon/skill_*.png（256×256 RGBA），并生成 output/early_skill_icons_contact.png。
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT / "assets" / "ui" / "icon"
OUT = ROOT / "output"

TIGER = ROOT / "vibe_images" / "tiger_skill_icons_sheet_1793306215118_e700d598.png"
BLADE = ROOT / "vibe_images" / "blade_skill_icons_sheet_v2_1793306297189_c410601e.png"
SWORD = ROOT / "vibe_images" / "sword_skill_icons_sheet_1793306336936_51f21a6d.png"

# (输出名, 图集, 列, 行)
CARDS = [
    ("skill_tiger_claw", TIGER, 0, 0),
    ("skill_tiger_rock", TIGER, 1, 0),
    ("skill_tiger_sandstorm", TIGER, 2, 0),
    ("skill_tiger_stomp", TIGER, 0, 1),
    ("skill_tiger_orb", TIGER, 1, 1),

    ("skill_blade_slash", BLADE, 0, 0),
    ("skill_blade_heavy", BLADE, 1, 0),
    ("skill_blade_dash", BLADE, 2, 0),
    ("skill_blade_turn", BLADE, 0, 1),
    ("skill_blade_scar", BLADE, 1, 1),
    ("skill_blade_qi", BLADE, 2, 1),
    ("skill_blade_field", BLADE, 0, 2),
    ("skill_blade_counter", BLADE, 1, 2),
    ("skill_blade_peak", BLADE, 2, 2),

    ("skill_sword_stab", SWORD, 0, 0),
    ("skill_sword_lift", SWORD, 1, 0),
    ("skill_sword_chop", SWORD, 2, 0),
    ("skill_sword_cloud", SWORD, 0, 1),
    ("skill_sword_pierce", SWORD, 1, 1),
    ("skill_sword_myriad", SWORD, 2, 1),
    ("skill_sword_heaven", SWORD, 0, 2),
]


def cell(sheet: Image.Image, col: int, row: int) -> Image.Image:
    w, h = sheet.size
    x0 = round(col * w / 3)
    x1 = round((col + 1) * w / 3)
    y0 = round(row * h / 3)
    y1 = round((row + 1) * h / 3)
    return sheet.crop((x0, y0, x1, y1)).convert("RGBA")


def circle_mask(size: tuple[int, int]) -> Image.Image:
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    cx, cy = size[0] * 0.5, size[1] * 0.5
    r = min(size) * 0.492
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    return mask.filter(ImageFilter.GaussianBlur(0.8)).point(lambda v: 255 if v > 120 else 0)


def main() -> None:
    sheets = {}
    sheet = Image.new("RGB", (7 * 148, 3 * 176), (16, 16, 16))
    draw = ImageDraw.Draw(sheet)
    for idx, (name, path, col, row) in enumerate(CARDS):
        if path not in sheets:
            sheets[path] = Image.open(path).convert("RGB")
        im = cell(sheets[path], col, row)
        im.putalpha(circle_mask(im.size))
        im = im.resize((256, 256), Image.LANCZOS)
        im.save(ICON / f"{name}.png")
        pv = im.resize((128, 128), Image.LANCZOS)
        x = (idx % 7) * 148 + 10
        y = (idx // 7) * 176 + 28
        sheet.paste(pv, (x, y), pv)
        draw.text((x, y - 16), name.replace("skill_", ""), fill=(235, 235, 235))
        print("icon", name)
    OUT.mkdir(exist_ok=True)
    sheet.save(OUT / "early_skill_icons_contact.png")


if __name__ == "__main__":
    main()
