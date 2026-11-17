class_name TowerPanel
extends SystemPanel
## 万界塔（阶段2-D）
##
## 硬约束（§2.8）：
##   - 塔内 BOSS 为真实位面 BOSS 的投影
##   - 首次击杀投影 → 观摩招式并感悟 → 永久习得对应功法；重复击杀不再获得
##   - 万界塔是唯一功法来源，禁止产出功法以外的成长资源
##
## 解锁方式（2026-10-17 用户定）：**一名 BOSS 对应一层**。
## 在万界秘境击败某名 BOSS，塔里对应的那一层立刻开放；不需要等整个位面通关。
## 层表由 DOMAINS 自动生成（`WorldDB.get_floors()`），面板只显示状态与「挑战」按钮。
##
## 2026-10-25 用户要求去掉「一排排生硬方框」，改成符合塔的设施定位：
##   - 左侧是**从塔底向上登临**的塔身图，10 层沿塔身排列，按位面分段；
##   - 右侧是**投影记录碑**：选中层的用时 / 通关次数 / 下次血量 / 感悟功法 / 无伤奖励；
##   - 挑战、再战、领取无伤奖励仍在右侧，始终可见，不挡操作。


# ===================== 塔身图 =====================

## 自绘塔身：淡淡的高塔立绘 + 从下往上的登塔光路 + 悬浮尘埃。
## 楼层按钮由面板作为子节点叠在上面，这里只负责「塔」的背景与连接。
class TowerMap extends Control:
	var tower_tex: Texture2D
	var points: Array = []
	var states: Array = []
	var selected := -1
	var _pulse := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		process_mode = Node.PROCESS_MODE_ALWAYS
		resized.connect(queue_redraw)

	func _process(delta: float) -> void:
		_pulse += delta
		if selected >= 0:
			queue_redraw()

	func setup(tex: Texture2D) -> void:
		tower_tex = tex
		queue_redraw()

	func set_data(p_points: Array, p_states: Array, p_selected: int) -> void:
		points = p_points
		states = p_states
		selected = p_selected
		queue_redraw()

	func _state_color(state: String) -> Color:
		match state:
			"cleared":
				return Color(0.93, 0.76, 0.42)
			"ready":
				return Color(0.46, 0.90, 0.82)
			_:
				return Color(0.48, 0.54, 0.58)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if tower_tex != null:
			draw_texture_rect(tower_tex, Rect2(-150.0, -24.0, 520.0, 548.0), false,
				Color(0.56, 0.96, 0.92, 0.150))

		# 右侧逐渐压暗：让楼层文字从塔身细节里浮出来，但不切出一条硬边
		if w > 140.0:
			var steps := 30
			var span := w - 140.0
			for i in steps:
				var t := float(i) / float(steps)
				draw_rect(Rect2(140.0 + span * t, 0.0, span / float(steps) + 1.0, h),
					Color(0.010, 0.018, 0.024, 0.30 * t))

		# 选中层向上的一缕登塔光
		var pulse := 0.5 + 0.5 * sin(_pulse * 1.6)
		if selected >= 0 and selected < points.size():
			var p: Vector2 = points[selected]
			draw_rect(Rect2(p.x - 0.75, 0.0, 1.5, p.y),
				Color(0.46, 0.90, 0.82, 0.045 + 0.018 * pulse))

		# 塔层之间的光路：下层 → 上层
		for i in range(1, points.size()):
			var state := String(states[i]) if i < states.size() else "locked"
			var c := _state_color(state)
			var a: Vector2 = points[i - 1]
			var b: Vector2 = points[i]
			draw_line(a, b, Color(c.r, c.g, c.b, 0.07), 6.0, true)
			draw_line(a, b, Color(c.r, c.g, c.b, 0.46), 1.3, true)

		for i in points.size():
			var state := String(states[i]) if i < states.size() else "locked"
			var c := _state_color(state)
			draw_circle(points[i], 2.0, Color(c.r, c.g, c.b, 0.72))

		if selected >= 0 and selected < points.size():
			var p: Vector2 = points[selected]
			var sel_col := _state_color(String(states[selected]) if selected < states.size() else "locked")
			draw_circle(p, 34.0, Color(sel_col.r, sel_col.g, sel_col.b, 0.032 + 0.020 * pulse))
			draw_circle(p, 27.0, Color(sel_col.r, sel_col.g, sel_col.b, 0.072 + 0.026 * pulse))

		# 尘埃 / 灵光：静态但错落，避免塔身太空
		for i in 18:
			var x := 154.0 + fmod(float(i) * 83.0, 382.0)
			var y := 18.0 + fmod(float(i) * 137.0, 464.0)
			var col := Color(0.46, 0.90, 0.82)
			if i % 5 == 0:
				col = Color(0.93, 0.76, 0.42)
			draw_circle(Vector2(x, y), 0.7 + float(i % 3) * 0.35,
				Color(col.r, col.g, col.b, 0.10))


# ===================== 布局常量 =====================

const MAP_W := 566.0
const MAP_H := 600.0
const ROW_W := 330.0
const ROW_H := 44.0
const FLOOR_X := 190.0
const FLOOR_BOTTOM := 500.0
const SEAL_CENTER_X := 29.0
## 区域首领分支节点：贴在塔身左侧，用一条侧枝连到对应位面的中间层
const CORE_BRANCH_X := 64.0
const BAND_GAP := 16.0
## 最高一层往上还要留出「位面 · 三重投影」标签的高度，否则会被画布剪掉
const MAP_TOP_ROOM := 40.0
## 每层在横向上错开一点，形成登塔的折线，而不是一排直条
const ZIGZAG := [0.0, 12.0, 0.0, 12.0, 0.0, 12.0, 0.0, 12.0, 0.0, 12.0]

const DETAIL_W := 356.0
const COLOR_INK := Color(0.020, 0.034, 0.042, 0.965)
const COLOR_READY := Color(0.46, 0.90, 0.82)
const COLOR_CLEARED := Color(0.93, 0.76, 0.42)
const COLOR_LOCKED := Color(0.52, 0.58, 0.62)
const TOWER_CUTOUT := "res://assets/ui/facilities/tower_cutout.png"
const TOWER_RULES := "一名 BOSS 对应一层：在万界秘境击败哪名 BOSS，对应塔层立刻开放。\n每次通关随机感悟该层功法，已掌握的不再重复。\n锻造晶石：首通 9 块，第二次 6 块，之后每次 3 块。\n无伤通关：每层一次，可领 %d 晶石。\n最快用时从第 11 次挑战起记录（血量翻倍的场次）。\n击败大世界区域核心首领后，对应位面左侧会出现分支节点：可重复挑战该首领；每胜一次血量 +10%%（2 倍封顶），掉本首领装备与锻造晶石；双倍血量取胜得华彩卡，双倍血量无伤得纯华彩卡，双倍血量 10 秒内取胜得纸本水墨；每区首次无伤另给 50 晶石。"


var _map: TowerMap
## 地图自己套一层滚动：楼层再多也只滚地图，右边卡片（含「挑战此层」）不再被顶出可视区
var _map_scroll: ScrollContainer
var _floor_nodes: Array[Dictionary] = []
var _floor_by_no: Dictionary = {}
var _selected_floor := 0
## 左侧区域核心分支：选中后右侧记录碑展示重战详情，底部按钮才进入战斗
var _selected_core := ""
var _core_nodes: Dictionary = {}

var _detail_panel: PanelContainer
var _detail_watermark: Label
var _detail_scroll: ScrollContainer
var _detail_disc: PanelContainer
var _detail_disc_tag: Label
var _detail_disc_num: Label
var _detail_floor_label: Label
var _detail_name_label: Label
var _detail_status_label: Label
var _detail_status_dot: Label
var _detail_lock_label: Label
var _detail_best_cap: Label
var _detail_best_label: Label
var _detail_best_note: Label
var _detail_clears_row: Control
var _detail_clears_label: Label
var _detail_next_label: Label
## 本层掉落：标题右侧的「第 N 次通关」+ 动态行 + 底部规则注（2026-11-13 用户定）
var _detail_drop_box: VBoxContainer
var _detail_drop_hint: Label
var _detail_drop_rows: VBoxContainer
var _detail_drop_note: Label
var _detail_skill_cap: Label
var _detail_skill_count: Label
var _detail_skills_label: Label
var _detail_skills_note: Label
var _detail_nohit_label: Label
var _claim_btn: Button
var _claim_note: Label
var _detail_status: Label
var _challenge_btn: Button


func _init() -> void:
	panel_title = "万界塔"
	panel_hint = "ESC 关闭 · 顶部页签切换「塔层 / 试炼之路」"

func facility_visual() -> Dictionary:
	return UIKit.facility_style("tower")


## 9 层（3 位面 × 3 BOSS）→ 10 层（照影界首位已落地），用最高档面板高度，一屏能看全
func panel_size() -> Vector2:
	return Vector2(1000.0, 680.0)


## 塔面板自己管高度：左侧地图内部滚动、右侧详情卡整列钉住，
## 「挑战此层」永远停在卡片底部，不再需要把整页下滑才点得到。
func content_scrolls() -> bool:
	return false


func _build_content() -> void:
	content.add_child(_build_tab_bar())

	_page_tower = UIKit.vbox(10)
	_page_tower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_tower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_page_tower)

	_page_rogue = UIKit.vbox(8)
	_page_rogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_rogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_page_rogue)

	_build_tower_page()
	_build_rogue_page()
	_switch_tab(0)


## 塔层分页（原面板内容整体搬进这个分页，逻辑一行没改）
func _build_tower_page() -> void:
	_page_tower.add_child(_build_top_strip())

	var main := UIKit.hbox(14)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_tower.add_child(main)

	_build_map()
	main.add_child(_map_scroll)
	main.add_child(_build_detail())


# ===================== 分页：塔层 / 试炼之路 =====================

var _page_tower: VBoxContainer
var _page_rogue: VBoxContainer
var _tab_buttons: Array[Button] = []
var _tab_index := 0


## 顶部导航：两套玩法做成真正的「书签」页签。
## ⚠ 2026-11-08 用户报「试炼之路入口不明显」：原来是两枚 quiet_button（无底纯字 +
##   modulate 0.55），和下面的图例挤成一行，看着像静态标签。现在换成 tab_button
##   （选中=米纸签 + 墨字，未选中=暗墨签，两者都有底），再加朱砂「新玩法」印、
##   右侧引导语和一条细分隔线，把导航区从正文里切出来。
func _build_tab_bar() -> Control:
	var col := UIKit.vbox(0)
	var bar := UIKit.hbox(10)
	bar.name = "RogueTabBar"
	bar.custom_minimum_size = Vector2(0.0, 44.0)
	var labels := ["塔层", "试炼之路"]
	for i in labels.size():
		var btn := UIKit.tab_button(String(labels[i]),
			Vector2(150.0 if i == 0 else 180.0, 40.0),
			UIKit.C_ACCENT if i == 0 else UIKit.C_GREAT)
		btn.add_theme_font_size_override("font_size", UIKit.F_SUBTITLE)
		btn.tooltip_text = "点击切换到「%s」" % String(labels[i])
		btn.pressed.connect(_switch_tab.bind(i))
		bar.add_child(btn)
		_tab_buttons.append(btn)
		if i == 1:
			# 朱砂小印：即使停在塔层页，「试炼之路」也要能被一眼扫到
			var tag := UIKit.chip("新玩法", UIKit.C_DANGER, 12)
			tag.name = "RogueNewTag"
			_rogue_new_tag = tag
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.add_child(tag)
	bar.add_child(UIKit.spacer())
	# ⚠ 用项目通用的 ◆，别用 ◂ / → 这类箭头：三极泼墨体缺字会渲染成小方点
	var hint := UIKit.label("◆ 两套玩法 · 点页签切换", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	hint.name = "RogueTabHint"
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(hint)
	col.add_child(bar)
	var rule := ColorRect.new()
	rule.name = "RogueTabRule"
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.color = Color(0.95, 0.82, 0.45, 0.20)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	return col


## 试炼之路入口门禁（2026-11-08 用户定）：通关万界秘境·凡界的虎妖前，
## 页签与「踏入试炼」都不可点；通关后永久开放（domain_progress 已进存档）。
## ⚠ 只用 disabled / tooltip / 文案：不动 size（会破坏几何恒定），
##   🚫 不叠 modulate 到页签上（tab 选中态由 InkButton 自己管，叠了会抹平对比）。
func _refresh_trial_lock() -> void:
	var open := RogueDB.trial_unlocked()
	if _tab_buttons.size() > 1:
		var tab := _tab_buttons[1] as Button
		if tab != null:
			# ⚠ 页签**不 disabled**：锁死页签玩家就永远看不到右栏「踏入试炼」被禁用
			#   和那行解锁条件，等于把提示白做了。只压暗旁边的朱砂印 + tooltip 说明。
			tab.disabled = false
			tab.tooltip_text = "点击切换到「试炼之路」" if open else RogueDB.TRIAL_UNLOCK_HINT
	if _rogue_new_tag != null:
		# ⚠ Node 没有 get_child_or_null()（只有 get_node_or_null(NodePath)）
		var lbl: Label = null
		if _rogue_new_tag.get_child_count() > 0:
			lbl = _rogue_new_tag.get_child(0) as Label
		if lbl != null:
			lbl.text = "新玩法" if open else "未开放"
		_rogue_new_tag.modulate = Color.WHITE if open else Color(1, 1, 1, 0.55)
	if _rogue_enter_btn != null:
		_rogue_enter_btn.disabled = not open
		_rogue_enter_btn.tooltip_text = "" if open else RogueDB.TRIAL_UNLOCK_HINT
	if _rogue_lock_label != null:
		_rogue_lock_label.text = "" if open else "◆ 未开放 · " + RogueDB.TRIAL_UNLOCK_HINT


func _switch_tab(index: int) -> void:
	_refresh_trial_lock()
	_tab_index = index
	# 新手指引：第 6 章只在第一次点开试炼页时开
	if index == 1:
		Tutorial.note("rogue_tab")
		Tutorial.maybe_start("event:rogue_tab")
	if _page_tower != null:
		_page_tower.visible = index == 0
	if _page_rogue != null:
		_page_rogue.visible = index == 1
	for i in _tab_buttons.size():
		# ⚠ 别再用 modulate 压暗：tab_button 的选中态由 InkButton 自己换米纸签，
		#   叠一层 0.55 透明度会把「选中/未选中」的对比一起抹平（旧版入口不明显的元凶之一）
		UIKit.set_tab_selected(_tab_buttons[i], i == index)
	if index == 1:
		_refresh_rogue_page()


# ===================== 试炼之路分页 =====================

var _rogue_info_box: VBoxContainer
var _rogue_best_label: Label
var _rogue_runs_label: Label
var _rogue_crystal_label: Label
var _rogue_family_label: Label
var _rogue_enter_btn: Button
## 试炼入口未开放提示（常驻固定高度，解锁时只清空文字）
var _rogue_lock_label: Label
## 页签旁的朱砂小印（未开放时改文案）
var _rogue_new_tag: PanelContainer
## 本局流派（开局功法与卡池都按它走）
var _rogue_family := "sword"
var _rogue_family_buttons: Array[Button] = []


func _build_rogue_page() -> void:
	var accent: Color = UIKit.facility_style("insight").get("accent", UIKit.C_ACCENT)
	_page_rogue.add_child(UIKit.note_card(
		"踏入试炼：从零开始——不带装备、法宝与已学功法，只有本流派的基础招式。\n"
		+ "一层四关（三小关 + 一 BOSS），每关结束三选一；无限层，层数即成绩。", accent))
	var main := UIKit.hbox(16)
	main.name = "RogueMain"
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_rogue.add_child(main)

	var left := UIKit.vbox(8)
	left.name = "RogueLeft"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(left)
	_rogue_info_box = UIKit.vbox(6)
	_rogue_info_box.name = "RogueInfo"
	left.add_child(_rogue_info_box)

	var right := UIKit.vbox(8)
	right.name = "RogueRight"
	right.custom_minimum_size = Vector2(300.0, 0.0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	_rogue_best_label = UIKit.label("", 18, UIKit.C_TITLE)
	right.add_child(_rogue_best_label)
	_rogue_runs_label = UIKit.readable_label("", 12, UIKit.C_TEXT_DIM)
	right.add_child(_rogue_runs_label)
	_rogue_crystal_label = UIKit.readable_label("", 12, UIKit.C_TEXT_DIM)
	right.add_child(_rogue_crystal_label)
	_rogue_family_label = UIKit.readable_label("", 12, UIKit.C_TEXT_DIM)
	_rogue_family_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_rogue_family_label)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 6.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(gap)
	var pick_caption := UIKit.label("开局流派", 12, UIKit.C_TEXT_DIM)
	right.add_child(pick_caption)
	right.add_child(_build_family_picker())

	right.add_child(UIKit.spacer())
	# ⚠ 未开放提示常驻且固定高度，解锁时只清空文字 —— 若用 visible 切换，
	#   VBox 会重新分高，「踏入试炼」按钮漂移，probe_rogue_family_layout 的几何断言会红。
	_rogue_lock_label = _rogue_line("", 12, UIKit.C_ANNOUNCE_WARN)
	_rogue_lock_label.custom_minimum_size = Vector2(0.0, 26.0)
	right.add_child(_rogue_lock_label)
	_rogue_enter_btn = UIKit.primary_button("踏入试炼", Vector2(220.0, 46.0), accent)
	_rogue_enter_btn.add_theme_font_size_override("font_size", UIKit.F_SUBTITLE)
	_rogue_enter_btn.pressed.connect(_on_enter_rogue)
	right.add_child(_rogue_enter_btn)


## 开局流派选择：12 套全列（6 × 2 行），未解锁的压暗 + 点不动
## ⚠ 以前只列 START_FAMILIES（3 个），后 9 套玩家根本看不见，等于没做
func _build_family_picker() -> Control:
	var col := UIKit.vbox(6)
	_rogue_family_buttons.clear()
	var row: HBoxContainer = null
	for i in RogueDB.FAMILY_ORDER.size():
		if i % 6 == 0:
			row = UIKit.hbox(6)
			col.add_child(row)
		var key := String(RogueDB.FAMILY_ORDER[i])
		var btn := UIKit.tab_button(String(RogueDB.FAMILY_NAME.get(key, key)),
			Vector2(74.0, 30.0))
		btn.add_theme_font_size_override("font_size", UIKit.F_SMALL)
		btn.set_meta("family", key)
		btn.set_meta("tut", "rogue.family")
		btn.pressed.connect(_on_pick_family.bind(key))
		row.add_child(btn)
		_rogue_family_buttons.append(btn)
	_refresh_family_picker()
	return col


## 某流派是否已解锁（历史最高层达标）
func _family_is_unlocked(fam: String) -> bool:
	if not RogueDB.FAMILY_UNLOCK_FLOOR.has(fam):
		return false
	return int(RogueDB.FAMILY_UNLOCK_FLOOR[fam]) <= CharacterData.rogue_best_floor


func _on_pick_family(fam: String) -> void:
	if fam == _rogue_family:
		return
	if not _family_is_unlocked(fam):
		GameState.play_ui("ui_deny")
		return
	_rogue_family = fam
	Tutorial.note("rogue_family")
	GameState.play_ui("ui_tab")
	_refresh_family_picker()
	_refresh_rogue_page()


func _refresh_family_picker() -> void:
	for b in _rogue_family_buttons:
		var key := String(b.get_meta("family", "sword"))
		var unlocked := _family_is_unlocked(key)
		b.disabled = not unlocked
		UIKit.set_tab_selected(b, key == _rogue_family)
		if unlocked:
			b.modulate.a = 1.0
			b.tooltip_text = ""
		else:
			b.modulate.a = 0.38
			b.tooltip_text = "第 %d 层解锁" % int(RogueDB.FAMILY_UNLOCK_FLOOR.get(key, 0))


## ⚠ UIKit.label / readable_label 默认 autowrap=OFF，Label 的 minimum_size.x
##   = 整行文字宽度。左栏文案随流派长短差一倍，HBox 按 min size 分宽度，
##   面板会被撑到 1000~1194 不等、「踏入试炼」按钮左右漂移近 200px
##   （2026-11-08 用户报「选不同流派面板变形」，probe_rogue_family_layout 复现）。
##   统一开自动换行后 Label 最小宽度收敛，栏宽只由容器分配决定，切 12 套都不动。
func _rogue_line(text: String, size: int, color: Color, readable := true) -> Label:
	var l := UIKit.label(text, size, color)
	if readable:
		UIKit.make_readable(l)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _refresh_rogue_page() -> void:
	_refresh_trial_lock()
	if _rogue_best_label == null:
		return
	_rogue_best_label.text = "历史最高：第 %d 层" % CharacterData.rogue_best_floor
	_rogue_runs_label.text = "累计试炼 %d 局" % CharacterData.rogue_runs
	# 晶石累计：试炼之路唯一带出主模式的东西，摆出来玩家才知道爬了有什么用
	_rogue_crystal_label.text = "锻造晶石：%d 个（每关 +%d · 每层额外 +%d）" % [
		CharacterData.count_item(RogueDB.CRYSTAL_ID),
		RogueDB.CRYSTALS_PER_STAGE, RogueDB.CRYSTALS_PER_FLOOR_BONUS]
	var unlocked: Array[String] = []
	var locked: Array[String] = []
	for fam in RogueDB.FAMILY_UNLOCK_FLOOR.keys():
		var key := String(fam)
		if key == "generic":
			continue
		var fam_name := String(RogueDB.FAMILY_NAME.get(key, key))
		var need := int(RogueDB.FAMILY_UNLOCK_FLOOR[key])
		if need <= CharacterData.rogue_best_floor:
			unlocked.append(fam_name)
		else:
			locked.append("%s（第 %d 层）" % [fam_name, need])
	_rogue_family_label.text = "已解锁流派：%s\n未解锁：%s" % [
		"、".join(unlocked), "、".join(locked)]
	UIKit.clear_children(_rogue_info_box)
	# 本局流派：入口页把「选了会拿到什么」讲清楚，别让玩家点进去才发现是刀修
	var fam_key := _rogue_family
	var fam_name := String(RogueDB.FAMILY_NAME.get(fam_key, fam_key))
	var blurb: Dictionary = RogueDB.FAMILY_BLURB.get(fam_key, {})
	_rogue_info_box.add_child(_rogue_line("本局流派 · %s" % fam_name, 14, UIKit.C_ACCENT, false))
	_rogue_info_box.add_child(_rogue_line(
		String(blurb.get("mechanic", "")), 13, UIKit.C_TEXT))
	var kit_names: Array[String] = []
	for raw_sid in (RogueDB.family_start(fam_key).get("active", []) as Array):
		var sk := SkillDB.get_skill(String(raw_sid))
		kit_names.append(String(sk.get("skill_name", raw_sid)))
	if fam_key == "talisman":
		_rogue_info_box.add_child(_rogue_line(
			"开局四符：下一页由你从七张元素符里挑四张", 13, UIKit.C_TEXT_DIM))
	else:
		_rogue_info_box.add_child(_rogue_line(
			"开局四式：%s" % "、".join(kit_names), 13, UIKit.C_TEXT_DIM))
	_rogue_info_box.add_child(_rogue_line(
		"构筑路线：%s" % String(blurb.get("paths", "")), 12, UIKit.C_TEXT_FAINT))
	_rogue_info_box.add_child(_rogue_line(
		"初始开放：剑修 / 刀修 / 虎妖 / 符箓。其余随最高层解锁。", 13, UIKit.C_TEXT_DIM))
	_rogue_info_box.add_child(_rogue_line(
		"结算：每通关 1 关 → %d 块锻造晶石，每过 1 层 → 额外 %d 块；死亡 / 主动退出同样结算。" % [
			RogueDB.CRYSTALS_PER_STAGE, RogueDB.CRYSTALS_PER_FLOOR_BONUS],
		13, UIKit.C_TEXT_DIM))
	_rogue_info_box.add_child(_rogue_line(
		"⚠ 试炼中不产出任何主模式装备与材料，也不会写入存档进度。", 13, UIKit.C_WARN))


func _on_enter_rogue() -> void:
	# ⚠ 门禁守卫必须在 close() 之前：否则未解锁时点了会把面板关掉却不进战斗
	if not RogueDB.trial_unlocked():
		return
	GameState.play_ui("ui_tab")
	# 符箓：先结符（挑四张），选定后再进本
	if _rogue_family == "talisman":
		_open_talisman_loadout()
		return
	# ⚠ 面板是 get_tree().root 的直接子节点，change_scene_to_file 只换「当前场景」，
	# 挂在 root 下的面板不会被销毁 —— 不先 close 就会盖在战斗画面上，得玩家自己点关闭。
	# 塔层 / 世界核心两个入口都是这个写法（见 _on_challenge_floor / _on_enter_domain）。
	close()
	BattleResolver.start_rogue(_rogue_family)


## 结符页：挑满四张才允许开跑；取消则留在塔面板
func _open_talisman_loadout() -> void:
	var page = load("res://scripts/ui/talisman_loadout_page.gd").new()
	page.confirmed.connect(_on_talisman_picks)
	page.cancelled.connect(func() -> void:
		if is_instance_valid(page):
			page.queue_free())
	add_child(page)


func _on_talisman_picks(picks: Array) -> void:
	# ⚠ 顺序：先关面板再切场景（面板挂在 root 下，不会随场景一起销毁）
	close()
	BattleResolver.start_rogue("talisman", picks)


# ===================== 顶部图例 =====================

func _build_top_strip() -> Control:
	var strip := UIKit.hbox(8)
	strip.custom_minimum_size = Vector2(0.0, 22.0)

	var diamond := UIKit.label("◆", 8, Color(COLOR_CLEARED.r, COLOR_CLEARED.g, COLOR_CLEARED.b, 0.80))
	diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(diamond)

	var intro := UIKit.readable_label("一层一影 · 点选塔层或分支查看投影记录", 10, UIKit.C_TEXT_DIM)
	intro.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(intro)

	strip.add_child(UIKit.spacer())

	strip.add_child(_legend_item(COLOR_READY, "可挑战"))
	strip.add_child(_legend_item(COLOR_CLEARED, "已通关"))
	strip.add_child(_legend_item(COLOR_LOCKED, "未解锁"))

	var sep := ColorRect.new()
	sep.color = Color(0.72, 0.63, 0.46, 0.22)
	sep.custom_minimum_size = Vector2(1.0, 11.0)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(sep)

	var rule_summary := UIKit.label("首通 9 · 二通 6 · 之后 3 · 无伤 %d" % CharacterData.TOWER_NO_HIT_BONUS_CRYSTALS, 9, UIKit.C_TEXT_DIM)
	rule_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(rule_summary)

	var rule := UIKit.label("塔规", 9, Color(COLOR_CLEARED.r, COLOR_CLEARED.g, COLOR_CLEARED.b, 0.72))
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_STOP
	rule.mouse_default_cursor_shape = Control.CURSOR_HELP
	rule.tooltip_text = TOWER_RULES % CharacterData.TOWER_NO_HIT_BONUS_CRYSTALS
	strip.add_child(rule)

	return strip


func _legend_item(color: Color, text: String) -> Control:
	var box := UIKit.hbox(3)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := UIKit.label("●", 8, color)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(dot)
	var lbl := UIKit.label(text, 9, UIKit.C_TEXT_DIM)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	return box


# ===================== 塔身图 =====================

## 建图时量出来的整体下移量（见 _build_map 里的说明）
var _row_shift := 0.0


func _floor_row_y(index: int, band_index: int) -> float:
	return FLOOR_BOTTOM + _row_shift - float(index) * ROW_H - float(band_index) * BAND_GAP


func _build_map() -> void:
	_map = TowerMap.new()
	_map.custom_minimum_size = Vector2(MAP_W, MAP_H)
	_map.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_map.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_map.setup(UIKit.ui_texture(TOWER_CUTOUT))
	_map.size = Vector2(MAP_W, MAP_H)

	var floors := WorldDB.get_floors()
	# 位面分段按 DOMAINS 实际顺序算，不再写死「每 3 层一段」：
	# 照影界当前只有 1 位守关者，它是独立的第四段。
	var bands: Array = []
	var band_of: Dictionary = {}
	for i in floors.size():
		var did := String((floors[i] as Dictionary).get("domain_id", ""))
		if bands.is_empty() or String((bands.back() as Dictionary).get("domain_id", "")) != did:
			bands.append({"domain_id": did, "start": i, "end": i})
		else:
			(bands.back() as Dictionary)["end"] = i
		band_of[i] = bands.size() - 1

	# ⚠ 层数会随内容往上涨（照影界从 1 位守关者涨到 3 位），而画布高度是写死的 MAP_H：
	#   最高几层会落到**负 y**，被 TowerMap 的 clip_contents 剪掉，
	#   而 ScrollContainer 永远滚不到负坐标 —— 用户看到的就是「滑不到上面」。
	#   所以先按实际层数量一次需要多高：把整体往下推、把画布加长。
	if not floors.is_empty():
		var top_index := floors.size() - 1
		var top_y := FLOOR_BOTTOM - float(top_index) * ROW_H \
				- float(band_of.get(top_index, 0)) * BAND_GAP
		_row_shift = maxf(0.0, MAP_TOP_ROOM - top_y)
		var map_h := MAP_H + _row_shift
		_map.custom_minimum_size = Vector2(MAP_W, map_h)
		_map.size = Vector2(MAP_W, map_h)

	for i in floors.size():
		var f: Dictionary = floors[i]
		var floor_no := int(f.get("floor", i + 1))
		var row_y := _floor_row_y(i, int(band_of.get(i, 0)))
		var zig := float(ZIGZAG[i]) if i < ZIGZAG.size() else 0.0
		var node := _make_floor_node(f, floor_no, row_y, zig)
		_floor_nodes.append(node)
		_floor_by_no[floor_no] = node

	# 每个位面一段：只画一条细线，不做成框
	const CN_NUM := ["零", "一", "二", "三", "四", "五", "六"]
	for band in bands.size():
		var b: Dictionary = bands[band]
		var highest := int(b.get("end", 0))
		if highest <= 0 and band == 0:
			if floors.is_empty():
				continue
		var f2: Dictionary = floors[highest]
		var domain := WorldDB.get_domain_name(String(f2.get("domain_id", "")))
		var count := int(b.get("end", 0)) - int(b.get("start", 0)) + 1
		var top_y := _floor_row_y(highest, band)
		var label_y := top_y - 18.0
		var band_label := UIKit.label("%s · %s重投影" % [
			domain, CN_NUM[clampi(count, 0, CN_NUM.size() - 1)]], 9,
			Color(0.93, 0.76, 0.42, 0.62))
		band_label.position = Vector2(FLOOR_X, label_y)
		band_label.size = Vector2(ROW_W, 14.0)
		band_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map.add_child(band_label)
		var line := ColorRect.new()
		line.color = Color(0.93, 0.76, 0.42, 0.11)
		line.position = Vector2(FLOOR_X, label_y + 15.0)
		line.size = Vector2(ROW_W, 1.0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map.add_child(line)

	_build_core_branches()

	# 地图装进滚动框：视口不够高时只滚塔，右边详情卡保持钉住
	_map_scroll = ScrollContainer.new()
	_map_scroll.name = "TowerMapScroll"
	_map_scroll.custom_minimum_size = Vector2(MAP_W, 0.0)
	_map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_map_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_map_scroll.add_child(_map)


## 已击败的大世界区域首领 → 对应位面左侧的分支节点。
## 节点只负责「进入重战」，不占塔层、不产出功法 / 晶石。
func _build_core_branches() -> void:
	var by_domain: Dictionary = {}
	for raw in SecretWorldDB.REGIONS:
		var region: Dictionary = raw
		var region_id := String(region.get("region_id", ""))
		if String(region.get("core_boss_id", "")) == "" \
				or not CharacterData.is_core_killed(region_id):
			continue
		var domain_id := WorldDB.get_domain_id_for_realm(String(region.get("realm", "")))
		if domain_id == "":
			continue
		if not by_domain.has(domain_id):
			by_domain[domain_id] = []
		by_domain[domain_id].append(region)

	for domain_id in by_domain.keys():
		var anchor := _domain_branch_anchor(String(domain_id))
		if anchor == Vector2.ZERO:
			continue
		var regions: Array = by_domain[domain_id]
		for i in regions.size():
			var y := anchor.y + (float(i) - float(regions.size() - 1) * 0.5) * 56.0
			_add_core_branch(regions[i] as Dictionary, anchor, y)


func _domain_branch_anchor(domain_id: String) -> Vector2:
	var nodes: Array = []
	for node in _floor_nodes:
		var f: Dictionary = node.get("data", {})
		if String(f.get("domain_id", "")) == domain_id:
			nodes.append(node)
	if nodes.is_empty():
		return Vector2.ZERO
	return Vector2(nodes[nodes.size() / 2].get("point"))


func _add_core_branch(region: Dictionary, anchor: Vector2, y: float) -> void:
	var region_id := String(region.get("region_id", ""))
	var core := SecretWorldDB.get_core_boss(region_id)
	if core.is_empty():
		return
	var boss_name := String(core.get("name", "区域首领"))
	var region_name := String(region.get("name", region_id))
	var accent := COLOR_CLEARED
	var clears := CharacterData.get_core_clear_count(region_id)
	var mult := CharacterData.core_hp_multiplier(region_id)
	var replay_line := "首次重战" if clears <= 0 \
		else "已重战 ×%d · 下次血量 +%d%%" % [clears, int(round((mult - 1.0) * 100.0))]
	if mult >= 2.0 - 0.001:
		replay_line += "（封顶）"
	var nohit_line := "无伤 50 晶石：已领" if CharacterData.core_no_hit_rewarded(region_id) \
		else "无伤通关：50 晶石（本区一次）"

	var link := Line2D.new()
	link.points = PackedVector2Array([
		Vector2(CORE_BRANCH_X + 23.0, y),
		Vector2(anchor.x - 36.0, y),
	])
	link.width = 1.4
	link.default_color = Color(accent.r, accent.g, accent.b, 0.54)
	link.antialiased = true
	_map.add_child(link)

	var btn := Button.new()
	btn.position = Vector2(CORE_BRANCH_X - 23.0, y - 23.0)
	btn.size = Vector2(46.0, 46.0)
	btn.custom_minimum_size = btn.size
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.tooltip_text = "分支节点 · 重战 %s\n%s · 击败核心首领后解锁\n%s\n%s\n掉本首领装备 + 锻造晶石，不重复首杀奖励\n点击查看记录碑，再点底部「进入」开战" % [
		boss_name, region_name, replay_line, nohit_line]
	UIKit.attach_click_sfx(btn, "ui_tab")
	btn.pressed.connect(_select_core_branch.bind(region_id))
	btn.mouse_entered.connect(func() -> void: btn.modulate = Color(1.10, 1.10, 1.10, 1.0))
	btn.mouse_exited.connect(func() -> void: btn.modulate = Color.WHITE)
	_map.add_child(btn)

	var disc := PanelContainer.new()
	disc.position = Vector2(2.0, 2.0)
	disc.size = Vector2(42.0, 42.0)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.020, 0.034, 0.043, 0.96)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.86)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(21)
	disc.add_theme_stylebox_override("panel", sb)
	btn.add_child(disc)

	var col := UIKit.vbox(-2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(col)
	var tag := UIKit.label("战", 7, Color(accent.r, accent.g, accent.b, 0.78))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tag)
	var num := UIKit.label(boss_name.right(1), 15, UIKit.C_TEXT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(num)

	var info := UIKit.vbox(0)
	info.position = Vector2(CORE_BRANCH_X + 26.0, y - 30.0)
	info.size = Vector2(100.0, 28.0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(info)
	var region_lbl := UIKit.label(region_name, 8, UIKit.C_TEXT_DIM)
	region_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(region_lbl)
	var boss_lbl := UIKit.label("%s · %s" % [boss_name,
		"重战" if clears <= 0 else "重战 ×%d" % clears], 10, accent)
	boss_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	boss_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(boss_lbl)

	_core_nodes[region_id] = {
		"button": btn,
		"link": link,
		"info": info,
		"region": region,
		"boss_name": boss_name,
		"region_name": region_name,
	}


func _select_core_branch(region_id: String) -> void:
	if not CharacterData.is_core_killed(region_id):
		set_status("尚未击败该区域的核心首领", UIKit.C_WARN)
		return
	if _selected_core == region_id and _selected_floor == 0:
		return
	_selected_core = region_id
	_selected_floor = 0
	_detail_status.text = ""
	_detail_status.visible = false
	_refresh_selection()
	_refresh_detail()
	_detail_scroll.scroll_vertical = 0


## 只在右侧「进入」按钮按下时真正开战：点左侧分支只选中并展示
func _on_core_enter(region_id: String) -> void:
	if not CharacterData.is_core_killed(region_id):
		set_status("尚未击败该区域的核心首领", UIKit.C_WARN)
		return
	close()
	BattleResolver.start_world_core(region_id)


## 单个塔层：圆形层印 + 投影名 + 状态；整行是按钮，但不画成卡片
func _make_floor_node(f: Dictionary, floor_no: int, row_y: float, zig: float) -> Dictionary:
	var btn := Button.new()
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(ROW_W, ROW_H)
	btn.size = Vector2(ROW_W, ROW_H)
	btn.position = Vector2(FLOOR_X + zig, row_y)
	btn.set_meta("tut", "tower.floor")
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", _row_bg_style(Color(0.46, 0.90, 0.82, 0.035)))
	btn.add_theme_stylebox_override("pressed", _row_bg_style(Color(0.46, 0.90, 0.82, 0.075)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
	UIKit.attach_click_sfx(btn, "ui_tab")
	btn.pressed.connect(_select_floor.bind(floor_no))
	btn.mouse_entered.connect(func() -> void: btn.modulate = Color(1.08, 1.08, 1.08, 1.0))
	btn.mouse_exited.connect(func() -> void: btn.modulate = Color.WHITE)
	_map.add_child(btn)

	var mark := ColorRect.new()
	mark.color = Color(COLOR_CLEARED.r, COLOR_CLEARED.g, COLOR_CLEARED.b, 0.92)
	mark.position = Vector2(0.0, 11.0)
	mark.size = Vector2(2.0, 24.0)
	mark.visible = false
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(mark)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 1)
	margin.add_theme_constant_override("margin_bottom", 1)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(margin)

	var h := UIKit.hbox(10)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(h)

	var disc := PanelContainer.new()
	disc.custom_minimum_size = Vector2(42.0, 42.0)
	disc.size = Vector2(42.0, 42.0)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(disc)

	var disc_col := UIKit.vbox(-2)
	disc_col.alignment = BoxContainer.ALIGNMENT_CENTER
	disc_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(disc_col)
	var tag := UIKit.label("层", 7, Color(0.46, 0.90, 0.82, 0.75))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc_col.add_child(tag)
	var num := UIKit.label("%02d" % floor_no, 15, UIKit.C_TEXT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc_col.add_child(num)

	var info := UIKit.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(info)
	var name_lbl := UIKit.label(String(f.get("boss_name", "")), 14, UIKit.C_TEXT)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_lbl)
	var status := UIKit.label("", 9, UIKit.C_TEXT_DIM)
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(status)

	var point := Vector2(FLOOR_X + zig + SEAL_CENTER_X, row_y + ROW_H * 0.5)
	return {
		"floor": floor_no,
		"data": f,
		"domain": WorldDB.get_domain_name(String(f.get("domain_id", ""))),
		"button": btn,
		"disc": disc,
		"tag": tag,
		"num": num,
		"name": name_lbl,
		"status": status,
		"mark": mark,
		"point": point,
		"state": "locked",
	}


func _row_bg_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


# ===================== 投影记录碑 =====================

func _build_detail() -> Control:
	_detail_panel = PanelContainer.new()
	# 卡片高度跟着这一行给的空间走（内部 body 自己滚），
	# 不再用 MAP_H 当最小高度把整页撑到需要下滑
	_detail_panel.custom_minimum_size = Vector2(DETAIL_W, 0.0)
	_detail_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_INK
	style.border_color = Color(0.46, 0.90, 0.82, 0.30)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	_detail_panel.add_theme_stylebox_override("panel", style)

	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(root)

	var top_line := ColorRect.new()
	top_line.color = Color(0.93, 0.76, 0.42, 0.52)
	top_line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# 锚点左右不等的节点，_ready 后 size 会被重算 —— 高度只走 offset_bottom
	top_line.offset_bottom = 1.0
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_line)

	_detail_watermark = UIKit.label("", 76, Color(0.46, 0.90, 0.82, 0.060))
	_detail_watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_detail_watermark.position = Vector2(190.0, -12.0)
	_detail_watermark.size = Vector2(150.0, 100.0)
	_detail_watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_detail_watermark)

	# 碑底淡印：让记录碑在内容较少时也有塔的归属感
	var sigil := TextureRect.new()
	sigil.texture = UIKit.ui_texture("res://assets/ui/facilities/tower_medallion.png")
	sigil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sigil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sigil.position = Vector2(126.0, 292.0)
	sigil.size = Vector2(104.0, 104.0)
	sigil.modulate = Color(0.58, 0.95, 0.90, 0.060)
	sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sigil)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)

	var col := UIKit.vbox(9)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# ---- 抬头：层印 + 投影名 + 状态 ----
	var head := UIKit.hbox(9)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	_detail_disc = PanelContainer.new()
	_detail_disc.custom_minimum_size = Vector2(40.0, 40.0)
	_detail_disc.size = Vector2(40.0, 40.0)
	_detail_disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_detail_disc)
	var disc_col := UIKit.vbox(-2)
	disc_col.alignment = BoxContainer.ALIGNMENT_CENTER
	disc_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_disc.add_child(disc_col)
	_detail_disc_tag = UIKit.label("层", 7, Color(0.46, 0.90, 0.82, 0.75))
	_detail_disc_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_disc_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc_col.add_child(_detail_disc_tag)
	_detail_disc_num = UIKit.label("00", 14, UIKit.C_TEXT)
	_detail_disc_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_disc_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc_col.add_child(_detail_disc_num)

	var titles := UIKit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(titles)
	_detail_floor_label = UIKit.label("", 9, UIKit.C_TEXT_DIM)
	_detail_floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(_detail_floor_label)
	_detail_name_label = UIKit.label("", 17, Color(0.95, 0.92, 0.85))
	_detail_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(_detail_name_label)

	var status_box := UIKit.hbox(4)
	status_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(status_box)
	_detail_status_dot = UIKit.label("●", 8, COLOR_LOCKED)
	_detail_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.add_child(_detail_status_dot)
	_detail_status_label = UIKit.label("", 9, UIKit.C_TEXT_DIM)
	_detail_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.add_child(_detail_status_label)

	col.add_child(_hairline(Color(0.72, 0.63, 0.46, 0.18)))

	# ---- 中部滚动：记录 + 功法 + 无伤 ----
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_detail_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_detail_scroll)

	var body := UIKit.vbox(9)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_scroll.add_child(body)

	_detail_lock_label = UIKit.readable_label("", 10, UIKit.C_WARN)
	_detail_lock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_lock_label.visible = false
	body.add_child(_detail_lock_label)

	_detail_best_cap = UIKit.label("最快用时", 9, UIKit.C_TEXT_DIM)
	_detail_best_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_detail_best_cap)
	_detail_best_label = UIKit.label("—", 30, UIKit.C_TEXT)
	_detail_best_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_detail_best_label)
	_detail_best_note = UIKit.readable_label("", 9, UIKit.C_TEXT_DIM)
	_detail_best_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_detail_best_note)

	body.add_child(_hairline(Color(0.72, 0.63, 0.46, 0.14)))

	var stat_clears := _make_stat_row("通关次数")
	_detail_clears_row = stat_clears[0]
	_detail_clears_label = stat_clears[1]
	body.add_child(stat_clears[0])
	var stat_next := _make_stat_row("下次挑战")
	_detail_next_label = stat_next[1]
	body.add_child(stat_next[0])

	body.add_child(_hairline(Color(0.72, 0.63, 0.46, 0.14)))

	# ---- 本层掉落（2026-11-13 用户定：写清本层掉什么 + 概率）----
	_detail_drop_box = UIKit.vbox(2)
	_detail_drop_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_detail_drop_box)
	var drop_head := UIKit.hbox(6)
	drop_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_drop_box.add_child(drop_head)
	var drop_dot := UIKit.label("◆", 7, Color(0.93, 0.76, 0.42, 0.75))
	drop_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drop_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_head.add_child(drop_dot)
	var drop_cap := UIKit.label("本层掉落", 10, Color(0.93, 0.76, 0.42, 0.86))
	drop_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drop_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_head.add_child(drop_cap)
	drop_head.add_child(UIKit.spacer())
	_detail_drop_hint = UIKit.label("", 9, UIKit.C_TEXT_DIM)
	_detail_drop_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_drop_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_head.add_child(_detail_drop_hint)
	_detail_drop_rows = UIKit.vbox(1)
	_detail_drop_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_drop_box.add_child(_detail_drop_rows)
	_detail_drop_note = UIKit.readable_label("", 9, UIKit.C_TEXT_DIM)
	_detail_drop_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_drop_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_drop_box.add_child(_detail_drop_note)

	body.add_child(_hairline(Color(0.72, 0.63, 0.46, 0.14)))

	var skill_head := UIKit.hbox(6)
	skill_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(skill_head)
	var skill_dot := UIKit.label("◆", 7, Color(0.93, 0.76, 0.42, 0.75))
	skill_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skill_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_head.add_child(skill_dot)
	_detail_skill_cap = UIKit.label("投影功法", 10, Color(0.93, 0.76, 0.42, 0.86))
	_detail_skill_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_skill_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_head.add_child(_detail_skill_cap)
	skill_head.add_child(UIKit.spacer())
	_detail_skill_count = UIKit.label("", 9, UIKit.C_TEXT_DIM)
	_detail_skill_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_skill_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_head.add_child(_detail_skill_count)

	_detail_skills_label = UIKit.readable_label("", 10, Color(0.88, 0.86, 0.80))
	_detail_skills_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_skills_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_detail_skills_label)
	_detail_skills_note = UIKit.readable_label("已掌握的功法不会重复感悟", 9, UIKit.C_TEXT_DIM)
	_detail_skills_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_detail_skills_note)

	body.add_child(_hairline(Color(0.72, 0.63, 0.46, 0.14)))

	var nohit_head := UIKit.hbox(6)
	nohit_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(nohit_head)
	var nohit_dot := UIKit.label("◆", 7, Color(0.93, 0.76, 0.42, 0.75))
	nohit_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nohit_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nohit_head.add_child(nohit_dot)
	var nohit_cap := UIKit.label("无伤通关", 10, Color(0.93, 0.76, 0.42, 0.86))
	nohit_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nohit_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nohit_head.add_child(nohit_cap)
	nohit_head.add_child(UIKit.spacer())
	_detail_nohit_label = UIKit.label("", 9, UIKit.C_TEXT_DIM)
	_detail_nohit_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_nohit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nohit_head.add_child(_detail_nohit_label)

	var flavor := UIKit.label("登塔问道 · 一层一影", 9, Color(0.93, 0.76, 0.42, 0.24))
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(flavor)

	col.add_child(_hairline(Color(0.72, 0.63, 0.46, 0.18)))

	# ---- 底部动作：永远可见 ----
	_challenge_btn = UIKit.primary_button("挑战", Vector2(0.0, 40.0), Color(0.46, 0.90, 0.82))
	UIKit.set_click_sfx(_challenge_btn, "ui_confirm")
	_challenge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challenge_btn.pressed.connect(_on_challenge_selected)
	# 新手指引锚点：c5 教玩家点右下角「挑战」进入虎妖层
	_challenge_btn.set_meta("tut", "tower.challenge")
	col.add_child(_challenge_btn)

	_claim_btn = Button.new()
	_claim_btn.text = ""
	_claim_btn.focus_mode = Control.FOCUS_NONE
	_claim_btn.custom_minimum_size = Vector2(0.0, 28.0)
	_claim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_claim_btn.add_theme_stylebox_override("normal", _claim_style(Color(0.46, 0.90, 0.82, 0.07)))
	_claim_btn.add_theme_stylebox_override("hover", _claim_style(Color(0.46, 0.90, 0.82, 0.16)))
	_claim_btn.add_theme_stylebox_override("pressed", _claim_style(Color(0.46, 0.90, 0.82, 0.24)))
	_claim_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_claim_btn.add_theme_color_override("font_color", Color(0.93, 0.80, 0.50))
	_claim_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.66))
	UIKit.set_readable_font(_claim_btn, 11)
	UIKit.attach_click_sfx(_claim_btn, "ui_confirm")
	_claim_btn.pressed.connect(_on_claim_selected)
	col.add_child(_claim_btn)

	_claim_note = UIKit.readable_label("", 9, UIKit.C_TEXT_DIM)
	_claim_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_claim_note)

	_detail_status = UIKit.readable_label("", 9, UIKit.C_OK)
	_detail_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_status.visible = false
	col.add_child(_detail_status)

	return _detail_panel


## 本层掉落的一行：名称 + 数量在左，概率在右（2026-11-13 用户定）
func _make_drop_row(text: String, chance: float) -> Control:
	var row := UIKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := UIKit.readable_label(text, 9, Color(0.88, 0.86, 0.80))
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(n)
	var pct := UIKit.label("%d%%" % roundi(chance * 100.0), 9,
		Color(0.93, 0.76, 0.42) if chance < 0.999 else UIKit.C_TEXT_DIM)
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pct)
	return row


func _make_stat_row(key: String) -> Array:
	var row := UIKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := UIKit.label(key, 9, UIKit.C_TEXT_DIM)
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(k)
	row.add_child(UIKit.spacer())
	var v := UIKit.readable_label("—", 10, Color(0.88, 0.86, 0.80))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	return [row, v]


func _hairline(color: Color) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _claim_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.93, 0.76, 0.42, 0.34)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


# ===================== 刷新 =====================

func _refresh_content() -> void:
	if _floor_nodes.is_empty():
		return
	for node in _floor_nodes:
		_refresh_floor_node(node)
	if _selected_core != "":
		if not CharacterData.is_core_killed(_selected_core):
			_selected_core = ""
		_selected_floor = 0
	elif _selected_floor <= 0 or not _floor_by_no.has(_selected_floor):
		_selected_floor = _default_floor()
	_refresh_selection()
	_refresh_detail()
	_refresh_rogue_page()
	# 打开面板时选中的是「当前进度那一层」，它可能落在地图的任一端：
	# 布局还没算完，所以这一跳要 deferred，否则拿到的是 0 高度
	_scroll_map_to.call_deferred(_selected_floor)


## 选中层落在地图可视区外时，把地图滚到它（右侧详情卡钉住，只有地图滚）
func _scroll_map_to(floor_no: int) -> void:
	if _map_scroll == null or not _floor_by_no.has(floor_no):
		return
	var btn := (_floor_by_no[floor_no] as Dictionary).get("button", null) as Control
	if btn == null:
		return
	var below := btn.position.y + btn.size.y - _map_scroll.size.y
	if below > 0.0:
		_map_scroll.scroll_vertical = int(below + 6.0)


## 默认选中「当前进度那一层」：优先第一个还没拿首通奖励的已解锁层
func _default_floor() -> int:
	var fallback := 1
	for node in _floor_nodes:
		var floor_no := int(node.get("floor", 1))
		if CharacterData.is_tower_floor_unlocked(floor_no):
			fallback = floor_no
			if not CharacterData.is_tower_first_kill_done(floor_no):
				return floor_no
	return fallback


func _state_color(state: String) -> Color:
	match state:
		"cleared":
			return COLOR_CLEARED
		"ready":
			return COLOR_READY
		_:
			return COLOR_LOCKED


func _refresh_floor_node(node: Dictionary) -> void:
	var floor_no := int(node.get("floor", 1))
	var f: Dictionary = node.get("data", {})
	var unlocked := CharacterData.is_tower_floor_unlocked(floor_no)
	var cleared := CharacterData.is_tower_first_kill_done(floor_no)
	var state := "cleared" if cleared else ("ready" if unlocked else "locked")
	node["state"] = state
	var accent := _state_color(state)

	var disc: PanelContainer = node.get("disc")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.020, 0.034, 0.043, 0.96)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.80 if unlocked else 0.42)
	sb.set_border_width_all(2 if state != "locked" else 1)
	sb.set_corner_radius_all(21)
	disc.add_theme_stylebox_override("panel", sb)

	var tag: Label = node.get("tag")
	tag.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.78))
	var num: Label = node.get("num")
	num.add_theme_color_override("font_color", accent if unlocked else Color(0.62, 0.66, 0.70))
	var name_lbl: Label = node.get("name")
	name_lbl.add_theme_color_override("font_color",
		Color(0.94, 0.91, 0.84) if unlocked else Color(0.63, 0.67, 0.70))
	var status: Label = node.get("status")
	var status_text := ""
	if cleared:
		status_text = "已通关 ×%d" % CharacterData.get_tower_clear_count(floor_no)
		status.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.88))
	elif unlocked:
		status_text = "可挑战 · 第 %d 次" % CharacterData.tower_challenge_index(floor_no)
		status.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.88))
	else:
		status_text = "未解锁"
		status.add_theme_color_override("font_color", Color(0.54, 0.58, 0.62))
	status.text = status_text

	var btn: Button = node.get("button")
	var tip := "%s · 第 %d 层" % [String(f.get("boss_name", "")), floor_no]
	if not unlocked:
		tip += "\n" + CharacterData.tower_floor_lock_reason(floor_no)
	elif cleared:
		tip += "\n已通关 ×%d" % CharacterData.get_tower_clear_count(floor_no)
	else:
		tip += "\n可挑战"
	btn.tooltip_text = tip


func _refresh_selection() -> void:
	var points: Array = []
	var states: Array = []
	var core_selected := _selected_core != ""
	for node in _floor_nodes:
		var floor_no := int(node.get("floor", 1))
		var selected := not core_selected and floor_no == _selected_floor
		var mark: ColorRect = node.get("mark")
		mark.visible = selected
		var btn: Button = node.get("button")
		var sel_accent := _state_color(String(node.get("state", "locked")))
		btn.add_theme_stylebox_override("normal",
			_row_bg_style(Color(sel_accent.r, sel_accent.g, sel_accent.b, 0.055)) if selected else StyleBoxEmpty.new())
		points.append(node.get("point"))
		states.append(String(node.get("state", "locked")))
	for rid in _core_nodes.keys():
		var node: Dictionary = _core_nodes[rid]
		var selected_core := String(rid) == _selected_core
		var core_btn: Button = node.get("button")
		core_btn.add_theme_stylebox_override("normal",
			_core_selected_style() if selected_core else StyleBoxEmpty.new())
		var link: Line2D = node.get("link")
		if link != null:
			var c := link.default_color
			link.default_color = Color(c.r, c.g, c.b, 0.90 if selected_core else 0.54)
	_map.set_data(points, states, -1 if core_selected else _selected_floor - 1)


func _core_selected_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COLOR_READY.r, COLOR_READY.g, COLOR_READY.b, 0.10)
	sb.border_color = Color(COLOR_READY.r, COLOR_READY.g, COLOR_READY.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(23)
	return sb


func _select_floor(floor_no: int) -> void:
	if not _floor_by_no.has(floor_no):
		return
	# ⚠ 教学事件必须在「已经选中这一层」的早退之前发：打开面板时默认就选中了第 1 层，
	#   玩家照提示点第一层会走进上面那条早退分支 —— 事件不发，指引只能跳过（2026-11-12 用户报）。
	Tutorial.note("tower_floor_pick")
	if floor_no == _selected_floor and _selected_core == "":
		return
	_selected_core = ""
	_selected_floor = floor_no
	_detail_status.text = ""
	_detail_status.visible = false
	_refresh_selection()
	_refresh_detail()
	_detail_scroll.scroll_vertical = 0
	_scroll_map_to(floor_no)


func _refresh_detail() -> void:
	if _selected_core != "":
		_refresh_core_detail()
		return
	var node: Dictionary = _floor_by_no.get(_selected_floor, {})
	if node.is_empty():
		return
	_detail_best_cap.text = "最快用时"
	_detail_skill_cap.text = "投影功法"
	_detail_clears_row.visible = true
	var f: Dictionary = node.get("data", {})
	var floor_no := int(node.get("floor", 1))
	var boss := String(f.get("boss_name", ""))
	var domain := String(node.get("domain", ""))
	var unlocked := CharacterData.is_tower_floor_unlocked(floor_no)
	var cleared := CharacterData.is_tower_first_kill_done(floor_no)
	var count := CharacterData.get_tower_clear_count(floor_no)
	var best := CharacterData.get_tower_best_time(floor_no)
	var state := "cleared" if cleared else ("ready" if unlocked else "locked")
	var accent := _state_color(state)

	_detail_watermark.text = "%02d" % floor_no
	_detail_floor_label.text = "第 %02d 层 · %s" % [floor_no, domain]
	_detail_name_label.text = "%s · 投影" % boss
	_detail_disc_num.text = "%02d" % floor_no
	_detail_disc_tag.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.78))
	_detail_disc_num.add_theme_color_override("font_color", accent)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.020, 0.034, 0.043, 0.96)
	dsb.border_color = Color(accent.r, accent.g, accent.b, 0.80)
	dsb.set_border_width_all(2 if state != "locked" else 1)
	dsb.set_corner_radius_all(20)
	_detail_disc.add_theme_stylebox_override("panel", dsb)

	_detail_status_dot.add_theme_color_override("font_color",
		accent if unlocked else Color(0.82, 0.64, 0.48))
	_detail_status_label.text = "已通关" if cleared else ("可挑战" if unlocked else "未解锁")
	_detail_status_label.add_theme_color_override("font_color",
		Color(accent.r, accent.g, accent.b, 0.86) if unlocked else Color(0.82, 0.64, 0.48))

	_detail_lock_label.visible = not unlocked
	_detail_lock_label.text = "此层尚未开启。\n%s" % CharacterData.tower_floor_lock_reason(floor_no)

	if best >= 0.0:
		_detail_best_label.text = CharacterData.format_duration(best)
		_detail_best_label.add_theme_color_override("font_color", COLOR_CLEARED)
		_detail_best_note.text = "第 11 次起的场次记录"
	else:
		_detail_best_label.text = "—"
		_detail_best_label.add_theme_color_override("font_color",
			UIKit.C_TEXT_DIM if not unlocked else Color(0.76, 0.73, 0.66))
		_detail_best_note.text = "首通后从第 11 次挑战起记录" if not cleared else "第 11 次挑战起记录"

	_detail_clears_label.text = ("×%d" % count) if cleared else "尚未通关"
	_detail_clears_label.add_theme_color_override("font_color",
		Color(0.93, 0.76, 0.42) if cleared else Color(0.62, 0.62, 0.60))

	var chall := CharacterData.tower_challenge_index(floor_no)
	var mult := CharacterData.tower_hp_multiplier(floor_no)
	if mult > 1.0:
		var next_text := "第 %d 次 · 血量 +%d%%" % [chall, int(round((mult - 1.0) * 100.0))]
		if mult >= 2.0 - 0.001:
			next_text += "（封顶）"
		_detail_next_label.text = next_text
		_detail_next_label.add_theme_color_override("font_color", Color(0.88, 0.70, 0.45))
	else:
		_detail_next_label.text = "第 %d 次 · 基础血量" % chall
		_detail_next_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.68))

	# ---- 本层掉落：数量按「下次通关」档位，概率现读 ItemDB ----
	_detail_drop_box.visible = true
	_detail_drop_hint.text = "按第 %d 次通关" % chall
	UIKit.clear_children(_detail_drop_rows)
	# 投影沿用本体 boss_id：先列本体的装备 / 材料掉落（含默认 50% / 显式 20%）
	var boss_id := String(f.get("boss_id", ""))
	for raw in ItemDB.get_drops_for_boss(boss_id):
		var drop: Dictionary = raw
		var iid := String(drop.get("item_id", ""))
		var nm := String(iid)
		if String(drop.get("kind", "equipment")) == "material" \
				or not ItemDB.get_material(iid).is_empty():
			nm = ItemDB.get_material_name(iid)
		else:
			var tpl := ItemDB.get_equipment_template(iid)
			if not tpl.is_empty():
				nm = String(tpl.get("equipment_name", iid))
		_detail_drop_rows.add_child(_make_drop_row(
			"%s ×%d" % [nm, maxi(1, int(drop.get("count", 1)))],
			ItemDB.get_drop_chance(drop)))
	# 塔层自己的材料表（锻造晶石按下次通关档位）
	for raw in ItemDB.get_tower_drops(floor_no, chall):
		var entry: Dictionary = raw
		var mid := String(entry.get("item_id", ""))
		var drop_n := maxi(1, int(entry.get("count", 1)))
		_detail_drop_rows.add_child(_make_drop_row(
			"%s ×%d" % [ItemDB.get_material_name(mid), drop_n],
			ItemDB.get_drop_chance(entry)))
	# 蕴仙髓 5% 是塔专属的独立掷骰，不在塔层表里
	_detail_drop_rows.add_child(_make_drop_row(
		"%s ×1" % ItemDB.get_material_name(CharacterData.YUNXIAN_MATERIAL),
		ItemDB.TOWER_YUNXIAN_DROP_CHANCE))
	var soul := ItemDB.soul_for_boss(String(f.get("boss_id", "")))
	var soul_name := String(soul.get("name", "BOSS 元魂"))
	var double_hp := CharacterData.tower_hp_multiplier_at(chall) >= 2.0 - 0.001
	if double_hp and not soul.is_empty():
		_detail_drop_rows.add_child(_make_drop_row(
			"%s ×1（双倍）" % soul_name, ItemDB.TOWER_SOUL_DROP_CHANCE))
	# 元魂未进本场时给一行预告；进本场时行内已标「双倍」，不再重复占一行
	if not soul.is_empty() and not double_hp:
		_detail_drop_note.text = "第 %d 次起（双倍血量）：%s %d%%" % [
			CharacterData.TOWER_RECORD_MIN_CLEAR, soul_name,
			roundi(ItemDB.TOWER_SOUL_DROP_CHANCE * 100.0)]
		_detail_drop_note.visible = true
	else:
		_detail_drop_note.text = ""
		_detail_drop_note.visible = false

	var ids := WorldDB.get_floor_reward_skills(floor_no)
	if ids.is_empty():
		_detail_skill_count.text = "暂无"
		_detail_skills_label.text = "占位 BOSS 尚未登记招式，暂无功法可感悟。"
		_detail_skills_label.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
		_detail_skills_note.visible = false
	else:
		var names := PackedStringArray()
		for sid in ids:
			names.append(SkillDB.get_skill_name(String(sid)))
		_detail_skill_count.text = "%d 门随机" % ids.size()
		_detail_skills_label.text = "、".join(names)
		_detail_skills_label.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80))
		_detail_skills_note.visible = true

	var sr := CharacterData.tower_no_hit_reward_state(floor_no)
	if not unlocked:
		_detail_nohit_label.text = "—"
		_detail_nohit_label.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
	elif sr == "ready":
		_detail_nohit_label.text = "可领取 %d 晶石" % CharacterData.TOWER_NO_HIT_BONUS_CRYSTALS
		_detail_nohit_label.add_theme_color_override("font_color", COLOR_CLEARED)
	elif sr == "claimed":
		_detail_nohit_label.text = "已领取"
		_detail_nohit_label.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
	else:
		_detail_nohit_label.text = "尚未达成"
		_detail_nohit_label.add_theme_color_override("font_color", Color(0.70, 0.66, 0.56))

	_claim_btn.visible = unlocked and sr == "ready"
	_claim_btn.text = "领取无伤通关 · %d 晶石" % CharacterData.TOWER_NO_HIT_BONUS_CRYSTALS
	if not unlocked:
		_claim_note.text = ""
	elif sr == "ready":
		_claim_note.text = "每层仅一次 · 领取后不会再次触发"
	elif sr == "claimed":
		_claim_note.text = "本层无伤奖励已领取"
	else:
		_claim_note.text = "任意一次全程不掉血通关后可领 %d 晶石" % CharacterData.TOWER_NO_HIT_BONUS_CRYSTALS

	if not unlocked:
		_challenge_btn.text = "尚未解锁"
		_challenge_btn.disabled = true
	elif cleared:
		_challenge_btn.text = "再战第 %02d 层" % floor_no
		_challenge_btn.disabled = false
	else:
		_challenge_btn.text = "挑战第 %02d 层" % floor_no
		_challenge_btn.disabled = false


## 区域核心分支：右侧记录碑展示重战次数 / 血量成长 / 掉落；点底部「进入」才开战
func _refresh_core_detail() -> void:
	var node: Dictionary = _core_nodes.get(_selected_core, {})
	var core := SecretWorldDB.get_core_boss(_selected_core)
	if core.is_empty():
		return
	var boss_name := String(core.get("name", node.get("boss_name", "区域首领")))
	var region_name := String(node.get("region_name", _selected_core))
	var clears := CharacterData.get_core_clear_count(_selected_core)
	var mult := CharacterData.core_hp_multiplier(_selected_core)
	var rewarded := CharacterData.core_no_hit_rewarded(_selected_core)
	var accent := COLOR_CLEARED

	_detail_watermark.text = "核"
	_detail_floor_label.text = "区域核心 · %s" % region_name
	_detail_name_label.text = "%s · 重战" % boss_name
	_detail_disc_tag.text = "核"
	_detail_disc_num.text = boss_name.right(1)
	_detail_disc_tag.add_theme_color_override("font_color",
		Color(accent.r, accent.g, accent.b, 0.78))
	_detail_disc_num.add_theme_color_override("font_color", accent)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.020, 0.034, 0.043, 0.96)
	dsb.border_color = Color(accent.r, accent.g, accent.b, 0.80)
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(20)
	_detail_disc.add_theme_stylebox_override("panel", dsb)

	_detail_status_dot.add_theme_color_override("font_color", accent)
	_detail_status_label.text = ("已重战 ×%d" % clears) if clears > 0 else "可重战"
	_detail_status_label.add_theme_color_override("font_color",
		Color(accent.r, accent.g, accent.b, 0.86))
	_detail_lock_label.visible = false

	_detail_best_cap.text = "重战次数"
	_detail_best_label.text = ("×%d" % clears) if clears > 0 else "—"
	_detail_best_label.add_theme_color_override("font_color",
		COLOR_CLEARED if clears > 0 else UIKit.C_TEXT_DIM)
	_detail_best_note.text = "每胜一次，下次血量 +10%，最多 2 倍"
	_detail_clears_row.visible = false
	# 核心分支的掉落写在下面的「重战掉落」里，塔层掉落段收起
	_detail_drop_box.visible = false

	var next_text := "首次重战 · 基础血量"
	if mult > 1.0:
		next_text = "下次 · 血量 +%d%%" % int(round((mult - 1.0) * 100.0))
		if mult >= 2.0 - 0.001:
			next_text += "（封顶）"
	_detail_next_label.text = next_text
	_detail_next_label.add_theme_color_override("font_color",
		Color(0.88, 0.70, 0.45) if mult > 1.0 else Color(0.72, 0.72, 0.68))

	_detail_skill_cap.text = "重战掉落"
	_detail_skill_count.text = "装备 + 晶石"
	_detail_skills_label.text = "本首领装备与锻造晶石；不产出功法。双倍血量胜：华彩卡；双倍无伤：纯华彩卡；双倍血量 10 秒内：纸本水墨。"
	_detail_skills_label.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80))
	_detail_skills_note.visible = false

	_detail_nohit_label.text = "已领 50 晶石" if rewarded else "首次无伤：50 晶石"
	_detail_nohit_label.add_theme_color_override("font_color",
		UIKit.C_TEXT_DIM if rewarded else COLOR_CLEARED)
	_claim_btn.visible = false
	_claim_note.text = "本区无伤奖励已领取" if rewarded else "首次无伤通关结算时自动发放"

	_challenge_btn.text = "进入"
	_challenge_btn.disabled = false


func _on_claim_selected() -> void:
	var floor_no := _selected_floor
	_on_claim_no_hit_reward(floor_no)
	_detail_status.text = "无伤奖励已领取 · 锻造晶石已入包"
	_detail_status.visible = true
	_detail_status.add_theme_color_override("font_color", UIKit.C_OK)


func _on_challenge_selected() -> void:
	if _selected_core != "":
		_on_core_enter(_selected_core)
		return
	if _selected_floor <= 0:
		return
	_on_challenge(_selected_floor)


# ===================== 动作 =====================

## 领取该层的无伤通关奖励（任意一次全程未掉血通关 → 固定晶石，每层仅一次）
func _on_claim_no_hit_reward(floor_no: int) -> void:
	var got := CharacterData.claim_tower_no_hit_reward(floor_no)
	if got <= 0:
		set_status("这个奖励已经领过了。", UIKit.C_WARN)
		_refresh_content()
		return
	set_status("第 %d 层无伤通关奖励：锻造晶石 ×%d" % [floor_no, got], UIKit.C_OK)
	_refresh_content()


## 进入真实战斗：胜利后由 BattleResolver 结算
## 首杀不在结算瞬间发放：结算只出结果，随后弹出感悟面板，玩家确认后才写入 learned_skills
## 首通与再战走同一条路径，区别只在结算时是否还有功法可发
func _on_challenge(floor_no: int) -> void:
	if not CharacterData.is_tower_floor_unlocked(floor_no):
		set_status("该层尚未解锁", UIKit.C_DANGER)
		return
	# 新手指引：c5「点右下角挑战」听这个事件（放在解锁校验之后，
	# 点了没解锁的白按钮不会把教学步放过去）
	Tutorial.note("tower_challenge")
	# 先关面板（恢复暂停并自我销毁），否则切场景后会残留一个画布层挡住战斗 UI
	close()
	BattleResolver.start_tower(floor_no)
