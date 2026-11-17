class_name CodexView
extends HBoxContainer
## 万界图鉴：左侧分类、右侧条目列表。
## 未解锁只显示名字与获取方式；解锁后追加图标、品质标签与详细资料。

const CATEGORY_WIDTH := 116.0
const PAGE_WIDTH := 800.0
const PAGE_MIN_HEIGHT := 520.0
const ICON_BOX := 64.0
const ICON_SIZE := Vector2(56.0, 56.0)

var _category_index := 0
var _category_buttons: Array = []
var _summary: Label
## 二级分类（装备部件 / 法宝类型 / 材料境界 / BOSS 来源）
var _sub_bar: HBoxContainer
var _sub_buttons: Array = []
var _sub_id: String = CodexDB.SUB_ALL
## 右侧列表的外层滚动：BOSS 详情页要把它关掉，改成只有文字自己滚
var _scroll: ScrollContainer
var _list_box: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, PAGE_MIN_HEIGHT)
	_build()
	refresh()


func _build() -> void:
	var left := UIKit.vbox(8)
	left.custom_minimum_size = Vector2(CATEGORY_WIDTH, 0.0)
	left.add_child(UIKit.label("卷目", 10, Color(0.86, 0.78, 0.52, 0.8)))
	for i in CodexDB.categories().size():
		var btn := UIKit.tab_button("", Vector2(CATEGORY_WIDTH, 42.0),
			UIKit.facility_style("codex").get("accent", UIKit.C_ACCENT))
		UIKit.set_click_sfx(btn, "ui_tab")
		btn.pressed.connect(_show_category.bind(i))
		left.add_child(btn)
		_category_buttons.append(btn)
	left.add_child(UIKit.spacer())
	add_child(left)

	var right := UIKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(PAGE_WIDTH, 0.0)
	add_child(right)

	_summary = UIKit.readable_note("")
	right.add_child(_summary)

	_sub_bar = UIKit.hbox(6)
	_sub_bar.name = "CodexSubBar"
	right.add_child(_sub_bar)

	var scroll := ScrollContainer.new()
	scroll.name = "CodexScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_scroll = scroll

	_list_box = UIKit.vbox(10)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_box.custom_minimum_size = Vector2(PAGE_WIDTH - 24.0, 0.0)
	scroll.add_child(_list_box)


func refresh() -> void:
	if _category_buttons.is_empty():
		return
	_category_index = clampi(_category_index, 0, CodexDB.categories().size() - 1)
	for i in _category_buttons.size():
		var c: Dictionary = CodexDB.categories()[i]
		var cid := String(c.get("id", ""))
		var btn: Button = _category_buttons[i]
		# 试炼卡牌没有「获得」概念：只写总数，否则 116px 的按钮放不下「卡牌 229/229」
		if cid == CodexDB.CAT_ROGUE_CARD:
			btn.text = "%s %d" % [String(c.get("title", "")),
				CodexDB.category_entries(cid).size()]
		else:
			btn.text = "%s %d/%d" % [
				String(c.get("title", "")),
				CodexDB.unlocked_count(cid),
				CodexDB.category_entries(cid).size(),
			]
	_sync_category_buttons()
	_render_list()


func _show_category(index: int) -> void:
	if index < 0 or index >= CodexDB.categories().size():
		return
	_category_index = index
	_sub_id = CodexDB.SUB_ALL
	_boss_detail_id = ""
	_sync_category_buttons()
	_render_list()


func _sync_category_buttons() -> void:
	for i in _category_buttons.size():
		UIKit.set_tab_selected(_category_buttons[i], i == _category_index)


func _render_sub_bar(cid: String) -> void:
	if _sub_bar == null:
		return
	UIKit.clear_children(_sub_bar)
	_sub_buttons.clear()
	var subs := CodexDB.subcategories(cid)
	if subs.size() <= 1:
		_sub_bar.visible = false
		_sub_id = CodexDB.SUB_ALL
		return
	_sub_bar.visible = true
	var valid := false
	for raw in subs:
		var sub: Dictionary = raw
		var sid := String(sub.get("id", CodexDB.SUB_ALL))
		if sid == _sub_id:
			valid = true
		var btn := UIKit.tab_button("%s %d" % [
			String(sub.get("title", sid)),
			CodexDB.category_entries(cid, sid).size(),
		], Vector2(108.0, 30.0), UIKit.facility_style("codex").get("accent", UIKit.C_ACCENT))
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		UIKit.set_click_sfx(btn, "ui_tab")
		btn.pressed.connect(_show_sub.bind(sid))
		_sub_bar.add_child(btn)
		_sub_buttons.append({"id": sid, "btn": btn})
	if not valid:
		_sub_id = CodexDB.SUB_ALL
	_sync_sub_buttons()


func _show_sub(sid: String) -> void:
	_sub_id = sid
	if String((CodexDB.categories()[_category_index] as Dictionary).get("id", "")) == CodexDB.CAT_BOSS:
		_boss_detail_id = ""
	_sync_sub_buttons()
	_render_list()


func _sync_sub_buttons() -> void:
	for raw in _sub_buttons:
		var item: Dictionary = raw
		UIKit.set_tab_selected(item["btn"], String(item["id"]) == _sub_id)


func _render_list() -> void:
	if _list_box == null:
		return
	# 列表页恢复整页滚动（详情页会把它关掉）
	if _scroll != null:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	UIKit.clear_children(_list_box)
	var cat: Dictionary = CodexDB.categories()[_category_index]
	var cid := String(cat.get("id", ""))
	if cid == CodexDB.CAT_BOSS:
		_render_sub_bar(cid)
		_render_boss()
		return
	if cid == CodexDB.CAT_ROGUE_CARD:
		_render_sub_bar(cid)
		_render_rogue_cards()
		return
	_render_sub_bar(cid)
	var entries := CodexDB.category_entries(cid, _sub_id)
	_summary.text = "%s图鉴　已解锁 %d / %d　　全图鉴 %d / %d" % [
		String(cat.get("title", "")),
		CodexDB.unlocked_count(cid, _sub_id), entries.size(),
		CodexDB.unlocked_count(), CodexDB.total_count(),
	]
	for e in entries:
		_list_box.add_child(_make_card(e as Dictionary))
	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0.0, 18.0)
	_list_box.add_child(bottom)


# ===================== 试炼卡牌页（2026-11-09）=====================
## 按流派分组的卡片清单：未解锁流派整组压暗且只显示「第 N 层解锁」，
## 已解锁流派完整展示效果与叠加上限。数据全从 RogueDB 现生成，图鉴不存第二份。

func _render_rogue_cards() -> void:
	var groups := CodexDB.rogue_card_groups()
	var shown := 0
	for raw in groups:
		var g: Dictionary = raw
		var cards: Array = g.get("cards", [])
		if _sub_id != CodexDB.SUB_ALL:
			var filtered: Array = []
			for c in cards:
				if String((c as Dictionary).get("rarity", "")) == _sub_id:
					filtered.append(c)
			cards = filtered
		if cards.is_empty():
			continue
		shown += cards.size()
		_add_rogue_group(g, cards)
	_summary.text = "试炼卡牌　本页 %d 张　·　局内三选一抽取 · 同种卡可叠层，传说固定 1 层" % shown
	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0.0, 18.0)
	_list_box.add_child(bottom)


func _add_rogue_group(g: Dictionary, cards: Array) -> void:
	var unlocked := bool(g.get("unlocked", true))
	var accent: Color = UIKit.facility_style("codex").get("accent", UIKit.C_ACCENT)
	var head := UIKit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := String(g.get("title", ""))
	if String(g.get("family", "")) == "generic":
		title += " · 全部流派"
	head.add_child(UIKit.label(title, UIKit.F_SECTION,
		accent if unlocked else UIKit.C_TEXT_DIM))
	head.add_child(UIKit.label("%d 张" % cards.size(), UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	_list_box.add_child(head)

	for raw in cards:
		_list_box.add_child(_make_rogue_card(raw as Dictionary, unlocked,
			int(g.get("unlock_floor", 0))))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 8.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_box.add_child(gap)


func _make_rogue_card(card: Dictionary, unlocked: bool, unlock_floor: int) -> Control:
	var rarity := String(card.get("rarity", "common"))
	var col: Color = RogueDB.RARITY_COLOR.get(rarity, UIKit.C_TEXT_DIM)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIKit.accent_card_style(col if unlocked else UIKit.C_SLOT_BORDER,
		0.80 if unlocked else 0.52, 0.34 if unlocked else 0.12, 6)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", sb)

	var row := UIKit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var bar := ColorRect.new()
	bar.color = Color(col.r, col.g, col.b, 0.9) if unlocked \
		else Color(0.30, 0.30, 0.34, 0.5)
	bar.custom_minimum_size = Vector2(2.0, 0.0)
	bar.size_flags_vertical = Control.SIZE_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	var info := UIKit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var head := UIKit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UIKit.label(String(card.get("name", "")), UIKit.F_BODY,
		col if unlocked else Color(0.55, 0.55, 0.60, 1.0)))
	if unlocked:
		head.add_child(UIKit.label("%s · 最多 %d 层" % [
			String(RogueDB.RARITY_NAME.get(rarity, rarity)),
			int(card.get("cap", 1))], UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	info.add_child(head)

	if unlocked:
		info.add_child(_wrapped(String(card.get("desc", "")), UIKit.F_SMALL, UIKit.C_TEXT))
	else:
		info.add_child(_wrapped("该流派尚未开放 · 历史最高到达第 %d 层后解锁" % unlock_floor,
			UIKit.F_SMALL, UIKit.C_DISABLE))
	return panel


# ===================== BOSS 页 =====================
## 一张卡一个 BOSS：立绘 + 名字 + 位面；点开换到详情（同一块区域，不弹窗）。

## 卡面按原画 2:3 直接铺满，不裁切构图
const BOSS_CARD_SIZE := Vector2(226.0, 372.0)
const BOSS_ART_SIZE := Vector2(200.0, 300.0)
const BOSS_DETAIL_ART := Vector2(300.0, 450.0)

var _boss_detail_id := ""


func _boss_accent() -> Color:
	return UIKit.facility_style("codex").get("accent", UIKit.C_ACCENT)


func _render_boss() -> void:
	var bosses := CodexDB.boss_entries(_sub_id)
	# 未击败只影响卡面亮度：资料照常可查（2026-10-28 用户定）
	_summary.text = "BOSS 图鉴　已击败 %d / %d　　未击败的卡面压暗，资料一样能看" % [
		CodexDB.unlocked_count(CodexDB.CAT_BOSS, _sub_id), bosses.size(),
	]
	if _boss_detail_id != "" and CodexDB.boss_entry(_boss_detail_id).is_empty():
		_boss_detail_id = ""
	if _boss_detail_id != "":
		_render_boss_detail(CodexDB.boss_entry(_boss_detail_id))
		return
	if bosses.is_empty():
		_list_box.add_child(UIKit.readable_note("本分类暂无首领"))
		return

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_box.add_child(grid)
	for e in bosses:
		grid.add_child(_make_boss_card(e as Dictionary))
	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0.0, 18.0)
	_list_box.add_child(bottom)


func _make_boss_card(entry: Dictionary) -> Control:
	var boss_id := String(entry.get("id", ""))
	var unlocked := CodexDB.is_boss_unlocked(boss_id)
	var accent := _boss_accent()

	var card := PanelContainer.new()
	card.custom_minimum_size = BOSS_CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_PASS   # PASS：点击能收，滚轮还能交给外层 ScrollContainer
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", UIKit.accent_card_style(
		accent, 0.88 if unlocked else 0.66, 0.42 if unlocked else 0.14, 8))
	card.gui_input.connect(_on_boss_card_input.bind(boss_id))

	var box := UIKit.vbox(6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(box)

	var art := TextureRect.new()
	art.custom_minimum_size = BOSS_ART_SIZE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _load_tex(String(entry.get("portrait", "")))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		art.modulate = Color(0.22, 0.24, 0.30, 1.0)
	box.add_child(art)

	var name_label := UIKit.label(String(entry.get("name", "")), UIKit.F_SECTION,
		accent if unlocked else Color(0.56, 0.56, 0.62, 1.0))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var sub := UIKit.label(String(entry.get("subtitle", "")),
		UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sub)
	return card


func _on_boss_card_input(event: InputEvent, boss_id: String) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	GameState.play_ui("ui_click")
	_boss_detail_id = boss_id
	_render_list()


func _render_boss_detail(entry: Dictionary) -> void:
	var boss_id := String(entry.get("id", ""))
	var unlocked := CodexDB.is_boss_unlocked(boss_id)
	var world_boss := bool(entry.get("world_boss", false))
	var accent := _boss_accent()

	# 详情页：整页不再跟着滚 —— 返回按钮与左侧立绘钉在原位，只有右侧文字自己滚
	if _scroll != null:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var back := UIKit.button("← 返回 BOSS 列表", Vector2(176.0, 34.0))
	back.add_theme_font_size_override("font_size", 15)
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func() -> void:
		_boss_detail_id = ""
		_render_list())
	_list_box.add_child(back)

	var row := UIKit.hbox(16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_box.add_child(row)

	# 左：立绘（大图），未解锁压暗
	var frame := PanelContainer.new()
	frame.custom_minimum_size = BOSS_DETAIL_ART
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UIKit.slot_style(true, accent, 2))
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _load_tex(String(entry.get("portrait", "")))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		art.modulate = Color(0.22, 0.24, 0.30, 1.0)
	frame.add_child(art)
	row.add_child(frame)

	# 右：资料 —— 自己一层滚动（外层整页滚动已在上面关掉，不构成嵌套滚动）
	var info_scroll := ScrollContainer.new()
	info_scroll.name = "BossInfoScroll"
	info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(info_scroll)
	var info := UIKit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(400.0, 0.0)
	info_scroll.add_child(info)

	var title := UIKit.label("%s　·　%s" % [String(entry.get("name", "")),
		String(entry.get("epithet", ""))], UIKit.F_TITLE, accent if unlocked else UIKit.C_TEXT_DIM)
	info.add_child(title)
	info.add_child(_wrapped(String(entry.get("subtitle", "")), UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	var tags: Array = entry.get("tags", [])
	if not tags.is_empty():
		info.add_child(_wrapped("　".join(PackedStringArray(tags)), UIKit.F_SMALL, accent))

	# 未击败不再拦截内容：整张卡照常展开（机制 / 状态 / 属性 / 招式 / 掉落 / 功法），
	# 只是卡面与标题压暗（2026-10-28 用户定：资料不需要击败就能看）

	# ---- 模块 1：专属机制（只讲机制，不列数据；数据在属性 / 招式 / 状态模块里）----
	_section(info, "专属机制 · %s" % String(entry.get("mechanic_title", "")), accent)
	info.add_child(_wrapped(String(entry.get("mechanic", "")), UIKit.F_BODY, UIKit.C_TEXT))
	var points: Array = entry.get("mechanic_points", [])
	for p in points:
		info.add_child(_wrapped("　· " + String(p), UIKit.F_SMALL, UIKit.C_TEXT_DIM))

	# ---- 模块 2：状态（只列它自己招式产生的状态，不解释名词、不讲玩家侧）----
	# 全部从招式表现查 + DebuffDB / BuffDB 现生成，卡片里不手写任何状态数字
	var states := CodexDB.boss_status_info(boss_id)
	_section(info, "状态", accent)
	if states.is_empty():
		info.add_child(_wrapped("该首领不施加状态；威胁来自招式判定与场地。",
			UIKit.F_SMALL, UIKit.C_DISABLE))
	for s in states:
		var sr: Dictionary = s
		var good := String(sr.get("kind", "")) == "good"
		var srcs := ", ".join(PackedStringArray(sr.get("sources", []) as Array))
		var head := "%s「%s」" % ["它自身" if good else "命中后挂上", String(sr.get("name", ""))]
		var t := float(sr.get("time", 0.0))
		if t > 0.0:
			head += "　%.0f 秒" % t
		info.add_child(_wrapped("　" + head + " · " + String(sr.get("effect", "")),
			UIKit.F_BODY, BuffDB.color(String(sr.get("id", ""))) if good
				else DebuffDB.color(String(sr.get("id", "")))))
		if srcs != "":
			info.add_child(_wrapped("　　来自招式：" + srcs, UIKit.F_SMALL, UIKit.C_TEXT_DIM))

	# ---- 属性 ----
	var st := CodexDB.boss_stats(boss_id)
	_section(info, "属性", accent)
	if st.is_empty():
		info.add_child(_wrapped("（数据缺失）", UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	else:
		_kv(info, "气血", str(st.get("hp", "?")))
		_kv(info, "攻击", String(st.get("attack_text", "")))
		_kv(info, "移速", "%d / %d（一阶 / 二阶）" % [int(st.get("speed_p1", 0)), int(st.get("speed_p2", 0))])
		_kv(info, "前摇", "%.2f 秒" % float(st.get("windup", 0.0)))
		if int(st.get("radius", 0)) > 0:
			_kv(info, "受击半径", "%d 像素" % int(st.get("radius", 0)))
		_kv(info, "二阶段", "解锁新招 · 前摇缩短 · 伤害提升")

	# ---- 招式 ----
	var moves := CodexDB.boss_moves_info(boss_id)
	_section(info, "招式（%d）" % moves.size(), accent)
	for m in moves:
		var mv: Dictionary = m
		var head := "%s　·　%s%s" % [String(mv.get("name", "")), String(mv.get("kind", "")),
			"（二阶解锁）" if int(mv.get("phase", 1)) > 1 else ""]
		info.add_child(_wrapped(head, UIKit.F_BODY, UIKit.C_TEXT))

	# ---- 掉落 ----
	var drops := CodexDB.boss_drops_info(boss_id)
	_section(info, "掉落", accent)
	if drops.is_empty():
		info.add_child(_wrapped("（无登记掉落）", UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	for d in drops:
		var dr: Dictionary = d
		info.add_child(_wrapped("%s ×%d　·　掉率 %d%%" % [
			String(dr.get("name", "")), int(dr.get("count", 1)),
			int(round(float(dr.get("chance", 0.0)) * 100.0))], UIKit.F_BODY, UIKit.C_TEXT))

	# ---- 模块 5：可感悟功法（只列名字与风味；机制说明的唯一来源是功法库）----
	# 大世界首领没有塔层，标题不能写「万界塔首杀」
	var learned := CodexDB.boss_learn_info(boss_id)
	_section(info, ("可感悟功法（%d）" % learned.size()) if world_boss
		else ("万界塔首杀 · 可感悟功法（%d）" % learned.size()), accent)
	if learned.is_empty():
		info.add_child(_wrapped("（大世界首领没有塔层感悟）" if world_boss
			else "（该层没有可感悟功法）", UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	for s in learned:
		var sk: Dictionary = s
		info.add_child(_wrapped(String(sk.get("name", "")), UIKit.F_BODY, UIKit.C_TEXT))

	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0.0, 16.0)
	info.add_child(bottom)


func _section(parent: Control, text: String, color: Color) -> void:
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0.0, 6.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)
	parent.add_child(UIKit.label(text, UIKit.F_SECTION, color))


func _kv(parent: Control, key: String, value: String) -> void:
	parent.add_child(_wrapped("%s：%s" % [key, value], UIKit.F_BODY, UIKit.C_TEXT))


func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _make_card(entry: Dictionary) -> Control:
	var item_id := String(entry.get("id", ""))
	var unlocked := CharacterData.is_codex_unlocked(item_id)
	var quality := CodexDB.quality_color(entry)

	var accent: Color = UIKit.facility_style("codex").get("accent", UIKit.C_ACCENT)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIKit.accent_card_style(quality if unlocked else UIKit.C_SLOT_BORDER,
		0.84 if unlocked else 0.62, 0.40 if unlocked else 0.14, 6)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", sb)

	var row := UIKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var bar := ColorRect.new()
	bar.color = Color(quality.r, quality.g, quality.b, 0.85) if unlocked 		else Color(0.3, 0.3, 0.34, 0.5)
	bar.custom_minimum_size = Vector2(2, 0)
	bar.size_flags_vertical = Control.SIZE_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	if unlocked:
		var icon_box := PanelContainer.new()
		icon_box.custom_minimum_size = Vector2(ICON_BOX, ICON_BOX)
		icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_theme_stylebox_override("panel", UIKit.slot_style(true, quality, 2))
		icon_box.add_child(UIKit.icon_node(
			String(entry.get("icon", "")),
			String(entry.get("name", "")),
			String(entry.get("category", "")),
			ICON_SIZE,
		))
		row.add_child(icon_box)

	var info := UIKit.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var head := UIKit.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_color := quality if unlocked else Color(0.55, 0.55, 0.60, 1.0)
	head.add_child(UIKit.label(String(entry.get("name", "")), UIKit.F_SECTION, name_color))
	if unlocked:
		head.add_child(UIKit.label(CodexDB.tag_text(entry), UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	info.add_child(head)

	info.add_child(_wrapped(
		"获取方式：%s" % String(entry.get("source", "")),
		UIKit.F_SMALL,
		UIKit.C_TEXT_DIM if not unlocked else Color(0.76, 0.76, 0.82, 1.0),
	))

	if unlocked:
		for line in CodexDB.detail_lines(entry):
			info.add_child(_wrapped(String(line), UIKit.F_SMALL, UIKit.C_TEXT))

	return card


func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := UIKit.readable_label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
