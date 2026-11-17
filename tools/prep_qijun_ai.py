"""把太虚气君的 AI 立绘抠成游戏素材（2026-10-28）。

生图底是洋红 (233,5,161) 一类的粉紫，不是 #FF00FF；判据用「洋红度 = min(r,b) − g」，
比欧氏距离稳。抠完按 900×720 画布摆位（云尾落在 y≈700），同时生成 640×960 图鉴卡。
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

SRC = "vibe_images/boss_qijun_cel_1793146574381_cb26dcd9.png"
OUT_BOSS = "assets/characters/boss/boss_qijun.png"
OUT_CARD = "assets/ui/codex/card_boss_qijun.png"
KEYED = "vibe_images/boss_qijun_keyed.png"


def key_out(img):
    a = np.array(img.convert("RGBA")).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mag = np.minimum(r, b) - g
    # 洋红 = 背景（含透过薄纱的底色）：一律抠掉；其余像素强制不透明
    alpha = np.where(mag > 45, 0, 255).astype(np.int16)
    gray = ((r + g + b) // 3).astype(np.int16)
    # 去溢色：任何残留洋红度都往灰白压，避免丝带泛粉
    tint = mag > 6
    r2 = np.where(tint, np.minimum(r, gray + 10), r)
    b2 = np.where(tint, np.minimum(b, gray + 14), b)
    out = np.stack([r2, g, b2, alpha], axis=-1).astype(np.uint8)
    res = Image.fromarray(out, "RGBA")
    # 1px 羽化，避免硬锯齿
    al = res.getchannel("A").filter(ImageFilter.GaussianBlur(0.7))
    al = al.point(lambda v: 0 if v < 96 else 255)
    res.putalpha(al)
    return res


def main():
    im = Image.open(SRC).convert("RGBA")
    keyed = key_out(im)
    bbox = keyed.getbbox()
    print("bbox", bbox)
    keyed = keyed.crop(bbox)
    keyed.save(KEYED)

    # 立绘：内容高 620，底边落在 700，水平居中
    target_h = 620
    scale = target_h / float(keyed.height)
    fw, fh = int(keyed.width * scale), target_h
    fig = keyed.resize((fw, fh), Image.LANCZOS)
    canvas = Image.new("RGBA", (900, 720), (0, 0, 0, 0))
    ox = (900 - fw) // 2
    oy = 700 - fh
    canvas.alpha_composite(fig, (ox, oy))
    canvas.save(OUT_BOSS)
    print("boss saved", canvas.size, "fig", (fw, fh), "at", (ox, oy))

    # 图鉴卡 640×960：青黑渐变 + 气环 + 抠好的立绘
    cw, ch = 640, 960
    card = Image.new("RGBA", (cw, ch), (8, 14, 20, 255))
    d = ImageDraw.Draw(card)
    for y in range(ch):
        t = y / ch
        d.line([(0, y), (cw, y)], fill=(int(8 + 10 * t), int(15 + 12 * t), int(21 + 14 * t), 255))
    card = Image.alpha_composite(card, ac.radial_glow((cw, ch), (120, 200, 220), 340, 44))
    ring = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rcx, rcy = cw // 2, 420
    for r, a in ((318, 34), (300, 48), (282, 60)):
        rd.ellipse([rcx - r, rcy - r, rcx + r, rcy + r], outline=(120, 200, 220, a), width=2)
    rd.ellipse([rcx - 264, rcy - 264, rcx + 264, rcy + 264], outline=(196, 158, 82, 100), width=3)
    for k in range(3):
        a0 = 20 + k * 120
        rd.arc([rcx - 242, rcy - 242, rcx + 242, rcy + 242], a0, a0 + 46,
               fill=(170, 232, 246, 110), width=4)
    card = Image.alpha_composite(card, ring.filter(ImageFilter.GaussianBlur(0.8)))
    # 人物：按卡高 900 缩放（保留全身与云尾）
    ch_fig = 880
    s2 = ch_fig / float(keyed.height)
    fw2, fh2 = int(keyed.width * s2), ch_fig
    fig2 = keyed.resize((fw2, fh2), Image.LANCZOS)
    fx = (cw - fw2) // 2
    fy = 56
    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([cw * 0.5 - 120, fy + fh2 - 46, cw * 0.5 + 120, fy + fh2 - 14], fill=(0, 0, 0, 70))
    card = Image.alpha_composite(card, shadow.filter(ImageFilter.GaussianBlur(18)))
    # 背后青色轮廓光
    rim = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    rim.alpha_composite(fig2, (fx, fy))
    glow = Image.new("RGBA", (cw, ch), (170, 232, 246, 255))
    glow.putalpha(rim.getchannel("A").point(lambda v: int(v * 0.40)))
    card = Image.alpha_composite(card, glow.filter(ImageFilter.GaussianBlur(16)))
    card.alpha_composite(fig2, (fx, fy))
    # 底部淡出 + 暗角
    fade = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fade)
    for i in range(170):
        fd.line([(0, ch - 1 - i), (cw, ch - 1 - i)], fill=(10, 16, 22, int(110 * (i / 170) ** 1.5)))
    card = Image.alpha_composite(card, fade)
    card = Image.alpha_composite(card, ac.vignette((cw, ch), 0.5))
    card.convert("RGB").save(OUT_CARD)
    print("card saved")


if __name__ == "__main__":
    main()
