extends Control
## 符匣里的一张符：叠纸 + 撕边卡面 + 数量朱印 + 悬停抬卡。
## 位置 / 基础角度 / z 由符匣排版传入，本脚本只负责外观与交互。

signal picked(item_id: String)
signal hovered(item_id: String, inside: bool)

const CARD_W := 190.0
const CARD_H := 285.0
const STACK_PAD := 16.0
const PAPER_TEX := "res://assets/ui/panel/talisman_paper.png"
const EDGE_SHADER := "res://assets/shaders/talisman_card_edge.gdshader"
const INK_TEXT := Color(0.19, 0.12, 0.07)
const INK_DIM := Color(0.38, 0.29, 0.19)

var item_id := ""
var base_rot := 0.0
var base_z := 0
## ⚠ 排版缩放必须放这里，不能直接写 `view.scale`：选中/悬停会 tween `scale` 到 1.0，
##   外部写死的缩放会被 _apply_pose 覆盖掉（结符页 0.80 就是这么被吃掉的）。
var base_scale := Vector2.ONE
var _selected := false
var _hovered := false
var _base_pos := Vector2.ZERO
var _glow: TextureRect
var _border: Panel
var _tween: Tween


func setup(data: Dictionary) -> void:
	item_id = String(data.get("item_id", ""))
	base_rot = float(data.get("rot", 0.0))
	base_z = int(data.get("z", 0))
	size = Vector2(CARD_W + STACK_PAD, CARD_H + STACK_PAD)
	custom_minimum_size = size
	pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
	mouse_filter = Control.MOUSE_FILTER_STOP
	rotation_degrees = base_rot
	z_index = base_z
	_build(data)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _build(data: Dictionary) -> void:
	var accent: Color = data.get("accent", Color(0.80, 0.72, 0.52))
	var count := int(data.get("count", 0))
	var paper_tex: Texture2D = null
	if ResourceLoader.exists(PAPER_TEX):
		paper_tex = load(PAPER_TEX)

	_glow = UIKit.glow_node(Vector2(250.0, 350.0), accent, 0.0)
	_glow.position = Vector2(-30.0, -34.0)
	_glow.z_index = -10
	add_child(_glow)

	var shadow := ColorRect.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.38)
	shadow.position = Vector2(7.0, 9.0)
	shadow.size = Vector2(CARD_W, CARD_H)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.z_index = -2
	add_child(shadow)

	# 叠纸：按持有张数叠 0~4 层，越上面越靠近卡面
	var layers := clampi(count, 1, 4)
	for i in range(layers - 1, 0, -1):
		var sheet := TextureRect.new()
		sheet.texture = paper_tex
		sheet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sheet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		sheet.position = Vector2(4.0 * float(i), 5.0 * float(i))
		sheet.size = Vector2(CARD_W, CARD_H)
		sheet.rotation_degrees = float(i) * 1.4
		# 叠纸压成暗褐纸，不再在卡后露出一圈白边
		sheet.modulate = Color(0.34 - 0.025 * float(i), 0.27 - 0.020 * float(i),
			0.20 - 0.015 * float(i), 0.96)
		sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.z_index = -1 - i
		add_child(sheet)
		var edge := Panel.new()
		edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var esb := StyleBoxFlat.new()
		esb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		esb.border_color = Color(0.52, 0.18, 0.12, 0.55)
		esb.set_border_width_all(1)
		edge.add_theme_stylebox_override("panel", esb)
		sheet.add_child(edge)

	var art := TextureRect.new()
	var art_path := String(data.get("card", ""))
	if art_path == "" or not ResourceLoader.exists(art_path):
		art_path = String(data.get("icon", ""))
	if art_path != "" and ResourceLoader.exists(art_path):
		art.texture = load(art_path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.size = Vector2(CARD_W, CARD_H)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.z_index = 10
	if ResourceLoader.exists(EDGE_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(EDGE_SHADER)
		mat.set_shader_parameter("ragged", 0.020 + randf() * 0.010)
		mat.set_shader_parameter("seed", randf() * 100.0)
		mat.set_shader_parameter("edge_dark", 0.16)
		art.material = mat
	add_child(art)

	var name_panel := Panel.new()
	name_panel.position = Vector2(8.0, CARD_H - 42.0)
	name_panel.size = Vector2(CARD_W - 16.0, 26.0)
	name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_panel.z_index = 20
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(0.91, 0.85, 0.70, 0.88)
	nsb.border_color = Color(0.52, 0.30, 0.18, 0.35)
	nsb.set_border_width_all(1)
	nsb.set_corner_radius_all(2)
	name_panel.add_theme_stylebox_override("panel", nsb)
	add_child(name_panel)

	var name_lbl := UIKit.label(String(data.get("title", "符箓")), 11, INK_TEXT)
	name_lbl.position = Vector2(8.0, CARD_H - 41.0)
	name_lbl.size = Vector2(CARD_W - 16.0, 24.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIKit.soft_text_shadow(name_lbl, 0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.z_index = 21
	add_child(name_lbl)

	# count = -1 表示「这张卡不谈库存」（结符页选符时用）：不画右下角印，也不压暗卡面。
	# 否则七张卡全是「×1」，玩家会以为每种只有一张、换掉就没了。
	var show_count := count >= 0
	var seal := PanelContainer.new()
	seal.visible = show_count
	seal.position = Vector2(CARD_W - 54.0, CARD_H - 72.0)
	seal.size = Vector2(46.0, 25.0)
	seal.rotation_degrees = 5.0
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.z_index = 22
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.60, 0.16, 0.11, 0.94) if count > 0 else Color(0.35, 0.33, 0.30, 0.9)
	ssb.border_color = Color(0.94, 0.84, 0.64, 0.55)
	ssb.set_border_width_all(1)
	ssb.set_corner_radius_all(2)
	seal.add_theme_stylebox_override("panel", ssb)
	var seal_txt := UIKit.label("×%d" % count if count > 0 else "无", 10, Color(0.98, 0.92, 0.78))
	seal_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal_txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(seal_txt)
	add_child(seal)

	var quality := String(data.get("quality", ""))
	if quality != "":
		var qseal := PanelContainer.new()
		# 卡面左上角留了一枚空的「符胆」牌位（美术坐标 x≈82~120 / y≈110~187，
		# 换算到 190×285 卡片就是 x 24~36 / y 33~56，七张卡位同一处）。
		# 品阶印正好嵌进牌位中央，不再压着虚线边框和云纹。
		qseal.position = Vector2(24.0, 39.0)
		qseal.size = Vector2(12.0, 12.0)
		qseal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qseal.z_index = 22
		var qsb := StyleBoxFlat.new()
		qsb.bg_color = Color(0.58, 0.15, 0.10, 0.90)
		qsb.border_color = Color(0.94, 0.84, 0.64, 0.50)
		qsb.set_border_width_all(1)
		qsb.set_corner_radius_all(2)
		qseal.add_theme_stylebox_override("panel", qsb)
		var qt := UIKit.label(quality.substr(0, 1), 8, Color(0.98, 0.92, 0.78))
		qt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		qt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qseal.add_child(qt)
		add_child(qseal)

	_border = Panel.new()
	_border.position = Vector2(-2.0, -2.0)
	_border.size = Vector2(CARD_W + 4.0, CARD_H + 4.0)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.z_index = 24
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	bsb.border_color = Color(0.92, 0.72, 0.38, 0.0)
	bsb.set_border_width_all(2)
	bsb.set_corner_radius_all(3)
	_border.add_theme_stylebox_override("panel", bsb)
	add_child(_border)

	if count == 0:
		art.modulate.a = 0.48
		name_panel.modulate.a = 0.75


func set_layout(pos: Vector2, rot: float, z: int) -> void:
	_base_pos = pos
	base_rot = rot
	base_z = z
	if _selected or _hovered:
		_apply_pose(true)
	else:
		position = pos
		rotation_degrees = base_rot
		z_index = base_z
		scale = base_scale


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_apply_pose()


func _on_mouse_entered() -> void:
	_hovered = true
	hovered.emit(item_id, true)
	_apply_pose()


func _on_mouse_exited() -> void:
	_hovered = false
	hovered.emit(item_id, false)
	_apply_pose()


func _gui_input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	if tapped:
		GameState.play_ui("ui_tab")
		picked.emit(item_id)
		accept_event()


func _apply_pose(instant: bool = false) -> void:
	var lifted := _selected or _hovered
	var target_rot := 0.0 if lifted else base_rot
	var target_scale := Vector2.ONE
	var target_z := base_z
	var glow_alpha := 0.0
	var lift := 0.0
	if _selected:
		target_scale = Vector2(1.055, 1.055)
		target_z = 60
		glow_alpha = 0.50
		lift = -10.0
	elif _hovered:
		target_scale = Vector2(1.035, 1.035)
		target_z = 50
		glow_alpha = 0.28
		lift = -4.0
	target_scale *= base_scale
	var target_pos := _base_pos + Vector2(0.0, lift)
	z_index = target_z
	var bsb := _border.get_theme_stylebox("panel") as StyleBoxFlat
	if bsb != null:
		bsb.border_color = Color(0.92, 0.72, 0.38, 0.86 if _selected else 0.0)
	if _border != null:
		_border.visible = _selected
	if instant:
		position = target_pos
		rotation_degrees = target_rot
		scale = target_scale
		if _glow != null:
			_glow.modulate.a = glow_alpha
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position", target_pos, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation_degrees", target_rot, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", target_scale, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_glow, "modulate:a", glow_alpha, 0.16)
