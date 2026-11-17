extends Node
## 一次性诊断：整屏浮层的 mouse_filter 三种取值，各自会让
##   ① 浮层**里面**的按钮 ② 浮层**空着的地方**底下的世界
## 收到点击吗？必须**窗口化**跑：无头模式 Viewport 根本不给 GUI 派发合成鼠标事件
## （三种 filter 全部"按钮收不到、世界收得到"，会把结论彻底带偏）。
## 用法：godot --path . --resolution 1280x720 res://tools/diag_gui_filter.tscn -- --no-save

const NAMES := {0: "STOP  ", 1: "PASS  ", 2: "IGNORE"}

var _world := ""
var _got := ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_world = _world + "|world"


func _send(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = at
	d.global_position = at
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	for e in [m, d, u]:
		get_viewport().push_input(e)
	await get_tree().process_frame


func _probe(root_filter: int) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var host := Control.new()
	host.mouse_filter = root_filter
	layer.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 两层容器，模拟 ScrollContainer → GridContainer → Button 的嵌套
	var mid := VBoxContainer.new()
	mid.mouse_filter = root_filter
	host.add_child(mid)
	mid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var b := Button.new()
	b.text = "B"
	b.position = Vector2(60, 60)
	b.size = Vector2(100, 40)
	mid.add_child(b)
	_got = ""
	_world = ""
	b.pressed.connect(func(): _got = "btn")
	await get_tree().process_frame
	await get_tree().process_frame
	await _send(b.get_global_rect().get_center())
	var on_btn := _got
	_got = ""
	_world = ""
	await _send(Vector2(600, 400))          # 浮层空着的地方
	var on_empty := _world
	print("DIAG 浮层与中间容器同为 ", String(NAMES.get(root_filter, root_filter)),
			" → 按钮=", ("收到" if on_btn != "" else "收不到"),
			" 空处世界=", ("收到" if on_empty != "" else "收不到"))
	layer.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	print("DIAG viewport=", get_viewport().get_visible_rect().size)
	for f in [Control.MOUSE_FILTER_STOP, Control.MOUSE_FILTER_PASS, Control.MOUSE_FILTER_IGNORE]:
		await _probe(f)
	get_tree().quit(0)
