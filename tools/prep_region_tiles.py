#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""练气区地面 tile 的原图整形：压平低频光照 → 抹水印 → 对齐目标亮度。

为什么每一步都不能省：
  水印   AI 出图右下角固定带「Qoder AI生成」，它压在纹理本体上，抠不掉只能盖掉。
  低频   模型总会画一个中心亮、四角暗的「氛围光」。tile 要平铺，这种大尺度亮度
         斜坡会在每个接缝处形成一条可见的格子网 —— 平铺贴图的第一杀手。
  亮度   地面必须比技能特效暗（SKILL_FX glow 亮度 0.506~0.562），否则刀气贴地时
         直接看不见；同时三套 tile 之间要能分辨出路/草/林缘。

用法：
    python tools/prep_region_tiles.py            # 全部处理，输出到 output/tiles/prep/
    python tools/prep_region_tiles.py --check    # 只报指标，不写文件

⚠ 压平只管到 sigma=边长/5（约 200px）以上的尺度。再往下的「草叶成条」是笔触本身，
   平掉它 texture 就成了一锅噪声。实测草地留到 1/12 尺度的起伏还有 4.4%，3x3 拼起来
   能看出一格一格的横纹 —— 这个不归这里管，交给 region_terrain.gdshader 的
   逐格随机旋转 + 亮度抖动去破，那才是破周期性重复的正确层。
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "vibe_images")
# 中间产物落在 output/（.gitignore 已排除）：这一步是纯确定性的，随时能从
# vibe_images 的源图重跑，没必要进版本库。进 assets 的只有 background-tile
# 之后的 896 无缝图。
OUT_DIR = os.path.join(ROOT, "output", "tiles", "prep")

## 每张 tile 的源图（取 glob 命中的最新一个）+ 目标平均亮度。
## 目标带依据：五区 ground_color 亮度 0.135~0.201，特效 glow 0.506 是天花板；
## 草/路留在 0.21~0.26 之间靠色相与明度差分辨，林缘压到 0.155 当「树荫下」。
TILES = {
    "grass": {"glob": "tile_grass_lianqi_v3_*.png", "target": 0.215},
    "road": {"glob": "tile_road_lianqi_v3_*.png", "target": 0.255},
    "forestfloor": {"glob": "tile_forestfloor_lianqi_v2_*.png", "target": 0.155},
    # 云隐谷（筑基）：冷灰绿 + 石板蓝，比练气再压暗一档（2026-10-28）
    "zhuji_grass": {"glob": "zhuji_tile_grass_v1_*.png", "target": 0.195},
    "zhuji_road": {"glob": "zhuji_tile_road_v1_*.png", "target": 0.235},
    "zhuji_forestfloor": {"glob": "zhuji_tile_forestfloor_v1_*.png", "target": 0.145},
    # 赤金丹霞（结丹）：红砂岩 + 金脉，比筑基暖一档；地面仍要压在特效亮度之下
    # ⚠ 丹霞三张出图本身偏橙红，直出在实机像火星；sat 统一往回收一档（2026-10-29）
    "jiedan_grass": {"glob": "jiedan_tile_grass_*.png", "target": 0.205, "sat": 0.78},
    "jiedan_road": {"glob": "jiedan_tile_road_*.png", "target": 0.225, "sat": 0.62},
    "jiedan_forestfloor": {"glob": "jiedan_tile_forestfloor_*.png", "target": 0.150, "sat": 0.90},
    # 幽冥灵墟（元婴）：阴土紫灰 + 冷青灵火，比结丹再压暗一档
    "youming_grass": {"glob": "youming_tile_grass_*.png", "target": 0.175, "sat": 0.84},
    "youming_road": {"glob": "youming_tile_road_*.png", "target": 0.205, "sat": 0.80},
    "youming_forestfloor": {"glob": "youming_tile_rubble_*.png", "target": 0.135, "sat": 0.90},
    # 九天之上（化神）：云海 / 玉台 / 雾岩岛缘。全项目最亮的一档地面 —— 这里本来就是云，
    # 但天花板仍是特效 glow 0.506，所以最高只推到 0.265，比丹霞草地亮一档而已。
    # ⚠ 云海用 v4 不用 v1~v3：v1 出图 0.785、v2 0.086、v3 0.475，要吸收的 gamma 是
    #   5.98/0.59/1.95，全都在现有各区 0.86~1.66 的带宽以外；v4 拿祭坛本身当图生图锚点，
    #   源图 0.356、gamma 1.52，笔触也终于是祭坛那种旋卷祥云而不是黄昏烟团。
    #   sat 收到 0.80：不回收饱和度在实机会盖掉角色的青白特效。
    "jiutian_cloudsea": {"glob": "jiutian_tile_cloudsea_v4_*.png", "target": 0.235, "sat": 0.80},
    # ⚠ 玉台出过四版，前两版都不对：v1/v2 是青玉，G 通道压过 R 通道 0.052，在紫云里
    #   直接读成「一块绿岛」，和祭坛那种紫灰石头不是一路；把 sat 压到 0.55 只是把绿洗成灰，
    #   并没有把色相请回祭坛那一族。祭坛本身就是紫+墨，所以正确做法是**同色相、靠质感分**：
    #   石头是切出来的硬平面，云是软的旋卷 —— 不是靠 hue 分。
    #   v4 直接拿祭坛当色彩锚点重画，并规定 10~14 块中小石板：
    #   v1~v3 那种五六块巨型石板在 zoom 1.0 下每块约 200 屏幕像素，看着像巨石阵不像脚下路面。
    "jiutian_terrace": {"glob": "jiutian_tile_terrace_v4_*.png", "target": 0.265, "sat": 0.92},
    "jiutian_mistrock": {"glob": "jiutian_tile_mistrock_*.png", "target": 0.170, "sat": 0.86},
}

# 低频场的高斯半径 = 边长 / FLAT_SCALE。取 1/5 是因为要压掉的是「整张图的明暗斜坡」，
# 笔触尺度（几十像素）必须原样保留。
FLAT_SCALE = 5.0
# 压平是收敛到不动点的迭代：一遍只能去掉当前低频场，除完又露出下一层。
# 实测草地 1/2/3 遍的低频残余 0.047 / 0.024 / 0.014，代价是 5-95% 从 0.153 掉到
# 0.140（笔触对比度损失 8%）—— 换掉肉眼可见的平铺横纹，值。
FLAT_ITERS = 3
# 增益限幅：暗部除以一个很小的场值会炸出噪声，宁可留一点没压平的余量。
# 下界 0.34 是实测出来的：草地左下角比中心暗 28%，卡 0.55 只能压回一半。
GAIN_CLIP = (0.34, 2.90)
## 水印盒（1024×1024 源图，含边界）。出图工具固定把「Qoder AI生成」压在右下角，
## 位置不随内容变，所以写死比自动检测稳 —— 自动检测会被纹理自身的亮笔触带偏，
## 一个离群像素就能把盒子撑到整个窗口。左边界留到 852：实测土路那张的 "Q" 在 870，
## 卡 884 会留半个字母。
WM_BOX = (852, 948, 1024, 1020)
## 补丁四周的羽化宽度。只贴方块会留一个可见的硬边矩形（草地第一版就是这样）。
FEATHER = 16


def _newest(pattern: str) -> str:
    hits = sorted(glob.glob(os.path.join(SRC_DIR, pattern)), key=os.path.getmtime)
    if not hits:
        raise SystemExit(f"no source matches {pattern} in vibe_images/")
    return hits[-1]


def _erase_watermark(rgb: np.ndarray) -> tuple[np.ndarray, float, tuple[float, float]]:
    """把右下角的水印用紧邻左侧的同批行纹理羽化盖掉。

    不裁边：tile 尺寸要卡住无缝化的 source >= period + overlap，1024 刚好在上限。
    取左邻块而不是横向镜像块：镜像离得太远，色差藏不住；左邻块低频亮度天然一致。
    放在压平之后调用，此时横向斜坡已经被抹掉，左邻块和盒区的亮度差最小。
    返回 (结果, 色差, (笔画能量比, 对照区笔画能量))：色差 = 贴块与左邻对照区的均值差，
    >0.02 就是贴出了一块色斑；能量比接近 1 且两者都≈对照区，说明水印已不在。
    """
    h, w, _ = rgb.shape
    x0, y0 = WM_BOX[0] * w // 1024, WM_BOX[1] * h // 1024
    x1, y1 = min(w, WM_BOX[2] * w // 1024), min(h, WM_BOX[3] * h // 1024)
    bw, bh = x1 - x0, y1 - y0
    src = rgb[y0:y1, x0 - bw - 6:x0 - 6]
    # 左 + 上两条边做线性羽化，右/下压在图边上没有内部接缝要藏。
    a = np.ones((bh, bw), dtype=np.float32)
    f = min(FEATHER, bw // 3, bh // 3)
    ramp = np.linspace(0.0, 1.0, f, dtype=np.float32)
    a[:, :f] *= ramp[None, :]
    a[:f, :] *= ramp[:, None]
    a = a[:, :, None]
    out = rgb.copy()
    out[y0:y1, x0:x1] = src * a + rgb[y0:y1, x0:x1] * (1.0 - a)
    lum = out.mean(axis=2)
    box = lum[y0:y1, x0:x1]
    ctrl = lum[y0:y1, x0 - bw - 6:x0 - 6]
    cast = abs(float(box.mean() - ctrl.mean()))
    # 「笔画能量」= 减去 3px 低频后剩下的锐度。水印是细笔画，这项远高于周围纹理；
    # 贴块之后应当掉到和对照区同一量级，所以报 before/after 的比值。
    def _ink(v: np.ndarray) -> float:
        blur = _low_freq(v, 2)
        return float(np.abs(v - blur).mean())
    ink_before = _ink(rgb.mean(axis=2)[y0:y1, x0:x1])
    ink_after = _ink(box)
    return out, cast, (ink_after / max(ink_before, 1e-4), _ink(ctrl))



def _low_freq(field: np.ndarray, sigma: float) -> np.ndarray:
    """显式 sigma 的低通。

    ⚠ 不能用 PIL 的 ImageFilter.GaussianBlur：它的参数叫 radius 但实际
    sigma ≈ radius/3，按「边长/5」传半径只会滤掉笔触尺度，大尺度明暗斜坡原封不动。
    mode='reflect' 是为了避免边界被当成 0 拉暗 —— 那会在四边又造出一圈新的暗带。
    """
    return gaussian_filter(field, sigma, mode="reflect")


def _flatten(rgb: np.ndarray) -> np.ndarray:
    """按通道除以自己的低频场，把大尺度明暗斜坡换成均匀底。

    sigma = 边长/FLAT_SCALE：要压的是「整张图一个亮中心 + 四角发暗」这种几百像素
    尺度的氛围光，笔触尺度（几十像素）必须原样保留。
    """
    w = rgb.shape[1]
    sigma = w / FLAT_SCALE
    out = np.empty_like(rgb)
    for ch in range(3):
        f = rgb[:, :, ch]
        field = _low_freq(f, sigma)
        gain = np.clip(field.mean() / np.maximum(field, 1e-4), *GAIN_CLIP)
        out[:, :, ch] = f * gain
    return out


def _gamma_to_target(rgb: np.ndarray, target: float) -> tuple[np.ndarray, float]:
    """解一个 gamma 让平均亮度落在 target。

    用 gamma 而不是线性缩放：线性乘 0.54 会把土路的明部暗部一起压掉、笔触对比度
    跟着塌；gamma 只挪中间调整体形状保住。
    """
    sub = rgb[::4, ::4]
    lo, hi = 0.05, 20.0
    g = 1.0
    for _ in range(28):
        g = 0.5 * (lo + hi)
        m = np.power(sub.clip(1e-4, 1.0), g).mean(axis=2).mean()
        if m < target:
            hi = g
        else:
            lo = g
    return np.power(rgb.clip(1e-4, 1.0), g), g


def _metrics(rgb: np.ndarray) -> dict:
    lum = rgb.mean(axis=2)
    h, w = lum.shape
    b = max(1, h // 8)
    corners = np.concatenate([
        lum[:b, :b].ravel(), lum[:b, -b:].ravel(),
        lum[-b:, :b].ravel(), lum[-b:, -b:].ravel(),
    ])
    centre = lum[h // 2 - b:h // 2 + b, w // 2 - b:w // 2 + b].ravel()
    p5, p50, p95 = np.percentile(lum, [5, 50, 95])
    # 低频残余：整张图自己的大尺度明暗起伏（相对值）。平铺后每格重复一次，
    # 是「看出格子」的主因，比接缝本身更值得盯。角/心只测了四角，这项测全图。
    lf = float(np.std(_low_freq(lum, w / FLAT_SCALE)) / max(lum.mean(), 1e-4))
    return {
        "mean": float(lum.mean()),
        "p5": float(p5), "p50": float(p50), "p95": float(p95),
        "spread": float(p95 - p5),
        "even": float(corners.mean() / max(centre.mean(), 1e-4)),
        "lf": lf,
    }


def prep(name: str, spec: dict, write: bool) -> int:
    src = _newest(spec["glob"])
    rgb = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255.0
    before = _metrics(rgb)
    # 先压平再抹水印：水印盒要靠左邻块补，横向斜坡没压掉之前左邻块和盒区不是一个亮度。
    for _ in range(FLAT_ITERS):
        rgb = _flatten(rgb)
    rgb, wm_cast, (wm_ink, wm_ink_ctrl) = _erase_watermark(rgb)
    sat = float(spec.get("sat", 1.0))
    if abs(sat - 1.0) > 1e-4:
        lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        rgb = np.clip(lum[:, :, None] + (rgb - lum[:, :, None]) * sat, 0.0, 1.0)
    rgb, gamma = _gamma_to_target(rgb, spec["target"])
    after = _metrics(rgb)

    print(f"[{name}]  {os.path.basename(src)}")
    print(f"    水印 贴块色斑={wm_cast:.4f}  笔画能量 抹后/抹前={wm_ink:.2f} (对照区 {wm_ink_ctrl:.4f})")
    print(f"    亮度  {before['mean']:.3f} -> {after['mean']:.3f}   (目标 {spec['target']:.3f})")
    print(f"    5-95% {before['spread']:.3f} -> {after['spread']:.3f}")
    print(f"    角/心 {before['even']:.3f} -> {after['even']:.3f}   (1.00 = 无低频斜坡)  gamma={gamma:.3f}")
    print(f"    低频残余 {before['lf']:.3f} -> {after['lf']:.3f}   (平铺后每格重复一次的大尺度起伏)")
    if write:
        os.makedirs(OUT_DIR, exist_ok=True)
        dst = os.path.join(OUT_DIR, f"tile_{name}.png")
        Image.fromarray((rgb.clip(0, 1) * 255.0 + 0.5).astype(np.uint8)).save(dst)
        print(f"    -> {os.path.relpath(dst, ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只报指标不写文件")
    args = ap.parse_args()
    for name, spec in TILES.items():
        prep(name, spec, write=not args.check)
    return 0


if __name__ == "__main__":
    sys.exit(main())
