#!/usr/bin/env python
"""从刀客侧身定妆图拆出人形骨骼分件（供 BossRigHuman 做骨骼动画）。

## 与虎妖（build_tiger_rig.py）的差别

虎妖是四足，拆件按「逐行 alpha 扫出的腿带」切。刀客是人形持刀：
持刀臂 + 两条腿 + 躯干，全部用**折线带（ribbon）/ 多边形**圈选 ——
人形肢体细长弯曲，逐行扫容易被斗篷和衣摆打断，沿中心线量距离反而最稳。

## 为什么**没有**单拆一个头

第一版按虎妖的思路拆了 `head`（脖子为轴），结果画面里出现**两个头**：
`HEAD_POLY` 只圈住了一小块，剩下大半个头留在 body 里 —— 头一转，body 里那颗
不动，看起来就是「影分身」。人形 BOSS 的头本来也只做 1° 级微动，收益远小于
风险，所以**头并入躯干**：躯干的旋转/挤压带着头一起动，已经够「活」了。

## 刀为什么挂在手臂上而不是单独一块

原画里刀柄是**握在手里**的，手和刀柄的像素互相咬合。拆成两块的话，刀一转，
手指就会脱离刀柄、或者刀柄从拳心滑出来 —— 这就是「握不住」的观感。
大刀的挥砍本来就靠肩关节发力，所以整条臂 + 刀做成一块，肩为轴。

## ⚠ 刀身压在头上 / 手臂压着胸口，这些被盖住的像素必须**补画**

手臂是独立刚体，一挥开，它原来占的地方就露出来了。如果那里是透明的洞，
玩家会看到「胸口破了个洞」；如果 body 里保留了原像素，挥刀时会看到
「另一把不动的刀 / 另一条不动的手臂」。所以 body 上的这些区域用**最近色补画**
（`inpaint`）—— 补出来是一片相近的暗色布料，25% 缩放的实机尺寸看不出破绽。

## 坐标口径

⚠ 本脚本**先把图缩到画布**（900×720、内容高 590、脚底 y=700，与
`gen_boss_sprite_frames.compose` 完全一致），再在画布坐标里切。
所有解剖参数都是**画布像素**，与叠网格的参考图 1:1 对得上。
上一版在源图坐标里写参数、再做一次坐标换算，读错一次缩放比就整套偏了半个身位 ——
所以这里宁可多占点内存，也要让「看图的坐标」= 「写下的坐标」。

用法：
    python tools/build_daoke_rig.py
输出：
    assets/characters/boss/daoke_rig/<part>.png       分件贴图（已是画布分辨率）
    assets/characters/boss/daoke_rig/rig.tres         骨骼数据（BossRigData）
    vibe_images/boss_work/boss_daoke/rig_preview.png  分件着色预览
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# 复用虎妖管线的通用几何工具（纯函数，不会触发它自己的 main）
from build_tiger_rig import dilate1, disk, dist_to_polyline, fill_disk_holes, safe_disk_radius  # noqa: E402

# ===================== 输入 / 输出 =====================

## 定妆图：刀客「垂刀式」立绘（右手垂到腰侧握柄、刀身向前下方悬着）
## ⚠ 必须是**侧身**姿势。idle 那张姿势表是正面站姿，拆出来的臂和腿都没法转。
## ⚠ 2026-10-26 换姿势：原来是「刀横扛在肩上」，每次挥刀都得先把刀从肩上抬开，
##   起手那半秒看着像挠痒。垂刀式起手就在下劈轨迹上，挥刀才是「直接劈出去」。
## 图是图像模型出的品红底图，`--key` 现场抠图（口径与序列帧管线同一个 key_out），
## 所以 SRC 直接指向原始生成图，不留中间产物 —— 中间产物一丢就得靠记忆重做。
SRC = "vibe_images/daoke_rig_垂刀B_锁刀形_1793011043302_50c983e6.png"
OUT_DIR = "assets/characters/boss/daoke_rig"
PREVIEW = "vibe_images/boss_work/boss_daoke/rig_preview.png"

# 与刀客序列帧完全同口径：帧 900×720 / 内容高 590 / 脚底 y=700（FOOT_MARGIN=20）
FRAME_W, FRAME_H = 900, 720
CONTENT_H = 590.0
FOOT_MARGIN = 20
RIG_SCRIPT = "res://scripts/visual/boss_rig_human.gd"

# ===================== 解剖参数（**画布坐标**）=====================
# ⚠ 换定妆图必须重读这些数：体形一变，圆盘就落到肉外面，一转身直接断肢。
#   读法：把缩到画布的图叠 50px 网格，直接读格线。
#   垂刀式这版的读数来源：逐行 alpha 游程（分腿/分刀）+ 刀色掩码（银脊 + 红刃
#   两种配色，逐行只落在刀刃左右两条边上）+ 2~3 倍放大格线图，三者互相校对。

## 肩关节（整条持刀臂 + 刀绕它转）。⚠ 必须落在肩窝里，不能落在肩甲中心
##   垂刀式：上臂皮肤左缘 x=378@y260、右缘（肌肉与胸口交界）x=430 → 轴心 404
##   y 从 258 抬到 238：肩甲现在是**不转的独立件**（见 PAULDRON_POLY），
##   肩盘必须整个藏在它下面才不会转出一块金色的糊。盘底 238+24=262，
##   实测肩甲下沿（皮肤起于的那条弧）在 x 390~440 之间是 y 252~269 → 盖得住。
SHOULDER = (408, 238)
SHOULDER_R = 24
## 髋关节（腿绕它转）。⚠ 放在裙摆内部（那里全是实心），圆盘才不会缩到没肉
## ⚠ 命名口径：**front = 朝向前方那条腿**（美术朝右，所以是画布右侧那条）。
##   这里出过一次错：按「图左 / 图右」随手命名，结果 front 实际是后腿 ——
##   突进斩里「前腿迈出去」变成后腿往前甩，看着像在倒退。
## ⚠ 垂刀式的刀身正好从后腿髋部（旧值 388,468）穿过去：盘心压在刀上，
##   后腿一转就会带走一坨刀色像素。所以两个髋盘都往中间收，绕开刀（刀在 y470
##   处占 x 365~405）；实测 safe_disk_radius 会把上限自动削到真正塞得下的半径。
HIP_FRONT = (524, 474)
HIP_BACK = (452, 476)
HIP_R = 40
## 裙摆下沿（画布 y）。髋部以上只挖圆洞，以下才按腿形挖 —— 见 body 那段注释。
HEM_Y = 582

## 持刀臂拆两段：上臂（肩→肘）+ 前臂（肘→拳，含刀）。
##
## ⚠ 2026-10-26 用户要求「给肘关节也加骨骼」：整条臂焊死在一块里，挥刀只能是
##   「整条刚体绕肩转」—— 扛在肩上直接往下抡，不符合人体动作。真人发力是
##   **肘先收、手领先甩出去、刀跟着走**（鞭打）。所以臂在肘部断开：
##   上臂绕肩转，前臂（含手和刀）绕肘转，肘用实心圆盘承接（同腿/肩的零缝做法）。
## 臂轴实测（左缘/右缘取中）：(404,260) → (388,318) → (376,386) → (372,428)，
## 全臂宽约 50px → 胶囊半径取 26~30，宁小勿大：大了就把胸口的布料卷进手臂。
ARM_UPPER_SEGS = [
    (((408, 238), (390, 318)), 30),   # 上臂（肩 → 肘）
]
ARM_FORE_SEGS = [
    (((390, 316), (376, 386)), 28),   # 前臂（黑护腕）
    (((376, 384), (372, 430)), 26),   # 拳（握刀处）
]

## 肘关节（前臂绕它转）。⚠ 必须落在肘窝里：上臂在肘盘边界截断成圆弧，
##   前臂带**同半径实心圆盘**，转任何角度盘都正好盖满截口 → 零缝。
##   换定妆图必须重读：盘心落到肉外，前臂一转就断肢。
## ⚠ 垂刀式的肘在皮肤与护腕的交界（y≈318）。盘的左边界受臂的左缘限制
##   （y=300 处左缘 371，y=318 处 365），所以半径只能到 24 左右 —— 比臂的
##   半宽还小一点，截口靠「最近轴心」判据补齐，实测 ±90° 不露缝即可接受。
ELBOW = (392, 318)
ELBOW_R = 26

## 手臂的外轮廓多边形（肩甲 + 大袖 + 拳头）。
## ⚠ 只靠折线带不够：折线带是**沿中心线的胶囊**，肩甲那一块（金色护肩，比手臂宽一倍）
##   会漏在 body 里 —— 挥刀时画面上会留下一块「金色的肩甲残影」。
##   这个多边形是照放大格线图实测轮廓描的，换定妆图必须重描。
## 垂刀式：肩甲（金 + 黑羽饰）占 x 378~476 / y 194~274。
ARM_BLOB = [
    (392, 206), (416, 194), (446, 194), (468, 208), (476, 230), (470, 252),
    (452, 268), (428, 274), (406, 270), (388, 256), (380, 236), (384, 216),
]

## 肩甲（金色狮头 + 黑色甲裙 + 皮扣带）——**单独一块、挂在 body 上、不参与旋转**。
##
## ⚠ 为什么不能留在上臂里（2026-10-26 实测）：肩甲比上臂宽一倍，跟着上臂绕肩转
##   到 +45° 就已经滑到肱二头肌上，+80° 直接掉到肘部，原来肩头只剩一块重涂的糊。
##   真人是「甲压着肩、胳膊在甲底下转」，所以甲必须是不转的那一层，而且 z 要**高于
##   上臂**（否则肩盘那 48px 圆会画在甲上面转出糊来）、**低于前臂**（否则举手护脸时
##   手会插到甲后面去）。
## ⚠ 下沿只能压到肩盘底（y≈262）附近：再往下就把皮肤圈进不转的甲里，胳膊一甩
##   会留下一块不动的肤色补丁；再往上则盖不住盘，盘边一转就在甲底下甩出金色糊。
##   下沿是逐列探「第一个连续 4px 肤色」量出来的（x 388→470：250/260/265/269/266/258/246）。
## ⚠ 上沿/右沿必须**盖住 ARM_BLOB**，否则 ARM_BLOB 里那些被甲抢走的像素会掉出
##   上臂又没人认领 —— 拆件自检报孤岛，静止帧上就是一个洞。
PAULDRON_POLY = [
    (384, 216), (392, 206), (416, 194), (446, 194), (468, 208), (476, 228),
    (470, 246), (452, 258), (432, 269), (414, 265), (400, 260), (388, 248),
]
## 肩甲的「关节」。它永远不转，这个点只参与 offset 的加减，取多边形中心即可。
PAULDRON_JOINT = (431, 231)

## 刀：柄 + 首 + 镡 + 身，一整块（全归前臂）。用多边形而不是折线带 ——
## 刀身是弯的、根部宽尖端窄，一个恒定半径的胶囊要么切掉刀尖、要么啃掉护肩。
## ⚠ 必须**一直包到刀首（金球）**：漏了它，刀首就留在 body 里，
##   挥刀时画面上会有一个金色小球悬在原地（第一版就是这个 bug）。
## ⚠ 环的走向：刀首 → 刀柄右侧 → 刀镡 → **刀背**（右缘）一路到刀尖 →
##   沿**刀刃**（左缘）回到刀镡 → 刀柄左侧收口。上下缘一旦交叉，
##   `ImageDraw.polygon` 会填出一块乱七八糟的形状。
## 两条缘的坐标是「刀色掩码」逐行量出来的（银脊 = 刀背侧高光，红晕 = 刀刃）：
##   刀背 x 400@460 → 421@510 → 452@570 → 464@600 → 500@660 → 516@680 → 尖 527@690
##   刀刃 x 362@455 → 375@510 → 396@570 → 407@600 → 436@660 → 452@680 → 尖 467@690
## ⚠ **描出来的缘要往外让 4~5px**，不能贴着走。第一版贴着实测缘写，结果
##   body 里留下一条 1~2px 宽、从裙摆一直延伸到刀尖的刀刃亮边（量到 y 596~692
##   每行都还有 1~2 个像素）—— 静止帧完全看不出来（前臂 z 最高，压在上面），
##   刀一挥开就是一条悬空发光的弧线。宁可让刀多吃几像素布边，也不能留亮边。
SWORD_POLY = [
    # 刀首 + 刀柄右侧（自上而下）
    (324, 332), (350, 326), (358, 347), (370, 371), (382, 399), (395, 423),
    # 刀镡（护手）
    (414, 431), (422, 452), (411, 471),
    # 刀背（右缘）到刀尖
    (419, 500), (429, 530), (443, 556), (457, 578), (471, 604), (485, 630),
    (501, 654), (519, 676), (536, 693),
    # 刀底 + 刀刃（左缘）回到刀镡
    (516, 703), (484, 701), (460, 694), (439, 674), (425, 652), (413, 626),
    (401, 598), (389, 568), (377, 538), (367, 508), (359, 480),
    # 刀镡左侧 + 刀柄左侧回到刀首
    (346, 462), (336, 434), (330, 404), (322, 378), (314, 355), (316, 338),
]

## 手臂「压在躯干上」的那一块（躯干侧）。
##
## ⚠ 手臂的处理要分两半，这是整条管线里最反直觉的一处：
##   · **压在躯干上的部分** → body 里保留、颜色重涂（`inpaint`）。
##     不留的话手臂一挥开，胸口就是一个背景色的洞。
##   · **压在背景上的部分**（刀身探出裙摆、刀首伸到身体左边）→ body 里**挖掉**。
##     保留的话，挥刀后原位会留一片「悬在空中的刀/拳头」。
##   分界线就是这些多边形：只有落在它们里面的手臂像素才被 body 保留。
## 垂刀式不再有「刀压过头顶」的问题（刀整个在身体下方），所以旧版的
## BUN_POLY / HAIR_KEEP_ZONE 一并删掉 —— 留着反而会把头发圈进手臂重涂区。
ARM_KEEP_ZONES = [
    # 肩甲 + 上臂 + 前臂 + 拳压在胸口/披风上的部分。
    # ⚠ 左边界在 y 330~372 之间要**内缩到 x≈358**：刀首（x 322~350）和身体之间
    #   有一条透明缝，把刀首圈进保留区，挥刀后那里会留一颗悬空的金球补丁。
    [(392, 196), (478, 206), (500, 252), (492, 322), (472, 400), (452, 472),
     (400, 478), (352, 442), (344, 396), (356, 372), (360, 330), (372, 268),
     (380, 222)],
    # 刀身压过裙摆的那一段。裙摆（HEM_Y=582）以下刀是悬在两条腿之间的背景里，
    # 必须留洞，所以下边界就切在 586。
    [(348, 440), (424, 440), (456, 496), (478, 560), (478, 588), (396, 588),
     (372, 540), (352, 486)],
]

## 腿：髋 → 膝 → 脚。靴子比小腿宽，所以脚那一段单独给大半径
## 每条腿的兜底包围盒（**只取裙摆以下**）。折线带在靴尖/靴跟会漏几像素，
## 漏掉的那片会留在 body 里 —— 腿一摆就成了「飘在地面的鞋尖」。盒子兜住它。
## ⚠ 上边界必须压在裙摆以下（垂刀式 y=582），否则会把裙子布料带进腿部。
## ⚠ 后腿盒子的右边界 400：刀在 y=582 处占 x 399~454。留到 396 的话，腿和刀之间
##   会空出 2~3px 谁都不认领的布料，那几条像素留在 body 里不跟着腿转。
##   多吃 1px 刀边没关系 —— leg_cover 会把被刀压住的像素补画成腿色。
LEG_FRONT_BOX = (522, 582, 662, 700)
LEG_BACK_BOX = (300, 582, 400, 700)

## ⚠ 折线带只在裙摆以下参与切件（见 main 里的 `ribbon & below_hem`）。
##   髋盘（y≈434~516）与裙摆（y≥582）之间那段大腿本来就被裙子盖着，
##   让胶囊去圈它等于把腰封、红绦的布料登记成「腿」—— 腿一转，一块红绦
##   跟着甩。留缺口没关系：那块区域 body 没被挖（洞只挖裙摆以下），
##   裙子照样画在上面。
LEG_FRONT_SEGS = [
    (((524, 474), (562, 566)), 38),
    (((562, 566), (580, 624)), 34),
    (((580, 624), (642, 660)), 44),
]
LEG_BACK_SEGS = [
    (((452, 476), (378, 566)), 38),
    (((378, 566), (352, 624)), 34),
    (((352, 624), (316, 664)), 42),
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


def fill_color(rgba: np.ndarray, hole: np.ndarray, src: np.ndarray) -> np.ndarray:
    """把 hole 里 alpha=0 的像素用最近的 src 实心像素颜色填上（保持不透明）。

    用途：手臂从躯干上拆走后，body 上会留一个**手臂形状的洞**。手臂一转开，
    洞就露在胸口 —— 背景色直接透出来，比白缝还刺眼。用邻近颜色填平后，
    看到的是「被手臂挡住的胸口」，转开也只是一片相近的暗色。
    """
    from scipy import ndimage
    holes = hole & (rgba[..., 3] < 40)
    solid = src & (rgba[..., 3] >= 40)
    if not holes.any() or not solid.any():
        return rgba
    _, idx = ndimage.distance_transform_edt(~solid, return_indices=True)
    out = rgba.copy()
    ys, xs = idx[0][holes], idx[1][holes]
    out[holes, :3] = rgba[ys, xs, :3]
    out[holes, 3] = 255
    return out


def inpaint(rgba: np.ndarray, hole: np.ndarray, keep: np.ndarray,
            margin: int = 6, blur_sigma: float = 5.0) -> np.ndarray:
    """把 hole 里的像素用**附近颜色**补出来（不透明）。

    ⚠ 和上面的 `fill_color` 不是一件事：那个只补 alpha=0 的**透明洞**；这里补的是
    **被别的部件盖住的、原本有像素**的区域（手臂压着胸口、刀身压着头发）。
    不补的话，部件一挥开就露出「空洞」；把原像素留在 body 里则会看到「另一把不动的刀」。

    `margin`：取色时跳过紧贴 hole 边缘的一条带。不做这一步，补出来的颜色会混进
    隔壁部件自己的颜色（比如刀的金属灰），补丁看着像一块脏污。
    `blur_sigma`：最近色填充在**大区域**上是一圈圈放射状条纹（每个洞像素取的是
    最近边缘像素的颜色），糊一下之后变成柔和的暗色渐层，读起来像「阴影里的衣料」。
    """
    from scipy import ndimage
    src_zone = alpha_keep = keep
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
    ap = argparse.ArgumentParser(description="把刀客定妆图拆成骨骼分件")
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", default=PREVIEW)
    ap.add_argument("--no-key", action="store_true",
                    help="输入已经是抠好底的 RGBA（默认按品红底现场抠图）")
    args = ap.parse_args()

    src = Image.open(args.src).convert("RGBA")
    if not args.no_key:
        # 与序列帧管线共用同一个 key_out：excess = min(r,b) - g，
        # 暗色布料（r≈g≈b）不会被误抠掉，半透明边缘能精确还原。
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from gen_boss_sprite_frames import key_out
        src = key_out(src)
    src = np.array(src)

    # ---- 缩到画布（口径与序列帧一致）----
    a0 = src[..., 3] > 180
    ys, xs = np.nonzero(a0)
    bx0, bx1, by0, by1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    bw, bh = bx1 - bx0 + 1, by1 - by0 + 1
    s = CONTENT_H / float(bh)
    left = FRAME_W * 0.5 - bw * s * 0.5
    top = (FRAME_H - FOOT_MARGIN) - CONTENT_H
    print(f"源图 {src.shape[1]}x{src.shape[0]} bbox ({bw}x{bh}) 缩放 {s:.4f} "
          f"→ 画布内左上 ({left:.1f},{top:.1f}) 脚底 y={FRAME_H - FOOT_MARGIN}")

    big = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    crop = Image.fromarray(src[by0:by1 + 1, bx0:bx1 + 1], "RGBA")
    crop = crop.resize((max(1, round(bw * s)), max(1, round(bh * s))), Image.LANCZOS)
    big.alpha_composite(crop, (int(round(left)), int(round(top))))
    rgba = np.array(big)
    alpha = rgba[..., 3] > 180
    shape = (FRAME_H, FRAME_W)
    ## 裙摆以下才是「腿自己说了算」的区域：以上全被裙子盖着（见 LEG_*_SEGS 的注释）。
    below_hem = np.zeros(shape, dtype=bool)
    below_hem[HEM_Y:, :] = True

    masks: dict[str, np.ndarray] = {}
    # 部件清单 = 写盘顺序 = 自检遍历顺序，三处共用一份，别再复制第二份。
    order = ["leg_back", "body", "leg_front", "arm", "pauldron", "arm_fore"]

    # ---- 手臂拆两块：上臂（肩盘）+ 前臂（肘盘 + 刀）----
    # ⚠ 刀身**只归前臂**（手握刀，刀跟着手走）。第一版曾让头也保留刀身像素，
    #   结果挥刀时画面上有**两把刀**。刀的优先级最高，这条不变。
    # 归属判定：臂区域里「离前臂中心线比上臂近」的像素归前臂，其余归上臂；
    # 肘盘整体归前臂（实心圆盘），上臂在盘边界截断 —— 前臂转到任何角度，
    # 盘都正好盖满上臂的圆截口，肘部零缝。
    arm_region = alpha & (ribbon_multi(shape, ARM_UPPER_SEGS)
                          | ribbon_multi(shape, ARM_FORE_SEGS)
                          | poly_mask(shape, SWORD_POLY)
                          | poly_mask(shape, ARM_BLOB))
    arm_r = safe_disk_radius(alpha, SHOULDER[0], SHOULDER[1], SHOULDER_R)
    elbow_r = safe_disk_radius(alpha, ELBOW[0], ELBOW[1], ELBOW_R)
    print(f"  圆盘 arm        上限 {SHOULDER_R} → 实际 {arm_r:.0f}")
    print(f"  圆盘 arm_fore   上限 {ELBOW_R} → 实际 {elbow_r:.0f}")
    sword_m = alpha & poly_mask(shape, SWORD_POLY)
    yy_g, xx_g = np.mgrid[0:shape[0], 0:shape[1]]
    xf = xx_g.astype(np.float32)
    yf = yy_g.astype(np.float32)
    d_up = dist_to_polyline(xf, yf, list(ARM_UPPER_SEGS[0][0]))
    d_fore = np.minimum(
        dist_to_polyline(xf, yf, list(ARM_FORE_SEGS[0][0])),
        dist_to_polyline(xf, yf, list(ARM_FORE_SEGS[1][0])))
    arm_fore = (arm_region & (d_fore <= d_up)) | sword_m \
        | disk(shape, ELBOW[0], ELBOW[1], elbow_r)
    # 肩甲先从「臂」里摘出去再截断：留在上臂里，挥刀时整块甲会顺着胳膊掉到肘部。
    pauldron_m = alpha & poly_mask(shape, PAULDRON_POLY)
    arm = ((arm_region & ~arm_fore & ~pauldron_m)
           | disk(shape, SHOULDER[0], SHOULDER[1], arm_r))
    masks["arm"] = arm
    masks["arm_fore"] = arm_fore
    masks["pauldron"] = pauldron_m
    # ⚠ body 的挖除与补画都按**整条臂**（上臂 ∪ 前臂）算：拆两块只是动画结构，
    #   静止帧里它们拼起来还是原来那条臂 —— 按单块算会把另一块漏进 body，
    #   挥臂时画面上就出现「另一截不动的手臂」。
    #   腿也要吃这条：垂刀式的刀身正好压在两腿之间、擦着后腿裙摆下沿过去，
    #   腿件不减掉刀就会把一条刀形黑边登记成自己的像素。
    arm_all = arm | arm_fore

    leg_r = {}
    leg_cover: dict[str, np.ndarray] = {}
    for name, segs, jo in (("leg_front", LEG_FRONT_SEGS, HIP_FRONT),
                           ("leg_back", LEG_BACK_SEGS, HIP_BACK)):
        rr = safe_disk_radius(alpha, jo[0], jo[1], HIP_R)
        leg_r[name] = rr
        box = LEG_FRONT_BOX if name == "leg_front" else LEG_BACK_BOX
        bx = np.zeros(shape, dtype=bool)
        bx[box[1]:box[3], box[0]:box[2]] = True
        leg_m = ((alpha & ribbon_multi(shape, segs) & below_hem) | (alpha & bx)
                 | disk(shape, jo[0], jo[1], rr))
        masks[name] = leg_m
        # 被刀压住的腿部像素：**范围留给腿，颜色补画**。
        # 只减范围不补画 → 刀一挥开，腿上出现一个刀形的透明洞；
        # 只补画不减范围 → 静止帧没问题，但腿一转就带走一条刀色黑边。
        leg_cover[name] = leg_m & arm_all
        print(f"  圆盘 {name:<10} 上限 {HIP_R} → 实际 {rr:.0f}  被刀压住 {int(leg_cover[name].sum())}px")

    # ---- body（含头）：腿挖洞、手臂分两半（见 ARM_KEEP_ZONES）----
    #
    # ⚠ 三种处理方式，分界是「这块部件下面本来是身体还是背景」：
    #   · 腿：**挖成洞**。腿本身就是那里的轮廓，若 body 还留着原像素，
    #     腿一摆开就会露出「另一条不动的腿」＝鬼影。挖洞后露出背景，正确。
    #   · 压在躯干上的手臂/刀：**保留轮廓、重涂颜色**（`inpaint`）。
    #     挖洞的话手臂一挥开就露出背景（胸口破洞）；保留原像素则留下「另一条不动的刀」。
    #   · 压在背景上的手臂/刀：**挖掉**。否则挥刀后原位会留一片悬空残影。
    # ---- body 的腿洞：**髋部只挖圆盘，圆盘以下才按腿形挖** ----
    #
    # ⚠ 这是「走路关节缝隙」的正解。原来的洞 = 整条腿的形状，腿一转，
    #   裙摆里那半截洞就露出来了 —— 因为洞的形状跟着腿转不了，只有**圆**能。
    #   分界：
    #     · 圆盘（在裙摆里）→ 挖成圆洞，腿绕圆心转，任何角度都盖得满 → 零缝隙
    #     · 圆盘以下（裙摆外）→ 按腿形挖，露出来的正好是**背景**，看不出来
    #   一句话：**洞只在"洞外面是背景"的地方才允许是腿形。**
    leg_hole = np.zeros_like(alpha)
    for name, jo, rr in (("leg_front", HIP_FRONT, leg_r["leg_front"]),
                         ("leg_back", HIP_BACK, leg_r["leg_back"])):
        leg_hole |= disk(shape, jo[0], jo[1], rr) | (masks[name] & below_hem)
    keep_zone = np.zeros(shape, dtype=bool)
    for zp in ARM_KEEP_ZONES:
        keep_zone |= poly_mask(shape, zp)
    arm_over_body = arm_all & keep_zone
    body = (alpha & ~leg_hole & ~arm_all) | arm_over_body
    masks["body"] = body
    body_src = inpaint(rgba, arm_over_body, alpha & ~arm_all & ~leg_hole)

    # 圆盘内填色：部件绕圆盘转时，圆盘里的背景像素必须变成实心，否则露出真空洞
    src_map = {
        "arm": fill_disk_holes(rgba, SHOULDER[0], SHOULDER[1], arm_r),
        "arm_fore": fill_disk_holes(rgba, ELBOW[0], ELBOW[1], elbow_r),
        "leg_front": inpaint(fill_disk_holes(rgba, HIP_FRONT[0], HIP_FRONT[1],
                                             leg_r["leg_front"]),
                             leg_cover["leg_front"], masks["leg_front"] & ~arm_all),
        "leg_back": inpaint(fill_disk_holes(rgba, HIP_BACK[0], HIP_BACK[1],
                                            leg_r["leg_back"]),
                            leg_cover["leg_back"], masks["leg_back"] & ~arm_all),
        "body": body_src,
        # 肩甲不转，也就没有「转出去露真空」的问题 —— 直接用原图颜色。
        "pauldron": rgba,
    }

    # ---- 自检：归属图（必须在 dilate1 **之前**算）----
    #
    # 每个实心像素应该**恰好**被一个部件认领。
    #   · 没人认领（unowned）→ 静止帧上就是一个洞，或者像第一版那样：
    #     刀一挥开，原地留一条谁都不管的亮边。
    #   · 被两块认领（dup）→ 低 z 的那块带着一份副本，高 z 的一转开就露出鬼影。
    # 圆盘之间、圆盘与别人本来就可能相切，所以只报**连成片**的（按连通块算面积，
    # 十几像素以内的相切噪声忽略掉）。
    claim = np.zeros(shape, dtype=np.int32)
    for name in order:
        claim += masks[name].astype(np.int32)
    unowned = alpha & (claim == 0)
    dup = alpha & (claim > 1)
    # 有意为之的重叠不是鬼影，先摘掉：低层「范围留给自己 + 颜色补画」的三处
    # （躯干垫在臂/刀下、两条腿垫在刀下）、肩甲垫自己那份躯干底色、
    # 再加上两个髋盘相切的那道透镜。
    dup &= ~(arm_over_body | pauldron_m
             | leg_cover["leg_front"] | leg_cover["leg_back"]
             | (disk(shape, HIP_FRONT[0], HIP_FRONT[1], leg_r["leg_front"])
                & disk(shape, HIP_BACK[0], HIP_BACK[1], leg_r["leg_back"])))
    from scipy import ndimage as _nd
    for tag, m in (("无人认领", unowned), ("重复认领", dup)):
        n = int(m.sum())
        if n == 0:
            print(f"自检 {tag} 0px")
            continue
        lab, nl = _nd.label(m)
        sizes = _nd.sum(m, lab, range(1, nl + 1))
        worst = int(sizes.max()) if nl else 0
        print(f"自检 {tag} {n}px / {nl} 块 / 最大一块 {worst}px")
        if worst < 12:
            continue
        for i in np.argsort(sizes)[::-1][:6]:
            if sizes[i] < 12:
                break
            cy, cx = _nd.center_of_mass(lab == i + 1)
            print(f"   ! {int(sizes[i]):5d}px  中心画布 ({int(cx)},{int(cy)})")

    # ---- 自检：旋转件上的孤岛 → 直接删 ----
    #
    # 一块和主体不相接的碎片，转起来就是画面里乱飞的一颗渣（28px 就够显眼，
    # 因为它带实心色、还跟着部件绕关节画大圆）。body 不单独转，发梢/飘带
    # 断开是合法的，所以只处理四个旋转件。
    for name in ("arm", "arm_fore", "leg_front", "leg_back"):
        m = masks[name]
        lab, nl = _nd.label(m)
        if nl <= 1:
            continue
        sizes = _nd.sum(m, lab, range(1, nl + 1))
        dust = 0
        for i in range(nl):
            if sizes[i] >= 400:
                continue
            ys, xs = np.nonzero(lab == i + 1)
            if sizes[i] >= 5:
                print(f"   ! 孤岛 {name} {int(sizes[i])}px 画布 x[{xs.min()},{xs.max()}] "
                      f"y[{ys.min()},{ys.max()}] → 已删除")
            else:
                dust += int(sizes[i])
            m[lab == i + 1] = False
        if dust:
            print(f"   · 孤岛 {name} 另有 {dust}px 多边形边缘的碎点 → 已删除")

    # 各部件向外溢 1px 与 body 咬合，消掉静止帧上的 1px 白缝
    # （肩甲也要溢：它的下沿正是和上臂皮肤相接的地方，不溢就是一条 1px 亮线）
    for k in ("arm", "arm_fore", "leg_front", "leg_back", "pauldron"):
        masks[k] = dilate1(masks[k])

    # ---- 写盘 ----
    # ⚠ 层级：后腿在 body 后面（z<0），前腿与持刀臂在前，肩甲压在上臂上，
    #   **前臂（含刀）在最上** —— 肘盘要盖住上臂的圆截口，刀也要压在躯干/腿前面
    #   （垂刀式的刀正好处在腿前）；肩甲夹在中间：盖住会转的肩盘，但举手护脸时
    #   要让手和刀压在甲前面。
    parent = {"leg_back": "body", "body": "", "leg_front": "body", "arm": "body",
              "pauldron": "body", "arm_fore": "arm"}
    z = {"leg_back": -1, "body": 0, "leg_front": 2, "arm": 3, "pauldron": 4,
         "arm_fore": 5}
    joint = {"leg_back": HIP_BACK, "body": None, "leg_front": HIP_FRONT,
             "arm": SHOULDER, "pauldron": PAULDRON_JOINT, "arm_fore": ELBOW}

    os.makedirs(args.out, exist_ok=True)
    part_imgs: dict[str, Image.Image] = {}
    part_meta: dict[str, dict] = {}

    def piece_topleft(name: str, meta: dict, size: tuple) -> tuple:
        """贴图左上角的**画布坐标**（预览 / 自检拼回共用）。

        ⚠ 全局关节 = joint 字典的画布坐标（body 用画布中心）；
          part_meta['joint'] 是相对父的，不能直接加画布中心 —— arm_fore 会悬空。
        """
        gx, gy = (FRAME_W * 0.5, FRAME_H * 0.5) if joint[name] is None else joint[name]
        return (int(round(gx + meta["offset"][0] - size[0] * 0.5)),
                int(round(gy + meta["offset"][1] - size[1] * 0.5)))

    # ⚠ 圆盘必须**整块不透明**。圆盘里原本可能有透明的缝隙（两条腿之间那点背景），
    #   而 fill_disk_holes 只补 alpha<40 的像素 —— 半透明边缘会漏过去。
    #   结果就是：腿一转，圆盘上透出背景，成了一条楔形裂缝（实测走路时两条）。
    solid_disc: dict[str, np.ndarray] = {}
    for nm, jo, rr in (("leg_front", HIP_FRONT, leg_r["leg_front"]),
                       ("leg_back", HIP_BACK, leg_r["leg_back"]),
                       ("arm", SHOULDER, arm_r),
                       ("arm_fore", ELBOW, elbow_r)):
        solid_disc[nm] = disk(shape, jo[0], jo[1], rr)

    for name in order:
        m8 = masks[name].astype(np.uint8) * 255
        piece = src_map[name].copy()
        piece[..., 3] = np.minimum(piece[..., 3], m8)
        if name in solid_disc:
            piece[..., 3][solid_disc[name] & masks[name]] = 255
        ys2, xs2 = np.nonzero(piece[..., 3] > 8)
        if len(ys2) == 0:
            raise RuntimeError(f"{name} 切出来是空的 —— 解剖参数错了")
        x0, y0 = int(xs2.min()), int(ys2.min())
        x1, y1 = int(xs2.max()) + 1, int(ys2.max()) + 1
        img = Image.fromarray(piece[y0:y1, x0:x1], "RGBA")
        img.save(os.path.join(args.out, f"{name}.png"))
        part_imgs[name] = img

        cx, cy = (x0 + x1) * 0.5 - FRAME_W * 0.5, (y0 + y1) * 0.5 - FRAME_H * 0.5
        # j_center = 关节在 rig 原点坐标系下的位置（画布坐标 - 画布中心）
        if joint[name] is None:    # body：关节就是画布中心
            j_center = (0.0, 0.0)
        else:
            j_center = (joint[name][0] - FRAME_W * 0.5, joint[name][1] - FRAME_H * 0.5)
        # ⚠ part_joint 一律是**相对 rig 原点（画布中心）**的全局关节坐标 —— 这正是
        #   BossRig._build_nodes 的口径：挂到父节点下时它自己会减掉父关节
        #   （child.global = part_joint[child]，减一次加一次正好抵消）。
        # ⚠ 2026-10-26 踩过的致命坑：曾给 arm_fore 特判成「相对父关节」
        #   （ELBOW - SHOULDER = (-28,48)），写进 part_joint 后引擎把肘放到了
        #   画布 (422,408) —— 腰的高度 —— 前臂+刀整体下垂 108px，静止帧的
        #   「扛刀在肩」变成「持刀在腰」，所有挥刀都绕着错误的轴转。
        #   而拆件脚本自己的预览/拼回用的是画布坐标（正确的 (400,300)），
        #   所以自检 IoU 照样全绿 —— 引擎侧的错完全没暴露。教训：**预览口径
        #   必须与引擎口径一致**，跨口径的验证等于没验证。
        j_rel = j_center
        part_meta[name] = {
            "tex": f"{name}.png",
            "joint": j_rel,
            "offset": (cx - j_center[0], cy - j_center[1]),
            "parent": parent[name],
            "z": z[name],
        }
        print(f"  {name:<10} 尺寸 {img.size[0]}x{img.size[1]}  关节 ({j_rel[0]:+7.1f},{j_rel[1]:+7.1f}) "
              f"偏移 ({part_meta[name]['offset'][0]:+7.1f},{part_meta[name]['offset'][1]:+7.1f}) z={z[name]:+d}")

    # ---- rig.tres ----
    def sarr(items):
        return "PackedStringArray(" + ", ".join('"%s"' % v for v in items) + ")"

    def varr(items):
        flat = []
        for v in items:
            flat.extend(v)
        return "PackedVector2Array(" + ", ".join("%.2f" % v for v in flat) + ")"

    res_path = "res://" + args.out.replace("\\", "/") + "/"
    # ---- 出招原点：刀气从**刀尖**出 ----
    # ⚠ 不写死坐标：定妆图一换，写死的刀尖就落到刀身中间或空气里（虎妖那版是实测出来的，
    #   这里改成同一套「从 alpha 量」的做法）。刀尖 = **前臂分件**里最右的一撮像素
    #   （美术朝右，刀尖永远在最右端；刀柄和拳都在左边，不会误判）。
    # ⚠ 锚点相对**肘**（前臂的关节）而不是肩：刀已归前臂，肘一转锚点必须跟着走。
    arm_a = np.array(part_imgs["arm_fore"])[..., 3]
    ays, axs = np.nonzero(arm_a > 8)
    right_x = float(axs.max())
    sel_tip = axs >= right_x - 6
    m_arm = part_meta["arm_fore"]
    # 贴图左上角（画布系）= 全局关节 + offset - 尺寸/2；arm_fore 的全局关节就是 ELBOW
    arm_left = ELBOW[0] + m_arm["offset"][0] - part_imgs["arm_fore"].size[0] * 0.5
    arm_top = ELBOW[1] + m_arm["offset"][1] - part_imgs["arm_fore"].size[1] * 0.5
    tip = (arm_left + float(axs[sel_tip].mean()), arm_top + float(ays[sel_tip].mean()))
    tip_rel = (tip[0] - ELBOW[0], tip[1] - ELBOW[1])

    tres = [
        '[gd_resource type="Resource" script_class="BossRigData" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/data/boss_rig_data.gd" id="1_rig"]',
        "",
        "[resource]",
        'script = ExtResource("1_rig")',
        "canvas = Vector2i(%d, %d)" % (FRAME_W, FRAME_H),
        # 人形招式多、动画集也不一样：由 rig_script 指到 BossRigHuman
        'rig_script = "%s"' % RIG_SCRIPT,
        "order = " + sarr(order),
        "part_name = " + sarr(order),
        "part_tex = " + sarr([res_path + part_meta[n]["tex"] for n in order]),
        "part_parent = " + sarr([part_meta[n]["parent"] for n in order]),
        "part_joint = " + varr([part_meta[n]["joint"] for n in order]),
        "part_offset = " + varr([part_meta[n]["offset"] for n in order]),
        "part_z = PackedInt32Array(" + ", ".join(str(part_meta[n]["z"]) for n in order) + ")",
        'muzzle_anim = ' + sarr(["palm_project"]),
        'muzzle_part = ' + sarr(["arm_fore"]),
        "muzzle_offset = " + varr([tip_rel]),
        "",
    ]
    with open(os.path.join(args.out, "rig.tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(tres))
    print(f"刀尖锚点 ({tip[0]:.1f},{tip[1]:.1f}) 相对肘 ({tip_rel[0]:.1f},{tip_rel[1]:.1f})")

    # ---- 着色预览 ----
    colors = {"body": (235, 235, 235), "arm": (255, 90, 90), "arm_fore": (255, 90, 200),
              "leg_front": (90, 160, 255), "leg_back": (255, 180, 60),
              "pauldron": (60, 220, 60)}
    prev = Image.new("RGB", (FRAME_W, FRAME_H), (250, 250, 250))
    for name in order:
        meta = part_meta[name]
        piece = part_imgs[name]
        px, py = piece_topleft(name, meta, piece.size)
        tint = np.array(piece).copy()
        c = colors[name]
        tint[..., :3] = (tint[..., :3] * 0.35 + np.array(c, np.float32) * 0.65).astype(np.uint8)
        prev.paste(Image.fromarray(tint, "RGBA"), (px, py), Image.fromarray(tint, "RGBA"))
    d = ImageDraw.Draw(prev)
    for name in order:
        jx, jy = (FRAME_W * 0.5, FRAME_H * 0.5) if joint[name] is None else joint[name]
        d.ellipse([jx - 5, jy - 5, jx + 5, jy + 5], outline=(0, 0, 0), width=2)
        d.text((jx + 7, jy - 6), name, fill=(0, 0, 0))
    d.line([(0, FRAME_H - FOOT_MARGIN), (FRAME_W, FRAME_H - FOOT_MARGIN)], fill=(255, 0, 0), width=1)
    prev.save(args.preview)
    print(f"预览 → {args.preview}")

    # ---- 自检：拼回画布与原图比 IoU ----
    #
    # ⚠ 裙摆以下、紧贴刀轮廓的那一圈 body 像素必须是空的。裙摆底下只有两条腿
    #   和一把刀，全都由腿盒 / SWORD_POLY 认领；body 在那里还留着**沿着刀边一长条**
    #   像素 = 描边描漏了一圈亮边。静止帧完全看不出来（前臂 z 最高，压在上面），
    #   刀一挥开就是一条悬空发光的弧线 —— 第一版就是这么漏的：body 里留下一条
    #   1~2px、从裙摆一直延伸到刀尖的刀刃边（约 150px，藏在裙摆尖里没被发现）。
    #   判据用**纵向跨度**而不是像素数：真正的漏边会跟着刀拉上百行，
    #   而腿盒与刀之间 2~3px 的接缝只占几行，本来就该留在 body（那是裙子/腿的边）。
    from scipy import ndimage as _nd
    edge_slack = body & ~arm_all
    edge_slack[:HEM_Y, :] = False
    near_blade = edge_slack & _nd.binary_dilation(arm_all, iterations=3)
    ys_s, xs_s = np.nonzero(near_blade)
    span = (int(ys_s.max()) - int(ys_s.min()) + 1) if len(ys_s) else 0
    print(f"自检 裙摆以下贴刀残留 {len(ys_s)}px / 纵向跨度 {span}")
    if span > 20:
        for cy in range(int(ys_s.min()), int(ys_s.max()) + 1, 10):
            sel = np.abs(ys_s - cy) <= 4
            if sel.any():
                print(f"   ! y≈{cy:3d}  x {int(xs_s[sel].min())}-{int(xs_s[sel].max())}")
        print("  ! 描边漏了一圈：把对应多边形的边**往外让几个像素**再跑")

    recon = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    for name in order:
        meta = part_meta[name]
        piece = part_imgs[name]
        px, py = piece_topleft(name, meta, piece.size)
        recon.alpha_composite(piece, (int(round(px)), int(round(py))))
    rm = np.array(recon)[..., 3] > 128
    iou = float((rm & alpha).sum()) / float((rm | alpha).sum() or 1)
    print(f"自检 拼回 IoU {iou * 100:.2f}%")
    if iou < 0.95:
        print("  ! 切件有遗漏或重复 —— 检查臂 / 腿的折线带与刀的多边形是否覆盖完整")
    print(f"完成：{len(part_imgs)} 块 → {args.out}/ (rig.tres 已生成)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
