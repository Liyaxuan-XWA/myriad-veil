extends Node
## 定阵先生攻击动作截图（2026-10-28）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_dingzhen_anim.tscn
## 输出：output/dingzhen_anim_idle.png / _windup.png / _strike.png

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.24, 0.25, 0.22)
	ground.position = Vector2(0, 430)
	ground.size = Vector2(1280, 290)
	add_child(ground)
	var feet := ColorRect.new()
	feet.color = Color(0.90, 0.78, 0.42)
	feet.position = Vector2(0, 429)
	feet.size = Vector2(1280, 1)
	add_child(feet)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_02_b.tscn") as PackedScene).instantiate()
	boss.position = Vector2(640, 430)
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _shot("dingzhen_anim_idle.png")

	boss._play_form_anim("form_array_burst", 1.35)
	await get_tree().create_timer(0.55, true, false, true).timeout
	await _shot("dingzhen_anim_windup.png")
	await get_tree().create_timer(0.47, true, false, true).timeout
	await _shot("dingzhen_anim_strike.png")
	get_tree().quit()
