extends Control
## 结符页（2026-11-10）：进试炼前从七张元素符里点选四张，装满 Q/E/R/T 才能踏入。
##
## 为什么单独一页而不是塞进万界塔面板：
##   塔面板右侧已经被流派说明占满（`probe_rogue_family_layout` 有几何断言），
##   再塞四个符位会把「踏入试炼」按钮挤走。独立一页还能复用符卡的大卡面。
##
## ⚠ 只列 `TalismanDB.start_pool()` 的七张：冰 / 光 / 暗 是试炼内靠符方获得的，
##   开局不该出现（否则玩家会以为「选了就有」，实际局内还要再抽）。
## ⚠ 卡面走 ArtDB.talisman_style()：没有正式贴图的符会退回符纸底 + 名字，不报错。

signal confirmed(picks: Array)
signal cancelled

const VIEW_W := 1280.0
const VIEW_H := 720.0
const CARD_SCALE := 0.80
const CARD_STEP_X := 168.0
const CARD_STEP_Y := 238.0
const SLOT_KEYS: Array[String] = ["Q", "E", "R", "T"]

var _picked: Array[String] = []
var _cards: Dictionary = {}
var _badges: Dictionary = {}
var _badge_nums: Dictionary = {}
var _slot_labels: Array[Label] = []
var _bag_label: Label = null
var _hint: Label = null
var _confirm: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	offset_right = VIEW_W
	offset_bottom = VIEW_H
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.015, 0.03, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var root := PanelContainer.new()
	root.offset_left = 34.0
	root.offset_top = 24.0
	root.offset_right = VIEW_W - 34.0
	root.offset_bottom = VIEW_H - 24.0
	root.add_theme_stylebox_override("panel", UIKit.accent_card_style(
		Color(0.72, 0.58, 0.34), 0.68, 0.40, 10))
	add_child(root)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	root.add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	outer.add_child(head)
	head.add_child(_seal("符", Color(0.60, 0.17, 0.12)))
	head.add_child(UIKit.label("结符", UIKit.F_TITLE, UIKit.C_ACCENT))
	head.add_child(UIKit.label("七元灵符 · 点四张，装进 Q/E/R/T", UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.label("每放一张符，随机连携符囊里的另一张", 11, UIKit.C_TEXT_FAINT))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	# 左：七张符卡（两行错落）
	var field := Control.new()
	field.custom_minimum_size = Vector2(700.0, 520.0)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.clip_contents = true
	body.add_child(field)
	_build_cards(field)

	# 右：四个符位 + 说明 + 按钮
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300.0, 0.0)
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	right.add_child(UIKit.label("装入四槽", 13, UIKit.C_ACCENT))
	for i in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UIKit.label(SLOT_KEYS[i], UIKit.F_BADGE, UIKit.C_TEXT_DIM))
		var lab := UIKit.readable_label("— 空 —", 13, UIKit.C_TEXT_FAINT)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		right.add_child(row)
		_slot_labels.append(lab)
	_bag_label = UIKit.readable_label("符囊 0/2 · 局内用符方扩充，只参与连携", 11, UIKit.C_TEXT_DIM)
	right.add_child(_bag_label)
	_hint = UIKit.readable_label("", 11, UIKit.C_WARN)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_hint)
	right.add_child(UIKit.spacer())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right.add_child(buttons)
	var back := UIKit.button("返回", Vector2(96.0, 34.0))
	back.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(back)
	_confirm = UIKit.button("踏入试炼", Vector2(0.0, 34.0), "primary")
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)
	_refresh()


func _build_cards(field: Control) -> void:
	var pool := TalismanDB.start_pool()
	for i in pool.size():
		var base_id := String(pool[i])
		var style: Dictionary = ArtDB.talisman_style(base_id)
		var view = load("res://scripts/ui/talisman_card_view.gd").new()
		view.setup({
			"item_id": base_id,
			"title": TalismanDB.display_name(base_id),
			"card": String(style.get("card", "")),
			"accent": Color(style.get("color", Color(0.82, 0.76, 0.64))),
			"count": -1,
			"rot": [-4.0, 3.0, -2.0, 5.0, 3.5, -3.0, 2.0][i],
			"z": i,
		})
		var col := i % 4
		var row := 0 if i < 4 else 1
		# ⚠ 位置与缩放都要走 set_layout / base_scale：直接写 position / scale 会在
		#   第一次点选时被 _apply_pose 覆盖 —— 四张选中的卡会全叠到左上角。
		view.base_scale = Vector2(CARD_SCALE, CARD_SCALE)
		view.set_layout(Vector2(18.0 + float(col) * CARD_STEP_X, 12.0 + float(row) * CARD_STEP_Y),
			[-4.0, 3.0, -2.0, 5.0, 3.5, -3.0, 2.0][i], i)
		view.picked.connect(_on_card_picked)
		field.add_child(view)
		_cards[base_id] = view
		# 序号朱印：白字直接贴在符纸上会看不见（符纸本身就是米黄色），
		# 必须给一个实心朱底，否则等于没做。
		var badge := PanelContainer.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.62, 0.16, 0.12, 0.95)
		bsb.border_color = Color(0.90, 0.82, 0.62, 0.85)
		bsb.set_border_width_all(1)
		bsb.set_corner_radius_all(11)
		badge.add_theme_stylebox_override("panel", bsb)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -36.0
		badge.offset_top = 6.0
		badge.offset_right = -14.0
		badge.offset_bottom = 28.0
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.visible = false
		view.add_child(badge)
		var num := UIKit.label("", 13, Color(0.99, 0.95, 0.86))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(num)
		_badges[base_id] = badge
		_badge_nums[base_id] = num


func _on_card_picked(item_id: String) -> void:
	if _picked.has(item_id):
		_picked.erase(item_id)
	elif _picked.size() < 4:
		_picked.append(item_id)
	else:
		_hint.text = "四槽已满：再点已选的符可以取消"
		return
	_hint.text = ""
	_refresh()


func _refresh() -> void:
	for raw in _cards.keys():
		var base_id := String(raw)
		var view: Control = _cards[base_id]
		var idx := _picked.find(base_id)
		view.set_selected(idx >= 0)
		var badge: Control = _badges.get(base_id)
		if badge != null and is_instance_valid(badge):
			badge.visible = idx >= 0
			var num: Label = _badge_nums.get(base_id)
			if num != null and is_instance_valid(num):
				num.text = str(idx + 1)
	for i in 4:
		if i < _picked.size():
			_slot_labels[i].text = TalismanDB.display_name(_picked[i])
			_slot_labels[i].add_theme_color_override("font_color", UIKit.C_TEXT)
		else:
			_slot_labels[i].text = "— 空 —"
			_slot_labels[i].add_theme_color_override("font_color", UIKit.C_TEXT_FAINT)
	_bag_label.text = "符囊 0/%d · 局内用符方扩充，只参与连携" % TalismanDB.BAG_BASE
	_confirm.disabled = _picked.size() != 4


func _on_confirm() -> void:
	if _picked.size() != 4:
		return
	confirmed.emit(_picked.duplicate())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancelled.emit()


func _seal(text: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(34.0, 34.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.90, 0.82, 0.62, 0.85)
	panel.add_theme_stylebox_override("panel", sb)
	var lab := UIKit.label(text, 18, Color(0.98, 0.94, 0.86))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lab)
	return panel
