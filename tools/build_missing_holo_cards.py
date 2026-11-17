"""补齐离照 / 晏无咎的华彩卡（有背景 + 无背景纯华彩）。

复用已有卡包管线：
  - 角色层：assets/characters/boss/boss_lizhao.png / boss_wujiu.png（透明立绘）
  - 背景层：ImageGen 按原卡面重绘的无人物竖图
  - 线条层：build_plain_holo_cards.make_lines（虎妖标准，mean~24）
  - 接触影 / 合成预览：build_core_holo_cards 的同口径函数

输出到 assets/ui/codex/holo/：
  boss_03_b_art.png / boss_03_b_lines.png / boss_03_b_bg.png
  boss_03_c_art.png / boss_03_c_lines.png / boss_03_c_bg.png
普通卡 / 纯华彩共用同一套 art + lines（和三位大陆首领一致）。
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, gaussian_filter, label

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_plain_holo_cards import (  # noqa: E402
    ROOT, W, H, FEET_Y, make_lines, grade_art, place_on_card,
)
from build_core_holo_cards import add_contact_shadow, composite  # noqa: E402

HOLO = ROOT / "assets" / "ui" / "codex" / "holo"
OUT = ROOT / "output"
PLAIN_BG = Image.open(HOLO / "plain_bg.png").convert("RGB")

CARDS = {
    "boss_03_b": {
        "art": ROOT / "assets" / "characters" / "boss" / "boss_lizhao.png",
        "bg": ROOT / "vibe_images" / "lizhao_holo_bg_raw_1793315351652_6b01a12f.png",
        "grade": (0.98, 1.0),
        "max_w": 600,
        "shadow": 0.30,
        "label": "离照",
    },
    "boss_03_c": {
        "art": ROOT / "assets" / "characters" / "boss" / "boss_wujiu.png",
        # 背景保留烟雾 / 余烬 / 地面，三灾环移到角色层，跟着人物一起视差
        "bg": ROOT / "vibe_images" / "wujiu_holo_bg_norings_raw_1793315737585_35349509.png",
        "rings_src": ROOT / "vibe_images" / "wujiu_holo_bg_raw_1793315375036_a05c2b61.png",
        "grade": (0.84, 1.02),
        "max_w": 590,
        "shadow": 0.26,
        "label": "晏无咎",
    },
}


def extract_rings(cur_path: Path, no_path: Path) -> Image.Image:
    """从「有环」和「无环」两张同构图里抠出三灾环，连同环周薄雾一起带进角色层。"""
    cur = Image.open(cur_path).convert("RGB")
    no = Image.open(no_path).convert("RGB")
    if no.size != cur.size:
        no = no.resize(cur.size, Image.LANCZOS)
    a = np.asarray(cur).astype(np.float32)
    b = np.asarray(no).astype(np.float32)
    diff = np.sqrt(((a - b) ** 2).sum(axis=2))
    sat = np.asarray(cur.convert("HSV")).astype(np.float32)[..., 1]
    mask = (diff > 45.0) & (sat > 35.0)
    big = binary_dilation(mask, iterations=3)
    lab, n = label(big)
    keep = np.zeros_like(mask)
    if n:
        sizes = np.bincount(lab.ravel())
        for i in range(1, n + 1):
            if sizes[i] >= 4000:
                keep |= (lab == i) & mask
    core = keep.astype(np.float32)
    alpha = np.clip(core * 0.95 + gaussian_filter(core, 5.0) * 0.8, 0.0, 1.0)
    rgba = np.dstack([a / 255.0, alpha])
    out = Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), "RGBA")
    out.save(OUT / "wujiu_rings_only.png")
    return out


def prepare_bg(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGB")
    if im.size != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    return im


def main() -> None:
    for name, cfg in CARDS.items():
        raw = Image.open(cfg["art"]).convert("RGBA")
        art = place_on_card(raw, int(cfg["max_w"]))
        art = grade_art(art, *cfg["grade"])
        if cfg.get("rings_src"):
            rings = extract_rings(cfg["rings_src"], cfg["bg"]).resize((W, H), Image.LANCZOS)
            combined = rings.copy()
            combined.alpha_composite(art)
            art = combined
        lines = make_lines(art, target_mean=24.0)
        bg = prepare_bg(cfg["bg"])
        scene_bg = add_contact_shadow(bg, art, FEET_Y, float(cfg["shadow"]))

        art.save(HOLO / f"{name}_art.png")
        lines.save(HOLO / f"{name}_lines.png")
        bg.save(HOLO / f"{name}_bg.png")

        composite(scene_bg, art, lines).resize((330, 495), Image.LANCZOS).save(
            OUT / f"{name}_scene_preview.png")
        composite(PLAIN_BG, art, lines).resize((330, 495), Image.LANCZOS).save(
            OUT / f"{name}_plain_preview.png")
        print(f"{cfg['label']}: {name} art {art.size} lines mean {np.asarray(lines).mean():.1f} "
              f"bg {bg.size} shadow {cfg['shadow']}")


if __name__ == "__main__":
    main()
