class_name InkButton
extends Button
## 全局文字按钮：墨签 / 朱印 / 纸签 / 书签
##
## 视觉口径（2026-10-25 用户定）：水墨纸本，不要金属/塑料方框。
##   - 默认 = 墨签：深墨纸底 + 金线 + 左侧小印
##   - primary = 朱印：朱砂底 + 暖白字，用于突破 / 开炉 / 执笔 / 踏入 / 确认
##   - paper = 纸签：米纸底 + 墨字，用于浅色纸面或需要轻量强调的操作
##   - danger = 血印：暗红底 + 浅红字，用于删除 / 退出 / 丢弃
##   - quiet = 无底笔字：仅 hover 时浮出笔刷下划线，用于「卸下 / 装配」等行内操作
##   - tab = 书签：选中时变成米纸签 + 墨字，未选中是暗墨签
##
## 交互（不改变布局）：hover 墨晕 / 下划线生长 / 小印亮起；按下轻微回弹；
## 键盘聚焦同样亮下划线；禁用时完全安静。全部补间显式设为暂停也运行，
## 因为系统面板打开时 tree.paused = true。

const UI := preload("res://scripts/ui/ui_kit.gd")

const TONE_DEFAULT := "default"
const TONE_PRIMARY := "primary"
const TONE_PAPER := "paper"
const TONE_DANGER := "danger"
const TONE_QUIET := "quiet"
const TONE_TAB := "tab"

const C_INK_TEXT := Color(0.92, 0.88, 0.79, 1.0)
const C_INK_TEXT_HOVER := Color(1.00, 0.90, 0.64, 1.0)
const C_PAPER_TEXT := Color(0.16, 0.14, 0.11, 1.0)
const C_PAPER_TEXT_HOVER := Color(0.28, 0.16, 0.10, 1.0)
const C_DANGER_TEXT := Color(1.00, 0.83, 0.78, 1.0)

var tone: String = TONE_DEFAULT
var accent: Color = Color(0.95, 0.82, 0.45, 1.0)

var _selected := false
var _glow: TextureRect
var _brush: TextureRect
var _seal: TextureRect
var _diamond: Label
var _hover_tw: Tween
var _press_tw: Tween
## 页签「可按」提示（2026-11-12 用户改口径：去掉选中态的呼吸/光扫，
## 把动态放到**未选中**的按钮上 —— 要的是「这块按得动」，不是闪光）。
## 做法：整块以底边中点为轴轻轻起伏（1.00 ↔ 1.02）。不动颜色、不加光、不扫光。
var _idle_tw: Tween


func _ready() -> void:
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clip_text = true
	_build_decor()
	_apply_skin()
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	_start_tab_idle()


## UIKit 工厂调用；即使 _ready 已经跑过也能安全重设
func setup(p_tone: String, p_accent: Color = Color(0.95, 0.82, 0.45, 1.0)) -> void:
	tone = p_tone if p_tone in [
		TONE_DEFAULT, TONE_PRIMARY, TONE_PAPER, TONE_DANGER, TONE_QUIET, TONE_TAB
	] else TONE_DEFAULT
	accent = p_accent
	if is_inside_tree():
		_apply_skin()


func set_selected(value: bool) -> void:
	var turned_on := value and not _selected
	_selected = value
	if not is_inside_tree():
		return
	_apply_skin()
	_refresh_decor(true)
	if tone != TONE_TAB:
		return
	if value:
		_stop_tab_idle()
	else:
		_start_tab_idle()


func is_selected() -> bool:
	return _selected


func _build_decor() -> void:
	if _glow != null:
		return
	_glow = TextureRect.new()
	_glow.name = "__ink_glow"
	_glow.texture = UI.ui_texture(UI.TEX_GLOW_SOFT)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.material = UI.additive_material()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 光从左上打：光晕往受光侧偏，背光侧只留很浅一层
	_glow.offset_left = -14
	_glow.offset_top = -14
	_glow.offset_right = 4
	_glow.offset_bottom = 6
	_glow.modulate = Color(1, 1, 1, 0)
	add_child(_glow)

	_brush = TextureRect.new()
	_brush.name = "__ink_brush"
	_brush.texture = UI.ui_texture(UI.TEX_BRUSH_LINE)
	_brush.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_brush.stretch_mode = TextureRect.STRETCH_SCALE
	_brush.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brush.anchor_left = 0.16
	_brush.anchor_right = 0.84
	_brush.anchor_top = 1.0
	_brush.anchor_bottom = 1.0
	_brush.offset_left = 0
	_brush.offset_right = 0
	_brush.offset_top = -6
	_brush.offset_bottom = -1
	_brush.modulate = Color(1, 1, 1, 0)
	_brush.resized.connect(func() -> void: _brush.pivot_offset = _brush.size * 0.5)
	add_child(_brush)

	_seal = TextureRect.new()
	_seal.name = "__ink_seal"
	_seal.texture = UI.ui_texture(UI.TEX_SEAL_MARK)
	_seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal.anchor_left = 0.0
	_seal.anchor_right = 0.0
	_seal.anchor_top = 0.5
	_seal.anchor_bottom = 0.5
	_seal.offset_left = 8
	_seal.offset_right = 18
	_seal.offset_top = -5
	_seal.offset_bottom = 5
	add_child(_seal)

	_diamond = Label.new()
	_diamond.name = "__ink_diamond"
	_diamond.text = "◆"
	_diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diamond.add_theme_font_size_override("font_size", 7)
	_diamond.anchor_left = 0.0
	_diamond.anchor_right = 0.0
	_diamond.anchor_top = 0.5
	_diamond.anchor_bottom = 0.5
	_diamond.offset_left = 9
	_diamond.offset_right = 17
	_diamond.offset_top = -6
	_diamond.offset_bottom = 6
	_diamond.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diamond.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_diamond)


func _apply_skin() -> void:
	# 键盘焦点框会和墨签打架，统一交给笔刷下划线表达
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var is_paper := tone == TONE_PAPER or (tone == TONE_TAB and _selected)
	var normal_tint := Color(1, 1, 1, 1)
	var hover_tint := Color(1.16, 1.12, 1.02, 1.0)
	var pressed_tint := Color(0.74, 0.72, 0.68, 1.0)
	var tex_path := UI.TEX_BTN_INK
	if tone == TONE_PRIMARY or tone == TONE_DANGER:
		tex_path = UI.TEX_BTN_SEAL
	elif is_paper:
		tex_path = UI.TEX_BTN_PAPER
	if tone == TONE_DANGER:
		normal_tint = Color(0.62, 0.46, 0.44, 1.0)
		hover_tint = Color(0.82, 0.58, 0.52, 1.0)
		pressed_tint = Color(0.48, 0.36, 0.34, 1.0)
	if tone == TONE_TAB and not _selected:
		normal_tint = Color(0.80, 0.80, 0.80, 1.0)
		hover_tint = Color(1.05, 1.0, 0.90, 1.0)

	if tone == TONE_QUIET:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 6
		empty.content_margin_right = 6
		empty.content_margin_top = 0
		empty.content_margin_bottom = 0
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, empty)
	else:
		add_theme_stylebox_override("normal", _style(tex_path, normal_tint))
		add_theme_stylebox_override("hover", _style(tex_path, hover_tint))
		add_theme_stylebox_override("pressed", _style(tex_path, pressed_tint))
		add_theme_stylebox_override("disabled", _style(tex_path, Color(1, 1, 1, 0.48)))

	var text_normal := C_INK_TEXT
	var text_hover := C_INK_TEXT_HOVER
	var text_pressed := Color(0.84, 0.80, 0.72, 1.0)
	var text_disabled := Color(0.56, 0.56, 0.60, 1.0)
	if is_paper:
		text_normal = C_PAPER_TEXT
		text_hover = C_PAPER_TEXT_HOVER
		text_pressed = Color(0.10, 0.09, 0.07, 1.0)
		text_disabled = Color(0.52, 0.49, 0.44, 1.0)
	elif tone == TONE_PRIMARY:
		text_normal = Color(1.0, 0.93, 0.80, 1.0)
		text_hover = Color(1.0, 0.98, 0.90, 1.0)
	elif tone == TONE_DANGER:
		text_normal = C_DANGER_TEXT
		text_hover = Color(1.0, 0.93, 0.88, 1.0)
		text_pressed = Color(0.90, 0.74, 0.70, 1.0)
	elif tone == TONE_TAB and not _selected:
		text_normal = Color(0.66, 0.66, 0.70, 1.0)
		text_hover = Color(0.98, 0.90, 0.70, 1.0)
	elif tone == TONE_QUIET:
		text_normal = Color(0.68, 0.68, 0.72, 1.0)
		text_hover = Color(1.0, 0.90, 0.64, 1.0)
		text_pressed = Color(0.86, 0.80, 0.64, 1.0)

	add_theme_color_override("font_color", text_normal)
	add_theme_color_override("font_hover_color", text_hover)
	add_theme_color_override("font_pressed_color", text_pressed)
	add_theme_color_override("font_focus_color", text_hover)
	add_theme_color_override("font_disabled_color", text_disabled)
	# 2026-11-04：字不靠描边撑，改走柔和投影（左上光 → 影子向右下 1,2）
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.42))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 2)
	add_theme_constant_override("shadow_outline_size", 2)
	add_theme_constant_override("outline_size", 0)

	_refresh_decor(false)


func _style(tex_path: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = UI.ui_texture(tex_path)
	sb.texture_margin_left = UI.BTN_PATCH_X
	sb.texture_margin_right = UI.BTN_PATCH_X
	sb.texture_margin_top = UI.BTN_PATCH_Y
	sb.texture_margin_bottom = UI.BTN_PATCH_Y
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.modulate_color = tint
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


func _refresh_decor(hovered_now: bool) -> void:
	if _glow == null:
		return
	var paper := tone == TONE_PAPER or (tone == TONE_TAB and _selected)
	var glow_color := accent
	if paper:
		glow_color = Color(1.0, 0.82, 0.45)
	if tone == TONE_PRIMARY:
		glow_color = Color(1.0, 0.66, 0.34)
	elif tone == TONE_DANGER:
		glow_color = Color(1.0, 0.36, 0.26)
	_glow.modulate = Color(glow_color.r, glow_color.g, glow_color.b, 0.0)
	if _selected or hovered_now:
		# 高亮度强调只留给主按钮：次要按钮 hover 时基本只是「抬起来一点」
		var glow_alpha := 0.05 if paper else (0.16 if tone == TONE_PRIMARY else 0.06)
		if tone == TONE_TAB and _selected:
			glow_alpha = 0.11
		_glow.modulate.a = glow_alpha

	var brush_color := accent
	if tone == TONE_PRIMARY:
		brush_color = Color(1.0, 0.90, 0.62)
	elif tone == TONE_PAPER:
		brush_color = Color(0.55, 0.14, 0.10)
	elif tone == TONE_DANGER:
		brush_color = Color(1.0, 0.55, 0.42)
	elif tone == TONE_TAB and _selected:
		brush_color = Color(0.55, 0.14, 0.10)
	_brush.modulate = Color(brush_color.r, brush_color.g, brush_color.b,
		0.9 if (_selected or hovered_now) else 0.0)
	_brush.scale = Vector2(1, 1) if (_selected or hovered_now) else Vector2(0.55, 1)

	var show_seal := tone in [TONE_DEFAULT, TONE_PAPER, TONE_DANGER] \
		or (tone == TONE_TAB and _selected)
	_seal.visible = show_seal
	_seal.modulate = Color(1, 1, 1, 0.74 if (_selected or hovered_now) else 0.46)
	if tone == TONE_DANGER:
		_seal.modulate = Color(1.0, 0.76, 0.62, _seal.modulate.a)

	_diamond.visible = tone == TONE_PRIMARY
	if _diamond.visible:
		_diamond.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58,
			0.9 if (_selected or hovered_now) else 0.55))


func _on_hover_changed(hovered: bool) -> void:
	if disabled:
		return
	_kill_hover_tween()
	_hover_tw = create_tween()
	_hover_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if _glow != null:
		var paper := tone == TONE_PAPER or (tone == TONE_TAB and _selected)
		var strong := 0.16 if tone == TONE_PRIMARY else 0.07
		var target := (0.0 if paper else strong) if hovered else (0.08 if _selected else 0.0)
		_hover_tw.parallel().tween_property(_glow, "modulate:a", target, 0.16)
	if _brush != null:
		# 笔刷线是「选中」的语言；hover 不再让它抽长，免得一次划过三四个特效同闪
		var brush_target := 0.86 if _selected else (0.34 if hovered else 0.0)
		_hover_tw.parallel().tween_property(_brush, "modulate:a", brush_target, 0.16)
		_brush.scale = Vector2.ONE if _selected else Vector2(0.72, 1)
	if _seal != null and _seal.visible:
		var seal_target := 0.80 if _selected else (0.60 if hovered else 0.46)
		_hover_tw.parallel().tween_property(_seal, "modulate:a", seal_target, 0.16)


func _on_focus_changed(focused: bool) -> void:
	if disabled:
		return
	_refresh_decor(focused)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	# 起伏以底边中点为轴：尺寸变了要跟着挪（面板刚建出来时 size 还是 0）
	if _idle_tw != null and _idle_tw.is_valid():
		_refresh_idle_pivot()


# ===================== 页签「可按」起伏 =====================

## 未选中的页签：整块以底边中点为轴轻轻起伏（1.00 ↔ 1.02，一个来回 2.6 秒）。
## ⚠ 不动颜色、不加光、不扫光 —— 用户 2026-11-12 明确「不要闪光」，
##   要的是**按得动**的手感：起伏 = 这块还是活的，选中那块落定不动。
## ⚠ 面板打开时整棵树是 paused：必须 PAUSE_PROCESS，否则在面板里是死的。
func _start_tab_idle() -> void:
	if tone != TONE_TAB or _selected:
		return
	if _idle_tw != null and _idle_tw.is_valid():
		return
	_refresh_idle_pivot()
	_idle_tw = create_tween().set_loops()
	_idle_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_idle_tw.tween_property(self, "scale", Vector2(1.02, 1.02), 1.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tw.tween_property(self, "scale", Vector2.ONE, 1.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_tab_idle() -> void:
	if _idle_tw != null:
		_idle_tw.kill()
		_idle_tw = null
	scale = Vector2.ONE


## 起伏轴心 = 底边中点：读作「被手指从下面托起来」，而不是朝左上角膨胀
func _refresh_idle_pivot() -> void:
	pivot_offset = Vector2(size.x * 0.5, size.y)


## 松手后过 0.16 秒再接上起伏（按下的缩放在那之前还没收完）
func _restart_idle_soon() -> void:
	if tone != TONE_TAB or _selected:
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.16)
	tw.tween_callback(_start_tab_idle)


func _on_button_down() -> void:
	_kill_press_tween()
	# 起伏先停：它和按下的缩放写的是同一个 scale
	if _idle_tw != null:
		_idle_tw.kill()
		_idle_tw = null
	pivot_offset = size * 0.5
	_press_tw = create_tween()
	_press_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_press_tw.tween_property(self, "scale", Vector2(0.972, 0.972), 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_button_up() -> void:
	_kill_press_tween()
	_press_tw = create_tween()
	_press_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_press_tw.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_restart_idle_soon()


func _kill_hover_tween() -> void:
	if _hover_tw != null and _hover_tw.is_valid():
		_hover_tw.kill()


func _kill_press_tween() -> void:
	if _press_tw != null and _press_tw.is_valid():
		_press_tw.kill()
