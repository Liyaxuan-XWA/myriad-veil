extends Node
## 赤金火麟实景截图（2026-10-29）：霞心本体 / 火雨 / 日蚀落点 / 二阶段日轮
## 用法：godot --path . res://tools/shot_jiedan_boss.tscn （不能加 --headless）

var _w: Node
var _boss: Node2D
var _cam: Camera2D


func _ready() -> void:
	get_tree().create_timer(50.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT JIEDAN BOSS TIMEOUT")
		get_tree().quit(2))
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_JIEDAN
	_w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(_w)
	await get_tree().create_timer(1.0, true, false, true).timeout
	var enemies: Dictionary = _w.get("_enemies")
	_boss = enemies.get("jiedan_core_boss", null)
	if _boss == null:
		print("SHOT no boss")
		get_tree().quit(1)
		return
	_boss.set_physics_process(false)
	var player: Node2D = _w.player
	player.set_physics_process(false)
	_cam = player.get_node_or_null("Camera2D") as Camera2D
	_boss.target = player

	player.global_position = _boss.global_position + Vector2(310.0, 150.0)
	if _cam != null:
		_cam.zoom = Vector2(0.8, 0.8)
		_cam.reset_smoothing()
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _shoot("output/qilin_world_idle.png")

	var rain_def := _find_skill("qilin_rain")
	_boss.set("_next_core_skill", rain_def)
	_boss.skin.play_one_shot("rain", 1.4)
	_boss.call("_cast_core_skill")
	await get_tree().create_timer(0.72, true, false, true).timeout
	await _shoot("output/qilin_world_rain.png")

	var eclipse_def := _find_skill("qilin_eclipse")
	_boss.phase = 2
	_boss.set("_next_core_skill", eclipse_def)
	_boss.skin.play_one_shot("eclipse", 1.8)
	_boss.call("_cast_core_skill")
	await get_tree().create_timer(0.36, true, false, true).timeout
	await _shoot("output/qilin_world_eclipse.png")

	# 日轮当空 + 玩家身上两层霞印
	_boss.call("_on_phase_two")
	player.global_position = _boss.global_position + Vector2(360.0, 140.0)
	# 前一招的延迟命中还挂着 pending，会再叠一层直接炸掉；这里直接摆两层
	_boss.set("_mark_once_pending", 0)
	_boss.set("_mark_stacks", 2)
	_boss.set("_mark_left", 10.0)
	# 等日蚀特效散尽，只留日轮 + 霞印图形；BOSS 物理被关掉，绕身日轮要手动推
	var until := Time.get_ticks_msec() + 2200
	while Time.get_ticks_msec() < until:
		_boss.call("_update_motes")
		await get_tree().process_frame
	var motes: Array = _boss.get("_motes")
	var lit := 0
	for m in motes:
		if m.visible and m.scale.x > 0.09:
			lit += 1
	print("DBG stacks=", _boss.get("_mark_stacks"), " lit motes=", lit)
	await _shoot("output/qilin_world_phase2.png")
	print("SHOT jiedan boss done")
	get_tree().quit(0)


func _find_skill(id: String) -> Dictionary:
	for raw in SecretWorldDB.CORE_BOSS_JIEDAN.get("core_skills", []):
		var def: Dictionary = raw
		if String(def.get("id", "")) == id:
			return def
	return {}


func _shoot(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)