extends Node
## 战场边缘视野探针：玩家贴墙时相机仍以玩家为中心，BOSS 在视野内，场外由边界雾收边。
## 用法：godot --path . --windowed --resolution 1280x720 tools/probe_arena_edge_camera.tscn -- --no-save

var _fails := 0
var _passes := 0
var _arena: Node
var _player: Node2D
var _boss: Node2D
var _cam: Camera2D


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails += 1
		print("FAIL  ", label, "  ", detail)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _screen_of(world_pos: Vector2) -> Vector2:
	return (world_pos - _cam.get_screen_center_position()) * _cam.zoom \
		+ get_viewport().get_visible_rect().size * 0.5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 战场边缘视野探针 ##########")
	get_tree().create_timer(40.0, true, false, true).timeout.connect(func() -> void:
		print("PROBE TIMEOUT")
		get_tree().quit(2))
	var boss_id := "boss_huyao"
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--boss="):
			boss_id = String(arg).trim_prefix("--boss=")
	GameState.battle_context = {
		"source": "tower",
		"boss_id": boss_id,
	}
	_arena = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(_arena)
	await get_tree().create_timer(0.8, true, false, true).timeout
	var card := _arena.find_child("BossIntroCard", true, false)
	if card != null:
		card.call("_dismiss")
	await get_tree().create_timer(1.8, true, false, true).timeout

	_player = _arena.get_node_or_null("Player") as Node2D
	_boss = _arena.get_node_or_null("Boss") as Node2D
	_check(_player != null and _boss != null, "战场玩家 / BOSS 已建")
	if _player == null or _boss == null:
		get_tree().quit(1)
		return
	_cam = _player.get_node_or_null("Camera2D") as Camera2D
	var half: Vector2 = _arena.get("arena_half_extents")
	_check(_cam != null and half.x > 1.0, "相机 / 战场半宽高可取",
		"%s / %s" % [str(_cam), str(half)])
	if _cam == null:
		get_tree().quit(1)
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	_boss.set_physics_process(false)
	_boss.set_process(false)

	var fog := _arena.find_child("EdgeFog", true, false) as ColorRect
	_check(fog != null and fog.material is ShaderMaterial, "边界雾已建")
	_viewport_check(half)

	# 贴右墙：人和 BOSS 都在最右侧，检查人是否仍在屏幕中心
	_player.global_position = Vector2(half.x - 72.0, 40.0)
	_boss.global_position = Vector2(half.x - 132.0, 10.0)
	await get_tree().create_timer(2.6, true, false, true).timeout
	var player_scr := _screen_of(_player.global_position)
	var vp := get_viewport().get_visible_rect().size
	_check(absf(player_scr.x - vp.x * 0.5) < 8.0 and absf(player_scr.y - vp.y * 0.5) < 8.0,
		"贴右墙玩家仍在视野中心", str(player_scr))
	var boss_scr := _screen_of(_boss.global_position)
	_check(boss_scr.x > 0.0 and boss_scr.x < vp.x and boss_scr.y > 0.0 and boss_scr.y < vp.y,
		"贴墙时 BOSS 仍在画面内", str(boss_scr))
	await _shot("output/arena_edge_%s_right.png" % boss_id)

	# 真正贴死在墙上（玩家碰撞体允许的极限），看边界雾会不会糊住人
	_player.global_position = Vector2(half.x - 44.0, 40.0)
	_boss.global_position = Vector2(half.x - 104.0, 10.0)
	await get_tree().create_timer(2.2, true, false, true).timeout
	await _shot("output/arena_edge_%s_wall.png" % boss_id)

	# 右下角：两个轴同时贴边
	_player.global_position = Vector2(half.x - 72.0, half.y - 72.0)
	_boss.global_position = Vector2(half.x - 132.0, half.y - 132.0)
	await get_tree().create_timer(2.6, true, false, true).timeout
	player_scr = _screen_of(_player.global_position)
	_check(absf(player_scr.x - vp.x * 0.5) < 8.0 and absf(player_scr.y - vp.y * 0.5) < 8.0,
		"右下角玩家仍在视野中心", str(player_scr))
	await _shot("output/arena_edge_%s_corner.png" % boss_id)

	# 场地中心：作为对照
	_player.global_position = Vector2.ZERO
	_boss.global_position = Vector2(-140.0, 0.0)
	await get_tree().create_timer(2.6, true, false, true).timeout
	player_scr = _screen_of(_player.global_position)
	_check(absf(player_scr.x - vp.x * 0.5) < 8.0 and absf(player_scr.y - vp.y * 0.5) < 8.0,
		"场地中心玩家居中", str(player_scr))
	await _shot("output/arena_edge_%s_center.png" % boss_id)

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _viewport_check(half: Vector2) -> void:
	var vp_half := get_viewport().get_visible_rect().size * 0.5
	_check(_cam.limit_right >= int(half.x + vp_half.x - 1.0),
		"相机右限制已外扩", "%d / 地图 %d" % [_cam.limit_right, int(half.x)])
	_check(_cam.limit_bottom >= int(half.y + vp_half.y - 1.0),
		"相机下限制已外扩", "%d / 地图 %d" % [_cam.limit_bottom, int(half.y)])
	_check(_cam.limit_left <= int(-half.x - vp_half.x + 1.0),
		"相机左限制已外扩", "%d" % _cam.limit_left)
	_check(_cam.limit_top <= int(-half.y - vp_half.y + 1.0),
		"相机上限制已外扩", "%d" % _cam.limit_top)
