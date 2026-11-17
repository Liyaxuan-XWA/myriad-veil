extends Node
## 成就卡包交互探针：展开页点卡进单卡 / 单卡悬停视差 / 拖动 / 拖出卡面松手。
## 用法：godot --path . --windowed --resolution 1600x900 tools/probe_holo_interact.tscn -- --no-save

var _fails := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS  ", label, "  ", detail)
	else:
		_fails += 1
		print("FAIL  ", label, "  ", detail)


func _shot(p_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + p_name)
	print("SHOT output/", p_name)


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(ev)


func _mouse_move(pos: Vector2, relative: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = relative
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(ev)


func _card_center(card: Control) -> Vector2:
	return get_viewport().get_final_transform() \
		* card.get_global_transform_with_canvas() * (card.size * 0.5)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var watchdog := get_tree().create_timer(20.0, true, false, true)
	watchdog.timeout.connect(func() -> void:
		print("FAIL watchdog timeout")
		get_tree().quit(2))
	CharacterData.tower_progress[2] = {"unlocked": true, "first_kill": true, "clear_count": 12}
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view

	# 展开页点中间那张进单卡（视图级 _input 处理，先移动鼠标再按下）
	view.open_boss("boss_01")
	await get_tree().create_timer(1.0, true, false, true).timeout
	var holo := view.find_child("HoloSpread0", true, false) as HoloCardView
	if holo == null:
		_check(false, "展开页有 HoloSpread0")
		get_tree().quit(1)
		return
	var center := _card_center(holo)
	_mouse_move(center, Vector2.ZERO, false)
	await get_tree().process_frame
	_mouse_button(center, true)
	await get_tree().process_frame
	_mouse_button(center, false)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check(view._mode == AchievementView.MODE_SINGLE, "点卡进入单卡查看",
		"mode=%d" % view._mode)
	if view._mode != AchievementView.MODE_SINGLE:
		get_tree().quit(1)
		return

	# 单卡悬停视差
	var big := view.find_child("HoloSingle", true, false) as HoloCardView
	if big == null:
		_check(false, "单卡大图已建")
		get_tree().quit(1)
		return
	big.set_idle_motion(false)
	center = _card_center(big)
	_mouse_move(center + Vector2(-80.0, -120.0), Vector2(-20.0, -20.0), false)
	await get_tree().create_timer(0.35, true, false, true).timeout
	print("HOVER view ", big._view)
	_check(absf(float(big._view.x)) > 0.05, "悬停产生视差", str(big._view))
	await _shot("achievement_pack_hover.png")

	# 拖动卡面
	_mouse_move(center, Vector2.ZERO, false)
	await get_tree().process_frame
	_mouse_button(center, true)
	await get_tree().process_frame
	_mouse_move(center + Vector2(80.0, 20.0), Vector2(80.0, 20.0), true)
	await get_tree().create_timer(0.4, true, false, true).timeout
	print("DRAG view ", big._view)
	_check(absf(float(big._view.x)) > 0.1, "拖动改变视差", str(big._view))
	await _shot("achievement_pack_drag.png")
	_mouse_button(center + Vector2(80.0, 20.0), false)
	await get_tree().create_timer(0.6, true, false, true).timeout
	print("RELEASE view ", big._view)
	await _shot("achievement_pack_release.png")

	# 拖出卡面再松手：不能卡在拖动状态
	_mouse_button(center, true)
	await get_tree().process_frame
	_mouse_move(center + Vector2(220.0, 140.0), Vector2(220.0, 140.0), true)
	await get_tree().process_frame
	_mouse_button(center + Vector2(220.0, 140.0), false)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check(not big._dragging, "拖出卡面松手后退出拖动", str(big._dragging))
	print("OUTSIDE dragging=", big._dragging, " view ", big._view)
	await _shot("achievement_pack_release_outside.png")

	print("\n########## 结果：%d 项失败 ##########" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
