#!/usr/bin/env python3
"""接缝地面过渡条预处理（2026-10-29）。

源图：vibe_images 里用 zhuji_forestfloor.png + lianqi_grass.png 做参考图生图的
「谷地暗林地 -> 草原」横向过渡。本脚本负责：
  1. 缩放到 1664x735（period 1536 + overlap 128）；
  2. 按两区 tile 的均值做逐行色阶对齐，让上/下边缘颜色接得上；
  3. 上下 alpha 羽化；
  4. 输出 work 图，并打印 background-tile 无缝化命令。

横向无缝由本地 sprite-gen（零凭据）完成：
  cd E:/skill/game/sprite-gen-main/sprite-gen-main
  python -m sprite_gen.cli background-tile --source <work> --out \
    assets/scenes/tiles/seam_transition.png --period 1536 --axis x --overlap 128 \
    --report output/seam_transition.report.json

用法：
  python tools/prep_seam_transition.py <raw.png>
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW_DEFAULT = ROOT / "vibe_images" / "seam_transition_v1_1793208573587_f852f271.png"
WORK = ROOT / "vibe_images" / "seam_transition_work.png"
NORTH = ROOT / "assets" / "scenes" / "tiles" / "zhuji_forestfloor.png"
SOUTH = ROOT / "assets" / "scenes" / "tiles" / "lianqi_grass.png"


def _mean(path: Path) -> np.ndarray:
    arr = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    return arr.mean(axis=(0, 1))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw", nargs="?", default=str(RAW_DEFAULT))
    ap.add_argument("--out-work", default=str(WORK))
    args = ap.parse_args()

    src = Image.open(args.raw).convert("RGB")
    # period 1536 + overlap 128; 世界深度 420px @ 1.75 texel/px
    img = src.resize((1664, 735), Image.LANCZOS)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    h = arr.shape[0]
    k = max(1, int(h * 0.15))
    ref_top = _mean(NORTH)
    ref_bot = _mean(SOUTH)
    y = np.linspace(0.0, 1.0, h)[:, None, None]
    t = y * y * (3.0 - 2.0 * y)

    for _ in range(2):
        cur_top = arr[:k].mean(axis=(0, 1))
        cur_bot = arr[-k:].mean(axis=(0, 1))
        gain_top = ref_top / np.maximum(cur_top, 1e-4)
        gain_bot = ref_bot / np.maximum(cur_bot, 1e-4)
        gain = gain_top[None, None, :] * (1.0 - t) + gain_bot[None, None, :] * t
        arr = np.clip(arr * gain, 0.0, 1.0)

    alpha = np.ones((h, arr.shape[1]), dtype=np.float32)
    top_fade = 88
    bottom_fade = 102
    ramp = np.linspace(0.0, 1.0, top_fade, dtype=np.float32)
    ramp = ramp * ramp * (3.0 - 2.0 * ramp)
    alpha[:top_fade, :] = ramp[:, None]
    ramp = np.linspace(1.0, 0.0, bottom_fade, dtype=np.float32)
    ramp = ramp * ramp * (3.0 - 2.0 * ramp)
    alpha[h - bottom_fade:, :] = ramp[:, None]

    out = np.dstack([arr, alpha])
    work = Path(args.out_work)
    work.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((out * 255.0).round().astype(np.uint8), "RGBA").save(work)
    print("work:", work)
    print("top mean:", arr[:k].mean(axis=(0, 1)).round(3),
          "bottom mean:", arr[-k:].mean(axis=(0, 1)).round(3))
    print("next: background-tile --source", work, "--out",
          ROOT / "assets" / "scenes" / "tiles" / "seam_transition.png",
          "--period 1536 --axis x --overlap 128")
    return 0


if __name__ == "__main__":
    sys.exit(main())
