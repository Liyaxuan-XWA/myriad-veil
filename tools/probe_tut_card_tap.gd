extends Node
## 教学说明卡「知道了」在手游点不了（2026-11-13）
## 用法：godot --headless --path . --quit-after 200000 res://tools/probe_tut_card_tap.tscn -- --no-save
##
## 根因：说明卡画在虚拟键上面（120 > 90），但它的底部正好落在摇杆召唤区里，
## 触摸合成的鼠标被 VirtualPad 认领 —— 按钮一次都收不到。
## 修法：浮层把「可点矩形」报给 VirtualPad（set_pass_rects），命中就不认领。
## ⚠ 全程只改运行时字段，不写 user://touch_ui.json。

var _passes := 0
var _fails: Array = []
var _hits := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 教学卡按钮能不能点 ##########")
	var was := bool(VirtualPad.is_touch_enabled())
	VirtualPad.set("_has_touchscreen", true)
	VirtualPad.enabled = true
	VirtualPad.call("_apply_enabled")
	VirtualPad.set_context("realm")
	await _frames(3)

	var zone: Rect2 = VirtualPad.call("_stick_zone_rect")
	# 复刻实机位置：按钮落在摇杆区的右下角（截图里「知道了」就在这块）
	var btn := Button.new()
	btn.text = "知道了"
	btn.size = Vector2(120, 40)
	btn.position = zone.position + zone.size * Vector2(0.55, 0.72)
	add_child(btn)
	var bc := btn.get_global_rect().get_center()
	_check(zone.has_point(bc), "前提：按钮确实落在摇杆召唤区里", "点=%s 区=%s" % [bc, zone])

	# ===== 1. 现状（不报让路矩形）：点不着，而且是被摇杆认领 =====
	_check(bool(VirtualPad.call("_owns_point", bc)), "不报让路时：这一点归摇杆管")
	_hits = 0
	btn.pressed.connect(func() -> void: _hits += 1)
	await _tap(bc)
	_check(_hits == 0, "不报让路时：按钮点不着（复现 bug）", str(_hits))

	# ===== 2. 报上让路矩形：点得着 =====
	VirtualPad.set_pass_rects([btn.get_global_rect()])
	_check(not bool(VirtualPad.call("_owns_point", bc)), "报了让路矩形：摇杆不再认领")
	_hits = 0
	await _tap(bc)
	_check(_hits == 1, "报了让路矩形：按钮点得着（且只点一次）", str(_hits))

	# ===== 3. 同一片区域里矩形之外照旧归摇杆 =====
	var outside := zone.position + zone.size * Vector2(0.15, 0.35)
	_check(not btn.get_global_rect().has_point(outside), "前提：对照点确实在卡片外")
	_check(bool(VirtualPad.call("_owns_point", outside)), "对照点：仍然归摇杆管")
	_hits = 0
	await _tap(outside)
	_check(_hits == 0, "对照点不会误点到卡片按钮", str(_hits))

	# ===== 4. 真说明卡：位置算完就把矩形报上来 =====
	VirtualPad.set_pass_rects([])
	var overlay: Node = (load("res://scripts/tutorial/tutorial_overlay.gd") as GDScript).new()
	add_child(overlay)
	await _frames(4)
	overlay.set("_has_target", false)
	overlay.call("_place_card")
	await _frames(2)
	var rects: Array = VirtualPad.get("_pass_rects")
	_check(rects.size() == 1 and (rects[0] as Rect2).size.x > 0.0,
		"真说明卡摆好后把矩形报给了 VirtualPad", str(rects))
	var card: Control = overlay.get("_card")
	_check(card.visible and card.get_combined_minimum_size().x > 200.0,
		"前提：卡片确实摆出来了", "min=%s" % card.get_combined_minimum_size())
	var ok_btn: Button = overlay.get("_card_ok")
	var ok_c := ok_btn.get_global_rect().get_center()
	_check(not bool(VirtualPad.call("_owns_point", ok_c)),
		"真卡片上「知道了」那一点不归摇杆管", "点=%s" % ok_c)

	# ===== 5. 卡片收起后让路矩形要撤掉 =====
	overlay.call("_hide_guide")
	await _frames(2)
	_check((VirtualPad.get("_pass_rects") as Array).is_empty(),
		"卡片收起 → 让路矩形清空", str(VirtualPad.get("_pass_rects")))

	overlay.queue_free()
	await _frames(3)
	VirtualPad.call("_release_all")
	VirtualPad.set("enabled", was)
	VirtualPad.set("_has_touchscreen", false)
	VirtualPad.call("_apply_enabled")
	print("  触屏开关已还原为跑之前的 ", was, "（全程没写 touch_ui.json）")
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _tap(at: Vector2) -> void:
	# 真机那一套：合成鼠标 press → release（不需要 ScreenTouch，VirtualPad 就是靠这个判的）
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	mb.global_position = at
	get_viewport().push_input(mb, true)
	await get_tree().process_frame
	var up := mb.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up, true)
	await _frames(2)
