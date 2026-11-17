"""从两仪真人的定妆图（洋红幕）拆出人形骨骼分件（2026-10-28）。

思路与 `build_daoke_rig.py` 相同：
  · 先把整图缩到画布口径（900×720，内容高 590、脚底 y=700，居中 x=450）；
  · 再用多边形 / 条带圈选「持杖臂 + 杖」「前中流苏」「两只脚」；
  · 被拆走的地方在 body 上用周围颜色补画（inpaint），避免挥臂时露出空洞；
  · 头像旧版一样并入 body（人形头只做 1° 级微动，单拆会分裂）。

⚠ 定妆图是**镜像后**再切的：游戏里 BOSS 统一朝右，持杖臂必须在画面右侧，
   这样 `BossRigLiangyi` 的挥击角度与 `muzzle_offset`（出手点）方向才对。
   交接包的定妆图是「3/4 侧身朝**左**、杖在画面左」—— 正好靠这次镜像翻成朝右。
⚠ 关节口径：body 的画布中心 = 骨骼原点 (450,360)；arm 关节量到肩点、
   legs 仍在裙摆下缘；`rig.tres` 的数值由本脚本按实测写回。

⚠ 键色是**洋红 #FF00FF**（2026-10-28 交接包定，旧版是绿幕）。抠幕两步：
   ① 二值 mask（含「暗洋红」兜底，脚边那圈偏暗的假阴影也要吃掉）；
   ② **去溢出用 unpremultiply，不是压通道** —— 边缘像素是「前景 × a + 洋红 × (1−a)」，
      直接把 r/b 压到 g 附近会把金饰一起削灰。正确做法是 `C = (P − (1−a)·M)/a`，
      a 取 mask 模糊值（下限 0.35，太透的位置改用邻域中位色）。
⚠ 生图水印在**原图右下角**（洋红背景上，不压人物）—— 抠幕时先整块 alpha 归零。

用法：python tools/build_liangyi_rig_v2.py
输出：assets/characters/boss/liangyi_rig/{body,arm,leg_front,leg_back,sash}.png
      + rig.tres（关节 / 出手点按新图重算）+ preview_v2.png
"""
from __future__ import annotations

from PIL import Image, ImageDraw, ImageFilter
import numpy as np
from scipy import ndimage
import os

SRC = "vibe_images/art_handoff/liangyi_cel_plate.png"
OUT = "assets/characters/boss/liangyi_rig"
W, H = 900, 720
CONTENT_H = 590.0      # 人物总高（画布像素）
FEET_Y = 700.0         # 脚底 y
CENTER_X = 450.0       # 人物中轴
KEY = (255, 0, 255)    # 洋红幕（名义值；实际键色在 load_plate 里实测）
MAG_HI = 90.0          # 「洋红度」≥ 此值判背景（纯洋红 184 / 暗洋红 110）
MAG_LO = 40.0          # ≤ 此值判前景（黑袍 / 白袍≈0，金饰<0）；中间是半透边缘
NEAR_WIN = 60          # 补洞取色窗口（像素）：要大到「袍身压过金边」，众数才稳
SMOOTH_R = 40          # 补洞区**纵向**平滑半径：洞是竖直窄条，逐行取色必然留横条纹，
                       # 必须沿 y 做强低通（横向色序仍由逐行取色保证）
TILE_H = 64            # 平铺模式的取样周期（现在只剩 flat_* 用）
DIFFUSE_ITERS = 160    # 扩散补洞的迭代次数（要大于洞宽的一半）


def load_plate() -> Image.Image:
    im = Image.open(SRC).convert("RGBA")
    rgb = np.asarray(im.convert("RGB")).astype(int)

    # ① 键色**实测**，不要照抄交接包的 #FF00FF
    #    ⚠ 踩过的坑（2026-10-28）：生图出的「洋红底」实际是偏暗的紫红（四角取样
    #      约 (219,83,172)），还带轻微起伏。拿 (255,0,255) 当键色去做去溢出，
    #      g 通道会被减多 → 黑袍 / 黑发边缘整圈泛绿，甚至被啃成洞。
    #      所以先取四角 32×32 的中位色当 KEY。
    corners = np.concatenate([
        rgb[:32, :32].reshape(-1, 3), rgb[:32, -32:].reshape(-1, 3),
        rgb[-32:, :32].reshape(-1, 3), rgb[-32:, -32:].reshape(-1, 3)])
    key = tuple(float(v) for v in np.median(corners, axis=0))
    print("key color measured:", tuple(int(v) for v in key))

    # ② 抠幕判据用「洋红度」mag = min(r,b) − g，而不是到 KEY 的欧氏距离
    #    ⚠ 欧氏距离的坑（2026-10-28 实测）：生图的洋红底带明暗起伏（暗处能到
    #      (150,40,150)），离 KEY 的距离远超阈值 → 整片暗洋红被判成前景，
    #      抠完人物轮廓上挂满洋红斑块。mag 只看「r、b 是不是同时压过 g」，
    #      与亮度无关：纯洋红 184 / 暗洋红 110 / 黑袍≈0 / 白袍≈0 / 金饰<0。
    mag = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]

    # ③ 软阈值 → 直接得到带半透边缘的 alpha（硬二值会让边缘锯齿 + 无法去溢出）
    #    mag ≥ 90 判背景、≤ 40 判前景，中间线性过渡。
    alpha = (np.clip((MAG_HI - mag) / (MAG_HI - MAG_LO), 0.0, 1.0) * 255).astype(np.uint8)

    # ④ 水印 / 噪点：抠幕后残留在背景里的小块前景（生图水印常躲在角落）
    #    按连通分量面积筛掉——人物主体是最大的那一块，其余小碎块一律判背景。
    lbl, n = ndimage.label(alpha > 100)
    if n > 1:
        sizes = ndimage.sum(np.ones_like(lbl), lbl, range(1, n + 1))
        keep = int(np.argmax(sizes)) + 1
        drop = np.isin(lbl, [i + 1 for i in range(n) if i + 1 != keep])
        print("drop %d stray components (watermark/noise), largest=%d px"
              % (n - 1, int(sizes.max())))
        alpha = np.where(drop, 0, alpha).astype(np.uint8)

    # ⑤ 边缘羽化 1px（硬边切件在旋转时会出锯齿）
    mask = Image.fromarray(alpha).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1))
    alpha_s = np.minimum(np.asarray(mask), alpha).astype(float)
    a = np.asarray(im).astype(int)
    a[..., 3] = alpha_s.astype(np.uint8)

    # ④ 去溢出：C = (P − (1−a)·M)/a，只对边缘像素做（内部 a=255 不动）
    edge = (alpha_s > 8) & (alpha_s < 250)
    if edge.any():
        af = np.clip(alpha_s / 255.0, 0.35, 1.0)
        out = np.asarray(im).astype(float)[..., :3]
        for ch, kv in enumerate(key):
            c = (out[..., ch] - (1.0 - af) * kv) / af
            out[..., ch] = np.where(edge, np.clip(c, 0, 255), out[..., ch])
        # ⚠ a 太小的位置（几乎全背景）除出来会爆成噪点 → 直接判为背景丢掉。
        #   （试过用邻域中位色兜底，但边缘邻域多半是洋红，反而把洋红糊回人物边。）
        too_thin = edge & (af <= 0.36)
        alpha_s = np.where(too_thin, 0.0, alpha_s)
        a[..., 3] = alpha_s.astype(np.uint8)
        a[..., :3] = np.clip(out, 0, 255).astype(np.uint8)

    plate = Image.fromarray(a.astype(np.uint8), "RGBA")
    ys, xs = np.where(np.asarray(plate)[..., 3] > 12)
    return plate.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


# 关节实测值（画布坐标，已镜像）→ 由网格图读出，写 rig.tres 时换算成原点相对
# ⚠ 2026-10-28 第二次换图（侧身版）：持杖臂在**画面左**，和刀客一样是「武器在远侧」。
#   所以关节 x 是**负**的（刀客 arm 也是 −42）。别再按「臂在右」写，否则整条臂
#   会挂到对侧肩膀上。
SHOULDER = (395.0, 270.0)     # arm 挂点：持杖那条臂的肩
HAND = (350.0, 390.0)         # 出手点：握杖的手（招式的特效锚点）
# ⚠ 出手点取**手**而不是杖顶太极球：八式（掌 / 指 / 双鱼 / 三叠 / 逆式）都是从
#   手上打出去的，杖顶那颗球是装饰；挂到杖顶会让特效全部从头顶上方冒出来。
SASH_JOINT = (465.0, 362.0)   # 腰饰挂点（腰带中心）
# 沿用旧值：腿是空件（长袍遮到脚踝，只露裸足，切开会留方框接缝），
# 光环挂躯干中心偏上，body 就是 rig 原点。
LEG_BACK = (-28.0, 240.0)
LEG_FRONT = (28.0, 240.0)
HALO_JOINT = (0.0, -90.0)


def write_rig() -> None:
    """按实测关节重写 rig.tres。

    ⚠ 两个口径（与刀客同一套，别混）：
      · part_joint = 关节**相对 rig 原点（画布中心 450,360）**；挂到父节点时
        引擎会自己减掉父关节（见 boss_rig.gd:153）。
      · part_offset = 贴图中心 − 自身关节。分件是**整画布口径**（900×720，
        不是裁切件），所以贴图中心 = 画布中心，offset 恒等于 −joint。
      · muzzle_offset = 出手点**相对部件关节**（`node.to_global(offset)`，
        节点就站在关节上）。
    """
    arm_j = (SHOULDER[0] - CENTER_X, SHOULDER[1] - H * 0.5)
    sash_j = (SASH_JOINT[0] - CENTER_X, SASH_JOINT[1] - H * 0.5)
    # 杖的旋转轴放在**手握处**（不是杖底也不是杖顶）：它不跟着手臂转，
    # 只做轻微滞后摆动，轴在手上才像「手握着的杖」。
    staff_j = (HAND[0] - CENTER_X, HAND[1] - H * 0.5)
    muzzle_arm = (HAND[0] - SHOULDER[0], HAND[1] - SHOULDER[1])
    names = ["halo", "taiji", "leg_back", "body", "staff", "leg_front", "arm"]
    joints = [HALO_JOINT, HALO_JOINT, LEG_BACK, (0.0, 0.0), staff_j, LEG_FRONT, arm_j]
    offsets = [(-j[0], -j[1]) for j in joints]
    parents = ["body", "body", "body", "", "arm", "body", "body"]
    zs = [-5, -4, -1, 0, 3, 2, 2]
    # 前五个（palm/finger/fish/triple/counter）挂 arm → 手；后两个挂 body
    muzzles = [muzzle_arm] * 5 + [(0.0, 0.0), (0.0, 0.0)]

    def fmt(v: list) -> str:
        return ", ".join("%.2f, %.2f" % (p[0], p[1]) for p in v)

    def q(v: list) -> str:
        return ", ".join('"%s"' % s for s in v)

    def i32(v: list) -> str:
        return ", ".join(str(n) for n in v)

    text = f"""[gd_resource type="Resource" script_class="BossRigData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/boss_rig_data.gd" id="1_rig"]

[resource]
script = ExtResource("1_rig")
canvas = Vector2i(900, 720)
rig_script = "res://scripts/visual/boss_rig_liangyi.gd"
order = PackedStringArray({q(names)})
part_name = PackedStringArray({q(names)})
part_tex = PackedStringArray({q(["res://assets/characters/boss/liangyi_rig/%s.png" % n for n in names])})
part_parent = PackedStringArray({q(parents)})
part_joint = PackedVector2Array({fmt(joints)})
part_offset = PackedVector2Array({fmt(offsets)})
part_z = PackedInt32Array({i32(zs)})
muzzle_anim = PackedStringArray("palm", "finger", "fish", "triple", "counter", "collapse", "wind")
muzzle_part = PackedStringArray("arm", "arm", "arm", "arm", "arm", "body", "body")
muzzle_offset = PackedVector2Array({fmt(muzzles)})
"""
    with open(os.path.join(OUT, "rig.tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("rig.tres  arm_joint=(%.0f,%.0f)  muzzle_arm=(%.0f,%.0f)"
          % (arm_j[0], arm_j[1], muzzle_arm[0], muzzle_arm[1]))


def probe(canvas: Image.Image) -> None:
    """调试用：输出带 50px 网格的归一化图，读圈选坐标时看这张"""
    grid = canvas.copy()
    gd = ImageDraw.Draw(grid)
    for x in range(0, W, 50):
        gd.line([(x, 0), (x, H)], fill=(255, 0, 0, 110), width=1)
        gd.text((x + 1, 2), str(x), fill=(255, 255, 0, 255))
    for y in range(0, H, 50):
        gd.line([(0, y), (W, y)], fill=(255, 0, 0, 110), width=1)
        gd.text((2, y + 1), str(y), fill=(255, 255, 0, 255))
    grid.save("vibe_images/_liangyi_plate_grid.png")
    print("probe -> vibe_images/_liangyi_plate_grid.png")


def to_canvas(plate: Image.Image) -> Image.Image:
    """把定妆图缩到 900×720：内容高 590、脚底 700、中轴 450"""
    s = CONTENT_H / plate.height
    pw, ph = int(round(plate.width * s)), int(round(plate.height * s))
    plate = plate.resize((pw, ph), Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.alpha_composite(plate, (int(round(CENTER_X - pw / 2)), int(round(FEET_Y - ph))))
    return canvas


def poly_mask(size, pts) -> np.ndarray:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return np.asarray(m)


def mask_from(img: Image.Image) -> np.ndarray:
    return np.asarray(img)[..., 3].copy()


def take(canvas: Image.Image, mask: np.ndarray) -> Image.Image:
    a = np.asarray(canvas).copy()
    a[..., 3] = np.minimum(a[..., 3], mask)
    return Image.fromarray(a, "RGBA")


def inpaint(canvas: Image.Image, hole: np.ndarray, mode: str = "left") -> Image.Image:
    """被拆走的地方补画回躯干色，避免挥臂 / 摆腰时露出空洞。

    ⚠ 平涂（赛璐璐）不能用高斯模糊补洞：会糊出一条渐变带，挥臂时那一块
      明显比周围「脏」。也不能左右两侧插值：洞的右缘常常挨着飘带 / 杖的金色，
      一插值就把金色拉满整条躯干（2026-10-28 实测的「金色拉丝」）。

    正确做法是**单向复制**：
      · mode="left" —— 每行取洞**左侧**最近的实心像素色，整段平涂。
        持杖那条臂本来就在身体右缘，它底下压的就是右半袍色，直接向左取色最准。
      · mode="top"  —— 每列取洞**上方**最近的实心像素色，整段平涂。
        腰饰是竖直垂下的一束，上方是腰带，往下复制正好接着腰带色。
    """
    a = np.asarray(canvas).copy()
    erase_all = (hole > 0) & (a[..., 3] > 0)

    erase = erase_all
    a[..., 3] = np.where(erase_all, 0, a[..., 3])
    out = a.copy()

    # "tile"：每列取洞**上方一段**（TILE_H 行）的像素，竖直平铺填满整列（腰饰那束用）
    #    ⚠ 别整块平涂一个色：腰饰的洞横跨黑白分襟（中轴 x≈435），左半是白袍、
    #      右半是黑袍，平涂任何单色都会有一半是错的（2026-10-28 实测：平涂腰带色
    #      后左半出现一大块黑）。按列取色才对；再竖直平铺一段而不是复制一行，
    #      是为了让褶皱纹理也跟着延续下来，不至于补出一条死色竖带。
    # "flat_all"：整块补成「衣服的主色」（洞周围一圈像素的众数）。
    #   ⚠ 用户 2026-10-28 的原话是「直接补衣服最大色块」，这是对的：
    #     补洞的洞是**被武器/袖子挡住的衣服**，那里本来就该是一块平整的袍色。
    #     逐行取色会留下纵向渐变带（看着失真）、平铺会复制纹样、扩散会出横条 ——
    #     都不如直接给一个和衣服一致的纯色。形状看不出来，是因为颜色完全一致。
    if mode == "flat_all":
        orig = ~erase
        ring = ndimage.binary_dilation(erase, iterations=10) & orig
        band = out[..., :3][ring]
        c = _mode_color(band) if band.size else last
        out[..., :3] = np.where(erase[..., None], np.clip(c, 0, 255).astype(np.uint8), out[..., :3])
        out[..., 3] = np.where(erase, 255, out[..., 3])
        return Image.fromarray(out.astype(np.uint8), "RGBA")

    # "diffuse"：颜色从洞的边界**由外向内渗透**（邻域平均迭代）。
    #   ⚠ 为什么不用平涂 / 平铺（2026-10-28 全部试过）：
    #     · 平铺一段纹理 → 把腰带金纹复制成一排衣领；
    #     · 单色平涂 → 补出来是一块「和洞同形状的纯色」，形状跟杖一样，
    #       杖一移开，玩家看到的就是「后面还藏着一根杖」；
    #     · 扩散填充没有固定形状，颜色由四周渐变过渡，读起来是「袍子被挡住的部分」。
    if mode == "diffuse":
        rgb = out[..., :3].astype(float)
        done = ~erase
        for _ in range(DIFFUSE_ITERS):
            if done[erase].all():
                break
            acc = np.zeros_like(rgb)
            cnt = np.zeros(erase.shape)
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                acc += np.roll(rgb, (dy, dx), (0, 1)) * np.roll(done, (dy, dx), (0, 1))[..., None]
                cnt += np.roll(done, (dy, dx), (0, 1))
            upd = erase & ~done & (cnt > 0)
            if not upd.any():
                break
            rgb[upd] = acc[upd] / cnt[upd][:, None]
            done |= upd
        out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
        out[..., 3] = np.where(erase, 255, out[..., 3])
        return Image.fromarray(out.astype(np.uint8), "RGBA")

    # "flat_up" / "flat_down"：每列只取洞**上方 / 下方紧邻的几行**，取中位色后整列平涂。
    #   ⚠ 2026-10-28 用户报「衣服纹样好奇怪，这么多衣领」的根因就在这里：
    #     原来用的是**竖直平铺一段纹理**（tile / below，TILE_H=64），会把腰带上的
    #     金色纹带照原样复制 4~5 次叠下去 —— 看着就是一排衣领。
    #     补洞只要求「颜色接得上」，**不能复制纹样**，所以改成单色平涂。
    if mode in ("flat_up", "flat_down"):
        Hh2, Ww2 = erase.shape
        for x in range(Ww2):
            col = erase[:, x]
            if not col.any():
                continue
            idx = np.where(col)[0]
            segs = np.split(idx, np.where(np.diff(idx) > 1)[0] + 1)
            for seg in segs:
                y0, y1 = int(seg[0]), int(seg[-1])
                if mode == "flat_up":
                    src_y0, src_y1 = max(0, y0 - NEAR_WIN), y0
                else:
                    src_y0, src_y1 = y1 + 1, min(Hh2, y1 + 1 + NEAR_WIN)
                band = a[src_y0:src_y1, x, :3].astype(float)
                solid = a[src_y0:src_y1, x, 3] > 200
                band = band[solid]
                if band.shape[0] == 0:                    # 那一侧没东西 → 退回众数兜底
                    whole = a[:, x, :3][a[:, x, 3] > 200]
                    c = _mode_color(whole) if whole.size else last
                else:
                    c = np.median(band, axis=0)           # 中位而不是复制纹理
                last = np.asarray(c, dtype=float)
                out[seg, x, :3] = np.clip(last, 0, 255).astype(np.uint8)
                out[seg, x, 3] = 255
        return Image.fromarray(out.astype(np.uint8), "RGBA")

    Hh, Ww = erase.shape
    solid_cache: dict = {}
    last = np.array([26.0, 26.0, 32.0])     # 兜底色（黑袍）

    def solid_of(fixed: int) -> np.ndarray:
        """某一行 / 某一列上的实心像素下标（带缓存，720 次循环不至于太慢）"""
        if fixed not in solid_cache:
            line = a[fixed, :, 3] if mode == "left" else a[:, fixed, 3]
            solid_cache[fixed] = np.where(line > 200)[0]
        return solid_cache[fixed]

    for fixed in range(Hh if mode == "left" else Ww):
        line = erase[fixed] if mode == "left" else erase[:, fixed]
        if not line.any():
            continue
        idx = np.where(line)[0]
        segs = np.split(idx, np.where(np.diff(idx) > 1)[0] + 1)
        solid = solid_of(fixed)
        for seg in segs:
            s0, s1 = int(seg[0]), int(seg[-1])
            near = solid[solid < s0]
            far = solid[solid > s1]
            if near.size:
                win = near[-NEAR_WIN:]
                c = _mode_color(a[fixed, win, :3] if mode == "left" else a[win, fixed, :3])
            elif far.size:
                win = far[:NEAR_WIN]
                c = _mode_color(a[fixed, win, :3] if mode == "left" else a[win, fixed, :3])
            else:
                c = last                      # 两侧都没有 → 沿用上一行 / 列
            c = np.asarray(c, dtype=float)
            last = c
            if mode == "left":
                # 众数打底，再把左侧袍子的褶皱**镜像**进来（以洞左缘为轴），
                # 免得补出一块没有纹理的死色。镜像源不够 / 非实心的位置退回众数。
                src = 2 * s0 - 1 - seg
                ok = (src >= 0) & (src < Ww) & (a[fixed, src, 3] > 200)
                col = np.where(ok[:, None], a[fixed, np.clip(src, 0, Ww - 1), :3].astype(float), c)
                out[fixed, seg, :3] = np.clip(col, 0, 255).astype(np.uint8)
                out[fixed, seg, 3] = 255
            else:
                out[seg, fixed, :3] = np.clip(c, 0, 255).astype(np.uint8)
                out[seg, fixed, 3] = 255

    # 竖直方向再平滑一次：袍色沿 y 变化很慢，而逐行取样必然留下横向条纹。
    # 只作用在补出来的那块上，不碰原图。
    rgb_f = out[..., :3].astype(float)
    smooth = np.stack([ndimage.uniform_filter1d(rgb_f[..., ch], SMOOTH_R * 2 + 1, axis=0)
                       for ch in range(3)], axis=-1)
    out[..., :3] = np.where(erase[..., None], np.clip(smooth, 0, 255), out[..., :3]).astype(np.uint8)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def _mode_color(block: np.ndarray) -> np.ndarray:
    """一小块像素的主导色（量化后取众数）—— 抗金边 / 抗明暗条纹"""
    q = (block.astype(int) // 16).astype(np.int64)
    key = q[..., 0] * 1024 + q[..., 1] * 32 + q[..., 2]
    vals, cnt = np.unique(key, return_counts=True)
    best = vals[int(np.argmax(cnt))]
    r, rem = divmod(int(best), 1024)
    g, b = divmod(rem, 32)
    return np.array([r * 16 + 8, g * 16 + 8, b * 16 + 8], dtype=float)


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    canvas = to_canvas(load_plate())
    alpha = mask_from(canvas)
    size = (W, H)

    # ---------- 圈选（画布坐标，**不镜像**：角色原生朝右、持杖臂在画面左）----------
    # ⚠ 坐标按 `vibe_images/_liangyi_plate_grid.png` 的 50px 网格实测（侧身版定妆图）：
    #   肩 (395,270) · 手 (350,390) · 杖顶太极球 (300,135) · 杖底 (400,690) · 腰带 (465,362)
    #   杖是**斜**的（顶在左上、底在右下），分两段多边形取并集：杖带 + 广袖。
    # ⚠ 杖必须按「沿中心线的窄带」圈，不能用一个宽多边形把它旁边的衣物一起框进来
    #   （2026-10-28 用户报「武器下方粘连衣物」：旧多边形宽 145px，而杖本身只有 40px，
    #   袖子 / 袍摆全被切进 staff 件，杖一动那片衣服就跟着走）。
    #   中心线实测：(300,180) → (315,300) → (335,400) → (355,500) → (370,600) → (378,694)，
    #   半宽 24（要够包住杖身上的金环，又不能碰到右边的袍子）。
    staff_poly = [(324, 180), (339, 300), (359, 400), (379, 500), (394, 600), (402, 694),
                  (354, 694),
                  (346, 600), (331, 500), (311, 400), (291, 300),
                  (276, 180)]
    # 杖顶的太极球**单独**一块：它悬空在身体外，body 上不能补（补了就成「后面还藏着
    # 一根杖」）。所以球归 staff 件、但 body 的补洞只管杆（见下面的 m_staff / m_ball）。
    # 杖头（球 + 下面那一串金饰）整块都算悬空件：y 到 312 是因为金饰一直挂到那儿，
    # 只框球的话金饰会留在 body 上（2026-10-28 实测）。
    ball_poly = [(252, 88), (358, 88), (358, 314), (252, 314)]
    # ⚠ 两套掩码：**擦除用宽带、分件用窄带**。窄带（±24）留给 staff 件，避免把旁边
    #   的袍子一起切走（那会造成「武器粘连衣物」）；擦除必须用更宽的 ±32，
    #   否则杖身上的金环比窄带宽，会在 body 上留一圈金色残影。
    staff_erase_poly = [(332, 300), (367, 300), (387, 400), (407, 500), (422, 600), (430, 694),
                        (326, 694),
                        (318, 600), (303, 500), (283, 400), (263, 300)]
    # 杖的分件掩码：窄带（杆身核心，半宽 14）+ 外扩区里的棕色（金环 / 金饰）
    staff_core_poly = [(320, 180), (335, 300), (355, 400), (375, 500), (390, 600), (398, 694),
                       (358, 694),
                       (350, 600), (335, 500), (315, 400), (295, 300), (280, 180)]
    staff_zone_poly = [(348, 180), (363, 300), (383, 400), (403, 500), (418, 600), (426, 694),
                       (330, 694),
                       (322, 600), (307, 500), (287, 400), (267, 300), (252, 180)]
    sleeve_poly = [(360, 240), (420, 250), (430, 300), (420, 360), (400, 420),
                   (370, 470), (320, 470), (292, 430), (288, 360), (310, 300),
                   (340, 255)]
    # ⚠ 杖**不能并进 arm**：arm 是绕肩转的，整根杖（约 555px，跟人差不多高）会被
    #   手臂带着从左上甩到右上（2026-10-28 实拍确认）。两仪是法系，招式是掌 / 指 /
    #   印，抬手施法时杖应该立在身侧。所以拆成独立的 `staff` 件，父 = body。
    # ⚠ 只靠多边形圈不住杖：杖身是一串**金环**（比杆宽），多边形一放宽就把旁边的
    #   黑袍/飘带一起框进来（用户反复报「武器下边还是连着衣服」）。
    #   定稿：**窄带管杆身 + 颜色筛金饰** —— 窄带（半宽 14）保证杆不断，
    #   外面 ±48 的范围内只额外收「棕色像素」（杖身金环 / 杖头金饰），
    #   黑袍是 r≈g≈b、白袍是亮灰，都过不了棕色判据。
    canvas_rgb = np.asarray(canvas)[..., :3].astype(int)
    _r, _g, _b = canvas_rgb[..., 0], canvas_rgb[..., 1], canvas_rgb[..., 2]
    # ⚠ 判据要**严**： 那种松判据会把白袍的暖灰阴影 (140,120,95) 也算成
    #   「金饰」，结果 staff 件里带上一大片白袍碎片（用户报「武器下边还是连着衣服」）。
    #   实测金饰 (180,150,90) 的 r-b≈90、白袍阴影只有 ≈45 → 阈值取 55 一刀切开。
    brown = ((_r - _b) > 55) & (_r > 110) & (_g > 70)
    # ⚠ 别用「颜色筛选」补金饰：金环有的亮、有的暗，筛选会把杖身切成碎块
    #   （2026-10-28 实测 y=300 断成 3 段）。改用**稍宽的连续窄带**（半宽 20），
    #   宁可杖边多 5px 袍色，也不能让杖断。
    m_staff = np.minimum(poly_mask(size, staff_core_poly), alpha)
    _ = brown  # 保留判据定义，供以后精修参考
    m_ball = np.minimum(poly_mask(size, ball_poly), alpha)     # 球（body 不补）
    m_staff_all = np.maximum(m_staff, m_ball)                  # staff 件 = 杆 + 球
    m_staff_erase = np.minimum(poly_mask(size, staff_erase_poly), alpha)   # body 擦除用宽版
    m_staff_erase = np.maximum(m_staff_erase, m_ball)
    m_arm = np.minimum(poly_mask(size, sleeve_poly), alpha)
    # ⚠ 袖子多边形和杖身有重叠（x 360~400、y 300~450 那一段），两份都切出来的话
    #   arm 件里就带着「一段杖」：手臂一转，那段跟着走，而 staff 件在原位还留着
    #   整根杖 —— 看着就是「武器粘着衣服」+「后面还有一个武器」（用户 2026-10-28 报）。
    #   归属按**视觉前后**定：杖画在袖子之前（z 更高），所以重叠区一律归 staff，
    #   袖子把这块让出去（它本来就被杖挡着，缺一块看不出来）。
    m_arm = np.where(m_staff_all > 0, 0, m_arm)

    # ⚠ 2026-10-28 起**不再切腰饰**（m_sash 留空，并回 body）。
    #   试过三种补洞都会露馅：竖直平铺纹理 → 腰带金纹被复制 4~5 次，像一排衣领
    #   （用户报「怎么这么多衣领」）；按列取上方色 → 因为洞有 80×300 那么大，
    #   每列颜色不同 → 腰前拉出一条竖向渐变带；整块平涂单色 → 洞横跨黑白分襟，
    #   必然有一半是错的。而腰饰本来的摆幅只有 0.06~0.16 rad，收益远小于代价。
    m_sash = np.zeros((H, W), dtype=np.uint8)

    # 腿：长袍遮到脚踝，只露裸足；硬切会在裙摆上留方框接缝，所以两只腿都给空白件
    # （rig 仍按原关节存在，只是不画东西 —— 不会白缝，也不会露洞）
    m_leg_front = np.zeros((H, W), dtype=np.uint8)
    m_leg_back = np.zeros((H, W), dtype=np.uint8)

    # ---------- 切件 ----------
    arm = take(canvas, m_arm)
    staff = take(canvas, m_staff_all)
    sash = take(canvas, m_sash)
    leg_front = take(canvas, m_leg_front)
    leg_back = take(canvas, m_leg_back)

    # 三个洞分开补、方向不同：袖（侧边竖条）向左取色 + 镜像纹理；杖同向左取色；
    # 腰饰（跨中轴）按列向上平铺。
    # ⚠ 杖顶球是**悬空**的：body 上要把它擦掉，但**不能补**（补了就成「后面还藏着一根杖」）。
    #   做法：先手动把球区 alpha 归零，再只对杆区做补洞。
    canvas_noball = np.asarray(canvas).copy()
    canvas_noball[m_ball > 0, 3] = 0
    body = inpaint(Image.fromarray(canvas_noball), m_staff_erase, "flat_all")
    body = inpaint(Image.fromarray(np.asarray(body)), m_arm, "flat_all")
    body = inpaint(Image.fromarray(np.asarray(body)), m_sash, "flat_up")

    for img, name in [(body, "body.png"), (arm, "arm.png"), (staff, "staff.png"),
                      (sash, "sash.png"), (leg_front, "leg_front.png"),
                      (leg_back, "leg_back.png")]:
        img.save(os.path.join(OUT, name))
        print("part", name)

    write_rig()

    # ---------- 预览 ----------
    prev = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for name in ["halo", "taiji", "leg_back", "body", "staff", "leg_front", "arm"]:
        prev.alpha_composite(Image.open(os.path.join(OUT, name + ".png")))
    prev.save(os.path.join(OUT, "preview_v2.png"))
    # 「移开 arm」的检查图：看 body 补洞有没有留空心
    noarm = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for name in ["leg_back", "body", "staff", "leg_front"]:
        noarm.alpha_composite(Image.open(os.path.join(OUT, name + ".png")))
    noarm.save("vibe_images/_liangyi_body_noarm.png")
    print("check -> vibe_images/_liangyi_body_noarm.png")
    grid = prev.copy()
    gd = ImageDraw.Draw(grid)
    for x in range(0, W, 50):
        gd.line([(x, 0), (x, H)], fill=(255, 0, 0, 90), width=1)
        gd.text((x + 1, 2), str(x), fill=(255, 255, 0, 255))
    for y in range(0, H, 50):
        gd.line([(0, y), (W, y)], fill=(255, 0, 0, 90), width=1)
        gd.text((2, y + 1), str(y), fill=(255, 255, 0, 255))
    grid.save("vibe_images/_rig_grid.png")
    print("preview_v2 saved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
