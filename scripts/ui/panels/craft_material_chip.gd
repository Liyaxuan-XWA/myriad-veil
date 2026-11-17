extends PanelContainer
## 药筐 / 皮架里的一味料（炼丹炉 · 制符台共用）
##
## 两种投法：**拖着丢进炉口**（主路径），或**点一下投一株**（触屏与快节奏兜底）。
## 拖拽协议：{ "kind": "craft_material", "id": String, "name": String }
## 跟随鼠标的那枚图标由 CraftStage 画在自己的 overlay 层上 ——
## 引擎的 set_drag_preview 画在根 viewport，会被本面板这层 CanvasLayer 盖住（锻造台同款坑）。

var material_id := ""
var material_name := ""
var count := 1
var stage: Node = null


func setup(p_id: String, p_name: String, p_count: int, p_stage: Node) -> void:
	material_id = p_id
	material_name = p_name
	count = p_count
	stage = p_stage

	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("panel", _rest_style())
	gui_input.connect(_on_input)

	var mc := UIKit.slot_padding()
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mc)
	var h := UIKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(h)
	h.add_child(UIKit.icon_node(String(ItemDB.get_material(material_id).get("icon", "")),
		material_name, "material", Vector2(30, 30)))

	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var nm := UIKit.label(material_name, UIKit.F_BODY)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	# 一味的去处写死在这一行：不用先翻方卷也知道丢进去会炼成什么
	var to := UIKit.readable_label("→ %s" % ItemDB.product_name_for_material(
		String(p_stage.call("craft_kind")), material_id), UIKit.F_BADGE, UIKit.C_TEXT_DIM)
	to.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(to)

	var ct := UIKit.label("×%d" % count, 15,
		UIKit.C_OK if count > 0 else UIKit.C_DANGER)
	ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ct)


func _rest_style() -> StyleBoxFlat:
	var sb := UIKit.slot_style(count > 0, ItemDB.material_border_color(material_id), 2)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _on_input(event: InputEvent) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	var released := false
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		released = true
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		released = true
	if not released:
		return
	# 刚起手拖拽就不算点击
	var vp := get_viewport()
	if vp != null and vp.gui_is_dragging():
		return
	stage.call("add_dose", material_id)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if stage == null or not is_instance_valid(stage):
		return null
	if count <= 0:
		stage.call("show_toast", "「%s」已经全部投进炉里了" % material_name, UIKit.C_WARN)
		return null
	if not bool(stage.call("can_accept", material_id)):
		return null
	# 不给 set_drag_preview：跟随图标交给 CraftStage._tick_follow()
	return {"kind": "craft_material", "id": material_id, "name": material_name}
