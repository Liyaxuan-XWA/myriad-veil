extends Node
## 苍澜大陆页三个按钮的点击命中对比：页签 / 区域选择 / 踏入。

var _pressed: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := DomainPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	panel._tab = "world"
	panel._refresh_content()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var board: Node = null
	for c in panel._body.get_children():
		if c.get_script() == load("res://scripts/ui/facility/world_region_board.gd"):
			board = c
	if board == null:
		print("BOARD missing")
		get_tree().quit(1)
		return

	board.enter_world_requested.disconnect(panel._on_enter_world)
	var tab: Button = panel._tab_world
	var sel: Button = null
	for c in board._selector.get_children():
		if c is Button:
			sel = c
			break
	var enter: Button = board._enter
	print("TAB ", tab.text, " rect=", tab.get_global_rect(), " mf=", tab.mouse_filter,
		" disabled=", tab.disabled, " pm=", tab.process_mode)
	print("SEL ", sel.text if sel != null else "<none>",
		" rect=", sel.get_global_rect() if sel != null else Rect2(),
		" mf=", sel.mouse_filter if sel != null else -1)
	print("ENTER ", enter.text, " rect=", enter.get_global_rect(), " mf=", enter.mouse_filter,
		" disabled=", enter.disabled, " pm=", enter.process_mode,
		" parent=", enter.get_parent().get_class(), " grand=", enter.get_parent().get_parent().get_class())

	for pair in [["tab", tab], ["sel", sel], ["enter", enter]]:
		var tag := String(pair[0])
		var b: Button = pair[1]
		if b == null:
			continue
		b.pressed.connect(_on_btn.bind(tag))
		if tag == "enter":
			b.gui_input.connect(func(e: InputEvent) -> void: print("   ENTER_GUI ", e))
			var anc: Node = b.get_parent()
			while anc != null:
				if anc is Control:
					(anc as Control).gui_input.connect(_trace_gui.bind(anc as Control))
				anc = anc.get_parent()
			b.button_down.connect(func() -> void: print("   ENTER_DOWN"))
			b.button_up.connect(func() -> void: print("   ENTER_UP"))
		var center := b.get_global_rect().get_center()
		var hover := get_viewport().gui_get_hovered_control()
		print("  ", tag, " center=", center, " rect=", b.get_global_rect(),
			" scale=", b.scale, " pivot=", b.pivot_offset)
		_click(center)
		await get_tree().process_frame
		await get_tree().process_frame
		print("  ", tag, " hovered_before=", hover.name if hover != null else "-",
			" pressed=", tag in _pressed)
	# 键盘路径也验证一次（焦点 + ui_accept）
	var vp := get_tree().root.get_node_or_null("VirtualPad")
	if vp != null:
		var stick = vp.get("_stick")
		print("VIRTUAL_PAD enabled=", vp.get("enabled"), " root_vis=", vp.get("_root").visible,
			" stick_vis=", stick.visible if stick != null else "-",
			" stick_hit_enter=", stick.hit(enter.get_global_rect().get_center()) if stick != null else "-",
			" stick_rect=", stick.get_global_rect() if stick != null else "-")
	else:
		print("VIRTUAL_PAD <none>")
	print("FOCUS_MODE=", enter.focus_mode)
	enter.grab_focus()
	print("FOCUSED=", get_viewport().gui_get_focus_owner() == enter)
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	get_viewport().push_input(accept)
	await get_tree().process_frame
	var rel := InputEventAction.new()
	rel.action = "ui_accept"
	rel.pressed = false
	get_viewport().push_input(rel)
	await get_tree().process_frame
	print("enter via keyboard pressed=", "enter" in _pressed)
	get_tree().paused = false
	get_tree().quit(0)


func _trace_gui(c: Control, e: InputEvent) -> void:
	if e is InputEventMouseButton:
		print("   GUI_ON ", c.name, "(", c.get_class(), ") ", e)


func _on_btn(tag: String) -> void:
	_pressed.append(tag)


func _click(center: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = center
	m.global_position = center
	get_viewport().push_input(m)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = center
	d.global_position = center
	get_viewport().push_input(d)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = center
	u.global_position = center
	get_viewport().push_input(u)
