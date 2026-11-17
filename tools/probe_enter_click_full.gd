extends Node
## 真实鼠标点击「踏入」→ 切场景 全链路（2026-11-02 摇杆吞点击回归）。
## ⚠ 2026-11-10 复测：headless 下点完不切场景（旧提交 2be2547 同样如此），
##   不是新手指引引入的回归；要查得用窗口模式手动复盘。别把它当绿灯看。

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
		print("FULL board missing")
		get_tree().quit(1)
		return
	var enter: Button = board._enter
	var center := enter.get_global_rect().get_center()
	print("FULL enter rect=", enter.get_global_rect(), " disabled=", enter.disabled,
		" paused=", get_tree().paused)
	var keeper := Node.new()
	keeper.set_script(load("res://tools/enter_world_checker.gd"))
	get_tree().root.add_child(keeper)
	var m := InputEventMouseMotion.new()
	m.position = center
	m.global_position = center
	get_viewport().push_input(m)
	await get_tree().process_frame
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
