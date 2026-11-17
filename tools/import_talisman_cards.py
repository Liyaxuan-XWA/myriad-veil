#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""符箓卡面导入（2026-11-02）

用户按「火金水木风雷土」顺序提供了 7 张新符箓卡面。这里做统一处理：

  1. 旧卡面先备份（这批 PNG 没进 git，覆盖不可恢复）
  2. 居中裁成正 2:3 → 缩到 640×960 → 存 RGBA PNG
  3. 报告每张「中心区域色彩标准差」，用来确认中心不再是一片空白
     （probe_talismans.gd 里有一条同口径的断言，防止以后又退回空框卡面）

用法：
    python tools/import_talisman_cards.py 图1 图2 图3 图4 图5 图6 图7
    # 顺序固定为 火 金 水 木 风 雷 土
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# 用户给的顺序：火金水木风雷土
ORDER = ["fire", "metal", "water", "wood", "wind", "thunder", "earth"]
OUT_DIR = Path("assets/ui/talisman/cards")
BACKUP_DIR = Path("tools/talisman_card_src/cards_before_2026-11-02")
TARGET = (640, 960)


def center_std(img: Image.Image) -> float:
    """中心区域（横向 40%、纵向 34%~66%）的颜色标准差：空白纸面会很低。"""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    crop = a[int(h * .34):int(h * .66), int(w * .30):int(w * .70)]
    return float(crop.reshape(-1, 3).std())


def normalize(src: Path) -> Image.Image:
    im = Image.open(src).convert("RGB")
    want = TARGET[0] / TARGET[1]
    w, h = im.size
    if w / h > want:                      # 太宽 → 左右裁
        nw = int(round(h * want))
        x0 = (w - nw) // 2
        im = im.crop((x0, 0, x0 + nw, h))
    elif w / h < want:                    # 太高 → 上下裁（保住底部名称条带）
        nh = int(round(w / want))
        y0 = max(0, h - nh)
        im = im.crop((0, y0, w, y0 + nh))
    return im.resize(TARGET, Image.LANCZOS).convert("RGBA")


def main(argv: list[str]) -> int:
    if len(argv) < len(ORDER):
        print(f"需要 {len(ORDER)} 张图（顺序：火 金 水 木 风 雷 土）")
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("talisman_card_*.png"):
        dst = BACKUP_DIR / old.name
        if not dst.exists():
            shutil.copy2(old, dst)
    print(f"旧卡面备份在 {BACKUP_DIR}")
    for elem, src in zip(ORDER, argv):
        img = normalize(Path(src))
        path = OUT_DIR / f"talisman_card_{elem}.png"
        img.save(path)
        print(f"  · {elem:8s} ← {Path(src).name[:24]:24s} {img.size}  中心σ={center_std(img):.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
