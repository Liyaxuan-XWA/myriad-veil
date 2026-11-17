"""生成设施面板用 UI 素材：圆形徽章、透明立绘、柔光/圆环/光点。

源图：assets/scenes/facilities/<id>.png（2048 方形、透明底）
输出：assets/ui/facilities/<id>_cutout.png / <id>_medallion.png / glow_soft.png / ring_soft.png / dot_soft.png
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "scenes" / "facilities"
DST = ROOT / "assets" / "ui" / "facilities"
IDS = [
    "arena", "tower", "gateway", "alchemy", "herb_garden",
    "talisman", "memory", "forge", "warehouse",
]


def alpha_trim(im: Image.Image, pad_ratio: float = 0.02) -> Image.Image:
    im = im.convert("RGBA")
    box = im.getbbox()
    if box is None:
        return im
    pad = int(max(box[2] - box[0], box[3] - box[1]) * pad_ratio)
    box = (
        max(0, box[0] - pad), max(0, box[1] - pad),
        min(im.width, box[2] + pad), min(im.height, box[3] + pad),
    )
    return im.crop(box)


def circular_mask(size: int) -> Image.Image:
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    d = ImageDraw.Draw(m)
    d.ellipse((0, 0, size * ss - 1, size * ss - 1), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def make_medallion(src: Image.Image, out: Path, size: int = 256) -> None:
    art = alpha_trim(src, 0.04)
    # 横幅场景（药田 / 锻造台 / 仓库等）从中心取方形，否则缩进圆里只剩一条细线；
    # 竖高主体（塔 / 碑）保留全貌。
    if art.width > art.height * 1.25:
        side = art.height
        left = (art.width - side) // 2
        art = art.crop((left, 0, left + side, side))
    inner = int(size * 0.82)
    scale = min(inner / art.width, inner / art.height)
    new = (max(1, int(art.width * scale)), max(1, int(art.height * scale)))
    art = art.resize(new, Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(art, ((size - new[0]) // 2, (size - new[1]) // 2), art)
    mask = circular_mask(size)
    canvas.putalpha(Image.composite(canvas.getchannel("A"), Image.new("L", (size, size), 0), mask))
    canvas.save(out)


def make_cutout(src: Image.Image, out: Path, max_side: int = 640) -> None:
    art = alpha_trim(src, 0.02)
    scale = min(1.0, max_side / max(art.width, art.height))
    if scale < 1.0:
        art = art.resize((max(1, int(art.width * scale)), max(1, int(art.height * scale))), Image.LANCZOS)
    art.save(out)


def make_radial(size: int, filename: str, power: float = 2.4) -> None:
    yy, xx = np.mgrid[0:size, 0:size]
    cx = cy = (size - 1) / 2.0
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (size * 0.5)
    a = np.clip(1.0 - r, 0.0, 1.0) ** power
    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(DST / filename)


def make_ring(size: int = 512) -> None:
    yy, xx = np.mgrid[0:size, 0:size]
    cx = cy = (size - 1) / 2.0
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (size * 0.5)
    band = np.exp(-((r - 0.80) / 0.020) ** 2)
    halo = np.exp(-((r - 0.80) / 0.085) ** 2) * 0.38
    a = np.clip(band + halo, 0.0, 1.0)
    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(DST / "ring_soft.png")


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    for fid in IDS:
        p = SRC / f"{fid}.png"
        if not p.exists():
            print("skip missing", p)
            continue
        im = Image.open(p).convert("RGBA")
        make_cutout(im, DST / f"{fid}_cutout.png")
        make_medallion(im, DST / f"{fid}_medallion.png")
        print("ok", fid)
    make_radial(512, "glow_soft.png", 2.4)
    make_radial(64, "dot_soft.png", 3.0)
    make_ring(512)
    print("done ->", DST)


if __name__ == "__main__":
    main()
