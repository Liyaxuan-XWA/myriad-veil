class_name SkillPanel
extends SystemPanel
## 功法库 —— 随身携带，Y 键打开
##
## 硬约束（§2.9 / §5.4）：
##   - 主角开局零功法，唯一来源为「真实位面 BOSS 击杀 → 解锁塔投影 → 首杀感悟」
##   - 习得即完整版，无等级、无升级（is_upgradeable 恒 false）
##   - 主城 / 演武场训练可自由切换搭配；正式位面 / 塔战斗不提供入口
##
## 布局（本次调整）：
##   - 「全部功法」按**来源 BOSS 分组**，无来源 BOSS 的归入独立的「杂类」分组
##   - 组标题可点击展开 / 收起，**默认全部收起**（不提供一键全展开）
##   - 组内每门功法都显示「是否已习得」
##
## 装配槽位：主动 4 / 被动 1。
## 主动 4 槽与战斗内快捷键一一对应（见下方 SLOT_KEYS），装配顺序即按键顺序。

## 主动功法槽位对应的战斗内快捷键（顺序即槽位顺序）
## ⚠ 必须与 scripts/player/player.gd 的 SKILL_KEYS 保持一致，改一处就要改另一处
const SLOT_KEYS: Array[String] = ["Q", "E", "R", "T"]

const MAX_ACTIVE := 4
const MAX_PASSIVE := 1

var _loadout_box: VBoxContainer
var _all_box: VBoxContainer
## 分组展开状态：group_id -> bool。空字典 = 全部收起（每次开面板都重新收起）
var _expanded: Dictionary = {}
## 单条功法的详情展开状态：skill_id -> bool（紧凑行点开后为 true）
var _expanded_skills: Dictionary = {}
## 「当前搭配」里的装配选择器：
##   _assign_slot >= 0  给某个键位挑选主动功法（槽位 → 技能）
##   _assign_passive     给唯一的被动槽挑选被动
## 技能 → 键位走独立的弹窗，见 _open_active_slot_popup()
var _assign_slot := -1
var _assign_passive := false
var _assign_popup: Control = null
var _cabinet: Control = null


func _init() -> void:
	panel_title = "功法库"
	panel_hint = "Y 键开关 · ESC 关闭"

func facility_visual() -> Dictionary:
	return UIKit.facility_style("skill")



func panel_size() -> Vector2:
	return Vector2(960.0, 640.0)


func _accent() -> Color:
	return UIKit.facility_style("skill").get("accent", UIKit.C_ACCENT)


func _open_cabinet(target_index: int = -1) -> void:
	if _cabinet != null and is_instance_valid(_cabinet):
		_cabinet.queue_free()
	var cab = load("res://scripts/ui/talisman_cabinet.gd").new()
	cab.target_slot = target_index
	cab.assigned.connect(func(_slot: int) -> void: _refresh_content())
	# ⚠ 关掉符匣也要重刷：在匣里画完符（成符走 talisman_stock，不发 assigned）只挂
	#   assigned 的话，行尾「符匣 · N 种」会停在打开面板时的旧数 —— 带状态的入口
	#   一旦数字是旧的，比没有状态更误导。
	cab.closed.connect(func() -> void:
		_cabinet = null
		_refresh_content())
	add_child(cab)
	_cabinet = cab


func _input(event: InputEvent) -> void:
	if _cabinet != null and is_instance_valid(_cabinet):
		# 符匣自己处理 ESC；技能库不要同时关闭
		return
	if _assign_popup != null and is_instance_valid(_assign_popup) \
			and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close_active_slot_popup()
		return
	super._input(event)


func _build_content() -> void:
	var accent := _accent()
	content.add_child(UIKit.note_card(
		"功法唯一来源：击杀真实位面 BOSS 解锁塔投影，首次击杀投影后感悟习得（§2.8.3）。重复击杀不再获得。",
		accent))
	content.add_child(UIKit.readable_label(
		"最终伤害 =（物理攻击力 × 物理系数 + 法术攻击力 × 法术系数）× 自身增益/削弱 ×（1 − 敌方抗性减免）× 敌方易伤",
		10, UIKit.C_TEXT_DIM))
	content.add_child(UIKit.section("当前搭配", accent))
	_loadout_box = UIKit.vbox(8)
	# 新手指引锚点：这里是「当前搭配」的装配区（c5_insight 指它，而不是整块面板）
	_loadout_box.set_meta("tut", "hud.skill.book")
	content.add_child(_loadout_box)
	content.add_child(UIKit.section("全部功法", accent))
	content.add_child(UIKit.readable_label(
		"按来源 BOSS 分组，点击分组标题展开；展开后点单条功法查看详情与装配。",
		10, UIKit.C_TEXT_DIM))
	_all_box = UIKit.vbox(8)
	content.add_child(_all_box)


func _refresh_content() -> void:
	UIKit.clear_children(_loadout_box)
	_loadout_box.add_child(_make_active_slots())
	if _assign_slot >= 0:
		_loadout_box.add_child(_make_slot_picker(_assign_slot))
	_loadout_box.add_child(_make_loadout_row("被动功法", CharacterData.passive_skill_loadout, MAX_PASSIVE, SkillDB.TYPE_PASSIVE))
	if _assign_passive:
		_loadout_box.add_child(_make_passive_picker())

	UIKit.clear_children(_all_box)
	for g in SkillDB.get_library_groups():
		var gid := String(g.get("group_id", ""))
		var skills: Array = g.get("skills", [])
		# 有新功法时自动展开对应分组，玩家一进功法库就能看到红「新」标
		for s in skills:
			if CharacterData.is_skill_new(String((s as Dictionary).get("skill_id", ""))):
				_expanded[gid] = true
				break
		var is_open := bool(_expanded.get(gid, false))
		_all_box.add_child(_make_group_header(g, is_open))
		if not is_open:
			continue
		var body := UIKit.vbox(4)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 18)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_child(body)
		_all_box.add_child(margin)
		if skills.is_empty():
			body.add_child(UIKit.label("（该组暂无功法）", UIKit.F_SMALL, UIKit.C_DISABLE))
			continue
		# 本组共享的机制（两仪势 / 刀痕 / 剑意）在组顶挂一次规则卡，
		# 单门详情只留这门自己的差异 —— 不再每门重复一遍同一套话
		var rules := SkillDB.get_group_rules(String((g as Dictionary).get("boss_id", "")))
		if not rules.is_empty():
			body.add_child(UIKit.note_card(SkillDB.group_rules_text(rules), _accent()))
		for s in skills:
			body.add_child(_make_skill_row(s))


# ===================== 当前搭配 =====================

## 主动功法：4 个键位卡片，显示图标 / 名称 / 更换 / 卸下
func _make_active_slots() -> Control:
	var wrap := UIKit.vbox(4)

	var head := UIKit.hbox(8)
	head.add_child(UIKit.label("主动功法 / 符箓（%d / %d）" % [
		CharacterData.active_skill_count(), MAX_ACTIVE
	], UIKit.F_BODY))
	head.add_child(UIKit.spacer())
	# ⚠ 原来这里是 `quiet_button("符匣", 54×24)` + 字号 10：
	#   `TONE_QUIET` 的皮肤是 StyleBoxEmpty（**一点底都没有**），文字色 0.68 灰，
	#   又紧挨着同样灰、同样小的提示句 → 玩家把它读成句子里的一个词，找不到入口。
	#   改法不是加朱印强调色（那会抢掉本屏唯一主按钮的位置），而是**给它结构与状态**：
	#   ① 换成有墨纸底的 default 按钮；② 字号抬到正文级；③ 文案带现算的库存种类数；
	#   ④ 挪到行尾（行尾=动作位），把说明句留在它左边，读序变成「说明 → 按钮」。
	head.add_child(UIKit.label("点「更换 / 装配」指派 Q/E/R/T",
		UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	var cab_btn := UIKit.button(_cabinet_entry_text(), Vector2(148, 30))
	UIKit.set_readable_font(cab_btn, UIKit.F_BODY)
	cab_btn.tooltip_text = "打开符匣，把符箓装进 Q/E/R/T"
	cab_btn.pressed.connect(_open_cabinet.bind(-1))
	head.add_child(cab_btn)
	wrap.add_child(head)

	var row := UIKit.hbox(8)
	for i in MAX_ACTIVE:
		row.add_child(_make_active_slot(i))
	wrap.add_child(row)
	return wrap


## 符匣入口的文案：种类数**现算**，不写死也不另存一份计数。
## 空匣不禁用按钮 —— 禁用了反而更找不到；用文字说明「还没有符」，点进去能看到去哪弄。
func _cabinet_entry_text() -> String:
	var kinds := CharacterData.talisman_stock.size()
	if kinds <= 0:
		return "符匣 · 还没有符"
	return "符匣 · %d 种" % kinds


func _make_active_slot(index: int) -> Control:
	var sid := ""
	if index < CharacterData.active_skill_loadout.size():
		sid = String(CharacterData.active_skill_loadout[index])
	var accent := _accent()

	var box := PanelContainer.new()
	var sb := UIKit.accent_card_style(accent, 0.70 if sid != "" else 0.42,
		0.38 if sid != "" else 0.16, 7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(205.0, 86.0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := UIKit.vbox(3)
	box.add_child(v)
	var is_talisman := CharacterData.is_talisman_slot(sid)
	var head := UIKit.hbox(5)
	v.add_child(head)
	head.add_child(UIKit.chip("[%s]" % _slot_key_text(index), accent, 10))
	head.add_child(UIKit.label("符箓" if is_talisman else "主动", 10, UIKit.C_TEXT_DIM))
	head.add_child(UIKit.spacer())
	if sid == "":
		var equip := UIKit.quiet_button("装配", Vector2(54, 24), accent)
		UIKit.set_readable_font(equip, 10)
		equip.tooltip_text = "为 [%s] 选择主动功法" % _slot_key_text(index)
		equip.pressed.connect(_request_slot.bind(index))
		head.add_child(equip)
	else:
		var change := UIKit.quiet_button("更换", Vector2(42, 22), accent)
		UIKit.set_readable_font(change, 10)
		change.tooltip_text = "更换 [%s] 槽的%s" % [_slot_key_text(index), "符箓" if is_talisman else "主动功法"]
		change.pressed.connect(_open_cabinet.bind(index) if is_talisman else _request_slot.bind(index))
		head.add_child(change)
		var off := UIKit.quiet_button("卸下", Vector2(42, 22), accent)
		UIKit.set_readable_font(off, 10)
		off.tooltip_text = "卸下 [%s] 槽" % _slot_key_text(index)
		off.pressed.connect(_on_unequip.bind(sid, true))
		head.add_child(off)

	var bottom := UIKit.hbox(6)
	v.add_child(bottom)
	if sid == "":
		var empty := UIKit.label("空位", 12, UIKit.C_DISABLE)
		empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(empty)
		bottom.add_child(UIKit.label("点「装配」选择功法", 9, UIKit.C_DISABLE))
		return box
	bottom.add_child(UIKit.icon_node(
		CharacterData.active_slot_display_icon(sid),
		CharacterData.active_slot_display_name(sid), "skill", Vector2(34, 34)))
	var name_lbl := UIKit.label(CharacterData.active_slot_display_name(sid), 14, Color(0.97, 0.92, 0.82))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom.add_child(name_lbl)
	if is_talisman:
		bottom.add_child(UIKit.label("×%d" % CharacterData.active_slot_talisman_count(sid),
			11, UIKit.C_OK))
	return box


func _slot_key_text(index: int) -> String:
	return SLOT_KEYS[index] if index >= 0 and index < SLOT_KEYS.size() else "?"


## 被动槽：图标 + 名称 + 更换 / 卸下；空槽直接给装配入口
func _make_loadout_row(title: String, loadout: Array, maximum: int, _type: String) -> Control:
	var accent := _accent()
	var row := PanelContainer.new()
	var sb := UIKit.accent_card_style(accent, 0.48, 0.18, 6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", sb)
	var hbox := UIKit.hbox(8)
	row.add_child(hbox)
	var count := 0
	for sid in loadout:
		if String(sid) != "":
			count += 1
	hbox.add_child(UIKit.chip("%s %d / %d" % [title, count, maximum], accent, 10))
	if count == 0:
		hbox.add_child(UIKit.label("未装配", UIKit.F_SMALL, UIKit.C_DISABLE))
		hbox.add_child(UIKit.spacer())
		var equip := UIKit.quiet_button("装配", Vector2(54, 26), accent)
		UIKit.set_readable_font(equip, 10)
		equip.tooltip_text = "选择一门被动功法"
		equip.pressed.connect(_request_passive)
		hbox.add_child(equip)
	else:
		var first_sid := ""
		var names: Array[String] = []
		for sid in loadout:
			if String(sid) == "":
				continue
			if first_sid == "":
				first_sid = String(sid)
			names.append(SkillDB.get_skill_name(String(sid)))
		hbox.add_child(UIKit.icon_node(
			String(SkillDB.get_skill(first_sid).get("icon", "")),
			SkillDB.get_skill_name(first_sid), "skill", Vector2(28, 28)))
		hbox.add_child(UIKit.readable_label("、".join(names), UIKit.F_BODY, Color(0.96, 0.92, 0.82)))
		hbox.add_child(UIKit.spacer())
		var change := UIKit.quiet_button("更换", Vector2(44, 24), accent)
		UIKit.set_readable_font(change, 10)
		change.tooltip_text = "更换被动功法"
		change.pressed.connect(_request_passive)
		hbox.add_child(change)
		var off := UIKit.quiet_button("卸下", Vector2(44, 24), accent)
		UIKit.set_readable_font(off, 10)
		off.tooltip_text = "卸下当前被动"
		off.pressed.connect(_on_unequip.bind(first_sid, false))
		hbox.add_child(off)
	return row


# ===================== 装配选择器 =====================

func _close_assign() -> void:
	_assign_slot = -1
	_assign_passive = false
	_close_active_slot_popup()
	_refresh_content()


func _request_slot(index: int) -> void:
	_close_active_slot_popup()
	_assign_slot = index
	_assign_passive = false
	_refresh_content()
	_scroll_to_loadout()


## 从功法行 / 详情点「装配」：弹出四个键位槽，选槽即放
func _request_key_for(sid: String) -> void:
	_assign_slot = -1
	_assign_passive = false
	_refresh_content()
	_open_active_slot_popup(sid)


func _request_passive() -> void:
	_close_active_slot_popup()
	_assign_slot = -1
	_assign_passive = true
	_refresh_content()
	_scroll_to_loadout()


## 选择器在「当前搭配」区：从下面功法行点装配时把滚动条带回顶部，
## 否则玩家会以为按钮没反应。
func _scroll_to_loadout() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var scroll := content.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0


func _make_picker_shell(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := UIKit.accent_card_style(_accent(), 0.58, 0.26, 6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	var body := UIKit.vbox(6)
	body.name = "PickerBody"
	panel.add_child(body)
	var head := UIKit.hbox(8)
	body.add_child(head)
	head.add_child(UIKit.label(title, UIKit.F_BODY, _accent()))
	head.add_child(UIKit.spacer())
	var cancel := UIKit.quiet_button("取消", Vector2(54, 26), _accent())
	UIKit.set_readable_font(cancel, 10)
	cancel.pressed.connect(_close_assign)
	head.add_child(cancel)
	return panel


func _learned_active_ids() -> Array:
	var out: Array = []
	for sid in CharacterData.learned_skills:
		if SkillDB.is_type_active(String(sid)):
			out.append(String(sid))
	return out


func _learned_passive_ids() -> Array:
	var out: Array = []
	for sid in CharacterData.learned_skills:
		if String(SkillDB.get_skill(String(sid)).get("skill_type", "")) == SkillDB.TYPE_PASSIVE:
			out.append(String(sid))
	return out


func _active_sid_at(index: int) -> String:
	if index >= 0 and index < CharacterData.active_skill_loadout.size():
		return String(CharacterData.active_skill_loadout[index])
	return ""


func _slot_key_for(sid: String) -> String:
	var idx := CharacterData.active_skill_loadout.find(sid)
	return _slot_key_text(idx) if idx >= 0 else ""


func _make_slot_picker(index: int) -> Control:
	var current := _active_sid_at(index)
	var panel := _make_picker_shell("为 [%s] 选择主动功法" % _slot_key_text(index))
	var body := panel.get_node("PickerBody") as VBoxContainer
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	var ids := _learned_active_ids()
	if ids.is_empty():
		body.add_child(UIKit.label("还没有学会主动功法。", UIKit.F_SMALL, UIKit.C_DISABLE))
	for raw in ids:
		var sid := String(raw)
		var key := _slot_key_for(sid)
		var prefix := ("[%s] " % key) if key != "" else ""
		var suffix := "　← 当前" if sid == current else ""
		var btn := UIKit.button("%s%s%s" % [prefix, SkillDB.get_skill_name(sid), suffix],
			Vector2(0, 30), "default", _accent())
		UIKit.set_readable_font(btn, 11)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_assign_active_to_slot.bind(index, sid))
		grid.add_child(btn)
	if current != "":
		var clear := UIKit.quiet_button("清空 [%s] · %s" % [
			_slot_key_text(index), SkillDB.get_skill_name(current)], Vector2(0, 28), _accent())
		UIKit.set_readable_font(clear, 10)
		clear.alignment = HORIZONTAL_ALIGNMENT_LEFT
		clear.pressed.connect(_clear_active_slot.bind(index))
		body.add_child(clear)
	return panel


## 技能 → 键位：弹出四槽面板。空槽直接装；有技能的槽先卸下原技能再装。
func _open_active_slot_popup(sid: String) -> void:
	_close_active_slot_popup()
	var accent := _accent()
	var overlay := Control.new()
	overlay.name = "ActiveSlotPopup"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 30
	add_child(overlay)
	overlay.add_child(UIKit.dim_rect())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ActiveSlotPopupPanel"
	panel.custom_minimum_size = Vector2(860.0, 0.0)
	var sb := UIKit.accent_card_style(accent, 0.76, 0.40, 8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := UIKit.vbox(8)
	panel.add_child(v)
	var head := UIKit.hbox(8)
	v.add_child(head)
	head.add_child(UIKit.label("把「%s」装到哪个键位？" % SkillDB.get_skill_name(sid),
		UIKit.F_SECTION, accent))
	head.add_child(UIKit.spacer())
	var current_key := _slot_key_for(sid)
	if current_key != "":
		head.add_child(UIKit.label("当前在 [%s]" % current_key, UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	var cancel := UIKit.quiet_button("取消", Vector2(54, 26), accent)
	UIKit.set_readable_font(cancel, 10)
	cancel.pressed.connect(_close_active_slot_popup)
	head.add_child(cancel)

	var slots := UIKit.hbox(8)
	v.add_child(slots)
	for i in MAX_ACTIVE:
		slots.add_child(_make_popup_slot_card(i, sid))
	v.add_child(UIKit.label("点空槽直接装入；点有技能的槽会先卸下原技能，再装入所选功法。",
		UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	if current_key != "":
		v.add_child(UIKit.label("所选功法已在 [%s]：换到别的槽会从原键位移过来。"
			% current_key, UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	_assign_popup = overlay


func _make_popup_slot_card(index: int, sid: String) -> Button:
	var occupant := _active_sid_at(index)
	var accent := _accent()
	var key := _slot_key_text(index)
	var btn := Button.new()
	btn.name = "AssignSlot_%d" % index
	btn.custom_minimum_size = Vector2(0.0, 108.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = ""
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := UIKit.accent_card_style(accent, 0.70 if occupant != "" else 0.40,
		0.38 if occupant != "" else 0.16, 7)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = accent
	hover.bg_color = hover.bg_color.lightened(0.06)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.tooltip_text = "装到 [%s]" % key
	btn.pressed.connect(_equip_active_to_slot_replace.bind(index, sid))

	var box := UIKit.vbox(4)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10.0
	box.offset_right = -10.0
	box.offset_top = 7.0
	box.offset_bottom = -7.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)
	var top := UIKit.hbox(5)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	top.add_child(UIKit.chip("[%s]" % key, accent, 10))
	if occupant == "":
		top.add_child(UIKit.label("空位", 10, UIKit.C_DISABLE))
	else:
		top.add_child(UIKit.label("已装", 10, UIKit.C_TEXT_DIM))
		top.add_child(UIKit.spacer())
		top.add_child(UIKit.label("当前" if occupant == sid else "点此替换",
			9, accent if occupant == sid else UIKit.C_TEXT_DIM))
	var body := UIKit.hbox(6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)
	if occupant == "":
		var empty := UIKit.label("＋  空槽", 15, UIKit.C_DISABLE)
		empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.add_child(empty)
	else:
		body.add_child(UIKit.icon_node(
			String(SkillDB.get_skill(occupant).get("icon", "")),
			SkillDB.get_skill_name(occupant), "skill", Vector2(38, 38)))
		var name_lbl := UIKit.label(SkillDB.get_skill_name(occupant), 14,
			Color(0.97, 0.92, 0.82))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		body.add_child(name_lbl)
	box.add_child(UIKit.label(
		"当前键位" if occupant == sid else ("原技能会卸下" if occupant != "" else "点此装入"),
		UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	return btn


func _close_active_slot_popup() -> void:
	if _assign_popup != null and is_instance_valid(_assign_popup):
		_assign_popup.queue_free()
	_assign_popup = null


## 弹窗里选目标槽：有技能就先清空该槽；选中的技能若在别的槽也清空原槽，不做交换
func _equip_active_to_slot_replace(index: int, sid: String) -> void:
	if sid == "" or index < 0 or index >= MAX_ACTIVE:
		return
	var loadout: Array = CharacterData.active_skill_loadout
	while loadout.size() <= index:
		loadout.append("")
	var current := String(loadout[index])
	# ⚠ 教学事件必须在「槽里本来就是这门」的早退之前发：玩家若在步骤开始前就装好了，
	#   再点一次「装配 → 选同一门」会走早退、事件不发，步骤只能跳过（2026-11-12 用户报）。
	Tutorial.note("skill_slotted")
	if current == sid:
		_close_active_slot_popup()
		return
	var source := loadout.find(sid)
	if source >= 0:
		loadout[source] = ""
	loadout[index] = sid
	_trim_active_slots()
	var key := _slot_key_text(index)
	var moved := source >= 0
	_close_active_slot_popup()
	if current != "":
		set_status("已替换 [%s]：%s → %s" % [
			key, SkillDB.get_skill_name(current), SkillDB.get_skill_name(sid)])
	elif moved:
		set_status("已移动：%s → [%s]" % [SkillDB.get_skill_name(sid), key])
	else:
		set_status("已装配：%s → [%s]" % [SkillDB.get_skill_name(sid), key])
	_refresh_content()


func _make_passive_picker() -> Control:
	var panel := _make_picker_shell("选择被动功法（只能带 1 门）")
	var body := panel.get_node("PickerBody") as VBoxContainer
	var ids := _learned_passive_ids()
	if ids.is_empty():
		body.add_child(UIKit.label("还没有学会被动功法。", UIKit.F_SMALL, UIKit.C_DISABLE))
	for raw in ids:
		var sid := String(raw)
		var current := not CharacterData.passive_skill_loadout.is_empty() \
			and String(CharacterData.passive_skill_loadout[0]) == sid
		var btn := UIKit.button("%s%s" % [SkillDB.get_skill_name(sid),
			"　← 当前" if current else ""], Vector2(0, 30), "default", _accent())
		UIKit.set_readable_font(btn, 11)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_assign_passive_to.bind(sid))
		body.add_child(btn)
	if not CharacterData.passive_skill_loadout.is_empty():
		var clear := UIKit.quiet_button("清空被动槽", Vector2(0, 28), _accent())
		UIKit.set_readable_font(clear, 10)
		clear.alignment = HORIZONTAL_ALIGNMENT_LEFT
		clear.pressed.connect(_assign_passive_to.bind(""))
		body.add_child(clear)
	return panel


## 给指定键位放技能：目标键已有功法时互换；原来没装则直接占位
func _assign_active_to_slot(index: int, sid: String) -> void:
	if sid == "" or index < 0 or index >= MAX_ACTIVE:
		return
	var loadout: Array = CharacterData.active_skill_loadout
	while loadout.size() <= index:
		loadout.append("")
	var current := String(loadout[index])
	if current == sid:
		_close_assign()
		return
	var source := loadout.find(sid)
	if source >= 0:
		loadout[source] = current
		loadout[index] = sid
		set_status("已交换 [%s] 与 [%s]" % [_slot_key_text(source), _slot_key_text(index)])
	else:
		loadout[index] = sid
		if current != "":
			set_status("已替换 [%s]：%s → %s" % [
				_slot_key_text(index), SkillDB.get_skill_name(current),
				SkillDB.get_skill_name(sid)])
		else:
			set_status("已装配：%s → [%s]" % [
				SkillDB.get_skill_name(sid), _slot_key_text(index)])
	_trim_active_slots()
	_close_assign()


func _clear_active_slot(index: int) -> void:
	var sid := _active_sid_at(index)
	if sid == "":
		return
	CharacterData.active_skill_loadout[index] = ""
	_trim_active_slots()
	set_status("已卸下 [%s]：%s" % [_slot_key_text(index), SkillDB.get_skill_name(sid)])
	_close_assign()


func _assign_passive_to(sid: String) -> void:
	if sid == "":
		CharacterData.passive_skill_loadout.clear()
		set_status("已清空被动槽")
	else:
		CharacterData.passive_skill_loadout = [sid]
		set_status("已装配被动：%s" % SkillDB.get_skill_name(sid))
	_close_assign()


func _trim_active_slots() -> void:
	var loadout: Array = CharacterData.active_skill_loadout
	while not loadout.is_empty() and String(loadout[loadout.size() - 1]) == "":
		loadout.pop_back()


# ===================== 分组 =====================

func _make_group_header(group: Dictionary, is_open: bool) -> Control:
	var gid := String(group.get("group_id", ""))
	var gname := String(group.get("group_name", ""))
	var total := int(group.get("total", 0))
	var learned := int(group.get("learned", 0))

	var accent := _accent()
	var row := PanelContainer.new()
	var sb := UIKit.accent_card_style(accent, 0.58 if learned > 0 else 0.38,
		0.30 if learned > 0 else 0.14, 6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)

	var btn := UIKit.quiet_button("%s %s　·　已习得 %d / %d" % [
		"▾" if is_open else "▸", gname, learned, total], Vector2(0, 34), accent)
	btn.add_theme_font_size_override("font_size", UIKit.F_SECTION)
	btn.add_theme_color_override("font_color", accent if learned > 0 else UIKit.C_TEXT_DIM)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_group_toggled.bind(gid))
	row.add_child(btn)
	return row


func _on_group_toggled(group_id: String) -> void:
	_expanded[group_id] = not bool(_expanded.get(group_id, false))
	_refresh_content()


# ===================== 单条功法（紧凑单行 + 点击展开） =====================
## 一屏能看三倍数量：默认只显示「图标 + 名称 + 关键数值」一行（约 40px），
## 点整行才展开描述、获取途径与装配按钮。
## 美术：图标仍走 UIKit.icon_node（填 skill_db.gd 的 icon 字段即换成贴图）

func _make_skill_row(skill: Dictionary) -> Control:
	var sid := String(skill.get("skill_id", ""))
	var learned := sid in CharacterData.learned_skills
	var is_active := String(skill.get("skill_type", "")) == SkillDB.TYPE_ACTIVE
	var is_open := bool(_expanded_skills.get(sid, false))

	var wrap := UIKit.vbox(2)
	wrap.add_child(_make_skill_head(skill, sid, learned, is_active, is_open))
	if is_open:
		wrap.add_child(_make_skill_detail(skill, sid, learned, is_active))
	return wrap


## 紧凑行：整行可点（透明按钮铺满），内容全部 MOUSE_FILTER_IGNORE 保证点击落到按钮上
func _make_skill_head(skill: Dictionary, sid: String, learned: bool, is_active: bool, is_open: bool) -> Control:
	var accent := _accent()
	var row := PanelContainer.new()
	var sb := UIKit.accent_card_style(accent if learned else UIKit.C_SLOT_BORDER,
		0.54 if learned else 0.40, 0.26 if learned else 0.12, 5)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	row.add_theme_stylebox_override("panel", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.border_color = accent
	hov.bg_color = hov.bg_color.lightened(0.05)

	var hb := UIKit.hbox(6)
	row.add_child(hb)

	var click := Button.new()
	UIKit.attach_click_sfx(click)
	click.flat = true
	click.focus_mode = Control.FOCUS_NONE
	click.custom_minimum_size = Vector2(0, 38)
	click.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click.mouse_entered.connect(func() -> void:
		row.add_theme_stylebox_override("panel", hov))
	click.mouse_exited.connect(func() -> void:
		row.add_theme_stylebox_override("panel", sb))
	click.pressed.connect(_on_skill_row_toggled.bind(sid))
	hb.add_child(click)

	var inner := UIKit.hbox(6)
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 8.0
	inner.offset_right = -8.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	click.add_child(inner)

	var state_bar := ColorRect.new()
	state_bar.color = Color(accent.r, accent.g, accent.b, 0.9) if learned else Color(0.3, 0.3, 0.34, 0.7)
	state_bar.custom_minimum_size = Vector2(2, 0)
	state_bar.size_flags_vertical = Control.SIZE_FILL
	state_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(state_bar)
	inner.add_child(UIKit.label("▾" if is_open else "▸", UIKit.F_SMALL, accent))
	var icon := UIKit.icon_node(
		String(skill.get("icon", "")), String(skill.get("skill_name", "")), "skill", Vector2(30, 30)
	)
	inner.add_child(icon)
	inner.add_child(UIKit.label("%s　［%s］" % [
		String(skill.get("skill_name", "")),
		"主动" if is_active else "被动",
	], UIKit.F_BODY, accent if learned else UIKit.C_TEXT))
	if CharacterData.is_skill_new(sid):
		inner.add_child(UIKit.chip("新", UIKit.C_DANGER, 9))
	if learned:
		inner.add_child(UIKit.chip("已习得", UIKit.C_OK, 9))
	elif not is_active:
		inner.add_child(UIKit.label("未习得", UIKit.F_SMALL, UIKit.C_DISABLE))

	var spacer := UIKit.spacer()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(spacer)

	if is_active:
		var cost := SkillDB.get_skill_cost(sid)
		inner.add_child(UIKit.label("%s · CD %.1fs · 物 ×%.2f / 法 ×%.2f" % [
			_cost_text(cost),
			float(cost.get("cooldown", 0.0)),
			SkillDB.get_phys_coeff(sid),
			SkillDB.get_spell_coeff(sid),
		], UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	if learned:
		var equipped := sid in (CharacterData.active_skill_loadout if is_active
			else CharacterData.passive_skill_loadout)
		var quick := UIKit.button("卸下" if equipped else "装配",
			Vector2(64, 28), "quiet" if equipped else "default", _accent())
		UIKit.set_readable_font(quick, 10)
		quick.tooltip_text = "卸下这门功法" if equipped else (
			"选择要放到的快捷键" if is_active else "选择被动槽")
		quick.pressed.connect(_on_quick_action.bind(sid, is_active))
		hb.add_child(quick)
	return row


## 功法行右侧的快捷装配/卸下：主动会先问键位，被动直接进唯一槽
func _on_quick_action(sid: String, is_active: bool) -> void:
	var equipped := sid in (CharacterData.active_skill_loadout if is_active
		else CharacterData.passive_skill_loadout)
	if equipped:
		_on_unequip(sid, is_active)
	elif is_active:
		_request_key_for(sid)
	else:
		_request_passive()


## 展开详情：描述、完整系数、获取途径、装配按钮
func _make_skill_detail(skill: Dictionary, sid: String, learned: bool, is_active: bool) -> Control:
	var margin := MarginContainer.new()
	margin.name = "SkillDetail_" + sid
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 4)

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(_accent(), 0.44, 0.18, 6))
	margin.add_child(row)

	var hb := UIKit.hbox(10)
	row.add_child(hb)

	var info := UIKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	# 效果说明：**全部由招式数据现算**（射程/张角/消耗/冷却/系数/刀痕/格挡…）
	# ⚠ 不要再在这里手写数值 —— 改 move_db 的招式表，这里会自动跟着变
	for item in SkillDB.get_effect_lines(sid):
		info.add_child(_detail_line(String(item.get("text", "")),
			UIKit.C_ACCENT if bool(item.get("accent", false)) else UIKit.C_TEXT_DIM))
	if not learned:
		# 无来源 BOSS 时明确标注待定，避免显示成「先击杀 」
		info.add_child(_detail_line(_acquire_text(skill), UIKit.C_WARN))
	else:
		info.add_child(_detail_line(_source_text(skill), UIKit.C_TEXT_DIM))

	hb.add_child(UIKit.spacer())

	if not learned:
		hb.add_child(UIKit.label("未习得", UIKit.F_SMALL, UIKit.C_DISABLE))
		return margin

	var equipped := sid in (CharacterData.active_skill_loadout if is_active else CharacterData.passive_skill_loadout)
	if equipped:
		var btn := UIKit.quiet_button("卸下", Vector2(72, 30), _accent())
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(_on_unequip.bind(sid, is_active))
		hb.add_child(btn)
	else:
		var btn := UIKit.primary_button("装配", Vector2(80, 32), _accent())
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if is_active:
			btn.pressed.connect(_request_key_for.bind(sid))
		else:
			btn.pressed.connect(_request_passive)
		hb.add_child(btn)
	return margin


## 详情正文必须自己换行：被动「负阴抱阳」这类整段机制说明，Label 不设
## autowrap 会把 HBox 的最小宽度顶到整行文本，整块面板随之横向撑变形。
func _detail_line(text: String, color: Color) -> Label:
	# 规则文案里的 ** 强调标记在普通 Label 上不会渲染，留着就是一堆星号
	var l := UIKit.readable_label(text.replace("**", ""), UIKit.F_SMALL, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2.ZERO
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _on_skill_row_toggled(skill_id: String) -> void:
	var opening := not bool(_expanded_skills.get(skill_id, false))
	_expanded_skills[skill_id] = opening
	# 展开详情 = 玩家已经看过这门新功法，清掉「新」标记（全部清完后主城 Y 红圈消失）
	if opening:
		CharacterData.mark_skill_seen(skill_id)
	_refresh_content()


## 消耗文案：按 cost_kind 生成（列表行的紧凑版；详情用 SkillDB 现算的完整版）
## ⚠ 与 SkillDB._cost_text 共用同一套口径（SkillDB.cost_resource_text），
##   包括一剑开天双形态的「精力全部 / 精力与灵力全部」—— 不要在这里另写分支
func _cost_text(cost: Dictionary) -> String:
	return SkillDB.cost_resource_text(cost)


## 获取途径文案：没有来源 BOSS 时明确标注待定，避免显示成「先击杀 」
func _acquire_text(skill: Dictionary) -> String:
	var boss_id := String(skill.get("source_boss_id", ""))
	if boss_id == "":
		return "获取：待定（对应 BOSS 尚未设计）"
	return "获取：先击杀 %s，再首次通关其塔投影" % WorldDB.get_boss_name(boss_id)


## 已习得时展示来源：哪个 BOSS 的哪一招
func _source_text(skill: Dictionary) -> String:
	var boss_id := String(skill.get("source_boss_id", ""))
	if boss_id == "":
		return "来源：通用招式（非 BOSS 专属）"
	return "来源：%s 的招式" % WorldDB.get_boss_name(boss_id)


func _group_has_array(skills: Array) -> bool:
	for s in skills:
		if bool((s as Dictionary).get("array", false)):
			return true
	return false


func _on_equip(skill_id: String, is_active: bool) -> void:
	if is_active:
		var loadout: Array = CharacterData.active_skill_loadout
		if skill_id in loadout:
			return
		var empty_index := -1
		for i in MAX_ACTIVE:
			if _active_sid_at(i) == "":
				empty_index = i
				break
		if empty_index < 0:
			set_status("主动功法 4 个键位都满了，请先卸下一门", UIKit.C_WARN)
			return
		while loadout.size() <= empty_index:
			loadout.append("")
		loadout[empty_index] = skill_id
		set_status("已装配：%s → [%s]" % [
			SkillDB.get_skill_name(skill_id), _slot_key_text(empty_index)])
	else:
		if CharacterData.passive_skill_loadout.size() >= MAX_PASSIVE:
			set_status("被动功法只能带一个，请先卸下当前被动", UIKit.C_WARN)
			return
		if skill_id in CharacterData.passive_skill_loadout:
			return
		CharacterData.passive_skill_loadout.append(skill_id)
		set_status("已装配被动：%s" % SkillDB.get_skill_name(skill_id))
	_refresh_content()


func _on_unequip(skill_id: String, is_active: bool) -> void:
	if is_active:
		var loadout: Array = CharacterData.active_skill_loadout
		var idx := loadout.find(skill_id)
		if idx >= 0:
			loadout[idx] = ""
			_trim_active_slots()
	else:
		CharacterData.passive_skill_loadout.erase(skill_id)
	set_status("已卸下：%s" % SkillDB.get_skill_name(skill_id))
	_refresh_content()
