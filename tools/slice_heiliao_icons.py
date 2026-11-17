"""切赫连霄技能图标表（4×2，黑底圆形徽记）。"""
from PIL import Image, ImageDraw, ImageFilter
import os

SRC = "vibe_images/thunder_skill_icons_sheet_1793209220984_df7f51a6.png"
OUT = "assets/ui/icon"
NAMES = [
    "skill_thunder_verdict", "skill_thunder_execute", "skill_thunder_drum", "skill_thunder_lock",
    "skill_thunder_step", "skill_thunder_gather", "skill_thunder_nine", "skill_thunder_prison",
]
im = Image.open(SRC).convert("RGB")
# 去掉右下角水印：填黑
d = ImageDraw.Draw(im)
d.rectangle([im.width - 220, im.height - 80, im.width, im.height], fill=(0, 0, 0))
cw, ch = im.width // 4, im.height // 2
os.makedirs(OUT, exist_ok=True)
for idx, name in enumerate(NAMES):
    col, row = idx % 4, idx // 4
    cell = im.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)).convert("RGBA")
    # 圆形遮罩：图标在格内居中，半径取格的短边 0.44
    mask = Image.new("L", cell.size, 0)
    md = ImageDraw.Draw(mask)
    cx, cy = cell.width * 0.5, cell.height * 0.5
    r = min(cell.width, cell.height) * 0.492
    md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 255 if v > 120 else 0)
    cell.putalpha(mask)
    cell = cell.resize((256, 256), Image.LANCZOS)
    cell.save(os.path.join(OUT, name + ".png"))
    print("icon", name)
