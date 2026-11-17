"""把三把后加武器的洋红底原片收成透明局内武器图。

仅做背景键出、边沿软化、按 alpha 裁切；不改武器造型。
输出到 assets/effects/weapons/，供 ArtDB.VISUALS 的 weapon_* 条目使用。
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_propagation

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "vibe_images"
DST = ROOT / "assets" / "effects" / "weapons"

RAW_NAMES = {
    "zhuxian_chizhang": "weapon_zhuxian_chizhang_1793391314735_7a08b042.png",
    "panguan_tiebi": "weapon_panguan_tiebi_1793391340458_69364976.png",
    "jiefeng": "weapon_jiefeng_1793391372016_ac21fb29.png",
}


def _fit_background(rgb: np.ndarray) -> np.ndarray:
    h, w, _ = rgb.shape
    yy, xx = np.mgrid[0:h, 0:w]
    border = np.zeros((h, w), bool)
    border[:4] = True
    border[-4:] = True
    border[:, :4] = True
    border[:, -4:] = True
    xs = (xx[border] / max(w - 1, 1) - 0.5).astype(np.float64)
    ys = (yy[border] / max(h - 1, 1) - 0.5).astype(np.float64)
    design = np.stack([np.ones_like(xs), xs, ys, xs * xs, ys * ys, xs * ys], axis=1)
    samples = rgb[border].astype(np.float64)
    coef, *_ = np.linalg.lstsq(design, samples, rcond=None)
    full_x = (xx / max(w - 1, 1) - 0.5).astype(np.float64)
    full_y = (yy / max(h - 1, 1) - 0.5).astype(np.float64)
    full = np.stack([np.ones_like(full_x), full_x, full_y,
        full_x * full_x, full_y * full_y, full_x * full_y], axis=-1)
    return np.einsum("...k,kc->...c", full, coef)


def key_one(raw_name: str, out_name: str) -> None:
    src = RAW / raw_name
    if not src.exists():
        raise SystemExit(f"missing raw: {src}")
    im = Image.open(src).convert("RGB")
    rgb = np.asarray(im, np.float32)
    pred = _fit_background(rgb).astype(np.float32)
    dist = np.linalg.norm(rgb - pred, axis=-1)

    h, w = dist.shape
    border = np.zeros((h, w), bool)
    border[:4] = True
    border[-4:] = True
    border[:, :4] = True
    border[:, -4:] = True
    bg_connected = binary_propagation(border, mask=dist < 78.0)

    alpha = np.full(dist.shape, 255.0, np.float32)
    soft = np.clip((dist - 10.0) / 34.0, 0.0, 1.0)
    alpha[bg_connected] = soft[bg_connected] * 255.0
    # 背景连通区外再清一圈残余洋红（非连通的小块）
    alpha[(dist < 12.0) & ~bg_connected] = 0.0

    rgba = np.dstack([rgb, alpha]).astype(np.uint8)
    out = Image.fromarray(rgba, "RGBA")
    bbox = out.getchannel("A").point(lambda v: 255 if v > 10 else 0).getbbox()
    if bbox is None:
        raise SystemExit(f"empty alpha after key: {raw_name}")
    out = out.crop(bbox)
    pad = 6
    canvas = Image.new("RGBA", (out.width + pad * 2, out.height + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(out, (pad, pad))
    canvas.save(DST / f"{out_name}.png", optimize=True)
    print(f"saved {out_name}.png  {canvas.size}")


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    for out_name, raw_name in RAW_NAMES.items():
        key_one(raw_name, out_name)


if __name__ == "__main__":
    main()
