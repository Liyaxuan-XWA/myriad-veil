"""Batch the approved no-background holo standard for all tower bosses.

Character sources are the existing transparent boss art or ImageGen cutouts.
Lines are derived from alpha + luminance edges and tuned to the 虎妖 standard's
mean coverage (~21/255) with a 20% 1px dilation.

Staging only: writes art/lines/previews under output/plain_holo_stage.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import (
    binary_dilation, binary_erosion, distance_transform_edt, gaussian_filter,
    label, maximum_filter, sobel,
)

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "output" / "plain_holo_stage"
STAGE.mkdir(parents=True, exist_ok=True)
W, H = 640, 960
MAX_W, MAX_H, FEET_Y = 600, 749, 893
CARD_BG = ROOT / "assets" / "ui" / "codex" / "holo" / "plain_bg.png"

VIBE = ROOT / "vibe_images"
SOURCES = {
    "boss_01": (ROOT / "assets" / "ui" / "codex" / "holo" / "boss_01_art.png", "alpha"),
    "boss_jianke": (VIBE / "boss_jianke_plain_art_1793225560372_56c00b51.png", "white"),
    "boss_liangyi": (VIBE / "boss_liangyi_plain_art_1793225729778_0159af3b.png", "alpha"),
    "boss_dingzhen": (VIBE / "boss_dingzhen_plain_art_1793225777029_4954803b.png", "white_soft"),
    "boss_qijun": (VIBE / "boss_qijun_plain_art_1793225708205_e844b3be.png", "alpha"),
    "boss_heiliao": (VIBE / "boss_heiliao_plain_art_1793225794524_d4ffb967.png", "alpha"),
}
MAX_WIDTH = {"boss_heiliao": 620, "boss_daoke": 640}
# 气君的云脚在场景层里已经并回人物，直接复用场景角色；先反解场景调色，
# 再走标准版自己的 0.52/1.05 分级，避免压两遍。
SCENE_REUSE = {
    "boss_qijun": (ROOT / "assets" / "ui" / "codex" / "holo" / "boss_02_c_art.png", 0.74, 1.0),
}
# Light-robed characters need a darker base under the legacy HDR glow, otherwise
# the white robe clips and swallows the etched lines. Gain, then gamma.
GRADE = {
    "boss_jianke": (0.62, 1.05),
    "boss_qijun": (0.52, 1.05),
    "boss_liangyi": (0.88, 1.0),
    "boss_dingzhen": (0.95, 1.0),
    "boss_heiliao": (0.95, 1.0),
    "boss_01": (1.0, 1.0),
}


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / max(b - a, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def key_magenta(path: Path) -> Image.Image:
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0
    key = rgb[4, 4].copy()
    dist = np.sqrt(((rgb - key) ** 2).sum(axis=2))
    alpha = np.clip((dist - 0.035) / 0.115, 0.0, 1.0)
    a3 = alpha[..., None]
    color = np.clip((rgb - (1.0 - a3) * key) / np.maximum(a3, 1e-4), 0.0, 1.0)
    return Image.fromarray((np.dstack([color, alpha]) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def key_white_connected(path: Path) -> Image.Image:
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0
    key = rgb[4, 4].copy()
    dist = np.sqrt(((rgb - key) ** 2).sum(axis=2))
    near = dist < 0.06
    lab, _ = label(near)
    border = np.unique(np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))
    bg = np.isin(lab, border[border > 0])
    alpha = (~bg).astype(np.float32)
    alpha = gaussian_filter(alpha, 0.65)
    a3 = alpha[..., None]
    color = np.clip((rgb - (1.0 - a3) * key) / np.maximum(a3, 1e-4), 0.0, 1.0)
    return Image.fromarray((np.dstack([color, alpha]) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def key_white_soft(path: Path) -> Image.Image:
    """White backdrop key for wispy hair: enclosed white pockets are background,
    a wide edge band estimates partial alpha, and 1px erosion drops the light rim.
    """
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0
    key = rgb[4, 4].copy()
    dist = np.sqrt(((rgb - key) ** 2).sum(axis=2))
    near = dist < 0.05
    band = binary_dilation(near, iterations=10) & ~near
    alpha = np.ones_like(dist)
    alpha[near] = 0.0
    alpha[band] = np.clip((dist[band] - 0.02) / 0.30, 0.0, 1.0)
    core = binary_erosion(alpha > 0.5, iterations=1)
    alpha = np.where(core, 1.0, alpha * 0.35)
    alpha = gaussian_filter(alpha, 0.6)
    lab, n = label(alpha > 0.25)
    if n > 0:
        sizes = np.bincount(lab.ravel())
        tiny = np.where(sizes < 20)[0]
        tiny = tiny[tiny > 0]
        if tiny.size:
            alpha[np.isin(lab, tiny)] = 0.0
    # Light, pencil-thin strands read as white scribble on the dark card; keep
    # the thick locks and saturated ribbons, drop the wispy light hairs.
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    thick = distance_transform_edt(alpha > 0.4)
    thin = np.clip((2.6 - thick) / 2.0, 0.0, 1.0)
    light = np.clip((lum - 0.40) / 0.22, 0.0, 1.0)
    alpha *= 1.0 - 0.90 * thin * light
    alpha = gaussian_filter(alpha, 0.4)
    a3 = alpha[..., None]
    color = np.clip((rgb - (1.0 - a3) * key) / np.maximum(a3, 1e-4), 0.0, 1.0)
    return Image.fromarray((np.dstack([color, alpha]) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def feather_bottom(art: Image.Image, px: int) -> Image.Image:
    """Dissolve the last `px` rows so a cloud hem doesn't end on a hard alpha step."""
    arr = np.asarray(art).astype(np.float32) / 255.0
    alpha = arr[..., 3]
    rows = np.where(alpha.max(axis=1) > 0.03)[0]
    if len(rows) == 0:
        return art
    bottom = int(rows.max())
    if bottom - px < 0:
        px = max(1, bottom)
    start = bottom - px
    t = np.clip((np.arange(H, dtype=np.float32) - start) / float(px), 0.0, 1.0)
    ramp = 1.0 - t * t * (3.0 - 2.0 * t)
    arr[..., 3] = alpha * ramp[:, None]
    return Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def place_on_card(art: Image.Image, max_w: int = MAX_W) -> Image.Image:
    alpha = np.asarray(art.getchannel("A"))
    ys, xs = np.where(alpha > 8)
    if len(xs) == 0:
        raise ValueError("empty character alpha")
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    crop = art.crop((x0, y0, x1, y1))
    scale = min(max_w / crop.width, MAX_H / crop.height)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    crop = crop.resize(size, Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.alpha_composite(crop, (round(W / 2 - size[0] / 2), FEET_Y - size[1]))
    return canvas


def make_lines(art: Image.Image, target_mean: float = 21.0) -> Image.Image:
    arr = np.asarray(art).astype(np.float32) / 255.0
    rgb, al = arr[..., :3], arr[..., 3]
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]

    def edge(field: np.ndarray) -> np.ndarray:
        return np.hypot(sobel(field, 0), sobel(field, 1))

    fine = edge(gaussian_filter(lum, 0.65))
    broad = edge(gaussian_filter(lum, 1.7))
    high = np.abs(lum - gaussian_filter(lum, 2.6))
    sil = edge(al)
    e = np.maximum.reduce([fine, broad * 0.65, high * 0.9, sil * 1.4])
    e *= smoothstep(0.06, 0.28, al)
    valid = e[al > 0.2]
    if valid.size == 0:
        return Image.new("L", (W, H), 0)

    best_m = None
    best_err = 1e9
    for pct in np.arange(60.0, 93.0, 1.0):
        p = float(np.percentile(valid, pct))
        m = smoothstep(p * 0.45, p * 1.25, e) * al
        m = 0.8 * m + 0.2 * maximum_filter(m, size=3)
        m *= smoothstep(0.03, 0.2, al)
        err = abs(float(m.mean() * 255.0) - target_mean)
        if err < best_err:
            best_err, best_m = err, m
    out = (np.clip(best_m, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(out, "L")


def grade_art(art: Image.Image, gain: float, gamma: float) -> Image.Image:
    arr = np.asarray(art).astype(np.float32) / 255.0
    rgb = np.clip((arr[..., :3] ** gamma) * gain, 0.0, 1.0)
    return Image.fromarray((np.dstack([rgb, arr[..., 3]]) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def main() -> None:
    only = set(sys.argv[1:])
    sheet = Image.new("RGB", (3 * 340, 2 * 540), (20, 20, 20))
    draw = ImageDraw.Draw(sheet)
    for idx, (name, (src, mode)) in enumerate(SOURCES.items()):
        if only and name not in only:
            continue
        if name in SCENE_REUSE:
            path, scene_gain, scene_gamma = SCENE_REUSE[name]
            arr = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0
            raw = np.clip((arr[..., :3] ** (1.0 / scene_gamma)) / scene_gain, 0.0, 1.0)
            im = Image.fromarray(
                (np.dstack([raw, arr[..., 3]]) * 255.0 + 0.5).astype(np.uint8), "RGBA")
        elif mode == "magenta":
            im = key_magenta(src)
        elif mode == "white_soft":
            im = key_white_soft(src)
        elif mode == "white":
            im = key_white_connected(src)
        else:
            im = Image.open(src).convert("RGBA")
        if name in SCENE_REUSE:
            pass
        elif name != "boss_01":
            im = place_on_card(im, MAX_WIDTH.get(name, MAX_W))
        elif im.size != (W, H):
            im = im.resize((W, H), Image.LANCZOS)
        if name == "boss_qijun" and name not in SCENE_REUSE:
            im = feather_bottom(im, 90)
        lines = make_lines(im)
        gain, gamma = GRADE.get(name, (1.0, 1.0))
        art_out = grade_art(im, gain, gamma)
        art_out.save(STAGE / f"{name}_art.png")
        lines.save(STAGE / f"{name}_lines.png")
        arr = np.asarray(lines)
        print(f"{name}: art alpha>128 {(np.asarray(art_out.getchannel('A'))>128).mean()*100:.1f}%  "
              f"grade {gain}/{gamma}  line mean {arr.mean():.1f}  nonzero {(arr>0).mean()*100:.1f}%")
        # Lightweight preview only: line coverage over the dark base, not the game shader.
        bg = Image.open(CARD_BG).convert("RGB")
        a3 = np.asarray(art_out.getchannel("A")).astype(np.float32)[..., None] / 255.0
        base = np.asarray(bg).astype(np.float32) * (1 - a3) + np.asarray(art_out.convert("RGB")).astype(np.float32) * a3
        lm = arr.astype(np.float32)[..., None] / 255.0
        xs = np.linspace(0.0, 1.0, W, dtype=np.float32)[None, :, None]
        spec = 0.52 + 0.48 * np.cos(6.28318 * (xs * 1.4 + np.array([0.0, 0.33, 0.67], dtype=np.float32)))
        out = np.clip(base + spec * lm * 2.2 * 255.0, 0, 255).astype(np.uint8)
        Image.fromarray(out, "RGB").save(STAGE / f"{name}_preview.png")
        pv = Image.fromarray(out).resize((330, 495), Image.LANCZOS)
        x = (idx % 3) * 340 + 5
        y = (idx // 3) * 540 + 30
        sheet.paste(pv, (x, y))
        draw.text((x, y - 20), name, fill=(235, 235, 235))
    sheet.save(STAGE / "contact.png")


if __name__ == "__main__":
    main()
