"""赤霄界三 BOSS 碰撞/受击框与立绘轮廓对照（2026-10-29）。

读 .tscn 里的 CollisionShape2D（圆 / 胶囊）+ rig 的 body（赫连霄额外把 arm_pen 算进
可见手臂），在 1 世界像素网格上算覆盖率 / 误覆盖 / IoU，并输出叠加图到 output/。

用法：python tools/check_plane3_hitboxes.py
"""
from __future__ import annotations

import math
import os
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
W, H = 240, 220
OX, OY = 120, 110  # 世界坐标 x / y 零点

BOSSES = [
    {
        "name": "heiliao", "label": "赫连霄",
        "scene": "scenes/boss/domain_boss_03.tscn",
        "rig": "assets/characters/boss/heiliao_rig/rig.tres",
        "parts": ["body", "arm_pen"],
    },
    {
        "name": "lizhao", "label": "离照",
        "scene": "scenes/boss/domain_boss_03_b.tscn",
        "rig": "assets/characters/boss/lizhao_rig/rig.tres",
        "parts": ["body"],
    },
    {
        "name": "wujiu", "label": "晏无咎",
        "scene": "scenes/boss/domain_boss_03_c.tscn",
        "rig": "assets/characters/boss/wujiu_rig/rig.tres",
        "parts": ["body", "hand_cast"],
    },
]


def parse_rig(rig_path: str) -> dict:
    text = (ROOT / rig_path).read_text(encoding="utf-8")
    order = re.findall(r'"([^"]*)"', re.search(r'order = PackedStringArray\((.*?)\)', text, re.S).group(1))
    joint = [float(x) for x in re.findall(r'-?\d+\.?\d*', re.search(r'part_joint = PackedVector2Array\((.*?)\)', text, re.S).group(1))]
    off = [float(x) for x in re.findall(r'-?\d+\.?\d*', re.search(r'part_offset = PackedVector2Array\((.*?)\)', text, re.S).group(1))]
    texs = re.findall(r'"([^"]*)"', re.search(r'part_tex = PackedStringArray\((.*?)\)', text, re.S).group(1))
    parts = {}
    for i, name in enumerate(order):
        parts[name] = {
            "img": Image.open(ROOT / texs[i].replace("res://", "")).convert("RGBA"),
            "joint": (joint[2 * i], joint[2 * i + 1]),
            "offset": (off[2 * i], off[2 * i + 1]),
        }
    return parts


def compose_mask(parts: dict, names: list[str]) -> np.ndarray:
    mask = np.zeros((H, W), dtype=bool)
    for name in names:
        part = parts[name]
        img = part["img"]
        j, o = part["joint"], part["offset"]
        a = np.array(img)[:, :, 3]
        ys, xs = np.where(a > 20)
        for y, x in zip(ys, xs):
            wx = (j[0] + o[0] + x - img.width / 2) * 0.25
            wy = (j[1] + o[1] + y - img.height / 2) * 0.25 + 5.0
            px, py = int(round(OX + wx)), int(round(OY + wy))
            if 0 <= px < W and 0 <= py < H:
                mask[py, px] = True
    return mask


def parse_scene_shapes(scene_path: str) -> list[dict]:
    text = (ROOT / scene_path).read_text(encoding="utf-8")
    sub: dict[str, dict] = {}
    for m in re.finditer(r'\[sub_resource type="(CircleShape2D|CapsuleShape2D)" id="([^"]+)"\](.*?)(?=\n\[|\Z)', text, re.S):
        kind, sid, body = m.group(1), m.group(2), m.group(3)
        radius = float(re.search(r'radius\s*=\s*([\d.]+)', body).group(1))
        height = float(re.search(r'height\s*=\s*([\d.]+)', body).group(1)) if kind == "CapsuleShape2D" else 0.0
        sub[sid] = {"kind": kind, "radius": radius, "height": height}
    shapes = []
    for m in re.finditer(r'\[node name="([^"]+)" type="CollisionShape2D" parent="\."\](.*?)(?=\n\[node|\Z)', text, re.S):
        node, body = m.group(1), m.group(2)
        sm = re.search(r'shape = SubResource\("([^"]+)"\)', body)
        if not sm:
            continue
        info = sub[sm.group(1)]
        posm = re.search(r'position = Vector2\(([-\d.]+), ([-\d.]+)\)', body)
        rotm = re.search(r'rotation = ([\d.-]+)', body)
        pos = (float(posm.group(1)), float(posm.group(2))) if posm else (0.0, 0.0)
        rot = float(rotm.group(1)) if rotm else 0.0
        shapes.append({"name": node, "pos": pos, "rot": rot, **info})
    return shapes


def shape_circles(shape: dict) -> list[tuple[float, float, float]]:
    x, y = shape["pos"]
    r = shape["radius"]
    if shape["kind"] == "CircleShape2D":
        return [(x, y, r)]
    seg = max(0.0, shape["height"] * 0.5 - r)
    steps = max(1, math.ceil(seg * 2.0 / max(r * 0.6, 1.0)))
    c, s = math.cos(shape["rot"]), math.sin(shape["rot"])
    out = []
    for i in range(steps + 1):
        t = -seg + seg * 2.0 * i / steps
        out.append((x - s * t, y + c * t, r))
    return out


def evaluate(mask: np.ndarray, shapes: list[dict]) -> tuple[float, int, float, np.ndarray]:
    yy, xx = np.ogrid[:H, :W]
    cov = np.zeros((H, W), dtype=bool)
    for sh in shapes:
        for sx, sy, r in shape_circles(sh):
            cov |= (xx - (OX + sx)) ** 2 + (yy - (OY + sy)) ** 2 <= r * r
    inter = int((mask & cov).sum())
    total = int(mask.sum())
    false = int((cov & ~mask).sum())
    union = int((mask | cov).sum())
    return inter / total * 100.0, false, inter / union * 100.0, cov


def draw(mask: np.ndarray, shapes: list[dict], path: Path) -> None:
    base = Image.new("RGBA", (W, H), (20, 20, 25, 255))
    tint = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    p = tint.load()
    for y in range(H):
        for x in range(W):
            if mask[y, x]:
                p[x, y] = (220, 210, 190, 170)
    base.alpha_composite(tint)
    d = ImageDraw.Draw(base)
    for sh in shapes:
        for sx, sy, r in shape_circles(sh):
            d.ellipse([OX + sx - r, OY + sy - r, OX + sx + r, OY + sy + r],
                      outline=(255, 80, 80, 220), width=2)
    d.line([OX, 0, OX, H], fill=(80, 160, 255, 180), width=1)
    d.line([0, OY, W, OY], fill=(80, 160, 255, 180), width=1)
    base.resize((W * 3, H * 3), Image.LANCZOS).save(path)


def main() -> None:
    out_dir = ROOT / "output"
    out_dir.mkdir(exist_ok=True)
    for cfg in BOSSES:
        parts = parse_rig(cfg["rig"])
        mask = compose_mask(parts, cfg["parts"])
        shapes = parse_scene_shapes(cfg["scene"])
        coverage, false, iou, _ = evaluate(mask, shapes)
        print(f'{cfg["label"]}: shapes={len(shapes)} coverage={coverage:.1f}% '
              f'false={false} IoU={iou:.1f}%')
        draw(mask, shapes, out_dir / f'hitbox_{cfg["name"]}_final.png')


if __name__ == "__main__":
    main()
