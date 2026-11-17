class_name AchievementView
extends HBoxContainer
## 成就界面：左侧「成就任务 / 成就收藏」，右侧内容。
## 2026-10-30 用户定：
##   · 卡包只显示**已经获得**的卡，未获得的卡连卡位都不出现；
##   · 一个 BOSS 一格，格子的封面 = 该 BOSS 卡序的第一张；
##   · 点开后已拥有的卡扇形展开，可鼠标拖动换位；第一位就是收藏册封面；
##   · 卡面统一走 CardFace（kind = holo / ink / still），加卡种只加数据 / 一个分支。
##   · 成就任务 = 每个 BOSS 的卡面获取条件（普通 / 华彩有背景 / 纯华彩无背景 / 纸本水墨），
##     进度直接读 CodexDB.card_entry 的变体解锁态；普通卡以外的卡解锁后可在此领 50 晶石。

const NAV_WIDTH := 132.0
const PAGE_MIN_HEIGHT := 520.0
const GRID_COLS := 3
const BOSS_CELL_SIZE := Vector2(214.0, 330.0)
const CELL_PREVIEW := Vector2(190.0, 285.0)
const SPREAD_CARD := Vector2(280.0, 420.0)
const STAGE_SIZE := Vector2(760.0, 456.0)
const SINGLE_CARD := Vector2(300.0, 450.0)
const SINGLE_HOLDER := Vector2(332.0, 462.0)
const COLOR_DONE := Color(0.93, 0.76, 0.42, 1.0)

const PAGE_TASKS := 0
const PAGE_PACK := 1
const MODE_GRID := 0
const MODE_SPREAD := 1
const MODE_SINGLE := 2

var _page := PAGE_PACK
var _mode := MODE_GRID
var _boss_id := ""
var _single_index := 0
var _order_dirty := false

var _nav_buttons: Array[Button] = []
var _summary: Label
var _scroll: ScrollContainer
var _list_box: VBoxContainer

var _spread_stage: Control
var _spread_ids: Array[String] = []
var _spread_slots: Dictionary = {}
var _drag_id := ""
var _drag_start := Vector2.ZERO
var _drag_grab := Vector2.ZERO
var _drag_moved := 0.0
## 四张卡时缩小扇面尺寸，四张牌与底下卡种名才不互相压住
var _spread_card := SPREAD_CARD


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, PAGE_MIN_HEIGHT)
	_build()
	refresh()


func _accent() -> Color:
	return UIKit.facility_style("achievement").get("accent", UIKit.C_ACCENT)


func _build() -> void:
	var left := UIKit.vbox(8)
	left.custom_minimum_size = Vector2(NAV_WIDTH, 0.0)
	left.add_child(UIKit.label("功行", 10, Color(0.86, 0.78, 0.52, 0.8)))
	for i in 2:
		var btn := UIKit.tab_button("", Vector2(NAV_WIDTH, 42.0), _accent())
		UIKit.set_click_sfx(btn, "ui_tab")
		btn.pressed.connect(_show_page.bind(i))
		left.add_child(btn)
		_nav_buttons.append(btn)
	left.add_child(UIKit.spacer())
	add_child(left)

	var right := UIKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(right)

	_summary = UIKit.readable_note("")
	right.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.name = "AchievementScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_scroll = scroll

	_list_box = UIKit.vbox(10)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_box.custom_minimum_size = Vector2(STAGE_SIZE.x + 40.0, 0.0)
	scroll.add_child(_list_box)


func refresh() -> void:
	if _nav_buttons.is_empty():
		return
	var bosses := CodexDB.card_collection_entries().size()
	_nav_buttons[PAGE_TASKS].text = "成就任务"
	_nav_buttons[PAGE_PACK].text = "成就收藏 %d" % bosses
	_sync_nav()
	if _page == PAGE_PACK and _mode != MODE_GRID:
		var entry := CodexDB.card_entry(_boss_id)
		if entry.is_empty() or CodexDB.ordered_variants(entry).is_empty():
			_mode = MODE_GRID
	_render()


func _sync_nav() -> void:
	for i in _nav_buttons.size():
		UIKit.set_tab_selected(_nav_buttons[i], i == _page)


func _show_page(index: int) -> void:
	if index == _page:
		return
	_page = index
	if index == PAGE_PACK:
		Tutorial.note("ach_pack_open")
	_mode = MODE_GRID
	_single_index = 0
	_sync_nav()
	_render()


## ESC 逐层后退：单卡 → 展开 → 收藏册
func back() -> bool:
	if _mode == MODE_SINGLE:
		_mode = MODE_SPREAD
		_render()
		return true
	if _mode == MODE_SPREAD:
		_mode = MODE_GRID
		_render()
		return true
	return false


## 面板关闭时把卡序写进存档（只在真的拖过的时候才写）
func take_order_dirty() -> bool:
	var dirty := _order_dirty
	_order_dirty = false
	return dirty


func _render() -> void:
	if _list_box == null:
		return
	UIKit.clear_children(_list_box)
	_spread_ids.clear()
	_spread_slots.clear()
	_drag_id = ""
	if _scroll != null:
		_scroll.scroll_vertical = 0
	_summary.visible = _page == PAGE_TASKS or _mode == MODE_GRID
	if _page == PAGE_TASKS:
		_render_tasks()
		return
	if _mode == MODE_SPREAD:
		_render_spread()
		return
	if _mode == MODE_SINGLE:
		_render_single()
		return
	_render_grid()


# ===================== 成就任务 · 卡面收集 =====================

func _render_tasks() -> void:
	var entries := CodexDB.card_entries()
	var total_cards := 0
	var got_cards := 0
	var done_bosses := 0
	for raw in entries:
		var e := raw as Dictionary
		var variants: Array = e.get("card_variants", [])
		var got := int(e.get("card_collected", 0))
		total_cards += variants.size()
		got_cards += got
		if not variants.is_empty() and got >= variants.size():
			done_bosses += 1
	_summary.text = "成就任务 · 卡面收集　已完成 %d / %d 位首领 · %d / %d 张卡" % [
		done_bosses, entries.size(), got_cards, total_cards,
	]
	_list_box.add_child(UIKit.note_card(
		"普通卡：击败对应首领。华彩 · 有背景：双倍气血场次取胜（第 %d 次及以后）。"
		% CodexDB.HOLO_CLEAR_REQUIRED
		+ "纯华彩 · 无背景：双倍气血场次无伤取胜。纸本水墨：双倍气血场次 %d 秒内取胜。"
		% int(CodexDB.INK_CLEAR_TIME_LIMIT)
		+ "普通卡以外的卡解锁后，可在本页领取 %d 锻造晶石。"
		% CharacterData.CARD_UNLOCK_BONUS_CRYSTALS, _accent()))
	if entries.is_empty():
		_list_box.add_child(UIKit.note_card("卡面数据尚未登记。", _accent()))
		return

	var group := ""
	for raw in entries:
		var entry := raw as Dictionary
		var next_group := _task_group_name(entry)
		if next_group != group:
			group = next_group
			_list_box.add_child(_task_group_header(group))
		_list_box.add_child(_make_card_task(entry))

	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0.0, 14.0)
	_list_box.add_child(bottom)


func _task_group_name(entry: Dictionary) -> String:
	if String(entry.get("world_region", "")) != "":
		return "大世界 · 区域核心"
	return "%s · 投影" % String(entry.get("domain", ""))


func _task_location(entry: Dictionary) -> String:
	var world_region := String(entry.get("world_region", ""))
	if world_region != "":
		var region := SecretWorldDB.get_region(world_region)
		return "%s · 区域核心重战" % String(region.get("name", world_region))
	return "第 %02d 层 · %s · 投影" % [
		int(entry.get("floor", 0)), String(entry.get("domain", "")),
	]


func _task_group_header(text: String) -> Control:
	var row := UIKit.hbox(8)
	row.custom_minimum_size = Vector2(0.0, 22.0)
	var lbl := UIKit.label(text, 11, Color(0.93, 0.76, 0.42, 0.82))
	row.add_child(lbl)
	var line := ColorRect.new()
	line.color = Color(0.93, 0.76, 0.42, 0.16)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	return row


func _make_card_task(entry: Dictionary) -> Control:
	var variants: Array = entry.get("card_variants", [])
	var total := variants.size()
	var done := int(entry.get("card_collected", 0))
	var complete := total > 0 and done >= total
	var accent: Color = entry.get("card_accent", _accent())
	var status_col := COLOR_DONE if complete else accent

	var card := PanelContainer.new()
	card.name = "CardTask_%s" % String(entry.get("id", ""))
	card.set_meta("tut", "ach.task")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(accent, 0.78, 0.30, 8))
	var col := UIKit.vbox(9)
	card.add_child(col)

	var header := UIKit.hbox(10)
	col.add_child(header)
	var titles := UIKit.vbox(1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(UIKit.label(String(entry.get("name", "")), 15,
		Color(0.95, 0.92, 0.84) if not complete else COLOR_DONE))
	titles.add_child(UIKit.label(_task_location(entry), 9, UIKit.C_TEXT_DIM))

	var bar := UIKit.mini_progress(float(done) / float(maxi(1, total)), status_col,
		Vector2(96.0, 6.0))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(bar)
	header.add_child(UIKit.chip("已完成" if complete else "%d/%d" % [done, total],
		status_col, 9))

	var line := ColorRect.new()
	line.color = Color(0.72, 0.63, 0.46, 0.14)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)

	for raw in _ordered_task_variants(variants):
		col.add_child(_make_task_goal(raw as Dictionary, entry, accent))
	return card


func _ordered_task_variants(variants: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for want in ["portrait", "scene", "plain"]:
		for raw in variants:
			var v := raw as Dictionary
			var vid := String(v.get("id", ""))
			if vid == want and not seen.has(vid):
				out.append(v)
				seen[vid] = true
				break
	for raw in variants:
		var v := raw as Dictionary
		var vid := String(v.get("id", ""))
		if not seen.has(vid):
			out.append(v)
			seen[vid] = true
	return out


func _make_task_goal(variant: Dictionary, entry: Dictionary, accent: Color) -> Control:
	var unlocked := bool(variant.get("unlocked", false))
	var col := accent if unlocked else Color(0.62, 0.64, 0.68)
	var row := UIKit.hbox(8)
	row.name = "TaskGoal_%s_%s" % [
		String(entry.get("id", "")), String(variant.get("id", "")),
	]
	row.custom_minimum_size = Vector2(0.0, 30.0)
	var dot := UIKit.label("●" if unlocked else "○", 10, col)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.custom_minimum_size = Vector2(12.0, 0.0)
	row.add_child(dot)

	var info := UIKit.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UIKit.label(String(variant.get("label", "卡面")), 10,
		Color(0.94, 0.91, 0.84) if unlocked else Color(0.72, 0.73, 0.76)))
	var method := UIKit.readable_label(_task_method(variant, entry), 9,
		UIKit.C_TEXT_DIM)
	method.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(method)

	var boss_id := String(entry.get("id", ""))
	var card_id := String(variant.get("id", ""))
	var state := UIKit.label("已获得" if unlocked else "未获得", 9, col)
	state.name = "TaskState_%s_%s" % [boss_id, card_id]
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(state)

	# 普通卡以外的卡：解锁后可在这里领一次 50 晶石
	if card_id != "portrait":
		var claimed := CharacterData.is_card_reward_claimed(boss_id, card_id)
		var claim := UIKit.paper_button(
			"已领 %d" % CharacterData.CARD_UNLOCK_BONUS_CRYSTALS if claimed \
				else "领 %d 晶石" % CharacterData.CARD_UNLOCK_BONUS_CRYSTALS,
			Vector2(88, 24), COLOR_DONE)
		UIKit.set_readable_font(claim, 9)
		claim.name = "TaskClaim_%s_%s" % [boss_id, card_id]
		claim.set_meta("tut", "ach.pack")
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		claim.disabled = not unlocked or claimed
		if not unlocked:
			claim.tooltip_text = "解锁这张卡后领取 %d 锻造晶石" % CharacterData.CARD_UNLOCK_BONUS_CRYSTALS
		elif claimed:
			claim.tooltip_text = "已领取 %d 锻造晶石" % CharacterData.CARD_UNLOCK_BONUS_CRYSTALS
		else:
			UIKit.set_click_sfx(claim, "ui_confirm")
			claim.pressed.connect(_claim_card_reward.bind(boss_id, card_id, claim))
		row.add_child(claim)
	return row


func _claim_card_reward(boss_id: String, card_id: String, btn: Button) -> void:
	var got := CharacterData.claim_card_reward(boss_id, card_id)
	if got <= 0:
		return
	Tutorial.note("reward_claim")
	btn.text = "已领 %d" % got
	btn.disabled = true
	btn.tooltip_text = "已领取 %d 锻造晶石" % got


func _task_method(variant: Dictionary, entry: Dictionary) -> String:
	var world := String(entry.get("world_region", "")) != ""
	match String(variant.get("id", "")):
		"portrait":
			return "击败大世界区域核心首领" if world \
				else "击败第 %02d 层投影" % int(entry.get("floor", 0))
		"scene":
			return "双倍气血场次取胜（第 %d 次及以后）" % CodexDB.HOLO_CLEAR_REQUIRED
		"plain":
			return "双倍气血场次无伤取胜"
		"ink":
			var limit := int(CodexDB.INK_CLEAR_TIME_LIMIT)
			return "双倍气血场次 %d 秒内通关大世界区域核心（第 %d 次及以后）" % [
				limit, CodexDB.HOLO_CLEAR_REQUIRED] if world \
				else "双倍气血场次 %d 秒内通关第 %02d 层（第 %d 次及以后）" % [
					limit, int(entry.get("floor", 0)), CodexDB.HOLO_CLEAR_REQUIRED]
		_:
			return String(variant.get("desc", "按卡面说明获取"))



# ===================== 成就收藏 · 卡包 =====================

func _render_grid() -> void:
	var entries := CodexDB.card_collection_entries()
	_summary.text = "成就收藏 · 卡包　已收藏 %d 张卡 · %d 位 BOSS" % [
		CodexDB.card_collected(), entries.size(),
	]
	_list_box.add_child(_collection_row())
	if entries.is_empty():
		_list_box.add_child(UIKit.note_card(
			"还没有卡牌。\n击败 BOSS 收普通卡；双倍气血与无伤解锁华彩；%d 秒内双倍气血收纸本水墨。"
			% int(CodexDB.INK_CLEAR_TIME_LIMIT), _accent()))
		return

	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.custom_minimum_size = Vector2(
		BOSS_CELL_SIZE.x * GRID_COLS + 12.0 * (GRID_COLS - 1), 0.0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_list_box.add_child(grid)
	for e in entries:
		grid.add_child(_make_boss_cell(e as Dictionary))

	_list_box.add_child(UIKit.note(
		"收藏规则：普通卡击败 BOSS 即收；华彩 · 有背景击败同层双倍气血 BOSS；"
		+ "纯华彩 · 无背景要无伤通关同层双倍气血 BOSS；"
		+ "纸本水墨要双倍气血场次 %d 秒内通关。" % int(CodexDB.INK_CLEAR_TIME_LIMIT)
		+ "普通卡以外的卡解锁后，到「成就任务」页可领 %d 晶石。"
		% CharacterData.CARD_UNLOCK_BONUS_CRYSTALS
		+ "一个 BOSS 一格，点开后按住卡可以拖动换位 —— 第一位就是这一格的封面。"))
	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0.0, 14.0)
	_list_box.add_child(bottom)


func _collection_row() -> Control:
	var row := UIKit.hbox(8)
	row.add_child(UIKit.label("收藏种类", UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	row.add_child(UIKit.chip("卡包 · 万界塔 & 大陆首领", _accent()))
	row.add_child(UIKit.chip("更多收藏 · 待开放", Color(0.5, 0.5, 0.56, 1.0)))
	row.add_child(UIKit.spacer())
	return row


func _make_boss_cell(entry: Dictionary) -> Control:
	var boss_id := String(entry.get("id", ""))
	var accent: Color = entry.get("card_accent", _accent())
	var owned := CodexDB.ordered_variants(entry)
	var count := owned.size()
	if count <= 0:
		return Control.new()
	var cover: Dictionary = owned[0]

	var cell := PanelContainer.new()
	cell.name = "BossCell_" + boss_id
	cell.custom_minimum_size = BOSS_CELL_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := UIKit.accent_card_style(accent, 0.92, 0.52, 12)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	cell.add_theme_stylebox_override("panel", style)
	cell.gui_input.connect(_on_cell_input.bind(boss_id))
	cell.pivot_offset = BOSS_CELL_SIZE * 0.5
	cell.mouse_entered.connect(_hover_cell.bind(cell, true))
	cell.mouse_exited.connect(_hover_cell.bind(cell, false))

	var box := Control.new()
	box.custom_minimum_size = BOSS_CELL_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)

	# 叠卡：收了几张就垫几层，一眼能看出这格后面还有卡
	for i in range(mini(count, 3) - 1, 0, -1):
		var layer := Panel.new()
		layer.position = Vector2(12.0 + 5.0 * i, 10.0 + 4.0 * i)
		layer.size = CELL_PREVIEW
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.04, 0.065, 0.88)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.20)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		layer.add_theme_stylebox_override("panel", sb)
		box.add_child(layer)

	var frame := Panel.new()
	frame.position = Vector2(12.0, 10.0)
	frame.size = CELL_PREVIEW
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.02, 0.03, 0.05, 0.95)
	fsb.border_color = Color(accent.r, accent.g, accent.b, 0.5)
	fsb.set_border_width_all(1)
	fsb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fsb)
	box.add_child(frame)
	_add_preview_layers(frame, cover, accent, func() -> void: open_boss(boss_id))

	# 底部压暗 + 名字 / 层数（封面本身就是第一张卡）
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -66.0
	shade.color = Color(0.015, 0.02, 0.035, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(shade)
	var name_label := UIKit.outlined_label(String(entry.get("name", "")), UIKit.F_SECTION, accent, 3)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -50.0
	name_label.offset_bottom = -28.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(name_label)
	var floor_no := int(entry.get("floor", 0))
	var sub := "第 %02d 层" % floor_no if floor_no > 0 else "大陆核心"
	var floor_label := UIKit.outlined_label(sub, UIKit.F_SMALL, Color(0.82, 0.84, 0.90, 1.0), 2)
	floor_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	floor_label.offset_top = -27.0
	floor_label.offset_bottom = -9.0
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(floor_label)

	var count_chip := UIKit.chip("%d 张" % count, accent, 10)
	count_chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	count_chip.offset_left = -52.0
	count_chip.offset_top = 6.0
	count_chip.offset_right = -6.0
	count_chip.offset_bottom = 24.0
	frame.add_child(count_chip)

	var status := UIKit.label("%d 张 · 点开" % count, UIKit.F_SMALL, accent)
	status.position = Vector2(12.0, 300.0)
	status.size = Vector2(CELL_PREVIEW.x, 18.0)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(status)
	return cell


## 封面预览：直接用 CardFace（bare）铺满格子 —— 卡种怎么渲染封面就怎么渲染。
##   · 华彩封面 = 真 HoloCardView：待机流彩、分层视差都在（不再是纯贴图）
##   · 普通封面 = 同一支 card_still 着色器（exposure / gamma 和单卡完全一致，
##     以前这里只给 modulate 1.18，同一个 BOSS 在格子里比单卡暗一截）
func _add_preview_layers(parent: Control, v: Dictionary, accent: Color,
		on_open: Callable = Callable()) -> void:
	var face := CardFace.new()
	if face.configure(v, parent.size if parent.size.x > 1.0 else CELL_PREVIEW, accent, true):
		# 待机不跑视差：12 格同时动会让收藏册掉帧（探针实测悬停视差直接失效）；
		# 水墨封面的低频相位流仍保留（最多一张，开销小）；输入保留，扫过封面才播视差。
		face.set_idle_motion(false)
		face.set_input_enabled(true)
		# 格子封面也吃全套：流转 / 墨环 / 收小幅度的微倾；开页时同样落墨
		face.set_paper_interactive(true, true, 0.5)
		if face.is_paper():
			face.play_paper_reveal(1.4)
		if on_open.is_valid():
			face.clicked.connect(on_open)
		parent.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	face.queue_free()
	var miss := UIKit.label("卡面缺图", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	miss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	miss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	miss.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(miss)


func _hover_cell(cell: Control, entered: bool) -> void:
	var tw := cell.create_tween()
	tw.tween_property(cell, "scale", Vector2(1.02, 1.02) if entered else Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_cell_input(event: InputEvent, boss_id: String) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	open_boss(boss_id)


# ===================== 单个 BOSS：只铺已拥有的卡 =====================

func open_boss(boss_id: String) -> void:
	GameState.play_ui("ui_click")
	_boss_id = boss_id
	_single_index = 0
	_mode = MODE_SPREAD
	_render()


func _render_spread() -> void:
	var entry := CodexDB.card_entry(_boss_id)
	var owned := CodexDB.ordered_variants(entry)
	if entry.is_empty() or owned.is_empty():
		_mode = MODE_GRID
		_render()
		return
	var accent: Color = entry.get("card_accent", _accent())
	_spread_card = SPREAD_CARD if owned.size() <= 3 else Vector2(216.0, 324.0)

	var head := UIKit.hbox(10)
	var back_btn := UIKit.button("← 返回收藏册", Vector2(150.0, 34.0))
	back_btn.add_theme_font_size_override("font_size", 15)
	back_btn.pressed.connect(func() -> void:
		_mode = MODE_GRID
		_render())
	head.add_child(back_btn)
	head.add_child(UIKit.label(String(entry.get("name", "")), UIKit.F_TITLE, accent))
	var floor_no := int(entry.get("floor", 0))
	head.add_child(UIKit.chip("第 %02d 层" % floor_no if floor_no > 0 else "大陆核心",
		UIKit.C_TEXT_DIM))
	head.add_child(UIKit.chip("已收藏 %d 张" % owned.size(), accent))
	head.add_child(UIKit.spacer())
	var head_hint := "拖动卡片换位 · 点一下看单卡"
	for raw in owned:
		if String((raw as Dictionary).get("fx", "")) == "paper":
			head_hint += " · 晃出水波"
			break
	head.add_child(UIKit.label(head_hint, UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	_list_box.add_child(head)

	var stage := Panel.new()
	stage.name = "SpreadStage"
	stage.custom_minimum_size = STAGE_SIZE
	stage.size = STAGE_SIZE
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stage_style := StyleBoxFlat.new()
	stage_style.bg_color = Color(0.02, 0.03, 0.05, 0.72)
	stage_style.border_color = Color(accent.r, accent.g, accent.b, 0.22)
	stage_style.set_border_width_all(1)
	stage_style.set_corner_radius_all(14)
	stage.add_theme_stylebox_override("panel", stage_style)
	_list_box.add_child(stage)
	_spread_stage = stage

	var glow := UIKit.glow_node(Vector2(640.0, 320.0), accent, 0.10)
	glow.position = (STAGE_SIZE - Vector2(640.0, 320.0)) * 0.5
	stage.add_child(glow)

	for i in owned.size():
		var v: Dictionary = owned[i]
		var cid := String(v.get("id", ""))
		var slot := Control.new()
		slot.name = "CardSlot%d" % i
		slot.custom_minimum_size = Vector2(_spread_card.x, _spread_card.y + 28.0)
		slot.size = slot.custom_minimum_size
		slot.pivot_offset = _spread_card * 0.5
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(slot)

		var face := _make_card_face(v, _spread_card, accent)
		if face != null:
			face.set_input_enabled(false)
			# 展开页也保留纸本全套：落墨 + 流转 + 微倾 + 水波；点击/拖动仍走视图级 _input
			face.set_paper_interactive(true, true)
			if face.is_paper():
				face.play_paper_reveal(1.5)
			face.name = "CardSpread%d" % i
			var inner := face.holo_view()
			if inner != null:
				inner.name = "HoloSpread%d" % i
			slot.add_child(face)
		else:
			slot.add_child(_card_placeholder(_spread_card))

		var cap := UIKit.label(String(v.get("label", "")), UIKit.F_SMALL, accent)
		cap.position = Vector2(0.0, _spread_card.y + 4.0)
		cap.size = Vector2(_spread_card.x, 18.0)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cap)

		slot.position = Vector2(
			STAGE_SIZE.x * 0.5 - _spread_card.x * 0.5,
			STAGE_SIZE.y * 0.5 - _spread_card.y * 0.5)
		slot.rotation = 0.0
		slot.scale = Vector2(0.88, 0.88)
		slot.modulate.a = 0.0
		_spread_slots[cid] = slot
		_spread_ids.append(cid)

	_apply_fan(true)


## 第 0 张在正中、压在最上面；其余左右交替往后扇形展开
func _fan_targets(n: int, card_size: Vector2) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var cx := STAGE_SIZE.x * 0.5
	var cy := STAGE_SIZE.y * 0.5 - 10.0
	if n == 1:
		out.append({"pos": Vector2(cx - card_size.x * 0.5,
			cy - card_size.y * 0.5), "rot": 0.0})
		return out
	var max_rank := int(ceil(float(n - 1) * 0.5))
	var step := minf(card_size.x * 0.55,
		(STAGE_SIZE.x - card_size.x - 36.0) / float(2 * max_rank))
	for i in n:
		if i == 0:
			out.append({"pos": Vector2(cx - card_size.x * 0.5,
				cy - card_size.y * 0.5), "rot": 0.0})
			continue
		var rank := int((i + 1) / 2)
		var side := -1.0 if i % 2 == 1 else 1.0
		out.append({
			"pos": Vector2(
				cx + side * rank * step - card_size.x * 0.5,
				cy - card_size.y * 0.5 + rank * 14.0),
			"rot": side * deg_to_rad(6.5) * minf(float(rank), 2.0),
		})
	return out


func _apply_fan(is_initial: bool) -> void:
	var targets := _fan_targets(_spread_ids.size(), _spread_card)
	for i in _spread_ids.size():
		var cid := _spread_ids[i]
		var slot: Control = _spread_slots.get(cid, null)
		if slot == null or i >= targets.size():
			continue
		var target: Dictionary = targets[i]
		slot.z_index = (_spread_ids.size() - i) * 2
		var tw := slot.create_tween()
		var dur := 0.46 if is_initial else 0.26
		if is_initial:
			tw.tween_interval(0.05 * float(i))
		tw.tween_property(slot, "position", target.get("pos", slot.position), dur) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(slot, "rotation", float(target.get("rot", 0.0)), dur) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(slot, "scale", Vector2.ONE, dur) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if is_initial:
			tw.parallel().tween_property(slot, "modulate:a", 1.0, 0.26)


## 展开页的拖动/点选在视图级 _input 里做：卡槽与卡面都不吃鼠标，
## 舞台只负责显示（避免某个子控件把事件截走）。
func _input(event: InputEvent) -> void:
	if _mode != MODE_SPREAD or _spread_stage == null or not is_instance_valid(_spread_stage):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var local := _stage_local(mb.position)
		if mb.pressed:
			if Rect2(Vector2.ZERO, STAGE_SIZE).has_point(local):
				_drag_press(local)
				get_viewport().set_input_as_handled()
		elif _drag_id != "":
			_drag_release(local)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var local2 := _stage_local(st.position)
		if st.pressed:
			if Rect2(Vector2.ZERO, STAGE_SIZE).has_point(local2):
				_drag_press(local2)
				get_viewport().set_input_as_handled()
		elif _drag_id != "":
			_drag_release(local2)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_id != "":
		_drag_move(_stage_local(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _drag_id != "":
		_drag_move(_stage_local(event.position))
		get_viewport().set_input_as_handled()


## `_input` 里拿到的事件坐标已经是画布坐标（视口已完成拉伸换算）
func _stage_local(canvas_pos: Vector2) -> Vector2:
	return _spread_stage.get_global_transform().affine_inverse() * canvas_pos


func _drag_press(pos: Vector2) -> void:
	var cid := _hit_card(pos)
	if cid == "":
		return
	var slot: Control = _spread_slots[cid]
	_drag_id = cid
	_drag_start = pos
	_drag_grab = pos - slot.position
	_drag_moved = 0.0
	slot.z_index = 100
	var tw := slot.create_tween()
	tw.tween_property(slot, "scale", Vector2(1.04, 1.04), 0.10)


func _drag_move(pos: Vector2) -> void:
	if _drag_id == "" or not _spread_slots.has(_drag_id):
		return
	_drag_moved = maxf(_drag_moved, pos.distance_to(_drag_start))
	var slot: Control = _spread_slots[_drag_id]
	slot.position = pos - _drag_grab


func _drag_release(pos: Vector2) -> void:
	if _drag_id == "":
		return
	var cid := _drag_id
	_drag_id = ""
	if _drag_moved <= 8.0:
		open_card(_spread_ids.find(cid))
		return
	var targets := _fan_targets(_spread_ids.size(), _spread_card)
	var best := _spread_ids.find(cid)
	var best_dist := INF
	for i in _spread_ids.size():
		var center: Vector2 = targets[i].get("pos", Vector2.ZERO) + _spread_card * 0.5
		var d := center.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	var from := _spread_ids.find(cid)
	if from >= 0 and best != from:
		_spread_ids.remove_at(from)
		_spread_ids.insert(best, cid)
		CodexDB.set_card_order(_boss_id, _spread_ids)
		_order_dirty = true
	_apply_fan(false)


## 命中测试按旋转后的卡面矩形算，第一张在最上层，从前往后找
func _hit_card(pos: Vector2) -> String:
	if _spread_stage == null:
		return ""
	var stage_xf := _spread_stage.get_global_transform()
	for cid in _spread_ids:
		var slot: Control = _spread_slots.get(cid, null)
		if slot == null:
			continue
		var local := slot.get_global_transform().affine_inverse() * (stage_xf * pos)
		if Rect2(Vector2.ZERO, _spread_card).has_point(local):
			return cid
	return ""


# ===================== 单张卡放大 =====================

func open_card(index: int) -> void:
	var entry := CodexDB.card_entry(_boss_id)
	var owned := CodexDB.ordered_variants(entry)
	if index < 0 or index >= owned.size():
		return
	GameState.play_ui("ui_click")
	_single_index = index
	_mode = MODE_SINGLE
	_render()


func _render_single() -> void:
	var entry := CodexDB.card_entry(_boss_id)
	var owned := CodexDB.ordered_variants(entry)
	if owned.is_empty():
		_mode = MODE_SPREAD
		_render()
		return
	_single_index = clampi(_single_index, 0, owned.size() - 1)
	var v: Dictionary = owned[_single_index]
	var accent: Color = entry.get("card_accent", _accent())

	var head := UIKit.hbox(10)
	var back_btn := UIKit.button("← 返回展开", Vector2(130.0, 34.0))
	back_btn.add_theme_font_size_override("font_size", 15)
	back_btn.pressed.connect(func() -> void:
		_mode = MODE_SPREAD
		_render())
	head.add_child(back_btn)
	head.add_child(UIKit.label(String(entry.get("name", "")), UIKit.F_TITLE, accent))
	head.add_child(UIKit.chip(String(v.get("label", "")), accent))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.label("%d / %d" % [_single_index + 1, owned.size()],
		UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	_list_box.add_child(head)

	var row := UIKit.hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_box.add_child(row)

	var holder := Panel.new()
	holder.name = "SingleHolder"
	holder.custom_minimum_size = SINGLE_HOLDER
	holder.size = SINGLE_HOLDER
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.02, 0.03, 0.05, 0.72)
	hsb.border_color = Color(accent.r, accent.g, accent.b, 0.22)
	hsb.set_border_width_all(1)
	hsb.set_corner_radius_all(14)
	holder.add_theme_stylebox_override("panel", hsb)
	row.add_child(holder)

	# 华彩卡直挂 HoloCardView，保留它自己的悬停/拖动；水墨与普通卡走 CardFace
	var kind := String(v.get("kind", "holo"))
	var face: Control = null
	if kind == "holo":
		face = _make_holo_direct(v, SINGLE_CARD, accent)
		if face != null:
			face.name = "HoloSingle"
	else:
		face = _make_card_face(v, SINGLE_CARD, accent)
		if face != null:
			face.name = "CardSingle"
	if face != null:
		face.position = (SINGLE_HOLDER - SINGLE_CARD) * 0.5
		face.pivot_offset = SINGLE_CARD * 0.5
		face.modulate.a = 0.0
		face.scale = Vector2(0.97, 0.97)
		holder.add_child(face)
		if face is CardFace and (face as CardFace).is_paper():
			(face as CardFace).play_paper_reveal()
			(face as CardFace).set_paper_interactive(true)
		var tw := face.create_tween()
		tw.tween_property(face, "modulate:a", 1.0, 0.22)
		tw.parallel().tween_property(face, "scale", Vector2.ONE, 0.26) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		var miss := _card_placeholder(SINGLE_CARD)
		miss.position = (SINGLE_HOLDER - SINGLE_CARD) * 0.5
		holder.add_child(miss)

	var info := UIKit.vbox(8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	info.add_child(UIKit.label("%s　·　%s" % [String(entry.get("name", "")),
		String(v.get("label", ""))], UIKit.F_SECTION, accent))
	var floor_no := int(entry.get("floor", 0))
	info.add_child(UIKit.label(
		"万界塔 · 第 %02d 层　%s" % [floor_no, String(entry.get("subtitle", ""))]
		if floor_no > 0 else "%s　%s" % [String(entry.get("subtitle", "")), "大陆核心首领"],
		UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	info.add_child(UIKit.chip("已收藏 · " + _unlock_text(entry, v), accent))
	if String(v.get("desc", "")) != "":
		var d := UIKit.readable_label(String(v.get("desc", "")), UIKit.F_BODY, UIKit.C_TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(d)
	var hint := "普通卡 · 静态原画（无视差）"
	if kind == "holo":
		hint = "按住卡面左右拖动 · 松手回正"
	elif String(v.get("hint", "")) != "":
		hint = String(v.get("hint", ""))
	info.add_child(UIKit.label(hint, UIKit.F_SMALL, accent))

	var nav := UIKit.hbox(8)
	var prev := UIKit.button("← 上一张", Vector2(96.0, 30.0))
	prev.disabled = owned.size() <= 1
	prev.pressed.connect(_step_card.bind(-1))
	nav.add_child(prev)
	var nxt := UIKit.button("下一张 →", Vector2(96.0, 30.0))
	nxt.disabled = owned.size() <= 1
	nxt.pressed.connect(_step_card.bind(1))
	nav.add_child(nxt)
	info.add_child(nav)
	info.add_child(UIKit.label("收藏册封面 = 展开页排第一的卡；展开页可拖动换位。",
		UIKit.F_SMALL, UIKit.C_TEXT_DIM))


func _unlock_text(entry: Dictionary, v: Dictionary) -> String:
	var core := bool(entry.get("world_boss", false))
	match String(v.get("unlock", "boss")):
		"double":
			return "击败该首领双倍气血" if core else "击败同层双倍气血 BOSS"
		"perfect":
			return "无伤通关该首领双倍气血" if core else "无伤通关同层双倍气血 BOSS"
		"speed":
			return "该首领双倍气血 %d 秒内通关" % int(CodexDB.INK_CLEAR_TIME_LIMIT) if core \
				else "同层双倍气血 %d 秒内通关" % int(CodexDB.INK_CLEAR_TIME_LIMIT)
		_:
			return "击败「%s」" % String(entry.get("name", ""))


func _step_card(dir: int) -> void:
	var owned := CodexDB.ordered_variants(CodexDB.card_entry(_boss_id))
	if owned.size() <= 1:
		return
	_single_index = (_single_index + dir + owned.size()) % owned.size()
	_render()


func _make_card_face(v: Dictionary, card_size: Vector2, accent: Color) -> CardFace:
	var face := CardFace.new()
	if not face.configure(v, card_size, accent):
		face.queue_free()
		return null
	return face


func _make_holo_direct(v: Dictionary, card_size: Vector2, accent: Color) -> HoloCardView:
	var holo := HoloCardView.new()
	holo.custom_minimum_size = card_size
	holo.size = card_size
	holo.mouse_filter = Control.MOUSE_FILTER_PASS
	if not holo.configure(String(v.get("art", "")), String(v.get("bg", "")),
			String(v.get("lines", "")), accent):
		holo.queue_free()
		return null
	holo.set_idle_motion(true)
	holo.set_effect(float(v.get("bg_scale", 0.5)), float(v.get("bg_shift", 0.25)),
		float(v.get("prism", 0.22)), float(v.get("emission_gain", 1.5)),
		float(v.get("wide_glow", 0.0)), float(v.get("aura", 0.0)))
	holo.set_contour(float(v.get("contour", 0.30)))
	holo.set_legacy(bool(v.get("legacy", false)))
	holo.set_depth(0.0)
	return holo


func _card_placeholder(card_size: Vector2) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = card_size
	p.size = card_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, 0.9)
	sb.border_color = Color(0.4, 0.4, 0.46, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	p.add_theme_stylebox_override("panel", sb)
	var l := UIKit.label("卡面缺图", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
