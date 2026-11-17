class_name MatchReportView
extends Control
## 战报页：对局结束后，逐只棋子、逐招的输出明细（整屏一档）
##
## ### 口径（2026-11-06 逐题拍定，全在 CONTEXT.md「战报」两条）
## · 数字 = **减免后实际掉血**，与决定胜负的那个数同源，不是招式名义伤害
## · 全部记到**打出来的那只棋子**名下：刀痕 / 镜环场 / 界灯 / 分影 / 法宝场地 /
##   扇形弹体 / 持续伤害各自成行；镜像等召唤物**并入主人**，不单独列
## · 每行只给「招式名 + 数字 + 占比横条」—— 读数用图形，不写百分号，
##   也不摆成 Excel（避免页游感）
## · 归属不明的钱落进「其余」，**不许静默消失**
##
## 数据由 `MatchArena` 结算时喂进来（本文件不认识对局，也不去扫树）：
## `open_with(sides)` 的 sides = [{ "title": String, "units": [ {name,total,spawned,alive,rows:[[行名,金额]]} ] }]

const PAD := 18.0
const TITLE_SIZE := 22
const SIDE_SIZE := 17
const UNIT_SIZE := 16
const ROW_SIZE := 14
const BAR_W := 92.0
const UNIT_BAR_W := 118.0


## 打开这一页。parent 一般是 CanvasLayer（要保证在棋盘与结算面板之上）。
static func open(parent: Node, sides: Array, summary: String = "") -> MatchReportView:
	var v := MatchReportView.new()
	v.name = "MatchReportView"
	parent.add_child(v)
	v._fill(sides, summary)
	return v


func _fill(sides: Array, summary: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 整屏浮层：默认 STOP 会把下面结算面板的「返回长卷」吃掉，
	# 所以根只当容器，承接点击的活儿交给下面那块遮罩（见 _scrim）。
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.02, 0.04, 0.90)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	add_child(frame)
	frame.add_theme_stylebox_override("panel", UIKit.panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(PAD))
	margin.add_theme_constant_override("margin_right", int(PAD))
	margin.add_theme_constant_override("margin_top", int(PAD * 0.7))
	margin.add_theme_constant_override("margin_bottom", int(PAD * 0.7))
	frame.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var title := Label.new()
	title.text = "战报"
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.add_theme_color_override("font_color", UIKit.C_TEXT)
	head.add_child(title)
	if summary != "":
		var sub := Label.new()
		sub.text = summary
		sub.add_theme_font_size_override("font_size", ROW_SIZE)
		sub.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
		head.add_child(sub)
	var close := Button.new()
	close.text = "关闭"
	close.flat = true
	close.pressed.connect(close_and_free)
	head.add_child(close)

	# 一行说明读数字的口径：不写清「这是减免后掉血」，玩家会拿它去和招式系数对
	var note := Label.new()
	note.text = "输出与承受都是减免后实际掉血（抗性、护体、易伤已算在内）。展开后「承受」按来源棋子分组，组里列招式。"
	note.add_theme_font_size_override("font_size", ROW_SIZE)
	note.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(PAD))
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	for side in sides:
		cols.add_child(_build_side(side as Dictionary))

	# 尺寸由**屏幕**定，不由内容最小尺寸定：
	# ⚠ 按 `get_combined_minimum_size()` 算 offset 会在"同一帧里刚挂完子节点"时拿到 0，
	#   整块塌成左边一条；而完全交给内容又会把面板撑到比屏幕还高（截图实测底部几行出屏）。
	#   固定一个屏内尺寸，内容超出就滞部滚动。
	var vp := get_viewport_rect().size
	var fw := minf(1120.0, vp.x - 48.0)
	var fh := minf(640.0, vp.y - 32.0)
	# ⚠ 不能用 `set_anchors_preset(PRESET_CENTER)` + ±半尺寸：预设不改 offset，
	#   锚点也没吃进去，实测整块框被当成从左上角往负方向摆，只剩右下角一块在屏内
	#   （本项目记过的那族坑：要 *_and_offsets_* 才会一起动，而它又按当时的最小尺寸算）。
	#   最稳的是锚点全 0（左上），offset 直接给绝对像素。
	frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var x0 := (vp.x - fw) * 0.5
	var y0 := (vp.y - fh) * 0.5
	frame.offset_left = x0
	frame.offset_top = y0
	frame.offset_right = x0 + fw
	frame.offset_bottom = y0 + fh


func _build_side(side: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	var header := Label.new()
	header.text = String(side.get("title", ""))
	header.add_theme_font_size_override("font_size", SIDE_SIZE)
	header.add_theme_color_override("font_color", UIKit.C_ACCENT)
	col.add_child(header)
	var units: Array = side.get("units", [])
	var top := 0.0
	for u in units:
		top = maxf(top, float((u as Dictionary).get("total", 0.0)))
	for u in units:
		col.add_child(_build_unit(u as Dictionary, top))
	return col


func _build_unit(u: Dictionary, side_top: float) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var name_s := String(u.get("name", ""))
	var total := float(u.get("total", 0.0))
	var spawned := bool(u.get("spawned", false))

	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.clip_contents = true
	head.add_theme_font_size_override("font_size", UNIT_SIZE)
	var rows: Array = u.get("rows", [])
	var taken: Array = u.get("taken", [])
	var taken_total := float(u.get("taken_total", 0.0))
	if not spawned:
		head.text = "%s　未上场" % name_s
		head.disabled = true
	else:
		# 两个数都要上屏：只报打出的话，被秒掉的那一侧整列都是 0，
		# 玩家会以为"我方没显示"（实机就是这么问的）—— 而它其实挨了十几万。
		head.text = "%s　%s　/　承 %s" % [name_s, _num(total), _num(taken_total)]
		# 一点内容都没有才禁用；只要挨过打就能点开看"谁打的"
		head.disabled = rows.is_empty() and taken.is_empty()
	# 整栏同尺度：占比条比的是"这一侧出力最多的那只"
	head.add_child(_bar_row(0.0 if side_top <= 0.0 else total / side_top, UNIT_BAR_W,
			UIKit.C_ACCENT if spawned else UIKit.C_DISABLE, false))
	wrap.add_child(head)
	UIKit.attach_click_sfx(head)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 1)
	body.visible = false
	wrap.add_child(body)
	# 展开后两组：这只**打出**多少（按招式）、**挨了**谁哪招多少。
	# 两组各自按本组最大一行定标尺，不然承受行会被输出行压成看不见。
	body.add_child(_group_label("打出"))
	body.add_child(_rows_block(rows, "　"))
	body.add_child(_group_label("承受"))
	body.add_child(_taken_block(taken))
	if not rows.is_empty() or not taken.is_empty():
		head.pressed.connect(func() -> void:
			body.visible = not body.visible)
	return wrap


## 组标题：只比正文小一档的灰字，不做分隔线也不加框（一屏的框已经够多了）
func _group_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", ROW_SIZE)
	l.add_theme_color_override("font_color", UIKit.C_DISABLE)
	return l


## 一组「行名 + 条 + 数字」；标尺取本组最大一行
func _rows_block(raw_rows: Array, indent: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var top := 0.0
	for r in raw_rows:
		top = maxf(top, float((r as Array)[1]))
	for r in raw_rows:
		box.add_child(_skill_row(indent + String((r as Array)[0]), float((r as Array)[1]), top))
	return box


## 承受：按来源棋子分组。组头一行是「来源名 + 该来源合计 + 占比条」，
## 组里只列招式名（列宽不再被"来源 · 招式"整串撑开）。
## 条子的标尺：组头比的是"打我最多的那个来源"，组内比的是"该来源最狠的一招"。
func _taken_block(groups: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var top_src := 0.0
	for g in groups:
		top_src = maxf(top_src, float((g as Dictionary).get("total", 0.0)))
	for g in groups:
		var d: Dictionary = g
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var who := Label.new()
		who.text = String(d.get("source", ""))
		who.add_theme_font_size_override("font_size", ROW_SIZE)
		who.add_theme_color_override("font_color", UIKit.C_TEXT)
		who.custom_minimum_size = Vector2(210, 0)
		who.clip_text = true
		head.add_child(who)
		head.add_child(_bar_row(0.0 if top_src <= 0.0 else float(d.get("total", 0.0)) / top_src,
				BAR_W, UIKit.C_WARN, false))
		var num := Label.new()
		num.text = _num(float(d.get("total", 0.0)))
		num.add_theme_font_size_override("font_size", ROW_SIZE)
		num.add_theme_color_override("font_color", UIKit.C_TEXT)
		num.custom_minimum_size = Vector2(64, 0)
		head.add_child(num)
		box.add_child(head)
		box.add_child(_rows_block(d.get("rows", []), "　　"))
	return box


func _skill_row(row_name: String, amount: float, row_top: float) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = row_name
	label.add_theme_font_size_override("font_size", ROW_SIZE)
	label.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
	label.custom_minimum_size = Vector2(210, 0)
	label.clip_text = true
	line.add_child(label)
	line.add_child(_bar_row(0.0 if row_top <= 0.0 else amount / row_top, BAR_W, UIKit.C_TEXT, true))
	var num := Label.new()
	num.text = _num(amount)
	num.add_theme_font_size_override("font_size", ROW_SIZE)
	num.add_theme_color_override("font_color", UIKit.C_TEXT)
	num.custom_minimum_size = Vector2(64, 0)
	line.add_child(num)
	return line


func _bar_row(ratio: float, w: float, color: Color, dim: bool) -> ProgressBar:
	var h := 4.0 if dim else 6.0
	var bar := UIKit.mini_progress(clampf(ratio, 0.0, 1.0), color, Vector2(w, h))
	if dim:
		bar.modulate = Color(0.82, 0.82, 0.88, 0.85)
	return bar


## 千分位：战报是"读账"的地方，12480 与 12,480 差一眼可读性
func _num(v: float) -> String:
	var n := int(roundf(v))
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("" if n >= 0 else "-") + out


func _on_scrim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		close_and_free()


func close_and_free() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		close_and_free()
