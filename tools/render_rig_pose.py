#!/usr/bin/env python
"""离线的刀客骨骼渲染器 —— 严格复刻 BossRig._build_nodes 的父子变换。

用途：不改 Godot、不进引擎，就能**看到**刀客在任意姿态下长什么样。
之前几轮「自动化检查全过、玩家却说动作错」的根因就是：只在 build 脚本里
用预览坐标画了图，没真正按 BossRig 的关节口径拼过。这个脚本按 BossRig 的真实
口径（part_joint 是相对 rig 原点的全局关节，挂父节点时要减掉父关节）来拼，
所以渲染出来的就是引擎里真实会出现的样子。

变换链（无旋转时的静止姿态即可验证关节口径对不对）：
  body.global = part_joint[body]               (父是空)
  arm.global  = part_joint[arm]                (父子相减再相加，相互抵消)
  arm_fore.global = part_joint[arm_fore]        (同上)

每个部件贴图：以自身关节为原点，贴图中心放在 part_offset（相对关节）。
然后整块套上全局仿射（平移到关节 + 绕关节旋转 + 躯干缩放）。

用法：
  python tools/render_rig_pose.py                        # 静止 + 几个极端姿态对照表
  python tools/render_rig_pose.py --fan arm_fore         # 只转前臂 ±150°，查肘部零缝
  python tools/render_rig_pose.py --walk                 # 腿 ±0.20rad，查裙摆下沿露馅
  python tools/render_rig_pose.py --pose arm=-0.45,fore=1.40
  python tools/render_rig_pose.py --out out.png
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
RIG_TRES = os.path.join(ROOT, "..", "assets", "characters", "boss", "daoke_rig", "rig.tres")
CANVAS = (900, 720)
ORIGIN = (CANVAS[0] * 0.5, CANVAS[1] * 0.5)  # rig 原点在画布中心


def parse_tres(path: str) -> dict:
    text = open(path, "r", encoding="utf-8").read()
    def grab(name: str) -> list[float]:
        m = re.search(name + r"\s*=\s*PackedVector2Array\(([^)]*)\)", text)
        nums = [float(x) for x in re.findall(r"-?\d+\.?\d*", m.group(1))]
        return nums
    def grab_str(name: str) -> list[str]:
        m = re.search(name + r"\s*=\s*PackedStringArray\(([^)]*)\)", text)
        return re.findall(r'"([^"]*)"', m.group(1))
    def grab_int(name: str) -> list[int]:
        m = re.search(name + r"\s*=\s*PackedInt32Array\(([^)]*)\)", text)
        return [int(x) for x in re.findall(r"-?\d+", m.group(1))]
    order = grab_str("order")
    parent = grab_str("part_parent")
    joint = grab("part_joint")
    offset = grab("part_offset")
    z = grab_int("part_z")
    n = len(order)
    joints = [(joint[2*i], joint[2*i+1]) for i in range(n)]
    offsets = [(offset[2*i], offset[2*i+1]) for i in range(n)]
    parts = {}
    d = os.path.dirname(path)
    # res:// 就是仓库根（Godot 的项目目录），本脚本在 tools/ 下 → 上一级即仓库根。
    # ⚠ 别按 tres 的路径「往上数 N 级」推：那样只有正式产物在
    #   assets/characters/boss/<x>/ 这一层深度时才碰巧对，验证用的临时拆件
    #   目录（output/ 下）会解析到仓库外面去，报一个看不懂的 FileNotFoundError。
    repo = os.path.dirname(ROOT)
    for i, name in enumerate(order):
        tex = re.search(r'part_tex = PackedStringArray\((.*?)\)', text, re.S).group(1)
        texpath = re.findall(r'"([^"]*)"', tex)[i]
        texpath = texpath.replace("res://", "").replace("/", os.sep)
        full = os.path.normpath(os.path.join(repo, texpath))
        parts[name] = {
            "joint": joints[i], "offset": offsets[i], "z": z[i],
            "parent": parent[i], "img": Image.open(full).convert("RGBA"),
        }
    return {"order": order, "parts": parts,
            "muzzle_part": grab_str("muzzle_part")[0],
            "muzzle_offset": tuple(grab("muzzle_offset")[:2])}


def compose(a, b):
    """2x3 仿射相乘：返回 a∘b（先 b 后 a）。a,b = (a,b,c,d,e,f)。"""
    a00, a01, a02, a10, a11, a12 = a
    b00, b01, b02, b10, b11, b12 = b
    return (
        a00*b00 + a01*b10, a00*b01 + a01*b11, a00*b02 + a01*b12 + a02,
        a10*b00 + a11*b10, a10*b01 + a11*b11, a10*b02 + a11*b12 + a12,
    )


def transl(tx, ty):
    return (1.0, 0.0, tx, 0.0, 1.0, ty)


def rot(th):
    c, s = math.cos(th), math.sin(th)
    return (c, -s, 0.0, s, c, 0.0)


def scale(sx, sy):
    return (sx, 0.0, 0.0, 0.0, sy, 0.0)


def invert(m):
    a, b, c, d, e, f = m
    det = a*e - b*d
    return (
        e/det, -b/det, (b*f - c*e)/det,
        -d/det, a/det, (c*d - a*f)/det,
    )


def xforms(rig, rots: dict | None = None,
           body_pos=(0.0, 0.0), body_scale=(1.0, 1.0)) -> dict:
    """每个部件 holder-local → 屏幕画布 的全局仿射。

    ⚠ 别写成「arm 用一个角、其余全用另一个角」的三元表达式：腿会跟着前臂一起转，
      于是「前臂 ±150° 零缝检查」渲染出来的其实是四条腿 + 一条臂一起飞，
      检查完全作废还全绿。每个部件必须各转各的。
    """
    rots = rots or {}
    parts = rig["parts"]
    order = rig["order"]
    g = {}  # name -> 2x3
    # body
    mb = compose(transl(ORIGIN[0] + body_pos[0], ORIGIN[1] + body_pos[1]),
                 compose(rot(rots.get("body", 0.0)), scale(*body_scale)))
    g["body"] = mb
    for name in order:
        if name == "body":
            continue
        p = parts[name]
        parent_name = p["parent"]
        mp = g[parent_name]
        # 子相对父的关节 = 自己全局关节 - 父全局关节
        self_j = p["joint"]
        par_j = parts[parent_name]["joint"]
        rel = (self_j[0] - par_j[0], self_j[1] - par_j[1])
        g[name] = compose(mp, compose(transl(*rel), rot(rots.get(name, 0.0))))
    return g


def apply_pt(m, x, y):
    return (m[0]*x + m[1]*y + m[2], m[3]*x + m[4]*y + m[5])


def tip_of(rig, rots: dict | None = None) -> tuple:
    """刀尖在画布上的位置 + 刀身朝向（度）。

    设计招式只有这一个口径：**先定刀尖要指哪，再反解肩角/肘角**。
    角度是刚体链上可直接相加的量，所以 tip_dir = 静止指向 + body + arm + fore，
    但这里仍然用仿射去算 —— 顺手把「刀尖够不够得到判定框」的位置也一起给了。
    """
    g = xforms(rig, rots)
    part = rig["muzzle_part"]
    mx, my = apply_pt(g[part], *rig["muzzle_offset"])
    ex, ey = apply_pt(g[part], 0.0, 0.0)      # 该部件的关节（肘）在画布上的位置
    ang = math.degrees(math.atan2(my - ey, mx - ex))
    return (mx, my), ang


def render(rig, rots: dict | None = None,
           body_pos=(0.0, 0.0), body_scale=(1.0, 1.0)) -> Image.Image:
    rots = rots or {}
    parts = rig["parts"]
    order = rig["order"]
    g = xforms(rig, rots, body_pos, body_scale)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    for name in order:
        p = parts[name]
        img = p["img"]
        W, H = img.size
        off = p["offset"]
        # holder-local：贴图中心在 offset，贴图像素 (col,row) 对应 holder-local
        #   (off.x - W/2 + col, off.y - H/2 + row)
        t2s = compose(g[name], transl(off[0] - W*0.5, off[1] - H*0.5))
        inv = invert(t2s)
        warped = img.transform(CANVAS, Image.AFFINE, inv, Image.BICUBIC)
        canvas = Image.alpha_composite(canvas, warped)
    return canvas


def label(img, text):
    d = ImageDraw.Draw(img)
    d.text((8, 6), text, fill=(255, 255, 0))
    return img


ALIAS = {"fore": "arm_fore", "front": "leg_front", "back": "leg_back"}


def parse_rots(spec: str) -> dict:
    """`--pose` 的两种写法：
        "0,-0.45,1.4"                    位置式，按 body,arm,arm_fore 顺序
        "arm=-0.45,fore=1.4,leg_back=0.2"  命名式（推荐：一眼看得出转的是哪块）
    """
    spec = spec.strip()
    if "=" in spec:
        out = {}
        for kv in spec.split(","):
            k, v = kv.split("=")
            out[ALIAS.get(k.strip(), k.strip())] = float(v)
        return out
    vals = [float(x) for x in spec.split(",") if x.strip() != ""]
    return dict(zip(["body", "arm", "arm_fore"], vals))


def sheet(rig, poses: list, cols: int, out: str) -> None:
    pad = 6
    cw, ch = CANVAS
    rows = (len(poses) + cols - 1) // cols
    grid = Image.new("RGBA", (cols * (cw + pad) + pad, rows * (ch + pad) + pad),
                     (40, 40, 40, 255))
    for i, (name, rots) in enumerate(poses):
        (tx, ty), ang = tip_of(rig, rots)
        im = label(render(rig, rots), f"{name}  刀尖 {ang:+.0f}° @({tx:.0f},{ty:.0f})")
        r, c = divmod(i, cols)
        grid.alpha_composite(im, (pad + c * (cw + pad), pad + r * (ch + pad)))
    grid.convert("RGB").save(out)
    print("saved", out, grid.size)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rig", default=RIG_TRES)
    ap.add_argument("--pose", default=None, help="见 parse_rots：位置式或 part=弧度")
    ap.add_argument("--out", default=None)
    ap.add_argument("--fan", default=None, metavar="PART",
                    help="零缝检查：只转这一个部件，从 -150° 扫到 +150°。"
                         "关节盘不够大 / 盘心没落在肉上，这里就会看到断肢或楔形缝")
    ap.add_argument("--walk", action="store_true",
                    help="走路检查：腿 ±0.20rad（= H_WALK_LEG_SWING）四个极位，"
                         "看裙摆下沿有没有露出腿件顶部的直切口")
    ap.add_argument("--keys", default=None, metavar="JSON",
                    help="招式检查：读一个 [[名字, {部件: 弧度}], ...] 的 JSON 表，"
                         "一格一个关键帧渲染成对照表，每格标出刀尖朝向和落点")
    ap.add_argument("--cols", type=int, default=3)
    args = ap.parse_args()

    rig = parse_tres(args.rig)

    if args.keys:
        table = json.load(open(args.keys, encoding="utf-8"))
        poses = [(str(name), {ALIAS.get(k, k): float(v) for k, v in rots.items()})
                 for name, rots in table]
        sheet(rig, poses, args.cols, args.out or "tmp_keys.png")
        return 0

    if args.fan:
        part = ALIAS.get(args.fan, args.fan)
        degs = [-150, -100, -60, 0, 60, 100, 150]
        sheet(rig, [(f"{part} {dg:+d}°", {part: math.radians(dg)}) for dg in degs],
              4, args.out or f"tmp_fan_{part}.png")
        return 0

    if args.walk:
        sw = 0.20
        sheet(rig, [
            ("走路 A 前腿最大", {"leg_front": -sw, "leg_back": sw, "body": 0.012}),
            ("走路 B 交腿", {"leg_front": 0.0, "leg_back": 0.0, "body": 0.0}),
            ("走路 C 后腿最大", {"leg_front": sw, "leg_back": -sw, "body": -0.012}),
            ("走路 D 交腿", {"leg_front": 0.0, "leg_back": 0.0, "body": 0.0}),
        ], 2, args.out or "tmp_walk.png")
        return 0

    if args.pose:
        im = render(rig, parse_rots(args.pose))
        out = args.out or "tmp_pose.png"
        im.save(out)
        print("saved", out)
        return 0

    sheet(rig, [("静止", {}),
                ("arm -40°", {"arm": -0.70}),
                ("fore +60°", {"arm_fore": 1.05}),
                ("arm +80° fore -30°", {"arm": 1.40, "arm_fore": -0.52})],
         2, args.out or "tmp_daoke_grid.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
