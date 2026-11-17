extends Node
## 晏无咎 rig / 招式 / 三灾特效截图（2026-10-29）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_wujiu_anim.tscn


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.052, 0.070)
	bg.size = Vector2(1280, 720)
	bg.z_index = -20
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.16, 0.15, 0.18)
	ground.z_index = -10
	ground.position = Vector2(0, 470)
	ground.size = Vector2(1280, 250)
	add_child(ground)
	var feet := ColorRect.new()
	feet.color = Color(0.78, 0.76, 0.82)
	feet.z_index = -9
	feet.position = Vector2(0, 469)
	feet.size = Vector2(1280, 1)
	add_child(feet)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_03_c.tscn") as PackedScene).instantiate()
	boss.position = Vector2(700, 470)
	add_child(boss)
	var cam := Camera2D.new()
	cam.position = Vector2(640, 380)
	cam.zoom = Vector2(1.75, 1.75)
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _shot("wujiu_anim_idle.png")

	boss._play_form_anim("form_calamity_turn", 0.85)
	await get_tree().create_timer(0.38, true, false, true).timeout
	await _shot("wujiu_anim_turn.png")

	boss._play_form_anim("form_calamity_final", 1.35)
	await get_tree().create_timer(0.72, true, false, true).timeout
	await _shot("wujiu_anim_final.png")

	boss._play_form_anim("form_calamity_thunder_pool", 0.95)
	await get_tree().create_timer(0.40, true, false, true).timeout
	await _shot("wujiu_anim_pool.png")

	# 八式命中层（target 在右侧）
	var target := Vector2(880, 435)
	var cases := [
		["skill_calamity_step", {"range": 100.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, false],
		["skill_calamity_slash", {"range": 190.0, "angle": 100.0, "hit_shape": MoveDB.SHAPE_FAN}, false],
		["skill_calamity_fire_seal", {"range": 100.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, true],
		["skill_calamity_fire_field", {"range": 140.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, true],
		["skill_calamity_thunder_strike", {"range": 120.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, true],
		["skill_calamity_thunder_pool", {"range": 150.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, true],
		["skill_calamity_turn", {"range": 120.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, true],
		["skill_calamity_final", {"range": 200.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, true],
	]
	for c in cases:
		var sid: String = c[0]
		var form: Dictionary = c[1]
		var use_origin: bool = c[2]
		SkillFx.play_at_strike(boss, sid, form, Vector2.RIGHT,
			target if use_origin else null)
		await get_tree().create_timer(0.12 if sid != "skill_calamity_final" else 0.42,
			true, false, true).timeout
		await _shot("wujiu_fx_" + sid.replace("skill_calamity_", "") + ".png")
		await get_tree().create_timer(0.55, true, false, true).timeout
	get_tree().quit()
