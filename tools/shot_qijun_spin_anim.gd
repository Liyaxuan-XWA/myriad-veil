extends Node
## 太虚气君回旋动作截图（2026-10-28）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_qijun_spin_anim.tscn
## 输出：output/qijun_spin_idle.png / _lean_a.png / _lean_b.png

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.12)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.20, 0.23, 0.24)
	ground.position = Vector2(0, 420)
	ground.size = Vector2(1280, 300)
	add_child(ground)
	var feet := ColorRect.new()
	feet.color = Color(0.70, 0.82, 0.90)
	feet.position = Vector2(0, 419)
	feet.size = Vector2(1280, 1)
	add_child(feet)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_02_c.tscn") as PackedScene).instantiate()
	boss.position = Vector2(640, 420)
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _shot("qijun_spin_idle.png")

	boss._play_form_anim("form_qi_spin", 0.75)
	await get_tree().create_timer(0.18, true, false, true).timeout
	await _shot("qijun_spin_lean_a.png")
	await get_tree().create_timer(0.16, true, false, true).timeout
	await _shot("qijun_spin_lean_b.png")
	get_tree().quit()
