extends Node
## 全局「按住拖动滚动」（2026-11-13 用户要求：所有可滑动界面都能用鼠标拖着滚）
##
## 为什么必须自己做：实测本引擎的 ScrollContainer 既不吃鼠标拖动、也不吃手指拖动
## （tools/tmp_drag_scroll_test 五种 mouse_filter 组合 + force_pass_scroll + ScreenDrag
##   全部「拖不动」，`scroll_deadzone` 默认 0 也照样不动）。面板里 24 个滚动区散在
## 15 个脚本（场景文件里 0 处，全是代码建的），逐个挂脚本必然漏，所以做成一个 autoload：
## 谁都能用，以后新建的界面也自动带上，不用记得接。
##
## 走的是**鼠标事件那一路**：安卓上 `emulate_mouse_from_touch=true`，手指本来就会
## 合成一套鼠标事件（VirtualPad 也是靠这个判定的），所以一套代码同时管住 PC 与手机；
## 摇杆/虚拟键命中区里的合成鼠标已经被 VirtualPad 吞掉，这里自然接不到，不会打架。
##
## 三条不能碰的边界：
##   1. 滚动条本体照旧归引擎 —— 落在滚动条上就不接管，否则拖不动也点不准；
##   2. 锻造台纸签那种 GUI 拖拽优先 —— 一旦 `gui_is_dragging()` 立刻放手；
##   3. 文本编辑/输入框要留选区 —— 落在 TextEdit / LineEdit 上不接管。
##
## 拖动过的那一发 release 必须吞掉，不然「拖列表」变成「点列表里那颗按钮」。
## 真机上最要紧的是这一种：拖到边界、内容已经动不了，光标却还在同一颗按钮里。
## 吞掉 release 不会留下「按下态」外观 —— 这条拿像素判过，
## 见 tools/tmp_drag_press_shot.gd（窗口化：按住时 99.9% 像素不同、拖完 0/10200）。
## 收尾那发不带按钮掩码的 MouseMotion 只是保险，目前没有断言撑着它（变异 M3b 跑出来全绿）。

## 超过这个位移才算「拖」，不算「点」（与 Godot 自己的 GUI 拖拽阈值同量级）
const THRESHOLD := 10.0
## 给个别容器留的后门：`set_meta("no_drag_scroll", true)` 就不接管（默认全部接管）。
## 标本身上也认 —— 只标记住不放的那张卡（华彩卡/手牌），同列表的空白处照样能拖滚。
const META_DISABLE := "no_drag_scroll"

var _target: ScrollContainer = null
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _dragging := false
var _enabled := true


func _ready() -> void:
	# 面板是暂停态（SystemPanel 会 pause 整棵树），拖动必须照常能用
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_begin(mb.position)
		else:
			_end(mb.position)
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		_move(mm.position)


# ===================== 三段处理 =====================

func _begin(pos: Vector2) -> void:
	_dragging = false
	# 摇杆/虚拟键命中区归 VirtualPad 管：PC 上手动开触屏按键调试时，那一按不该顺手
	# 把底下的面板滚一屏（VirtualPad 自己会吞掉那一路事件，但它的层是 IGNORE，
	# 这里按同一个判据让路，别去抢）
	if VirtualPad.is_touch_enabled() and bool(VirtualPad.call("_owns_point", pos)):
		_target = null
		return
	_target = _container_at(pos)
	if _target == null:
		return
	_start = pos
	_last = pos


func _move(pos: Vector2) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	# 子节点自己开始了 GUI 拖拽（锻造台纸签上砧、棋局拖棋子）：让路
	if get_viewport().gui_is_dragging():
		_reset()
		return
	if not _dragging and pos.distance_to(_start) < THRESHOLD:
		return
	_dragging = true
	var delta := pos - _last
	_last = pos
	if not _apply_delta(_target, delta):
		return
	# 这一拍打「已处理」：挡掉后面 `_unhandled_input` 那一路的读者
	# （世界里的鼠标瞄准 / 点地那类，不该把面板里的拖动当成瞄准移动）。
	# ⚠ 别指望它挡得住 hover —— Viewport 自己算 mouse_over，实测该亮还是亮，
	#   正常拖动时内容 1:1 跟手所以只有一行在光标底下，看起来才像「没亮」。
	get_viewport().set_input_as_handled()


func _end(pos: Vector2) -> void:
	var was_dragging := _dragging
	_reset()
	if not was_dragging:
		return
	# 拖动过 → 这发 release 不能变成点击
	get_viewport().set_input_as_handled()
	_resync_hover.call_deferred(pos)


## 吞掉 release 之后，被拖的那个按钮收不到抬起，会一直挂着「按下」的外观。
## 补一发不带按钮掩码的移动，让 GUI 重新算一次悬停把它清掉。
func _resync_hover(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.relative = Vector2.ZERO
	mm.button_mask = 0
	if is_instance_valid(get_viewport()):
		get_viewport().push_input(mm, true)


func _reset() -> void:
	_target = null
	_dragging = false
	_start = Vector2.ZERO
	_last = Vector2.ZERO


# ===================== 找该谁滚 =====================

## 命中点下**最深**的那个可滚 ScrollContainer（嵌套列表时里层优先）
func _container_at(pos: Vector2) -> ScrollContainer:
	var best: ScrollContainer = null
	var best_depth := -1
	for sc in _all_scroll_containers(get_tree().root):
		if not sc.visible or not sc.get_global_rect().has_point(pos):
			continue
		if sc.has_meta(META_DISABLE):
			continue
		if _over_scrollbar(sc, pos):
			continue
		if not _scrollable(sc):
			continue
		if _blocks_drag(pos):
			continue
		var d := _depth(sc)
		if d > best_depth:
			best_depth = d
			best = sc
	return best


func _all_scroll_containers(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is ScrollContainer:
			out.append(c)
		_all_scroll_containers(c, out)
	return out


func _depth(n: Node) -> int:
	var d := 0
	var p := n.get_parent()
	while p != null:
		d += 1
		p = p.get_parent()
	return d


## 滚动条本体交给引擎自己拖，别抢
func _over_scrollbar(sc: ScrollContainer, pos: Vector2) -> bool:
	var vb := sc.get_v_scroll_bar()
	var hb := sc.get_h_scroll_bar()
	if vb != null and vb.visible and vb.get_global_rect().has_point(pos):
		return true
	if hb != null and hb.visible and hb.get_global_rect().has_point(pos):
		return true
	return false


## 有没有得滚：滚动条 max_value 为 0 就是内容没超出，不用接管
func _scrollable(sc: ScrollContainer) -> bool:
	return _has_room(sc.get_v_scroll_bar()) or _has_room(sc.get_h_scroll_bar())


## 到底有没有得滚：max_value 是「内容长度」，page 是「可视长度」，
## 只有 max_value > page 才有可滚范围。
## ⚠ 只看 max_value > 0 会误判 —— 实测指引书面板 max=430 / page=430（内容正好铺满），
##   写 scroll_vertical=15 被引擎夹回 0，探针当时报的就是「0 个动了」。
func _has_room(bar: ScrollBar) -> bool:
	return bar != null and bar.max_value > bar.page + 0.5


## 落在文本编辑 / 输入框上时不接管：那边拖动是要选字的
func _blocks_drag(pos: Vector2) -> bool:
	# 显式标注类型：这里在父链上往上走，用 := 会从 Variant 推断，
	# 本项目的编译设置会把那条警告当错误
	# 落在「自己实现了 _get_drag_data 的控件」上也不接管：那是锻造台纸签上砧、
	# 棋局拖棋子那类拖拽，阈值和这里几乎一样（Godot 默认 10px），谁先抢到看运气，
	# 所以直接让路。基类每个 Control 都有 _get_drag_data 方法，只能看脚本有没有覆盖。
	var c: Control = _control_at(pos)
	while c != null:
		# 后门也可以标在「自己吃拖拽的那个控件」身上（华彩卡、手牌）
		if c.has_meta(META_DISABLE):
			return true
		if c is TextEdit or c is LineEdit:
			return true
		if _is_drag_source(c):
			return true
		c = c.get_parent() as Control
	return false


## 指针下那个「真的会收事件的控件」。
## ⚠ 不能只读 `gui_get_hovered_control()`：手机上第一发事件就是按下，之前没有移动，
##   hover 还是空的 —— 那样拖拽源/输入框的让路判定就会形同虚设（探针 9b 抓到过）。
##   所以 hover 不可信时，自己按矩形从最深层往上找一个非 IGNORE 的控件。
func _control_at(pos: Vector2) -> Control:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.get_global_rect().has_point(pos):
		return hovered
	var best: Control = null
	var best_depth := -1
	for c in _all_controls(get_tree().root):
		if not (c is Control) or not (c as Control).visible:
			continue
		if (c as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if not (c as Control).get_global_rect().has_point(pos):
			continue
		var d := _depth(c)
		if d > best_depth:
			best_depth = d
			best = c as Control
	return best


func _all_controls(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		out.append(c)
		_all_controls(c, out)
	return out


func _is_drag_source(c: Control) -> bool:
	var s := c.get_script() as GDScript
	if s == null:
		return false
	for m in s.get_script_method_list():
		if String(m["name"]) == "_get_drag_data":
			return true
	return false


## 真正滚一下。返回 false = 这一发没动（该让 GUI 自己处理）
## 两个轴各自独立：竖排列表跟手上下走，横排（卡包 / 图鉴分类条）跟手左右走。
func _apply_delta(sc: ScrollContainer, delta: Vector2) -> bool:
	var moved := false
	var vb := sc.get_v_scroll_bar()
	if vb != null and _has_room(vb) and delta.y != 0.0:
		sc.scroll_vertical = int(round(float(sc.scroll_vertical) - delta.y))
		moved = true
	var hb := sc.get_h_scroll_bar()
	if hb != null and _has_room(hb) and delta.x != 0.0:
		sc.scroll_horizontal = int(round(float(sc.scroll_horizontal) - delta.x))
		moved = true
	return moved
