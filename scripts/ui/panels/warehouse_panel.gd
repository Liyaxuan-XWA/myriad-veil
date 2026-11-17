class_name WarehousePanel
extends SystemPanel
## 仓库：与背包**完全分开**的独立存储空间（2026-11-02 用户定）
##
## 同一页签里左右两栏并排：左=随身背包（每类 100 格），右=仓库（每类 500 格），
## 单件「存入 / 取出」+ 整类「全部存入 / 全部取回」，两栏各自滚动、页签与栏头固定。
##
## ⚠ 「只有背包里的东西能被使用」这条规则落在 CharacterData 的读接口上：
##   count_item / count_material / has_materials 一律不读 warehouse，
##   所以炼丹、制符、锻造投料、战斗轮盘、破境材料都只认背包。仓库只是存放。
## 符箓照旧收在符匣（talisman_stock），既不占背包也不进仓库。

## 页签顺序与背包一致（常量表达式取不到 autoload，这里写字面量）
const TABS: Array = [
	["丹药", "pill"],
	["材料", "material"],
	["装备", "equipment"],
	["法宝", "treasure"],
]

var _tab: String = CharacterData.ITEM_PILL
var _tab_buttons: Array = []
var _msg: Label

var _bag_list: VBoxContainer
var _wh_list: VBoxContainer
var _bag_count: Label
var _wh_count: Label
var _bag_all_btn: Button
var _wh_all_btn: Button

## 这次打开面板真的搬动过物品 → 关闭时落一次自动存档
var _moved := false


func _init() -> void:
	panel_title = "仓库"
	panel_hint = "ESC 关闭"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("warehouse")


func panel_size() -> Vector2:
	return Vector2(1040.0, 640.0)


## 两栏要各自占满高度并在内部滚动：外层滚动会按最小尺寸摆子节点，栏位会被压扁
func content_scrolls() -> bool:
	return false


func _accent() -> Color:
	return UIKit.facility_style("warehouse").get("accent", UIKit.C_ACCENT)


# ===================== 结构 =====================

func _build_content() -> void:
	var accent := _accent()
	content.add_child(_build_tab_row())

	_msg = UIKit.readable_label("", UIKit.F_BODY, UIKit.C_TEXT_DIM)
	# 固定高度：出反馈时不会把下面两栏顶下去
	_msg.custom_minimum_size = Vector2(0, 20)
	content.add_child(_msg)

	var cols := UIKit.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	cols.add_child(_build_column(true, accent))
	cols.add_child(_build_column(false, accent))

	content.add_child(_build_footnote(accent))


func _build_tab_row() -> Control:
	var row := UIKit.hbox(6)
	for t in TABS:
		var btn := UIKit.tab_button(String(t[0]), Vector2(66, 28))
		UIKit.set_click_sfx(btn, "ui_tab")
		UIKit.set_tab_selected(btn, String(t[1]) == _tab)
		btn.pressed.connect(_on_tab_pressed.bind(String(t[1]), btn))
		btn.set_meta("tut", "warehouse.tab")
		row.add_child(btn)
		_tab_buttons.append([btn, String(t[1])])
	row.add_child(UIKit.spacer())
	var hint := UIKit.readable_label("只有背包里的东西能随时使用", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	return row


## is_bag=true → 左栏（随身背包），false → 右栏（仓库）
func _build_column(is_bag: bool, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(accent, 0.60, 0.24, 8))
	var col := UIKit.vbox(6)
	card.add_child(col)

	var head := UIKit.hbox(8)
	col.add_child(head)
	var title := UIKit.label("随身背包" if is_bag else "仓库储存", UIKit.F_SECTION,
		Color(0.97, 0.93, 0.84) if is_bag else Color(accent.r, accent.g, accent.b, 0.95))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)

	var count := UIKit.readable_label("", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(count)

	var all_btn := UIKit.quiet_button("全部存入" if is_bag else "全部取回", Vector2(86, 26), accent)
	all_btn.pressed.connect(_on_store_all_pressed if is_bag else _on_take_all_pressed)
	head.add_child(all_btn)
	if is_bag:
		_bag_count = count
		_bag_all_btn = all_btn
	else:
		_wh_count = count
		_wh_all_btn = all_btn

	var rule := ColorRect.new()
	rule.color = Color(accent.r, accent.g, accent.b, 0.22)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var list := UIKit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if is_bag:
		_bag_list = list
	else:
		_wh_list = list
	return card


func _build_footnote(accent: Color) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(accent, 0.42, 0.18, 6))
	var l := UIKit.readable_label(
		"炼丹、制符、锻造投料和战斗轮盘只认背包：仓库里的东西要先取回背包才能用。符箓收在符匣，不进仓库。",
		UIKit.F_SMALL, Color(0.72, 0.74, 0.80, 0.95))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# ⚠ autowrap 的 Label 在**还没拿到宽度**时按 1 字一行算最小高度（能撑到一千多 px），
	#   而 SystemPanel 的 _apply_size 是 deferred 的，那一下会把面板高度夹到这个值上。
	#   限两行 + 固定高度，最小尺寸就和宽度无关了。
	l.max_lines_visible = 2
	l.clip_text = true
	l.custom_minimum_size = Vector2(0, 32)
	# 探针按 Label 文本查「符箓」是否又被列成一项；这一行是规则说明，按名字放行
	l.name = "RuleNote"
	box.add_child(l)
	return box


# ===================== 刷新 =====================

func _refresh_content() -> void:
	var d := CharacterData
	UIKit.clear_children(_bag_list)
	UIKit.clear_children(_wh_list)

	var bag_rows := _fill_list(_bag_list, d.inventory, true)
	var wh_rows := _fill_list(_wh_list, d.warehouse, false)
	if bag_rows == 0:
		_bag_list.add_child(_empty_note("这一类背包是空的。"))
	if wh_rows == 0:
		_wh_list.add_child(_empty_note("这一类仓库还是空的。"))

	_bag_count.text = "占用 %d / %d 格" % [d.bag_count_for(_tab), d.bag_cap_for(_tab)]
	_wh_count.text = "占用 %d / %d 格" % [d.warehouse_count_for(_tab), d.WAREHOUSE_CAP_PER_CATEGORY]
	_bag_all_btn.disabled = bag_rows == 0
	_wh_all_btn.disabled = wh_rows == 0


## 按当前页签填一栏，返回渲染行数。下标用**数组真实下标**，不是显示下标
func _fill_list(list: VBoxContainer, source: Array, from_bag: bool) -> int:
	var rows := 0
	for i in source.size():
		var raw = source[i]
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw
		if CharacterData.bag_category_of(item) != _tab:
			continue
		list.add_child(_make_row(item, i, from_bag))
		rows += 1
	return rows


func _make_row(item: Dictionary, index: int, from_bag: bool) -> Control:
	var accent := _accent()
	var border := ItemDB.item_border_color(item)
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 46)
	row.add_theme_stylebox_override("panel", UIKit.slot_style(true, border, 1))

	var box := UIKit.hbox(8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(38, 38)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", UIKit.slot_style(true, border, 2))
	icon_box.add_child(UIKit.icon_node(String(item.get("icon", "")),
		String(item.get("name", "")), String(item.get("type", "")), Vector2(32, 32)))
	box.add_child(icon_box)

	var info := UIKit.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(info)
	info.add_child(_row_name(item))
	info.add_child(_row_sub(item))

	var count := int(item.get("count", 1))
	if count > 1:
		var tag := UIKit.chip("×%d" % count, accent, UIKit.F_SMALL)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(tag)

	var btn := UIKit.quiet_button("存入" if from_bag else "取出", Vector2(58, 26), accent)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if from_bag:
		btn.pressed.connect(_on_store_pressed.bind(index))
		var can_wh := CharacterData.warehouse_has_room(item)
		btn.disabled = not can_wh
		btn.tooltip_text = "存入仓库" if can_wh else _warehouse_full_text()
	else:
		btn.pressed.connect(_on_take_pressed.bind(index))
		var can_bag := CharacterData.bag_has_room(item)
		btn.disabled = not can_bag
		btn.tooltip_text = "取回背包" if can_bag else CharacterData.bag_full_message(item)
	box.add_child(btn)
	return row


func _row_name(item: Dictionary) -> Label:
	var grade := String(item.get("equipment_grade", ""))
	var color := UIKit.grade_color(grade) if grade != "" else Color(0.94, 0.92, 0.88)
	var l := UIKit.label(String(item.get("name", item.get("id", ""))), UIKit.F_BODY, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func _row_sub(item: Dictionary) -> Label:
	var d := CharacterData
	var cat := d.bag_category_of(item)
	var parts := PackedStringArray()
	parts.append(String(d.ITEM_TYPE_DISPLAY.get(cat, "")))
	if cat == d.ITEM_MATERIAL:
		var realm := String(ItemDB.get_material(String(item.get("id", ""))).get("realm", ""))
		if realm != "":
			parts.append(realm)
	var eff := String(item.get("effect", ""))
	if eff != "":
		parts.append(eff)
	var l := UIKit.readable_label("　·　".join(parts), UIKit.F_BADGE, UIKit.C_TEXT_DIM)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func _empty_note(text: String) -> Control:
	var l := UIKit.readable_label(text, UIKit.F_SMALL, UIKit.C_DISABLE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 40)
	return l


# ===================== 交互 =====================

func _on_tab_pressed(tab: String, _btn: Button) -> void:
	if tab == _tab:
		return
	_tab = tab
	for pair in _tab_buttons:
		UIKit.set_tab_selected(pair[0] as Button, String(pair[1]) == _tab)
	_refresh_content()


func _on_store_pressed(index: int) -> void:
	var res := CharacterData.store_to_warehouse(index)
	_report(res)
	if bool(res.get("ok", false)):
		_moved = true
		Tutorial.note("warehouse_move")
		_refresh_content()


func _on_take_pressed(index: int) -> void:
	var res := CharacterData.take_from_warehouse(index)
	_report(res)
	if bool(res.get("ok", false)):
		_moved = true
		Tutorial.note("warehouse_move")
		_refresh_content()


func _on_store_all_pressed() -> void:
	var moved := CharacterData.store_category(_tab)
	if moved == 0:
		_set_msg(_warehouse_full_text(), UIKit.C_WARN)
		return
	var left := CharacterData.bag_count_for(_tab)
	_set_msg("已存入 %d 格。%s" % [moved,
		("背包还剩 %d 格放不下。" % left) if left > 0 else ""], UIKit.C_OK)
	_moved = true
	_refresh_content()


func _on_take_all_pressed() -> void:
	var moved := CharacterData.take_category(_tab)
	if moved == 0:
		_set_msg(CharacterData.bag_full_message({"type": _tab}), UIKit.C_WARN)
		return
	var left := CharacterData.warehouse_count_for(_tab)
	_set_msg("已取回 %d 格。%s" % [moved,
		("仓库还剩 %d 格背包放不下。" % left) if left > 0 else ""], UIKit.C_OK)
	_moved = true
	_refresh_content()


func _warehouse_full_text() -> String:
	return "仓库「%s」已满 %d 格" % [
		String(CharacterData.ITEM_TYPE_DISPLAY.get(_tab, "这一类")),
		CharacterData.WAREHOUSE_CAP_PER_CATEGORY]


func _report(res: Dictionary) -> void:
	_set_msg(String(res.get("message", "")),
		UIKit.C_OK if bool(res.get("ok", false)) else UIKit.C_WARN)


func _set_msg(text: String, color: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", color)


func close() -> void:
	# 物品换了数组就得落档：主城只在「进入主城」时自动存档，
	# 存完直接退出会让仓库看着没生效。
	if _moved:
		SaveManager.auto_save()
	super.close()
