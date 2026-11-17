#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""九天之上（化神区）地貌遮罩烘焙器。

产出一张 750x500 的 RGBA = 世界 6000x4000 的 1/8。逐像素：
    R = 云海权重   G = 玉台权重   B = 雾岩岛缘权重   A = 仙气贴花强度
region_terrain.gdshader 把 RGB 归一化后加权混三套 tile，A 决定雾纹叠多少。

和练气/幽冥那几个区的根本差别：那些区的遮罩是**从内容表的航点算出来的**
（药材点、兽群点、传送门连成路网）。九天之上的内容表里 herbs/beasts/qi_orbs/
cultivators 全是空的 —— 它不是地图，是一块突破用的场地。所以这里不编航点，
只按三件真实存在的东西摆位：
    化神坛 = 区域中心（SecretWorldDB.huashen_altar_pos()）
    回程传送门 = HUASHEN_CONTENT["portal"].pos
    进场落点     = HUASHEN_CONTENT["spawn"].pos
坛下是玉台，落点和坛之间是一条玉阶甬道，外围才是碎掉的岛缘。
坐标一律从 secret_world_db.gd 现读，不在这里抄一份 —— 抄了就会漂。

用法：
    python tools/bake_jiutian_mask.py                 # 烘到 assets/scenes/tiles/jiutian_mask.png
    python tools/bake_jiutian_mask.py --debug         # 顺带出四通道分解 + 合成预览
    python tools/bake_jiutian_mask.py --scale 8       # 遮罩 = 世界 / scale（默认 8）
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_region_mask as R  # noqa: E402  复用同一套噪声/读表/归一化口径

ROOT = R.ROOT
OUT_PNG = os.path.join(ROOT, "assets", "scenes", "tiles", "jiutian_mask.png")
DEBUG_DIR = os.path.join(ROOT, "output", "tiles")

REGION_X, REGION_Y = 6000.0, 4000.0   # 和 SecretWorldDB 的 rect 尺寸一致

## ===== 玉台 =====
## 坛在中心，台子要大到够玩家绕着按 F，又不能大到把云海吃掉。
## ⚠ 半径按「站在坛前看得见台边」定，不是按面积占比定：相机 zoom 1.0 一屏只有
##   1280x720 世界像素，上一版 1180x900 时人在坛前四周全是石板，云海和岛缘都在
##   屏幕外，实机截图看着就是一片铺地而不是「云上的一块台子」。
##   收到 820x620 之后台边落在视场里，台子仍然是坛周围够用的一圈。
TERRACE_RX, TERRACE_RY = 820.0, 620.0
TERRACE_FEATHER = 150.0        # 台缘往云海一侧的渐变宽度
## 甬道：落点走到坛下得踩着石头，不能让人一进场就站在云上。
WALK_WIDTH = 150.0
WALK_FEATHER = 46.0

## ===== 雾岩岛缘 =====
## 岛缘是贴着区域矩形边的一条碎岩带，**不是椭圆外的一切**。
## 用归一化半径判的话四个角全落进「半径 > 阈值」，实测 rim 覆盖率冲到 39% ——
## 那等于把这块场地画成碎岩地，云海只剩中间一条，仙气就没了。
## 按到边距离算、带宽 RIM_DEPTH 世界像素，覆盖率落在 ~20%，云海留 65% 上下。
RIM_DEPTH = 240.0

## ===== 仙气贴花（A 通道）=====
## 这一层是「缭绕」本身：云海和碎岩都只交代地貌，雾要靠它。
## 上一版密度 0.34 + 底数 0.30 烘出来 decal 均值只有 0.052，合成预览里几乎看不见雾，
## 站在地面上就是一块紫云地板而不是九天之上 —— 所以底数抬到 0.52，密度也跟着抬。
## 玉台上仍然要压掉大半：台子是踩出来的石面，雾在脚边绕，不是把字都糊住。
DECAL_DENSITY = 0.46           # 全区平均覆盖率
DECAL_EDGE_BIAS = 1.9          # 台缘/岛缘附近加权倍数
DECAL_BASE = 0.52              # 远离边缘处的保底强度
DECAL_NOISE_SCALE = 118.0      # 细档：雾丝
DECAL_CLUSTER_SCALE = 40.0     # 粗档：雾团


def read_huashen() -> dict:
    """从 secret_world_db.gd 现读 rect 尺寸与坛/门/落点坐标，不在这里抄第二份。

    抄一份一定会和 .gd 漂移，而这张遮罩的正确性完全依赖摆位跟游戏里长在同一张图上。
    结构一变就 raise 出声，比静默烘出一张错位地图好。
    """
    text = open(R.DB_GD, encoding="utf-8").read()
    m = re.search(r'"region_id":\s*REGION_HUASHEN.*?\n\t\},', text, re.S)
    if not m:
        raise SystemExit("九天之上 REGIONS 条目没找到，.gd 结构变了？")
    rect = re.search(r'"rect":\s*Rect2\(([^)]*)\)', m.group(0))
    if not rect:
        raise SystemExit("九天之上的 rect 缺了")
    rw, rh = float(rect.group(1).split(",")[2]), float(rect.group(1).split(",")[3])
    if (rw, rh) != (REGION_X, REGION_Y):
        raise SystemExit(f"九天之上 rect 尺寸变成 {rw}x{rh}，遮罩分辨率参数要跟着改")

    cm = re.search(r"const HUASHEN_CONTENT: Dictionary = \{(.*?)\n\}", text, re.S)
    if not cm:
        raise SystemExit("HUASHEN_CONTENT 没找到")
    content = cm.group(1)
    portal = re.search(r'"portal":\s*\{[^}]*"pos":\s*(Vector2\([^)]*\))', content)
    spawn = re.search(r'"spawn":\s*\{[^}]*"pos":\s*(Vector2\([^)]*\))', content)
    if not portal or not spawn:
        raise SystemExit("HUASHEN_CONTENT 里的 portal / spawn 坐标缺一个")
    pv, sv = R._vec2(portal.group(1)), R._vec2(spawn.group(1))
    if pv is None or sv is None:
        raise SystemExit("portal / spawn 坐标解析不出来，格式变了？")
    return {"altar": (0.0, 0.0), "portal": pv, "spawn": sv}


def _grid(w: int, h: int, scale: float) -> tuple[np.ndarray, np.ndarray]:
    """内容坐标网格：以区域中心为原点，x∈[-3000,3000]、y∈[-2000,2000]。"""
    ys = (np.arange(h, dtype=np.float32) + 0.5) * scale - REGION_Y / 2.0
    xs = (np.arange(w, dtype=np.float32) + 0.5) * scale - REGION_X / 2.0
    return np.meshgrid(xs, ys)


def terrace_field(xx, yy, data, scale: float) -> np.ndarray:
    """坛下的椭圆台 + 从落点接到台边的甬道。"""
    d = np.hypot(xx / TERRACE_RX, yy / TERRACE_RY)
    t = np.clip((1.0 - d) * (max(TERRACE_RX, TERRACE_RY) / TERRACE_FEATHER), 0.0, 1.0)
    t = gaussian_filter(t.astype(np.float32), 1.2)

    # 甬道：落点 -> 坛，但只画到台缘以外一点，进了台子就没必要再画一条
    sx, sy = data["spawn"]
    px, py = data["altar"]
    seg = math.hypot(sx - px, sy - py)
    ux, uy = (sx - px) / seg, (sy - py) / seg
    # 台缘在这个方向上的距离
    edge = TERRACE_RX * TERRACE_RY / math.hypot(TERRACE_RY * ux, TERRACE_RX * uy)
    ax, ay = px + ux * edge * 0.86, py + uy * edge * 0.86
    bx, by = sx + 40.0, sy - 40.0
    n = max(int(seg * 1.4), 24)
    ts = np.linspace(0.0, 1.0, n)
    # 略微弯一下：直线甬道在云海上看着像一根尺画的线
    mx, my = (ax + bx) / 2.0 - uy * 150.0, (ay + by) / 2.0 + ux * 150.0
    cx = (1 - ts) ** 2 * ax + 2 * (1 - ts) * ts * mx + ts ** 2 * bx
    cy = (1 - ts) ** 2 * ay + 2 * (1 - ts) * ts * my + ts ** 2 * by
    road = np.zeros_like(xx, dtype=np.float32)
    for i in range(n):
        dd = np.hypot(xx - cx[i], yy - cy[i])
        road = np.maximum(road, np.clip(1.0 - (dd - WALK_WIDTH / 2.0) / WALK_FEATHER, 0.0, 1.0))
    road = gaussian_filter(road, 1.6)
    return np.clip(np.maximum(t, road * 0.96), 0.0, 1.0)


def rim_field(xx, yy, w: int, h: int) -> np.ndarray:
    """岛缘：到最近一条边的距离过线以后开始碎，两档噪声把边线咬成不规则。"""
    dist = np.minimum(REGION_X / 2.0 - np.abs(xx), REGION_Y / 2.0 - np.abs(yy))
    wob = np.zeros_like(dist, dtype=np.float32)
    for amp, scale, seed in ((170.0, 62.0, 41), (74.0, 24.0, 42)):
        wob += amp * (R._value_noise((h, w), scale, seed) - 0.5) * 2.0
    # 过渡带 130px：真实岛缘是碎石渐隐进云里，不是刀切的一条
    return np.clip((RIM_DEPTH + wob - dist) / 130.0, 0.0, 1.0)


def decal_field(w, h, terrace, rim) -> np.ndarray:
    """仙气：雾团 + 雾丝两档噪声，台缘和岛缘最多，玉台上几乎没有。"""
    clumps = R._value_noise((h, w), DECAL_CLUSTER_SCALE, 31)
    fine = R._value_noise((h, w), DECAL_NOISE_SCALE, 32)
    field = clumps * 0.60 + fine * 0.40
    thr = float(np.quantile(field, 1.0 - DECAL_DENSITY))
    span = max(float(field.max() - thr), 1e-4)
    a = np.clip((field - thr) / span, 0.0, 1.0) ** 0.7
    # 越靠台缘/岛缘雾越厚：台子是从云里长出来的，岛缘更是直接泡在云里
    edge = np.clip(np.maximum(terrace * (1.0 - terrace) * 4.0, rim), 0.0, 1.0)
    a *= DECAL_BASE + (1.0 - DECAL_BASE) * np.clip(edge * DECAL_EDGE_BIAS, 0.0, 1.0)
    a *= (1.0 - terrace * 0.62)
    return a


def bake(scale: int) -> tuple[np.ndarray, dict]:
    data = read_huashen()
    w, h = int(REGION_X / scale), int(REGION_Y / scale)
    xx, yy = _grid(w, h, scale)
    terrace = terrace_field(xx, yy, data, scale)
    rim = rim_field(xx, yy, w, h)
    # 玉台上不长岛缘碎岩（同一条理由：路是踩出来的，不是树底下的腐叶）
    rim *= (1.0 - terrace * 0.9)
    cloud = np.clip(1.0 - terrace - rim, 0.0, 1.0)
    decal = decal_field(w, h, terrace, rim)
    rgb = np.stack([cloud, terrace, rim], axis=2)
    s = rgb.sum(axis=2, keepdims=True)
    rgb = np.where(s > 1e-4, rgb / np.maximum(s, 1e-4), np.array([1.0, 0.0, 0.0], dtype=np.float32))
    rgba = np.concatenate([rgb, decal[:, :, None]], axis=2)
    stats = {
        "terrace": float(terrace.mean()), "rim": float(rim.mean()),
        "terrace_px": float((terrace > 0.5).mean()), "rim_px": float((rim > 0.5).mean()),
        "decal": float(decal.mean()), "decal_px": float((decal > 0.25).mean()),
        "portal": data["portal"], "spawn": data["spawn"],
    }
    return (rgba * 255.0 + 0.5).astype(np.uint8), stats


def debug_outputs(rgba: np.ndarray) -> None:
    os.makedirs(DEBUG_DIR, exist_ok=True)
    ch = {"R_cloud": 0, "G_terrace": 1, "B_rim": 2, "A_mist": 3}
    sheet = Image.new("RGB", (rgba.shape[1] * 2 + 12, rgba.shape[0] * 2 + 12), (14, 12, 20))
    for i, (_name, idx) in enumerate(ch.items()):
        g = Image.fromarray(rgba[:, :, idx]).convert("RGB").resize((rgba.shape[1], rgba.shape[0]))
        sheet.paste(g, (10 + (i % 2) * (rgba.shape[1] + 2), 10 + (i // 2) * (rgba.shape[0] + 2)))
    sheet.save(os.path.join(DEBUG_DIR, "jiutian_mask_channels.png"))
    for name, idx in ch.items():
        Image.fromarray(rgba[:, :, idx]).save(os.path.join(DEBUG_DIR, f"jiutian_mask_{name}.png"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=8)
    ap.add_argument("--out", default=OUT_PNG)
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()
    rgba, stats = bake(args.scale)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    Image.fromarray(rgba).save(args.out)
    if args.debug:
        debug_outputs(rgba)
    print("写出", os.path.relpath(args.out, ROOT), rgba.shape[1], "x", rgba.shape[0])
    for k, v in stats.items():
        print("   %-11s %s" % (k, round(v, 4) if isinstance(v, float) else v))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
