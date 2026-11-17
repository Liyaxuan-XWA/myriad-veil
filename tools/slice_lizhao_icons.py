"""切离照技能图标表（4×2，洋红底圆形徽记）。"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import os

SRC = "vibe_images/lizhao_skill_sheet_1793230860874_6174297e.png"
OUT = "assets/ui/icon"
NAMES = [
    "skill_sun_step", "skill_sun_slash", "skill_sun_throw", "skill_sun_pull",
    "skill_sun_wind", "skill_sun_eclipse", "skill_sun_wheel", "skill_sun_meteor",
]
im = Image.open(SRC).convert("RGBA")
# 去掉右下角水印：填洋红
d = ImageDraw.Draw(im)
d.rectangle([im.width - 220, im.height - 80, im.width, im.height], fill=(255, 0, 255, 255))
cw, ch = im.width // 4, im.height // 2
os.makedirs(OUT, exist_ok=True)


def keyed(cell):
    a = np.array(cell).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mag = np.minimum(r, b) - g
    alpha = np.where(mag > 55, 0, 255).astype(np.uint8)
    out = np.stack([r, g, b, alpha], axis=-1).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


for idx, name in enumerate(NAMES):
    col, row = idx % 4, idx // 4
    cell = im.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
    cell = keyed(cell)
    bbox = cell.getbbox()
    if not bbox:
        continue
    # 以图标实际包围盒取正方形，保证圆心不会落在洋红边上
    cx = (bbox[0] + bbox[2]) * 0.5
    cy = (bbox[1] + bbox[3]) * 0.5
    half = max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.5 + 2
    box = (int(cx - half), int(cy - half), int(cx + half), int(cy + half))
    cell = cell.crop(box)
    mask = Image.new("L", cell.size, 0)
    md = ImageDraw.Draw(mask)
    w, h = cell.size
    md.ellipse([2, 2, w - 3, h - 3], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.1)).point(lambda v: 255 if v > 120 else 0)
    cell.putalpha(mask)
    cell = cell.resize((256, 256), Image.LANCZOS)
    cell.save(os.path.join(OUT, name + ".png"))
    print("icon", name, bbox)
