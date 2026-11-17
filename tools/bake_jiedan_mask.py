#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""赤金丹霞（结丹区）低频地貌遮罩：750x500 RGBA，世界 6000x4000 的 1/8。

和练气 / 云隐谷同一套通道口径：
    R = 赤金草地   G = 土路   B = 焦土（林缘裸土位）   A = 碎叶贴花
差别只在布局：
  · 西 / 北 / 南三面有崖壁林带（wall_inset 400 / 480 / 355），东沿与云隐谷
    直接相接，不种树（inset 0），改铺竖向接缝过渡；
  · 传送门在左上角，区域中心是霞心首领场 —— 场心铺一圈焦土，把日轮祭坛
    和周围的赤金草地分开；
  · 没有灵田，航点是 传送门 + 霞心 + 灵气团 + 野修 + 草药簇 + 灵兽簇。

用法：
    python tools/bake_jiedan_mask.py            # 出 assets/scenes/tiles/jiedan_mask.png
    python tools/bake_jiedan_mask.py --debug    # 顺带出通道分解 / 路网预览
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_region_mask as M  # noqa: E402

ROOT = M.ROOT
DB_GD = M.DB_GD
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")
OUT_PNG = os.path.join(TILE_DIR, "jiedan_mask.png")
DEBUG_DIR = M.DEBUG_DIR

REGION_X, REGION_Y = 6000.0, 4000.0
## 霞心焦土：以区域中心为圆心的焦土圆盘（世界半径 / 羽化）
## ⚠ 2026-10-29 实测后关掉：B 通道用的是「林缘裸土」tile，丹霞这张是**落叶**
##   （秋叶 + 枯枝），铺在霞心读成一片树林底下，不是焦土。霞心改由日轮祭坛
##   本体 + 二阶段灼土层来区分；这里的圆盘参数留着，换到真正的焦土 tile 再开。
ASH_RADIUS = 760.0
ASH_FEATHER = 300.0
ASH_PEAK = 0.0
## 三条崖壁边的林缘羽化（往草地一侧）
FOREST_FEATHER = 240.0
FOREST_RAGGED = ((170.0, 700.0), (80.0, 240.0))


def _vec2(s: str):
	return M._vec2(s)


def read_jiedan(text: str) -> dict:
	m = re.search(r'"region_id":\s*REGION_JIEDAN.*?\n\t\},', text, re.S)
	if not m:
		raise SystemExit("结丹区 REGIONS 条目没找到，.gd 结构变了？")
	blk = m.group(0)
	rect = re.search(r'"rect":\s*Rect2\(([^)]*)\)', blk)
	inset = re.search(r'"wall_inset":\s*\{([^}]*)\}', blk)
	if not rect or not inset:
		raise SystemExit("结丹区的 rect / wall_inset 缺一个")
	rw, rh = float(rect.group(1).split(",")[2]), float(rect.group(1).split(",")[3])
	if (rw, rh) != (REGION_X, REGION_Y):
		raise SystemExit(f"结丹区 rect 尺寸变成 {rw}x{rh}，遮罩分辨率参数要跟着改")
	wall = {k: float(v) for k, v in re.findall(r'"(north|west|south|east)":\s*([\d.]+)', inset.group(1))}

	cm = re.search(r"const JIEDAN_CONTENT: Dictionary = \{(.*?)\n\}", text, re.S)
	if not cm:
		raise SystemExit("JIEDAN_CONTENT 没找到")
	content = cm.group(1)

	def section(name: str, nxt: str | None = None) -> str:
		i = content.find(f'"{name}"')
		if i < 0:
			raise SystemExit(f'JIEDAN_CONTENT 里没有 "{name}"')
		j = content.find(f'"{nxt}"', i + 1) if nxt else -1
		return content[i:j if j > 0 else len(content)]

	def positions(blob: str):
		return [v for v in (_vec2(x) for x in re.findall(
			r'"pos":\s*(Vector2\([^)]*\)|Vector2\.ZERO)', blob)) if v]

	portal = positions(section("portal", "spawn"))
	core = positions(section("core_boss", "portal"))
	herbs = positions(section("herbs", "beasts"))
	beasts = positions(section("beasts", "qi_orbs"))
	qi = positions(section("qi_orbs", "cultivators"))
	cult = positions(section("cultivators"))
	got = {"portal": len(portal), "core": len(core), "herbs": len(herbs),
		"qi": len(qi), "cult": len(cult)}
	want = {"portal": 1, "core": 1, "herbs": 16, "qi": 6, "cult": 2}
	if got != want:
		raise SystemExit(f"航点数量对不上：读到 {got}，期望 {want}（.gd 里加了/删了点位？）")
	return {"wall": wall, "nodes": portal + core + qi + cult,
		"herbs": herbs, "beasts": beasts}


def forest_field(w: int, h: int, wall: dict, scale: int) -> np.ndarray:
	hw, hh = REGION_X / 2.0, REGION_Y / 2.0
	xs = (np.arange(w, dtype=np.float32) + 0.5) * scale - hw
	ys = (np.arange(h, dtype=np.float32) + 0.5) * scale - hh
	X, Y = np.meshgrid(xs, ys)
	rag = np.zeros((h, w), dtype=np.float32)
	for i, (amp, cell) in enumerate(FOREST_RAGGED):
		rag += (M._value_noise((h, w), cell / scale, 31 + i) - 0.5) * 2.0 * amp
	# 三条崖壁：越往崖里越深；东沿不种树，留 -1e9
	west_line = -hw + wall["west"]
	north_line = -hh + wall["north"]
	south_line = hh - wall["south"]
	depth = np.maximum.reduce([
		(west_line - X) + rag,
		(north_line - Y) + rag,
		(Y - south_line) + rag,
		np.full((h, w), -1.0e9, dtype=np.float32),
	])
	t = np.clip((depth + FOREST_FEATHER) / FOREST_FEATHER, 0.0, 1.0)
	edge = t * t * (3.0 - 2.0 * t)
	# 霞心焦土：以区域中心为圆心的焦土圆盘（内深外浅，不是外圈糊一圈）
	r = np.sqrt(X * X + Y * Y)
	ta = np.clip((ASH_RADIUS + ASH_FEATHER - r) / ASH_FEATHER, 0.0, 1.0)
	ash = (ta * ta * (3.0 - 2.0 * ta)) * ASH_PEAK
	return np.maximum(edge, ash).astype(np.float32)


def bake(scale: int) -> np.ndarray:
	text = open(DB_GD, encoding="utf-8").read()
	data = read_jiedan(text)
	w, h = int(REGION_X / scale), int(REGION_Y / scale)
	road = M.road_field(M.build_roads(data["nodes"], data["herbs"], data["beasts"], scale),
		w, h, scale)
	forest = forest_field(w, h, data["wall"], scale)
	forest *= (1.0 - road * 0.80)
	grass = np.clip(1.0 - road - forest, 0.0, 1.0)
	decal = M.decal_field(w, h, road, forest)
	rgb = np.stack([grass, road, forest], axis=2)
	s = rgb.sum(axis=2, keepdims=True)
	rgb = np.where(s > 1e-4, rgb / np.maximum(s, 1e-4), np.array([1.0, 0.0, 0.0], dtype=np.float32))
	rgba = np.concatenate([rgb, decal[:, :, None]], axis=2)
	print(f"mask {w}x{h}  road {road.mean() * 100:.1f}%  forest {forest.mean() * 100:.1f}%  "
		f"decal {decal.mean() * 100:.1f}%")
	return rgba


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--scale", type=int, default=8)
	ap.add_argument("--debug", action="store_true")
	args = ap.parse_args()
	rgba = bake(args.scale)
	os.makedirs(TILE_DIR, exist_ok=True)
	Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), "RGBA").save(OUT_PNG)
	print("->", os.path.relpath(OUT_PNG, ROOT))
	if args.debug:
		os.makedirs(DEBUG_DIR, exist_ok=True)
		for i, name in enumerate(("grass", "road", "forest", "decal")):
			Image.fromarray((np.clip(rgba[:, :, i], 0, 1) * 255).astype(np.uint8)).save(
				os.path.join(DEBUG_DIR, f"jiedan_mask_{name}.png"))
		prev = np.clip(rgba[:, :, :3] * 0.9, 0, 1)
		Image.fromarray((prev * 255).astype(np.uint8)).resize((900, 600), Image.LANCZOS).save(
			os.path.join(DEBUG_DIR, "jiedan_mask_preview.png"))
		print("debug ->", os.path.relpath(DEBUG_DIR, ROOT))
	return 0


if __name__ == "__main__":
	sys.exit(main())
