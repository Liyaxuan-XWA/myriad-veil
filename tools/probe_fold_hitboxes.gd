extends Node
## 叠纸受击球 / 碰撞体贴合度量测（2026-11-02）
##
## 场景里那 5 颗球是我**照着画布尺寸推的，没量过剪影**。
## rig 画布中心 ≠ BOSS 原点，换一张图或改一次 scale，球就整批偏掉 ——
## 赤霄界三只是靠实机剪影重拟过才有 93.9% 覆盖率的，这只必须走同一道流程。
##
## 做法：把 rig 的 body / rule 件按各自全局变换映回 BOSS 局部坐标，
## 逐像素取不透明点，再和「所有受击球的并集」比：
##   coverage = 剪影被球盖住的比例（低了 = 有的地方打不到）
##   stray    = 球盖到空地面的比例（高了 = 空气墙能打，玩家觉得明明躲开了还掉血）
## 用法：godot --headless --path . res://tools/probe_fold_hitboxes.tscn -- --no-save

const BOSS_SCENE := "res://scenes/boss/domain_boss_04_c.tscn"
const STEP := 4          ## 纹理空间采样步长（像素）


func _ready() -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 1
	await get_tree().process_frame
	var boss: Node2D = (load(BOSS_SCENE) as PackedScene).instantiate()
	add_child(boss)
	for i in range(8):
		await get_tree().process_frame

	var root: Node = boss.get_node_or_null("Visual")
	if root == null:
		print("FAIL 没有 Visual 节点")
		get_tree().quit(1)
		return

	# 1) 把每件不透明像素映回 BOSS 局部坐标
	var pts := PackedVector2Array()
	var xmin := 1.0e9
	var xmax := -1.0e9
	var ymin := 1.0e9
	var ymax := -1.0e9
	for n in root.find_children("*", "Sprite2D", true, false):
		var spr := n as Sprite2D
		if spr == null or spr.texture == null or not spr.visible:
			continue
		var tex := spr.texture.get_image()
		if tex == null:
			continue
		var w := tex.get_width()
		var h := tex.get_height()
		var x := 0
		while x < w:
			var y := 0
			while y < h:
				if tex.get_pixel(x, y).a > 0.25:
					# to_global 才是「件内坐标 → 世界」；写成 to_local 会把祖先变换反着乘一遍
					var lp := boss.to_local(spr.to_global(Vector2(x - w * 0.5, y - h * 0.5)))
					pts.append(lp)
					xmin = minf(xmin, lp.x)
					xmax = maxf(xmax, lp.x)
					ymin = minf(ymin, lp.y)
					ymax = maxf(ymax, lp.y)
				y += STEP
			x += STEP
	if pts.is_empty():
		print("FAIL 剪影是空的（贴图没导入？）")
		get_tree().quit(1)
		return
	print("剪影采样点 %d  · 局部包围盒 x %.1f..%.1f  y %.1f..%.1f  (%.0f x %.0f)" % [
		pts.size(), xmin, xmax, ymin, ymax, xmax - xmin, ymax - ymin])
	print("head_top_y %.1f  feet_offset %.1f  血条锚定 %.1f" % [
		float(boss.call("head_top_y")), float(boss.call("feet_offset")),
		float(boss.call("head_top_y")) - 14.0])

	# 2) 与受击球并集比对
	var spheres: Array = boss.call("hit_spheres")
	var covered := 0
	for p in pts:
		for s in spheres:
			if p.distance_to(Vector2(s.x, s.y)) <= float(s.z):
				covered += 1
				break
	var coverage := 100.0 * float(covered) / float(pts.size())

	# 球盖到空地面的比例：在球的联合包围盒上按同样步长撒点
	var sxmin := 1.0e9
	var sxmax := -1.0e9
	var symin := 1.0e9
	var symax := -1.0e9
	for s in spheres:
		sxmin = minf(sxmin, float(s.x) - float(s.z))
		sxmax = maxf(sxmax, float(s.x) + float(s.z))
		symin = minf(symin, float(s.y) - float(s.z))
		symax = maxf(symax, float(s.y) + float(s.z))
	# 剪影点做成网格哈希，否则「每个球内点 × 全部剪影点」会跑到十万级循环
	var cell := 8.0
	var grid: Dictionary = {}
	## ⚠ 每个球内点只能记一次：早先 3x3 扫描没有整体早退，
	##   一个点会在多个桶里各加一次，外溢率算成负数（等于这条判据在说谎）
	for q in pts:
		var key := "%d:%d" % [int(floor(q.x / cell)), int(floor(q.y / cell))]
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(q)
	var in_sphere := 0
	var in_sil := 0
	var y := symin
	while y <= symax:
		var x := sxmin
		while x <= sxmax:
			var p := Vector2(x, y)
			var hit_s := false
			for s in spheres:
				if p.distance_to(Vector2(s.x, s.y)) <= float(s.z):
					hit_s = true
					break
			if hit_s:
				in_sphere += 1
				if _near_silhouette(p, grid, cell):
					in_sil += 1
			x += 6.0
		y += 6.0
	var stray := 100.0 * float(in_sphere - in_sil) / maxf(float(in_sphere), 1.0)

	print("受击球 %d 颗  剪影覆盖 %.1f%%  球外溢 %.1f%%" % [spheres.size(), coverage, stray])
	for s in spheres:
		print("  sphere x %6.1f y %6.1f r %5.1f  -> 纵向 %.1f..%.1f" % [
			s.x, s.y, s.z, float(s.y) - float(s.z), float(s.y) + float(s.z)])
	print("── 逐横带（局部 y：左右边界 / 宽度 / 中心 x）──")
	var bands := {}
	for q in pts:
		var key := int(floor(q.y / 20.0))
		if not bands.has(key):
			bands[key] = [1.0e9, -1.0e9]
		(bands[key] as Array)[0] = minf((bands[key] as Array)[0], q.x)
		(bands[key] as Array)[1] = maxf((bands[key] as Array)[1], q.x)
	var keys := bands.keys()
	keys.sort()
	for k in keys:
		var r: Array = bands[k]
		var yc := float(k) * 20.0 + 10.0
		print("  y %6.1f  x %6.1f .. %6.1f   宽 %5.1f  中心 %6.1f" % [
			yc, r[0], r[1], r[1] - r[0], (r[0] + r[1]) * 0.5])
	print("  剪影纵向 %.1f .. %.1f" % [ymin, ymax])
	var ok := coverage >= 90.0 and stray <= 22.0
	print("%s  判据：覆盖 >= 90%% 且 外溢 <= 22%%" % ["PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


## 网格哈希里查「附近有没有剪影像素」（3x3 桶，命中即返回，不重复计数）
func _near_silhouette(p: Vector2, grid: Dictionary, cell: float) -> bool:
	var cx := int(floor(p.x / cell))
	var cy := int(floor(p.y / cell))
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var bucket = grid.get("%d:%d" % [cx + ox, cy + oy])
			if bucket == null:
				continue
			for q in (bucket as Array):
				if (q as Vector2).distance_squared_to(p) <= 64.0:
					return true
	return false
