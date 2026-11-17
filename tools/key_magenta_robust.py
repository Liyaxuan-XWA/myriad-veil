"""洋红键底（鲁棒版）：生成器给的洋红不是纯净 #E6007E，R 在 188~253 之间漂。

判据用色度而不是到某个固定色的距离：洋红 = R、B 同时明显高于 G。
再做边界连通域，只删「和边框连成一片的洋红」，人物内部被围住的洋红高光不误删。
"""
from __future__ import annotations
import numpy as np
from PIL import Image, ImageFilter
from scipy.ndimage import binary_dilation, gaussian_filter, label


def key_magenta_robust(path, spill: float = 0.85) -> Image.Image:
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mag = (r > 130.0) & (r > g + 55.0) & (b > g + 45.0) & (np.abs(r - b) < 150.0)
    # 全局删，不做边界连通域：这四位角色里没有一个真正的品红部件，
    # 而腿间 / 枝角间被围住的洋红恰恰是最容易漏的地方。
    bg = mag
    # 洋红边缘的内侧一圈：按「有多少洋红邻居」算半透明，避免硬锯齿
    near = binary_dilation(bg, iterations=3) & ~bg
    alpha = (~bg).astype(np.float32)
    strength = np.clip((np.stack([r - g, b - g]).min(axis=0)) / 130.0, 0.0, 1.0)
    alpha[near] = 1.0 - strength[near] * 0.95
    alpha = gaussian_filter(alpha, 0.7)
    # 解键：把边缘像素上叠加的洋红分量反解掉，不然会留一圈品红毛边
    key = np.array([230.0, 0.0, 126.0], np.float32)
    a3 = np.clip(alpha, 1e-3, 1.0)[..., None]
    spill_amt = np.clip(strength * spill, 0.0, 1.0)[..., None] * (1.0 - a3)
    color = (rgb - spill_amt * key) / np.maximum(1.0 - spill_amt, 1e-3)
    color = np.clip(color, 0.0, 255.0)
    return Image.fromarray((np.dstack([color, alpha * 255.0]) + 0.5).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    import sys
    from pathlib import Path
    out = Path("output/key_dbg.png")
    src = sys.argv[1]
    im = key_magenta_robust(src)
    a = np.asarray(im)
    print("alpha coverage %.1f%%  0<al<250 %.1f%%" % ((a[..., 3] > 24).mean() * 100,
          ((a[..., 3] > 8) & (a[..., 3] < 247)).mean() * 100))
    c = Image.new("RGB", im.size, (26, 26, 30))
    c.paste(im, (0, 0), im)
    c.save(out)
