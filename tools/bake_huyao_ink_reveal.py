"""烘虎妖纸本水墨的落墨顺序图。

种子按「眼/口 → 虎身主笔 → 尾梢/岩台」排先后；
输出灰度顺序图给 ink_paper.gdshader，外加几张 reveal 预览。
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "ui" / "codex" / "holo" / "boss_huyao_ink.png"
OUT = ROOT / "assets" / "ui" / "codex" / "holo" / "boss_huyao_ink_reveal.png"
PREVIEW_DIR = ROOT / "output"

# x/y 为 640×960 归一化坐标；第三项是先后偏移（小=先出现）
SEEDS = [
    (0.800, 0.437, 0.000),  # 左眼
    (0.855, 0.435, 0.010),  # 右眼
    (0.840, 0.500, 0.035),  # 牙口
    (0.620, 0.450, 0.060),  # 颈侧主笔
    (0.500, 0.550, 0.070),  # 虎身中段
    (0.360, 0.490, 0.085),  # 背脊中段
    (0.180, 0.310, 0.095),  # 尾梢
    (0.200, 0.760, 0.135),  # 岩台左
    (0.520, 0.770, 0.145),  # 岩台中
    (0.840, 0.750, 0.155),  # 岩台右
]


def _preview(base, paper, field, value):
    shown = np.clip((value - field + 0.06) / 0.12, 0.0, 1.0)
    shown = shown * shown * (3.0 - 2.0 * shown)
    ink = np.clip(1.0 - base @ np.array([0.299, 0.587, 0.114], np.float32), 0.0, 1.0)
    col = paper[None, None, :] * (1.0 - shown[..., None]) + base * shown[..., None]
    front = np.exp(-((field - value) / 0.03) ** 2)
    col *= 1.0 - front[..., None] * 0.16 * ink[..., None]
    return Image.fromarray(np.clip(col * 255.0, 0.0, 255.0).astype(np.uint8))


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    yy, xx = np.mgrid[0:h, 0:w]
    x = xx / float(w)
    y = yy / float(h)
    field = np.full((h, w), 9.0, np.float32)
    for sx, sy, offset in SEEDS:
        d = np.sqrt((x - sx) ** 2 + (y - sy) ** 2)
        field = np.minimum(field, d + offset)
    rng = np.random.default_rng(20261030)
    noise = gaussian_filter(rng.normal(size=(h, w)).astype(np.float32), 70.0)
    noise = (noise - noise.min()) / (noise.max() - noise.min() + 1e-6)
    field = gaussian_filter(field + (noise - 0.5) * 0.16, 5.0)
    field = (field - field.min()) / (field.max() - field.min() + 1e-6)
    Image.fromarray((field * 255.0 + 0.5).astype(np.uint8), "L").save(OUT, optimize=True)

    base = np.asarray(im, np.float32) / 255.0
    paper = np.array([0.93, 0.91, 0.86], np.float32)
    for value in (0.30, 0.65, 1.0):
        _preview(base, paper, field, value).save(
            PREVIEW_DIR / f"huyao_ink_v4_reveal_{int(value * 100):03d}.png")
    print("saved", OUT.relative_to(ROOT))
    print("field range", float(field.min()), float(field.max()))


if __name__ == "__main__":
    main()
