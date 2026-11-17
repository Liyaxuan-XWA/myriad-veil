class_name ForgeTagSlot
extends Button
## 工坊兵器架挂签：已穿戴 / 背包装备共用
## 外观是钉在木架上的纸/皮签，品阶色只染描边，不染整张纸。

var item: Dictionary = {}
var index := -1
var slot_id := ""
var panel: Node = null
var kind := "bag"          # bag / worn
var compact := false
## 点一下 = 自动上铁砧；拖到已穿戴格 = 换装。这个标记区分真拖出去和单纯点击，
## 免得松手时又上一遍。
var _drag_started := false


func setup(p_item: Dictionary, p_panel: Node, p_kind: String, p_index := -1,
		p_slot := "", p_compact := false) -> void:
	item = p_item
	panel = p_panel
	kind = p_kind
	index = p_index
	slot_id = p_slot
	compact = p_compact
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	# 槽宽：已穿戴网格 78（3×78+10=244 ≤ 254）；背包格要再让出竖直滚动条 12px，只能 76
	custom_minimum_size = Vector2(78, 90) if compact else Vector2(76, 102)

	var empty := item.is_empty()
	var grade := String(item.get("equipment_grade", ""))
	var border := UIKit.grade_border_color(grade) if not empty else Color(0.18, 0.15, 0.12, 1.0)
	var sb := StyleBoxTexture.new()
	sb.texture = UIKit.ui_texture("res://assets/ui/forge/paper_tag_9p.png")
	sb.texture_margin_left = 22
	sb.texture_margin_right = 22
	sb.texture_margin_top = 30
	sb.texture_margin_bottom = 22
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.modulate_color = Color(0.82, 0.78, 0.70) if empty else Color(1, 1, 1)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 6
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxTexture
	hover.modulate_color = Color(1.08, 1.02, 0.90)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", sb)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var frame := PanelContainer.new()
	frame.name = "__frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0)
	fsb.border_color = border
	fsb.set_border_width_all(2 if not empty else 1)
	fsb.set_corner_radius_all(5)
	frame.add_theme_stylebox_override("panel", fsb)
	add_child(frame)

	var pad := UIKit.slot_padding()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pad)
	var v := UIKit.vbox(1)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(v)

	var slot_label := CharacterData.slot_display_name(slot_id) if p_kind == "worn" else ""
	if slot_label != "":
		var sl := UIKit.label(slot_label, 9, Color(0.47, 0.39, 0.28))
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sl)

	if empty:
		var empty_lbl := UIKit.label("空", 14, Color(0.46, 0.41, 0.33))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(empty_lbl)
		tooltip_text = "%s\n空 · 可拖装备到这里" % CharacterData.slot_display_name(slot_id)
		# ⚠ 空槽也必须挂拖放转发，否则空的护甲 / 饰品槽收不到任何装备
		if kind == "worn":
			set_drag_forwarding(_drag_worn, panel._can_drop_on_worn.bind(slot_id),
				panel._drop_on_worn.bind(slot_id))
		return

	# 图标放大：30/34 → 42/50，挂签主要靠图标认装备
	# 强化数字改由右上角单独绘制，所以不走 equip_icon（它自带右下角金色 +N 角标）
	var icon_size := Vector2(42, 42) if compact else Vector2(50, 50)
	var icon := _trimmed_icon(String(item.get("icon", "")), String(item.get("name", "?")),
		"treasure" if String(item.get("equipment_type", "")) == "treasure" else "equipment",
		icon_size)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon)
	var name_lbl := UIKit.label(String(item.get("name", "?")), 9 if compact else 10,
		UIKit.grade_color(grade) if grade != "" else UIKit.C_TEXT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 品阶色（尤其凡品近白）压在羊皮纸底上发飘，描黑边才立得住
	UIKit.soft_text_shadow(name_lbl, 1)
	# 右侧给角标数字留出 16px：名字居中在剩余宽度里，不会被右下角的磨损数字压住
	var name_row := MarginContainer.new()
	name_row.add_theme_constant_override("margin_right", 16)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(name_lbl)
	v.add_child(name_row)

	# 左上角绿色 = 累计强化成功次数；右上角黑色 = 当前强化等级；
	# 右下角红色 = 累计失败次数（破损就写「破」）
	# 法宝没有普通强化与词条，这三个角标全部不画。
	var is_divine_badge := String(item.get("equipment_type", "")) != "treasure" 		and ItemDB.is_max_grade(String(item.get("equipment_grade", "")))
	if String(item.get("equipment_type", "")) != "treasure" and not is_divine_badge:
		var success := maxi(0, int(item.get("enhance_success_count", 0)))
		if success > 0:
			add_child(_corner_label("成%d" % success, Color(0.16, 0.44, 0.19), true, true))
		var enh := maxi(0, int(item.get("enhancement_level", 0)))
		if enh > 0:
			add_child(_corner_label("+%d" % enh, Color(0.09, 0.07, 0.05), true))
		var broken := bool(item.get("is_broken", false))
		var fail := mini(ItemDB.ENHANCE_FAIL_LIMIT, maxi(0, int(item.get("enhance_fail_count", 0))))
		if broken or fail > 0:
			add_child(_corner_label("破" if broken else "%d" % fail, Color(0.80, 0.12, 0.10), false))
	tooltip_text = _tooltip()

	pressed.connect(_on_pressed)
	gui_input.connect(_on_gui_input)
	if kind == "worn":
		set_drag_forwarding(_drag_worn, panel._can_drop_on_worn.bind(slot_id),
			panel._drop_on_worn.bind(slot_id))
	else:
		set_drag_forwarding(_drag_bag, panel._can_drop_on_bag_at, panel._drop_on_bag_at)


## 图标贴图是 256 画布、兵器只占中间 ~45%，直接放大控件看着还是小。
## 按 alpha 包围盒裁一次再撑满图标框；结果按路径缓存（get_image/get_used_rect 要扫整图）。
static var _icon_regions: Dictionary = {}

## 裁掉 alpha 空白后的贴图（挂签图标 / 拖拽预览共用；结果按路径缓存）
static func _trimmed_texture(icon_path: String) -> Texture2D:
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return null
	if not _icon_regions.has(icon_path):
		var tex := load(icon_path) as Texture2D
		var img := tex.get_image() if tex != null else null
		_icon_regions[icon_path] = Rect2(img.get_used_rect()) if img != null else Rect2()
	var region: Rect2 = _icon_regions[icon_path]
	if region.size.x > 0.0 and region.size.y > 0.0:
		var at := AtlasTexture.new()
		at.atlas = load(icon_path)
		at.region = region
		return at
	return load(icon_path)


static func _trimmed_icon(icon_path: String, display_name: String, type: String,
		size: Vector2) -> Control:
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return UIKit.icon_node(icon_path, display_name, type, size)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = _trimmed_texture(icon_path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	return holder


## 槽位角上的数字：左上角累计成功（绿）/ 右上角强化（黑）/ 右下角磨损（红）。
## 直接锚在挂签四角、不进 vbox —— 图标放大后排版里没有多余的行给它。
func _corner_label(text: String, color: Color, top: bool, left := false) -> Label:
	var l := UIKit.label(text, 12, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP if top else VERTICAL_ALIGNMENT_BOTTOM
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.anchor_left = 0.0 if left else 1.0
	l.anchor_right = 0.0 if left else 1.0
	l.anchor_top = 0.0 if top else 1.0
	l.anchor_bottom = 0.0 if top else 1.0
	l.offset_left = 5.0 if left else -40.0
	l.offset_right = 40.0 if left else -5.0
	if top:
		l.offset_top = 1.0
		l.offset_bottom = 19.0
	else:
		l.offset_top = -19.0
		l.offset_bottom = -2.0
	l.z_index = 2
	return l


func _tooltip() -> String:
	var head := "【%s】" % (CharacterData.slot_display_name(slot_id) if kind == "worn" else "背包")
	var lines: Array[String] = [head, String(item.get("name", "?"))]
	if String(item.get("equipment_type", "")) == "treasure":
		lines.append("品阶：%s · 法宝（无属性词条）" % String(item.get("equipment_grade", "")))
		for line in ItemDB.treasure_effect_lines(item):
			lines.append(line)
		lines.append("进阶只增强主动效果。")
		lines.append("点一下卸下" if kind == "worn" else "点一下上砧 · 拖到已穿戴格装备 · 右键看详情")
		return "\n".join(lines)
	var is_divine := String(item.get("equipment_type", "")) != "treasure" \
		and ItemDB.is_max_grade(String(item.get("equipment_grade", "")))
	if is_divine:
		lines.append("品阶：%s · 已铸神（没有强化等级）" % String(item.get("equipment_grade", "")))
		var dattr := ItemDB.item_attributes_with_gain_text(item)
		if dattr != "":
			lines.append(dattr)
		lines.append("神器无法再强化")
		lines.append("点一下卸下" if kind == "worn" else "点一下上砧 · 拖到已穿戴格装备 · 右键看详情")
		return "\n".join(lines)
	lines.append("品阶：%s · 强化 %s" % [
		String(item.get("equipment_grade", "")), ItemDB.enhance_text(item)])
	var attr := ItemDB.item_attributes_with_gain_text(item)
	if attr != "":
		lines.append(attr)
	if int(item.get("enhance_success_count", 0)) > 0:
		lines.append("累计强化词条 %d 次（大成功计 2 次）" % int(item.get("enhance_success_count", 0)))
	if bool(item.get("is_broken", false)):
		lines.append("【已破损】无法继续强化")
	elif int(item.get("enhance_fail_count", 0)) > 0:
		lines.append(ItemDB.wear_text(item))
	lines.append("点一下卸下" if kind == "worn" else "点一下上砧 · 拖到已穿戴格装备 · 右键看详情")
	return "\n".join(lines)


func _on_pressed() -> void:
	if panel == null:
		return
	if _drag_started:
		_drag_started = false
		return
	if kind == "worn":
		if panel.has_method("_on_unequip"):
			panel._on_unequip(slot_id)
		return
	if panel.has_method("_on_bag_clicked"):
		panel._on_bag_clicked(index)


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_drag_started = false
	elif mb.button_index == MOUSE_BUTTON_RIGHT and panel != null:
		GameState.play_ui("ui_click")
		panel._show_item_detail(item, ("已穿戴 · " + CharacterData.slot_display_name(slot_id))
			if kind == "worn" else "背包")
		accept_event()


func _drag_bag(_at: Vector2) -> Variant:
	if kind != "bag" or item.is_empty():
		return null
	_drag_started = true
	return {
		"kind": "forge_drag", "from": "bag", "index": index,
		"slot": String(item.get("equipment_type", "")),
		"name": String(item.get("name", "")),
	}


## 身上装备也能拖走：拖到背包（卸下）/ 铁砧（上砧）/ 另一个槽（换位）
func _drag_worn(_at: Vector2) -> Variant:
	if kind != "worn" or item.is_empty():
		return null
	_drag_started = true
	return {
		"kind": "forge_drag", "from": "worn", "slot": slot_id,
		"name": String(item.get("name", "")),
	}

