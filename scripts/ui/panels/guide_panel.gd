class_name GuidePanel
extends SystemPanel
## 新手指引 —— 原初位面左上角「小书」点开后的界面（2026-10-23 用户定）
##
## 结构：左侧书签竖排切章，右侧显示该章内容。
## 全部文案在 GuideDB，本文件只负责「怎么排」。
##
## ⚠ 关于滚动：SystemPanel 的内容区本身就在 ScrollContainer 里，
##   这里再套一层内滚动（书签固定 + 右页滚动）会变成嵌套滚动。
##   做法是**关掉外层竖向滚动**，只让右侧内页滚 —— 书签就不会跟着滚走。

## 书签栏宽度
const BOOKMARK_WIDTH := 116.0
## 右页内容的最小宽度：给 Label 的自动换行一个明确上限，
## 否则 Label 在 ScrollContainer 里可能按「无限宽」排版，文字全挤成一行
const PAGE_WIDTH := 800.0
## 右页滚动区的最小高度：书签栏 8 项只有约 392 高，
## 不撑开的话滚动区会缩成一条、页面底部留一大块黑底，最后一行容易被面板框盖住
const PAGE_MIN_HEIGHT := 520.0

var _bookmark_buttons: Array = []
var _page_box: VBoxContainer
var _page_title: Label
var _current_index := 0
## 外部注入：非空时打开后直接翻到这一章（战斗里「变强之法」入口用，见 combat_arena）
var start_chapter_id: String = ""


func _init() -> void:
	panel_title = "新手指引"
	panel_hint = "点左侧书签切换 · ESC 关闭"

func facility_visual() -> Dictionary:
	return UIKit.facility_style("guide")



func panel_size() -> Vector2:
	return Vector2(1000.0, 660.0)


func _build_content() -> void:
	# 关掉外层竖向滚动：内容高度固定为面板高，滚动交给右侧内页
	var outer := content.get_parent() as ScrollContainer
	if outer != null:
		outer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var row := UIKit.hbox(14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, PAGE_MIN_HEIGHT)
	content.add_child(row)

	row.add_child(_build_bookmarks())

	# 右侧：一张「翻开的内页」——标题、卷线、滚动正文都收在纸页卡里
	var accent: Color = UIKit.facility_style("guide").get("accent", UIKit.C_ACCENT)
	var page_card := PanelContainer.new()
	page_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_card.custom_minimum_size = Vector2(0, PAGE_MIN_HEIGHT)
	var page_sb := UIKit.accent_card_style(accent, 0.72, 0.30, 8)
	page_sb.bg_color = Color(0.055, 0.050, 0.043, 0.94)
	page_card.add_theme_stylebox_override("panel", page_sb)
	row.add_child(page_card)

	var page_margin := MarginContainer.new()
	page_margin.add_theme_constant_override("margin_left", 18)
	page_margin.add_theme_constant_override("margin_right", 12)
	page_margin.add_theme_constant_override("margin_top", 10)
	page_margin.add_theme_constant_override("margin_bottom", 8)
	page_card.add_child(page_margin)

	var page_col := UIKit.vbox(6)
	page_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_margin.add_child(page_col)
	var page_head := UIKit.hbox(8)
	page_col.add_child(page_head)
	_page_title = UIKit.label("", 17, Color(0.98, 0.94, 0.84))
	page_head.add_child(_page_title)
	page_head.add_child(UIKit.spacer())
	page_head.add_child(UIKit.chip("青简", accent, 9))
	var rule := TextureRect.new()
	rule.texture = UIKit.horizontal_gradient(
		Color(accent.r, accent.g, accent.b, 0.30),
		Color(accent.r, accent.g, accent.b, 0.0))
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_col.add_child(rule)

	# 独立滚动区：页眉占掉的高度从最小高度里让出来，避免撑破面板
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, PAGE_MIN_HEIGHT - 34.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_col.add_child(scroll)

	_page_box = UIKit.vbox(10)
	_page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ⚠ 只设横向：纵向保持默认，设成 EXPAND_FILL 会被压扁导致滚不动
	_page_box.custom_minimum_size = Vector2(760.0, 0.0)
	scroll.add_child(_page_box)


## 左侧书签栏：一章一个按钮，当前章高亮（复用锻造台那套写法）
func _build_bookmarks() -> Control:
	var col := UIKit.vbox(8)
	col.custom_minimum_size = Vector2(BOOKMARK_WIDTH, 0)
	col.add_child(UIKit.label("卷目", 10, Color(0.92, 0.80, 0.50, 0.8)))
	for i in GuideDB.chapter_count():
		var btn := UIKit.tab_button(GuideDB.chapter_title(i), Vector2(BOOKMARK_WIDTH, 42),
			UIKit.facility_style("guide").get("accent", UIKit.C_ACCENT))
		# 页签用「翻页」音色，和普通点击区分开
		UIKit.set_click_sfx(btn, "ui_tab")
		btn.pressed.connect(_show_chapter.bind(i))
		col.add_child(btn)
		_bookmark_buttons.append(btn)
	col.add_child(UIKit.spacer())
	# 新手引导重看入口（2026-11-10）：老档默认不弹引导，想看只能从这里进
	# ⚠ 只重置「步骤完成标记」，不动存档里的其它进度
	var replay := UIKit.paper_button("重看新手引导", Vector2(BOOKMARK_WIDTH, 34.0))
	UIKit.set_readable_font(replay, 10)
	replay.tooltip_text = "把引导清单清零、从第 1 章重新走一遍"
	replay.pressed.connect(func() -> void:
		Tutorial.reset_all()
		close())
	col.add_child(replay)
	return col


## 切章：只重建右页（书签节点一直在，状态不丢）
func _show_chapter(index: int) -> void:
	if index < 0 or index >= GuideDB.chapter_count():
		return
	_current_index = index
	if _page_title != null:
		_page_title.text = GuideDB.chapter_title(index)
	for i in _bookmark_buttons.size():
		UIKit.set_tab_selected(_bookmark_buttons[i], i == index)
	_render_page(index)


## 把一章的条目渲染成控件
func _render_page(index: int) -> void:
	if _page_box == null:
		return
	UIKit.clear_children(_page_box)
	for b in GuideDB.chapter_blocks(index):
		var block := b as Dictionary
		var node := _make_block(String(block.get("t", "p")), String(block.get("x", "")))
		if node != null:
			_page_box.add_child(node)
	# 底部留白：滚到底时最后一行不会贴住/压到面板下沿
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 18)
	_page_box.add_child(bottom_pad)


## 单条文案 → 控件
## 返回 null 表示空文本（跳过，不占位）
func _make_block(kind: String, text: String) -> Control:
	if text == "":
		return null
	match kind:
		"s":
			# 小节标题：上方留点空，让章节内层次清楚
			var sec := UIKit.label(text, UIKit.F_SECTION, UIKit.C_ACCENT)
			sec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sec.custom_minimum_size = Vector2(0, 0)
			var wrap := MarginContainer.new()
			wrap.add_theme_constant_override("margin_top", 8)
			wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrap.add_child(sec)
			return wrap
		"k":
			return _line("▸ " + text, UIKit.F_BODY, UIKit.C_ACCENT)
		"b":
			return _line("· " + text, UIKit.F_BODY, UIKit.C_TEXT)
		"tip":
			return _line("提示：" + text, UIKit.F_SMALL, UIKit.C_TEXT_DIM)
		"live":
			# 实时卡片：这一页要给出「你现在在哪、下一步差多少」，数字全在开页时现算
			return _make_live(text)
		_:
			return _line(text, UIKit.F_BODY, UIKit.C_TEXT)


## 一行可自动换行的文字（指引正文一律用阅读字体，避免毛笔体小字难读）
func _line(text: String, size: int, color: Color) -> Label:
	var l := UIKit.label(text, size, color)
	UIKit.make_readable(l)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## 「现状」卡片：纸底金边的小卡，把该节的实时数值排在正文里
func _make_live(key: String) -> Control:
	var lines := _live_lines(key)
	if lines.is_empty():
		return null
	var accent: Color = UIKit.facility_style("guide").get("accent", UIKit.C_ACCENT)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.94, 0.42, 6))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var col := UIKit.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)
	for raw in lines:
		col.add_child(_line(String(raw), UIKit.F_BODY, Color(0.95, 0.91, 0.79)))
	return card


## 取数键 → 若干行现状文字。
## ⚠ 数字一律从 CharacterData / ItemDB / SkillDB 现取：改数值表不用回来改这里。
func _live_lines(key: String) -> Array:
	var out: Array = []
	match key:
		"status":
			out.append("你现在的底子：物理攻击 %d　法术攻击 %d　气血上限 %d" % [
				int(round(CharacterData.physical_attack())),
				int(round(CharacterData.spell_attack())),
				int(round(CharacterData.max_hp()))])
			out.append("境界 %s%s，本阶段修为 %d / %d —— 修为满了就不再涨，要先突破" % [
				CharacterData.current_realm, CharacterData.get_realm_stage_name(),
				CharacterData.realm_exp, CharacterData.get_stage_exp_required()])
		"realm":
			var major := 1.0 + CharacterData.REALM_MAJOR_GAIN
			var minor := 1.0 + CharacterData.REALM_MINOR_GAIN
			var now := CharacterData.realm_stat_multiplier()
			var lack := maxi(0, CharacterData.get_stage_exp_required() - CharacterData.realm_exp)
			var tail := "" if lack <= 0 else "，还差修为 %d" % lack
			var next_realm := CharacterData.get_next_realm()
			if next_realm == "":
				out.append("境界 %s 已是最后一档，倍率成长到此为止 —— 接着靠装备、功法和手法。" % CharacterData.current_realm)
			elif CharacterData.is_final_stage():
				out.append("下一步是大突破：%s → %s，力量 / 法强 / 双抗 / 气血 / 灵力 ×%.1f（累积 ×%.2f → ×%.2f）%s" % [
					CharacterData.current_realm, next_realm, major, now, now * major, tail])
				if next_realm == CharacterData.REALM_HUASHEN:
					out.append("化神不在面板突破：把化神底髓与化神天髓在锻造台熔铸成化神破境晶，再带它到幽冥灵墟中心的九天门开门，进九天之上登坛突破。")
				else:
					out.append("破境材料要合成：底髓出自本境界大陆核心首领，天髓出自对应位面第三位 BOSS，两枚在锻造台「熔铸」页合璧；按 Tab →「修炼突破」。")
			else:
				out.append("下一步是小突破：%s%s → %s，同样六项 ×%.1f（累积 ×%.2f → ×%.2f）%s" % [
					CharacterData.current_realm, CharacterData.get_realm_stage_name(),
					CharacterData.get_next_stage_name(), minor, now, now * minor, tail])
				out.append("小突破不要材料，修为满了就能点：按 Tab →「修炼突破」。")
		"gear":
			var worn := 0
			var enh := 0
			for slot in CharacterData.SLOT_ORDER:
				var item := CharacterData.get_equipped(slot)
				if item.is_empty():
					continue
				worn += 1
				enh += int(item.get("enhancement_level", 0))
			var slots := CharacterData.SLOT_ORDER.size()
			out.append("身上 %d / %d 件穿满，强化合计 +%d（每件上限 +%d）" % [
				worn, slots, enh, ItemDB.MAX_ENHANCE])
			if worn < slots:
				out.append("还有 %d 个槽空着 —— 空槽等于白丢一截属性，先拿 BOSS 掉的装备把位置填上。" % (slots - worn))
			var cap := ItemDB.realm_grade_cap(CharacterData.current_realm)
			if cap != "":
				out.append("%s期品阶上限「%s」：到这个阶的装备整件停敲，突破境界才继续解锁。" % [
					CharacterData.current_realm, cap])
		"skill":
			var total := 0
			for group in SkillDB.get_library_groups():
				total += int((group as Dictionary).get("total", 0))
			var act := CharacterData.active_skill_count()
			var pas := CharacterData.passive_skill_loadout.size()
			out.append("已学 %d / %d 门 · 主动装配 %d / %d · 被动装配 %d / %d" % [
				CharacterData.learned_skills.size(), total, act, SkillPanel.MAX_ACTIVE,
				pas, SkillPanel.MAX_PASSIVE])
			if CharacterData.learned_skills.is_empty():
				out.append("一门功法都还没学：去万界塔，每层通关必感悟 1 门（塔是功法的唯一来源）。")
			elif CharacterData.learned_skills.size() > act + pas:
				out.append("有学会了但没进槽的功法 —— 没装配的一行效果都不生效，按 Y 去功法库放好。")
		"treasure":
			var t_worn := 0
			for t_slot in CharacterData.TREASURE_SLOT_ORDER:
				if not CharacterData.get_equipped(t_slot).is_empty():
					t_worn += 1
			var spare := 0
			for bag_item in CharacterData.inventory:
				if String(bag_item.get("type", "")) == CharacterData.ITEM_EQUIPMENT \
						and String(bag_item.get("equipment_type", "")) == "treasure":
					spare += 1
			out.append("法宝 %d / %d 槽已穿，背包里还有 %d 件法宝没穿" % [
				t_worn, CharacterData.TREASURE_SLOT_ORDER.size(), spare])
			out.append("法宝也能上铁砧：每 +1 级，召唤物气血与攻击各 +%d%%；每进阶一次，召唤时长 +%.0f 秒。" % [
				CharacterData.SUMMON_BOOST_PER_LEVEL, CharacterData.SUMMON_DURATION_PER_ASCEND])
		"pills":
			var pills := 0
			for bag in CharacterData.inventory:
				if String(bag.get("type", "")) == CharacterData.ITEM_PILL:
					pills += 1
			var talismans := 0
			for tid in CharacterData.talisman_stock.keys():
				talismans += CharacterData.talisman_count(String(tid))
			var slotted := 0
			for sid in CharacterData.quick_slots.keys():
				if String(CharacterData.quick_slots[sid]) != "":
					slotted += 1
			out.append("背包里丹药 %d 颗、符匣里符箓 %d 张 · 战斗轮盘已装 %d / %d 格" % [
				pills, talismans, slotted, CharacterData.quick_slots.size()])
			if slotted == 0:
				out.append("轮盘一格都没装 —— 进战前在背包右上「战斗轮盘」装好，不然战斗中按 G 也拿不出来。")
	return out


func _refresh_content() -> void:
	# 外部指定了页（战斗里点「变强之法」）就翻到那页，否则回第一章：
	# 玩家主动点「小书」多半是第一次看
	if start_chapter_id != "":
		_show_chapter(GuideDB.chapter_index_by_id(start_chapter_id))
		start_chapter_id = ""
		return
	_show_chapter(0)
