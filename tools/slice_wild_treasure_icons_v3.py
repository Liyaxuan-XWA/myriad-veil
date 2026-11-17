"""切野修法宝第二组图标（2×2，洋红底，2026-11-01）。

- 断念铃 / 禁步桩 / 续命灯 / 蚀甲锥
- 与既有物品图标同口径：256² RGBA、保留物件原轮廓、无圆形裁切
- 底部水印用「亮洋红混色」定向擦除，避免整块矩形裁掉蚀甲锥尖
"""
from PIL import Image, ImageFilter
import numpy as np
import os
from scipy import ndimage

SRC = "vibe_images/wild_treasure_icons_sheet_v3_1793481600814_0c468d9f.png"
OUT = "assets/ui/icon"
NAMES = [
    "tr_xuesi_yin", "tr_huanwei_jue",
    "tr_jijia_pei", "tr_huifeng_dai",
]


def patch_watermark(im):
    a = np.array(im.convert("RGBA")).astype(np.int16)
    h, w, _ = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    region = (xx > w - 190) & (yy > h - 60)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    # 水印有两种：压在洋红上的浅色半透明字（r 高、g 被抬高、b 仍偏洋红），
    # 以及直接压在白底上的浅灰字（三通道都高、低饱和）。两种都擦掉。
    mag_tint = (r > 200) & (g > 20) & (g < 150) & (b > 165)
    light_gray = (r > 150) & (g > 150) & (b > 150)         & ((np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)) < 70)
    mask = region & (mag_tint | light_gray)
    a[mask] = (240, 0, 166, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def keyed(cell, thresh=48):
    a = np.array(cell.convert("RGBA")).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mag = np.minimum(r, b) - g
    alpha = np.where(mag > thresh, 0, 255).astype(np.uint8)
    gray = ((r + g + b) // 3).astype(np.int16)
    tint = mag > 4
    r2 = np.where(tint, np.minimum(r, gray + 10), r)
    b2 = np.where(tint, np.minimum(b, gray + 14), b)
    out = np.stack([r2, g, b2, alpha], axis=-1).astype(np.uint8)
    res = Image.fromarray(out, "RGBA")
    al = res.getchannel("A").filter(ImageFilter.GaussianBlur(0.6)).point(
        lambda v: 0 if v < 110 else 255)
    res.putalpha(al)
    # 透明区里残留的洋红 RGB 会在大图缩小时渗进边缘，先向最近的不透明色渗透
    arr = np.array(res)
    opaque = arr[:, :, 3] > 8
    if opaque.any():
        inds = ndimage.distance_transform_edt(
            ~opaque, return_distances=False, return_indices=True)
        arr[:, :, :3] = arr[:, :, :3][tuple(inds)]
        res = Image.fromarray(arr, "RGBA")
    return res


def square_crop(cell, pad=6):
    bbox = cell.getbbox()
    if not bbox:
        return None
    cx = (bbox[0] + bbox[2]) * 0.5
    cy = (bbox[1] + bbox[3]) * 0.5
    half = max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.5 + pad
    return cell.crop((int(cx - half), int(cy - half), int(cx + half), int(cy + half)))


im = patch_watermark(Image.open(SRC))
im.load()
cw, ch = im.width // 2, im.height // 2
os.makedirs(OUT, exist_ok=True)
for idx, name in enumerate(NAMES):
    col, row = idx % 2, idx // 2
    cell = im.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
    cell = keyed(cell)
    cell = square_crop(cell)
    if cell is None:
        print("EMPTY", name)
        continue
    cell = cell.resize((256, 256), Image.LANCZOS)
    cell.save(os.path.join(OUT, name + ".png"))
    print("icon", name, cell.size)
