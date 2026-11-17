#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""云隐谷（筑基区）低频地貌遮罩烘焙器。

和练气区同一套口径：750x500 的 RGBA，R=草 / G=土路 / B=林缘裸土 / A=贴花。
差别只有三处：
  · 林缘在东、北两条外沿；南沿是接缝林带，中间留出南口（局部 x=0 附近）；
  · 起点是内容表的 spawn（谷地南口），不是传送门；
  · 没有核心首领 / 灵田航点。

用法：
    python tools/bake_zhuji_mask.py
    python tools/bake_zhuji_mask.py --debug
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_region_mask as B  # noqa: E402  复用路网 / 贴花 / 噪声

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_GD = os.path.join(ROOT, "scripts", "data", "secret_world_db.gd")
OUT_PNG = os.path.join(ROOT, "assets", "scenes", "tiles", "zhuji_mask.png")
DEBUG_DIR = os.path.join(ROOT, "output", "tiles", "zhuji")

REGION_X, REGION_Y = 6000.0, 4000.0
## 接缝林带：从南沿往谷内多深算树荫；南口半宽（世界 x）
SEAM_FOREST_DEPTH = 300.0
SEAM_GAP_HALF = 360.0
SEAM_GAP_FEATHER = 140.0


def read_region(text: str) -> dict:
    m = re.search(r'"region_id":\s*REGION_ZHUJI.*?\n\t\},', text, re.S)
    if not m:
        raise SystemExit("云隐谷 REGIONS 条目没找到，.gd 结构变了？")
    blk = m.group(0)
    rect = re.search(r'"rect":\s*Rect2\(([^)]*)\)', blk)
    inset = re.search(r'"wall_inset":\s*\{([^}]*)\}', blk)
    if not rect or not inset:
        raise SystemExit("云隐谷的 rect / wall_inset 缺一个")
    parts = [float(x) for x in rect.group(1).split(",")]
    rw, rh = parts[2], parts[3]
    if (rw, rh) != (REGION_X, REGION_Y):
        raise SystemExit(f"云隐谷 rect 尺寸变成 {rw}x{rh}，遮罩分辨率参数要跟着改")
    wall = {k: float(v) for k, v in re.findall(r'"(north|west|south|east)":\s*([\d.]+)', inset.group(1))}

    cm = re.search(r"const ZHUJI_CONTENT: Dictionary = \{(.*?)\n\}", text, re.S)
    if not cm:
        raise SystemExit("ZHUJI_CONTENT 没找到")
    content = cm.group(1)

    def section(name: str, nxt: str) -> str:
        i = content.find(f'"{name}"')
        if i < 0:
            raise SystemExit(f'ZHUJI_CONTENT 里没有 "{name}"')
        j = content.find(f'"{nxt}"', i + 1)
        return content[i:j if j > 0 else len(content)]

    def positions(blob: str) -> list[tuple[float, float]]:
        return [v for v in (B._vec2(x) for x in re.findall(
            r'"pos":\s*(Vector2\([^)]*\)|Vector2\.ZERO)', blob)) if v]

    spawn = positions(section("spawn", "beasts"))
    herbs = positions(section("herbs", "spawn"))
    beasts = positions(section("beasts", "qi_orbs"))
    qi = positions(section("qi_orbs", "cultivators"))
    cult = positions(section("cultivators", ""))
    got = {"spawn": len(spawn), "herbs": len(herbs), "beasts": len(beasts),
           "qi": len(qi), "cult": len(cult)}
    want = {"spawn": 1, "herbs": 16, "beasts": 8, "qi": 6, "cult": 2}
    if got != want:
        raise SystemExit(f"航点数量对不上：读到 {got}，期望 {want}（.gd 里加了/删了点位？）")
    # 南口当作一个虚拟节点，让主路从 spawn 一直走到接缝缺口
    pass_node = [(0.0, REGION_Y / 2.0 - 50.0)]
    return {
        "wall": wall,
        "nodes": spawn + pass_node + qi + cult,
        "herbs": herbs,
        "beasts": beasts,
    }


def forest_field_zhuji(w: int, h: int, scale: int) -> np.ndarray:
    """东、北两条外沿的树线 + 南沿接缝林带（中间留南口）。

    坐标口径与内容表一致：区域中心为原点，x ∈ [-3000,3000]、y ∈ [-2000,2000]。
    """
    hw, hh = REGION_X / 2.0, REGION_Y / 2.0
    xs = (np.arange(w, dtype=np.float32) + 0.5) * scale - hw
    ys = (np.arange(h, dtype=np.float32) + 0.5) * scale - hh
    X, Y = np.meshgrid(xs, ys)
    rag = np.zeros((h, w), dtype=np.float32)
    for i, (amp, cell) in enumerate(B.FOREST_RAGGED):
        rag += (B._value_noise((h, w), cell / scale, 7 + i) - 0.5) * 2.0 * amp

    # 东：树线从 rect 右沿内缩 400，林缘往草地里渐变
    east = X - (hw - 400.0 + rag)
    # 北：树线从 rect 上沿内缩 480（与 wall_inset.north 同口径）
    north = (-hh + 480.0 - rag) - Y
    # 南沿接缝：一条东西向林带，南口（局部 x=0 附近）不种树
    seam = Y - (hh - SEAM_FOREST_DEPTH + rag)
    gap = np.clip((np.abs(X) - SEAM_GAP_HALF) / SEAM_GAP_FEATHER, 0.0, 1.0)
    gap = gap * gap * (3.0 - 2.0 * gap)
    # 缺口内必须是「远离树线」的负值，不能简单乘 0 —— 0 会被 np.maximum 当成
    # 比东西两侧的负深度更大，整条南口反而变成满森林（首版 750×500 实测）。
    seam = seam * gap - (1.0 - gap) * 100000.0

    depth = np.maximum(np.maximum(east, north), seam)
    t = np.clip((depth + B.FOREST_FEATHER) / B.FOREST_FEATHER, 0.0, 1.0)
    return (t * t * (3.0 - 2.0 * t)).astype(np.float32)


def bake(scale: int) -> tuple[np.ndarray, dict]:
    text = open(DB_GD, encoding="utf-8").read()
    data = read_region(text)
    w, h = int(REGION_X / scale), int(REGION_Y / scale)
    road = B.road_field(B.build_roads(data["nodes"], data["herbs"], data["beasts"], scale),
                        w, h, scale)
    forest = forest_field_zhuji(w, h, scale)
    forest *= (1.0 - road * 0.85)
    grass = np.clip(1.0 - road - forest, 0.0, 1.0)
    decal = B.decal_field(w, h, road, forest)
    rgb = np.stack([grass, road, forest], axis=2)
    s = rgb.sum(axis=2, keepdims=True)
    rgb = np.where(s > 1e-4, rgb / np.maximum(s, 1e-4),
                   np.array([1.0, 0.0, 0.0], dtype=np.float32))
    rgba = np.concatenate([rgb, decal[:, :, None]], axis=2)
    stats = {
        "road": float(road.mean()), "forest": float(forest.mean()),
        "road_px": float((road > 0.5).mean()), "forest_px": float((forest > 0.5).mean()),
        "decal": float(decal.mean()), "decal_px": float((decal > 0.25).mean()),
        "wall": data["wall"],
    }
    return (rgba * 255.0 + 0.5).astype(np.uint8), stats


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=8, help="遮罩 = 世界 / scale")
    ap.add_argument("--out", default=OUT_PNG)
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()
    rgba, stats = bake(args.scale)
    if args.debug:
        B.DEBUG_DIR = DEBUG_DIR
        B.debug_outputs(rgba)
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
