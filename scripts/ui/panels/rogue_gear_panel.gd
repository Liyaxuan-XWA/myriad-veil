class_name RogueGearPanel
extends SystemPanel
## 试炼之路 · 局内行囊（2026-11-08 用户定）
##
## ⚠ 只读写 RogueRun 的局内容器（gear_bag / gear_slots / realm_*），
##   **绝不碰** CharacterData 的 equipment_slots / inventory / 境界字段。
## 局外角色面板在试炼里仍被 rogue_lock 锁住，Tab 改为打开本面板。
## 关闭即销毁（SystemPanel 一次性面板），出局时局内数据由 RogueRun.restore() 清空。

var _realm_label: Label
var _exp_bar: ProgressBar
var _slots_box: GridContainer
var _bag_box: VBoxContainer
var _summary: Label

## 顶部页签：「行囊」（装备/境界）与「玉简」（本局已获增幅卡）。
## ⚠ 不新开键位：试炼里 TAB 已经是「看局内信息」的肌肉记忆，再挂一个键只会和
##   Q/E/R/T（技能）、G（轮盘）、F（拾取）、ESC（结算退出）挤在一起。
var _tab_buttons: Array[Button] = []
var _tab_index := 0
var _page_gear: VBoxContainer
var _page_deck: VBoxContainer
var _deck_view: RogueDeckView
var _deck_tab: Button

## 一行的高度 / 图标边长：只改这两个数，卡片自动跟着缩放（别在下面写死像素）
## ⚠ 装备原画在 256 画布里留白很大（实测有效内容约 45%），所以这里配合
##   `UIKit.equip_icon(..., trim = true)` 一起用：先裁掉透明边，图形才真的填满格子。
const CARD_H := 72.0
const CARD_ICON := 54.0


func _init() -> void:
	panel_title = "试炼行囊"
	# ⚠ header 的 hint 在 820 宽 + 设施抬头下会被挤没（实测整行看不见），
	#   所以这里留空，操作提示统一写进下方页签栏右侧那一行。
	panel_hint = ""


func facility_visual() -> Dictionary:
	return UIKit.facility_style("insight")


func panel_size() -> Vector2:
	return Vector2(820.0, 570.0)


func content_scrolls() -> bool:
	return false


func _build_content() -> void:
	var accent: Color = UIKit.facility_style("insight").get("accent", UIKit.C_ACCENT)
	content.add_child(_build_tab_bar(accent))

	# ===== 页一：行囊（装备 / 境界）=====
	_page_gear = UIKit.vbox(8)
	_page_gear.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_page_gear)

	_page_gear.add_child(UIKit.note_card(
		"击败 BOSS 会掉出该 BOSS 的一件装备（落在地上，走近按 F 拾取），进局内行囊后在这里穿戴。\n"
		+ "击杀小怪与 BOSS 累积修为，满即自动突破。⚠ 装备与境界只在试炼内生效，出局全部清空，绝不碰主模式。",
		accent))

	_realm_label = UIKit.label("", 17, UIKit.C_TITLE)
	_page_gear.add_child(_realm_label)
	_exp_bar = ProgressBar.new()
	_exp_bar.custom_minimum_size = Vector2(0.0, 16.0)
	_exp_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(accent.r, accent.g, accent.b, 0.85)
	_exp_bar.add_theme_stylebox_override("fill", fill)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.22, 0.22, 0.26, 0.95)
	bar_bg.set_corner_radius_all(3)
	_exp_bar.add_theme_stylebox_override("background", bar_bg)
	_page_gear.add_child(_exp_bar)

	# ⚠ 摘要放在主区之前：main 是 SIZE_EXPAND_FILL，放它后面会被挤到面板外看不见
	_summary = UIKit.readable_label("", 12, UIKit.C_TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.custom_minimum_size = Vector2(0.0, 24.0)
	_page_gear.add_child(_summary)

	var main := UIKit.hbox(16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_gear.add_child(main)

	var left := UIKit.vbox(6)
	left.custom_minimum_size = Vector2(350.0, 0.0)
	main.add_child(left)
	left.add_child(UIKit.label("已穿戴（点击卸下）", 14, UIKit.C_ACCENT))
	# 6 个槽位排成 2 列 × 3 行：比竖着堆 6 条省一半高度，又保留「装备栏」的形状
	_slots_box = GridContainer.new()
	_slots_box.columns = 2
	_slots_box.add_theme_constant_override("h_separation", 6)
	_slots_box.add_theme_constant_override("v_separation", 6)
	left.add_child(_slots_box)

	var right := UIKit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	right.add_child(UIKit.label("行囊（点击穿戴）", 14, UIKit.C_ACCENT))
	# ⚠ 行囊会越捡越多（一局能捡十几件），不套滚动容器会直接顶出面板外
	var bag_scroll := ScrollContainer.new()
	bag_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(bag_scroll)
	_bag_box = UIKit.vbox(6)
	_bag_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(_bag_box)

	# ===== 页二：玉简（本局已获增幅卡）=====
	_page_deck = UIKit.vbox(0)
	_page_deck.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_deck.visible = false
	content.add_child(_page_deck)

	# ⚠ 玉简会越拿越多（一局二三十张），必须整页滚动；
	#   横向滚动禁用，否则窄一点的分辨率会出现第二条滚动条把卡片挤扁。
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_deck.add_child(deck_scroll)
	_deck_view = RogueDeckView.new()
	_deck_view.name = "RogueDeckView"
	deck_scroll.add_child(_deck_view)


## 顶部导航：两枚书签页签 + 一条细分隔线，把导航区从正文里切出来。
## 沿用万界塔面板的做法（`UIKit.tab_button` + `set_tab_selected`），别用 modulate 压暗
## —— 那会把「选中 / 未选中」的对比一起抹平。
func _build_tab_bar(accent: Color) -> Control:
	var col := UIKit.vbox(0)
	var bar := UIKit.hbox(10)
	bar.name = "RogueGearTabBar"
	bar.custom_minimum_size = Vector2(0.0, 40.0)
	var labels := ["行囊", "玉简"]
	for i in labels.size():
		var btn := UIKit.tab_button(String(labels[i]), Vector2(124.0, 36.0), accent)
		btn.add_theme_font_size_override("font_size", UIKit.F_SUBTITLE)
		btn.tooltip_text = "点击切换到「%s」" % String(labels[i])
		btn.pressed.connect(_switch_tab.bind(i))
		bar.add_child(btn)
		_tab_buttons.append(btn)
		if i == 1:
			_deck_tab = btn
	bar.add_child(UIKit.spacer())
	# ⚠ 用项目通用的 ◆，别用 ◂ / → 这类箭头（三极泼墨体缺字会渲染成小方点）
	var hint := UIKit.label("◆ ESC 关闭 · 点页签切换", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(hint)
	col.add_child(bar)
	var rule := ColorRect.new()
	rule.color = Color(0.95, 0.82, 0.45, 0.20)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	if _tab_buttons.size() >= 2:
		UIKit.set_tab_selected(_tab_buttons[0], true)
		UIKit.set_tab_selected(_tab_buttons[1], false)
	return col


func _switch_tab(index: int) -> void:
	if index == _tab_index:
		return
	_tab_index = index
	if _page_gear != null:
		_page_gear.visible = index == 0
	if _page_deck != null:
		_page_deck.visible = index == 1
	for i in _tab_buttons.size():
		UIKit.set_tab_selected(_tab_buttons[i], i == index)
	# 切到玉简才重画：行囊页每帧都在刷新，没必要为看不见的页面反复建节点
	if index == 1 and _deck_view != null:
		_deck_view.refresh()
		Tutorial.note("rogue_deck_open")
	GameState.play_ui("ui_tab")


func _refresh_content() -> void:
	_refresh_gear_page()
	_refresh_tab_labels()
	# 打开面板时若停在玉简页（探针 / 上一帧切过），按最新数据重画一遍
	if _tab_index == 1 and _deck_view != null:
		_deck_view.refresh()
	_pin_panel_size()


## ⚠ 说明卡里的 autowrap Label 第一帧按 0 宽度量高度（量出 1900+ px），PanelContainer
## 被这个假最小高度撑到两千多高，而且**不会自己缩回去** —— 表现为「面板变形、越拿越多卡
## 越拉越长」，玉简页的 ScrollContainer 也因此永远拿到内容同高的视口、滚不动。
## 等布局落定两帧后把尺寸钉回 panel_size()，滚动条才会出现。
func _pin_panel_size() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and _visible:
		_apply_size()


## 玉简页签带数量：不切页也知道这一局到底攒了多少张
func _refresh_tab_labels() -> void:
	if _deck_tab == null:
		return
	var n := RogueRun.buffs.size()
	_deck_tab.text = "玉简" if n <= 0 else "玉简 · %d" % n


func _refresh_gear_page() -> void:
	_realm_label.text = "境界：%s　修为 %d/%d　累计突破 %d 次" % [
		RogueRun.realm_title(), RogueRun.realm_exp,
		RogueRun.stage_exp_required(), RogueRun.breakthroughs]
	_exp_bar.max_value = float(maxi(1, RogueRun.stage_exp_required()))
	_exp_bar.value = float(RogueRun.realm_exp)

	UIKit.clear_children(_slots_box)
	var worn := 0
	for raw in CharacterData.SLOT_ORDER:
		var slot := String(raw)
		var it = RogueRun.gear_slots.get(slot)
		var equipped := it is Dictionary
		if equipped:
			worn += 1
		var slot_name := String(CharacterData.SLOT_DISPLAY.get(slot, slot))
		var card: Button
		if equipped:
			var gitem: Dictionary = it
			# 副行显示槽位名，主行才是装备名 —— 空槽反过来（槽位名当主行）
			card = _gear_card(gitem, String(gitem.get("name", "装备")), slot_name)
			card.tooltip_text = "点击卸下，回到行囊"
			card.pressed.connect(_on_unequip.bind(slot))
		else:
			card = _gear_card({}, slot_name, "— 空 —", false)
			card.tooltip_text = "该槽位还没有装备"
		_slots_box.add_child(card)

	UIKit.clear_children(_bag_box)
	if RogueRun.gear_bag.is_empty():
		var empty := UIKit.readable_label(
			"行囊空空。击败 BOSS 后会掉落该 BOSS 的一件装备（落地，按 F 拾取），回到这里点一下就能穿戴。",
			12, UIKit.C_TEXT_FAINT)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bag_box.add_child(empty)
	else:
		for i in RogueRun.gear_bag.size():
			var raw = RogueRun.gear_bag[i]
			if not (raw is Dictionary):
				continue
			var item: Dictionary = raw
			var attrs := ItemDB.item_attributes_text(item)
			var row := _gear_card(item, String(item.get("name", "装备")),
				attrs if attrs != "" else "无词条")
			row.tooltip_text = "点击穿戴到对应槽位"
			row.pressed.connect(_on_equip.bind(i))
			_bag_box.add_child(row)

	var gear_src: Dictionary = CharacterData.attribute_mods.get("rogue_gear", {})
	var realm_src: Dictionary = CharacterData.attribute_mods.get("rogue_realm", {})
	_summary.text = "局内加成：已穿戴 %d/6 件 · 装备词条 %d 条 · 境界修正 %d 条（属性已实时生效）" % [
		worn, gear_src.size(), realm_src.size()]


## 一行「具象化」装备卡片：左侧图标（真贴图 / 空槽占位）+ 右侧名称与词条。
##
## ⚠ 为什么不用 `UIKit.paper_button(text)`：那种按钮只画一行字，放不下图标、
##   也没有品阶描边。这里沿用角色面板装备格的做法 —— 裸 Button + `UIKit.slot_style()`
##   （品阶色描边），内容套 `slot_padding()` 再用 `PRESET_FULL_RECT` 铺满，
##   所有子节点 `MOUSE_FILTER_IGNORE`，否则图例会抢走点击、按钮点不动。
## ⚠ 图标一律走 `UIKit.equip_icon()`：美术替换只需在装备数据里填 icon，这里不用改。
func _gear_card(item: Dictionary, title: String, sub: String, filled: bool = true) -> Button:
	var b := Button.new()
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0.0, CARD_H)
	var border := UIKit.C_SLOT_BORDER
	if filled and not item.is_empty():
		border = ItemDB.item_border_color(item)
	UIKit.apply_slot_style(b, UIKit.slot_style(filled, border, 2))
	UIKit.attach_click_sfx(b)
	b.disabled = not filled

	var mc := UIKit.slot_padding()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(mc)
	var h := UIKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(h)

	if filled and not item.is_empty():
		h.add_child(UIKit.equip_icon(item, Vector2(CARD_ICON, CARD_ICON), true))
	else:
		h.add_child(_empty_icon())

	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var name_lbl := UIKit.label(title, 14,
		UIKit.grade_color(String(item.get("equipment_grade", ""))) if filled else UIKit.C_TEXT_FAINT)
	# 不开 autowrap（会把最小高度算大、把卡片撑高），长了就省略号
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)

	if sub != "":
		var sub_lbl := UIKit.readable_label(sub, 11,
			UIKit.C_TEXT_DIM if filled else UIKit.C_TEXT_FAINT)
		sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sub_lbl)
	return b


## 空槽图标位：和真图标同尺寸的暗方块 + 「空」字，保证 6 个槽位总是对齐成一格一格
func _empty_icon() -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(CARD_ICON, CARD_ICON)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_ICON, CARD_ICON)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.C_SLOT_BG
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var l := UIKit.label("空", 10, UIKit.C_TEXT_FAINT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)
	holder.add_child(panel)
	return holder


func _on_equip(index: int) -> void:
	if RogueRun.equip_from_bag(index):
		GameState.play_ui("ui_tab")
		_refresh_content()


func _on_unequip(slot: String) -> void:
	if RogueRun.unequip_gear(slot):
		GameState.play_ui("ui_tab")
		_refresh_content()
