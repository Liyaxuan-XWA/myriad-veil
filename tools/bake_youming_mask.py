#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""幽冥灵墟（元婴区）低频地貌遮罩：750x500 RGBA，世界 6000x4000 的 1/8。

和前三区同一套通道口径：
    R = 幽冥草地   G = 残砖路   B = 墟土（林缘裸土位）   A = 碎叶贴花
差别在布局：
  · 西 / 南两面有墙（wall_inset 400 / 355）；北接赤金丹霞、东邻青岚野，
    不种墙，改铺地面过渡条；
  · 区域中心是灵墟山门（纯景观），把山门当作路网中心节点，四条路从门洞前穿过；
  · 传送门在西南角，航点是 传送门 + 山门 + 灵气团 + 野修 + 草药簇 + 灵兽簇。

用法：
    python tools/bake_youming_mask.py            # 出 assets/scenes/tiles/youming_mask.png
    python tools/bake_youming_mask.py --debug    # 顺带出通道分解 / 路网预览
"""
from __future__ import annotations

import argparse
import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_region_mask as M  # noqa: E402

ROOT = M.ROOT
DB_GD = M.DB_GD
TILE_DIR = os.path.join(ROOT, "assets", "scenes", "tiles")
OUT_PNG = os.path.join(TILE_DIR, "youming_mask.png")
DEBUG_DIR = M.DEBUG_DIR

REGION_X, REGION_Y = 6000.0, 4000.0
## 西 / 南墙往草地一侧的林缘（断墙脚下堆着墟土与枯草）
FOREST_FEATHER = 250.0
FOREST_RAGGED = ((165.0, 680.0), (78.0, 230.0))


def _vec2(s: str):
	return M._vec2(s)


def read_youming(text: str) -> dict:
	m = re.search(r'"region_id":\s*REGION_YUANYING.*?\n\t\},', text, re.S)
	if not m:
		raise SystemExit("元婴区 REGIONS 条目没找到，.gd 结构变了？")
	blk = m.group(0)
	rect = re.search(r'"rect":\s*Rect2\(([^)]*)\)', blk)
	inset = re.search(r'"wall_inset":\s*\{([^}]*)\}', blk)
	if not rect or not inset:
		raise SystemExit("元婴区的 rect / wall_inset 缺一个")
	rw, rh = float(rect.group(1).split(",")[2]), float(rect.group(1).split(",")[3])
	if (rw, rh) != (REGION_X, REGION_Y):
		raise SystemExit(f"元婴区 rect 尺寸变成 {rw}x{rh}，遮罩分辨率参数要跟着改")
	wall = {k: float(v) for k, v in re.findall(r'"(north|west|south|east)":\s*([\d.]+)', inset.group(1))}

	cm = re.search(r"const YUANYING_CONTENT: Dictionary = \{(.*?)\n\}", text, re.S)
	if not cm:
		raise SystemExit("YUANYING_CONTENT 没找到")
	content = cm.group(1)

	def section(name: str, nxt: str | None = None) -> str:
		i = content.find(f'"{name}"')
		if i < 0:
			raise SystemExit(f'YUANYING_CONTENT 里没有 "{name}"')
		j = content.find(f'"{nxt}"', i + 1) if nxt else -1
		return content[i:j if j > 0 else len(content)]

	def positions(blob: str):
		return [v for v in (_vec2(x) for x in re.findall(
			r'"pos":\s*(Vector2\([^)]*\)|Vector2\.ZERO)', blob)) if v]

	portal = positions(section("portal", "spawn"))
	herbs = positions(section("herbs", "beasts"))
	beasts = positions(section("beasts", "qi_orbs"))
	qi = positions(section("qi_orbs", "cultivators"))
	cult = positions(section("cultivators"))
	got = {"portal": len(portal), "herbs": len(herbs), "qi": len(qi), "cult": len(cult)}
	want = {"portal": 1, "herbs": 16, "qi": 6, "cult": 2}
	if got != want:
		raise SystemExit(f"航点数量对不上：读到 {got}，期望 {want}（.gd 里加了/删了点位？）")
	## 山门在区域中心（landmark.pos = ZERO），作为路网的中央枢纽
	return {"wall": wall, "nodes": portal + [(0.0, 0.0)] + qi + cult,
		"herbs": herbs, "beasts": beasts}


def forest_field(w: int, h: int, wall: dict, scale: int) -> np.ndarray:
	hw, hh = REGION_X / 2.0, REGION_Y / 2.0
	xs = (np.arange(w, dtype=np.float32) + 0.5) * scale - hw
	ys = (np.arange(h, dtype=np.float32) + 0.5) * scale - hh
	X, Y = np.meshgrid(xs, ys)
	rag = np.zeros((h, w), dtype=np.float32)
	for i, (amp, cell) in enumerate(FOREST_RAGGED):
		rag += (M._value_noise((h, w), cell / scale, 71 + i) - 0.5) * 2.0 * amp
	west_line = -hw + wall["west"]
	south_line = hh - wall["south"]
	depth = np.maximum.reduce([
		(west_line - X) + rag,
		(Y - south_line) + rag,
		np.full((h, w), -1.0e9, dtype=np.float32),
	])
	t = np.clip((depth + FOREST_FEATHER) / FOREST_FEATHER, 0.0, 1.0)
	return (t * t * (3.0 - 2.0 * t)).astype(np.float32)


def bake(scale: int) -> np.ndarray:
	text = open(DB_GD, encoding="utf-8").read()
	data = read_youming(text)
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
				os.path.join(DEBUG_DIR, f"youming_mask_{name}.png"))
		prev = np.clip(rgba[:, :, :3] * 0.9, 0, 1)
		Image.fromarray((prev * 255).astype(np.uint8)).resize((900, 600), Image.LANCZOS).save(
			os.path.join(DEBUG_DIR, "youming_mask_preview.png"))
		print("debug ->", os.path.relpath(DEBUG_DIR, ROOT))
	return 0


if __name__ == "__main__":
	sys.exit(main())
