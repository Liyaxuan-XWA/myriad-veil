extends Node
## 一次实验：安卓上「推摇杆为什么会点开设施」——摇杆吞的是 ScreenTouch，
## 而 facility.gd:93 认的是 MouseButton。这里量两件事：
##   ① 注入一根手指的触摸，引擎会不会另外生成鼠标左键；
##   ② 运行时 ProjectSettings.set_setting("...emulate_mouse_from_touch", false) 到底管不管用。
## 用法：godot --headless --path . --quit-after 6000 res://tools/probe_touch_mouse_emu.tscn

var _seen: Array = []


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_seen.append("ScreenTouch p=%s" % (event as InputEventScreenTouch).pressed)
	elif event is InputEventScreenDrag:
		_seen.append("ScreenDrag")
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_seen.append("MouseButton L p=%s @%s" % [mb.pressed, mb.position])
	elif event is InputEventMouseMotion:
		_seen.append("MouseMotion")


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	var center := Vector2(vp.x * 0.135, vp.y * 0.720)
	print("视口=", vp, " 摇杆中心=", center)
	print("emulate_mouse_from_touch 初始=",
		ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"))

	# 阶段 1：默认设置下注入一根手指（按-拖-抬）
	_seen.clear()
	await _inject_finger(center)
	var mouse_a := _count_mouse()
	print("阶段1 默认设置：鼠标事件=", mouse_a, " 条  事件序=", _seen)

	# 阶段 2：运行时把开关关掉（VirtualPad._ready 就是这么写的），再注入一次
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", false)
	_seen.clear()
	await _inject_finger(center)
	var mouse_b := _count_mouse()
	print("阶段2 set_setting(false) 后：鼠标事件=", mouse_b, " 条  事件序=", _seen)
	print("结论：", "运行时 set_setting 有效 —— 关掉后触摸不再合成鼠标"
			if mouse_b == 0 else "运行时 set_setting 无效（开关只在启动时读一次），得改用吞事件的路子")
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", true)
	get_tree().quit(0)


func _count_mouse() -> int:
	var n := 0
	for s in _seen:
		if String(s).begins_with("MouseButton") or String(s).begins_with("MouseMotion"):
			n += 1
	return n


func _inject_finger(center: Vector2) -> void:
	_push_touch(0, center, true)
	await get_tree().process_frame
	_push_drag(0, center + Vector2(40, 20))
	await get_tree().process_frame
	_push_drag(0, center + Vector2(60, 30))
	await get_tree().process_frame
	_push_touch(0, center + Vector2(60, 30), false)
	for i in range(6):
		await get_tree().process_frame


## 走 Input.parse_input_event（= 真机触摸的同一入口），触摸→鼠标模拟才会在这里发生
func _push_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)


func _push_drag(idx: int, pos: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = pos
	Input.parse_input_event(d)
