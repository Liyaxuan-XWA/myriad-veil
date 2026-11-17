extends Node
## 观澜 rig / 八式 / 镜身特效截图（2026-11-01）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_guanying_rig.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.055, 0.085)
	bg.size = Vector2(1280, 720)
	bg.z_index = -20
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.12, 0.16, 0.20)
	ground.z_index = -10
	ground.position = Vector2(0, 470)
	ground.size = Vector2(1280, 250)
	add_child(ground)
	var feet := ColorRect.new()
	feet.color = Color(0.58, 0.82, 0.96)
	feet.z_index = -9
	feet.position = Vector2(0, 469)
	feet.size = Vector2(1280, 1)
	add_child(feet)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_04.tscn") as PackedScene).instantiate()
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
	await _shot("guanying_rig_idle.png")

	var shots := [
		["form_mirror_slash", 1.0, 0.72, "guanying_rig_slash"],
		["form_mirror_thrust", 0.9, 0.62, "guanying_rig_thrust"],
		["form_mirror_bloom", 0.8, 0.48, "guanying_rig_bloom"],
		["form_mirror_shatter", 0.9, 0.54, "guanying_rig_shatter"],
		["form_mirror_return", 0.7, 0.34, "guanying_rig_return"],
		["form_mirror_ring", 0.9, 0.54, "guanying_rig_ring"],
		["form_mirror_myriad", 1.4, 1.0, "guanying_rig_myriad"],
	]
	for raw in shots:
		var row: Array = raw
		boss.call("_play_form_anim", String(row[0]), float(row[1]))
		await get_tree().create_timer(float(row[2]), true, false, true).timeout
		await _shot(String(row[3]) + ".png")
		await get_tree().create_timer(0.35, true, false, true).timeout

	# 镜身实体：召两具镜像 + 水镜环
	boss.call("_cast_bloom", MoveDB.resolve_boss("form_mirror_bloom"))
	await get_tree().create_timer(0.2, true, false, true).timeout
	boss.call("_cast_bloom", MoveDB.resolve_boss("form_mirror_bloom"))
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("guanying_images.png")
	boss.call("_cast_ring", MoveDB.resolve_boss("form_mirror_ring"))
	await get_tree().create_timer(0.15, true, false, true).timeout
	await _shot("guanying_ring.png")
	# 等水镜环完全散掉，否则它的蓝环会盖住后面每一张技能特效
	await get_tree().create_timer(3.4, true, false, true).timeout

	# 各招命中层
	var faces := [
		["skill_mirror_slash", {"range": 150.0, "angle": 110.0, "hit_shape": MoveDB.SHAPE_FAN}, "guanying_fx_slash"],
		["skill_mirror_thrust", {"range": 280.0, "hit_shape": MoveDB.SHAPE_LINE}, "guanying_fx_thrust"],
		["skill_mirror_shatter", {"range": 110.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, "guanying_fx_shatter"],
		["skill_mirror_return", {"hit_shape": MoveDB.SHAPE_SELF}, "guanying_fx_return"],
		["skill_mirror_ring", {"range": 150.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, "guanying_fx_ring"],
		["skill_mirror_myriad", {"range": 180.0, "angle": 130.0, "hit_shape": MoveDB.SHAPE_FAN}, "guanying_fx_myriad"],
	]
	for raw in faces:
		var row2: Array = raw
		SkillFx.play_at_strike(boss, String(row2[0]), row2[1], Vector2.RIGHT)
		await get_tree().create_timer(0.12, true, false, true).timeout
		await _shot(String(row2[2]) + ".png")
		await get_tree().create_timer(0.55, true, false, true).timeout
	get_tree().quit()
