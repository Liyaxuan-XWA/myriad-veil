extends Node
## 拖动滚动 · 真面板前后对照截图（给用户一眼看出「拖得动」）
## 用法：godot --path . --windowed --resolution 1280x720 res://tools/shot_drag_scroll.tscn -- --no-save
##
## 走的是真事件（按下 → 一串带左键掩码的移动 → 抬手），
## 读数用引擎自己的 scroll_vertical，不自己置标记。

const PANELS := [
	"res://scripts/ui/panels/guide_panel.gd",
	"res://scripts/ui/panels/tower_panel.gd",
	"res://scripts/ui/character_panel.gd",
	"res://scripts/ui/panels/warehouse_panel.gd",
]

var _panel: Node = null


func _ready() -> void:
	for path in PANELS:
		var name: String = path.get_file().get_basename()
		await _one(path, name)
	print("\n########## 拖动滚动截图完成 ##########")
	get_tree().quit(0)


func _one(path: String, name: String) -> void:
	# 显式标注类型：`.new()` 返回 Variant，用 := 推断会被本项目的编译设置当错误
	_panel = (load(path) as GDScript).new()
	add_child(_panel)
	await _frames(4)
	# 两套叫法都有：SystemPanel 系是 open()/close()，character_panel 是 open_panel()/close_panel()
	var op := "open" if _panel.has_method("open") else "open_panel"
	var cl := "close" if _panel.has_method("close") else "close_panel"
	_panel.call(op)
	await _frames(20)
	var scrollers: Array = []
	_collect(_panel, scrollers)
	for s in scrollers:
		var vb = (s as ScrollContainer).get_v_scroll_bar()
		print("  DIAG ", name, "/", (s as ScrollContainer).name,
			" max=", vb.max_value, " page=", vb.page, " 可视=", (s as ScrollContainer).visible)
	var sc := _biggest_scroller(_panel)
	if sc == null:
		print("SKIP ", name, " 里没找到可滚的列表（滚动区共 ", scrollers.size(), " 个）")
	else:
		# 先归零再往上拖：面板记住的上一次位置可能已经在底部，
		# 底部再往上拖内容动不了，看起来就像「拖不动」（第一次就踩了这个）
		sc.scroll_vertical = 0
		await _frames(3)
		var before: int = sc.scroll_vertical
		await _shot("%s_0_before.png" % name)
		var r := sc.get_global_rect()
		var from := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.62)
		var to := from - Vector2(0, 130)
		await _drag(from, to)
		await _frames(3)
		var after: int = sc.scroll_vertical
		await _shot("%s_1_after_drag.png" % name)
		print("%-16s 滚动区=%s  拖动前 scroll=%d  拖动后 scroll=%d  %s" % [
			name, sc.name, before, after,
			"拖得动 ✓" if after > before else "没动 ✗"])
	# SystemPanel.close() 会把自己 queue_free，这里不能再用一次
	if _panel != null and is_instance_valid(_panel):
		_panel.call(cl)
	_panel = null
	await _frames(6)


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ScrollContainer:
			out.append(c)
		_collect(c, out)


## 面板里「最有内容可滚」的那个滚动区：max_value 减 page 最大的
func _biggest_scroller(n: Node, best: ScrollContainer = null) -> ScrollContainer:
	for c in n.get_children():
		if c is ScrollContainer:
			var sc := c as ScrollContainer
			var vb := sc.get_v_scroll_bar()
			var room := 0.0
			if vb != null:
				room = vb.max_value - vb.page
			if best == null or room > _room(best):
				if room > 0.5:
					best = sc
		best = _biggest_scroller(c, best)
	return best


func _room(sc: ScrollContainer) -> float:
	var vb := sc.get_v_scroll_bar()
	return 0.0 if vb == null else vb.max_value - vb.page


func _drag(from: Vector2, to: Vector2) -> void:
	Input.warp_mouse(from)
	await get_tree().process_frame
	_mouse(true, from)
	await get_tree().process_frame
	var steps := 8
	for i in range(steps):
		var p: Vector2 = from.lerp(to, float(i + 1) / steps)
		Input.warp_mouse(p)
		_motion(p)
		await get_tree().process_frame
	_mouse(false, to)
	await get_tree().process_frame


func _mouse(pressed: bool, at: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = at
	mb.global_position = at
	get_viewport().push_input(mb, true)


func _motion(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(mm, true)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/drag_scroll_" + name)
	print("SHOT output/drag_scroll_", name)
