extends Node
## 诊断：幽冥灵墟两条接缝的节点矩形、纹理与屏幕映射（一次性排查脚本）。

func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	var world := s.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var p := world.get_node("Player") as Node2D
	var cam := p.get_node("Camera2D") as Camera2D
	for spec in [Vector2(-3000.0, 0.0), Vector2(0.0, 2000.0)]:
		p.global_position = spec
		cam.global_position = spec
		cam.reset_smoothing()
		await get_tree().process_frame
		await get_tree().process_frame
		print("=== target ", spec, " player=", p.global_position,
			" cam=", cam.global_position, " zoom=", cam.zoom,
			" center=", cam.get_screen_center_position())

	var ground := world.get_node("Ground") as Node2D
	for c in ground.get_children():
		var nm := String(c.name)
		var z := 0
		if c is CanvasItem:
			z = (c as CanvasItem).z_index
		var extra := ""
		if c is ColorRect:
			extra = " pos=%s size=%s" % [(c as ColorRect).position, (c as ColorRect).size]
			var mat := (c as ColorRect).material as ShaderMaterial
			if mat != null:
				for key in ["band_tex", "mask_tex", "grass_tex"]:
					var tex: Variant = mat.get_shader_parameter(key)
					if tex is Texture2D:
						extra += " %s=%s" % [key, (tex as Texture2D).resource_path]
		if nm.begins_with("Seam") or nm.begins_with("Band") or nm.begins_with("Terrain"):
			print(nm, " z=", z, extra)
	get_tree().quit(0)
