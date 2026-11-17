extends Node2D

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.13, 0.11, 1.0)
	bg.size = Vector2(1280, 720)
	layer.add_child(bg)
	var cam := Camera2D.new()
	cam.position = Vector2(0, -62)
	cam.zoom = Vector2(2.0, 2.0)
	add_child(cam)
	cam.make_current()
	var boss = (load("res://scenes/world/world_enemy.tscn") as PackedScene).instantiate()
	var cfg: Dictionary = SecretWorldDB.CORE_BOSS.duplicate(true)
	cfg["pos"] = Vector2.ZERO
	boss.configure(cfg, WorldEnemy.KIND_CORE, "青岚古猿")
	boss.position = Vector2.ZERO
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	await get_tree().create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/ape_rig_idle.png")
	boss.skin.play_one_shot("slam", 1.0)
	await get_tree().create_timer(0.40, true, false, true).timeout
	await get_tree().create_timer(0.44, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/ape_rig_slam.png")
	print("SHOT ape rig")
	get_tree().quit(0)
