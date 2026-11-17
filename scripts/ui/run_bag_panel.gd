class_name RunBagPanel
extends CanvasLayer
## 苍澜大陆·局内背包（用户 2026-10-23 定）
##
## 只装**本次副本**里捡到的东西（药材 / 兽皮），不写存档：
##   - 死亡：管理器直接清空数据 → 本次收获全部散失
##   - 从入口传送门撤离：管理器把数据并入永久背包 → 成功带出
##
## 交互：
##   - B / ESC 开关（打开时暂停场景，避免一边翻包一边挨打）
##   - 把物品拖到面板外松手 = 丢弃：面板回调管理器，在玩家脚下生成地面掉落物
##     （不是凭空消失 —— 丢错了还能走回去捡）
##
## 数据由管理器持有（items 数组），本面板只做展示与拖拽，避免两处各存一份。

const VIEW_W := 1280.0
const VIEW_H := 720.0
const PANEL_SIZE := Vector2(640.0, 470.0)
const GRID_COLS := 6
const MIN_SLOTS := 24
const SLOT_SIZE := Vector2(66.0, 66.0)
const SLOT_GAP := 6.0

## 管理器注入：本次副本的物品（id / name / type / count / icon / desc）
var items: Array = []
var capacity: int = 60
## 丢弃回调：参数是 item，由管理器负责生成地面掉落物
var drop_handler: Callable = Callable()

var _visible := false
var _root: PanelContainer
var _grid: GridContainer
var _count_label: Label
var _empty_hint: Label
var _drag_index := -1
var _drag_preview: Control
## 是不是本面板暂停了场景：只有自己暂停的才自己恢复，
## 避免设置面板开着时误按 B，关包顺带把游戏解除暂停
var _paused_tree := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 95
	_build()
	_set_visible(false)


func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_B or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_bag()
			return
	# 拖拽追踪：按下在槽位上（gui_input），移动与松开在这里统一处理
	if _drag_index < 0:
		return
	if event is InputEventMouseMotion:
		_follow_drag((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_finish_drag(mb.position)


# ===================== 开关 =====================

func toggle_bag() -> void:
	if _visible:
		close_bag()
	else:
		open_bag()


func open_bag() -> void:
	if _visible:
		return
	# 已有别的面板在暂停（设置 / 系统面板）→ 不开，否则层叠 + 关闭时误解暂停
	if get_tree().paused:
		return
	_visible = true
	GameState.play_ui("ui_open")
	refresh()
	_set_visible(true)
	get_tree().paused = true
	_paused_tree = true


func close_bag() -> void:
	if not _visible:
		return
	_visible = false
	_cancel_drag()
	GameState.play_ui("ui_close")
	_set_visible(false)
	if _paused_tree:
		get_tree().paused = false
		_paused_tree = false


func is_open() -> bool:
	return _visible


func _set_visible(v: bool) -> void:
	for c in get_children():
		if c is ColorRect or c is PanelContainer:
			var ci := c as CanvasItem
			ci.visible = v
	# 拖拽预览永远跟着状态走
	if not v:
		_cancel_drag()


# ===================== 构建 =====================

func _build() -> void:
	add_child(UIKit.dim_rect())

	_root = PanelContainer.new()
	_root.add_theme_stylebox_override("panel", UIKit.panel_style())
	add_child(_root)
	UIKit.apply_panel_frame(_root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UIKit.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_right", UIKit.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_root.add_child(margin)

	var vbox := UIKit.vbox(8)
	margin.add_child(vbox)

	var accent: Color = UIKit.facility_style("herb_garden").get("accent", UIKit.C_ACCENT)
	var header := UIKit.hbox(10)
	vbox.add_child(header)
	header.add_child(UIKit.facility_disc({"accent": accent, "glyph": "囊"}, 30))
	var title := UIKit.label("局内背包", 19, Color(0.97, 0.93, 0.84))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	_count_label = UIKit.label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_count_label)
	header.add_child(UIKit.spacer())
	header.add_child(UIKit.label("拖出面板松手 = 丢在地上 · B 关闭", UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	var close_btn := UIKit.button("关闭", Vector2(72, 30))
	close_btn.pressed.connect(close_bag)
	header.add_child(close_btn)

	vbox.add_child(UIKit.note_card(
		"只存放本次苍澜大陆所得：死亡会全部散失，走回入口传送门撤离才带回原初位面。", accent))

	_empty_hint = UIKit.label("（空空如也 —— 去采集药材、猎杀灵兽吧）", UIKit.F_SMALL, UIKit.C_DISABLE)
	vbox.add_child(_empty_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", int(SLOT_GAP))
	_grid.add_theme_constant_override("v_separation", int(SLOT_GAP))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	call_deferred("_apply_size")


func _apply_size() -> void:
	_root.position = Vector2((VIEW_W - PANEL_SIZE.x) * 0.5, (VIEW_H - PANEL_SIZE.y) * 0.5)
	_root.size = PANEL_SIZE


# ===================== 刷新 =====================

func refresh() -> void:
	if _grid == null:
		return
	UIKit.clear_children(_grid)
	_count_label.text = "局内物品 %d / %d" % [items.size(), capacity]
	_empty_hint.visible = items.is_empty()
	var slot_count := maxi(MIN_SLOTS, items.size())
	for i in slot_count:
		_grid.add_child(_make_slot(i))


func _make_slot(index: int) -> Control:
	var filled := index < items.size()
	var item: Dictionary = items[index] if filled else {}
	var box := PanelContainer.new()
	box.custom_minimum_size = SLOT_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_theme_stylebox_override("panel", UIKit.slot_style(
		filled,
		ItemDB.item_border_color(item) if filled else UIKit.C_SLOT_BORDER,
		2 if filled else 1))
	if not filled:
		return box

	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stack)

	var icon_type := "material"
	if String(item.get("type", "")) == CharacterData.ITEM_EQUIPMENT:
		icon_type = "treasure" if String(item.get("equipment_type", "")) == "treasure" else "equipment"
	var icon := UIKit.icon_node(
		String(item.get("icon", "")),
		String(item.get("name", "")),
		icon_type,
		Vector2(44.0, 44.0))
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)

	var count := int(item.get("count", 1))
	if count > 1:
		var cnt := UIKit.label("×%d" % count, UIKit.F_BADGE, UIKit.C_TEXT)
		cnt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt.offset_left = -44.0
		cnt.offset_top = -18.0
		cnt.offset_right = -4.0
		cnt.offset_bottom = -2.0
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(cnt)

	var realm := ItemDB.item_realm(item)
	var realm_line := ("境界：%s\n" % realm) if realm != "" else ""
	box.tooltip_text = "%s ×%d\n%s%s\n拖到面板外松手 = 丢在地上" % [
		String(item.get("name", "")), count, realm_line, String(item.get("desc", "")),
	]
	box.gui_input.connect(_on_slot_gui_input.bind(index))
	return box


# ===================== 拖拽丢弃 =====================

func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if index >= items.size() or _drag_index >= 0:
		return
	_begin_drag(index, get_viewport().get_mouse_position())
	get_viewport().set_input_as_handled()


func _begin_drag(index: int, mouse_pos: Vector2) -> void:
	_drag_index = index
	_drag_preview = _make_drag_preview(items[index])
	add_child(_drag_preview)
	_drag_preview.size = Vector2(160.0, 36.0)
	_drag_preview.position = mouse_pos - _drag_preview.size * 0.5


func _follow_drag(mouse_pos: Vector2) -> void:
	if _drag_preview == null or not is_instance_valid(_drag_preview):
		return
	_drag_preview.position = mouse_pos - _drag_preview.size * 0.5


func _finish_drag(mouse_pos: Vector2) -> void:
	var idx := _drag_index
	_cancel_drag()
	if idx < 0 or idx >= items.size():
		return
	# 松手在面板内 = 取消；面板外 = 丢弃
	if _root != null and _root.get_global_rect().has_point(mouse_pos):
		return
	var item: Dictionary = items[idx]
	items.remove_at(idx)
	GameState.play_ui("pickup")
	if drop_handler.is_valid():
		drop_handler.call(item)
	refresh()


func _cancel_drag() -> void:
	_drag_index = -1
	if _drag_preview != null and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
	_drag_preview = null


func _make_drag_preview(item: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.slot_style(true, ItemDB.item_border_color(item), 2))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var icon := UIKit.icon_node(
		String(item.get("icon", "")),
		String(item.get("name", "")),
		"material",
		Vector2(26.0, 26.0))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var l := UIKit.label("%s ×%d" % [String(item.get("name", "")), int(item.get("count", 1))],
		UIKit.F_SMALL, UIKit.C_TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return box
