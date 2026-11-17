"""赫连霄碰撞框拟合（2026-10-30）。

按**实际渲染的 idle 剪影**（output/heiliao_silhouette.png，1:1、原点在屏幕中心）
评估圆/胶囊覆盖率与误覆盖，并出叠加图。改 CANDIDATES 后重跑即可迭代。

用法：python tools/fit_heiliao_hitbox.py
"""
from __future__ import annotations

import math
import numpy as np
from PIL import Image, ImageDraw

SIL = "output/heiliao_silhouette.png"
SCENE = "scenes/boss/domain_boss_03.tscn"
CX, CY = 640, 360          # 剪影里 BOSS 原点所在的屏幕坐标
W, H = 300, 260            # 输出画布（世界像素）
OX, OY = 120, 120          # 世界原点到画布的位置

# (x, y, r) 圆；("cap", x, y, r, height_px, rot) 胶囊（rot 为弧度，数学正方向）
CANDIDATES = [
    (-33, -15, 28),        # 胸 / 躯干
    (-33, 42, 28),         # 袍身
    (-60, -15, 26),        # 鼓 + 左肩
    (-60, 45, 24),         # 左披风
    (-12, 57, 24),         # 下摆（右）
    (-18, 9, 28),          # 腰腹
    (-30, -51, 10),        # 头冠尖
    (-39, 78, 10),         # 下摆最下
    (-48, 18, 14),         # 左腰
    ("cap", 26, 24, 6, 42.0, -0.72),  # 铁笔（斜向右下）
]


def shapes_from_scene() -> list:
    import re
    from pathlib import Path
    text = Path(SCENE).read_text(encoding="utf-8")
    sub: dict[str, dict] = {}
    for m in re.finditer(
            r'\[sub_resource type="(CircleShape2D|CapsuleShape2D)" id="([^"]+)"\](.*?)(?=\n\[|\Z)',
            text, re.S):
        kind, sid, body = m.group(1), m.group(2), m.group(3)
        radius = float(re.search(r'radius\s*=\s*([\d.]+)', body).group(1))
        height = float(re.search(r'height\s*=\s*([\d.]+)', body).group(1))             if kind == "CapsuleShape2D" else 0.0
        sub[sid] = {"kind": kind, "radius": radius, "height": height}
    out = []
    for m in re.finditer(
            r'\[node name="([^"]+)" type="CollisionShape2D" parent="\."\](.*?)(?=\n\[node|\Z)',
            text, re.S):
        body = m.group(2)
        sm = re.search(r'shape = SubResource\("([^"]+)"\)', body)
        if not sm:
            continue
        info = sub[sm.group(1)]
        posm = re.search(r'position = Vector2\(([-\d.]+), ([-\d.]+)\)', body)
        rotm = re.search(r'rotation = ([-\d.]+)', body)
        x, y = (float(posm.group(1)), float(posm.group(2))) if posm else (0.0, 0.0)
        rot = float(rotm.group(1)) if rotm else 0.0
        if info["kind"] == "CircleShape2D":
            out.append((x, y, info["radius"]))
        else:
            out.append(("cap", x, y, info["radius"], info["height"], rot))
    return out


def load_mask() -> np.ndarray:
    from scipy import ndimage
    img = np.array(Image.open(SIL).convert("RGB")).astype(int)
    img[0:60, 1180:1280, :] = 0
    m = img.sum(axis=2) > 6
    m = ndimage.binary_closing(m, structure=np.ones((3, 3)), iterations=2)
    m = ndimage.binary_fill_holes(m)
    return ndimage.binary_opening(m, structure=np.ones((3, 3)))


def mask_local() -> np.ndarray:
    m = load_mask()
    out = np.zeros((H, W), dtype=bool)
    ys, xs = np.where(m)
    for y, x in zip(ys, xs):
        px, py = int(x - CX + OX), int(y - CY + OY)
        if 0 <= px < W and 0 <= py < H:
            out[py, px] = True
    return out


def shape_circles(sh) -> list[tuple[float, float, float]]:
    if sh[0] != "cap":
        return [(float(sh[0]), float(sh[1]), float(sh[2]))]
    _, x, y, r, height, rot = sh
    seg = max(0.0, height * 0.5 - r)
    steps = max(1, int(math.ceil(seg * 2.0 / max(r * 0.6, 1.0))))
    c, s = math.cos(rot), math.sin(rot)
    return [(x - s * t, y + c * t, r)
            for t in (-seg + seg * 2.0 * i / steps for i in range(steps + 1))]


def main() -> None:
    mask = mask_local()
    shapes = shapes_from_scene()
    print("scene shapes:", len(shapes))
    yy, xx = np.ogrid[:H, :W]
    cov = np.zeros((H, W), dtype=bool)
    for sh in shapes:
        for sx, sy, r in shape_circles(sh):
            cov |= (xx - (OX + sx)) ** 2 + (yy - (OY + sy)) ** 2 <= r * r
    inter = int((mask & cov).sum())
    total = int(mask.sum())
    false = int((cov & ~mask).sum())
    union = int((mask | cov).sum())
    print(f"覆盖 {inter / total * 100:.1f}%  误覆盖 {false}px  IoU {inter / union * 100:.1f}%  剪影 {total}px")
    print(f"漏掉 {total - inter}px")
    ys, xs = np.where(mask & ~cov)
    if len(ys):
        print("漏掉区域 bbox x", xs.min() - OX, xs.max() - OX, "y", ys.min() - OY, ys.max() - OY)

    base = Image.new("RGBA", (W, H), (16, 16, 20, 255))
    tint = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    tp = tint.load()
    for y in range(H):
        for x in range(W):
            if mask[y, x]:
                tp[x, y] = (215, 205, 185, 190)
    base.alpha_composite(tint)
    d = ImageDraw.Draw(base)
    for sh in shapes:
        for sx, sy, r in shape_circles(sh):
            d.ellipse([OX + sx - r, OY + sy - r, OX + sx + r, OY + sy + r],
                      outline=(255, 70, 70, 230), width=1)
    d.line([OX, 0, OX, H], fill=(70, 150, 255, 160))
    d.line([0, OY, W, OY], fill=(70, 150, 255, 160))
    base.resize((W * 3, H * 3), Image.LANCZOS).save("output/heiliao_fit.png")
    print("overlay -> output/heiliao_fit.png")


if __name__ == "__main__":
    main()
