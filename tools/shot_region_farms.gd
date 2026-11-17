extends Node
## 三区灵田实景截图：先把三区核心首领标为已杀，进大世界后逐块飞到本区田旁
## 用法：godot --path . tools/shot_region_farms.tscn -- --no-save

const SHOTS := [
	{"tag": "lianqi", "pos": Vector2(4980.0, 3217.0), "zoom": 0.85},
	{"tag": "zhuji", "pos": Vector2(4850.0, -2997.0), "zoom": 0.85},
	{"tag": "jiedan", "pos": Vector2(-4850.0, -2997.0), "zoom": 0.85},
]

var _w: Node
var _idx := 0


func _ready() -> void:
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT REGION FARMS TIMEOUT")
		get_tree().quit(2))
	CharacterData.secret_world["core_kills"] = {
		SecretWorldDB.REGION_LIANQI: true,
		SecretWorldDB.REGION_ZHUJI: true,
		SecretWorldDB.REGION_JIEDAN: true,
	}
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_LIANQI
	_w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(_w)
	await get_tree().create_timer(1.0, true, false, true).timeout
	_w.player.set_physics_process(false)
	var cam := _w.player.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.reset_smoothing()
	await get_tree().create_timer(0.4, true, false, true).timeout
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
		img.save_png("output/region_farm_%s.png" % String(s["tag"]))
		print("SHOT output/region_farm_%s.png" % String(s["tag"]), " ",
			img.get_width(), "x", img.get_height())
		_idx += 1
	get_tree().quit()
