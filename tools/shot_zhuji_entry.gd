extends Node

func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_ZHUJI
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().create_timer(0.8, true, false, true).timeout
	print("player=", w.player.global_position, " portal=", w._portal.global_position if w._portal != null else "none",
		" current=", w._current_region_id, " cam_limits=",
		w.player.get_node("Camera2D").limit_left, ",", w.player.get_node("Camera2D").limit_top, " .. ",
		w.player.get_node("Camera2D").limit_right, ",", w.player.get_node("Camera2D").limit_bottom)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/zhuji_entry.png")
	print("SHOT output/zhuji_entry.png")
	get_tree().quit()
