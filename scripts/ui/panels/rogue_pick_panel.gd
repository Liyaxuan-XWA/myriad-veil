class_name RoguePickPanel
extends SystemPanel
## 试炼之路「玉简三选一」—— 每次小关 / BOSS 关结束弹出
##
## 交互（2026-11-08 用户定）：
##   - 三枚玉简横向悬浮，底色按稀有度（青 / 紫 / 金），朱砂印标档位
##   - **两步式**：点玉简只「选中」（可改选），下方「确认选择」按钮才真正结算
##   - 防误触三道：① 弹出后 320ms 内不受理点选 ② 弹出瞬间左键若正按着，
##     必须先收到一次真实的「松开」 ③ 选中后 280ms 内确认按钮保持灰着
##   - **不允许跳过**：ESC 不生效（can_close = false），必须选一张并确认
##
## ⚠ 起因：清怪时玩家一直连点左键攻击，面板一弹出，落在玉简上的那一下
##   （甚至同一帧的后续点击）会直接把卡收走，选到的完全是随机的。
##   ⚠ 所以 `picked` **只能**由 `_on_confirm_pressed` 发，别在卡片回调里 emit。
##
## 美术接入：卡片底走 UIKit.accent_card_style（换皮改一处）；
## 将来要做「玉简」贴图，把 _make_card 的 PanelContainer 换成 TextureRect 即可，逻辑不动。

signal picked(buff_id: String)

## 防误触时间窗（毫秒）：面板刚现身 / 刚改选，都留一段「看得清、点不动」的时间
const OPEN_GUARD_MS := 320
const CONFIRM_GUARD_MS := 280
## 极端兜底：万一收不到「松开」事件（合成事件 / 远程桌面），别把面板锁死
const RELEASE_FALLBACK_MS := 700

var choices: Array = []
var floor_no := 1
var stage_no := 1
## 当前选中的玉简 id；只有「确认选择」才把它交出去
var selected_id: String = ""

var _row: HBoxContainer
var _confirm_btn: Button
var _status_label: Label
var _select_ready_at := 0
var _confirm_ready_at := 0
var _selected_name := ""
var _confirmed := false
## 打开那一刻左键正按着 → 必须先松开一次，否则连点会一路穿进来
var _require_release := false


func _init() -> void:
	panel_title = "试炼 · 择一而进"
	panel_hint = "先择玉简，再按下方确认 · 本次必须选择"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("insight")


func panel_size() -> Vector2:
	# 比旧版高 30：多出来的空间全给底部确认行，玉简本身略收矮。
	# ⚠ 内容区走 ScrollContainer（按最小尺寸贴顶排），面板再高只会多出底部空白，
	#   不会把卡片撑开 —— 500 实测刚好留一圈呼吸位，不出现滚动条。
	return Vector2(900.0, 500.0)


## 必须在 add_child 之前调用
func setup(p_choices: Array, p_floor: int, p_stage: int) -> void:
	choices = p_choices.duplicate()
	floor_no = p_floor
	stage_no = p_stage


func can_close() -> bool:
	return false


## 必须选一张，所以连关闭按钮都不画（免得玩家对着死按钮点）
func shows_close_button() -> bool:
	return false


func open() -> void:
	if _visible:
		return
	selected_id = ""
	_selected_name = ""
	_confirmed = false
	_require_release = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var now := Time.get_ticks_msec()
	_select_ready_at = now + OPEN_GUARD_MS
	_confirm_ready_at = now + OPEN_GUARD_MS
	super()


func _input(event: InputEvent) -> void:
	super(event)
	if not _visible or not _require_release:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_require_release = false


func _process(_delta: float) -> void:
	# 按钮的「可点 / 灰着」由真实时间决定：冷却没走完就是灰的，
	# 玩家看得见，也不会出现「按了没反应」的困惑。
	# ⚠ 基类是 PROCESS_MODE_ALWAYS，open() 后树已暂停，_process 仍会跑。
	if _confirmed or _confirm_btn == null or not is_instance_valid(_confirm_btn):
		return
	var now := Time.get_ticks_msec()
	if _require_release and now >= _select_ready_at + RELEASE_FALLBACK_MS:
		_require_release = false
	var ready_now := selected_id != "" and not _require_release and now >= _confirm_ready_at
	if _confirm_btn.disabled == ready_now:
		_confirm_btn.disabled = not ready_now
		if selected_id == "":
			_confirm_btn.text = "请先择一枚玉简"
		elif ready_now:
			_confirm_btn.text = "确认选择 · %s" % _selected_name
		else:
			_confirm_btn.text = "稍候… · %s" % _selected_name


func _build_content() -> void:
	var accent: Color = UIKit.facility_style("insight").get("accent", UIKit.C_ACCENT)
	var where: String = "第 %d 层 · BOSS 关" % floor_no if stage_no >= RogueDB.STAGES_PER_FLOOR \
		else "第 %d 层 · 小关 %d" % [floor_no, stage_no]
	content.add_child(UIKit.note_card("%s 已清空。择一枚玉简，本局即刻生效。" % where, accent))

	_row = UIKit.hbox(16)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(_row)

	var tip := UIKit.readable_label("同一张增益最多叠 3 层（传说 1 层），叠满后不再出现。", 11, UIKit.C_TEXT_FAINT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tip)

	# 确认区单独一行，和玉简拉开距离：连点攻击的落点一般在上半屏，
	# 即使穿透了守卫，也只会「选中」一张，再改回来即可，不会直接结算。
	var foot := UIKit.hbox(14)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(foot)
	_status_label = UIKit.readable_label("点玉简选中 · 可改选", 12, UIKit.C_TEXT_DIM)
	foot.add_child(_status_label)
	_confirm_btn = UIKit.primary_button("请先择一枚玉简", Vector2(250.0, 44.0), accent)
	_confirm_btn.add_theme_font_size_override("font_size", UIKit.F_BODY)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	foot.add_child(_confirm_btn)


func _refresh_content() -> void:
	UIKit.clear_children(_row)
	for raw in choices:
		var def: Dictionary = raw
		_row.add_child(_make_card(def))
	_paint_selection()


func _make_card(def: Dictionary) -> Control:
	var rarity := String(def.get("rarity", RogueDB.RARITY_COMMON))
	var accent: Color = RogueDB.RARITY_COLOR.get(rarity, UIKit.C_ACCENT)
	var buff_id := String(def.get("id", ""))
	var stacks := RogueRun.buff_stacks(buff_id)
	var max_stacks := RogueDB.stack_cap(buff_id)

	var card := PanelContainer.new()
	card.set_meta("tut", "rogue.card")
	card.custom_minimum_size = Vector2(258.0, 226.0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "点选这枚玉简（还需在下方确认）"
	card.set_meta("buff_id", buff_id)
	card.set_meta("accent", accent)

	var box := UIKit.vbox(8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	var head := UIKit.hbox(6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var title := UIKit.label(String(def.get("name", buff_id)), 20, accent)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.chip(String(RogueDB.RARITY_NAME.get(rarity, "")), accent, 11))

	var line := ColorRect.new()
	line.color = Color(accent.r, accent.g, accent.b, 0.24)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)

	var desc := UIKit.readable_label(String(def.get("desc", "")), 15, UIKit.C_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(226.0, 78.0)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)

	box.add_child(UIKit.spacer())

	var foot := UIKit.readable_label("已叠 %d / %d" % [stacks, max_stacks], 12, UIKit.C_TEXT_DIM)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(foot)

	var hint := UIKit.readable_label("点此选中", 12, Color(accent.r, accent.g, accent.b, 0.72))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)
	card.set_meta("hint", hint)

	_apply_card_style(card, false)
	card.gui_input.connect(_on_card_input.bind(buff_id))
	card.mouse_entered.connect(_on_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_card_hover.bind(card, false))
	return card


func _apply_card_style(card: Control, hovered: bool) -> void:
	if not is_instance_valid(card):
		return
	var accent: Color = card.get_meta("accent", UIKit.C_ACCENT)
	var on := selected_id != "" and String(card.get_meta("buff_id", "")) == selected_id
	card.add_theme_stylebox_override("panel", UIKit.accent_card_style(
		accent,
		0.82 if on else (0.70 if hovered else 0.62),
		1.0 if on else (0.78 if hovered else 0.42),
		8))


func _on_card_hover(card: Control, entered: bool) -> void:
	# ⚠ 不要在这里直接写绝对值 stylebox：会把「已选中」的高亮抹掉
	_apply_card_style(card, entered)


func _paint_selection() -> void:
	if _row == null:
		return
	for c in _row.get_children():
		var card := c as Control
		if card == null:
			continue
		_apply_card_style(card, false)
		var hint: Label = card.get_meta("hint", null) as Label
		if hint != null:
			var on := selected_id != "" and String(card.get_meta("buff_id", "")) == selected_id
			hint.text = "✓ 已选中 · 待确认" if on else "点此选中"
	if _status_label != null:
		_status_label.text = "已择「%s」· 可改选" % _selected_name \
			if selected_id != "" else "点玉简选中 · 可改选"


func _on_card_input(event: InputEvent, buff_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	get_viewport().set_input_as_handled()
	if _confirmed or _require_release or Time.get_ticks_msec() < _select_ready_at:
		return
	_select(buff_id)


func _select(buff_id: String) -> void:
	if selected_id == buff_id:
		return
	selected_id = buff_id
	_selected_name = buff_id
	for raw in choices:
		var def: Dictionary = raw
		if String(def.get("id", "")) == buff_id:
			_selected_name = String(def.get("name", buff_id))
			break
	_confirm_ready_at = Time.get_ticks_msec() + CONFIRM_GUARD_MS
	_paint_selection()
	GameState.play_ui("ui_tab")


func _on_confirm_pressed() -> void:
	if _confirmed or selected_id == "":
		return
	if _require_release or Time.get_ticks_msec() < _confirm_ready_at:
		return
	_confirmed = true
	GameState.play_ui("ui_confirm")
	Tutorial.note("rogue_card")
	picked.emit(selected_id)
	close()
