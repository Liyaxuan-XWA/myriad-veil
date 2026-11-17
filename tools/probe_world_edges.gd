extends Node2D
## 大陆边界/接缝自检（2026-11-01）：
##   1) 外缘带全部用 _v2 贴图，z=2；接缝地垫 z=3 压在外缘带之上
##   2) 四条接缝都有地垫，且贴图已加载
##   3) 旧的硬边 ColorRect 阴影斑已清掉（Ground 下不得再有 >80×80 的纯色矩形）
## 用法：godot --headless --path . tools/probe_world_edges.tscn

var _fails: Array = []
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	var world := s.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var ground := world.get_node("Ground") as Node2D
	var band_count := 0
	var seam_count := 0
	var shadow_count := 0
	for c in ground.get_children():
		var nm := String(c.name)
		var z := (c as CanvasItem).z_index if c is CanvasItem else 0
		if nm.begins_with("Band_"):
			band_count += 1
			var mat := (c as ColorRect).material as ShaderMaterial
			var tex: Variant = mat.get_shader_parameter("band_tex") if mat != null else null
			_check(tex is Texture2D, nm + " 有贴图")
			if tex is Texture2D:
				var path := (tex as Texture2D).resource_path
				_check(path.ends_with("_v2.png"), nm + " 用新版贴图", path)
			_check(z == 2, nm + " z=2", str(z))
		elif nm.begins_with("Seam"):
			seam_count += 1
			var mat := (c as ColorRect).material as ShaderMaterial
			var tex: Variant = mat.get_shader_parameter("band_tex") if mat != null else null
			_check(tex is Texture2D, nm + " 有贴图")
			if tex is Texture2D:
				var path := (tex as Texture2D).resource_path
				_check(path.ends_with("_v2.png"), nm + " 用新版贴图", path)
			_check(z == 3, nm + " z=3", str(z))
		elif c is Sprite2D:
			var tex := (c as Sprite2D).texture
			if tex is GradientTexture2D:
				shadow_count += 1
		elif c is ColorRect:
			var r := c as ColorRect
			_check(r.size.x <= 80.0 or r.size.y <= 80.0,
				"Ground 下无大块硬边矩形", "%s %s" % [nm, r.size])

	_check(band_count == 8, "八条外缘带", str(band_count))
	_check(seam_count == 4, "四条接缝地垫", str(seam_count))
	_check(shadow_count >= 200, "柔边阴影斑已铺开", str(shadow_count))

	print("\nRESULT ", _passes, "/", _passes + _fails.size(), "  fails=", _fails.size())
	if not _fails.is_empty():
		for f in _fails:
			print("  - ", f)
		get_tree().quit(1)
	else:
		get_tree().quit(0)
