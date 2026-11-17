#!/usr/bin/env python
"""从正侧定妆图拆出虎妖的骨骼分件（供 BossRig 做骨骼动画）。

## 为什么需要拆件

序列帧的「抽搐」是结构性的：每一格都是模型**独立重画的一只虎**，8 帧就有 8 个
不同的躯干轮廓，播起来身体必然一鼓一缩。改提示词、加密帧数都治不了 —— 加密只
增加抽搐次数。

骨骼动画里躯干始终是**同一张贴图**，只有关节在旋转，所以从原理上就不可能抽搐。
代价是必须先把定妆图按解剖拆成独立贴片。

## 切法：圆形关节（关键）

body 在每个关节处挖一个圆洞，对应的部件带一个半径更大的同心圆盘。圆盘内的像素
只属于部件、**不属于 body** —— 于是部件转多少度，圆盘都恰好填满 body 的洞，
旋转时不会露出背景。

⚠ 圆盘里的躯干纹理也会跟着转，这是 2D 骨骼的固有代价。把半径压到「略大于该处
  肢体粗」可以让它肉眼不可见；半径放大到整条大腿那样就会看到肉在扭。

## 只做「膝 / 肘以下」一段摆动

虎的腹部下沿在 y≈615，再往上躯干与腿在 alpha 上完全连成一片（实测 y=520 整行
只有两段：远侧后腿 + 躯干到下颌），强行切大腿必然带走腹部。四足行走的观感主要
来自小腿摆动 + 躯干起伏，所以腿只留一段，髋与大腿留给 body 不动。

## 与序列帧同尺寸

拆件前先把整只虎缩放到「内容高 560、脚底在 820 高画布的 y=780」，与
`tools/gen_boss_sprite_frames.py compose` 的输出完全一致 —— 这样 ArtDB 里的
scale / offset / anchor_bottom 一个都不用改，骨骼版和序列帧版可以随时互换。

用法：
    python tools/build_tiger_rig.py
输出：
    assets/characters/boss/tiger_rig/<part>.png       分件贴图（裁到 bbox）
    assets/characters/boss/tiger_rig/rig.json         关节 / 挂载 / 层级（BossRig 读它建模）
    vibe_images/boss_work/boss_huyao/rig_preview.png  分件着色预览（验切缝）
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_boss_sprite_frames as gbf  # noqa: E402  （复用 key_out 抠图）

# ===================== 输入 / 输出 =====================

SRC = ("vibe_images/boss_work/boss_huyao/"
       "_背景_高饱和荧光品红纯色平涂__FF00FF_量级_R_与_2026-10-25T19-20-02.png")
CROP_BOTTOM = 56                      # AI 出图右下角的水印
OUT_DIR = "assets/characters/boss/tiger_rig"
PREVIEW = "vibe_images/boss_work/boss_huyao/rig_preview.png"

# 与 gen_boss_sprite_frames.compose 的输出口径保持一致（见模块注释「与序列帧同尺寸」）
FRAME_W, FRAME_H = 1100, 820
CONTENT_H = 560.0
FOOT_MARGIN = 40                      # 脚底基线 = FRAME_H - FOOT_MARGIN

# ===================== 解剖参数 =====================
# 坐标全部是**原图坐标系**（1536×968，y 向下），由逐行 alpha 扫描校准。
# ⚠ 换定妆图必须重读这些数 —— 它们是整套骨骼的地基。赛璐璐重画后的虎体形变了
#   （腿更粗短、近侧后腿右移了 70px），沿用旧值会让圆盘落到腿外面、转起来直接断腿。
#   扫描方法：y=620/700/780/860 上四条腿各自是独立的 alpha 段，读它们的中心与宽度。

# 尾巴中线：只用来把尾巴分成前后两段（不用于圈选）。
# 实测（赛璐璐版）：尾巴 y=460 起独立（x 241..306），一路向左下收到 y=700 的 161..234，
# 末端在 y≈740 回勾。中心线就是这些段的中点。
TAIL_SPINE = [(300, 420), (273, 460), (253, 540), (234, 620),
              (197, 700), (140, 740), (90, 748)]
TAIL_SPLIT_IDX = 3                    # 中线第几个点作为尾根段 / 尾末段的关节

# 尾巴的**右边界曲线**（y, x_max）：尾巴向左下方延伸、末端还回勾，是条 S 形，
# 「离中线多远」圈不准 —— 末端回勾时折线会自己吃掉自己。逐行右边界最稳。
# ⚠ 起点必须画在「尾巴刚开始与身体分离」的那一行（y≈440）。写晚了尾巴上半段留在
#   body 里，tail1 只剩一小块，摆尾时尾根会整个裂开。
TAIL_EDGE = [(440, 310), (500, 296), (560, 280), (620, 270),
             (660, 250), (700, 240), (740, 226), (770, 232)]

# 四条腿。
# ⚠ 横向边界必须**随 y 变化**（折线），不能用固定区间：前腿是斜的，固定区间要么
#   切掉腿根（圆盘补不回来，旋转后看到「半个身子」），要么吃到旁边那条腿（同一片
#   像素进两个块，旋转时出重影）。下面的 Y 值全部来自逐行 alpha 扫描。
# ⚠ 圆心必须落在腿的**中心线**上（不是"大概在腿根附近"）：偏 50px 圆盘就有一半伸到腿外，
#   安全半径会被压到 20px 出头（实测 far_hind 起初只算出 22），那条腿等于没有圆盘保护。
# ⚠ 圆盘半径 = 腿根的粗细。它现在决定两件事：
#   ① 腿从哪一行开始摆（圆盘下沿 jy+r）；
#   ② 圆盘里带走多少躯干肉（圆盘上半部伸进躯干，那部分会跟着腿转）。
#   所以「宁小勿大」，但**必须盖住腿根截面**，否则圆盘外的腿根像素归 body、
#   腿转走后会在躯干上留一块腿形的肉。
# ⚠ 换图必须重读关节坐标：赛璐璐重画后近侧后腿右移了 70px，沿用旧值圆盘会落到
#   腿外面，一转身直接断腿。
LEGS = {
    "leg_far_hind": dict(jo=(334, 662), r=64, z=-3,
                         edge=[(610, 272, 478), (700, 240, 352),
                               (780, 234, 342), (880, 262, 392)]),
    "leg_near_hind": dict(jo=(556, 648), r=70, z=2,
                          edge=[(615, 490, 672), (700, 450, 578),
                                (780, 498, 618), (880, 524, 700)]),
    "leg_far_front": dict(jo=(958, 578), r=74, z=-3,
                          edge=[(610, 872, 1032), (700, 898, 1028),
                                (780, 900, 1038), (880, 930, 1138)]),
    "leg_near_front": dict(jo=(1124, 578), r=80, z=2,
                           edge=[(610, 1028, 1208), (700, 1082, 1212),
                                 (780, 1112, 1244), (880, 1192, 1308)]),
}

# 实际生效的圆盘半径（由 safe_disk_radius 从配置的 r 往下收，见该函数注释）
LEG_R: dict[str, float] = {}

# ===================== 出招原点（嘴 / 爪尖）=====================
# 招式动作名 → [部件, 部件本地偏移（**画布像素**）]。
# 用途：妖丹要「从嘴里喷出来」、掷石 / 砂石要「从前爪甩出去」。以前统一用
# `global_position + facing * 20`（身体正中），兽型横长体量下妖丹会从胸口冒出来。
# ⚠ 偏移相对该部件**关节**，跟着关节一起转 —— 甩头 / 挥爪时原点自己会动。
# ⚠ 数值从分件 PNG 的 alpha 实测：爪尖 = 腿块里 (x+y) 最大的那撮像素（取最大 6 像素均值），
#   口部 = 头块右缘往内 150px、下缘往上 55px 处（张嘴的位置）。
#   换定妆图必须重测，否则妖丹会从下巴或小腿飘出来。
# ⚠ 只登记「点状出生」的招式。扇形 / 圆形 AOE 的 FX 中心必须留在身体原点，
#   否则刀光 / 气浪会比实际判定范围远出去一截。
MUZZLE = {
    "arrow": ("leg_near_front", (139.3, 198.0)),          # 掷石 → 爪尖
    "arrow_volley": ("leg_near_front", (139.3, 198.0)),   # 砂石乱舞 → 爪尖
    "element_orb": ("head", (150.0, 55.0)),               # 吐妖丹 → 口部
}

## 腿根保留半径（原图像素）：躯干轮廓向外这么多以内、且属于腿的像素，留在 body 上。
## 太小 → 腿转走后露白缝；太大 → 残影伸到躯干外反而更难看（实测 110 时白缝比 60 更大）。
ROOT_KEEP = 60

HEAD_JO = (1262, 430)
HEAD_R = 104
TAIL_JO = (300, 412)                  # 尾根：与臀部交界处
# 圆盘半径要盖住「尾巴在尾根处的粗细」，否则摆尾时尾根与臀部的接缝露缝（半径 50 时
# 实测摆 5° 就有 5px 的缝）。58 刚好略大于尾巴最粗处。
TAIL_R = 58
TAIL_R2 = 38                          # 尾中关节的圆盘半径（尾巴比大腿细）

# 头的多边形（原图坐标）。头不能用「矩形 + 圆盘」切：颈关节右侧还压着近侧前腿的
# 上段与前胸，矩形会把它们一并切给头，转头时就带着胸肉一起动。
# ⚠ 下缘必须**沿下颌轮廓走**，不能从嘴角直接斜切到脖子 —— 那样会把整个嘴的下半部
#   （下颌 / 獠牙 / 舌头 / 下巴）切给 body，head 贴图上就只剩上唇，游戏里就是
#   「虎妖嘴缺了一块」。多边形大一点是安全的：取的是 alpha & polygon，多出来的部分
#   本来就没有像素，不会误吞身体。
HEAD_POLY = [
    (1196, 118), (1290, 112), (1360, 150), (1430, 215), (1486, 300),
    (1514, 374), (1506, 442), (1480, 498), (1442, 548), (1398, 588),
    (1348, 592), (1312, 556), (1288, 500), (1262, 420), (1242, 300), (1188, 196),
]

# ===================== 工具 =====================


def dist_to_polyline(px: np.ndarray, py: np.ndarray, pts: list) -> np.ndarray:
    """每个像素到折线的最短距离。尾巴分离用它，比矩形区间稳。"""
    best = np.full(px.shape, np.inf, dtype=np.float32)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx, dy = float(x1 - x0), float(y1 - y0)
        l2 = dx * dx + dy * dy
        if l2 < 1e-6:
            d = np.hypot(px - x0, py - y0)
        else:
            t = np.clip(((px - x0) * dx + (py - y0) * dy) / l2, 0.0, 1.0)
            d = np.hypot(px - (x0 + t * dx), py - (y0 + t * dy))
        best = np.minimum(best, d.astype(np.float32))
    return best


def disk(shape, cx: float, cy: float, r: float) -> np.ndarray:
    yy, xx = np.ogrid[0:shape[0], 0:shape[1]]
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r


def dilate1(m: np.ndarray) -> np.ndarray:
    """4 邻域膨胀 1px。

    ⚠ 这一步是必须的，不是为了「保险」：相邻部件的 mask 严格互斥时，边界两侧的
      alpha 都被裁到 0，缩放插值后各自变淡 → 拼起来露出一条 1~2px 的白缝（实测
      静止帧上臀部、腿根、尾中都有）。让每块向外溢 1px，边界互补，缝就没了。
      代价是旋转时重叠区有 1~2px 重影，在 scale 0.25 下不到半个屏幕像素，看不出。
    """
    p = np.pad(m, 1, mode="edge")
    return (p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])


## 圆盘抢像素的优先级：近侧腿在前 —— 它 z 更高、挡在外面，少拿像素就会露缝。
LEG_PRIORITY = ["leg_near_front", "leg_near_hind", "leg_far_front", "leg_far_hind"]


def safe_disk_radius(alpha: np.ndarray, jx: float, jy: float, r_max: float,
                     tol: float = 0.004) -> float:
    """返回「以 (jx,jy) 为圆心、内部几乎没有背景」的最大半径。

    ⚠ 圆盘内哪怕只有一小块背景，腿转起来就会把它转到别处 —— 而 body 那块已经被挖空，
      于是露出一个**真空洞**（内部 alpha=0）。实测配置 r=70 时 near_hind 的圆盘内
      15.3% 是背景，转 20° 就破一个 30x33px 的洞，就是用户看到的「关节裂隙」。
      所以半径必须收到「内部全实体」为止，宁可摆臂短一点。
    """
    h, w = alpha.shape
    yy, xx = np.mgrid[0:h, 0:w]
    for r in range(int(r_max), 15, -2):
        inside = (xx - jx) ** 2 + (yy - jy) ** 2 <= r * r
        if 1.0 - float(alpha[inside].mean()) <= tol:
            return float(r)
    return 16.0


def fill_disk_holes(rgba: np.ndarray, jx: float, jy: float, r: float) -> np.ndarray:
    """把圆盘内 alpha=0 的像素用「最近的实心像素」颜色填成不透明。

    圆盘绕自己的圆心旋转时形状不变 —— 只要内部**全是实心**，body 挖的那个洞
    就永远被填满。这一步是把「圆盘内的小背景」变成实心的关键，
    否则 safe_disk_radius 只能一退再退，摆臂会短到挥不动。
    """
    h, w = rgba.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    inside = (xx - jx) ** 2 + (yy - jy) ** 2 <= r * r
    holes = inside & (rgba[..., 3] < 40)
    src = inside & (rgba[..., 3] >= 40)
    if not holes.any() or not src.any():
        return rgba
    _, idx = ndimage.distance_transform_edt(~src, return_indices=True)
    out = rgba.copy()
    ys, xs = idx[0][holes], idx[1][holes]
    out[holes, :3] = rgba[ys, xs, :3]
    out[holes, 3] = 255
    return out


def build_masks(rgba: np.ndarray) -> tuple[dict, np.ndarray]:
    """返回 {部件名: 布尔掩码}。

    分配给各部件后统一下刀，最后剩下的才是 body —— body 不膨胀，它只需要「没被别人
    拿走的部分」，膨胀反而会让它在别人转走时露出残影。
    """
    # ⚠ 阈值不能低：Alpha 里混着抠图残留的极淡噪点，取 60 时 bbox 会撑满整张图，
    #   于是「内容高归一」的缩放比算错，整套坐标跟着漂（实测 s 从 0.73 掉到 0.58）。
    alpha = rgba[..., 3] > 180
    h, w = alpha.shape
    yy, xx = np.mgrid[0:h, 0:w]
    xx = xx.astype(np.float32)
    yy = yy.astype(np.float32)

    masks: dict[str, np.ndarray] = {}

    # ---- 四条腿：真圆盘关节（2026-10-26 重做）----
    #
    # 腿块 = 「整个关节圆盘里的全部前景」∪「圆盘下沿以下的腿身」。
    #
    # ⚠ 这是能不能大幅挥爪的分水岭。旧做法是「y >= cut 的一条带 + 圆盘」，
    #   带的上边界是一条**水平切边**：腿转 θ 度，这条边扫过的区域就会越出 body 挖的洞，
    #   露出一条白缝（实测 10° 就有 5~8px）。于是摆角只能压在 12.5° 以内 ——
    #   等于没有挥爪，玩家看到的就是「腿不动，身体在缩」。
    #   改成「圆盘内全归腿」之后，腿的上边界就是圆弧本身：圆弧绕自己的圆心旋转
    #   形状不变，body 挖的正是同一个圆，所以**转任意角度都恰好填满，不会露背景**。
    #   代价是圆盘里那一小块躯干肉会跟着腿转（赛璐璐平涂 + 实际显示只有十几像素，
    #   看不出来），换腿能挥 45° 是值得的。
    for name, cfg in LEGS.items():
        jx, jy = cfg["jo"]
        # 半径收到「圆盘内没有背景」为止（见 safe_disk_radius）——
        # 配置里的 r 只是上限，实际用多少由图像决定
        r = safe_disk_radius(alpha, jx, jy, float(cfg["r"]))
        LEG_R[name] = r
        cut_y = jy + r                      # 圆盘下沿：再往下才是腿身
        ys_c = [p[0] for p in cfg["edge"]]
        x0s = [p[1] for p in cfg["edge"]]
        x1s = [p[2] for p in cfg["edge"]]
        x0 = np.interp(yy[:, 0], ys_c, x0s)[:, None]
        x1 = np.interp(yy[:, 0], ys_c, x1s)[:, None]
        band = alpha & (yy >= cut_y) & (xx >= x0) & (xx <= x1)
        # ⚠ 圆盘部分是**几何圆**，不能写 `alpha & disk` —— 圆盘内原本是背景的像素在
        #   原始 alpha 里是 0，那样 mask 就把它们挡掉了，`fill_disk_holes` 填的颜色
        #   根本进不了贴图，圆盘内仍有一个缺口，腿一转就露洞（实测 4241px）。
        masks[name] = band | disk(alpha.shape, jx, jy, r)

    # ---- 尾巴：逐行右边界圈选（见 TAIL_EDGE 注释），再按中线分两段 ----
    edge_x = np.interp(yy[:, 0], [p[0] for p in TAIL_EDGE], [p[1] for p in TAIL_EDGE])[:, None]
    tail_all = alpha & (yy >= TAIL_EDGE[0][0]) & (xx < edge_x)
    d_a = dist_to_polyline(xx, yy, TAIL_SPINE[:TAIL_SPLIT_IDX + 1])
    d_b = dist_to_polyline(xx, yy, TAIL_SPINE[TAIL_SPLIT_IDX:])
    t1 = tail_all & (d_a <= d_b)
    t2 = tail_all & (d_b < d_a)
    j1 = TAIL_JO
    j2 = TAIL_SPINE[TAIL_SPLIT_IDX]
    # 两节之间是「尾根让出中关节圆盘、中关节的圆盘填进来」—— 旋转时接缝处不会露硬切边
    disk1 = alpha & disk(alpha.shape, j1[0], j1[1], TAIL_R)
    disk2 = alpha & disk(alpha.shape, j2[0], j2[1], TAIL_R2)
    masks["tail1"] = (t1 | disk1) & ~disk2
    masks["tail2"] = (t2 | disk2) & ~disk1

    # ---- 头：手工多边形 + 颈部圆盘（圆盘那圈让出来给头，旋转时它填满 body 的洞）----
    poly = Image.new("L", (w, h), 0)
    ImageDraw.Draw(poly).polygon(HEAD_POLY, fill=255)
    hx, hy = HEAD_JO
    masks["head"] = (alpha & (np.array(poly) > 0)) | (alpha & disk(alpha.shape, hx, hy, HEAD_R * 0.55))

    # ---- body：挖掉所有部件，**但把腿根留在躯干轮廓内** ----
    #
    # 这一步是「关节不露白缝」的最终解。前面试过两条路，都不行：
    #   ① 全挖（含腿身）→ 腿转走后原位置空一块，露出背景 = 白缝（游戏尺寸下清晰可见）
    #   ② 全留（只挖圆盘）→ body 上有四条灰扑扑的残影腿，比白缝更难看
    # 现在取中间：**腿根（躯干轮廓 + ROOT_KEEP px 以内）留在 body，其余挖掉**。
    #   · 腿根残影是毛色，且被躯干包住 → 融得进去，看着像「躯干下缘的腿根」
    #   · 腿上段转走后的位置在躯干轮廓之外 → 那里 body 本来就没有像素（背景）→ 不会露洞
    raw_acc = np.zeros_like(alpha)
    for m in masks.values():
        raw_acc |= m
    body_core = alpha & ~raw_acc

    # 躯干主体的连通块（去掉腿之后 body 可能是几块，取最大那块当躯干）
    lab0, cnt0 = ndimage.label(body_core)
    if cnt0 > 1:
        sizes0 = ndimage.sum(body_core, lab0, index=np.arange(1, cnt0 + 1))
        torso = (lab0 == int(np.argmax(sizes0)) + 1)
    else:
        torso = body_core

    # 腿根保留区：躯干轮廓向外 ROOT_KEEP px，且必须本来就是腿的像素
    near_torso = ndimage.binary_dilation(torso, ndimage.generate_binary_structure(2, 2),
                                         iterations=ROOT_KEEP)
    leg_any = np.zeros_like(alpha)
    for name in LEGS:
        leg_any |= masks[name]
    keep = near_torso & leg_any & alpha

    # ⚠ 挖洞形状必须**高斯平滑**：腿的 mask 边界是折线（band 的左右界 + cut_y 的水平线），
    #   直接用它在 body 上挖洞，洞的边缘就是硬直线和直角。腿一转开，这些直角就露在
    #   背景里 —— 看起来就是「关节处裂了一条直线」（实测放大后是明显的台阶）。
    #   sigma=4 把折线抹成圆角，视觉上像自然的缝隙；顺带让洞比腿小一点，
    #   腿的边缘能盖住洞口。
    hole = raw_acc & ~keep
    soft = ndimage.gaussian_filter(hole.astype(np.float32), sigma=4.0)
    body = alpha & (soft < 0.5)
    if keep.any():
        print(f"  腿根保留 {int(keep.sum())} px（躯干外扩 {ROOT_KEEP}px 内），避免转走后露白缝")

    body_rgba = rgba

    lab, cnt = ndimage.label(body)
    if cnt > 1:
        sizes = ndimage.sum(body, lab, index=np.arange(1, cnt + 1))
        main_id = int(np.argmax(sizes)) + 1
        moved = 0
        for i in range(1, cnt + 1):
            if i == main_id:
                continue
            comp = (lab == i)
            if int(comp.sum()) < 150:
                body = body & ~comp          # 毛发碎点，丢掉
                continue
            best_k, best_ov = None, 0
            for k, m in masks.items():
                ov = int((comp & m).sum())
                if ov > best_ov:
                    best_ov, best_k = ov, k
            if best_k is not None and best_ov > 0:
                masks[best_k] = masks[best_k] | comp
                moved += 1
            body = body & ~comp
        if moved:
            print(f"  body 的 {moved} 块孤立碎骨已归给相邻部件")

    masks["body"] = body

    # ---- 各部件向外溢 1px，与 body 的边界互相咬合，消掉白缝（见 dilate1 注释）----
    for k in list(masks.keys()):
        if k != "body":
            masks[k] = dilate1(masks[k])
    return masks, body_rgba


# ===================== 主流程 =====================


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description="把 BOSS 正侧定妆图拆成骨骼分件")
    ap.add_argument("--src", default=SRC, help="正侧定妆图（品红底）")
    ap.add_argument("--out", default=OUT_DIR, help="分件 + rig.tres 的输出目录")
    ap.add_argument("--preview", default=PREVIEW, help="分件着色预览图")
    args = ap.parse_args()

    img = Image.open(args.src).convert("RGB")
    img = img.crop((0, 0, img.size[0], img.size[1] - CROP_BOTTOM))
    rgba = np.array(gbf.key_out(img))

    alpha = rgba[..., 3] > 180
    ys, xs = np.nonzero(alpha)
    bx0, bx1, by0, by1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    bw, bh = bx1 - bx0 + 1, by1 - by0 + 1
    print(f"源图 {img.size[0]}x{img.size[1]}  主体 bbox x{bx0}..{bx1} y{by0}..{by1}  ({bw}x{bh})")

    # ---- 整体缩放到「内容高 CONTENT_H、脚底落在 baseline」----
    s = CONTENT_H / float(bh)
    left = FRAME_W * 0.5 - bw * s * 0.5
    top = (FRAME_H - FOOT_MARGIN) - CONTENT_H
    print(f"缩放 {s:.4f}  →  画布 {FRAME_W}x{FRAME_H} 内 内容 {bw*s:.0f}x{CONTENT_H:.0f}  "
          f"左上角 ({left:.0f}, {top:.0f})  脚底 y={FRAME_H - FOOT_MARGIN}")

    # ⚠ 画布坐标再减掉画布中心：rig 节点的原点必须与 SkinVisual 的口径一致
    #   （序列帧的 _raw_half_size 就是画布的一半），否则整只虎会整体偏移半个画布。
    def to_canvas(px: float, py: float) -> tuple[float, float]:
        return ((px - bx0) * s + left - FRAME_W * 0.5,
                (py - by0) * s + top - FRAME_H * 0.5)

    part_imgs: dict[str, Image.Image] = {}
    part_meta: dict[str, dict] = {}

    def emit(name: str, mask: np.ndarray, joint_src: tuple[float, float] | None,
             parent: str | None, z: int, src: np.ndarray | None = None) -> None:
        m8 = (mask.astype(np.uint8) * 255)
        # src 用于「颜色已被单独处理过」的部件：腿要圆盘填充色，body 要抹平的腿身
        piece = (rgba if src is None else src).copy()
        piece[..., 3] = np.minimum(piece[..., 3], m8)
        ys2, xs2 = np.nonzero(piece[..., 3] > 8)
        if len(ys2) == 0:
            raise RuntimeError(f"{name} 切出来是空的 —— 关节/区间参数错了")
        x0, y0 = int(xs2.min()), int(ys2.min())
        x1, y1 = int(xs2.max()) + 1, int(ys2.max()) + 1
        crop = Image.fromarray(piece[y0:y1, x0:x1], "RGBA")

        # 缩放到画布口径
        nw, nh = max(1, round(crop.size[0] * s)), max(1, round(crop.size[1] * s))
        crop = crop.resize((nw, nh), Image.LANCZOS)

        cx, cy = to_canvas((x0 + x1) * 0.5, (y0 + y1) * 0.5)
        jx, jy = (0.0, 0.0) if joint_src is None else to_canvas(*joint_src)
        part_imgs[name] = crop
        part_meta[name] = {
            "tex": f"{name}.png",
            "parent": parent,
            "joint": [round(jx, 2), round(jy, 2)],          # 相对 rig 原点（= 画布中心）
            "offset": [round(cx - jx, 2), round(cy - jy, 2)],  # 贴图中心相对关节
            "size": [nw, nh],
            "z": z,
        }
        print(f"  {name:<14} {nw:4d}x{nh:<4d}  关节 ({jx:6.1f},{jy:6.1f})  "
              f"offset ({cx-jx:+7.1f},{cy-jy:+7.1f})  z={z:+d}")

    print("切件：")
    masks, body_rgba = build_masks(rgba)
    for name in LEGS:
        print(f"  圆盘半径 {name:<14} 配置 {LEGS[name]['r']:>3} → 实际 {LEG_R[name]:.0f}")

    # 层级：body 是唯一的躯干根，**所有部件都挂在它下面** —— 躯干起伏 / 俯仰时
    # 头、尾、四条腿必须跟着一起走，否则连接处会裂开。
    # 例外是 tail2：挂在 tail1 下，尾巴前段一摆后段自动跟随（两节链）。
    emit("tail1", masks["tail1"], TAIL_JO, "body", -2)
    emit("tail2", masks["tail2"], TAIL_SPINE[TAIL_SPLIT_IDX], "tail1", -2)

    for name in ("leg_far_hind", "leg_far_front"):
        jx, jy = LEGS[name]["jo"]
        emit(name, masks[name], (jx, jy), "body", LEGS[name]["z"],
             src=fill_disk_holes(rgba, jx, jy, LEG_R[name]))

    emit("body", masks["body"], None, None, 0, src=body_rgba)
    emit("head", masks["head"], HEAD_JO, "body", 1)

    for name in ("leg_near_hind", "leg_near_front"):
        jx, jy = LEGS[name]["jo"]
        emit(name, masks[name], (jx, jy), "body", LEGS[name]["z"],
             src=fill_disk_holes(rgba, jx, jy, LEG_R[name]))

    # ---- 写盘 ----
    os.makedirs(args.out, exist_ok=True)
    for name, im in part_imgs.items():
        im.save(os.path.join(args.out, f"{name}.png"))

    order = ["leg_far_hind", "leg_far_front", "tail1", "tail2", "body", "head",
             "leg_near_hind", "leg_near_front"]

    # ⚠ 用 .tres 不用 .json：res:// 下的 .json 不保证被打进导出包（非资源文件默认
    #   不导出），.tres 是标准资源，导出与依赖追踪都没问题。
    def sarr(items):
        return "PackedStringArray(" + ", ".join('"%s"' % s for s in items) + ")"

    def varr(items):
        flat = []
        for v in items:
            flat.extend(v)
        return "PackedVector2Array(" + ", ".join("%.2f" % v for v in flat) + ")"

    res_path = "res://" + args.out.replace("\\", "/") + "/"
    tres = [
        '[gd_resource type="Resource" script_class="BossRigData" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/data/boss_rig_data.gd" id="1_rig"]',
        "",
        "[resource]",
        'script = ExtResource("1_rig")',
        "canvas = Vector2i(%d, %d)" % (FRAME_W, FRAME_H),
        "order = " + sarr(order),
        "part_name = " + sarr(order),
        "part_tex = " + sarr([res_path + part_meta[n]["tex"] for n in order]),
        "part_parent = " + sarr([part_meta[n]["parent"] or "" for n in order]),
        "part_joint = " + varr([part_meta[n]["joint"] for n in order]),
        "part_offset = " + varr([part_meta[n]["offset"] for n in order]),
        "part_z = PackedInt32Array(" + ", ".join(str(part_meta[n]["z"]) for n in order) + ")",
        "muzzle_anim = " + sarr(list(MUZZLE)),
        "muzzle_part = " + sarr([MUZZLE[k][0] for k in MUZZLE]),
        "muzzle_offset = " + varr([MUZZLE[k][1] for k in MUZZLE]),
        "",
    ]
    with open(os.path.join(args.out, "rig.tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(tres))

    # ---- 分件着色预览：每块一个色相，肉眼检查切缝有没有漏 / 有没有互吃 ----
    colors = [(60, 130, 255), (255, 90, 90), (90, 210, 120), (255, 190, 60),
              (200, 100, 255), (60, 220, 220), (255, 120, 200), (150, 150, 90)]
    prev = Image.new("RGB", (FRAME_W, FRAME_H), (250, 250, 250))
    for i, name in enumerate(order):
        meta = part_meta[name]
        piece = part_imgs[name]
        # joint / offset 都是「相对 rig 原点（画布中心）」的，预览画布是绝对坐标，要加回来
        px = int(round(FRAME_W * 0.5 + meta["joint"][0] + meta["offset"][0] - piece.size[0] * 0.5))
        py = int(round(FRAME_H * 0.5 + meta["joint"][1] + meta["offset"][1] - piece.size[1] * 0.5))
        tint = np.array(piece).copy()
        c = colors[i % len(colors)]
        tint[..., :3] = (tint[..., :3] * 0.35 + np.array(c, np.float32) * 0.65).astype(np.uint8)
        prev.paste(Image.fromarray(tint, "RGBA"), (px, py), Image.fromarray(tint, "RGBA"))
    d = ImageDraw.Draw(prev)
    for name, meta in part_meta.items():
        jx = FRAME_W * 0.5 + meta["joint"][0]
        jy = FRAME_H * 0.5 + meta["joint"][1]
        d.ellipse([jx - 6, jy - 6, jx + 6, jy + 6], outline=(0, 0, 0), width=2)
        d.text((jx + 8, jy - 5), name, fill=(0, 0, 0))
    d.line([(0, FRAME_H - FOOT_MARGIN), (FRAME_W, FRAME_H - FOOT_MARGIN)],
           fill=(255, 0, 0), width=1)
    prev.save(args.preview)
    print(f"预览 → {args.preview}")

    # ---- 自检：按 joint+offset 把各块拼回画布，与「缩放后的原图」比 IoU ----
    # 切件最常见的失误是「某块少了一角 / 两块抢同一片像素」，肉眼看预览很难发现，
    # 但拼回去一减法就现形。判据用二值 alpha 的 IoU 而不是逐像素差 ——
    # 原图与分件各做过一次 LANCZOS 缩放，边缘振铃会让逐像素差虚高到 50%。
    recon = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    for name in order:
        meta = part_meta[name]
        piece = part_imgs[name]
        px = int(round(FRAME_W * 0.5 + meta["joint"][0] + meta["offset"][0] - piece.size[0] * 0.5))
        py = int(round(FRAME_H * 0.5 + meta["joint"][1] + meta["offset"][1] - piece.size[1] * 0.5))
        recon.alpha_composite(piece, (px, py))
    ref = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    # ⚠ 必须裁到主体 bbox 再缩放 —— 直接缩整图会得到 (1058,560) 的「全图」，
    #   而 recon 是 bbox 口径的 (1058,560) 的「虎」，两者根本不同源，IoU 会假跌到 65%。
    sub = rgba[by0:by1 + 1, bx0:bx1 + 1]
    scaled = Image.fromarray(sub, "RGBA").resize(
        (max(1, round(bw * s)), max(1, round(bh * s))), Image.LANCZOS)
    ref.alpha_composite(scaled, (int(round(left)), int(round(top))))
    rm = np.array(recon)[..., 3] > 128
    fm = np.array(ref)[..., 3] > 128
    inter = int((rm & fm).sum())
    union = int((rm | fm).sum()) or 1
    iou = inter / float(union)
    print(f"自检 拼回 IoU {iou * 100:.2f}%  （单块面积占比 缺 {100*(1-inter/max(int(fm.sum()),1)):.2f}%）")
    if iou < 0.95:
        print("  ! 切件有遗漏或重复 —— 检查 LEGS 的 x 区间 / TAIL_EDGE 是否覆盖完整")
    print(f"完成：{len(part_imgs)} 块 → {args.out}/  (rig.tres 已生成)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
