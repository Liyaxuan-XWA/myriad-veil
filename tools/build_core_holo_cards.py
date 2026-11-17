"""Build first-pass holo card assets for the three mainland core bosses.

Inputs:
  - transparent character cutouts from vibe_images (cel / boss art)
  - empty core-arena plates from output/core_holo_bg_*.png (see shot_core_holo_bg)

Outputs (assets/ui/codex/holo):
  world_core_<tag>_art.png   640x960 transparent character
  world_core_<tag>_lines.png 640x960 etched line layer
  world_core_<tag>_bg.png    640x960 empty scene plate

Also writes previews + `output/core_holo_contact.png` for art review.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scipy.ndimage import gaussian_filter, label  # noqa: E402

from build_plain_holo_cards import (  # noqa: E402
    ROOT, W, H, FEET_Y, place_on_card, make_lines, grade_art,
)

HOLO = ROOT / "assets" / "ui" / "codex" / "holo"
PLAIN_BG = HOLO / "plain_bg.png"
OUT = ROOT / "output"

CARDS = {
    "lianqi": {
        "art": ROOT / "vibe_images" / "ape_qinglan_sprite_cel_1793197036704_f9b80b68.png",
        "bg": OUT / "core_holo_bg_lianqi.png",
        "accent": (150, 190, 120),
        "max_w": 590,
        "grade": (0.98, 1.0),
        "shadow": 0.30,
    },
    "zhuji": {
        "art": ROOT / "vibe_images" / "cangjiao_cel_v2_1793214583012_097dab94.png",
        "bg": OUT / "core_holo_bg_zhuji.png",
        "accent": (130, 200, 170),
        "max_w": 590,
        "grade": (0.96, 1.0),
        "shadow": 0.30,
    },
    "jiedan": {
        "art": ROOT / "vibe_images" / "qilin_boss_art_1793269592016_72cf4aa7.png",
        "bg": OUT / "core_holo_bg_jiedan.png",
        "accent": (230, 150, 80),
        "max_w": 600,
        "grade": (1.0, 1.0),
        "shadow": 0.26,
    },
    "shihou": {
        # 已拆好的透明立绘；原地保留白色边光，不再二次键底
        "art": ROOT / "assets" / "characters" / "boss" / "shihou.png",
        "bg": ROOT / "vibe_images" / "shihou_card_bg_empty_1793462829560_2931861a.png",
        "bg_trim_bottom": 180,
        "accent": (105, 215, 205),
        "max_w": 600,
        "grade": (1.02, 1.0),
        "shadow": 0.28,
        # 已拆好的透明立绘，不再键底
        "already_keyed": True,
        # 原立绘带一圈奶油色外发光，放到深色卡面上会像贴纸白边；只压卡面层，不动游戏内立绘
        "clean_halo": True,
    },
}


def key_magenta_clean(path: Path) -> Image.Image:
    """洋红底立绘：按「洋红特征」删边缘毛边，再去掉右下角的水印字。"""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0
    key = rgb[4, 4].copy()
    dist = np.sqrt(((rgb - key) ** 2).sum(axis=2))
    alpha = np.clip((dist - 0.05) / 0.18, 0.0, 1.0)
    # 洋红特征像素：不是角色本身的东西（猴子的紫花很小，可接受）
    magenta = ((rgb[..., 0] - rgb[..., 1]) > 0.20) \
        & ((rgb[..., 2] - rgb[..., 1]) > 0.20) \
        & (rgb[..., 0] > 0.40) & (rgb[..., 2] > 0.40)
    alpha[magenta & (dist < 0.55)] = 0.0
    # 去掉右下角灰色水印字（源图的「Codex AI 生成」）
    hh, ww = alpha.shape
    yy, xx = np.mgrid[0:hh, 0:ww]
    low_sat = (rgb.max(axis=2) - rgb.min(axis=2)) < 0.14
    alpha[(yy > hh - 120) & (xx > ww - 360) & low_sat] = 0.0
    # 小碎点清理：小于 120 像素的孤立块一律丢掉
    lab, n = label(alpha > 0.2)
    if n > 0:
        sizes = np.bincount(lab.ravel())
        tiny = np.where(sizes < 120)[0]
        tiny = tiny[tiny > 0]
        if tiny.size:
            alpha[np.isin(lab, tiny)] = 0.0
    alpha = gaussian_filter(alpha, 0.45)
    a3 = alpha[..., None]
    color = np.clip((rgb - (1.0 - a3) * key) / np.maximum(a3, 1e-4), 0.0, 1.0)
    return Image.fromarray(
        (np.dstack([color, alpha]) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def clean_halo(art: Image.Image) -> Image.Image:
    """压掉低 alpha 的浅色外发光，不碰角色本体。"""
    arr = np.asarray(art).astype(np.float32) / 255.0
    rgb, alpha = arr[..., :3], arr[..., 3].copy()
    lum = (rgb * np.array([0.299, 0.587, 0.114], np.float32)).sum(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    halo = (alpha > 0.01) & (alpha < 0.88) & (lum > 0.42) & (sat < 0.30)
    alpha[halo] *= 0.22
    alpha[alpha < 0.04] = 0.0
    return Image.fromarray(
        (np.dstack([rgb, alpha]) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def crop_bg(path: Path, trim_bottom: int = 0) -> Image.Image:
    im = Image.open(path).convert("RGB")
    if trim_bottom > 0:
        im = im.crop((0, 0, im.width, im.height - trim_bottom))
    # 1280x720 → 居中 480x720（2:3）→ 640x960；2:3 原图直接缩放
    side = int(round(im.height * 2 / 3))
    x0 = (im.width - side) // 2
    im = im.crop((x0, 0, x0 + side, im.height)).resize((W, H), Image.LANCZOS)
    return im


def add_contact_shadow(bg: Image.Image, art: Image.Image, feet_y: int, strength: float) -> Image.Image:
    if strength <= 0.0:
        return bg
    alpha = np.asarray(art.getchannel("A"))
    band = alpha[max(0, feet_y - 40):feet_y - 2]
    ys, xs = np.where(band > 32)
    if len(xs) < 40:
        ys, xs = np.where(alpha > 32)
    cx = float(xs.mean())
    spread = float(xs.max() - xs.min() + 1) if len(xs) > 0 else 300.0
    half_w = max(80.0, spread * 0.52)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ell = ((xx - cx) / half_w) ** 2 + ((yy - (feet_y - 4)) / 20.0) ** 2
    mask = np.clip(1.0 - ell, 0.0, 1.0) ** 1.4
    mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(5.0))).astype(np.float32) / 255.0
    arr = np.asarray(bg).astype(np.float32)
    arr *= (1.0 - strength * mask)[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def composite(bg: Image.Image, art: Image.Image, lines: Image.Image) -> Image.Image:
    arr = np.asarray(bg).astype(np.float32)
    a = np.asarray(art).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3]
    base = arr * (1.0 - al[..., None]) + rgb * 255.0 * al[..., None]
    lm = np.asarray(lines).astype(np.float32) / 255.0
    xs = np.linspace(0.0, 1.0, W, dtype=np.float32)[None, :, None]
    spec = 0.52 + 0.48 * np.cos(6.28318 * (xs * 1.4 + np.array([0.0, 0.33, 0.67], dtype=np.float32)))
    return Image.fromarray(
        np.clip(base + spec * lm[..., None] * 2.1 * 255.0, 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    only = set(sys.argv[1:])
    cards = [(tag, cfg) for tag, cfg in CARDS.items() if not only or tag in only]
    sheet = Image.new("RGB", (4 * 340, 2 * 540), (18, 18, 18))
    draw = ImageDraw.Draw(sheet)
    for idx, (tag, cfg) in enumerate(cards):
        # 三张立绘都是洋红底表，先键掉底再进卡面；石犼已经是透明 RGBA
        if cfg.get("already_keyed", False):
            raw = Image.open(cfg["art"]).convert("RGBA")
        else:
            raw = key_magenta_clean(cfg["art"])
        if cfg.get("clean_halo", False):
            raw = clean_halo(raw)
        art = place_on_card(raw, cfg["max_w"])
        art = grade_art(art, *cfg["grade"])
        lines = make_lines(art)
        bg = crop_bg(cfg["bg"], int(cfg.get("bg_trim_bottom", 0)))
        scene = add_contact_shadow(bg, art, FEET_Y, cfg["shadow"])
        art.save(HOLO / f"world_core_{tag}_art.png")
        lines.save(HOLO / f"world_core_{tag}_lines.png")
        bg.save(HOLO / f"world_core_{tag}_bg.png")
        plain = composite(Image.open(PLAIN_BG).convert("RGB"), art, lines)
        scene_img = composite(scene, art, lines)
        plain.save(OUT / f"core_holo_{tag}_plain_preview.png")
        scene_img.save(OUT / f"core_holo_{tag}_scene_preview.png")
        for row, im in enumerate((scene_img, plain)):
            pv = im.resize((330, 495), Image.LANCZOS)
            x = (idx % 4) * 340 + 5
            y = row * 540 + 30
            sheet.paste(pv, (x, y))
            draw.text((x, y - 20), f"{tag} {'scene' if row == 0 else 'plain'}",
                      fill=(235, 235, 235))
        print(f"{tag}: art {art.size}  lines mean {np.asarray(lines).mean():.1f}  "
              f"bg {bg.size}  shadow {cfg['shadow']}")
    sheet.save(OUT / "core_holo_contact.png")


if __name__ == "__main__":
    main()
