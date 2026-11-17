extends Node
## 赤金丹霞实景截图（五处）：左上角传送门 / 东西接缝 / 霞心祭坛 / 南崖 / 西崖
## 用法：godot --path . tools/shot_jiedan_region.tscn

const SHOTS := [
	{"tag": "portal", "pos": Vector2(-5000.0, -3060.0), "zoom": 1.0},
	{"tag": "seam", "pos": Vector2(-260.0, -2000.0), "zoom": 1.15},
	{"tag": "heart", "pos": Vector2(-3000.0, -1700.0), "zoom": 0.58},
	{"tag": "south", "pos": Vector2(-3000.0, -750.0), "zoom": 1.0},
	{"tag": "west", "pos": Vector2(-5250.0, -2000.0), "zoom": 1.0},
]

var _w: Node
var _idx := 0


func _ready() -> void:
	get_tree().create_timer(50.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT JIEDAN REGION TIMEOUT")
		get_tree().quit(2))
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_JIEDAN
	_w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(_w)
	await get_tree().create_timer(0.8, true, false, true).timeout
	_w.player.set_physics_process(false)
	var cam := _w.player.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.reset_smoothing()
	# 首领卡不存在于大世界；这里只等 HUD 铺完
	await get_tree().create_timer(0.5, true, false, true).timeout
	while _idx < SHOTS.size():
		var s: Dictionary = SHOTS[_idx]
		_w.player.global_position = Vector2(s["pos"])
		if cam != null:
			cam.zoom = Vector2.ONE * float(s["zoom"])
			cam.reset_smoothing()
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("output/jiedan_%s.png" % String(s["tag"]))
		print("SHOT output/jiedan_%s.png" % String(s["tag"]), " ", img.get_width(), "x", img.get_height())
		_idx += 1
	get_tree().quit()
