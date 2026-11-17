#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""青岚古猿 / 云隐苍角的正面骨骼分件（2026-10-29）。

两只大陆核心首领原来是单张立绘；这里按正面视角拆成 5~6 块刚体件：
  · 猿：body（躯干+头+肩甲）、arm_l / arm_r（肘下前臂+手）、leg_l / leg_r（髋下腿脚）
  · 鹿：body（躯干+苔披）、head（颈+头+巨角）、leg_bl / leg_br / leg_fl / leg_fr

关节用圆盘保护：body 在关节处挖圆洞，部件圆盘略大；圆盘内透明像素用最近实色补齐，
旋转时不会露出背景。动画集见 scripts/visual/boss_rig_ape.gd / boss_rig_stag.gd。

用法：python tools/build_world_boss_rigs.py
输出：assets/characters/world/ape_rig/、assets/characters/boss/cangjiao_rig/
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


BOSSES = {
    "ape": {
        "src": "assets/characters/world/ape_qinglan.png",
        "out": "assets/characters/world/ape_rig",
        "preview": "vibe_images/world_boss_work/ape_rig_preview.png",
        "rig_script": "res://scripts/visual/boss_rig_ape.gd",
        "frame": (360, 560),
        "content_h": 504.0,
        "foot": 40.0,
        "order": ["lower", "body", "arm_l", "arm_r"],
        "parts": [
            # 正面猿：躯干+头+肩甲留在 body；前臂从肘下拆，腿合并成 lower
            {"name": "arm_l", "joint": (95.0, 250.0), "z": 2, "priority": 30,
             "shapes": [("disk", (95.0, 250.0, 42.0)),
                        ("poly", [(45.0, 230.0), (130.0, 230.0), (138.0, 300.0),
                                  (128.0, 360.0), (136.0, 430.0), (54.0, 430.0),
                                  (42.0, 340.0), (45.0, 270.0)])]},
            {"name": "arm_r", "joint": (248.0, 255.0), "z": 3, "priority": 31,
             "shapes": [("disk", (248.0, 255.0, 40.0)),
                        ("poly", [(213.0, 240.0), (282.0, 240.0), (290.0, 320.0),
                                  (282.0, 380.0), (288.0, 420.0), (218.0, 420.0),
                                  (210.0, 340.0)])]},
            {"name": "lower", "joint": (155.0, 375.0), "z": 1, "priority": 10,
             "shapes": [("disk", (155.0, 375.0, 60.0)),
                        ("rect", (40.0, 390.0, 270.0, 516.0))]},
        ],
    },
    "stag": {
        "src": "assets/characters/boss/cangjiao.png",
        "out": "assets/characters/boss/cangjiao_rig",
        "preview": "vibe_images/world_boss_work/stag_rig_preview.png",
        "rig_script": "res://scripts/visual/boss_rig_stag.gd",
        "frame": (700, 1120),
        "content_h": 1040.0,
        "foot": 40.0,
        "order": ["leg_bl", "leg_br", "body", "leg_fl", "leg_fr", "head"],
        "parts": [
            # 头+角：整块从颈线以上带走；颈部圆盘盖住接缝
            {"name": "head", "joint": (450.0, 730.0), "z": 3, "priority": 40,
             "shapes": [("rect", (0.0, 0.0, 766.0, 738.0)),
                        ("disk", (450.0, 730.0, 92.0))]},
            {"name": "leg_bl", "joint": (115.0, 980.0), "z": -3, "priority": 12,
             "shapes": [("disk", (115.0, 980.0, 56.0)),
                        ("rect", (0.0, 960.0, 170.0, 1404.0))]},
            {"name": "leg_br", "joint": (235.0, 980.0), "z": -2, "priority": 11,
             "shapes": [("disk", (235.0, 980.0, 56.0)),
                        ("rect", (170.0, 960.0, 310.0, 1404.0))]},
            {"name": "leg_fl", "joint": (390.0, 980.0), "z": 1, "priority": 13,
             "shapes": [("disk", (390.0, 980.0, 56.0)),
                        ("rect", (310.0, 960.0, 455.0, 1404.0))]},
            {"name": "leg_fr", "joint": (530.0, 980.0), "z": 2, "priority": 14,
             "shapes": [("disk", (530.0, 980.0, 56.0)),
                        ("rect", (455.0, 960.0, 766.0, 1404.0))]},
        ],
    },
    # 赤金火麟：3/4 侧视（朝右），只拆 6 块 —— 头（含巨角）/ 近侧前腿 / 近侧后腿 /
    # 远侧后腿 / 火焰尾 / 躯干。远侧前腿原图整条被近侧挡住，不拆。
    # 坐标读 assets/characters/boss/qilin.png（947×1404，见 prep_qilin_art.py 的标尺图）。
    # 镇墟石犼：3/4 侧视（朝右），7 块 —— 头+碑鬃 / 躯干 / 石槌尾 / 四条腿。
    # 坐标读 assets/characters/boss/shihou.png（969×1404，见 tools/prep_shihou_art.py 的标尺图）。
    "shihou": {
        "src": "assets/characters/boss/shihou.png",
        "out": "assets/characters/boss/shihou_rig",
        "preview": "vibe_images/world_boss_work/shihou_rig_preview.png",
        "rig_script": "res://scripts/visual/boss_rig_shihou.gd",
        "frame": (880, 1120),
        "content_h": 1040.0,
        "foot": 40.0,
        "order": ["leg_rear_far", "body", "tail", "leg_front_far", "leg_rear_near", "leg_front_near", "head"],
        "parts": [
            # 头 + 碑石鬃 + 封眼石带：从颈部以上整块带走；圆盘盖住接缝
            {"name": "head", "joint": (610.0, 500.0), "z": 4, "priority": 50,
             "shapes": [("disk", (610.0, 500.0, 118.0)),
                        ("poly", [(540.0, 0.0), (720.0, 0.0), (820.0, 40.0),
                                  (900.0, 100.0), (955.0, 200.0), (965.0, 360.0),
                                  (930.0, 470.0), (880.0, 500.0), (830.0, 490.0),
                                  (780.0, 480.0), (730.0, 480.0), (680.0, 500.0),
                                  (640.0, 520.0), (575.0, 520.0), (520.0, 480.0),
                                  (470.0, 410.0), (430.0, 330.0), (440.0, 200.0),
                                  (480.0, 90.0)])]},
            # 近侧后腿（髋在 y≈930）
            {"name": "leg_rear_near", "joint": (540.0, 930.0), "z": 2, "priority": 30,
             "shapes": [("disk", (540.0, 930.0, 82.0)),
                        ("poly", [(455.0, 900.0), (625.0, 900.0), (650.0, 1404.0),
                                  (500.0, 1404.0), (470.0, 1050.0)])]},
            # 远侧后腿（被石槌尾压住一部分，小摆角）
            {"name": "leg_rear_far", "joint": (350.0, 930.0), "z": -3, "priority": 25,
             "shapes": [("disk", (350.0, 930.0, 78.0)),
                        ("poly", [(270.0, 900.0), (450.0, 900.0), (460.0, 1250.0),
                                  (440.0, 1330.0), (300.0, 1330.0), (280.0, 1200.0)])]},
            # 近侧前腿（肩在 y≈920）
            {"name": "leg_front_near", "joint": (860.0, 920.0), "z": 3, "priority": 40,
             "shapes": [("disk", (860.0, 920.0, 95.0)),
                        ("poly", [(770.0, 880.0), (969.0, 880.0), (969.0, 1404.0),
                                  (800.0, 1404.0), (780.0, 1000.0)])]},
            # 远侧前腿（近侧前腿后面，只露一半）
            {"name": "leg_front_far", "joint": (690.0, 920.0), "z": 1, "priority": 35,
             "shapes": [("disk", (690.0, 920.0, 88.0)),
                        ("poly", [(610.0, 900.0), (775.0, 900.0), (790.0, 1404.0),
                                  (640.0, 1404.0), (615.0, 1000.0)])]},
            # 石槌尾：从臀部向左下甩到画面左下，末端石球
            {"name": "tail", "joint": (250.0, 760.0), "z": 1, "priority": 20,
             "shapes": [("disk", (250.0, 760.0, 85.0)),
                        ("poly", [(210.0, 650.0), (320.0, 700.0), (350.0, 790.0),
                                  (330.0, 900.0), (300.0, 1010.0), (260.0, 1120.0),
                                  (210.0, 1230.0), (130.0, 1310.0), (40.0, 1320.0),
                                  (0.0, 1240.0), (0.0, 1100.0), (40.0, 980.0),
                                  (80.0, 880.0), (120.0, 780.0), (160.0, 700.0)])]},
        ],
    },
    "qilin": {
        "src": "assets/characters/boss/qilin.png",
        "out": "assets/characters/boss/qilin_rig",
        "preview": "vibe_images/world_boss_work/qilin_rig_preview.png",
        "rig_script": "res://scripts/visual/boss_rig_qilin.gd",
        "frame": (800, 1120),
        "content_h": 1040.0,
        "foot": 40.0,
        "order": ["leg_hind_far", "tail", "body", "leg_hind", "leg_front", "head"],
        "parts": [
            # 头 + 双角：从颈线往右整块带走；颈部圆盘盖住接缝
            {"name": "head", "joint": (645.0, 565.0), "z": 3, "priority": 50,
             "shapes": [("disk", (645.0, 565.0, 104.0)),
                        ("poly", [(520.0, 70.0), (600.0, 30.0), (700.0, 30.0),
                                  (790.0, 85.0), (870.0, 200.0), (947.0, 320.0),
                                  (947.0, 480.0), (920.0, 570.0), (880.0, 625.0),
                                  (820.0, 600.0), (760.0, 615.0), (700.0, 655.0),
                                  (640.0, 670.0), (580.0, 630.0), (545.0, 560.0),
                                  (520.0, 420.0), (505.0, 260.0)])]},
            # 近侧前腿：膝在 y≈950，脚底 1404
            {"name": "leg_front", "joint": (855.0, 950.0), "z": 2, "priority": 40,
             "shapes": [("disk", (855.0, 950.0, 82.0)),
                        ("poly", [(762.0, 935.0), (947.0, 935.0), (947.0, 1404.0),
                                  (772.0, 1404.0)])]},
            # 近侧后腿：髋在 y≈1000
            {"name": "leg_hind", "joint": (630.0, 1000.0), "z": 2, "priority": 41,
             "shapes": [("disk", (630.0, 1000.0, 84.0)),
                        ("poly", [(548.0, 985.0), (748.0, 985.0), (760.0, 1404.0),
                                  (556.0, 1404.0)])]},
            # 远侧后腿：被近侧后腿压住一半，只做小摆角
            {"name": "leg_hind_far", "joint": (470.0, 1010.0), "z": -3, "priority": 20,
             "shapes": [("disk", (470.0, 1010.0, 62.0)),
                        ("poly", [(385.0, 995.0), (552.0, 995.0), (548.0, 1404.0),
                                  (398.0, 1404.0)])]},
            # 火焰尾：从臀部向左下甩到画面左下，末端回勾到 x≈500
            {"name": "tail", "joint": (390.0, 760.0), "z": 1, "priority": 30,
             "shapes": [("disk", (390.0, 760.0, 86.0)),
                        ("rect", (0.0, 690.0, 435.0, 1404.0)),
                        # 尾尖只在下缘这一楔形里，别伸到远侧后腿的蹄子上（蹄底 y≈1295）
                        ("poly", [(410.0, 1310.0), (515.0, 1355.0),
                                  (500.0, 1404.0), (385.0, 1404.0)])]},
        ],
    },
}


def alpha_of(rgba: np.ndarray) -> np.ndarray:
    return rgba[..., 3] > 180


def disk_mask(shape, cx, cy, r):
    yy, xx = np.ogrid[0:shape[0], 0:shape[1]]
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r


def rect_mask(shape, x0, y0, x1, y1):
    m = np.zeros(shape, dtype=bool)
    m[max(0, int(y0)):min(shape[0], int(y1)),
      max(0, int(x0)):min(shape[1], int(x1))] = True
    return m


def dilate1(m: np.ndarray) -> np.ndarray:
    p = np.pad(m, 1, mode="edge")
    return (p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])


def fill_holes(rgba: np.ndarray, region: np.ndarray, solid: np.ndarray) -> np.ndarray:
    """把 region 内透明像素用最近实色补满（圆盘转动时不露背景）。"""
    holes = region & (rgba[..., 3] < 40)
    src = solid & (rgba[..., 3] >= 40)
    if not holes.any() or not src.any():
        return rgba
    _, idx = ndimage.distance_transform_edt(~src, return_indices=True)
    out = rgba.copy()
    ys, xs = idx[0][holes], idx[1][holes]
    out[holes, :3] = rgba[ys, xs, :3]
    out[holes, 3] = 255
    return out


def render_part(frame, mask, joint, name, out_dir, mean_rgb):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        raise RuntimeError("部件没有像素：" + name)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    crop = frame[y0:y1, x0:x1].copy()
    m = mask[y0:y1, x0:x1]
    # 膨胀边缘可能带出透明像素：用部件均值补色，避免黑边
    transparent = m & (crop[..., 3] < 40)
    if transparent.any():
        crop[transparent, :3] = mean_rgb
        crop[transparent, 3] = 255
    crop[..., 3] = np.where(m, crop[..., 3], 0).astype(np.uint8)
    img = Image.fromarray(crop)
    img.save(os.path.join(out_dir, name + ".png"))
    bbox_center = np.array([(x0 + x1) * 0.5, (y0 + y1) * 0.5], dtype=np.float64)
    offset = bbox_center - np.array(joint, dtype=np.float64)
    return offset


def build(key, cfg):
    src = Image.open(cfg["src"]).convert("RGBA")
    arr = np.array(src)
    a = alpha_of(arr)
    ys, xs = np.nonzero(a)
    bx0, bx1 = int(xs.min()), int(xs.max()) + 1
    by0, by1 = int(ys.min()), int(ys.max()) + 1
    content_h = float(cfg["content_h"])
    s = content_h / float(by1 - by0)
    content_w = round((bx1 - bx0) * s)
    fw, fh = cfg["frame"]
    ox = (fw - content_w) * 0.5
    oy = fh - cfg["foot"] - content_h
    resized = src.crop((bx0, by0, bx1, by1)).resize((content_w, round(content_h)), Image.LANCZOS)
    frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    frame.alpha_composite(resized, (int(round(ox)), int(round(oy))))
    frame_arr = np.array(frame)
    alpha = alpha_of(frame_arr)
    h, w = alpha.shape

    def tx(x):
        return (x - bx0) * s + ox

    def ty(y):
        return (y - by0) * s + oy

    assigned = np.zeros((h, w), dtype=bool)
    parts = sorted(cfg["parts"], key=lambda p: -int(p["priority"]))
    part_masks = {}
    for p in parts:
        m = np.zeros((h, w), dtype=bool)
        for kind, args in p["shapes"]:
            if kind == "disk":
                cx, cy, r = args
                m |= disk_mask((h, w), tx(cx), ty(cy), r * s)
            elif kind == "poly":
                pts = [(tx(px), ty(py)) for px, py in args]
                pm = Image.new("1", (w, h), 0)
                ImageDraw.Draw(pm).polygon(pts, fill=1)
                m |= np.array(pm, dtype=bool)
            else:
                x0, y0, x1, y1 = args
                m |= rect_mask((h, w), tx(x0), ty(y0), tx(x1), ty(y1))
        m &= alpha
        m &= ~assigned
        if not m.any():
            raise RuntimeError("%s/%s 没有分到像素" % (key, p["name"]))
        # 关节圆盘内补洞，保证旋转时不露背景
        for kind, args in p["shapes"]:
            if kind == "disk":
                cx, cy, r = args
                dm = disk_mask((h, w), tx(cx), ty(cy), r * s)
                frame_arr = fill_holes(frame_arr, dm, alpha)
        m = dilate1(m) & ~assigned
        part_masks[p["name"]] = m
        assigned |= m

    body_mask = alpha & ~assigned
    if not body_mask.any():
        raise RuntimeError(key + " body 为空")
    part_masks["body"] = body_mask

    os.makedirs(cfg["out"], exist_ok=True)
    order = cfg["order"]
    assert "body" in order
    # 记录关节 / 偏移
    meta = {}
    for name, m in part_masks.items():
        ys2, xs2 = np.nonzero(m)
        mean_rgb = frame_arr[m][:, :3].mean(axis=0).astype(np.uint8)
        if name == "body":
            joint = (w * 0.5, h * 0.5)
        else:
            p = next(p for p in cfg["parts"] if p["name"] == name)
            joint = (tx(p["joint"][0]), ty(p["joint"][1]))
        off = render_part(frame_arr, m, joint, name, cfg["out"], mean_rgb)
        meta[name] = {
            "joint": (joint[0] - w * 0.5, joint[1] - h * 0.5),
            "offset": (float(off[0]), float(off[1])),
            "z": 0 if name == "body" else next(p for p in cfg["parts"] if p["name"] == name)["z"],
            "parent": "" if name == "body" else "body",
        }

    # .tres
    def sarr(vals):
        return "PackedStringArray(" + ", ".join('"%s"' % v for v in vals) + ")"

    def varr(vals):
        return "PackedVector2Array(" + ", ".join("%.2f, %.2f" % (v[0], v[1]) for v in vals) + ")"

    res_path = "res://" + cfg["out"].replace("\\", "/") + "/"
    tres = [
        '[gd_resource type="Resource" script_class="BossRigData" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/data/boss_rig_data.gd" id="1_rig"]',
        "",
        "[resource]",
        'script = ExtResource("1_rig")',
        "canvas = Vector2i(%d, %d)" % (fw, fh),
        "rig_script = " + ('"%s"' % cfg["rig_script"]),
        "order = " + sarr(order),
        "part_name = " + sarr(order),
        "part_tex = " + sarr([res_path + n + ".png" for n in order]),
        "part_parent = " + sarr([meta[n]["parent"] for n in order]),
        "part_joint = " + varr([meta[n]["joint"] for n in order]),
        "part_offset = " + varr([meta[n]["offset"] for n in order]),
        "part_z = PackedInt32Array(" + ", ".join(str(meta[n]["z"]) for n in order) + ")",
        "muzzle_anim = PackedStringArray()",
        "muzzle_part = PackedStringArray()",
        "muzzle_offset = PackedVector2Array()",
        "",
    ]
    with open(os.path.join(cfg["out"], "rig.tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(tres))

    # 预览：每块着色 + 原图叠影，检查切缝
    colors = [(70, 140, 255), (255, 90, 90), (90, 210, 120), (255, 190, 60),
              (200, 100, 255), (60, 220, 220), (255, 120, 200)]
    preview = Image.new("RGB", (fw, fh), (238, 238, 238))
    for i, name in enumerate(order):
        m = part_masks[name]
        layer = np.zeros((h, w, 4), dtype=np.uint8)
        layer[..., 0], layer[..., 1], layer[..., 2] = colors[i % len(colors)]
        layer[..., 3] = np.where(m, 210, 0).astype(np.uint8)
        preview.paste(Image.fromarray(layer), (0, 0), Image.fromarray(layer))
    os.makedirs(os.path.dirname(cfg["preview"]), exist_ok=True)
    preview.save(cfg["preview"])

    union = np.zeros((h, w), dtype=bool)
    for m in part_masks.values():
        union |= m
    inter = float((union & alpha).sum())
    iou = inter / float(max((union | alpha).sum(), 1))
    print("[%s] 画布 %dx%d，内容高 %.0f，%d 块，拼回 IoU %.2f%%"
          % (key, fw, fh, content_h, len(part_masks), iou * 100))
    print("  " + cfg["out"] + "/rig.tres")
    print("  预览 " + cfg["preview"])


def main() -> int:
    for key, cfg in BOSSES.items():
        build(key, cfg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
