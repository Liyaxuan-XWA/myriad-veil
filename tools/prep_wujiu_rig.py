"""晏无咎：原型图去水印 / 洋红键色 / 放置到 rig 画布（2026-10-29）。

定妆图：vibe_images/boss_wujiu_tpose_v2_1793233721335_a398f174.png
- 洋红背景有轻微渐变，键色阈值要比离照那张松一点，再对边缘做去洋红。
- 水印在右下角，先用同一行的背景色铺回去，避免键色后留下灰字。
- 输出 900×720 画布、脚底 y=700、身高 660，与既有 rig 同口径。
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

SRC = "vibe_images/boss_wujiu_tpose_v2_1793233721335_a398f174.png"
OUT = "vibe_images/_wujiu_placed.png"
PREVIEW = "vibe_images/_wujiu_grid.png"
CANVAS = (900, 720)
BODY_CX = 450.0
FEET_Y = 700.0
TARGET_H = 660.0


def patch_watermark(img):
    a = np.array(img.convert("RGB"))
    # 取水印左侧同高度的背景均值，水印区域整块铺回去
    ref = a[1470:1540, 640:790].reshape(-1, 3).mean(axis=0)
    a[1465:1545, 800:1024] = ref.astype(np.uint8)
    return Image.fromarray(a, "RGB").convert("RGBA")


def key_out(img):
    a = np.array(img.convert("RGBA")).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mag = np.minimum(r, b) - g
    # 芯部：明显洋红 → 全透明；边缘：压低红/蓝，去紫边
    alpha = np.where(mag > 38, 0, 255).astype(np.uint8)
    gray = ((r + g + b) // 3).astype(np.int16)
    tint = mag > 5
    r2 = np.where(tint, np.minimum(r, gray + 12), r)
    b2 = np.where(tint, np.minimum(b, gray + 16), b)
    out = np.stack([r2, g, b2, alpha], axis=-1).astype(np.uint8)
    res = Image.fromarray(out, "RGBA")
    # 收一圈半透明边，避免洋红残余
    al = res.getchannel("A").filter(ImageFilter.GaussianBlur(0.6)).point(
        lambda v: 0 if v < 110 else 255)
    res.putalpha(al)
    return res


def main():
    im = Image.open(SRC).convert("RGBA")
    im = patch_watermark(im)
    keyed = key_out(im)
    bbox = keyed.getbbox()
    print("src", im.size, "bbox", bbox)
    crop = keyed.crop(bbox)
    scale = TARGET_H / float(crop.height)
    nw, nh = int(crop.width * scale), int(crop.height * scale)
    crop = crop.resize((nw, nh), Image.LANCZOS)
    # 人物中轴（头部/腰/脚）在原图约 x=530
    body_rel = (530.0 - float(bbox[0])) * scale
    x0 = int(round(BODY_CX - body_rel))
    y0 = int(round(FEET_Y - nh))
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    canvas.alpha_composite(crop, (x0, y0))
    canvas.save(OUT)
    print("placed", (x0, y0, nw, nh), "scale", round(scale, 4))

    prev = Image.new("RGBA", CANVAS, (30, 26, 30, 255))
    prev.alpha_composite(canvas)
    pd = ImageDraw.Draw(prev)
    for x in range(0, CANVAS[0], 50):
        pd.line([(x, 0), (x, CANVAS[1])], fill=(80, 80, 92, 120), width=1)
        pd.text((x + 2, 2), str(x), fill=(235, 235, 235, 220))
    for y in range(0, CANVAS[1], 50):
        pd.line([(0, y), (CANVAS[0], y)], fill=(80, 80, 92, 120), width=1)
        pd.text((2, y + 1), str(y), fill=(235, 235, 235, 220))
    prev.convert("RGB").save(PREVIEW)


if __name__ == "__main__":
    main()
