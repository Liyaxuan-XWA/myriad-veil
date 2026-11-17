extends Node

func _ready() -> void:
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().create_timer(0.8, true, false, true).timeout
	var p = w.player
	p.global_position = Vector2(5110.0, 3270.0)
	var cam := Camera2D.new()
	cam.global_position = p.global_position
	cam.zoom = Vector2(1.0, 1.0)
	add_child(cam)
	cam.make_current()
	await get_tree().create_timer(0.6, true, false, true).timeout
	# 实机里能放阵旗技能，说明已学会至少一门；截图工具也要先解锁，否则 _array_precast 会清旗
	if not CharacterData.learned_skills.has("skill_array_plant"):
		CharacterData.learned_skills.append("skill_array_plant")
	p._refresh_array_unlock()
	p._clear_array_flags()
	var f = p._plant_array_flag(p.global_position, ArrayFlag.Kind.ATTACK)
	print("FLAG ", f.global_position, " visible=", f.is_visible_in_tree(),
		" alpha=", f.modulate.a, " tex=", f._spr.texture.resource_path)
	await get_tree().create_timer(0.4, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/world_array_flag.png")
	# 再补三面旗：2 困 + 1 守 → 封阵多数色为困，起手应报「困牢 · 无伤」
	p._plant_array_flag(p.global_position + Vector2(-46.0, -18.0), ArrayFlag.Kind.BIND)
	p._plant_array_flag(p.global_position + Vector2(46.0, -18.0), ArrayFlag.Kind.BIND)
	p._plant_array_flag(p.global_position + Vector2(0.0, 34.0), ArrayFlag.Kind.GUARD)
	p._array_precast("skill_array_seal", Vector2.RIGHT)
	await get_tree().create_timer(0.15, true, false, true).timeout
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png("output/world_seal_label.png")
	print("SHOT world flag + seal label")
	get_tree().quit()
