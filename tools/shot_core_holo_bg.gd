extends Node
## 三只大陆核心首领的「空战场」背景板（华彩卡场景层用）：
## 进大世界 → 隐藏 HUD / 玩家 / 所有内容实体 → 镜头对准三个核心场地各拍一张
## 用法：godot --path . tools/shot_core_holo_bg.tscn -- --no-save

const SHOTS := [
	{"tag": "lianqi", "pos": Vector2(3000.0, 2000.0), "zoom": 0.72},
	{"tag": "zhuji", "pos": Vector2(3000.0, -2000.0), "zoom": 0.72},
	{"tag": "jiedan", "pos": Vector2(-3000.0, -2000.0), "zoom": 0.72},
]

var _w: Node
var _idx := 0


func _ready() -> void:
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT CORE HOLO BG TIMEOUT")
		get_tree().quit(2))
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_LIANQI
	_w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(_w)
	await get_tree().create_timer(1.0, true, false, true).timeout
	_w.player.set_physics_process(false)
	# 只留地形与场地道具：HUD、玩家、敌人 / 草药 / 传送门全藏起来
	_w.hud.visible = false
	_w.player.modulate = Color(1.0, 1.0, 1.0, 0.0)
	for c in _w.content.get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
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
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("output/core_holo_bg_%s.png" % String(s["tag"]))
		print("SHOT output/core_holo_bg_%s.png" % String(s["tag"]), " ",
			img.get_width(), "x", img.get_height())
		_idx += 1
	get_tree().quit()
