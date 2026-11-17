class_name RogueDeckView
extends VBoxContainer
## 试炼之路 ·「玉简录」：本局已获得的增幅卡一览（2026-11-09 用户要）
##
## 为什么独立成控件：行囊页是「左右两栏 + 固定高度」，玉简页是「流式卡片 + 整体滚动」，
## 两套尺寸假设塞进同一个 `_build_content()` 会互相打架。这里只管画，
## 由 `RogueGearPanel` 决定挂在哪一页、什么时候 `refresh()`。
##
## 数据**只读** `RogueRun.buffs` + `RogueDB`，不复制任何状态 —— 每次打开都按当前层数重算，
## 不会出现「面板写 2 层、实际已经 3 层」这种两处不同步。
##
## 美术接入：卡片底走 `UIKit.accent_card_style()`（换皮改一处）；将来若给玉简做贴图，
## 把 `_make_card()` 里的 PanelContainer 换成 TextureRect 即可，内部分栏结构不用动。

## 卡片最小宽度：面板 820 − 左右内衬 36 − 列间距 12，两列各约 386。
## 写 350 是给字体变宽留余量；别按 386 卡满，最小宽度一旦等于可用宽度就会被挤出横向滚动。
const CARD_MIN_W := 350.0
const COLUMNS := 2
## 稀有度排序权重（越小越靠前）：先看强的，别让「淬体」压在「借命」上面。
## 用字符串字面量而不是 RogueDB 常量 —— 常量表改名时这里会**静默**退回默认权重，
## 用字面量至少和卡表里的 `rarity` 值一样是肉眼可核对的。
const RARITY_RANK: Dictionary = {
	"legend": 0,
	"rare": 1,
	"common": 2,
}

## 组内排序用的「获得顺序」表：id -> 当初加入 buffs 的次序。
## ⚠ `sort_custom` 不保证稳定，只按稀有度排会让同档卡在每次打开时乱跳，
##   所以同档必须自己带一个确定的次序兜底。
var _order_map: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


## 重画整页（每次打开面板 / 切到本页时调用）
func refresh() -> void:
	UIKit.clear_children(self)
	_order_map.clear()
	var i := 0
	for raw_id in RogueRun.buffs.keys():
		_order_map[String(raw_id)] = i
		i += 1

	var groups := _grouped_ids()
	var total_kinds := 0
	var total_stacks := 0
	for raw in groups:
		var g: Dictionary = raw
		var ids: Array = g.get("ids", [])
		total_kinds += ids.size()
		for id in ids:
			total_stacks += RogueRun.buff_stacks(String(id))

	add_child(_summary_card(total_kinds, total_stacks))
	if total_kinds == 0:
		add_child(_empty_hint())
		return

	for raw in groups:
		var g2: Dictionary = raw
		var ids2: Array = g2.get("ids", [])
		if ids2.is_empty():
			continue
		add_child(_group_header(String(g2.get("title", "")), ids2))
		add_child(_group_grid(ids2))


# ===================== 汇总 / 空态 =====================

func _summary_card(kinds: int, stacks: int) -> Control:
	var fam := String(RogueDB.FAMILY_NAME.get(RogueRun.family, RogueRun.family))
	var accent: Color = UIKit.C_ACCENT
	if kinds == 0:
		return UIKit.note_card(
			"本局流派：%s · 尚未获得任何玉简。每清空一个小关或 BOSS 关都会弹出三选一。" % fam,
			accent)
	# 池子大小从表里现算：新增卡只需改 RogueDB.POOLS，这里不会写死数字
	var pool_n := 0
	if RogueDB.POOLS.has(RogueRun.family):
		pool_n += (RogueDB.POOLS[RogueRun.family] as Array).size()
	if RogueDB.POOLS.has("generic"):
		pool_n += (RogueDB.POOLS["generic"] as Array).size()
	return UIKit.note_card(
		"本局流派：%s · 已获 %d 种玉简 / 共 %d 层（本局卡池 %d 种，叠满的卡不再出现在三选一里）。"
		% [fam, kinds, stacks, pool_n], accent)


func _empty_hint() -> Control:
	var col := UIKit.vbox(6)
	var l := UIKit.readable_label(
		"打完第一个小关的波次后，会弹出三枚玉简让你选一张 —— 选到的卡就记在这里，随时可以回来翻。",
		13, UIKit.C_TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(l)
	return col


# ===================== 分组 =====================

## 返回 [{ family, title, ids }]，本流派在前、通用在后。
## 只列**本局真的拿到**的卡；未获得的卡在卡池里，不进这一页（图鉴那页才列全量）。
func _grouped_ids() -> Array:
	var out: Array = []
	var fam := String(RogueRun.family)
	for key in [fam, "generic"]:
		var fam_key := String(key)
		if not RogueDB.POOLS.has(fam_key):
			continue
		var ids: Array = []
		for raw_id in RogueRun.buffs.keys():
			var id := String(raw_id)
			if RogueRun.buff_stacks(id) <= 0:
				continue
			# ⚠ 归属只认 RogueDB.family_of()（按卡表反查），
			#   别拿「当前流派 == 卡 id 前缀」这种拼法，通用卡会被漏掉。
			if RogueDB.family_of(id) != fam_key:
				continue
			ids.append(id)
		ids.sort_custom(_compare_cards)
		out.append({
			"family": fam_key,
			"title": String(RogueDB.FAMILY_NAME.get(fam_key, fam_key)),
			"ids": ids,
		})
	return out


func _compare_cards(a: String, b: String) -> bool:
	var ra := int(RARITY_RANK.get(_rarity_of(a), 9))
	var rb := int(RARITY_RANK.get(_rarity_of(b), 9))
	if ra != rb:
		return ra < rb
	return int(_order_map.get(a, 0)) < int(_order_map.get(b, 0))


func _rarity_of(id: String) -> String:
	return String(RogueDB.get_buff(id).get("rarity", "common"))


func _group_header(title: String, ids: Array) -> Control:
	var stacks := 0
	for id in ids:
		stacks += RogueRun.buff_stacks(String(id))
	var row := UIKit.vbox(4)
	var line := UIKit.hbox(8)
	line.add_child(UIKit.label("◆ " + title, UIKit.F_SECTION, UIKit.C_ACCENT))
	var count := UIKit.label("%d 种 · %d 层" % [ids.size(), stacks], UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(count)
	line.add_child(UIKit.spacer())
	row.add_child(line)
	var rule := ColorRect.new()
	rule.color = Color(0.95, 0.82, 0.45, 0.18)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	return row


func _group_grid(ids: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in ids:
		grid.add_child(_make_card(String(id)))
	return grid


# ===================== 单张卡 =====================

func _make_card(buff_id: String) -> Control:
	var def := RogueDB.get_buff(buff_id)
	var rarity := String(def.get("rarity", "common"))
	var accent: Color = RogueDB.RARITY_COLOR.get(rarity, UIKit.C_ACCENT)
	var stacks := RogueRun.buff_stacks(buff_id)
	var cap := RogueDB.stack_cap(buff_id)
	var full := stacks >= cap
	var stack_line := RogueDB.buff_stack_line(buff_id, stacks)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_MIN_W, 0.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UIKit.accent_card_style(
		accent, 0.72 if full else 0.58, 0.88 if full else 0.42, 8))
	card.tooltip_text = "%s · %s（%d/%d 层）\n%s\n\n%s" % [
		String(def.get("name", buff_id)), String(RogueDB.RARITY_NAME.get(rarity, "")),
		stacks, cap, String(def.get("desc", "")), stack_line]
	card.set_meta("buff_id", buff_id)

	var box := UIKit.vbox(5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# 首行：卡名 + 层数（层数是这张卡「有多强」的唯一刻度，放最右且加粗）
	var head := UIKit.hbox(6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl := UIKit.label(String(def.get("name", buff_id)), 18, accent)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_lbl)
	head.add_child(UIKit.spacer())
	var stack_lbl := UIKit.label("×%d" % stacks, 16,
		UIKit.C_GREAT if full else UIKit.C_TEXT)
	stack_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(stack_lbl)
	box.add_child(head)

	# 次行：稀有度 / 上限 / 满层 —— 用 chip 而不是括号文字，扫一眼就能分档
	var tags := UIKit.hbox(6)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.add_child(UIKit.chip(String(RogueDB.RARITY_NAME.get(rarity, rarity)), accent, 10))
	tags.add_child(UIKit.chip("上限 %d 层" % cap, UIKit.C_TEXT_DIM, 10))
	if full:
		tags.add_child(UIKit.chip("已叠满", UIKit.C_GREAT, 10))
	box.add_child(tags)

	var rule := ColorRect.new()
	rule.color = Color(accent.r, accent.g, accent.b, 0.22)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	# ⚠ 必须显式开 autowrap：`UIKit.label` 默认关，关着时 minimum_size.x = 整行宽，
	#   长 desc 会把卡片（进而把整个面板）撑宽。
	var desc := UIKit.readable_label(String(def.get("desc", "")), 14, UIKit.C_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0.0, 0.0)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)

	if stack_line != "":
		var acc := UIKit.readable_label(stack_line, 12,
			accent if not full else UIKit.C_GREAT)
		acc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		acc.custom_minimum_size = Vector2(0.0, 0.0)
		acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(acc)
	return card


# ===================== 探针辅助 =====================

## 当前显示的卡片节点（按显示顺序）。探针用它数张数 / 读文案，
## 别在探针里递归扫 PanelContainer —— 会把 chip、note_card 一起数进去。
func card_nodes() -> Array:
	var out: Array = []
	_collect_cards(self, out)
	return out


func _collect_cards(node: Node, out: Array) -> void:
	for child in node.get_children():
		var ctrl := child as Control
		if ctrl != null and ctrl.has_meta("buff_id"):
			out.append(ctrl)
			continue
		_collect_cards(child, out)
