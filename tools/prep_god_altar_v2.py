"""铸神祭坛立绘 v2（2026-11-13）

旧版（prep_god_altar_art.py::_altar）是从一张庭院实景里裁出来的，靠**椭圆羽化**
把底座周围的地砖渐隐 —— 实机看就是一圈白灰雾边 + 底部没抠干净的地面。

v2 改成：以旧图为设计母本重绘（纯色背景）→ 从边框做连通泛洪 → 真剪影 +
软边 + 去背景色溢色，不再用椭圆遮罩。

用法：
  python tools/prep_god_altar_v2.py --src <重绘图.png> [--out 输出.png]
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "assets/scenes/world/god_altar.png")
BACKUP = os.path.join(ROOT, ".scratch/god_altar/god_altar_before.png")


def key_out(im: Image.Image, t0: float, t1: float) -> Image.Image:
    rgb = np.asarray(im.convert("RGB")).astype(np.float32)
    h, w = rgb.shape[:2]
    # 背景色：边框一圈的中位数（背景是纯色，中位数比均值抗溢出）
    ring = np.concatenate([
        rgb[0:3].reshape(-1, 3), rgb[h - 3:h].reshape(-1, 3),
        rgb[:, 0:3].reshape(-1, 3), rgb[:, w - 3:w].reshape(-1, 3)])
    bg = np.median(ring, axis=0)
    # 切比雪夫距离：三通道任一偏离都算，抗「背景渐变到暗红」
    d = np.abs(rgb - bg).max(axis=2)

    bg_like = (d < t0).astype(np.uint8) * 255
    m = Image.fromarray(bg_like, "L").copy()
    for x in range(w):
        for y in (0, h - 1):
            if m.getpixel((x, y)) == 255:
                ImageDraw.floodfill(m, (x, y), 128)
    for y in range(h):
        for x in (0, w - 1):
            if m.getpixel((x, y)) == 255:
                ImageDraw.floodfill(m, (x, y), 128)
    outside = np.asarray(m) == 128          # 与边框连通的背景
    inside_bg = (np.asarray(m) == 255)      # 被主体包住的同色区（比如晶柱里的暗红）→ 保留

    # 软边：距离在 [t0, t1] 之间给半透明，只对紧贴轮廓的一圈生效
    soft = np.clip((d - t0) / max(t1 - t0, 1e-3), 0.0, 1.0)
    alpha = np.where(outside, 0.0, 1.0).astype(np.float32)
    near = np.asarray(
        Image.fromarray((outside * 255).astype(np.uint8), "L")
        .filter(ImageFilter.MaxFilter(5))) > 0
    alpha = np.where(near & ~outside, soft, alpha)
    alpha = np.where(inside_bg, 1.0, alpha)

    a = Image.fromarray((alpha * 255).astype(np.uint8), "L")
    # 去孤立噪点 + 1px 羽化（只动 alpha，不动颜色）
    a = a.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    alpha = np.asarray(a).astype(np.float32) / 255.0

    # 去溢色：边缘像素把背景色成分减掉，免得留一圈红边
    a3 = alpha[..., None]
    fg = (rgb - (1.0 - a3) * bg) / np.maximum(a3, 1e-3)
    fg = np.clip(fg, 0, 255)

    # 贴着轮廓的「背景色碎屑」：石头底边常夹着几个没被泛洪吃到的背景色像素
    # （放大看是一排亮红点）。凡是**颜色还是背景色**、又紧挨着透明区的，一律清掉。
    near_out = np.asarray(
        Image.fromarray((outside * 255).astype(np.uint8), "L")
        .filter(ImageFilter.MaxFilter(9))) > 0
    # 判据一：颜色还是背景色；判据二：红得发亮（背景红和火焰边缘都这样，
    # 石台/金链/粉晶都到不了 «r - max(g,b) > 90» 这档）
    redness = rgb[..., 0] - np.maximum(rgb[..., 1], rgb[..., 2])
    speckle = ((d < t0) | (redness > 90.0)) & near_out
    alpha = np.where(speckle, 0.0, alpha)
    out = np.dstack([fg, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def neutralize_base_rim(im: Image.Image, keep: float = 0.85) -> Image.Image:
    """台基底边那圈「暖红反光」：AI 出图在石头缝里带了一圈红，
    放大看不见、缩到 170px 实机尺寸就成了一圈红边。
    只处理**下半部分 + 贴着透明轮廓 3px + 暖红但不亮**的像素，
    把它们按亮度去色（不删，免得在石头上开洞）；火焰边缘（够亮 / g 高）不碰。"""
    arr = np.asarray(im).astype(np.float32)
    h, w = arr.shape[:2]
    a = arr[..., 3]
    zero = (a < 8)
    near = np.asarray(
        Image.fromarray((zero * 255).astype(np.uint8), "L")
        .filter(ImageFilter.MaxFilter(7))) > 0
    rgb = arr[..., :3]
    red = rgb[..., 0] - np.maximum(rgb[..., 1], rgb[..., 2])
    yy = np.arange(h)[:, None] * np.ones((1, w), bool)
    # 台基缝里的红不一定贴着外轮廓（夹在石头缝里），所以不要求 near；
    # 用「g 低」把火焰排掉：火焰 g≈140+，缝里的红 g≈90
    mask = (yy > h * 0.45) & (red > 55.0) & (rgb[..., 0] < 235.0)         & (rgb[..., 1] < 130.0)
    gray = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2])[..., None]
    rgb_new = np.where(mask[..., None], rgb * (1.0 - keep) + gray * keep, rgb)
    arr[..., :3] = np.clip(rgb_new, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def drop_bottom_shadow(im: Image.Image, band: float = 0.10) -> Image.Image:
    """AI 出图底部常拖一层贴地灰雾。只削「低饱和 + 暗」的像素，
    石台台阶本身有明确轮廓、色相偏青灰，用饱和度/亮度两个条件能分开。"""
    arr = np.asarray(im).astype(np.float32)
    h = arr.shape[0]
    top = int(h * (1.0 - band))
    rgb = arr[..., :3] / 255.0
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    dark = mx < 0.62
    grayish = sat < 0.10
    mask = np.zeros((h, arr.shape[1]), bool)
    mask[top:] = True
    kill = mask & dark & grayish
    arr[..., 3] = np.where(kill, 0.0, arr[..., 3])
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--t0", type=float, default=34.0)
    ap.add_argument("--t1", type=float, default=78.0)
    ap.add_argument("--shadow-band", type=float, default=0.10)
    ap.add_argument("--size", type=int, default=512)
    args = ap.parse_args()

    im = Image.open(args.src).convert("RGBA")
    keyed = key_out(im, args.t0, args.t1)
    keyed = drop_bottom_shadow(keyed, args.shadow_band)
    keyed = neutralize_base_rim(keyed)

    bbox = keyed.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    keyed = keyed.crop(bbox)
    side_w, side_h = keyed.size
    # 左右 6%、上下 4% 留白，再按高度缩到目标尺寸
    pad_x = int(side_w * 0.06)
    pad_y = int(side_h * 0.04)
    canvas = Image.new("RGBA", (side_w + 2 * pad_x, side_h + 2 * pad_y), (0, 0, 0, 0))
    canvas.paste(keyed, (pad_x, pad_y), keyed)
    scale = args.size / canvas.height
    canvas = canvas.resize(
        (max(1, round(canvas.width * scale)), args.size), Image.LANCZOS)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    if os.path.abspath(args.out) == os.path.abspath(DEFAULT_OUT):
        os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
        if os.path.exists(args.out) and not os.path.exists(BACKUP):
            Image.open(args.out).save(BACKUP)
            print("旧图已备份 →", BACKUP)
    canvas.save(args.out)
    a = np.asarray(canvas.getchannel("A"))
    print("输出", args.out, canvas.size)
    print("alpha：全透明 %.1f%% / 半透明 %.1f%% / 不透明 %.1f%%" % (
        100 * (a == 0).mean(), 100 * ((a > 0) & (a < 250)).mean(),
        100 * (a >= 250).mean()))


if __name__ == "__main__":
    main()
