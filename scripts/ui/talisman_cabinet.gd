extends Control
## A 符匣全屏页（2026-10-31）：七元素符大卡陈列（旧烈火 / 磐石已下架）。
## 新 7 张用顶部品阶切换练气/筑基/结丹/元婴；点卡选中，右侧详情，按钮装进 Q/E/R/T。

signal assigned(slot_index: int)
signal closed

const TalismanCardViewScript = preload("res://scripts/ui/talisman_card_view.gd")
const VIEW_W := 1280.0
const VIEW_H := 720.0
const QUALITY_LABELS := ["练气", "筑基", "结丹", "元婴"]
## 七张符在左半区的错落落点（相对 field 尺寸），后三张压在前四张的下沿
const CARD_LAYOUT := [
	{"x": 0.02, "y": 0.01, "rot": -5.0},
	{"x": 0.25, "y": 0.00, "rot": 3.0},
	{"x": 0.48, "y": 0.04, "rot": -2.5},
	{"x": 0.71, "y": 0.015, "rot": 6.0},
	{"x": 0.13, "y": 0.43, "rot": 4.5},
	{"x": 0.36, "y": 0.46, "rot": -4.0},
	{"x": 0.59, "y": 0.41, "rot": 2.0},
]
const INK_TEXT := Color(0.19, 0.12, 0.07)
const INK_DIM := Color(0.38, 0.29, 0.19)
const INK_OK := Color(0.17, 0.46, 0.20)
const INK_WARN := Color(0.60, 0.24, 0.10)
const INK_DANGER := Color(0.55, 0.12, 0.08)
## 元素配色统一在 ArtDB.ELEMENT_COLORS（符匣 / 结符页 / 符阵 / 符灵同一份），
## 本文件不再自留一份，免得改色时漏掉一处。
const ELEMENT_GLYPHS := {
	"metal": "金", "wood": "木", "water": "水", "fire": "火",
	"earth": "土", "wind": "风", "thunder": "雷",
}

var target_slot: int = -1
## 从制符台打开时透出符案舞台底图；从功法库打开时用暗底
var use_stage_bg := false
var _quality := 0
var _selected_id := ""
var _field: Control
var _detail_panel: Control
var _detail_name: Label
var _detail_effect: Label
var _detail_meta: Label
var _craft_cost_label: Label
var _craft_result: Label
var _craft_row: HBoxContainer
var _assign_row: HBoxContainer
var _quality_row: HBoxContainer = null
var _card_views: Array = []
var _brush_layer: Control = null
var _brush_canvas: TalismanCanvas = null
var _brush_recipe: Dictionary = {}
var _brush_batch: int = 1
var _brush_qty_row: HBoxContainer = null
var _brush_cost_label: Label = null
var _brush_exp_label: Label = null
var _brush_rate_label: Label = null
var _brush_stack_label: Label = null
var _brush_result_box: VBoxContainer = null
var _brush_result_label: Label = null
var _brush_result_detail: Label = null
var _brush_actions: HBoxContainer = null
var _brush_stamp: Label = null
var _brush_stage_count: Label = null
var _brush_cancel: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	offset_right = VIEW_W
	offset_bottom = VIEW_H
	_build()
	_refresh_cards()


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/talisman/stage_desk.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(1, 1, 1, 1.0 if use_stage_bg else 0.42)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.015, 0.03, 0.58 if use_stage_bg else 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# 可用视口尺寸由父面板的 VIEW 常量决定；这里用固定 1280×720 的绝对布局
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
	head.add_child(_make_seal("符", Color(0.60, 0.17, 0.12), 34))
	head.add_child(UIKit.label("符匣", UIKit.F_TITLE, UIKit.C_ACCENT))
	head.add_child(UIKit.label("七元素符 · 点一张，走笔或装 Q/E/R/T",
		UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.label("品阶", 10, UIKit.C_TEXT_DIM))
	_quality_row = UIKit.hbox(4)
	head.add_child(_quality_row)
	_refresh_quality_buttons()
	var close := UIKit.quiet_button("收匣", Vector2(56, 26), UIKit.C_TEXT_DIM)
	UIKit.set_readable_font(close, 11)
	close.pressed.connect(_close)
	head.add_child(close)
	_add_brush_divider(outer)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	outer.add_child(body)

	# 左：散落的符纸案。错位 + 旋转 + 叠纸，不再是等距方格
	var field_wrap := Control.new()
	field_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_wrap.clip_contents = true
	field_wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(field_wrap)
	var wash := UIKit.glow_node(Vector2(780.0, 560.0), Color(0.72, 0.56, 0.30), 0.10)
	wash.position = Vector2(-40.0, -20.0)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_wrap.add_child(wash)
	var thread := TextureRect.new()
	thread.texture = UIKit.ui_texture(UIKit.TEX_BRUSH_LINE)
	thread.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thread.stretch_mode = TextureRect.STRETCH_SCALE
	thread.position = Vector2(-30.0, 260.0)
	thread.size = Vector2(820.0, 30.0)
	thread.rotation_degrees = -14.0
	thread.modulate = Color(0.56, 0.14, 0.10, 0.20)
	thread.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_wrap.add_child(thread)
	_field = Control.new()
	_field.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.mouse_filter = Control.MOUSE_FILTER_PASS
	field_wrap.add_child(_field)
	_field.resized.connect(_layout_card_views)

	# 右：一张斜放的撕边纸笺，不是又一块深色面板
	_detail_panel = Control.new()
	_detail_panel.custom_minimum_size = Vector2(302, 0)
	# 新手指引锚点：右侧纸笺里的「装 Q/E/R/T」才是把符装上键位的地方
	# （c4_load 原来指着战斗里 Q 槽的旧锚点，界面关了以后会在别处飘着）
	_detail_panel.set_meta("tut", "talisman.assign")
	_detail_panel.rotation_degrees = -1.2
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(_detail_panel)

	var paper_shadow := ColorRect.new()
	paper_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper_shadow.offset_left = 6.0
	paper_shadow.offset_top = 8.0
	paper_shadow.offset_right = -2.0
	paper_shadow.offset_bottom = -2.0
	paper_shadow.color = Color(0.0, 0.0, 0.0, 0.26)
	paper_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(paper_shadow)

	var paper_bg := TextureRect.new()
	paper_bg.texture = load(UIKit.TEX_TALISMAN_PAPER)
	paper_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	paper_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/shaders/talisman_card_edge.gdshader"):
		var pmat := ShaderMaterial.new()
		pmat.shader = load("res://assets/shaders/talisman_card_edge.gdshader")
		pmat.set_shader_parameter("ragged", 0.012)
		pmat.set_shader_parameter("seed", 31.7)
		pmat.set_shader_parameter("edge_dark", 0.0)
		paper_bg.material = pmat
	_detail_panel.add_child(paper_bg)

	var wm_holder := Control.new()
	wm_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wm_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(wm_holder)
	var wm := UIKit.label("符", 128, Color(0.55, 0.14, 0.09, 0.075))
	wm.anchor_left = 1.0
	wm.anchor_top = 1.0
	wm.anchor_right = 1.0
	wm.anchor_bottom = 1.0
	wm.offset_left = -168.0
	wm.offset_top = -188.0
	wm.offset_right = -8.0
	wm.offset_bottom = -8.0
	wm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wm.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wm_holder.add_child(wm)

	# 纸笺顶部一枚木夹 + 红线，像真的夹在符案上
	var pin := ColorRect.new()
	pin.color = Color(0.20, 0.13, 0.08, 0.88)
	pin.anchor_left = 0.5
	pin.anchor_right = 0.5
	pin.offset_left = -27.0
	pin.offset_right = 27.0
	pin.offset_top = 0.0
	pin.offset_bottom = 7.0
	pin.rotation_degrees = -2.0
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(pin)
	var cord := ColorRect.new()
	cord.color = Color(0.58, 0.15, 0.10, 0.82)
	cord.anchor_left = 0.5
	cord.anchor_right = 0.5
	cord.offset_left = -1.0
	cord.offset_right = 1.0
	cord.offset_top = -14.0
	cord.offset_bottom = 2.0
	cord.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(cord)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_panel.add_child(margin)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 7)
	margin.add_child(dv)

	var dtitle := UIKit.hbox(8)
	_detail_name = UIKit.label("选一张符", 20, INK_TEXT)
	dtitle.add_child(_detail_name)
	dtitle.add_child(UIKit.spacer())
	dtitle.add_child(_make_seal("录", Color(0.60, 0.17, 0.12), 28))
	dv.add_child(dtitle)
	_detail_meta = UIKit.label("", UIKit.F_SMALL, INK_DIM)
	dv.add_child(_detail_meta)
	var ink_line := TextureRect.new()
	ink_line.texture = UIKit.ui_texture(UIKit.TEX_BRUSH_LINE)
	ink_line.custom_minimum_size = Vector2(0, 8)
	ink_line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ink_line.stretch_mode = TextureRect.STRETCH_SCALE
	ink_line.modulate = Color(0.42, 0.16, 0.10, 0.38)
	ink_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dv.add_child(ink_line)
	_detail_effect = UIKit.readable_label("", 12, INK_TEXT)
	_detail_effect.custom_minimum_size = Vector2(252, 150)
	_detail_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_detail_effect)
	var cost_row := UIKit.hbox(7)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(_make_seal("耗", Color(0.60, 0.17, 0.12), 22))
	_craft_cost_label = UIKit.readable_label("", 11, INK_DIM)
	_craft_cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_row.add_child(_craft_cost_label)
	dv.add_child(cost_row)
	_craft_result = UIKit.readable_label("", 11, INK_OK)
	_craft_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_craft_result)
	dv.add_child(UIKit.spacer())
	_craft_row = HBoxContainer.new()
	_craft_row.add_theme_constant_override("separation", 4)
	dv.add_child(_craft_row)
	_assign_row = HBoxContainer.new()
	_assign_row.add_theme_constant_override("separation", 4)
	dv.add_child(_assign_row)
	var foot := UIKit.label("符匣 · 七元素", 9, Color(0.42, 0.32, 0.21, 0.72))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dv.add_child(foot)


func _set_quality(index: int) -> void:
	_quality = clampi(index, 0, QUALITY_LABELS.size() - 1)
	_selected_id = ""
	_detail_name.text = "选一张符"
	_detail_meta.text = ""
	_detail_effect.text = ""
	_craft_cost_label.text = ""
	_craft_result.text = ""
	for c in _craft_row.get_children():
		c.queue_free()
	for c in _assign_row.get_children():
		c.queue_free()
	_refresh_cards()


func _close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _brush_layer != null and is_instance_valid(_brush_layer):
			_close_brush()
		else:
			_close()


func _refresh_quality_buttons() -> void:
	if _quality_row == null:
		return
	UIKit.clear_children(_quality_row)
	var tilts := [-2.0, 0.0, 2.0]
	for i in QUALITY_LABELS.size():
		var btn: Button = UIKit.paper_button(QUALITY_LABELS[i], Vector2(64, 26)) \
			if i == _quality else UIKit.quiet_button(QUALITY_LABELS[i], Vector2(58, 26),
				UIKit.C_TEXT_DIM)
		UIKit.set_readable_font(btn, 10)
		btn.rotation_degrees = tilts[i % tilts.size()]
		btn.pressed.connect(_set_quality.bind(i))
		_quality_row.add_child(btn)


func _refresh_cards() -> void:
	for v in _card_views:
		if is_instance_valid(v):
			v.queue_free()
	_card_views.clear()
	_refresh_quality_buttons()
	for i in range(ItemDB.ELEMENT_TALISMAN_BASES.size()):
		var b: Dictionary = ItemDB.ELEMENT_TALISMAN_BASES[i]
		var item_id := ItemDB.element_talisman_item_id(String(b.get("base_id", "")), _quality)
		var def := ItemDB.get_consumable(item_id)
		if def.is_empty():
			continue
		var view = TalismanCardViewScript.new()
		_field.add_child(view)
		view.setup({
			"item_id": item_id,
			"title": String(def.get("talisman_name", "")),
			"quality": QUALITY_LABELS[_quality],
			"card": String(def.get("card", "")),
			"icon": String(def.get("icon", "")),
			"accent": ArtDB.element_color(String(b.get("element", ""))),
			"count": CharacterData.talisman_count(item_id),
		})
		view.picked.connect(_select)
		_card_views.append(view)
	_layout_card_views()
	if _selected_id != "":
		_select(_selected_id)


func _layout_card_views() -> void:
	if _field == null or _field.size.x < 10.0:
		return
	for i in range(_card_views.size()):
		var view = _card_views[i]
		if not is_instance_valid(view):
			continue
		var cfg: Dictionary = CARD_LAYOUT[i % CARD_LAYOUT.size()]
		var pos := Vector2(float(cfg.get("x", 0.0)) * _field.size.x,
			float(cfg.get("y", 0.0)) * _field.size.y)
		view.set_layout(pos, float(cfg.get("rot", 0.0)), i)
	if _detail_panel != null:
		_detail_panel.pivot_offset = _detail_panel.size * 0.5


func _select(item_id: String) -> void:
	_selected_id = item_id
	_craft_result.text = ""
	_craft_result.add_theme_color_override("font_color", INK_OK)
	_craft_cost_label.text = ""
	_craft_cost_label.add_theme_color_override("font_color", INK_DIM)
	for v in _card_views:
		if is_instance_valid(v):
			v.set_selected(String(v.item_id) == item_id)
	var def := ItemDB.get_consumable(item_id)
	if def.is_empty():
		return
	var eff: Dictionary = def.get("battle_effect", {})
	_detail_name.text = String(def.get("talisman_name", "符箓"))
	_detail_meta.text = "%s · %s · 持有 %d · 消耗 5 灵力" % [
		String(def.get("realm", "")), String(def.get("talisman_type", "")),
		CharacterData.talisman_count(item_id)]
	_detail_effect.text = _detail_text(def, eff)
	for c in _craft_row.get_children():
		c.queue_free()
	for c in _assign_row.get_children():
		c.queue_free()
	var recipe := _recipe_for_item(item_id)
	if not recipe.is_empty():
		var rate := ItemDB.talisman_success_rate(String(recipe.get("realm", "")))
		var cost := ItemDB.talisman_cultivation_cost(recipe)
		var mats: Dictionary = recipe.get("materials", {})
		var known := bool(recipe.get("uses_realm_success", false)) \
			or CharacterData.is_recipe_known("talisman", String(recipe.get("recipe_id", "")))
		var can_craft := known and rate > 0.0 and CharacterData.realm_exp >= cost \
			and CharacterData.has_materials(mats)
		var cost_int := int(cost)
		var rate_int := int(round(rate * 100.0))
		var btn_text := "走笔制符 · 需修为 %d" % cost_int
		var cost_text := "修为：%d / 张 · 现有 %d\n材料：%s\n成功率：%d%%" % [
			cost_int, int(CharacterData.realm_exp), _materials_owned_text(mats), rate_int]
		var cost_color := INK_DIM
		if rate <= 0.0:
			cost_text = "越两级，无法制作"
			cost_color = INK_DANGER
		else:
			var lack: Array[String] = []
			if CharacterData.realm_exp < cost:
				lack.append("修为")
			if not CharacterData.has_materials(mats):
				lack.append("材料")
			if not lack.is_empty():
				cost_text += "　·　%s不足" % "与".join(lack)
				cost_color = INK_DANGER
		_craft_cost_label.text = cost_text
		_craft_cost_label.add_theme_color_override("font_color", cost_color)
		var craft_btn := UIKit.primary_button(btn_text, Vector2(0, 32))
		craft_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.set_readable_font(craft_btn, 10)
		craft_btn.disabled = not can_craft
		craft_btn.tooltip_text = "%s\n材料：%s\n修为：%d / 张 · 现有 %d\n成功率：%d%%（同级 100%%，越一级 5%%，越两级不可做）\n逐张判定" % [
			String(def.get("desc", "")), _materials_owned_text(mats), int(cost),
			int(CharacterData.realm_exp), int(round(rate * 100.0))]
		craft_btn.pressed.connect(_open_brush.bind(recipe))
		_craft_row.add_child(craft_btn)
		# InkButton 会在入树时重刷皮肤，颜色必须在入树后的下一帧再覆盖一次
		craft_btn.add_theme_color_override("font_color", Color(1.0, 0.93, 0.80))
		craft_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.90))
		craft_btn.call_deferred("add_theme_color_override", "font_color",
			Color(1.0, 0.93, 0.80))
		craft_btn.call_deferred("add_theme_color_override", "font_hover_color",
			Color(1.0, 0.98, 0.90))
	var choices: Array = [target_slot] if target_slot >= 0 else [0, 1, 2, 3]
	for slot_index in choices:
		var btn := UIKit.paper_button("装 %s" % ["Q", "E", "R", "T"][slot_index],
			Vector2(54, 28), INK_TEXT)
		UIKit.set_readable_font(btn, 10)
		btn.disabled = CharacterData.talisman_count(item_id) <= 0
		btn.pressed.connect(_assign.bind(item_id, slot_index))
		_assign_row.add_child(btn)


func _recipe_for_item(item_id: String) -> Dictionary:
	for raw in ItemDB.all_talisman_recipes():
		var r: Dictionary = raw
		if String(r.get("talisman_id", "")) == item_id:
			return r
	return {}


func _materials_owned_text(materials: Dictionary) -> String:
	var parts: Array[String] = []
	for k in materials.keys():
		parts.append("%s ×%d（现有 %d）" % [
			ItemDB.get_material_name(String(k)), int(materials[k]),
			CharacterData.count_item(String(k)),
		])
	return "、".join(parts) if not parts.is_empty() else "无"


## 走笔量上限：材料与修为都按张消耗，取两边能支撑的最大张数
func _max_batch_for(recipe: Dictionary) -> int:
	if recipe.is_empty():
		return 0
	if ItemDB.talisman_success_rate(String(recipe.get("realm", ""))) <= 0.0:
		return 0
	var max_n := 999
	var mats: Dictionary = recipe.get("materials", {})
	for k in mats.keys():
		var need := int(mats[k])
		if need <= 0:
			continue
		max_n = mini(max_n, CharacterData.count_item(String(k)) / need)
	var cost := int(ItemDB.talisman_cultivation_cost(recipe))
	if cost > 0:
		max_n = mini(max_n, int(CharacterData.realm_exp) / cost)
	return maxi(max_n, 0)


func _add_brush_divider(parent: Control) -> void:
	var d := TextureRect.new()
	d.texture = UIKit.ui_texture(UIKit.TEX_BRUSH_LINE)
	d.custom_minimum_size = Vector2(0, 3)
	d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	d.stretch_mode = TextureRect.STRETCH_SCALE
	d.modulate = Color(0.92, 0.78, 0.45, 0.55)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(d)


func _make_seal(text: String, color: Color, side: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(side, side)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color(0.95, 0.82, 0.55, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	var l := UIKit.label(text, int(side * 0.52), Color(0.98, 0.93, 0.82))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## 所有符都先走笔：符路描满后才按境界成功率逐张结算；墨尽 = 不制作、不扣料。
func _open_brush(recipe: Dictionary) -> void:
	_close_brush()
	_brush_recipe = recipe.duplicate(true)
	_brush_batch = 1
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 200
	add_child(layer)
	_brush_layer = layer

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.02, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.offset_left = 190.0
	panel.offset_top = 46.0
	panel.offset_right = 1090.0
	panel.offset_bottom = 674.0
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", UIKit.accent_card_style(
		Color(0.86, 0.67, 0.31), 0.97, 0.82, 12))
	layer.add_child(panel)

	var desk := TextureRect.new()
	desk.texture = load("res://assets/ui/talisman/stage_desk.png")
	desk.set_anchors_preset(Control.PRESET_FULL_RECT)
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	desk.modulate = Color(0.62, 0.55, 0.45, 0.26)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(desk)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)

	var head := UIKit.hbox(10)
	head.add_child(_make_seal("制", Color(0.60, 0.17, 0.12), 42))
	var htxt := VBoxContainer.new()
	htxt.add_theme_constant_override("separation", 0)
	htxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	htxt.add_child(UIKit.label("走笔制符", 22, UIKit.C_ACCENT))
	htxt.add_child(UIKit.label("%s · 按住左键沿金色符路描满" % String(recipe.get("talisman_name", "符箓")),
		11, UIKit.C_TEXT_DIM))
	head.add_child(htxt)
	head.add_child(UIKit.spacer())
	var rate := ItemDB.talisman_success_rate(String(recipe.get("realm", "")))
	var rate_col := UIKit.C_OK if rate >= 1.0 else (UIKit.C_WARN if rate > 0.0 else UIKit.C_DANGER)
	head.add_child(UIKit.chip("成功率 %d%%" % int(round(rate * 100.0)), rate_col))
	box.add_child(head)
	_add_brush_divider(box)

	var info := UIKit.hbox(8)
	info.add_child(UIKit.label("制符数量", 11, UIKit.C_TEXT_DIM))
	_brush_qty_row = UIKit.hbox(4)
	info.add_child(_brush_qty_row)
	info.add_child(UIKit.spacer())
	_brush_stack_label = UIKit.label("", 11, UIKit.C_ACCENT)
	info.add_child(_brush_stack_label)
	box.add_child(info)

	var cost_row := UIKit.hbox(10)
	_brush_cost_label = UIKit.readable_label("", 11, UIKit.C_TEXT_DIM)
	_brush_cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_row.add_child(_brush_cost_label)
	_brush_exp_label = UIKit.readable_label("", 12, UIKit.C_ACCENT)
	cost_row.add_child(_brush_exp_label)
	_brush_rate_label = UIKit.readable_label("", 10, UIKit.C_TEXT_DIM)
	cost_row.add_child(_brush_rate_label)
	box.add_child(cost_row)

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 300)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	box.add_child(stage)
	var canvas := TalismanCanvas.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.set_strokes(TalismanPatterns.for_item(String(recipe.get("talisman_id", ""))))
	stage.add_child(canvas)
	_brush_stage_count = UIKit.outlined_label("", 18, UIKit.C_ACCENT, 4)
	_brush_stage_count.position = Vector2(14, 10)
	_brush_stage_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_brush_stage_count)
	var tip := UIKit.label("沿金线描满 · 墨尽即废", 10, Color(0.88, 0.80, 0.64, 0.75))
	tip.anchor_left = 1.0
	tip.anchor_right = 1.0
	tip.offset_left = -240.0
	tip.offset_right = -14.0
	tip.offset_top = 10.0
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(tip)
	_brush_stamp = UIKit.outlined_label("", 76, UIKit.C_OK, 10)
	_brush_stamp.set_anchors_preset(Control.PRESET_CENTER)
	_brush_stamp.offset_left = -120.0
	_brush_stamp.offset_right = 120.0
	_brush_stamp.offset_top = -62.0
	_brush_stamp.offset_bottom = 62.0
	_brush_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brush_stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_brush_stamp.rotation_degrees = -10.0
	_brush_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brush_stamp.visible = false
	stage.add_child(_brush_stamp)

	_brush_result_box = VBoxContainer.new()
	_brush_result_box.add_theme_constant_override("separation", 1)
	_brush_result_box.visible = false
	_brush_result_label = UIKit.readable_label("", 14, UIKit.C_OK)
	_brush_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brush_result_box.add_child(_brush_result_label)
	_brush_result_detail = UIKit.label("", 10, UIKit.C_TEXT_DIM)
	_brush_result_box.add_child(_brush_result_detail)
	box.add_child(_brush_result_box)

	var foot := UIKit.hbox(8)
	_brush_cancel = UIKit.quiet_button("放下笔（不制作）", Vector2(158, 28), UIKit.C_TEXT_DIM)
	UIKit.set_readable_font(_brush_cancel, 10)
	_brush_cancel.pressed.connect(_exit_brush)
	foot.add_child(_brush_cancel)
	foot.add_child(UIKit.spacer())
	_brush_actions = UIKit.hbox(8)
	_brush_actions.visible = false
	foot.add_child(_brush_actions)
	box.add_child(foot)

	_brush_canvas = canvas
	canvas.completed.connect(_finish_brush)
	canvas.ink_empty.connect(_on_brush_empty)
	_refresh_brush_info()
	await get_tree().process_frame
	canvas.activate()


func _qty_chip(n: int, text: String, selected: bool) -> Button:
	var b: Button = UIKit.paper_button(text, Vector2(56, 24)) if selected \
		else UIKit.quiet_button(text, Vector2(56, 24), UIKit.C_ACCENT)
	UIKit.set_readable_font(b, 10)
	b.pressed.connect(_set_brush_batch.bind(n))
	return b


func _refresh_brush_info() -> void:
	if _brush_recipe.is_empty() or _brush_qty_row == null:
		return
	var recipe := _brush_recipe
	var max_n := _max_batch_for(recipe)
	_brush_batch = 0 if max_n <= 0 else clampi(_brush_batch, 1, max_n)
	UIKit.clear_children(_brush_qty_row)
	var opts: Array = []
	for v in [1, 5, 10]:
		if int(v) <= max_n:
			opts.append(int(v))
	if max_n <= 0:
		var none := UIKit.label("材料或修为不足", 10, UIKit.C_DANGER)
		_brush_qty_row.add_child(none)
	else:
		for v in opts:
			_brush_qty_row.add_child(_qty_chip(int(v), "×%d" % int(v), _brush_batch == int(v)))
		if not opts.has(max_n):
			_brush_qty_row.add_child(_qty_chip(max_n, "全部", _brush_batch == max_n))
	_brush_stack_label.text = "本次 ×%d" % _brush_batch if _brush_batch > 0 else ""
	_brush_stage_count.text = "×%d" % maxi(_brush_batch, 1)

	var n := maxi(_brush_batch, 0)
	var mats: Dictionary = recipe.get("materials", {})
	var scaled := {}
	for k in mats.keys():
		scaled[String(k)] = int(mats[k]) * n
	var per_cost := int(ItemDB.talisman_cultivation_cost(recipe))
	var cost := per_cost * n
	if n <= 0:
		_brush_cost_label.text = "耗材：—"
		_brush_exp_label.text = "修为 —"
	else:
		_brush_cost_label.text = "耗材：%s" % _materials_owned_text(scaled)
		_brush_exp_label.text = "修为 %d（每张 %d）· 现有 %d" % [
			cost, per_cost, int(CharacterData.realm_exp)]
	var rate := ItemDB.talisman_success_rate(String(recipe.get("realm", "")))
	var tail := "每张必成" if rate >= 1.0 else ("逐张判定" if n <= 1
		else "逐张判定 · 期望成 %.1f 张" % (float(n) * rate))
	_brush_rate_label.text = "成功率 %d%% · %s" % [int(round(rate * 100.0)), tail]
	if _brush_canvas != null and is_instance_valid(_brush_canvas):
		_brush_canvas.set_batch_count(maxi(_brush_batch, 1))


func _set_brush_batch(n: int) -> void:
	var max_n := _max_batch_for(_brush_recipe)
	if max_n <= 0:
		return
	_brush_batch = clampi(n, 1, max_n)
	_hide_brush_result()
	_refresh_brush_info()
	if _brush_canvas != null and is_instance_valid(_brush_canvas):
		_brush_canvas.activate()


func _finish_brush() -> void:
	if _brush_canvas != null and is_instance_valid(_brush_canvas):
		_brush_canvas.deactivate()
	if _brush_recipe.is_empty():
		_close_brush()
		return
	var n := maxi(1, _brush_batch)
	var res := CharacterData.craft_talisman(_brush_recipe, n)
	var sc := int(res.get("success_count", 0))
	var fc := int(res.get("fail_count", n - sc))
	# ⚠ 制符的埋点必须在这里，不能指望 CraftStage 那一句：制符台打开即进符匣，
	#   成符走的是这条路径，`craft_stage.gd` 里 `note("craft_done:" + craft_kind())`
	#   只对炼丹生效。11-11 漏这一句的后果是「制作一次符纸」任务和教学 c4_talisman
	#   这一步永远打不了勾（配置表写了 ev，运行时没人发）。
	if sc > 0:
		Tutorial.note("craft_done:talisman")
	_refresh_cards()
	if not _selected_id.is_empty():
		_select(_selected_id)
	_craft_result.text = String(res.get("message", ""))
	_craft_result.add_theme_color_override("font_color",
		INK_OK if sc >= n else (INK_WARN if sc > 0 else INK_DANGER))
	_show_brush_result(String(res.get("message", "")), sc, fc, n,
		int(res.get("cost", 0)))


func _show_brush_result(msg: String, sc: int, fc: int, n: int, cost: int) -> void:
	_brush_result_box.visible = true
	_brush_result_label.text = msg
	var all_ok := sc >= n
	_brush_result_label.add_theme_color_override("font_color",
		UIKit.C_OK if all_ok else (UIKit.C_WARN if sc > 0 else UIKit.C_DANGER))
	_brush_result_detail.text = "本次 %d 张 · 成 %d · 败 %d · 耗修为 %d" % [n, sc, fc, cost]
	_brush_stamp.text = "成" if all_ok else ("半" if sc > 0 else "败")
	_brush_stamp.add_theme_color_override("font_color",
		UIKit.C_OK if all_ok else (UIKit.C_WARN if sc > 0 else UIKit.C_DANGER))
	_brush_stamp.visible = true
	_brush_cancel.text = "收笔（返回符匣）"
	_rebuild_brush_actions("再画一批", true)


func _rebuild_brush_actions(retry_text: String, can_retry: bool) -> void:
	UIKit.clear_children(_brush_actions)
	_brush_actions.visible = true
	_brush_cancel.visible = false
	var again := UIKit.primary_button(retry_text, Vector2(104, 28), UIKit.C_ACCENT)
	UIKit.set_readable_font(again, 10)
	again.disabled = not can_retry or _max_batch_for(_brush_recipe) <= 0
	again.pressed.connect(_retry_brush)
	_brush_actions.add_child(again)
	var done := UIKit.quiet_button("收笔", Vector2(64, 28), UIKit.C_TEXT_DIM)
	UIKit.set_readable_font(done, 10)
	done.pressed.connect(_exit_brush)
	_brush_actions.add_child(done)


func _hide_brush_result() -> void:
	if _brush_result_box != null:
		_brush_result_box.visible = false
	if _brush_stamp != null:
		_brush_stamp.visible = false
	if _brush_actions != null:
		_brush_actions.visible = false
	if _brush_cancel != null:
		_brush_cancel.visible = true
		_brush_cancel.text = "放下笔（不制作）"


func _retry_brush() -> void:
	if _brush_canvas == null or _brush_recipe.is_empty():
		return
	var max_n := _max_batch_for(_brush_recipe)
	if max_n <= 0:
		_brush_result_label.text = "材料或修为不足，无法再画"
		_brush_result_label.add_theme_color_override("font_color", UIKit.C_WARN)
		_brush_stamp.visible = false
		_rebuild_brush_actions("再画一批", false)
		return
	_brush_batch = clampi(_brush_batch, 1, max_n)
	_hide_brush_result()
	_refresh_brush_info()
	_brush_canvas.activate()


func _on_brush_empty() -> void:
	if _brush_canvas != null and is_instance_valid(_brush_canvas):
		_brush_canvas.deactivate()
	_brush_result_box.visible = true
	_brush_result_label.text = "符墨耗尽，本次未落笔（材料与修为未扣）"
	_brush_result_label.add_theme_color_override("font_color", UIKit.C_WARN)
	_brush_result_detail.text = "重新铺纸可再试；一张符要一笔描满符路。"
	_brush_stamp.text = "空"
	_brush_stamp.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
	_brush_stamp.visible = true
	_brush_cancel.text = "收笔（返回符匣）"
	_rebuild_brush_actions("重新铺纸", true)


func _exit_brush() -> void:
	_close_brush()
	_refresh_cards()
	if not _selected_id.is_empty():
		_select(_selected_id)


func _close_brush() -> void:
	if _brush_canvas != null and is_instance_valid(_brush_canvas):
		_brush_canvas.deactivate()
	_brush_canvas = null
	if _brush_layer != null and is_instance_valid(_brush_layer):
		_brush_layer.queue_free()
	_brush_layer = null
	_brush_recipe = {}
	_brush_batch = 1
	_brush_qty_row = null
	_brush_cost_label = null
	_brush_rate_label = null
	_brush_stack_label = null
	_brush_result_box = null
	_brush_result_label = null
	_brush_result_detail = null
	_brush_actions = null
	_brush_stamp = null
	_brush_stage_count = null
	_brush_cancel = null


func _assign(item_id: String, slot_index: int) -> void:
	if CharacterData.talisman_count(item_id) <= 0:
		return
	var value := CharacterData.talisman_slot_value(item_id)
	for i in range(CharacterData.active_skill_loadout.size()):
		if String(CharacterData.active_skill_loadout[i]) == value:
			CharacterData.active_skill_loadout[i] = ""
	while CharacterData.active_skill_loadout.size() <= slot_index:
		CharacterData.active_skill_loadout.append("")
	CharacterData.active_skill_loadout[slot_index] = value
	Tutorial.note("talisman_loaded")
	assigned.emit(slot_index)
	_refresh_cards()


func _detail_text(def: Dictionary, eff: Dictionary) -> String:
	var lines: Array[String] = [String(def.get("desc", ""))]
	var kind := String(eff.get("kind", ""))
	if kind == "element_talisman":
		match String(eff.get("effect", "")):
			"sword_qi":
				lines.append("固定伤害 %d；直线剑气，命中第一个目标。" % int(eff.get("damage", 0)))
			"fireball":
				lines.append("固定伤害 %d；80 半径火球，命中挂灼烧 8 秒。" % int(eff.get("damage", 0)))
			"lightning":
				lines.append("固定伤害 %d；%.0f%% 概率眩晕 %.1f 秒。" % [
					int(eff.get("damage", 0)), float(eff.get("stun_chance", 0.0)) * 100.0,
					float(eff.get("stun_time", 0.0))])
			"root":
				lines.append("定身 %.1f 秒。" % float(eff.get("root_time", 0.0)))
			"regen_hp":
				lines.append("每秒回复 %.0f 点气血，持续 %.0f 秒。" % [
					float(eff.get("heal_per_sec", 0.0)), float(eff.get("heal_time", 0.0))])
			"speed_up":
				lines.append("移速 +%.0f%%，持续 %.0f 秒。" % [
					float(eff.get("speed_pct", 0.0)), float(eff.get("duration", 0.0))])
			"stone_body":
				lines.append("移速 -%.0f%%，受伤 -%.0f%%，挡 %d 次或 12 秒。" % [
					float(eff.get("speed_down", 0.0)), float(eff.get("damage_reduction", 0.0)),
					int(eff.get("hits", 0))])
	elif kind == "buff":
		lines.append(String(BuffDB.display_text(String(eff.get("buff_id", "")))))
	return "\n".join(lines)


func _element_effect_line(def: Dictionary) -> String:
	var eff: Dictionary = def.get("battle_effect", {})
	match String(eff.get("effect", "")):
		"sword_qi":
			return "固定 %d 剑气" % int(eff.get("damage", 0))
		"fireball":
			return "固定 %d 火球 + 灼烧" % int(eff.get("damage", 0))
		"lightning":
			return "固定 %d 雷 + %.0f%% 眩晕" % [int(eff.get("damage", 0)),
				float(eff.get("stun_chance", 0.0)) * 100.0]
		"root":
			return "定身 %.0f 秒" % float(eff.get("root_time", 0.0))
		"regen_hp":
			return "10 HP/秒 × %.0f 秒" % float(eff.get("heal_time", 0.0))
		"speed_up":
			return "移速 +%.0f%%，%.0f 秒" % [float(eff.get("speed_pct", 0.0)),
				float(eff.get("duration", 0.0))]
		"stone_body":
			return "受伤 -%.0f%%，挡 %d 次" % [float(eff.get("damage_reduction", 0.0)),
				int(eff.get("hits", 0))]
	return String(def.get("desc", ""))
