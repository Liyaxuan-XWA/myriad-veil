"""Scene-layer holo cards for the six bosses that still need the 虎妖 treatment.

Each scene gets an empty background plate resized to 640x960 (1:1 mapping in the
shader), a re-placed character with a milder grade than the legacy HDR standard,
and lines derived from that character at the 虎妖 scene density.

Staging only: writes under output/scene_holo_stage.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_plain_holo_cards import (  # noqa: E402
    ROOT, STAGE as PLAIN_STAGE, key_white_connected, key_white_soft,
    feather_bottom, make_lines, grade_art,
)

VIBE = ROOT / "vibe_images"
HOLO = ROOT / "assets" / "ui" / "codex" / "holo"
STAGE = ROOT / "output" / "scene_holo_stage"
STAGE.mkdir(parents=True, exist_ok=True)
W, H = 640, 960

# max_h / max_w gate the fit; feet_y and center_x position the alpha bbox.
CARDS = {
    "boss_01": {
        "bg": HOLO / "boss_01_bg.png",
        "art": HOLO / "boss_01_art.png",
        "native": True,
        "feet_y": 893,
        "center_x": 320,
        "shadow": 0.20,
    },
    "boss_01_c": {
        "bg": VIBE / "boss_jianke_scene_bg_1793226560213_6ffc5e23.png",
        "src": VIBE / "boss_jianke_plain_art_1793225560372_56c00b51.png",
        "key": "white",
        "grade": (0.78, 1.0),
        "max_h": 690,
        "max_w": 540,
        "feet_y": 877,
        "center_x": 305,
        "shadow": 0.32,
    },
    "boss_02": {
        "bg": VIBE / "boss_liangyi_scene_bg_1793226580397_978b4848.png",
        "src": VIBE / "boss_liangyi_plain_art_1793225729778_0159af3b.png",
        "key": "alpha",
        "grade": (0.95, 1.0),
        "max_h": 742,
        "max_w": 600,
        "feet_y": 898,
        "center_x": 320,
        "shadow": 0.30,
    },
    "boss_02_b": {
        "bg": VIBE / "boss_dingzhen_scene_bg_1793226600320_df1835fc.png",
        "src": VIBE / "boss_dingzhen_plain_art_1793225777029_4954803b.png",
        "key": "white_soft",
        "grade": (1.0, 1.0),
        "max_h": 742,
        "max_w": 600,
        "feet_y": 893,
        "center_x": 320,
        "shadow": 0.30,
    },
    "boss_02_c": {
        "bg": VIBE / "boss_qijun_scene_bg_1793226628231_46123b69.png",
        "src": VIBE / "boss_qijun_plain_art_1793225708205_e844b3be.png",
        "key": "alpha",
        "grade": (0.74, 1.0),
        "max_h": 730,
        "max_w": 600,
        "feet_y": 878,
        "center_x": 320,
        "shadow": 0.0,
        "feather": 90,
        "cloud_from_bg": True,
        "dark_bottom": True,
    },
    "boss_03": {
        "bg": VIBE / "boss_heiliao_scene_bg_1793226649462_9414224d.png",
        "src": VIBE / "boss_heiliao_plain_art_1793225794524_d4ffb967.png",
        "key": "alpha",
        "grade": (0.95, 1.0),
        "max_h": 748,
        "max_w": 600,
        "feet_y": 902,
        "center_x": 320,
        "shadow": 0.0,
    },
}


def load_char(cfg: dict) -> Image.Image:
    if cfg.get("native"):
        art = Image.open(cfg["art"]).convert("RGBA")
        return art if art.size == (W, H) else art.resize((W, H), Image.LANCZOS)
    src = cfg["src"]
    if cfg["key"] == "white_soft":
        im = key_white_soft(src)
    elif cfg["key"] == "white":
        im = key_white_connected(src)
    else:
        im = Image.open(src).convert("RGBA")
    alpha = np.asarray(im.getchannel("A"))
    ys, xs = np.where(alpha > 8)
    crop = im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    scale = min(cfg["max_w"] / crop.width, cfg["max_h"] / crop.height)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    crop = crop.resize(size, Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.alpha_composite(crop, (round(cfg["center_x"] - size[0] / 2), cfg["feet_y"] - size[1]))
    return canvas


def feet_centroid_x(art: Image.Image, feet_y: int) -> tuple[float, float]:
    alpha = np.asarray(art.getchannel("A"))
    band = alpha[max(0, feet_y - 36):feet_y - 2]
    ys, xs = np.where(band > 32)
    if len(xs) < 40:
        ys, xs = np.where(alpha > 32)
    return float(xs.mean()), float(xs.max() - xs.min() + 1)


def add_contact_shadow(bg: Image.Image, art: Image.Image, feet_y: int, strength: float) -> Image.Image:
    if strength <= 0.0:
        return bg
    cx, spread = feet_centroid_x(art, feet_y)
    half_w = max(70.0, spread * 0.62)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ell = ((xx - cx) / half_w) ** 2 + ((yy - (feet_y - 6)) / 22.0) ** 2
    mask = np.clip(1.0 - ell, 0.0, 1.0) ** 1.35
    mask = gaussian_filter(mask, 5.0)
    arr = np.asarray(bg).astype(np.float32)
    arr *= (1.0 - strength * mask)[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def prepare_bg(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGB")
    if im.size != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    return im


def extract_cloud_layer(bg: Image.Image) -> Image.Image:
    """把景片底部那团白云从背景里提出来，作为人物层云脚的延伸。
    它在图生图里本来就是气君云脚的副本，放回人物层才不会只剩半截。
    """
    arr = np.asarray(bg).astype(np.float32) / 255.0
    lum = 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]
    yy = np.arange(H, dtype=np.float32)[:, None] / float(H)
    t = np.clip((yy - 0.43) / 0.17, 0.0, 1.0)
    vert = t * t * (3.0 - 2.0 * t)
    b = np.clip((lum - 0.20) / 0.26, 0.0, 1.0)
    bright = b * b * (3.0 - 2.0 * b)
    mask = gaussian_filter(vert * bright, 3.0)
    return Image.fromarray(
        (np.dstack([arr, mask]) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def add_cloud_extension(art: Image.Image, bg: Image.Image) -> Image.Image:
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(extract_cloud_layer(bg))
    out.alpha_composite(art)
    return out


def dusk_bottom_cloud(bg: Image.Image) -> Image.Image:
    """气君的白色云脚在人物层里，景片底部那团是被图生图带回来的副本。
    压暗、去色并轻微虚化，收成远景云海，避免和人物云脚拼成两层。
    """
    soft = bg.filter(ImageFilter.GaussianBlur(3.0))
    yy = np.arange(H, dtype=np.float32)[:, None] / float(H)
    blur_t = np.clip((yy - 0.46) / 0.26, 0.0, 1.0)
    blur_t = blur_t * blur_t * (3.0 - 2.0 * blur_t)
    blur_mask = Image.fromarray((blur_t * 255.0).repeat(W, axis=1).astype(np.uint8), "L")
    bg = Image.composite(soft, bg, blur_mask)
    arr = np.asarray(bg).astype(np.float32) / 255.0
    lum = 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]
    vert = np.clip((yy - 0.45) / 0.30, 0.0, 1.0)
    vert = vert * vert * (3.0 - 2.0 * vert)
    bright = np.clip((lum - 0.14) / 0.40, 0.0, 1.0)
    mask = (vert * bright)[..., None]
    arr = arr * (1.0 - 0.72 * mask)
    gray = lum[..., None].repeat(3, axis=2)
    arr = arr * (1.0 - 0.35 * mask) + gray * (0.35 * mask)
    return Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGB")


def shader_preview(bg: Image.Image, art: Image.Image, lines: Image.Image) -> Image.Image:
    """Rough CPU twin of the non-legacy branch at view=0, for alignment checks only."""
    arr = np.asarray(art).astype(np.float32) / 255.0
    a = arr[..., 3:4]
    col = np.asarray(bg).astype(np.float32) / 255.0 * (1.0 - a) + arr[..., :3] * a
    lm = np.asarray(lines).astype(np.float32) / 255.0
    aa = arr[..., 3]
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    p_x, p_y = xs / W, ys / H
    phase = p_x * 0.62 + p_y * 0.36
    light = np.power(np.clip(1.0 - np.abs((phase + 0.16) % 1.0 - 0.5) * 2.0, 0, 1), 3.0)
    spec = 0.5 + 0.5 * np.cos(6.28318 * (phase[..., None] * 2.2 + np.array([0.0, 0.33, 0.67], dtype=np.float32)))
    col = col * (1.0 - light[..., None] * 0.30) + (col * spec * 0.55 + spec * 0.045) * light[..., None] * 0.30
    glow = gaussian_filter(lm, 2.0) * aa
    wide = gaussian_filter(lm, 10.0) * aa
    emis = spec * (lm * 0.9 + glow * 0.5 + wide * 0.3)[..., None] * light[..., None] * 0.18 * 1.15
    col += emis
    return Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")


def main() -> None:
    only = set(sys.argv[1:])
    names = [n for n in CARDS if not only or n in only]
    sheet = Image.new("RGB", (3 * 340, 2 * 540), (18, 18, 18))
    draw = ImageDraw.Draw(sheet)
    for idx, name in enumerate(names):
        cfg = CARDS[name]
        bg = prepare_bg(cfg["bg"])
        original_bg = bg
        if cfg.get("dark_bottom"):
            bg = dusk_bottom_cloud(bg)
        art = load_char(cfg)
        if cfg.get("feather"):
            art = feather_bottom(art, int(cfg["feather"]))
        if cfg.get("cloud_from_bg"):
            art = add_cloud_extension(art, original_bg)
        if cfg.get("grade"):
            art = grade_art(art, *cfg["grade"])
        bg = add_contact_shadow(bg, art, cfg["feet_y"], cfg["shadow"])
        lines = make_lines(art, target_mean=24.0)
        art.save(STAGE / f"{name}_scene_art.png")
        bg.save(STAGE / f"{name}_scene_bg.png")
        lines.save(STAGE / f"{name}_scene_lines.png")
        preview = shader_preview(bg, art, lines)
        preview.save(STAGE / f"{name}_scene_preview.png")
        pv = preview.resize((330, 495), Image.LANCZOS)
        x = (idx % 3) * 340 + 5
        y = (idx // 3) * 540 + 30
        sheet.paste(pv, (x, y))
        draw.text((x, y - 20), name, fill=(235, 235, 235))
        print(f"{name}: line mean {np.asarray(lines).mean():.1f} "
              f"shadow {cfg['shadow']} feet {cfg['feet_y']}")
    sheet.save(STAGE / "contact.png")


if __name__ == "__main__":
    main()
