"""离照：原型图去水印 / 洋红键色 / 放置到 rig 画布（2026-10-29）。"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

SRC = "vibe_images/boss_lizhao_tpose_1793230585948_ad969c0d.png"
OUT = "vibe_images/_lizhao_placed.png"
PREVIEW = "vibe_images/_lizhao_grid.png"
CANVAS = (900, 720)
BODY_CX = 480.0
FEET_Y = 700.0
TARGET_H = 660.0


def key_out(img):
    a = np.array(img.convert("RGBA")).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mag = np.minimum(r, b) - g
    alpha = np.where(mag > 45, 0, 255).astype(np.uint8)
    gray = ((r + g + b) // 3).astype(np.int16)
    tint = mag > 6
    r2 = np.where(tint, np.minimum(r, gray + 10), r)
    b2 = np.where(tint, np.minimum(b, gray + 14), b)
    out = np.stack([r2, g, b2, alpha], axis=-1).astype(np.uint8)
    res = Image.fromarray(out, "RGBA")
    al = res.getchannel("A").filter(ImageFilter.GaussianBlur(0.7)).point(
        lambda v: 0 if v < 96 else 255)
    res.putalpha(al)
    return res


def main():
    im = Image.open(SRC).convert("RGBA")
    # 右下角水印在洋红背景上：先铺回洋红，避免键色后留下灰字
    d = ImageDraw.Draw(im)
    d.rectangle([780, 1420, 1024, 1536], fill=(255, 0, 255, 255))
    keyed = key_out(im)
    bbox = keyed.getbbox()
    print("src", im.size, "bbox", bbox)
    crop = keyed.crop(bbox)
    scale = TARGET_H / float(crop.height)
    nw = int(crop.width * scale)
    nh = int(crop.height * scale)
    crop = crop.resize((nw, nh), Image.LANCZOS)
    # 原图身体中心（估）：source x=530；裁切后相对坐标
    body_rel = (530.0 - float(bbox[0])) * scale
    x0 = int(round(BODY_CX - body_rel))
    y0 = int(round(FEET_Y - nh))
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    canvas.alpha_composite(crop, (x0, y0))
    canvas.save(OUT)
    # 坐标网格预览
    prev = Image.new("RGBA", CANVAS, (28, 24, 26, 255))
    prev.alpha_composite(canvas)
    pd = ImageDraw.Draw(prev)
    for x in range(0, CANVAS[0], 50):
        pd.line([(x, 0), (x, CANVAS[1])], fill=(70, 70, 80, 120), width=1)
        pd.text((x + 2, 2), str(x), fill=(230, 230, 230, 220))
    for y in range(0, CANVAS[1], 50):
        pd.line([(0, y), (CANVAS[0], y)], fill=(70, 70, 80, 120), width=1)
        pd.text((2, y + 1), str(y), fill=(230, 230, 230, 220))
    prev.convert("RGB").save(PREVIEW)
    print("placed", (x0, y0, nw, nh), "body_rel", body_rel)


if __name__ == "__main__":
    main()
