extends Node2D
## 执灯（影族）八式特效实机尺寸截图 + 柔边度量（2026-11-04 用户报「还是硬边色块」）
##
## ⚠ 必须窗口化跑：要的是"叠在真实地面上、按实机显示尺寸"的观感，
##   不是贴图自己的指标（见 [[art-import-verify-at-display-scale]]）。
## 用法：godot --path . --resolution 1000x1000 res://tools/shot_shadow_fx.tscn -- --no-save

const GROUND := "res://assets/scenes/zhaoying_lamp_arena_ground.png"
## 与 ArtDB.bg_zhaoying_lamp_arena 同口径：战场 1200px 见方铺 6 块 tile
const ARENA_TARGET_LENGTH := 1200.0
const ARENA_MAP_TILES := 6

const MODES := [
	["skill_shadow_cut", {"range": 178.0, "angle": 100.0, "hit_shape": MoveDB.SHAPE_FAN}],
	["skill_shadow_reach", {"range": 300.0, "width": 30.0, "hit_shape": MoveDB.SHAPE_LINE}],
	["skill_shadow_bind", {"range": 120.0, "hit_shape": MoveDB.SHAPE_CIRCLE}],
	["skill_shadow_step", {"range": 260.0, "width": 26.0, "hit_shape": MoveDB.SHAPE_LINE}],
	["skill_shadow_dim", {"range": 150.0, "hit_shape": MoveDB.SHAPE_SELF}],
	["skill_shadow_beam", {"range": 320.0, "width": 62.0, "hit_shape": MoveDB.SHAPE_LINE}],
	["skill_shadow_split", {"range": 220.0, "hit_shape": MoveDB.SHAPE_SELF}],
	["skill_shadow_longnight", {"range": 240.0, "hit_shape": MoveDB.SHAPE_CIRCLE}],
]

var _host: Node2D


func _ready() -> void:
	var vs := get_viewport().get_visible_rect().size
	position = vs * 0.5
	# 地面：按实机的每块 tile 尺寸铺 6×6，特效才有"落在地上"的可比性
	# （战场真身是 2×2 镜像块，这里不镜像 —— 判柔边与亮度对比不受影响）
	var tile_side := ARENA_TARGET_LENGTH / ARENA_MAP_TILES
	var gt: Texture2D = load(GROUND)
	var ts := tile_side / float(gt.get_width())
	for ty in ARENA_MAP_TILES:
		for tx in ARENA_MAP_TILES:
			var g := Sprite2D.new()
			g.texture = gt
			g.scale = Vector2.ONE * ts
			g.position = Vector2(
					(tx - (ARENA_MAP_TILES - 1) * 0.5) * tile_side,
					(ty - (ARENA_MAP_TILES - 1) * 0.5) * tile_side)
			# ⚠ 必须与实机同一层叠：combat_arena 的地面在 z=-10，而影族的墨带是 z=-1。
			#   这里留 0 的话墨层整个钻到地面底下，拍出来"特效只剩一根亮线"，
			#   会把 harness 的问题当成游戏的美术问题（第一版就栽在这）。
			g.z_index = -10
			add_child(g)
	_host = Node2D.new()
	add_child(_host)

	_measure_profile()
	for raw in MODES:
		var row: Array = raw
		SkillFx.play_at_strike(_host, String(row[0]), row[1], Vector2.RIGHT)
		# 峰值那一拍就抓：影族的瞬时层 lifetime 只有 0.4 秒左右，
		# 等 0.10 秒再抓会抓到衰减尾巴，看着像"没画出来"
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		await _grab(String(row[0]).replace("skill_shadow_", "shadow_fx_") + ".png")
		await get_tree().create_timer(0.70, true, false, true).timeout
	print("SHOT_SHADOW done")
	get_tree().quit(0)


## 柔边度量：直接读 streak_texture 的纵向 alpha 剖面，算 10%→90% 的过渡宽度。
## 纯白图（原来的 _stretch_bar）这个值是 0 —— 一条垂直一刀就是"硬边色块"。
func _measure_profile() -> void:
	var tex: Texture2D = SkillFx.lightbar_texture()
	var img: Image = tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var mid := (img.get_height() - 1) / 2
	var col: Array = []
	for y in img.get_height():
		col.append(img.get_pixel(img.get_width() / 2, y).a)
	var peak := 0.0
	for v in col:
		peak = maxf(peak, float(v))
	var lo_i := -1
	var hi_i := -1
	for y in img.get_height():
		var v := float(col[y])
		if lo_i < 0 and v >= peak * 0.10:
			lo_i = y
		if v >= peak * 0.90:
			hi_i = y
	var feather_px := float(absi(hi_i - lo_i))
	# 显示尺寸换算：tile 1024px 在实机铺成 200px → 0.195 倍
	var disp := tile_side_display()
	print("METRIC 贴图纵向 10→90 过渡 = %.1f px（原生）≈ %.2f px（实机显示）"
			% [feather_px, feather_px * disp])
	print("METRIC 原 _stretch_bar 用 4×4 纯白：过渡 = 0.0 px（硬边）")
	# 芯宽与全宽之比：决定"看得见的芯"和"外面的晕"各占多少
	var core := 0.0
	for v in col:
		if float(v) >= peak * 0.50:
			core += 1.0
	print("METRIC 芯(FWHM)占全高 = %.1f%%  峰值 alpha = %.2f  → _soft_bar 按 thickness=芯宽 折算"
			% [core / float(img.get_height()) * 100.0, peak])


func tile_side_display() -> float:
	return ARENA_TARGET_LENGTH / ARENA_MAP_TILES / 1024.0


func _grab(fname: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var crop := Image.create(720, 420, false, Image.FORMAT_RGBA8)
	var ox := int(position.x) - 360
	var oy := int(position.y) - 210
	for y in 420:
		for x in 720:
			var sx := ox + x
			var sy := oy + y
			if sx < img.get_width() and sy < img.get_height():
				crop.set_pixel(x, y, img.get_pixel(sx, sy))
	var err := crop.save_png("output/" + fname)
	# 量一下"叠在地面上的最大亮度差"：为 0 就是这一拍根本没画出来
	var base := 0.0
	var peakd := 0.0
	for y in range(0, 420, 3):
		for x in range(0, 720, 3):
			var c := crop.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			base += lum
			peakd = maxf(peakd, absf(lum - 0.30))
	var n := (420 / 3) * (720 / 3)
	print("SHOT output/", fname, " err=", err, " 地面均亮=%.3f 最亮偏离=%.3f" % [base / n, peakd])
