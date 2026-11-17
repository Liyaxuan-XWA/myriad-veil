extends Node

func _ready() -> void:
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().create_timer(1.0, true, false, true).timeout
	var center := Vector2(3000.0, -2000.0)
	var cam := Camera2D.new()
	cam.global_position = center + Vector2(0.0, 40.0)
	add_child(cam)
	cam.make_current()
	w.player.global_position = center + Vector2(0.0, 230.0)
	await get_tree().create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/zhuji_core.png")
	print("SHOT output/zhuji_core.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
