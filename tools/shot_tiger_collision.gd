extends Node
## 虎妖碰撞体截图（2026-10-28）
## 用法：godot --path . res://tools/shot_tiger_collision.tscn
## 输出：output/tiger_collision_fix.png（启用碰撞调试绘制，脚底线为 y=400）

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.13)
	bg.size = Vector2(1280, 720)
	add_child(bg)

	var ground := ColorRect.new()
	ground.color = Color(0.22, 0.30, 0.18)
	ground.position = Vector2(0, 400)
	ground.size = Vector2(1280, 320)
	add_child(ground)
	var feet := ColorRect.new()
	feet.color = Color(0.95, 0.85, 0.35)
	feet.position = Vector2(0, 399)
	feet.size = Vector2(1280, 1)
	add_child(feet)

	get_tree().debug_collisions_hint = true
	var boss: Node2D = (load("res://scenes/boss/boss.tscn") as PackedScene).instantiate()
	boss.position = Vector2(640, 400)
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	await get_tree().create_timer(0.4, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/tiger_collision_fix.png")
	print("SHOT output/tiger_collision_fix.png  ", img.get_width(), "x", img.get_height())
	get_tree().quit()
