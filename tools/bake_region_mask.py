#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""练气区（青岚野）低频地貌遮罩烘焙器。

产出一张 750x500 的 RGBA = 世界 6000x4000 的 1/8。逐像素：
    R = 草地权重   G = 土路权重   B = 林缘裸土权重   A = 贴花强度
region_terrain.gdshader 把 RGB 归一化后加权混三套 tile，A 决定碎叶贴花叠多少。

为什么是「低频遮罩 + 平方分之一的图」而不是画一整张 6000x4000 的地图：
  1) 整图必然被拉到 1.46 倍糊在 3.5 倍放大的屏幕上，笔触全碎；
  2) 遮罩只管「哪里是路、哪里是林子」这种几百像素尺度的事，细节交给能平铺的
     tile 自己出，放大多少都还是清晰的 tile；
  3) 遮罩由航点算出来，改一个药材点位重跑一次就完事，不用重画地图。

坐标口径（和 secret_world_db.gd 一致）：内容表以**区域中心**为原点，
x ∈ [-3000,3000]、y ∈ [-2000,2000]；这里全程用内容坐标，不碰 rect 左上角。

用法：
    python tools/bake_region_mask.py                 # 烘到 assets/scenes/tiles/lianqi_mask.png
    python tools/bake_region_mask.py --debug         # 顺带出遮罩四通道分解 + 合成预览
    python tools/bake_region_mask.py --scale 8       # 遮罩 = 世界 / scale（默认 8）
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_GD = os.path.join(ROOT, "scripts", "data", "secret_world_db.gd")
OUT_PNG = os.path.join(ROOT, "assets", "scenes", "tiles", "lianqi_mask.png")
DEBUG_DIR = os.path.join(ROOT, "output", "tiles")

REGION_X, REGION_Y = 6000.0, 4000.0

## ===== 地貌参数 =====
## 土路：主干 / 次干 / 支路三级。宽度是世界像素，peak 是这条路的最大权重
## （支路压到 0.55 是为了让它「隐进草里」，否则地图上会爬满细白管子）。
ROAD_TIERS = (
    {"width": 112.0, "peak": 1.00, "feather": 30.0},   # 传送门到腹地这一段
    {"width": 76.0, "peak": 0.90, "feather": 24.0},
    {"width": 46.0, "peak": 0.55, "feather": 18.0},
)
## 林缘：树线以内多宽算「树底下」。过渡做成长尾，因为真实林缘是疏密渐变不是刀切。
FOREST_FEATHER = 210.0     # 树线往草地一侧的渐变宽度
## 树线起伏用两个八度：只有大八度会画出一条均匀的波浪边，像烫过的头发；
## 叠一个小八度才出现往里凹的树湾和往外伸的指状林梢。
FOREST_RAGGED = ((150.0, 620.0), (72.0, 210.0))

## ===== 贴花（A 通道）=====
## 碎叶/枯草丛。逻辑是「越靠近树线越多，路上没有」——落叶堆在林边，路被人踩秃。
DECAL_DENSITY = 0.30       # 全区平均覆盖率
DECAL_EDGE_BIAS = 2.1      # 树线附近的加权倍数
DECAL_NOISE_SCALE = 96.0
DECAL_CLUSTER_SCALE = 34.0


# ---------------------------------------------------------------- 数据读取

def _vec2(s: str) -> tuple[float, float] | None:
    m = re.fullmatch(r"Vector2\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)", s.replace(" ", ""))
    if m:
        return float(m.group(1)), float(m.group(2))
    if "Vector2.ZERO" in s:
        return 0.0, 0.0
    return None


def read_region(text: str) -> dict:
    """从 secret_world_db.gd 里抠出练气区的 rect / wall_inset / 全部航点。

    不 import Godot、不复制一份常量表：复制的那份一定会和 .gd 漂移，
    而这张遮罩的正确性完全依赖航点跟游戏里长在同一张图上。
    结构一变就 assert 出声，比静默烘出一张错位地图好。
    """
    m = re.search(r'"region_id":\s*REGION_LIANQI.*?\n\t\},', text, re.S)
    if not m:
        raise SystemExit("练气区 REGIONS 条目没找到，.gd 结构变了？")
    blk = m.group(0)
    rect = re.search(r'"rect":\s*Rect2\(([^)]*)\)', blk)
    inset = re.search(r'"wall_inset":\s*\{([^}]*)\}', blk)
    if not rect or not inset:
        raise SystemExit("练气区的 rect / wall_inset 缺一个")
    rw, rh = float(rect.group(1).split(",")[2]), float(rect.group(1).split(",")[3])
    if (rw, rh) != (REGION_X, REGION_Y):
        raise SystemExit(f"练气区 rect 尺寸变成 {rw}x{rh}，遮罩分辨率参数要跟着改")
    wall = {k: float(v) for k, v in re.findall(r'"(north|west|south|east)":\s*([\d.]+)', inset.group(1))}

    cm = re.search(r"const LIANQI_CONTENT: Dictionary = \{(.*?)\n\}", text, re.S)
    if not cm:
        raise SystemExit("LIANQI_CONTENT 没找到")
    content = cm.group(1)

    def section(name: str, nxt: str | None = None) -> str:
        i = content.find(f'"{name}"')
        if i < 0:
            raise SystemExit(f'LIANQI_CONTENT 里没有 "{name}"')
        j = content.find(f'"{nxt}"', i + 1) if nxt else -1
        return content[i:j if j > 0 else len(content)]

    def positions(blob: str) -> list[tuple[float, float]]:
        return [v for v in (_vec2(x) for x in re.findall(r'"pos":\s*(Vector2\([^)]*\)|Vector2\.ZERO)', blob)) if v]

    portal = positions(section("portal", "core_boss"))
    core = positions(section("core_boss", "farm"))
    farm = positions(section("farm", "herbs"))
    herbs = positions(section("herbs", "beasts"))
    beasts = positions(section("beasts", "qi_orbs"))
    qi = positions(section("qi_orbs", "cultivators"))
    cult = positions(section("cultivators"))
    got = {
        "portal": len(portal), "core": len(core), "farm": len(farm),
        "herbs": len(herbs), "qi": len(qi), "cult": len(cult),
    }
    want = {"portal": 1, "core": 1, "farm": 1, "herbs": 16, "qi": 6, "cult": 2}
    if got != want:
        raise SystemExit(f"航点数量对不上：读到 {got}，期望 {want}（.gd 里加了/删了点位？）")
    return {
        "wall": wall,
        "nodes": portal + core + farm + qi + cult,
        "herbs": herbs,
        "beasts": beasts,
    }


def cluster(points: list[tuple[float, float]], radius: float) -> list[tuple[float, float]]:
    """把散点按半径聚成簇心 —— 一簇药材只该引一条支路过去，不是一株一条。"""
    centers: list[list[float]] = []
    for x, y in points:
        for c in centers:
            if math.hypot(x - c[0] / c[2], y - c[1] / c[2]) < radius:
                c[0] += x; c[1] += y; c[2] += 1.0
                break
        else:
            centers.append([x, y, 1.0])
    return [(c[0] / c[2], c[1] / c[2]) for c in centers]


# ---------------------------------------------------------------- 路网

def _mst(nodes: list[tuple[float, float]]) -> list[tuple[int, int]]:
    """Prim 最小生成树。手写而不是拉 networkx：16 个点，O(n^2) 十几行，
    装一个图论依赖来连线不值得。"""
    n = len(nodes)
    if n < 2:
        return []
    in_tree = [False] * n
    in_tree[0] = True
    edges: list[tuple[int, int]] = []
    for _ in range(n - 1):
        best = None
        for i in range(n):
            if not in_tree[i]:
                continue
            for j in range(n):
                if in_tree[j]:
                    continue
                d = math.dist(nodes[i], nodes[j])
                if best is None or d < best[0]:
                    best = (d, i, j)
        _, i, j = best
        in_tree[j] = True
        edges.append((i, j))
    return edges


def _catmull_seg(a, b, c, d, n: int) -> list[tuple[float, float]]:
    """标准 Catmull-Rom 的一段：起点 b、终点 c。"""
    pts = []
    for k in range(n):
        t = k / float(n - 1)
        t2, t3 = t * t, t * t * t
        def axis(i):
            return 0.5 * ((2 * b[i]) + (-a[i] + c[i]) * t
                          + (2 * a[i] - 5 * b[i] + 4 * c[i] - d[i]) * t2
                          + (-a[i] + 3 * b[i] - 3 * c[i] + d[i]) * t3)
        pts.append((axis(0), axis(1)))
    return pts


def _curved(p0, p1, rng) -> list[tuple[float, float]]:
    """两点之间插一个横向偏移的中点，再用 Catmull-Rom 采出一条带弧度的折线。
    直连线看着像规划图，真实土路是绕出来的。

    ⚠ 必须串两段：一段 CR 只走 b->c，即 p0->mid，只采一半会把每条路都截成
    半截（第一版实测土路 Coverage 因此少了一半）。
    """
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = max(math.hypot(dx, dy), 1.0)
    off = rng.uniform(-0.14, 0.14) * ln
    mx, my = (p0[0] + p1[0]) / 2 - dy / ln * off, (p0[1] + p1[1]) / 2 + dx / ln * off
    mid = (mx, my)
    return _catmull_seg(p0, p0, mid, p1, 17) + _catmull_seg(p0, mid, p1, p1, 17)[1:]


def build_roads(nodes, herbs, beasts, scale: int):
    """节点表 → 带弧度的分层路网。画布坐标 = 内容坐标 + 半张图，再除 scale。

    药材和灵兽都先按半径聚成簇再当节点：一簇三株若各引一条路，地图上会出现
    三条并行的细管子，看着像血管不像人走的。
    """
    pts = list(nodes) + cluster(herbs, 460.0) + cluster(beasts, 520.0)
    edges = _mst(pts)
    adj: dict[int, list[int]] = {i: [] for i in range(len(pts))}
    for a, b in edges:
        adj[a].append(b); adj[b].append(a)
    ## 分级按「这条边后面挂着多少个点」，不按离传送门几跳。
    ## 用跳数分过一版：传送门在东南角，MST 从它拉出去是一条长链，
    ## 结果 26 条边里 24 条被判成支路，整张图只剩细管子、看不见主道。
    parent = {0: -1}
    order = [0]
    for u in order:
        for v in adj[u]:
            if v not in parent:
                parent[v] = u
                order.append(v)
    sub = {i: 1 for i in range(len(pts))}
    for u in reversed(order):          # 自底向上累加子树规模
        if parent[u] >= 0:
            sub[parent[u]] += sub[u]
    rng = np.random.default_rng(20261026)
    layers = []
    for a, b in edges:
        beyond = sub[b] if parent[b] == a else sub[a]   # 靠叶子那一侧的规模
        tier = 0 if beyond >= 8 else (1 if beyond >= 3 else 2)
        layers.append((tier, _curved(pts[a], pts[b], rng)))
    return layers


def road_field(layers, w: int, h: int, scale: int) -> np.ndarray:
    """每一级单独画线再模糊：宽度和羽化都不同，混在一张图上做不出来。"""
    out = np.zeros((h, w), dtype=np.float32)
    # 内容坐标原点在区域中心，画布原点在左上角：不先平移，一半的路会画到画外去
    # （PIL 不报错，只是安静地什么都不画，于是遮罩上路 Coverage 掉到 0.1%）。
    ox, oy = w / 2.0, h / 2.0
    for tier, chain in layers:
        spec = ROAD_TIERS[tier]
        img = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(img)
        px = [(x / scale + ox, y / scale + oy) for x, y in chain]
        d.line(px, fill=255, width=max(1, int(spec["width"] / scale)), joint="curve")
        f = gaussian_filter(np.asarray(img, dtype=np.float32) / 255.0,
                            spec["feather"] / scale, mode="constant")
        out = np.maximum(out, np.clip(f, 0.0, 1.0) * spec["peak"])
    return out


# ---------------------------------------------------------------- 林缘 / 贴花

def _value_noise(shape, cell: float, seed: int) -> np.ndarray:
    """双线性插值的网格噪声。用来给树线加起伏、给贴花做团块，
    不需要真正的 fBm —— 低频遮罩本来就只关心几百像素尺度的事。"""
    h, w = shape
    rng = np.random.default_rng(seed)
    gw, gh = int(math.ceil(w / cell)) + 2, int(math.ceil(h / cell)) + 2
    grid = rng.random((gh, gw)).astype(np.float32)
    ys = np.arange(h, dtype=np.float32) / cell
    xs = np.arange(w, dtype=np.float32) / cell
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None].astype(np.float32); fx = (xs - x0)[None, :].astype(np.float32)
    y0 = y0[:, None]; x0 = x0[None, :]
    def g(dy, dx):
        return grid[y0 + dy, x0 + dx]
    smooth = lambda t: t * t * (3.0 - 2.0 * t)
    a = g(0, 0) * (1 - fx) + g(0, 1) * fx
    b = g(1, 0) * (1 - fx) + g(1, 1) * fx
    return a * (1 - smooth(fy)) + b * smooth(fy)


def forest_field(w: int, h: int, wall: dict, scale: int) -> np.ndarray:
    """南、东两条边按 wall_inset 内缩出树线，树线以外是林缘裸土，往草地方向渐变。

    北/西的 inset 只有 40 —— 那是通往其它区域的路，不种树（2026-10-23 定），
    所以只在这两条边上生成。
    """
    hw, hh = REGION_X / 2.0, REGION_Y / 2.0
    xs = (np.arange(w, dtype=np.float32) + 0.5) * scale - hw
    ys = (np.arange(h, dtype=np.float32) + 0.5) * scale - hh
    X, Y = np.meshgrid(xs, ys)
    rag = np.zeros((h, w), dtype=np.float32)
    for i, (amp, cell) in enumerate(FOREST_RAGGED):
        rag += (_value_noise((h, w), cell / scale, 7 + i) - 0.5) * 2.0 * amp
    # 到树线的有符号距离：>0 已经走进林子，<0 还在草地里。两条边取更深的那个，
    # 于是东南角自然合成一片连起来的拐角林，而不是两条各画各的带子。
    depth = np.maximum(Y - (hh - wall["south"] + rag), X - (hw - wall["east"] + rag))
    t = np.clip((depth + FOREST_FEATHER) / FOREST_FEATHER, 0.0, 1.0)
    return (t * t * (3.0 - 2.0 * t)).astype(np.float32)


def decal_field(w: int, h: int, road: np.ndarray, forest: np.ndarray) -> np.ndarray:
    """A 通道 = 碎叶贴花强度。团块噪声过一遍阈值，再按「离树线多近」加权，路上抹掉。"""
    clumps = _value_noise((h, w), DECAL_CLUSTER_SCALE, 21)
    fine = _value_noise((h, w), DECAL_NOISE_SCALE, 22)
    field = clumps * 0.65 + fine * 0.35
    ## 阈值取分位数而不是写死：值噪声是尖峰分布，(field - 0.7) 那种写法实际只覆盖
    ## 0.9% 的地图，等于没有贴花。取 (1-DENSITY) 分位数才让 DECAL_DENSITY 真的是覆盖率。
    thr = float(np.quantile(field, 1.0 - DECAL_DENSITY))
    span = max(float(field.max() - thr), 1e-4)
    a = np.clip((field - thr) / span, 0.0, 1.0) ** 0.7
    # 树根下落叶最多，往外衰减到 DECAL_EDGE_BIAS 分之一
    near_edge = np.clip(forest * DECAL_EDGE_BIAS, 0.0, 1.0)
    a *= 0.35 + 0.65 * near_edge
    a *= (1.0 - road)
    return a


# ---------------------------------------------------------------- 主流程

def bake(scale: int) -> tuple[np.ndarray, dict]:
    text = open(DB_GD, encoding="utf-8").read()
    data = read_region(text)
    w, h = int(REGION_X / scale), int(REGION_Y / scale)
    road = road_field(build_roads(data["nodes"], data["herbs"], data["beasts"], scale), w, h, scale)
    forest = forest_field(w, h, data["wall"], scale)
    # 路上不长林缘裸土：路要看得出来是踩出来的，不是树底下的腐叶。
    forest *= (1.0 - road * 0.85)
    grass = np.clip(1.0 - road - forest, 0.0, 1.0)
    decal = decal_field(w, h, road, forest)
    rgb = np.stack([grass, road, forest], axis=2)
    s = rgb.sum(axis=2, keepdims=True)
    rgb = np.where(s > 1e-4, rgb / np.maximum(s, 1e-4), np.array([1.0, 0.0, 0.0], dtype=np.float32))
    rgba = np.concatenate([rgb, decal[:, :, None]], axis=2)
    stats = {
        "road": float(road.mean()), "forest": float(forest.mean()),
        "road_px": float((road > 0.5).mean()), "forest_px": float((forest > 0.5).mean()),
        "decal": float(decal.mean()), "decal_px": float((decal > 0.25).mean()),
        "wall": data["wall"],
    }
    return (rgba * 255.0 + 0.5).astype(np.uint8), stats


def debug_outputs(rgba: np.ndarray) -> None:
    os.makedirs(DEBUG_DIR, exist_ok=True)
    ch = {"R_grass": 0, "G_road": 1, "B_forest": 2, "A_decal": 3}
    sheet = Image.new("RGB", (rgba.shape[1] * 2 + 10, rgba.shape[0] * 2 + 10), (24, 24, 24))
    for i, (name, idx) in enumerate(ch.items()):
        g = Image.fromarray(rgba[:, :, idx])
        sheet.paste(g.convert("RGB"), ((i % 2) * (rgba.shape[1] + 10), (i // 2) * (rgba.shape[0] + 10)))
    sheet.save(os.path.join(DEBUG_DIR, "mask_channels.png"))
    for name, idx in ch.items():
        Image.fromarray(rgba[:, :, idx]).save(os.path.join(DEBUG_DIR, f"mask_{name}.png"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=8, help="遮罩 = 世界 / scale")
    ap.add_argument("--out", default=OUT_PNG)
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    rgba, stats = bake(args.scale)
    if args.debug:
        debug_outputs(rgba)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    Image.fromarray(rgba).save(args.out)
    h, w = rgba.shape[:2]
    print(f"遮罩 {w}x{h}  (世界 {REGION_X:.0f}x{REGION_Y:.0f} / {args.scale})  ->  {os.path.relpath(args.out, ROOT)}")
    print(f"  土路  均值 {stats['road']:.3f}   覆盖(>0.5) {stats['road_px'] * 100:.1f}%")
    print(f"  林缘  均值 {stats['forest']:.3f}   覆盖(>0.5) {stats['forest_px'] * 100:.1f}%")
    print(f"  贴花  均值 {stats['decal']:.3f}   覆盖(>0.25) {stats['decal_px'] * 100:.1f}%")
    print(f"  wall_inset {stats['wall']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
