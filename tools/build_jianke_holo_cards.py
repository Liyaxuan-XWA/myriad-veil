"""重置剑客华彩卡：把背后的飞剑和人物一起扣进角色层。

输入：ImageGen 从用户提供的剑客卡面抠出的「人物 + 飞剑」透明层。
输出（assets/ui/codex/holo/）：
  boss_01_c_art.png / boss_01_c_lines.png          有背景场景版
  boss_01_c_plain_art.png / boss_01_c_plain_lines.png  纯华彩无背景版
背景 boss_01_c_bg.png 保持现有的云海悬崖（无飞剑），飞剑改由角色层带视差。
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_plain_holo_cards import (  # noqa: E402
    ROOT, W, H, make_lines, grade_art,
)
from build_core_holo_cards import composite  # noqa: E402

HOLO = ROOT / "assets" / "ui" / "codex" / "holo"
OUT = ROOT / "output"
PLAIN_BG = Image.open(HOLO / "plain_bg.png").convert("RGB")
SRC = ROOT / "vibe_images" / "jianke_char_swords_src_1793316519195_e3ee8684.png"


def place_custom(art: Image.Image, max_w: int, max_h: int, feet_y: int,
        center_x: int = W // 2) -> Image.Image:
    alpha = np.asarray(art.getchannel("A"))
    ys, xs = np.where(alpha > 8)
    if len(xs) == 0:
        raise ValueError("empty character alpha")
    crop = art.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    scale = min(max_w / crop.width, max_h / crop.height)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    crop = crop.resize(size, Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.alpha_composite(crop, (round(center_x - size[0] / 2), feet_y - size[1]))
    return canvas


def main() -> None:
    raw = Image.open(SRC).convert("RGBA")
    # 场景版：沿用旧卡脚底 877 / 最大高 690；纯华彩版沿用 893 / 749
    scene_art = place_custom(raw, 600, 690, 877, 320)
    scene_art = grade_art(scene_art, 0.78, 1.0)
    scene_lines = make_lines(scene_art, target_mean=24.0)

    plain_art = place_custom(raw, 600, 749, 893, 320)
    plain_art = grade_art(plain_art, 0.62, 1.05)
    plain_lines = make_lines(plain_art, target_mean=24.0)

    scene_art.save(HOLO / "boss_01_c_art.png")
    scene_lines.save(HOLO / "boss_01_c_lines.png")
    plain_art.save(HOLO / "boss_01_c_plain_art.png")
    plain_lines.save(HOLO / "boss_01_c_plain_lines.png")

    composite(Image.open(HOLO / "boss_01_c_bg.png").convert("RGB"),
              scene_art, scene_lines).resize((330, 495), Image.LANCZOS).save(
        OUT / "jianke_holo_scene_preview2.png")
    composite(PLAIN_BG, plain_art, plain_lines).resize((330, 495), Image.LANCZOS).save(
        OUT / "jianke_holo_plain_preview2.png")
    print("jianke: scene lines mean", f"{np.asarray(scene_lines).mean():.1f}",
          "plain lines mean", f"{np.asarray(plain_lines).mean():.1f}")


if __name__ == "__main__":
    main()
