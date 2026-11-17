extends Node
## 试炼之路 ·「玉简录」（局内已获增幅卡一览）自检（2026-11-09）
## 覆盖：
##   ① `RogueDB.buff_stack_line()` 的三种载体口径（attr / cap / flag / stat）；
##   ② `RogueDeckView` 的卡片张数、分组顺序、稀有度排序、满层标记、空态；
##   ③ `RogueGearPanel` 的页签：默认停在行囊页、点「玉简」才切页并重画；
##   ④ 表不脱节：CAP_BASE 的每个 key 都登记了中文名，卡表里每个 attr/stat 载体
##      都能被 `buff_stack_line()` 接住（不会把原始 key 印给玩家）。
## 用法：godot --headless --path . res://tools/probe_rogue_deck.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_seed_buffs()
	_test_stack_lines()
	_test_table_coverage()
	await _test_view()
	await _test_panel()
	RogueRun.buffs.clear()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


## 摆一局「打到一半」的样本：通用 5 张 + 剑修 3 张，覆盖满层 / 未满 / 传说 / 开关
func _seed_buffs() -> void:
	RogueRun.family = "sword"
	RogueRun.active = true
	RogueRun.buffs = {
		"g_str": 3,          # attr flat，max 3 → 满层
		"g_hp": 2,           # attr base_pct
		"g_res": 1,          # attr 百分比词条（xxx_pct 后缀，双属性）
		"g_last_stand": 1,   # flag（传说，一次性）
		"g_full": 2,         # stat（不翻译，回「每层独立叠加」）
		"s_wj_cap": 1,       # cap（剑意上限）
		"s_wj_count": 2,     # stat（剑修池）
		"s_yj_free": 1,      # flag + 传说（剑修池）
	}


# ===================== ① 文案口径 =====================

func _test_stack_lines() -> void:
	print("\n--- 当前累计文案 ---")
	var str_line := RogueDB.buff_stack_line("g_str", 3)
	_check(str_line.contains("力量"), "attr flat：属性名翻成中文", str_line)
	_check(str_line.contains("+9"), "attr flat：3 层 ×3 = +9", str_line)

	var hp_line := RogueDB.buff_stack_line("g_hp", 2)
	_check(hp_line.contains("气血上限"), "attr base_pct：属性名", hp_line)
	_check(hp_line.contains("+30%"), "attr base_pct：2 层 ×15% = +30%", hp_line)

	var res_line := RogueDB.buff_stack_line("g_res", 1)
	_check(res_line.contains("物抗") and res_line.contains("法抗"),
		"attr 百分比词条：去掉 _pct 后仍能取到中文名", res_line)
	_check(res_line.contains("+8%"), "attr 百分比词条：带 % 号", res_line)
	_check(not res_line.contains("_pct"), "attr 百分比词条：不把原始 key 印出来", res_line)

	var cap_line := RogueDB.buff_stack_line("s_wj_cap", 1)
	_check(cap_line.contains("剑意上限") and cap_line.contains("+2"),
		"cap：资源名 + 加值", cap_line)

	var flag_line := RogueDB.buff_stack_line("g_last_stand", 1)
	_check(flag_line.contains("机制已激活"), "flag：说「已激活」而不是层数", flag_line)
	_check(not flag_line.contains("×1"), "flag：不按层数说话", flag_line)

	var stat_line := RogueDB.buff_stack_line("g_full", 2)
	_check(stat_line.contains("每层独立叠加") and stat_line.contains("2 层"),
		"stat：不硬翻译，回「每层独立叠加」", stat_line)

	_check(RogueDB.buff_stack_line("g_str", 0) == "", "0 层：空串（不显示累计行）")
	_check(RogueDB.buff_stack_line("no_such_card", 2) == "", "未知 id：空串，不崩")
	# 满层文案必须与上限一致：传说卡上限恒 1，传说 flag 卡不应该出现「2 层」
	_check(RogueDB.stack_cap("g_last_stand") == 1, "传说卡上限恒 1 层")


# ===================== ④ 表不脱节 =====================

func _test_table_coverage() -> void:
	print("\n--- 数据表接缝 ---")
	var miss_cap: Array = []
	for raw_key in RogueDB.CAP_BASE.keys():
		var k := String(raw_key)
		if not RogueDB.CAP_NAME.has(k):
			miss_cap.append(k)
	_check(miss_cap.is_empty(), "CAP_BASE 的每个 key 都登记了中文名", str(miss_cap))

	# 每张卡都必须能算出「累计」那一行，否则卡片底部会空一块
	var miss_line: Array = []
	for raw in RogueDB.all_buffs():
		var def: Dictionary = raw
		var id := String(def.get("id", ""))
		if RogueDB.buff_stack_line(id, 1) == "":
			miss_line.append(id)
	_check(miss_line.is_empty(), "每张卡都有「当前累计」文案（1 层时）", str(miss_line))

	# attr 载体全走 AttributeDB：未登记的属性名会原样印 key，这里兜一层
	var raw_attr: Array = []
	for raw2 in RogueDB.all_buffs():
		var d2: Dictionary = raw2
		var attr: Dictionary = d2.get("attr", {})
		for raw_aid in attr.keys():
			var aid := String(raw_aid)
			var body := aid.trim_suffix("_pct") if aid.ends_with("_pct") else aid
			if AttributeDB.attr_name(body) == body:
				raw_attr.append(aid)
	_check(raw_attr.is_empty(), "卡表里的 attr 都能被 AttributeDB 翻成中文", str(raw_attr))


# ===================== ② 视图 =====================

func _labels_of(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append((c as Label).text)
		out.append_array(_labels_of(c))
	return out


func _test_view() -> void:
	print("\n--- 玉简视图 ---")
	var view := RogueDeckView.new()
	add_child(view)
	view.refresh()
	var cards := view.card_nodes()
	_check(cards.size() == 8, "卡片数 = 已获卡种数", str(cards.size()))

	# 分组顺序：本流派（剑修）在前，通用在后
	var first_ids: Array = []
	for c in cards:
		first_ids.append(String((c as Node).get_meta("buff_id", "")))
	_check(String(first_ids[0]).begins_with("s_"),
		"本流派组排在通用组之前", str(first_ids))
	# 组内：传说 → 稀有 → 普通
	_check(String(first_ids[0]) == "s_yj_free",
		"剑修组内传说卡排最前", str(first_ids))
	var legend_pos := first_ids.find("g_last_stand")
	var common_pos := first_ids.find("g_hp")
	_check(legend_pos >= 0 and common_pos >= 0 and legend_pos < common_pos,
		"通用组内传说排在普通之前", "legend=%d common=%d" % [legend_pos, common_pos])

	# 组标题的数字必须是现算的：3 种剑修卡共 4 层、5 种通用卡共 9 层
	var all_text := "\n".join(_labels_of(view))
	_check(all_text.contains("3 种 · 4 层"), "剑修组标题：种数 / 层数现算", all_text)
	_check(all_text.contains("5 种 · 9 层"), "通用组标题：种数 / 层数现算", all_text)

	# 满层卡：g_str 3/3 → 「已叠满」；未满的 g_hp 2/3 不该有
	var full_card: Node = null
	var part_card: Node = null
	for c in cards:
		var n := c as Node
		if String(n.get_meta("buff_id", "")) == "g_str":
			full_card = n
		elif String(n.get_meta("buff_id", "")) == "g_hp":
			part_card = n
	_check(full_card != null and part_card != null, "样本卡都渲染出来了")
	if full_card != null:
		var texts := _labels_of(full_card)
		_check(texts.has("已叠满"), "满层卡带「已叠满」标记", str(texts))
		_check(texts.has("×3"), "满层卡显示 ×3", str(texts))
		_check(texts.has("力量 +3"), "卡片上有 desc 原文", str(texts))
		_check(texts.has("当前 力量 +9"), "卡片上有累计值", str(texts))
	if part_card != null:
		var texts2 := _labels_of(part_card)
		_check(not texts2.has("已叠满"), "未满层卡没有「已叠满」", str(texts2))
		_check(texts2.has("上限 3 层"), "卡片标出叠加上限", str(texts2))

	# 空态：一张卡都没有时不能是空白页
	var empty_view := RogueDeckView.new()
	add_child(empty_view)
	var backup := RogueRun.buffs.duplicate()
	RogueRun.buffs.clear()
	empty_view.refresh()
	var empty_cards := empty_view.card_nodes()
	_check(empty_cards.is_empty(), "空态：没有卡片节点", str(empty_cards.size()))
	var empty_text := "\n".join(_labels_of(empty_view))
	_check(empty_text.contains("尚未获得"), "空态：有「尚未获得」提示", empty_text.substr(0, 40))
	RogueRun.buffs = backup
	empty_view.queue_free()
	view.queue_free()
	await get_tree().process_frame


# ===================== ③ 面板页签 =====================

func _test_panel() -> void:
	print("\n--- 行囊面板页签 ---")
	var panel := RogueGearPanel.new()
	add_child(panel)
	await get_tree().process_frame
	var page_gear = panel.get("_page_gear")
	var page_deck = panel.get("_page_deck")
	_check(page_gear != null and page_deck != null, "两个页面都建出来了")
	if page_gear == null or page_deck == null:
		panel.queue_free()
		return
	_check((page_gear as Control).visible and not (page_deck as Control).visible,
		"默认停在「行囊」页")

	# open() 里唯一的数据刷新点；面板自己会暂停树，这里只借它的刷新逻辑
	panel.call("_refresh_content")
	var tabs: Array = panel.get("_tab_buttons")
	_check(tabs.size() == 2, "页签数量 = 2", str(tabs.size()))
	if tabs.size() == 2:
		_check(String((tabs[1] as Button).text).contains("8"),
			"「玉简」页签带已获数量", String((tabs[1] as Button).text))
		# 走真实按钮信号：验证 connect 没断（不是直接调 _switch_tab）
		(tabs[1] as Button).pressed.emit()
		_check(not (page_gear as Control).visible and (page_deck as Control).visible,
			"点「玉简」后两个页面互斥切换")
		var deck: RogueDeckView = panel.get("_deck_view")
		_check(deck != null and deck.card_nodes().size() == 8,
			"切页后玉简视图按当前数据重画", str(deck.card_nodes().size() if deck != null else -1))
		(tabs[0] as Button).pressed.emit()
		_check((page_gear as Control).visible and not (page_deck as Control).visible,
			"点「行囊」能切回去")
	panel.queue_free()
	await get_tree().process_frame
