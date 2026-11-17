#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""执烛那 13 张「带深蓝圆角底板」图标的抠图工具，两条路。

【结论】底板是手绘的、影/墨物件和底板在同一个深蓝域 —— **像素算法抠不干净**，
最后靠「图生图只换背景成洋红 → 键色收片」解决。四轮算法的失败数字留在下面，别再来一遍。

路线 A `matte()`（暖色物件可用，本次只有 `tr_zhizhu_ling.png` 走这条：83.5%→54.1%、0 漏洞）：
  1) 靠边一圈拟合二次多项式 + 径向项（牌心有辉光，纯 xy 多项式拟合不出来）；
  2) 粗轮廓内部挖空，只留实测底板像素，在 1/8 网格解 Laplace（Jacobi 松弛）重建牌面；
  3) **σ=1.2px 模糊后才比色**：纸纹被平均掉（残差 ~0.3），物件的大尺度色差留着；
  4) 阈值按本图底板带残差分位数现算；背景只从四边灌入（物件暗芯不被打穿）；
  5) alpha = 掩膜高斯羽化。**不能**把色距 ramp 也乘进 alpha —— 底板像素会拿到 ~89 的半透明，
     浅底上一铺就是一个灰方块（烛泪坠实测 alpha 加权 40.2% / 实心 13.6%）。
  已实测**不成立**的三条判据：滞后双阈值（烛泪坠 80.1% 全留）、纹理（底板局部高频 p90=36
  > 刀身暗侧中位 12.1，噪声尾部盖过笔触）、轮廓当墙（加与不加数字一模一样，暗刀身到牌面是渐变）。

路线 B `--key`（其余 12 张走这条，全部一次通过）：
  图生图只换背景 → `vibe_images/icon_<名>_key_*.png` → `key_magenta()` 键色收片。
  两个必须的做法（都是量出来的，见 docs/执烛待生成美术_提示词.md §9）：
   - **颜色从最近实心像素搬，不反解**：反解 `观测=真色×(1-k)+键色×k` 在冷银/白热边上过冲偏绿，
     照骨/投晷/缚影的羽化带 36~40% 偏绿（实心区 0.00%）；搬色后 2~13%。
   - **去紫偏**：模型会顺键色把墨迹画成紫罗兰（踏灯可见区中位 (40,21,60)，原设计蓝黑）。
     判据取「r 和 b **同时**高于 g」那部分一起减 —— 暖铜/皮肤/纯蓝墨都不满足，不受影响。

用法：
  python tools/mat_icon_plate.py                      # 路线 A 预览（装备那批）
  python tools/mat_icon_plate.py --all --write        # 路线 A 真改（先备份）
  python tools/mat_icon_plate.py --key --all          # 路线 B 预览键色重出件
  python tools/mat_icon_plate.py --key --all --write  # 路线 B 落盘
"""
import argparse
import glob
import os
import shutil

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(ROOT, "assets", "ui", "icon")

# 用户点名的「装备/材料」那批
EQUIP = [
    "equip_changye_ren.png", "equip_zhului_zhui.png", "mat_zhaoying_zhulei.png",
    "soul_zhizhu.png", "tr_zhizhu_ling.png",
]
# 同一批出图的功法图标，底板一模一样
SKILLS = [
    "skill_shadow_cut.png", "skill_shadow_reach.png", "skill_shadow_bind.png",
    "skill_shadow_step.png", "skill_shadow_dim.png", "skill_shadow_beam.png",
    "skill_shadow_split.png", "skill_shadow_longnight.png", "skill_shadow_lamp.png",
]

BLUR = 1.2          # 比色前的平滑半径：要大到吃掉纸纹，小到不糊掉物件轮廓
KEY_SPAN = 150.0    # 自动键色的软过渡跨度（欧氏距离单位），越大边缘越软
COARSE = 8          # 底板重建的粗网格倍率
JACOBI = 900        # Laplace 松弛轮数
RIM_ERODE = 4       # 圆角牌四边斜口高光带宽度（像素），按牌形硬切
FEATHER = 1.1       # 掩膜羽化半径：给 2~3px 软边，不留锯齿
CLOS = 7            # 剪影闭运算半径：深色物件的中调常被判成牌色，缺口要能自己封回去
WALL_K = 1.6        # 边缘墙阈值 = 牌面自身梯度 p99.5 × 这个倍数
HF_SIGMA = 1.6      # 高频提取：原图减去这个半径的高斯，只留笔触/颗粒这一层
HF_BOX = 7          # 局部高频能量的统计窗口
TEX_K = 1.4         # 纹理阈值 = 底板带局部高频 p97 × 这个倍数


def _poly_basis(gx, gy, w, h, cx, cy):
    """二次渐层 + 到牌心的径向项：牌面中心有一圈辉光（vignette），只用 xy 多项式拟合不出来。"""
    nx = gx / (w - 1.0)
    ny = gy / (h - 1.0)
    r = np.sqrt((gx - cx) ** 2 + (gy - cy) ** 2) / (0.5 * (w + h))
    return np.stack([np.ones_like(nx), nx, ny, nx * nx, ny * ny, nx * ny,
                     r, r * r, r * r * r], axis=2)


def _border_band(opaque):
    """实心外接框的最外一圈 —— 确定只有底板，没有物件。"""
    ys, xs = np.where(opaque)
    cx = (xs.min() + xs.max()) * 0.5
    cy = (ys.min() + ys.max()) * 0.5
    d = np.maximum(np.abs(xs - cx), np.abs(ys - cy))
    band = np.zeros(opaque.shape, bool)
    band[ys[d >= np.quantile(d, 0.82)], xs[d >= np.quantile(d, 0.82)]] = True
    return band


def _plate_poly(a_s, band):
    """在平滑图上迭代拟合底板渐层（剔除被物件污染的样本）。"""
    h, w = a_s.shape[:2]
    gy, gx = np.mgrid[0:h, 0:w]
    ys, xs = np.where(band)
    cx = (xs.min() + xs.max()) * 0.5
    cy = (ys.min() + ys.max()) * 0.5
    f_all = _poly_basis(gx, gy, w, h, cx, cy)
    sel = np.ones(len(xs), bool)
    rgb = a_s[ys, xs, :3].astype(np.float64)
    coef = None
    for _ in range(4):
        coef, *_ = np.linalg.lstsq(f_all[ys[sel], xs[sel]], rgb[sel], rcond=None)
        res = np.sqrt(((rgb - f_all[ys, xs] @ coef) ** 2).sum(1))
        sel = res <= np.quantile(res, 0.70)
    return np.einsum("ijk,kl->ijl", f_all, coef)


def _harmonic_fill(vals, known, coarse=COARSE, iters=JACOBI):
    """用 known 处的实测值在 1/coarse 网格上解 Laplace，把 unknown 补成平滑渐层。"""
    h, w = vals.shape[:2]
    ch, cw = (h + coarse - 1) // coarse, (w + coarse - 1) // coarse
    out = np.zeros((ch, cw, 3), np.float64)
    km = known.reshape(ch, coarse, cw, coarse)
    for c in range(3):
        v = vals[..., c].astype(np.float64)
        pm = km.mean(axis=(1, 3))
        num = (v * known).reshape(ch, coarse, cw, coarse).sum(axis=(1, 3))
        avg = num / np.maximum(pm * coarse * coarse, 1e-9)
        valid = pm > 0.30
        g = np.where(valid, avg, 0.0)
        for _ in range(iters):
            p = np.pad(g, 1, mode="edge")
            nb = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) * 0.25
            g = np.where(valid, avg, nb)
        out[..., c] = g
    big = np.stack([ndimage.zoom(out[..., c], (coarse, coarse), order=1, mode="nearest")
                    for c in range(3)], axis=2)
    return big[:h, :w]


def _flood_from_border(bg):
    """只从画面四边灌入标记背景 —— 物件内部即使残差很低也不会被当成牌打掉。"""
    lab, n = ndimage.label(bg)
    if n == 0:
        return np.zeros_like(bg)
    seeds = np.unique(np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))
    return np.isin(lab, seeds[seeds > 0])


# 逐张阈值倍数：底板噪声/辉光每张不同，统一倍数会在某几张上留牌雾或啃掉物件。
# 数值由 --lo 扫描 + 实心/alpha 加权占比与肉眼对照共同定的，见 docs/执烛待生成美术_提示词.md §9。
KLO = {}


def _klo(f, override):
    if override >= 0.0:
        return override
    return KLO.get(f, 1.0)


def _disk(r):
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return (x * x + y * y) <= r * r


def matte(img, k_lo=1.0, clos=CLOS):
    a = np.asarray(img.convert("RGBA"), dtype=np.uint8)
    h, w = a.shape[:2]
    alpha = a[..., 3]
    opaque = alpha > 200
    if opaque.sum() < 400:
        return a.copy(), 0.0, 0.0, 0.0
    a_s = ndimage.gaussian_filter(a[..., :3].astype(np.float64), (BLUR, BLUR, 0))

    band = _border_band(opaque)
    rough = _plate_poly(a_s, band)

    def dist(m):
        return np.sqrt(((a_s - m) ** 2).sum(axis=2)) / (17.32 * np.sqrt(BLUR * 2 + 1))

    # --- 1) 粗轮廓 → 底板重建
    d0 = dist(rough)
    thr = np.quantile(d0[band], 0.90) * 1.6
    obj = (d0 > thr) & opaque
    obj = ndimage.binary_closing(obj, np.ones((3, 3), bool), iterations=2)
    obj = ndimage.binary_fill_holes(obj)
    obj = ndimage.binary_dilation(obj, np.ones((3, 3), bool))
    known = opaque & ~obj

    # --- 2) 精键：色距 + **纹理**双判据，背景从画面四边灌入（flood fill）。
    #        纹理才是这批图的正确判据：实测底板是一张**无颗粒**的平滑渐层
    #        （7×7 局部高频能量中位 1.2），手绘物件带笔触（刀身暗侧 12.1、刀脊亮线 82.6、
    #        铜护手 59.9）—— 差 10~50 倍。只按色距判，「中调等于牌色」的暗刀身/石面会被从中间啃穿。
    plate = _harmonic_fill(a_s, known)
    d1 = dist(plate)
    base = np.quantile(d1[known], 0.95)
    t_lo = base * k_lo
    rgb0 = a[..., :3].astype(np.float64)
    hf = rgb0 - ndimage.gaussian_filter(rgb0, (HF_SIGMA, HF_SIGMA, 0))
    loc = ndimage.uniform_filter((hf ** 2).sum(axis=2), HF_BOX)
    e_thr = max(np.quantile(loc[band], 0.97) * TEX_K, 4.0)
    notplate = (d1 >= t_lo) | (loc >= e_thr)
    # 边缘当墙：泛洪不许穿过物件自己的轮廓线
    gy, gx = np.gradient(a_s, axis=0), np.gradient(a_s, axis=1)
    grad = np.sqrt(np.max(gx * gx + gy * gy, axis=2))
    w_thr = np.quantile(grad[band], 0.995) * WALL_K
    walls = ndimage.binary_dilation(grad > w_thr, _disk(1))
    bg = _flood_from_border((~notplate | (alpha <= 200)) & ~walls)
    keep = ndimage.binary_closing(~bg, _disk(clos))
    keep = ndimage.binary_fill_holes(keep)
    keep = ndimage.binary_opening(keep, _disk(2))
    lab, n = ndimage.label(keep)
    if n > 1:
        sizes = np.bincount(lab.ravel())
        biggest = int(sizes[1:].argmax()) + 1
        floor = max(60, sizes[biggest] * 0.03)
        ids = [i for i in range(1, n + 1) if sizes[i] >= floor or i == biggest]
        keep = np.isin(lab, ids)
    # 圆角牌四边有一圈斜口高光，紧贴实心外缘 —— 那是牌不是物件
    edge_band = ~ndimage.binary_erosion(opaque, ndimage.generate_binary_structure(2, 2),
                                        iterations=RIM_ERODE)
    keep &= ~edge_band

    # --- 3) alpha = 掩膜本身的高斯羽化。
    #        早先把色距 ramp 也乘进 alpha，底板像素拿到 ~89 的半透明，浅底上一铺就是一个灰方块。
    soft = ndimage.gaussian_filter(keep.astype(np.float64), FEATHER)
    new_a = np.clip(np.round((soft - 0.16) / 0.76 * 255.0), 0, 255)
    new_a[~opaque] = np.minimum(new_a[~opaque], alpha[~opaque])

    # --- 4) 去蓝溢：只动羽化带（0<alpha<255，牌色透出来的那一圈）。
    #        按「离实心底边 ≤3px」判会连细笔触一起脱溢 —— 蓝火苗整条都 ≤3px，脱完变绿。
    out = a.astype(np.float64).copy()
    r, g, b = out[..., 0], out[..., 1], out[..., 2]
    blend = (new_a > 0) & (new_a < 250)
    spill = np.clip(b - np.maximum(r, g) - 10.0, 0.0, 70.0) * blend
    out[..., 0] = np.clip(r + spill * 0.30, 0, 255)
    out[..., 1] = np.clip(g + spill * 0.30, 0, 255)
    out[..., 2] = np.clip(b - spill, 0, 255)
    out[..., 3] = np.minimum(alpha, new_a)
    u8 = out.astype(np.uint8)
    cov = float((u8[..., 3] > 200).mean()) * 100.0
    hole = float(100.0 * (ndimage.binary_fill_holes(u8[..., 3] > 200) & (u8[..., 3] <= 200)).mean())
    return u8, cov, float(base), hole


VIBE = os.path.join(ROOT, "vibe_images")


def detect_key(im, band=6):
    """从画面四边量出真实键色。生图模型会把「平涂洋红」画歪：
    执烛图标背景出成 (236,91,206)、万界棋坛两张分别出成 (217,32,128) 暗红和淡粉，
    写死 #FF00FE 就解不干净。四边一定是最纯的底色，取中位数最稳。"""
    a = np.asarray(im.convert("RGB"), np.float64)
    edge = np.concatenate([a[:band].reshape(-1, 3), a[-band:].reshape(-1, 3),
                           a[:, :band].reshape(-1, 3), a[:, -band:].reshape(-1, 3)])
    return np.median(edge, axis=0)


def key_auto(im, edge_prop_px=0):
    """按量出来的键色抠图：k = 到键色的欧氏距离，底噪以上做一段软过渡。"""
    a = np.asarray(im.convert("RGB"), np.float64)
    keyc = detect_key(im)
    raw = np.sqrt(((a - keyc[None, None, :]) ** 2).sum(axis=2))
    edge = np.concatenate([raw[:6].ravel(), raw[-6:].ravel(), raw[:, :6].ravel(), raw[:, -6:].ravel()])
    r0 = max(np.quantile(edge, 0.99), 6.0)      # 底噪上限：这段以内算纯背景
    # k = 「这一像素掺了多少键色」：离键色越近 k 越大（纯底 k=1 → alpha=0）。
    # 早先写成 (raw-r0)/SPAN，方向反了，纯背景算出 k=0 → alpha=255，整张底全留着。
    k = np.clip((r0 + KEY_SPAN - raw) / KEY_SPAN, 0.0, 1.0)
    return _finish_key(a, k, keyc, edge_prop_px)


def _finish_key(a, k, keyc, edge_prop_px):
    alpha = (1.0 - k) * 255.0
    k = np.minimum(k, 0.999)
    alpha[k >= 0.995] = 0.0
    solid = k <= 0.02
    idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    prop = a[tuple(idx)]
    d = ndimage.distance_transform_edt(~solid)
    inv = 1.0 / np.maximum(1.0 - k[..., None], 1e-3)
    unpre = np.clip((a - keyc[None, None, :] * k[..., None]) * inv, 0, 255)
    band = (d <= float(edge_prop_px)) if edge_prop_px > 0 else (d <= 24.0)
    rgb = np.where(band[..., None], prop, unpre)
    exc = np.minimum(rgb[..., 0] - rgb[..., 1], rgb[..., 2] - rgb[..., 1])
    pull = np.clip(exc - 8.0, 0.0, 90.0) * 0.80 * (alpha > 0)
    rgb[..., 0] = np.clip(rgb[..., 0] - pull, 0, 255)
    rgb[..., 2] = np.clip(rgb[..., 2] - pull * 0.55, 0, 255)
    return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")


def key_magenta(im, edge_prop_px=0):
    """洋红键色抠图：alpha 由键色浓度算，颜色按「离实心多远」分两种口径。

    反解 `观测 = 真色×(1-k) + 键色×k` 在亮边（冷银/白热）上会过冲到偏绿：
    实测 beam/reach/bind 的羽化带里 36~40% 的像素偏绿，而实心区 0.00%。
    但**全程搬色又会毁掉半透明光晕** —— 光晕的颜色被换成最近实心像素的浅石灰，
    整圈发白（万界棋坛实机截图里抓到的就是这个）。
    所以：紧贴轮廓 edge_prop_px 窄带搬色，深处的半透明区反解。
    edge_prop_px=0 = 沿用图标那批的旧口径（<=24px 搬色，之外反解）。
    """
    a = np.asarray(im.convert("RGB"), np.float64)
    k = np.clip((((a[..., 0] + a[..., 2]) * 0.5 - a[..., 1]) - 30.0) / 70.0, 0.0, 1.0)
    alpha = (1.0 - k) * 255.0
    alpha[k >= 0.995] = 0.0
    solid = k <= 0.02
    idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    prop = a[tuple(idx)]
    d = ndimage.distance_transform_edt(~solid)
    keyc = np.array([255.0, 8.0, 255.0])
    inv = 1.0 / np.maximum(1.0 - k, 1e-3)
    unpre = np.clip((a - keyc[None, None, :] * k[..., None]) * inv[..., None], 0, 255)
    # 紧贴轮廓的窄带搬色（压掉品红硬边），更深的半透明区留给反解（保住光晕本色）。
    # edge_prop_px=0 时退回「全程搬色、>24px 才反解」—— 图标那批的既有口径。
    band = (d <= float(edge_prop_px)) if edge_prop_px > 0 else (d <= 24.0)
    rgb = np.where(band[..., None], prop, unpre)
    # 去紫偏：生图模型会顺着键色把墨迹画成紫罗兰（实测 skill_shadow_step 可见区中位色
    # (40,21,60)，原设计是蓝黑）。判据 = r 和 b **同时**高于 g 的那部分，两者一起减掉。
    # 暖铜 (150,100,60)、皮肤 (200,160,140)、纯蓝墨 (20,25,60) 都不满足「双双高于 g」，不受影响。
    exc = np.minimum(rgb[..., 0] - rgb[..., 1], rgb[..., 2] - rgb[..., 1])
    pull = np.clip(exc - 8.0, 0.0, 90.0) * 0.80 * (alpha > 0)
    rgb[..., 0] = np.clip(rgb[..., 0] - pull, 0, 255)
    rgb[..., 2] = np.clip(rgb[..., 2] - pull * 0.55, 0, 255)
    return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")


def key_to_icon(path, size=256, margin=14, min_blob=48, auto=False):
    """键色原片 → 抠图 → 掉碎点 → 按内容包围盒裁 → 等比塞进 size² 方图标（物件占画面 ~78%）。

    auto=True 走 key_auto（从四边量键色）：生图把「平涂洋红」画歪过三次，新出的图默认用这条。
    """
    src = Image.open(path).convert("RGB")
    keyed = key_auto(src) if auto else key_magenta(src)
    ar = np.asarray(keyed).copy()
    vis = ar[..., 3] > 24
    lab, n = ndimage.label(vis)
    if n > 1:
        sizes = np.bincount(lab.ravel())
        biggest = int(sizes[1:].argmax()) + 1
        keep = [i for i in range(1, n + 1) if sizes[i] >= min_blob or i == biggest]
        ar[..., 3] = np.where(np.isin(lab, keep), ar[..., 3], 0)
    keyed = Image.fromarray(ar.astype(np.uint8), "RGBA")
    box = np.argwhere(ar[..., 3] > 24)
    if box.size == 0:
        return None, 0.0
    y0, x0 = box.min(0)
    y1, x1 = box.max(0) + 1
    crop = keyed.crop((int(x0), int(y0), int(x1), int(y1)))
    cw, ch = crop.size
    s = (size - margin * 2) / max(cw, ch)
    crop = crop.resize((max(1, int(round(cw * s))), max(1, int(round(ch * s)))), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(crop, ((size - crop.size[0]) // 2, (size - crop.size[1]) // 2))
    cov = float((np.asarray(canvas)[..., 3] > 200).mean()) * 100.0
    return canvas, cov


def run_key(names, write):
    """重出件（洋红底）走这条路；底板件走 matte()。"""
    bdir = os.path.join(ROOT, "assets", "_backup", "mat_plate_20261104")
    sheet = Image.new("RGB", (256 * 2, 256 * len(names)), (28, 28, 30))
    done = []
    for i, f in enumerate(names):
        stem = os.path.splitext(f)[0]
        cands = sorted([p for p in glob.glob(os.path.join(VIBE, "icon_%s_key_*.png" % stem))],
                       key=os.path.getmtime)
        if not cands:
            print("%-26s 没有重出的键色原片，跳过" % f)
            continue
        icon, cov = key_to_icon(cands[-1])
        if icon is None:
            print("%-26s 键色全图，判不出内容" % f)
            continue
        print("%-26s 键色实心占比 %5.1f%%   <- %s" % (f, cov, os.path.basename(cands[-1])))
        done.append(f)
        old = Image.open(os.path.join(ICON, f)).convert("RGBA")
        sheet.paste(_cell(old, 256, "light").convert("RGB"), (0, i * 256))
        sheet.paste(_cell(icon, 256, "light").convert("RGB"), (256, i * 256))
        if write:
            os.makedirs(bdir, exist_ok=True)
            p = os.path.join(ICON, f)
            bk = os.path.join(bdir, f)
            if not os.path.exists(bk):
                shutil.copy2(p, bk)
            icon.save(p)
    out = os.path.join(ROOT, "output", "mat_key_sheet.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print("对照表（每行左=现役带底板 右=键色重出抠后）：", out)
    print("已处理 %d 张：%s" % (len(done), ", ".join(done)))
    if write:
        print("已写入，备份在", bdir)
    return done


def _cell(im, size=128, mode="checker"):
    if mode == "checker":
        n = 16
        yy, xx = np.mgrid[0:size, 0:size]
        dark = (((yy // n) + (xx // n)) % 2) == 0
        base = np.zeros((size, size, 4), np.uint8)
        base[..., :3] = np.where(dark[..., None], 46, 96)
        base[..., 3] = 255
        cell = Image.fromarray(base, "RGBA")
    elif mode == "light":
        cell = Image.new("RGBA", (size, size), (238, 236, 228, 255))
    else:
        cell = Image.new("RGBA", (size, size), (18, 46, 30, 255))
    t = im.copy()
    t.thumbnail((size - 4, size - 4), Image.LANCZOS)
    cell.alpha_composite(t, ((size - t.size[0]) // 2, (size - t.size[1]) // 2))
    return cell


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="真改原图（先备份）")
    ap.add_argument("--skills", action="store_true", help="只做功法图标那批")
    ap.add_argument("--all", action="store_true", help="装备 + 功法全做")
    ap.add_argument("--lo", type=float, default=-1.0, help="背景阈值倍数，负数=用 KLO 表里的逐张定值")
    ap.add_argument("--key", action="store_true",
                    help="走洋红键色重出件这条路（vibe_images/icon_<名>_key_*.png），不做底板重建")
    ap.add_argument("only", nargs="*", help="只处理指定文件名")
    args = ap.parse_args()

    if args.only:
        names = list(args.only)
    elif args.all:
        names = EQUIP + SKILLS
    elif args.skills:
        names = list(SKILLS)
    else:
        names = list(EQUIP)

    if args.key:
        run_key(names, args.write)
        return

    bdir = os.path.join(ROOT, "assets", "_backup", "mat_plate_20261104")
    col = 3
    nrows = (len(names) + col - 1) // col
    blocks = [("before", "checker"), ("after", "checker"), ("after", "light"), ("after", "green")]
    sheet = Image.new("RGB", (128 * col, 128 * nrows * len(blocks)), (28, 28, 30))
    for i, f in enumerate(names):
        p = os.path.join(ICON, f)
        if not os.path.exists(p):
            print("缺文件", f)
            continue
        before = Image.open(p).convert("RGBA")
        arr, cov, base, hole = matte(before, _klo(f, args.lo))
        after = Image.fromarray(arr, "RGBA")
        b0 = float((np.asarray(before)[..., 3] > 200).mean()) * 100.0
        aw = float(np.asarray(after)[..., 3].mean()) / 255.0 * 100.0
        print("%-26s 实心 %5.1f%% -> %5.1f%%（alpha 加权 %5.1f%%）  残差基准 %.3f  物件内漏洞 %.2f%%"
              % (f, b0, cov, aw, base, hole))
        cx, rw = (i % col) * 128, i // col
        for j, (which, mode) in enumerate(blocks):
            im = before if which == "before" else after
            sheet.paste(_cell(im, 128, mode).convert("RGB"), (cx, (j * nrows + rw) * 128))
        if args.write:
            os.makedirs(bdir, exist_ok=True)
            bk = os.path.join(bdir, f)
            if not os.path.exists(bk):
                shutil.copy2(p, bk)
            after.save(p)
    out = os.path.join(ROOT, "output", "mat_v5_sheet.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print("对照表（每列自上而下 = 原图棋盘 / 抠后棋盘 / 抠后亮底 / 抠后绿底）：", out)
    if args.write:
        print("已写入，备份在", bdir)


if __name__ == "__main__":
    main()
