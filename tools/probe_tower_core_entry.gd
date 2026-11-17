extends Node
## 万界塔区域核心分支：点击先出右侧记录碑，再点底部「进入」（2026-10-30）
## 用法：godot --headless --path . tools/probe_tower_core_entry.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _branch_button(root: Node) -> Button:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b != null and b.tooltip_text.contains("分支节点"):
			return b
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 万界塔 · 区域核心分支入口 ##########")
	get_tree().create_timer(15.0, true, false, true).timeout.connect(func() -> void:
		print("PROBE TIMEOUT")
		get_tree().quit(2))
	CharacterData.secret_world["core_kills"] = {"world_lianqi": true}
	CharacterData.core_replay = {"world_lianqi": {"clear_count": 3}}
	GameState.battle_context = {}

	var panel := TowerPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame

	var btn := _branch_button(panel)
	_check(btn != null, "找到区域核心分支按钮")
	if btn == null:
		get_tree().quit(1)
		return
	btn.pressed.emit()
	await get_tree().process_frame
	_check(panel.visible, "点分支后面板保持打开")
	_check(panel._selected_core == "world_lianqi" and panel._selected_floor == 0,
		"分支进入选中态（不占塔层）",
		"%s / %d" % [panel._selected_core, panel._selected_floor])
	_check(panel._map.selected == -1, "地图不误亮塔层")
	_check(GameState.battle_context.is_empty(), "点分支不直接开战")
	_check(panel._detail_name_label.text.contains("青岚古猿")
		and panel._detail_name_label.text.contains("重战"),
		"右侧展示核心首领", panel._detail_name_label.text)
	_check(panel._challenge_btn.text == "进入" and not panel._challenge_btn.disabled,
		"底部按钮为「进入」", panel._challenge_btn.text)
	_check(panel._detail_best_cap.text == "重战次数"
		and panel._detail_best_label.text == "×3",
		"记录碑显示重战次数", "%s %s" % [panel._detail_best_cap.text, panel._detail_best_label.text])

	# 点塔层应切回层详情
	panel._select_floor(1)
	await get_tree().process_frame
	_check(panel._selected_core == "" and panel._detail_best_cap.text == "最快用时",
		"切回塔层后恢复层记录", panel._detail_best_cap.text)

	# 再点分支，确认底部按钮接线到「进入」逻辑（不在这里真的切战斗场景）
	btn.pressed.emit()
	await get_tree().process_frame
	var enter_handler := Callable(panel, "_on_challenge_selected")
	_check(panel._challenge_btn.pressed.is_connected(enter_handler),
		"底部「进入」按钮已接进入逻辑")
	_check(GameState.battle_context.is_empty(), "选中分支期间仍未开战")

	# 塔层全部要落在画布内：画布高度以前写死 600，照影界涨到 3 位守关者后
	# 最高几层落到负 y，被 clip_contents 剪掉、ScrollContainer 又滚不到负坐标
	# → 2026-11-02 用户报「无法滑动到上面」
	var rows: Dictionary = panel._floor_by_no
	var below_zero := ""
	for no in rows.keys():
		var row_btn: Control = (rows[no] as Dictionary).get("button")
		if row_btn != null and row_btn.position.y < 0.0:
			below_zero += "%d " % int(no)
	_check(below_zero == "", "所有塔层都在画布内（没有负 y）", below_zero)
	var top_no := 0
	for no in rows.keys():
		top_no = maxi(top_no, int(no))
	panel._map_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var view := panel._map_scroll.get_global_rect()
	var top_rect: Rect2 = ((rows[top_no] as Dictionary).get("button") as Control).get_global_rect()
	_check(view.encloses(top_rect), "滚到最顶能看到第 %d 层" % top_no,
		"视口=%s 层=%s" % [str(view), str(top_rect)])

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
