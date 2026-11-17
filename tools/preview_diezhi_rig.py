"""叠纸 rig 合成预览：按 rig.tres 的 part_joint / part_offset 真摆一遍。

⚠ 只看「镇尺握没握住」不够 —— 这条预览存在的理由是**血条/受击球锚点**：
  BossBase.head_top_y() 取的是 rig 画布上内容的最高点，画布留白会把它顶上天。
  所以这里同时打印合成结果在 rig 画布坐标系里的包围盒，和定妆图对一遍。
"""
from __future__ import annotations

import math
import re
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RIG = ROOT / "assets" / "characters" / "boss" / "diezhi_rig"
OUT = ROOT / "output" / "diezhi_rig_composite.png"
GROUND = ROOT / "assets" / "scenes" / "zhaoying_fold_arena_ground.png"
RULE_REST_ROT = -0.34     # boss_rig_diezhi.RULE_REST_ROT（弧度，屏幕 y 向下为正=顺时针）


def parse_tres(path: Path) -> dict:
    txt = path.read_text(encoding="utf-8")

    def vec2_array(key: str) -> list:
        m = re.search(key + r" = PackedVector2Array\(([^)]*)\)", txt)
        if not m:
            return []
        nums = [float(v) for v in re.split(r"[,\s]+", m.group(1).strip()) if v]
        return [(nums[i], nums[i + 1]) for i in range(0, len(nums) - 1, 2)]

    m = re.search(r"canvas = Vector2i\((\d+),\s*(\d+)\)", txt)
    return {
        "canvas": (int(m.group(1)), int(m.group(2))),
        "order": re.findall(r'"(\w+)"', re.search(r'order = PackedStringArray\(([^)]*)\)', txt).group(1)),
        "part": re.findall(r'"(\w+)"', re.search(r'part_name = PackedStringArray\(([^)]*)\)', txt).group(1)),
        "parent": re.findall(r'"(\w*)"', re.search(r'part_parent = PackedStringArray\(([^)]*)\)', txt).group(1)),
        "joint": vec2_array("part_joint"),
        "offset": vec2_array("part_offset"),
    }


def main() -> None:
    d = parse_tres(RIG / "rig.tres")
    cw, ch = d["canvas"]
    print(f"画布 {cw}×{ch}  部件 {d['part']}  父级 {d['parent']}")
    for i, name in enumerate(d["part"]):
        print(f"  {name:6s} joint {d['joint'][i]}  offset {d['offset'][i]}")

    # 画布外扩，免得 body 的 offset 把它推出边界被裁
    pad = 200
    W, H = cw + pad * 2, ch + pad * 2
    ox, oy = W / 2.0, H / 2.0          # rig 原点 = 画布中心
    canvas = np.zeros((H, W, 4), np.float32)

    def paste_center(img: Image.Image, cx: float, cy: float) -> None:
        x = int(round(cx - img.width / 2))
        y = int(round(cy - img.height / 2))
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(W, x + img.width), min(H, y + img.height)
        if x1 <= x0 or y1 <= y0:
            return
        a = np.asarray(img, np.float32)
        sub = a[y0 - y:y1 - y, x0 - x:x1 - x]
        al = sub[..., 3:4] / 255.0
        reg = canvas[y0:y1, x0:x1]
        rgb = reg[..., :3] * (1.0 - al) + sub[..., :3] * al
        alpha = np.maximum(reg[..., 3:4], sub[..., 3:4])
        canvas[y0:y1, x0:x1] = np.dstack([rgb, alpha])

    for i, name in enumerate(d["part"]):
        img = Image.open(RIG / f"{name}.png").convert("RGBA")
        # boss_rig.gd：holder.position = joint[i] - joint[parent]，挂在父 holder 下，
        # 绝对位置展开后正好等于 joint[i]，所以这里**不要**再加父关节。
        jx, jy = d["joint"][i]
        cx, cy = ox + jx + d["offset"][i][0], oy + jy + d["offset"][i][1]
        if name == "rule":
            # 待机静止角：boss_rig_diezhi.RULE_REST_ROT，绕握点（holder 原点）转
            img = img.rotate(-RULE_REST_ROT * 180.0 / math.pi, expand=True,
                             resample=Image.BICUBIC)
        paste_center(img, cx, cy)

    # 合成结果换回 rig 画布坐标（原点 = 画布中心）
    ys, xs = np.nonzero(canvas[..., 3] > 24)
    bb = (int(xs.min()) - ox, int(ys.min()) - oy, int(xs.max()) - ox, int(ys.max()) - oy)
    print(f"合成内容包围盒(rig 局部) x {bb[0]}~{bb[2]}  y {bb[1]}~{bb[3]}"
          f"   最高点 y={bb[1]}（head_top_y 直接吃这个数）")

    g = np.asarray(Image.open(GROUND).convert("RGB").resize((W, H), Image.LANCZOS), np.float32)
    al = canvas[..., 3:4] / 255.0
    out = np.clip(g * (1.0 - al) + canvas[..., :3] * al, 0, 255).astype(np.uint8)
    Image.fromarray(out, "RGB").save(OUT)
    print("预览 ->", OUT)


if __name__ == "__main__":
    main()
