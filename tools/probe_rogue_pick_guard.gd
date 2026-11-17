extends Node
## 试炼之路「玉简三选一」防误触自检（2026-11-08）
## 复现用户报的场景：清场时一直连点左键攻击，面板一弹出就被误触收走一张卡。
## 验：冷却窗 / 按住左键守卫 / 两步式（选中不结算）/ 改选 / 确认只结算一次。
## 用法：godot --headless --path . res://tools/probe_rogue_pick_guard.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _picked: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## ⚠ 面板 open() 会把树暂停，create_timer 会被一起冻住。
##   时序断言统一用 Time.get_ticks_msec() 轮询 + process_frame（暂停下照常推进）。
func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


func _click_card(panel: RoguePickPanel, index: int) -> void:
	var row: HBoxContainer = panel.get("_row")
	if row == null or index >= row.get_child_count():
		return
	var card: Control = row.get_child(index) as Control
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	card.emit_signal("gui_input", ev)


func _press_confirm(panel: RoguePickPanel) -> void:
	var btn: Button = panel.get("_confirm_btn")
	if btn != null and is_instance_valid(btn):
		btn.emit_signal("pressed")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	print("\n########## 玉简三选一 · 防误触 ##########")
	var choices := [
		{"id": "probe_a", "name": "甲简", "rarity": RogueDB.RARITY_COMMON, "desc": "测试用甲"},
		{"id": "probe_b", "name": "乙简", "rarity": RogueDB.RARITY_RARE, "desc": "测试用乙"},
		{"id": "probe_c", "name": "丙简", "rarity": RogueDB.RARITY_LEGEND, "desc": "测试用丙"},
	]
	var panel := RoguePickPanel.new()
	panel.setup(choices, 1, 2)
	panel.picked.connect(func(id: String) -> void: _picked.append(id))
	# 真实运行时挂在 root 下（CanvasLayer），保持一致。
	# ⚠ _ready 栈帧里 root 正在布置 children，直接 add_child 会被拒（节点脱树，
	#   随后 open() 里 get_tree() 返回 null）→ 必须 call_deferred + 多等一帧让 _ready 建完外壳。
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame

	var btn: Button = panel.get("_confirm_btn")
	_check(btn != null and is_instance_valid(btn), "下方有确认按钮")
	_check(btn != null and btn.disabled, "确认按钮初始灰着（没选卡）", str(btn.text))
	_check(String(panel.selected_id) == "", "开局没有预选中的玉简")

	# ① 弹出瞬间的连点：冷却窗内一律不受理
	_click_card(panel, 0)
	_press_confirm(panel)
	_check(String(panel.selected_id) == "", "弹出瞬间的连点不会选中玉简",
		String(panel.selected_id))
	_check(_picked.is_empty(), "弹出瞬间的连点不会结算（老 bug 复现点）", str(_picked))

	# ② 打开时左键仍按着 → 必须先收到一次「松开」
	await _wait_ms(360)
	panel.set("_require_release", true)
	_click_card(panel, 0)
	_check(String(panel.selected_id) == "", "左键未松开时点玉简无效")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	panel.call("_input", release)
	_check(panel.get("_require_release") == false, "收到松开后解除守卫")

	# ③ 冷却过了：点第一张只「选中」，不结算
	_click_card(panel, 0)
	_check(String(panel.selected_id) == "probe_a", "点玉简只选中", String(panel.selected_id))
	_check(_picked.is_empty(), "选中不会立刻结算（两步式）", str(_picked))
	_check(panel.get("_visible") == true, "选中后面板仍开着")

	# ④ 刚选中就按确认：仍在冷却，不结算
	_press_confirm(panel)
	_check(_picked.is_empty(), "刚选中就按确认不结算（防连点穿透）", str(_picked))

	await _wait_ms(320)
	_check(btn.disabled == false, "冷却走完后确认按钮亮起", str(btn.text))

	# ⑤ 改选：换成第三张，且改选会重新上冷却
	_click_card(panel, 2)
	_check(String(panel.selected_id) == "probe_c", "可以改选", String(panel.selected_id))
	_press_confirm(panel)
	_check(_picked.is_empty(), "改选后立刻按确认仍不结算", str(_picked))

	# ⑥ 冷却走完，正常确认 → 只结算一次，面板关闭
	await _wait_ms(320)
	_press_confirm(panel)
	_check(_picked.size() == 1 and String(_picked[0]) == "probe_c",
		"确认后结算的是最后选中的那张", str(_picked))
	_check(panel.get("_visible") == false, "确认后面板关闭")
	_press_confirm(panel)
	_check(_picked.size() == 1, "重复按确认不会二次结算", str(_picked))

	RogueRun.restore()
