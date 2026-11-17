extends Node

func _ready() -> void:
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().create_timer(0.8, true, false, true).timeout
	var cam := Camera2D.new()
	cam.global_position = Vector2(3000.0, 0.0)
	cam.zoom = Vector2(1.0, 1.0)
	add_child(cam)
	cam.make_current()
	w.player.global_position = Vector2(3000.0, 120.0)
	await get_tree().create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/seam_south.png")
	w.player.global_position = Vector2(3000.0, -260.0)
	await get_tree().create_timer(0.5, true, false, true).timeout
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png("output/seam_north.png")
	print("SHOT seam")
	get_tree().quit()
