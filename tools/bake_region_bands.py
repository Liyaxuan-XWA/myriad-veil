#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""练气区两条林带的出图整形：抹水印 → 品红抠图 + 去溢色 → 裁内容 → 压平 → 对齐亮度。

和 tile 的分工：tile 是能平铺的地面本体，林带是压在地图上「挡住去路」的树。
南侧是**侧视**树墙（玩家从北边看过去的立面），东侧是**俯视**密冠（从头顶看树冠）。
两条都只在一个方向上重复：南带沿 x、东带沿 y。

为什么抠图而不是直接要透明底：出图工具不产 alpha，只能给它一个纯色底再键掉。
品红是仓库里既有的口径（gen_boss_sprite_frames.py 同一套），因为暗绿松林和品红
在色轮上离得最远，键起来不吃树冠边缘。

⚠ 水印只能贴块盖掉，不能指望认出来：南带的「Qoder AI生成」落在品红底上变成粉白，
   东带那行落在暗绿树冠上变成灰白 —— 两种都不像字本身，按颜色检测实测一边漏掉
   一边误删真树。所以两张各自写死一个右下角盒子，用紧邻左侧的同高纹理羽化盖掉。

用法：
    python tools/bake_region_bands.py            # 出到 output/tiles/bands/
    python tools/bake_region_bands.py --check    # 只报指标
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import median_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_region_tiles as T  # noqa: E402  复用压平 / gamma / 指标，两处口径必须一致

ROOT = T.ROOT
SRC_DIR = os.path.join(ROOT, "vibe_images")
OUT_DIR = os.path.join(ROOT, "output", "tiles", "bands")

BANDS = {
    # axis = 重复方向；south 是侧视树墙所以底边要留一点羽化，east 是俯视密冠不用。
    # wm = 水印盒（该张源图自己的像素坐标）。按右下角目视裁块量出字的外沿，
    # 再往外让出一个羽化带 —— 见 _patch_watermark 里那条 ⚠。
    "south": {"glob": "band_south_pine_side_*.png", "axis": "x", "target": 0.175,
              "base_fade": 0.055, "wm": (2270, 1000, 2560, 1080)},
    "east": {"glob": "band_east_canopy_top_v2_*.png", "axis": "y", "target": 0.165,
             "base_fade": 0.0, "wm": (840, 1450, 1024, 1536)},
}
# 抠图：到参考底色的距离小于 lo 全透，大于 hi 全不透。
KEY_LO, KEY_HI = 0.055, 0.20
# 反合成的覆盖率下限，见 _key。
UNMIX_MIN = 0.25
# 粉边的判读基准：林带实际压在 lianqi_forestfloor.png 上（实测前景均值 RGB）。
# 品红污染的特征是 r 和 b **同时**高出 g —— 只查一个都会误报：地面是暖棕
# (0.192,0.160,0.114) 合成时把 r 抬上去了，而树冠本身偏冷，b 本来就高于 g。
GROUND_RGB = np.array([0.1917, 0.1600, 0.1142], dtype=np.float32)


def _newest(pattern: str) -> str:
    hits = sorted(glob.glob(os.path.join(SRC_DIR, pattern)), key=os.path.getmtime)
    if not hits:
        raise SystemExit(f"no source matches {pattern} in vibe_images/")
    return hits[-1]


def _bg_ref(rgb: np.ndarray) -> np.ndarray:
    """底色 = 满足「R 高、G 低、B 不低」的像素的中位色。

    不按四角取：东带右下角是树冠不是底色，取角会取错。
    """
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    rough = (r > 0.55) & (g < 0.42) & (b > 0.28)
    if rough.mean() < 0.02:
        raise SystemExit("没找到品红底 —— 出图提示词里要求的纯色底没出来？")
    return np.median(rgb[rough], axis=0)


def _patch_watermark(rgb: np.ndarray, box: tuple[int, int, int, int]) -> tuple[np.ndarray, float, float]:
    """把水印盒用紧邻左侧的同高纹理羽化盖掉。

    不走「按颜色认字」：浅灰字叠在品红底上出来的是粉白，叠在暗绿树冠上出来的是灰白，
    两种都不像字本身，检测器只会漏。也不走「这块是背景就整块抹透明」：东带的字
    是压在树冠上的，那种做法会把一整块真树删掉。
    取左邻块而不是镜像块 —— 和 tile 那边同一套理由：镜像离得远、色差藏不住。
    ⚠ 盒子的上/左边界必须比字的外沿再多留一个羽化带（≥FEATHER 行）：羽化是
      src·a + 原图·(1-a)，a<1 的那几行会把原图里的字漏出来 —— 实测南带盒子只
      高出字顶 9 行时，贴完还在 y=1045 留了 13 个 alpha 0.14 的像素点。
    返回 (结果, 色差, 锐度比)：色差 = 贴块与左邻对照区的亮度均值差；锐度比 = 盒区
      「减掉局部中值后剩下的正尖峰」相对借块，>1.3 说明字还留着一截。
    """
    h, w, _ = rgb.shape
    x0, y0, x1, y1 = box
    x1, y1 = min(x1, w), min(y1, h)
    bw, bh = x1 - x0, y1 - y0
    if x0 - bw - 6 < 0:
        raise SystemExit(f"水印盒太宽，左边没有可借的同高纹理：{box}")
    src = rgb[y0:y1, x0 - bw - 6:x0 - 6]
    a = np.ones((bh, bw), dtype=np.float32)
    f = min(T.FEATHER, bw // 3, bh // 3)
    ramp = np.linspace(0.0, 1.0, f, dtype=np.float32)
    a[:, :f] *= ramp[None, :]
    a[:f, :] *= ramp[:, None]
    out = rgb.copy()
    out[y0:y1, x0:x1] = src * a[:, :, None] + rgb[y0:y1, x0:x1] * (1.0 - a[:, :, None])
    lum = out.mean(axis=2)
    ctrl = lum[y0:y1, x0 - bw - 6:x0 - 6]
    cast = abs(float(lum[y0:y1, x0:x1].mean() - ctrl.mean()))
    # 贴完的盒区相对「借来的那块」还有多尖：1.0 = 和周围纹理同级，字已经不在；
    # 借块本身就是锐利针叶（东带），所以不能用「贴前/贴后」判断，要拿借块当基准。
    ratio = _spike(lum[y0:y1, x0:x1]) / max(_spike(ctrl), 1e-4)
    return out, cast, ratio


def _spike(v: np.ndarray) -> float:
    """减掉 9px 局部中值后剩下的**正**尖峰均值 —— 半透明白字正是这种形状。

    用中值不用高斯：水印笔画宽 2~3px，高斯会把整块树冠纹理的低频也一起算进来；
    只取正号是因为字只会往亮里抬，暗下去的纹理不该算成残留。
    """
    med = median_filter(v, size=9, mode="reflect")
    return float(np.clip(v - med, 0.0, None).mean())


def _key(rgb: np.ndarray, ref: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """抠图 + 反合成（unmix），返回 (前景色, alpha)。

    只去溢色（从 r/b 里减掉超出 g 的那截）不够：50/50 混了品红的树冠像素，减完
    r-g 还剩 0.15，实测边缘带里偏品红的像素亮度 0.257、树体本身才 0.152 ——
    等于沿整条树线描了一圈亮红边，在暗地面上非常扎眼。
    正确做法是把底色按覆盖率解回去：obs = c·fg + (1-c)·ref → fg = (obs-(1-c)·ref)/c。

    ⚠ 这里的 c 不能直接拿 alpha 用。alpha 是对「到底色距离」做 smoothstep 得到的
      显示透明度，不是真实覆盖率；而 d 本身正比于 c（d = c·|fg-ref|），所以
      覆盖率用 d/D 反推，D = 不透明树冠像素的 d 中位数。
    c 低于 UNMIX_MIN 时不再继续放大：那些像素 alpha 已经 ≤0.2，误差乘上去也
    只剩一层薄雾，比让它们炸成白边划算。
    """
    d = np.sqrt(((rgb - ref) ** 2).sum(axis=2))
    t = np.clip((d - KEY_LO) / (KEY_HI - KEY_LO), 0.0, 1.0)
    alpha = t * t * (3.0 - 2.0 * t)
    full = float(np.median(d[d > KEY_HI]))
    c = np.clip(d / max(full, 1e-3), 0.0, 1.0)
    den = np.maximum(c, UNMIX_MIN)[:, :, None]
    fg = (rgb - ref[None, None, :] * (1.0 - c)[:, :, None]) / den
    return np.clip(fg, 0.0, 1.0), alpha


def _flatten_rgb(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """只在前景上压低频。

    直接用整图的低频场会被透明区拖偏：树带的外轮廓外面是一大片 0，
    高斯过去会在树线边缘造出一圈假暗带，压平反而画出了阴影。
    所以低频场用 alpha 加权平均（分子分母各滤一次），归一化也只用前景的均值。
    """
    w = rgb.shape[1]
    sigma = w / T.FLAT_SCALE
    a = np.clip(alpha, 0.0, 1.0)
    denom = np.maximum(T._low_freq(a, sigma), 1e-3)
    fg = a > 0.5
    out = np.empty_like(rgb)
    for ch in range(3):
        f = rgb[:, :, ch]
        field = T._low_freq(f * a, sigma) / denom
        ref = float(field[fg].mean()) if fg.any() else float(field.mean())
        gain = np.clip(ref / np.maximum(field, 1e-4), *T.GAIN_CLIP)
        out[:, :, ch] = f * gain
    return out


def _crop_to_content(rgb: np.ndarray, alpha: np.ndarray, pad: int = 2):
    ys, xs = np.where(alpha > 0.08)
    if len(ys) == 0:
        raise SystemExit("抠完什么都不剩了")
    y0, y1 = max(0, ys.min() - pad), min(alpha.shape[0], ys.max() + 1 + pad)
    x0, x1 = max(0, xs.min() - pad), min(alpha.shape[1], xs.max() + 1 + pad)
    return rgb[y0:y1, x0:x1], alpha[y0:y1, x0:x1], (x0, y0, x1, y1)


def _fringe_check(rgb: np.ndarray, alpha: np.ndarray) -> tuple[float, float]:
    """合成到地面色之后，分别量半透明带和不透明区里「双通道压过绿」的比例。

    判据必须是 r 和 b **同时**高出 g，单看一个都会误报：地面 tile 是暖棕（r 比 g 高
    0.03，合成时把边缘往暖里带），而树冠本身偏冷（b 比 g 高，但 r 压在 g 下面）。
    只有品红污染才两头一起抬。
    只看半透明带也没意义：要拿同一张图里肯定干净的不透明内部当对照组。
    """
    comp = rgb * alpha[:, :, None] + GROUND_RGB[None, None, :] * (1.0 - alpha)[:, :, None]
    r, g, b = comp[:, :, 0], comp[:, :, 1], comp[:, :, 2]
    over = (r > g + 0.02) & (b > g + 0.02)
    edge = over[(alpha > 0.03) & (alpha < 0.97)]
    core = over[alpha > 0.90]
    return float(edge.mean()) if edge.size else 0.0, float(core.mean()) if core.size else 0.0


def bake(name: str, spec: dict, write: bool) -> int:
    src = _newest(spec["glob"])
    rgb = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255.0
    ref = _bg_ref(rgb)
    rgb, cast, ink = _patch_watermark(rgb, spec["wm"])
    rgb, alpha = _key(rgb, ref)
    rgb, alpha, box = _crop_to_content(rgb, alpha)
    rgb = _flatten_rgb(rgb, alpha)
    # gamma 用前景掩码求解：把透明的底色区也算进均值会让目标亮度整体偏移。
    fg = alpha > 0.5
    lo, hi = 0.05, 20.0
    g = 1.0
    for _ in range(28):
        g = 0.5 * (lo + hi)
        if np.power(np.clip(rgb, 1e-4, 1.0), g).mean(axis=2)[fg].mean() < spec["target"]:
            hi = g
        else:
            lo = g
    rgb = np.power(np.clip(rgb, 1e-4, 1.0), g)
    lum = rgb.mean(axis=2)

    if spec["base_fade"] > 0:
        n = max(2, int(rgb.shape[0] * spec["base_fade"]))
        ramp = np.linspace(1.0, 0.0, n, dtype=np.float32)[:, None]
        alpha = alpha.copy()
        alpha[-n:, :] *= ramp

    rgba = np.concatenate([rgb, alpha[:, :, None]], axis=2)
    fringe, baseline = _fringe_check(rgb, alpha)
    print(f"[{name}]  {os.path.basename(src)}")
    print(f"    底色 {np.round(ref, 3)}   水印贴块 色差 {cast:.4f} 锐度 {ink:.2f}×   裁切盒 {box}")
    print(f"    尺寸 -> {rgb.shape[1]}x{rgb.shape[0]}   前景 {fg.mean() * 100:.1f}%")
    print(f"    亮度 前景均值 {lum[fg].mean():.3f} (目标 {spec['target']:.3f})  p95 {np.percentile(lum[fg], 95):.3f}  gamma={g:.3f}")
    print(f"    偏品红 边缘 {fringe * 100:.1f}% / 内部对照 {baseline * 100:.1f}%   (边缘高出对照 >8pt = 树冠还有粉边)")
    if write:
        os.makedirs(OUT_DIR, exist_ok=True)
        dst = os.path.join(OUT_DIR, f"band_{name}.png")
        Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8)).save(dst)
        print(f"    -> {os.path.relpath(dst, ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    for name, spec in BANDS.items():
        bake(name, spec, write=not args.check)
    return 0


if __name__ == "__main__":
    sys.exit(main())
