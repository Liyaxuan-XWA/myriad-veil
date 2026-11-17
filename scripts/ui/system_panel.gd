class_name SystemPanel
extends CanvasLayer
## 通用系统面板基类 —— 所有主城系统界面均继承本类
##
## 提供：全屏遮罩、标题栏、可滚动内容区、关闭按钮、ESC 关闭、打开时暂停游戏。
## 子类只需：
##   1. 在 _ready 之前（或用 _init / 属性初始化）设定 panel_title / panel_size
##   2. 覆写 _build_content() 搭建结构
##   3. 覆写 _refresh_content() 刷新数据（每次 open 都会调用）
##
## 生命周期：由调用方 new 出来 add 到 root 再 open()；关闭时自行 queue_free。
## 与 CharacterPanel 的差异：本类是一次性面板（关闭即销毁），角色面板是常驻 autoload。

signal closed

var panel_title: String = "系统"
var panel_hint: String = "ESC 关闭"

## 面板键（脚本文件名，如 forge_panel）：新手指引的触发与聚光都认它
## ⚠ 改脚本文件名会静默断掉引导触发 —— 断的是「打开这个面板就教这套」，
##   不会报错，只会表现为那一章永远不出现。改名时同步 TutorialDB 的 trigger。
var _panel_key_cache := ""

func panel_key() -> String:
	if _panel_key_cache != "":
		return _panel_key_cache
	var sc := get_script() as Script
	if sc == null:
		return ""
	_panel_key_cache = sc.resource_path.get_file().get_basename()
	return _panel_key_cache

## 供子类填内容；基类负责放进滚动区
var content: VBoxContainer
## 外壳给内容区套的那层滚动（内容需要自己占满高度时用它，见 content_scrolls()）
var _content_scroll: ScrollContainer

var _visible := false
## 是否已登记进 GameState 的模态计数（open → true，close / 被 free → false）
## ⚠ 顺序任务面板靠这个计数决定「要不要藏起来」，漏登记就会浮在面板上层
var _modal_counted := false
var _root: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _close_btn: Button
var _facility: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 101
	_build_shell()
	_build_content()
	_set_visible(false)


func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if can_close():
				close()


# ===================== 生命周期 =====================

func open() -> void:
	if _visible:
		return
	_visible = true
	# 打开音：所有系统面板（含点击设施进入）统一走这里，一处在场就全都有声
	GameState.play_ui("ui_open")
	_refresh_content()
	_set_visible(true)
	get_tree().paused = true
	# 新手指引：面板是运行时建的，这里报一句，引导才能把聚光对到里面的控件
	# ⚠ 传的是「面板键」（脚本名去 _panel），改文件名会断掉引导触发表
	# ⚠ 顺序不能反：maybe_start 可能就地开一章（首次打开锻造台 / 塔面板），
	#   而那一章的第一步完成条件恰好是「打开这个面板」→ 必须先开章再报事件。
	Tutorial.maybe_start("panel:" + panel_key())
	Tutorial.note("panel_opened:" + panel_key())
	_mark_modal(true)


func close() -> void:
	if not _visible:
		return
	_visible = false
	GameState.play_ui("ui_close")
	get_tree().paused = false
	_mark_modal(false)
	closed.emit()
	queue_free()


func is_open() -> bool:
	return _visible


## 登记 / 注销「盖在 HUD 之上的界面」计数（顺序任务面板据此隐藏）
## ⚠ 幂等：open/close/_exit_tree 都会调，重复调用不能把计数带偏
func _mark_modal(on: bool) -> void:
	if on == _modal_counted:
		return
	_modal_counted = on
	if on:
		GameState.push_modal_ui(self)
	elif is_instance_valid(GameState):
		GameState.pop_modal_ui(self)


## ⚠ 场景切换时面板是被 free 掉的、不走 close()，这里必须兜底返还计数。
##   子类若也重写了 _exit_tree，**必须调 super._exit_tree()**（forge_panel 就是这种）。
func _exit_tree() -> void:
	_mark_modal(false)


func _on_close_pressed() -> void:
	if can_close():
		close()


## 子类覆写：返回 false 可拦下 ESC / 关闭按钮（用于「中途不许退出」的流程）
func can_close() -> bool:
	return true


## 子类覆写：返回 false 连关闭按钮都不画（用于「必须选一个」的流程，
## 免得玩家对着一个按不出反应的按钮使劲点）
func shows_close_button() -> bool:
	return true


# ===================== 构建 =====================

func _build_shell() -> void:
	add_child(UIKit.dim_rect())

	_facility = facility_visual()

	_root = PanelContainer.new()
	_root.add_theme_stylebox_override("panel", UIKit.panel_style())
	# 新手指引的兜底聚光目标：具体控件没挂 meta 时，至少把整个面板圈出来
	_root.set_meta("tut", "panel")
	add_child(_root)

	# 可选整面板背景图（子类覆写 panel_bg_path()）：插在深色底之上、内容之下
	var bg_path := panel_bg_path()
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var bg := TextureRect.new()
		bg.name = "__panel_bg"
		bg.texture = load(bg_path)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# 压暗成「氛围灯」：背景图只是气氛，不能让正文读不清（0.32 实测可读）
		bg.modulate = Color(1, 1, 1, 0.32)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bg)

	# 设施立绘水印：不占布局、不吃鼠标，只负责把设施气质带进面板
	if not _facility.is_empty():
		_add_facility_watermark()

	# 金色云纹框：叠在最上层（内部透明，不挡内容）
	UIKit.apply_panel_frame(_root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UIKit.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_right", UIKit.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	_root.add_child(margin)

	var vbox := UIKit.vbox(10)
	margin.add_child(vbox)

	# 标题栏：设施面板用插画抬头，普通面板保持原样
	if _facility.is_empty():
		vbox.add_child(_build_plain_header())
	else:
		vbox.add_child(_build_facility_header())
	# 「必须做出选择」的流程（如玉简三选一）不该给一个按了没反应的关闭按钮
	if _close_btn != null and not shows_close_button():
		_close_btn.visible = false

	content = UIKit.vbox(8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if content_scrolls():
		# 内容区（可滚动）
		# 面板内容按 1280 宽度设计；横向滚动条只会破坏版式，统一关掉
		_content_scroll = ScrollContainer.new()
		_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vbox.add_child(_content_scroll)
		_content_scroll.add_child(content)
	else:
		# ⚠ 关掉外层滚动才拿得到伸展空间：ScrollContainer 永远按「最小尺寸」摆子节点，
		#   在里面写 SIZE_EXPAND_FILL 是无效的（塔面板的右侧卡片会被压成 2px 高）。
		#   需要自己占满高度、内部再分块滚动的面板走这条路（见 content_scrolls()）。
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(content)

	# 布局放最后：等子类设完 panel_size
	call_deferred("_apply_size")


func _build_plain_header() -> Control:
	var header := UIKit.hbox(10)
	header.add_child(UIKit.facility_disc(
		{"accent": UIKit.C_ACCENT, "glyph": panel_title.substr(0, 1)}, 28))
	_title_label = UIKit.label(panel_title, UIKit.F_TITLE, Color(0.98, 0.94, 0.84))
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_title_label)
	header.add_child(UIKit.spacer())
	if panel_hint != "":
		header.add_child(UIKit.label(panel_hint, UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	var close_btn := UIKit.button("关闭", Vector2(72, 30))
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)
	_close_btn = close_btn
	return header


## 设施插画抬头：圆形印记 + 毛笔标题 + 氛围副标题 + 右侧淡立绘
## 只比普通标题栏高 30px 左右，正文仍是原来的滚动区 —— 不抢操作空间。
func _build_facility_header() -> Control:
	var accent: Color = _facility.get("accent", UIKit.C_ACCENT)
	var compact := facility_header_compact()
	var banner_h := 38.0 if compact else 62.0
	var banner := Control.new()
	banner.custom_minimum_size = Vector2(0.0, banner_h)
	banner.clip_contents = true
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 底：主题色从左向右淡出，像一层从设施里透出来的光
	var bg := TextureRect.new()
	bg.texture = UIKit.horizontal_gradient(
		Color(accent.r, accent.g, accent.b, 0.20),
		Color(accent.r, accent.g, accent.b, 0.0)
	)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bg)

	var rule := ColorRect.new()
	rule.color = Color(accent.r, accent.g, accent.b, 0.22)
	rule.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	rule.offset_top = -1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(rule)

	# 右侧淡立绘：只露半个身子，保留想象空间
	var cut := _facility_cutout_node()
	if cut != null:
		banner.add_child(cut)

	# 圆形印记（有专属插画用插画，没有就用单字印）
	banner.add_child(_make_facility_disc(accent, 34.0 if compact else 54.0))

	# 标题 + 副标题
	var titles := UIKit.vbox(0)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.anchor_left = 0.0
	titles.anchor_right = 1.0
	titles.offset_left = 46.0 if compact else 68.0
	titles.offset_right = -300.0 if compact else -360.0
	titles.offset_top = 0.0 if compact else 4.0
	titles.offset_bottom = banner_h - 2.0
	banner.add_child(titles)
	_title_label = UIKit.label(panel_title, 17 if compact else UIKit.F_TITLE, Color(0.98, 0.95, 0.86))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(_title_label)
	_subtitle_label = UIKit.label(String(_facility.get("subtitle", "")), 9 if compact else UIKit.F_SMALL,
		Color(accent.r, accent.g, accent.b, 0.82))
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(_subtitle_label)

	# 右侧：操作提示（最多两行，长提示省略）+ 关闭
	var actions := UIKit.hbox(8)
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.anchor_left = 1.0
	actions.anchor_right = 1.0
	actions.offset_left = -300.0 if compact else -350.0
	actions.offset_right = 0.0
	actions.offset_top = 3.0 if compact else 14.0
	actions.offset_bottom = 35.0 if compact else 50.0
	banner.add_child(actions)
	if panel_hint != "":
		var hint := UIKit.label(panel_hint, 10, Color(0.72, 0.74, 0.80, 0.92))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.max_lines_visible = 1 if compact else 2
		hint.clip_text = true
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.soft_text_shadow(hint, 1)
		actions.add_child(hint)
	var close_btn := UIKit.button("关闭", Vector2(66, 28 if compact else 30))
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_on_close_pressed)
	actions.add_child(close_btn)
	_close_btn = close_btn
	return banner


func _facility_cutout_node() -> TextureRect:
	var tex := UIKit.ui_texture(String(_facility.get("cutout", "")))
	if tex == null:
		return null
	var cut := TextureRect.new()
	cut.texture = tex
	cut.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cut.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cut.anchor_left = 1.0
	cut.anchor_right = 1.0
	cut.offset_left = -330.0
	cut.offset_right = -90.0
	cut.offset_top = -18.0
	cut.offset_bottom = 76.0
	cut.modulate = Color(1.0, 1.0, 1.0, 0.34)
	cut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cut


func _make_facility_disc(accent: Color, disc_size: float = 54.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(disc_size + 2.0, disc_size + 2.0)
	holder.size = Vector2(disc_size + 2.0, disc_size + 2.0)
	holder.offset_top = 3.0 if disc_size > 40.0 else 2.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var glow := UIKit.glow_node(Vector2(disc_size * 1.9, disc_size * 1.9), accent, 0.30)
	glow.position = Vector2.ONE * (disc_size * 0.5 - glow.size.x * 0.5)
	holder.add_child(glow)

	var disc := PanelContainer.new()
	disc.position = Vector2(1.0, 1.0)
	disc.custom_minimum_size = Vector2(disc_size, disc_size)
	disc.size = Vector2(disc_size, disc_size)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.045, 0.075, 0.94)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.62)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(disc_size * 0.5))
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	disc.add_theme_stylebox_override("panel", sb)
	holder.add_child(disc)

	var medallion := UIKit.ui_texture(String(_facility.get("medallion", "")))
	if medallion != null:
		var art := TextureRect.new()
		art.texture = medallion
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(art)
	else:
		var glyph := String(_facility.get("glyph", "◆"))
		var l := UIKit.label(glyph, 22 if disc_size > 40.0 else 16, accent)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(l)
	return holder


func _add_facility_watermark() -> void:
	var cutout := String(_facility.get("cutout", ""))
	var glyph := String(_facility.get("glyph", ""))
	if cutout == "" and glyph == "":
		return
	var accent: Color = _facility.get("accent", UIKit.C_ACCENT)
	var layer := Control.new()
	layer.name = "__facility_watermark"
	layer.clip_contents = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(layer)

	var glow := UIKit.glow_node(Vector2(360.0, 360.0), accent, 0.10)
	glow.anchor_left = 1.0
	glow.anchor_top = 1.0
	glow.anchor_right = 1.0
	glow.anchor_bottom = 1.0
	glow.offset_left = -400.0
	glow.offset_top = -390.0
	glow.offset_right = -40.0
	glow.offset_bottom = -30.0
	layer.add_child(glow)

	if cutout != "":
		var wm := TextureRect.new()
		wm.texture = UIKit.ui_texture(cutout)
		wm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wm.modulate = Color(1.0, 1.0, 1.0, 0.075)
		wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wm.anchor_left = 1.0
		wm.anchor_top = 1.0
		wm.anchor_right = 1.0
		wm.anchor_bottom = 1.0
		wm.offset_left = -390.0
		wm.offset_top = -390.0
		wm.offset_right = -20.0
		wm.offset_bottom = -10.0
		layer.add_child(wm)
		return

	# 没有专属立绘的系统（功法库 / 境界 / 图鉴 / 指引 / 感悟）用单字大印做水印
	var ring := UIKit.glow_node(Vector2(420.0, 420.0), accent, 0.075, UIKit.TEX_RING_SOFT)
	ring.anchor_left = 1.0
	ring.anchor_top = 1.0
	ring.anchor_right = 1.0
	ring.anchor_bottom = 1.0
	ring.offset_left = -450.0
	ring.offset_top = -440.0
	ring.offset_right = -10.0
	ring.offset_bottom = 0.0
	layer.add_child(ring)

	var mark := UIKit.label(glyph, 260, Color(accent.r, accent.g, accent.b, 0.055))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.anchor_left = 1.0
	mark.anchor_top = 1.0
	mark.anchor_right = 1.0
	mark.anchor_bottom = 1.0
	mark.offset_left = -340.0
	mark.offset_top = -350.0
	mark.offset_right = -30.0
	mark.offset_bottom = -20.0
	layer.add_child(mark)


func _apply_size() -> void:
	var w := panel_size().x
	var h := panel_size().y
	## 按 1280×720 设计稿居中。画布是 canvas_items + aspect=expand，
	## 面板高度**不跟着视口长**是故意的：headless 探针按这套坐标合成点击，
	## 改成按真实视口居中会让所有面板整体位移、点击坐标全部作废。
	## 需要「自己占满高度 + 内部局部分块滚动」的面板走 content_scrolls()。
	_root.position = Vector2((1280.0 - w) * 0.5, (720.0 - h) * 0.5)
	_root.size = Vector2(w, h)


## 子类覆写以自定义面板尺寸
func panel_size() -> Vector2:
	return Vector2(900.0, 600.0)


## 内容区是否套外层滚动（默认套）。覆写成 false 的面板自己负责高度分配，
## 通常是因为它要「左右两栏各自占满 + 内部局部滚动」（万界塔：地图滚、详情卡钉住）。
func content_scrolls() -> bool:
	return true


## 子类覆写以给整个面板铺背景图（返回 "" = 不铺，只用深色底）
## 2026-10-22：位面选择背景先这样接（美术说明里原本要求新建两屏，用户选择先当面板背景）
func panel_bg_path() -> String:
	return ""


## 子类覆写以使用设施专属抬头：
##   UIKit.facility_style("tower") 等，返回 { accent, subtitle, medallion/cutout 或 glyph }
## 返回空字典 = 保持普通标题栏。
func facility_visual() -> Dictionary:
	return {}


## 子类覆写：内容区极高的面板（如锻造台）改用 38px 紧凑抬头，避免挤压操作区
func facility_header_compact() -> bool:
	return false


func set_subtitle(text: String) -> void:
	if _subtitle_label != null:
		_subtitle_label.text = text


func _set_visible(v: bool) -> void:
	_root.visible = v
	for c in get_children():
		if c is ColorRect:
			c.visible = v


func set_title(text: String) -> void:
	panel_title = text
	if _title_label:
		_title_label.text = text


# ===================== 子类覆写 =====================

## 搭建静态结构（仅调用一次）
func _build_content() -> void:
	pass


## 刷新动态数据（每次 open 调用）
func _refresh_content() -> void:
	pass


# ===================== 便捷工具 =====================

## 提示行：显示在内容区顶部，用于反馈操作结果
func add_status_line(text: String, color: Color = UIKit.C_OK) -> void:
	var l := UIKit.label(text, UIKit.F_BODY, color)
	l.name = "StatusLine"
	# 已存在则更新，避免重复堆积
	var old := content.get_node_or_null("StatusLine")
	if old:
		old.text = text
		old.add_theme_color_override("font_color", color)
		return
	content.add_child(l)
	content.move_child(l, 0)


## 操作反馈：把结果写到状态行
func set_status(text: String, color: Color = UIKit.C_OK) -> void:
	add_status_line(text, color)
