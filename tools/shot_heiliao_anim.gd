extends Node
## 赫连霄 rig / 招式截图（2026-10-29）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_heiliao_anim.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.09)
	bg.size = Vector2(1280, 720)
	bg.z_index = -20
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.20, 0.15, 0.15)
	ground.z_index = -10
	ground.position = Vector2(0, 470)
	ground.size = Vector2(1280, 250)
	add_child(ground)
	var feet := ColorRect.new()
	feet.color = Color(0.82, 0.68, 0.36)
	feet.z_index = -9
	feet.position = Vector2(0, 469)
	feet.size = Vector2(1280, 1)
	add_child(feet)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_03.tscn") as PackedScene).instantiate()
	boss.position = Vector2(640, 470)
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
	await _shot("heiliao_anim_idle.png")

	boss._play_form_anim("form_thunder_verdict", 1.0)
	await get_tree().create_timer(0.45, true, false, true).timeout
	await _shot("heiliao_anim_verdict_windup.png")
	await get_tree().create_timer(0.55, true, false, true).timeout
	await _shot("heiliao_anim_verdict_strike.png")

	boss._play_form_anim("form_thunder_drum", 0.75)
	await get_tree().create_timer(0.42, true, false, true).timeout
	await _shot("heiliao_anim_drum.png")

	boss._play_form_anim("form_thunder_nine", 1.35)
	await get_tree().create_timer(0.9, true, false, true).timeout
	await _shot("heiliao_anim_nine.png")

	# 技能特效：定刑 / 九霄 / 雷牢 各一张（落在 boss 脚下前方）
	var fx_form := {"range": 90.0, "hit_shape": MoveDB.SHAPE_CIRCLE}
	SkillFx.play_at_strike(boss, "skill_thunder_execute", fx_form, Vector2.RIGHT,
		Vector2(780, 470))
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _shot("heiliao_fx_execute.png")
	await get_tree().create_timer(0.5, true, false, true).timeout

	var nine_form := {"range": 100.0, "hit_shape": MoveDB.SHAPE_CIRCLE}
	SkillFx.play_at_strike(boss, "skill_thunder_nine", nine_form, Vector2.RIGHT,
		Vector2(780, 470))
	await get_tree().create_timer(0.15, true, false, true).timeout
	await _shot("heiliao_fx_nine.png")
	await get_tree().create_timer(0.6, true, false, true).timeout

	var prison_form := {"range": 170.0, "prison_radius": 170.0, "closing_time": 1.2,
		"hit_shape": MoveDB.SHAPE_CIRCLE}
	SkillFx.play_at_strike(boss, "skill_thunder_prison", prison_form, Vector2.RIGHT,
		Vector2(780, 470))
	await get_tree().create_timer(0.35, true, false, true).timeout
	await _shot("heiliao_fx_prison.png")
	await get_tree().create_timer(0.95, true, false, true).timeout
	await _shot("heiliao_fx_prison_close.png")
	get_tree().quit()
