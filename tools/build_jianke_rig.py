#!/usr/bin/env python
"""从剑客侧身定妆图拆出人形骨骼分件（供 BossRigSwordsman 做骨骼动画）。

## 与刀客（build_daoke_rig.py）的差别

| | 刀客 | 剑客 |
|---|---|---|
| 兵刃 | 大刀归手臂（大片遮罩地狱） | **不持兵刃**，飞剑走特效 → 没有刀身遮罩问题 |
| 头 | 并入躯干 | 并入躯干（同理） |
| 腿 | 裙摆下露出大腿到脚 | **长袍遮到脚踝**，可见的只有靴子（约 70px）→ 髋放低、摆幅小 |
| 额外部件 | — | **披帛拆两节**（肩后垂下的长纱，做滞后摆动） |

## 部件与层级

```
body（躯干 + 头 + 长发 + 长袍 + 胸前那截披帛）
  ├── arm        肩 ———— 整条持剑指的手臂 + 大袖，挥指全靠它
  ├── leg_front  髋 ———— 前脚（靴筒内为轴）
  └── leg_back   髋 ———— 后脚
shawl1（肩后垂下的披帛上段，画在身后）
  └── shawl2（披帛下摆长尾）
```

⚠ `shawl1/2` 是 **body 的兄弟节点**（不是子节点）：披帛画在身后，若挂在 body 下，
躯干一晃它就跟着甩，失去「滞后一拍」的观感。它的摆动要自己 K 帧。

## 尺寸口径

先跑 `tools/cut_jianke_anchor.py` 把定妆图变成 900×720 画布（内容高 590、脚底 y=700），
本脚本只吃那张画布图 —— 所有解剖参数都是**画布像素**，与叠网格的参考图 1:1 对得上。

用法：
    python tools/build_jianke_rig.py
输出：
    assets/characters/boss/jianke_rig/<part>.png       分件贴图（画布分辨率）
    assets/characters/boss/jianke_rig/rig.tres         骨骼数据（BossRigData）
    vibe_images/boss_work/boss_jianke/rig_preview.png  分件着色预览
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_tiger_rig import dilate1, disk, dist_to_polyline, fill_disk_holes, safe_disk_radius  # noqa: E402

# ===================== 输入 / 输出 =====================

## 画布图（由 cut_jianke_anchor.py 生成，已经是 900x720 / 内容高 590 / 脚底 y=700）
SRC = "vibe_images/boss_work/boss_jianke/_canvas.png"
OUT_DIR = "assets/characters/boss/jianke_rig"
PREVIEW = "vibe_images/boss_work/boss_jianke/rig_preview.png"

FRAME_W, FRAME_H = 900, 720
RIG_SCRIPT = "res://scripts/visual/boss_rig_swordsman.gd"

# ===================== 解剖参数（**画布坐标**）=====================
# ⚠ 换定妆图必须重读这些数：体形一变，圆盘就落到肉外面，一转身直接断肢。
#   读法：把画布图叠 20px 网格，直接读格线（_g_arm.png / _g_legs.png）。

## 肩关节（整条手臂绕它转）。落在袖子里、肩窝位置，不要放在袖口
SHOULDER = (432, 315)
SHOULDER_R = 30

## 手臂：折线带（肩 → 肘 → 腕），每段一个半径
ARM_SEGS = [
    (((434, 314), (472, 322)), 27),   # 上臂 + 大袖根部
    (((470, 322), (506, 340)), 22),   # 前臂 + 黑护腕
]
## 袖子本体（比手臂粗得多，折线带圈不住）+ 手：都用多边形
SLEEVE_POLY = [
    (402, 276), (452, 268), (498, 300), (500, 336), (470, 352), (420, 348), (398, 316),
]
## 剑指手。⚠ 坐标是逐行量出来的：手指尖到 x=604 / y 344~352，
##   第一版整体标高了 25px（写成 316~348），手就留在躯干上 —— 挥指时画面上有**两只手**。
HAND_POLY = [
    (500, 326), (545, 330), (588, 338), (604, 345), (600, 355),
    (568, 362), (540, 368), (510, 366), (500, 348),
]

## 髋关节（腿绕它转）。⚠ 长袍遮到 y≈628，可见的腿只有靴子：
##   关节必须**放进靴筒**(y≈605)，圆盘才不会切到袍子上；摆幅也要跟着小。
HIP_FRONT = (480, 605)
HIP_BACK = (415, 605)
HIP_R = 26
## 两条靴子的包围盒（用 alpha 裁形，矩形只是范围）
LEG_FRONT_BOX = (438, 588, 545, 704)
LEG_BACK_BOX = (378, 588, 478, 704)

## 披帛：上段（肩后垂到腰）与下段（长尾）。
## ⚠ 上段要盖住肩后那一圈，不然躯干一转，肩后就是背景色的洞。
SHAWL1_POLY = [
    (346, 262), (420, 250), (474, 262), (492, 320), (486, 380),
    (452, 430), (386, 436), (344, 396), (334, 320),
]
SHAWL1_PIVOT = (452, 286)
SHAWL1_R = 30
SHAWL2_POLY = [
    (344, 396), (452, 430), (440, 500), (410, 560), (372, 606),
    (330, 628), (306, 592), (300, 500), (306, 430),
]
SHAWL2_PIVOT = (398, 430)
SHAWL2_R = 26

## 手臂压在**躯干**上的那一段（袖子内侧）。只有这块在 body 里保留 + 重涂，
## 其余（伸到背景上的部分）从 body 挖掉，否则挥指时原地留一片袖子残影。
## ⚠ 必须盖住**袖子压住躯干的全部范围**（实测 x 395~505 / y 262~384）。
##   第一版圈小了（只到 x=466），袖子一抬起来胸口就露出一个 V 形的背景缺口。
##   右边界的上限是躯干轮廓（该高度 x≈520），超出去就会保留「袖子糊在空中」。
ARM_KEEP_ZONE = [
    (392, 262), (472, 268), (506, 330), (500, 382), (410, 386), (386, 320),
]

## 披帛**胸前那一段**（画在身体前面，绕在肩上）。
## ⚠ 它**不能**进 shawl1 部件：shawl1 的 z 在 body 之后，把胸前那截放进去会被躯干挡住
##   （实测待机帧胸口糊了一片补画色）。正确做法是把它整块留给 body —— 它本来就跟着躯干走，
##   不需要摆动。真正要摆的是**身后**那条长纱。
SHAWL_FRONT_ZONE = [
    (408, 250), (512, 256), (518, 340), (500, 402), (404, 406), (396, 320),
]

# ===================== 工具 =====================


def ribbon(shape, pts, r: float) -> np.ndarray:
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    d = dist_to_polyline(xx.astype(np.float32), yy.astype(np.float32), list(pts))
    return d <= r


def ribbon_multi(shape, segs) -> np.ndarray:
    out = np.zeros(shape, dtype=bool)
    for pts, r in segs:
        out |= ribbon(shape, pts, r)
    return out


def poly_mask(shape, pts) -> np.ndarray:
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).polygon(pts, fill=255)
    return np.array(im) > 0


def box_mask(shape, box) -> np.ndarray:
    x0, y0, x1, y1 = box
    m = np.zeros(shape, dtype=bool)
    m[y0:y1, x0:x1] = True
    return m


def keep_large(shape_mask: np.ndarray, ratio: float = 0.03) -> np.ndarray:
    """去掉小于「最大连通块 ratio 倍」的碎片。

    ⚠ 为什么需要：披帛/袖子的多边形会顺手圈到几块**不相连的边角**（纱的细边、
    衣角反光），它们跟着部件转就变成空中漂浮的碎片（实测 heaven 定格有三片）。
    只保留主块，边角料留在 body 里（那里本来就看不出）。
    """
    from scipy import ndimage
    lab, n = ndimage.label(shape_mask)
    if n <= 1:
        return shape_mask
    sizes = ndimage.sum(shape_mask, lab, range(1, n + 1))
    big = int(sizes.max())
    keep = np.zeros_like(shape_mask)
    for i, s in enumerate(sizes, start=1):
        if s >= big * ratio:
            keep |= (lab == i)
    return keep


def inpaint(rgba: np.ndarray, hole: np.ndarray, keep: np.ndarray,
            margin: int = 5, blur_sigma: float = 4.0) -> np.ndarray:
    """把 hole 里的像素用附近颜色补出来（不透明）。见 build_daoke_rig.inpaint 的注释。"""
    from scipy import ndimage
    src_zone = keep
    if margin > 0:
        src_zone = keep & ~ndimage.binary_dilation(hole, iterations=margin)
        if not src_zone.any():
            src_zone = keep
    solid = src_zone & (rgba[..., 3] >= 40)
    if not hole.any() or not solid.any():
        return rgba
    _, idx = ndimage.distance_transform_edt(~solid, return_indices=True)
    out = rgba.copy()
    ys, xs = np.nonzero(hole)
    out[ys, xs, :3] = rgba[idx[0][ys, xs], idx[1][ys, xs], :3]
    out[ys, xs, 3] = 255
    if blur_sigma > 0:
        soft = ndimage.gaussian_filter(out[..., :3].astype(np.float32),
                                       sigma=(blur_sigma, blur_sigma, 0))
        out[ys, xs, :3] = soft[ys, xs].astype(np.uint8)
    return out


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description="把剑客定妆图拆成骨骼分件")
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default=PREVIEW)
    args = ap.parse_args()

    rgba = np.array(Image.open(args.src).convert("RGBA"))
    if rgba.shape[0] != FRAME_H or rgba.shape[1] != FRAME_W:
        raise SystemExit(f"{args.src} 不是 {FRAME_W}x{FRAME_H} 的画布图 —— 先跑 cut_jianke_anchor.py")
    alpha = rgba[..., 3] > 180
    shape = (FRAME_H, FRAME_W)
    masks: dict[str, np.ndarray] = {}
    src_map: dict[str, np.ndarray] = {}

    # ---- 手臂（含大袖、手）----
    arm = alpha & (ribbon_multi(shape, ARM_SEGS)
                   | poly_mask(shape, SLEEVE_POLY)
                   | poly_mask(shape, HAND_POLY))
    arm_r = safe_disk_radius(alpha, SHOULDER[0], SHOULDER[1], SHOULDER_R)
    arm |= disk(shape, SHOULDER[0], SHOULDER[1], arm_r)
    masks["arm"] = keep_large(arm)
    arm = masks["arm"]
    src_map["arm"] = fill_disk_holes(rgba, SHOULDER[0], SHOULDER[1], arm_r)
    print(f"  圆盘 arm     上限 {SHOULDER_R} → 实际 {arm_r:.0f}")

    # ---- 两条腿（只有靴子可见）----
    for name, box, jo in (("leg_front", LEG_FRONT_BOX, HIP_FRONT),
                          ("leg_back", LEG_BACK_BOX, HIP_BACK)):
        rr = safe_disk_radius(alpha, jo[0], jo[1], HIP_R)
        m = alpha & box_mask(shape, box)
        m |= disk(shape, jo[0], jo[1], rr)
        masks[name] = m
        src_map[name] = fill_disk_holes(rgba, jo[0], jo[1], rr)
        print(f"  圆盘 {name:<9} 上限 {HIP_R} → 实际 {rr:.0f}")

    # ---- 披帛两节（画在身后，画布上不与躯干重叠，直接从 alpha 里切）----
    # ⚠ 必须**挖掉手臂**：披帛的多边形会盖到袖子那一块，而手臂画在披帛**前面**。
    #   不挖的话手臂一转，原地就留下一个「手的残影」（实测：斩的命中帧上出现两只手）。
    #   挖掉是安全的 —— 那块地方本来就被手臂挡着，看不到。
    shawl_raw: dict[str, np.ndarray] = {}
    for name, poly, piv, rmax in (
            ("shawl1", SHAWL1_POLY, SHAWL1_PIVOT, SHAWL1_R),
            ("shawl2", SHAWL2_POLY, SHAWL2_PIVOT, SHAWL2_R)):
        rr = safe_disk_radius(alpha, piv[0], piv[1], rmax)
        m = (alpha & poly_mask(shape, poly)) & ~arm
        m |= disk(shape, piv[0], piv[1], rr) & ~arm
        if name == "shawl1":
            # 胸前那截留给 body（见 SHAWL_FRONT_ZONE 注释）
            m &= ~poly_mask(shape, SHAWL_FRONT_ZONE)
        shawl_raw[name] = m
        masks[name] = keep_large(m)
        src_map[name] = fill_disk_holes(rgba, piv[0], piv[1], rr)
        print(f"  圆盘 {name:<9} 上限 {rmax} → 实际 {rr:.0f}")

    # ---- body：腿挖洞、手臂分两半、披帛挖掉 ----
    leg_acc = masks["leg_front"] | masks["leg_back"]
    arm_over_body = arm & poly_mask(shape, ARM_KEEP_ZONE)
    # ⚠ 从 body 里减掉的必须是**未剔除碎片**的披帛范围：碎片已经被 keep_large 从部件里丢掉，
    #   若 body 还留着它们，就会在原位留下一片「跟不走的纱」（实测 heaven 定格左侧两片）。
    body = ((alpha & ~leg_acc & ~arm & ~shawl_raw["shawl1"] & ~shawl_raw["shawl2"])
            | arm_over_body)
    masks["body"] = body
    # 补色时**只从亮部取色**（长袍是月白的）。不限制的话最近色会取到头发/护腕的暗色，
    # 补出来的胸口是一团灰黑，手臂一抬就是一块「脏印」（实测 heaven 定格）。
    bright = rgba[..., :3].astype(np.int16).max(axis=2) > 150
    keep_src = alpha & ~arm & ~masks["shawl1"] & bright
    src_map["body"] = inpaint(rgba, arm_over_body, keep_src)

    # 部件外溢 1px 与 body 咬合，消掉静止帧上的 1px 白缝
    for k in ("arm", "leg_front", "leg_back", "shawl1", "shawl2"):
        masks[k] = dilate1(masks[k])

    # ---- 写盘 ----
    # ⚠ 层级：披帛在最后（z<0），腿的先后按美术（前脚盖住袍摆、后脚在袍后）。
    order = ["shawl2", "shawl1", "leg_back", "body", "leg_front", "arm"]
    parent = {"shawl2": "shawl1", "shawl1": "", "leg_back": "body",
              "body": "", "leg_front": "body", "arm": "body"}
    z = {"shawl2": -4, "shawl1": -3, "leg_back": -1, "body": 0, "leg_front": 2, "arm": 3}
    joint = {"shawl2": SHAWL2_PIVOT, "shawl1": SHAWL1_PIVOT, "leg_back": HIP_BACK,
             "body": None, "leg_front": HIP_FRONT, "arm": SHOULDER}

    os.makedirs(args.out, exist_ok=True)
    part_imgs: dict[str, Image.Image] = {}
    part_meta: dict[str, dict] = {}
    for name in order:
        m8 = masks[name].astype(np.uint8) * 255
        piece = src_map[name].copy()
        piece[..., 3] = np.minimum(piece[..., 3], m8)
        ys2, xs2 = np.nonzero(piece[..., 3] > 8)
        if len(ys2) == 0:
            raise RuntimeError(f"{name} 切出来是空的 —— 解剖参数错了")
        x0, y0 = int(xs2.min()), int(ys2.min())
        x1, y1 = int(xs2.max()) + 1, int(ys2.max()) + 1
        img = Image.fromarray(piece[y0:y1, x0:x1], "RGBA")
        img.save(os.path.join(args.out, f"{name}.png"))
        part_imgs[name] = img

        cx, cy = (x0 + x1) * 0.5 - FRAME_W * 0.5, (y0 + y1) * 0.5 - FRAME_H * 0.5
        jx, jy = (0.0, 0.0) if joint[name] is None else (
            joint[name][0] - FRAME_W * 0.5, joint[name][1] - FRAME_H * 0.5)
        part_meta[name] = {
            "tex": f"{name}.png",
            "joint": (jx, jy),
            "offset": (cx - jx, cy - jy),
            "parent": parent[name],
            "z": z[name],
        }
        print(f"  {name:<9} {img.size[0]:>3}x{img.size[1]:<3} 关节 ({jx:+7.1f},{jy:+7.1f}) "
              f"偏移 ({cx-jx:+7.1f},{cy-jy:+7.1f}) z={z[name]:+d}")

    # ---- rig.tres ----
    def sarr(items):
        return "PackedStringArray(" + ", ".join('"%s"' % v for v in items) + ")"

    def varr(items):
        flat = []
        for v in items:
            flat.extend(v)
        return "PackedVector2Array(" + ", ".join("%.2f" % v for v in flat) + ")"

    res_path = "res://" + args.out.replace("\\", "/") + "/"
    # 出招原点：剑指从**指尖**出（刀气 / 飞剑都从这里飞出去）
    tip = (602, 349)
    tip_rel = (tip[0] - SHOULDER[0], tip[1] - SHOULDER[1])

    tres = [
        '[gd_resource type="Resource" script_class="BossRigData" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/data/boss_rig_data.gd" id="1_rig"]',
        "",
        "[resource]",
        'script = ExtResource("1_rig")',
        "canvas = Vector2i(%d, %d)" % (FRAME_W, FRAME_H),
        'rig_script = "%s"' % RIG_SCRIPT,
        "order = " + sarr(order),
        "part_name = " + sarr(order),
        "part_tex = " + sarr([res_path + part_meta[n]["tex"] for n in order]),
        "part_parent = " + sarr([part_meta[n]["parent"] for n in order]),
        "part_joint = " + varr([part_meta[n]["joint"] for n in order]),
        "part_offset = " + varr([part_meta[n]["offset"] for n in order]),
        "part_z = PackedInt32Array(" + ", ".join(str(part_meta[n]["z"]) for n in order) + ")",
        # 九式里所有「从指尖发出」的招式都登记同一条锚点
        'muzzle_anim = ' + sarr(["stab", "lift", "chop", "cloud", "pierce",
                                 "myriad", "heaven", "heaven_full"]),
        "muzzle_part = " + sarr(["arm"] * 8),
        "muzzle_offset = " + varr([tip_rel] * 8),
        "",
    ]
    with open(os.path.join(args.out, "rig.tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(tres))
    print(f"指尖锚点 ({tip[0]},{tip[1]}) 相对肩 ({tip_rel[0]},{tip_rel[1]})")

    # ---- 着色预览 ----
    colors = {"body": (235, 235, 235), "arm": (255, 90, 90),
              "leg_front": (90, 160, 255), "leg_back": (255, 180, 60),
              "shawl1": (90, 220, 160), "shawl2": (160, 120, 255)}
    prev = Image.new("RGB", (FRAME_W, FRAME_H), (250, 250, 250))
    for name in order:
        meta = part_meta[name]
        piece = part_imgs[name]
        px = int(round(FRAME_W * 0.5 + meta["joint"][0] + meta["offset"][0] - piece.size[0] * 0.5))
        py = int(round(FRAME_H * 0.5 + meta["joint"][1] + meta["offset"][1] - piece.size[1] * 0.5))
        tint = np.array(piece).copy()
        c = colors[name]
        tint[..., :3] = (tint[..., :3] * 0.35 + np.array(c, np.float32) * 0.65).astype(np.uint8)
        prev.paste(Image.fromarray(tint, "RGBA"), (px, py), Image.fromarray(tint, "RGBA"))
    d = ImageDraw.Draw(prev)
    for name in order:
        meta = part_meta[name]
        jx = FRAME_W * 0.5 + meta["joint"][0]
        jy = FRAME_H * 0.5 + meta["joint"][1]
        d.ellipse([jx - 5, jy - 5, jx + 5, jy + 5], outline=(0, 0, 0), width=2)
        d.text((jx + 7, jy - 6), name, fill=(0, 0, 0))
    d.line([(0, FRAME_H - 20), (FRAME_W, FRAME_H - 20)], fill=(255, 0, 0), width=1)
    prev.save(args.preview)
    print(f"预览 → {args.preview}")

    # ---- 自检：拼回画布与原图比 IoU ----
    recon = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    for name in order:
        meta = part_meta[name]
        piece = part_imgs[name]
        px = int(round(FRAME_W * 0.5 + meta["joint"][0] + meta["offset"][0] - piece.size[0] * 0.5))
        py = int(round(FRAME_H * 0.5 + meta["joint"][1] + meta["offset"][1] - piece.size[1] * 0.5))
        recon.alpha_composite(piece, (px, py))
    rm = np.array(recon)[..., 3] > 128
    iou = float((rm & alpha).sum()) / float((rm | alpha).sum() or 1)
    print(f"自检 拼回 IoU {iou * 100:.2f}%")
    if iou < 0.95:
        print("  ! 切件有遗漏或重复 —— 检查各多边形的覆盖")
    print(f"完成：{len(part_imgs)} 块 → {args.out}/ (rig.tres 已生成)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
