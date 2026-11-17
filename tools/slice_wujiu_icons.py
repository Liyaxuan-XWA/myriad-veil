"""切晏无咎的技能 / 物品图标（2026-10-29）。

- 技能表：4×2，圆形徽记 → 256²，圆形 alpha 收边（与离照同一套）。
- 物品表：3×2，物件保留原轮廓 → 256²，无圆形裁切（与既有装备图标一致）。
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import os
from scipy import ndimage

OUT = "assets/ui/icon"
SKILL_SRC = "vibe_images/wujiu_skill_sheet_1793234195445_f11d3a12.png"
ITEM_SRC = "vibe_images/wujiu_item_sheet_1793234235357_be6f17a2.png"
SKILLS = [
    "skill_calamity_step", "skill_calamity_slash",
    "skill_calamity_fire_seal", "skill_calamity_fire_field",
    "skill_calamity_thunder_strike", "skill_calamity_thunder_pool",
    "skill_calamity_turn", "skill_calamity_final",
]
ITEMS = [
    "equip_jiefeng", "equip_jiehui_fayi", "mat_chixiao_jiehui",
    "soul_yanwujiu", "tr_jiezhu_ling", "tr_sanzai_lun",
]


def patch_watermark(im):
    d = ImageDraw.Draw(im)
    d.rectangle([im.width - 280, im.height - 100, im.width, im.height],
                fill=(224, 40, 166, 255))
    return im


def keyed(cell, thresh=48, drop_border=True):
    a = np.array(cell.convert("RGBA")).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mag = np.minimum(r, b) - g
    alpha = np.where(mag > thresh, 0, 255).astype(np.uint8)
    # 边缘连通的「假不透明」背景整块清掉：暗角背景可能没达到洋红阈值，
    # 但它一定和格子边界连通；图标本体是闭合圆形，不会连到边界。
    lab, n = ndimage.label(alpha > 0)
    border_ids = set()
    border_ids.update(np.unique(lab[0, :]).tolist())
    border_ids.update(np.unique(lab[-1, :]).tolist())
    border_ids.update(np.unique(lab[:, 0]).tolist())
    border_ids.update(np.unique(lab[:, -1]).tolist())
    border_ids.discard(0)
    if drop_border and border_ids:
        drop = np.isin(lab, list(border_ids))
        alpha[drop] = 0
    gray = ((r + g + b) // 3).astype(np.int16)
    tint = mag > 4
    r2 = np.where(tint, np.minimum(r, gray + 10), r)
    b2 = np.where(tint, np.minimum(b, gray + 14), b)
    out = np.stack([r2, g, b2, alpha], axis=-1).astype(np.uint8)
    res = Image.fromarray(out, "RGBA")
    al = res.getchannel("A").filter(ImageFilter.GaussianBlur(0.6)).point(
        lambda v: 0 if v < 110 else 255)
    res.putalpha(al)
    # 透明区里还存着洋红 RGB，直接 LANCZOS 缩放会把洋红混进图标边缘。
    # 先把离每个透明像素最近的不透明颜色「渗」过去，再缩放就不会有洋红圈。
    arr = np.array(res)
    opaque = arr[:, :, 3] > 8
    if opaque.any():
        inds = ndimage.distance_transform_edt(
            ~opaque, return_distances=False, return_indices=True)
        arr[:, :, :3] = arr[:, :, :3][tuple(inds)]
        res = Image.fromarray(arr, "RGBA")
    return res


def square_crop(cell, pad=4):
    bbox = cell.getbbox()
    if not bbox:
        return None
    cx = (bbox[0] + bbox[2]) * 0.5
    cy = (bbox[1] + bbox[3]) * 0.5
    half = max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.5 + pad
    box = (int(cx - half), int(cy - half), int(cx + half), int(cy + half))
    return cell.crop(box)


def slice_sheet(src, names, cols, rows, circle, drop_border=True, pad=0):
    im = patch_watermark(Image.open(src).convert("RGBA"))
    im.load()
    cw, ch = im.width // cols, im.height // rows
    os.makedirs(OUT, exist_ok=True)
    for idx, name in enumerate(names):
        col, row = idx % cols, idx // cols
        # 技能表第 4/8 格图标偏左、越过了整格切线，按格切会把圆形边框切破，
        # 「边界连通背景」随即把整个图标当背景删掉，只剩空洞。外扩后图标重新闭合。
        x0 = max(0, col * cw - pad)
        y0 = max(0, row * ch - pad)
        x1 = min(im.width, (col + 1) * cw + pad)
        y1 = min(im.height, (row + 1) * ch + pad)
        cell = keyed(im.crop((x0, y0, x1, y1)).copy(),
                     drop_border=drop_border)
        cell = square_crop(cell)
        if cell is None:
            print("EMPTY", name)
            continue
        if circle:
            mask = Image.new("L", cell.size, 0)
            w, h = cell.size
            ImageDraw.Draw(mask).ellipse([4, 4, w - 5, h - 5], fill=255)
            mask = mask.filter(ImageFilter.GaussianBlur(1.1)).point(
                lambda v: 255 if v > 120 else 0)
            cell.putalpha(mask)
        cell = cell.resize((256, 256), Image.LANCZOS)
        cell.save(os.path.join(OUT, name + ".png"))
        print("icon", name, cell.size)


slice_sheet(SKILL_SRC, SKILLS, 4, 2, True, pad=24)
slice_sheet(ITEM_SRC, ITEMS, 3, 2, False, drop_border=False)
