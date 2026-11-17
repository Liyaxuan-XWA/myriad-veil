extends Node2D
## 临时排查：列出 Ground 下所有 plate（名字 / 世界矩形 / z / 贴图或 shader 参数）。
## 用法：godot --headless --path . tools/inspect_ground_plates.tscn

func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	var world := s.instantiate()
	add_child(world)
	for i in range(8):
		await get_tree().process_frame
	var ground := world.get_node("Ground") as Node2D
	print("ground children=", ground.get_child_count())
	for c in ground.get_children():
		if not (c is ColorRect):
			continue
		var r := c as ColorRect
		var mat := r.material as ShaderMaterial
		var tex := ""
		if mat != null:
			for key in ["band_tex", "mask_tex"]:
				var v: Variant = mat.get_shader_parameter(key)
				if v is Texture2D:
					tex += key + "=" + (v as Texture2D).resource_path + " "
		print("%-34s z=%d rect=(%s,%s) %sx%s  %s" % [
			String(r.name), r.z_index, int(r.position.x), int(r.position.y),
			int(r.size.x), int(r.size.y), tex])
	get_tree().quit(0)
