extends Node
## 离照 rig / 招式 / 日轮特效截图（2026-10-29）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_lizhao_anim.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.045, 0.04)
	bg.size = Vector2(1280, 720)
	bg.z_index = -20
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.20, 0.13, 0.10)
	ground.z_index = -10
	ground.position = Vector2(0, 470)
	ground.size = Vector2(1280, 250)
	add_child(ground)
	var feet := ColorRect.new()
	feet.color = Color(0.92, 0.70, 0.34)
	feet.z_index = -9
	feet.position = Vector2(0, 469)
	feet.size = Vector2(1280, 1)
	add_child(feet)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_03_b.tscn") as PackedScene).instantiate()
	boss.position = Vector2(700, 470)
	add_child(boss)
	var cam := Camera2D.new()
	cam.position = Vector2(640, 380)
	cam.zoom = Vector2(1.9, 1.9)
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _shot("lizhao_anim_idle.png")

	# 火种世界层
	var seed := SunSeed.new()
	add_child(seed)
	seed.global_position = Vector2(520, 430)
	seed.set_claim_lock(9.0)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("lizhao_anim_seed.png")

	boss._play_form_anim("form_sun_slash", 0.8)
	await get_tree().create_timer(0.35, true, false, true).timeout
	await _shot("lizhao_anim_slash_windup.png")
	boss._play_form_anim("form_sun_meteor", 1.25)
	await get_tree().create_timer(0.55, true, false, true).timeout
	await _shot("lizhao_anim_meteor_windup.png")

	# 八式命中层
	var slash_form := {"range": 190.0, "angle": 110.0, "hit_shape": MoveDB.SHAPE_FAN}
	SkillFx.play_at_strike(boss, "skill_sun_slash", slash_form, Vector2.RIGHT,
		Vector2(860, 430))
	await get_tree().create_timer(0.10, true, false, true).timeout
	await _shot("lizhao_fx_slash.png")
	await get_tree().create_timer(0.45, true, false, true).timeout

	var throw_form := {"range": 100.0, "hit_shape": MoveDB.SHAPE_CIRCLE}
	SkillFx.play_at_strike(boss, "skill_sun_throw", throw_form, Vector2.RIGHT,
		Vector2(860, 430))
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _shot("lizhao_fx_throw.png")
	await get_tree().create_timer(0.5, true, false, true).timeout

	var eclipse_form := {"range": 140.0, "hit_shape": MoveDB.SHAPE_CIRCLE}
	SkillFx.sun_warn_at(get_parent(), Vector2(860, 430), 140.0, 0.55)
	SkillFx.play_at_strike(boss, "skill_sun_eclipse", eclipse_form, Vector2.RIGHT,
		Vector2(860, 430))
	await get_tree().create_timer(0.30, true, false, true).timeout
	await _shot("lizhao_fx_eclipse.png")
	await get_tree().create_timer(0.5, true, false, true).timeout

	var wheel_form := {"range": 130.0, "hit_shape": MoveDB.SHAPE_CIRCLE}
	SkillFx.play_at_strike(boss, "skill_sun_wheel", wheel_form, Vector2.RIGHT,
		Vector2(760, 440))
	await get_tree().create_timer(0.20, true, false, true).timeout
	await _shot("lizhao_fx_wheel.png")
	await get_tree().create_timer(0.4, true, false, true).timeout

	var meteor_form := {"range": 180.0, "hit_shape": MoveDB.SHAPE_CIRCLE}
	SkillFx.sun_warn_at(get_parent(), Vector2(860, 430), 180.0, 0.55)
	SkillFx.play_at_strike(boss, "skill_sun_meteor", meteor_form, Vector2.RIGHT,
		Vector2(860, 430))
	await get_tree().create_timer(0.30, true, false, true).timeout
	await _shot("lizhao_fx_meteor.png")
	await get_tree().create_timer(0.8, true, false, true).timeout
	get_tree().quit()
