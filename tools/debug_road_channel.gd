extends Node2D
## 临时排查：把 terrain shader 的 road_tex 换成洋红，看练气东缘那块褐色地是不是 road 通道。
## 用法：godot --path . tools/debug_road_channel.tscn

const TARGET := Vector2(5400.0, 1800.0)


func _ready() -> void:
	VirtualPad.enabled = false
	SettingsUI.set_entry_visible(false)
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_LIANQI
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	var world := s.instantiate()
	add_child(world)
	for i in range(30):
		await get_tree().process_frame

	var hud := world.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var p := world.get_node("Player") as Node2D
	p.set_physics_process(false)
	var cam := p.get_node("Camera2D") as Camera2D
	p.global_position = TARGET
	cam.global_position = TARGET
	cam.zoom = Vector2(1.2, 1.2)
	cam.reset_smoothing()

	var ground := world.get_node("Ground") as Node2D
	var magenta := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	magenta.fill(Color(1, 0, 1, 1))
	var mtex := ImageTexture.create_from_image(magenta)
	for c in ground.get_children():
		if c is ColorRect and (c as ColorRect).material is ShaderMaterial:
			var mat := (c as ColorRect).material as ShaderMaterial
			if mat.shader == null or not mat.shader.resource_path.ends_with("region_terrain.gdshader"):
				continue
			var mask: Texture2D = mat.get_shader_parameter("mask_tex")
			var img := mask.get_image() if mask != null else null
			print("plate=", c.name, " mask=", mask.resource_path if mask != null else "null")
			if img != null:
				# 世界(5100,1600) 落在 6000x4000 的练气矩形内 → UV
				var uv := Vector2(5100.0 / 6000.0, 1600.0 / 4000.0)
				var px := Vector2i(int(uv.x * img.get_width()), int(uv.y * img.get_height()))
				print("  mask@(5100,1600) ", px, " = ", img.get_pixelv(px))
				var uv2 := Vector2(0.85, 0.40)
				print("  mask@uv(.85,.40) = ", img.get_pixelv(Vector2i(int(uv2.x * img.get_width()), int(uv2.y * img.get_height()))))
			mat.set_shader_parameter("road_tex", mtex)

	for i in range(6):
		await get_tree().process_frame
	var path := "res://output/debug_road_magenta.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	get_tree().quit(0)
