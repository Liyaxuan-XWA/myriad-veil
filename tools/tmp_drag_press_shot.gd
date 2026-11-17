extends Node
## 一次性实验（不是回归件）：吞掉 release 之后，那颗按钮**画面上**还挂着按下态吗？
## 判据是像素，不是 button_pressed 那个标志位（非 toggle 按钮可能根本不读它）。
## 用法：godot --path . --windowed --resolution 1280x720 res://tools/tmp_drag_press_shot.tscn -- --no-save

const DIR := "output/tmp_drag_press/"
var _sc: ScrollContainer
var _col: VBoxContainer
var _target: Button


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_sc = ScrollContainer.new()
	_sc.size = Vector2(320, 420)
	_sc.custom_minimum_size = Vector2(320, 420)
	_sc.position = Vector2(120, 120)
	add_child(_sc)
	_col = VBoxContainer.new()
	for i in range(30):
		var b := Button.new()
		b.text = "行 %d" % i
		b.custom_minimum_size = Vector2(300, 34)
		_col.add_child(b)
	_sc.add_child(_col)
	await _frames(6)
	_target = _col.get_child(3) as Button
	var c := _target.get_global_rect().get_center()

	# 0) 光标先落在别处，取一张「从没碰过」的底片
	await _warp(Vector2(1100, 60))
	await _frames(4)
	await _shot("00_clean.png")
	# 1) 只悬停（对照组：hover 该长什么样）
	await _warp(c)
	await _frames(4)
	await _shot("01_hover.png")
	# 2) 在按钮上按下 → 拖 140 → 在拖动的路上抬手（ScrollDrag 会吞掉这发 release）
	await _press(true, c)
	await _frames(2)
	await _shot("02_held.png")
	var to := c - Vector2(0, 140)
	for i in range(7):
		await _warp(c.lerp(to, float(i + 1) / 7.0))
		await _press_move(c.lerp(to, float(i + 1) / 7.0))
		await get_tree().process_frame
	await _press(false, to)
	await _frames(2)
	# 把列表滚回原位、光标挪到别处：这样这一张和 00_clean 比的是**同一格像素**，
	# 唯一区别就是那颗按钮从没收到过 release
	_sc.scroll_vertical = 0
	await _warp(Vector2(1100, 60))
	await _frames(5)
	await _shot("03_after_drag.png")
	# 4) 对照：正常点完（走完 press+release），同样滚回原位、光标同样挪开
	await _warp(c)
	await _frames(3)
	await _press(true, c)
	await _frames(2)
	await _press(false, c)
	_sc.scroll_vertical = 0
	await _warp(Vector2(1100, 60))
	await _frames(5)
	await _shot("04_normal_click.png")
	print("RESULT 拖动后 vs 干净 ==", _cmp("00_clean.png", "03_after_drag.png"),
		"   正常点击后 vs 干净 ==", _cmp("00_clean.png", "04_normal_click.png"),
		"   按住时 vs 干净 ==", _cmp("00_clean.png", "02_held.png"))
	get_tree().quit(0)


## 只比按钮那一条横带的像素，别拿整屏噪声凑数
func _cmp(a: String, b: String) -> String:
	var ia := Image.load_from_file(ProjectSettings.globalize_path(DIR + a))
	var ib := Image.load_from_file(ProjectSettings.globalize_path(DIR + b))
	if ia == null or ib == null:
		return "读不到图"
	var r := _target.get_global_rect()
	var x0 := int(r.position.x)
	var y0 := int(r.position.y)
	var x1 := mini(int(r.end.x), ia.get_width())
	var y1 := mini(int(r.end.y), ia.get_height())
	var diff := 0
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			n += 1
			if ia.get_pixel(x, y) != ib.get_pixel(x, y):
				diff += 1
	return "%d/%d 像素不同 (%.1f%%)" % [diff, n, 100.0 * diff / maxi(n, 1)]


func _warp(p: Vector2) -> void:
	Input.warp_mouse(p)
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + name)
	print("SHOT ", DIR + name)


func _press(p: bool, at: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = p
	mb.position = at
	mb.global_position = at
	get_viewport().push_input(mb, true)


## 带左键掩码的移动：真实拖动就是这一串（ScrollDrag 靠它判阈值）
func _press_move(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(mm, true)
