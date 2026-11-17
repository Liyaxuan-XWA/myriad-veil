class_name ForgeButton
extends Button
## 锻造工坊专用控件：木牌 / 纸签 / 朱砂印
##
## 与全局 InkButton 分开：工坊是木梁 + 纸签 + 铜钉语言，不套金色方框。
## 贴图来自 tools/gen_forge_stage_art.py，9-patch 拉伸。

const UI := preload("res://scripts/ui/ui_kit.gd")
const TEX_WOOD := "res://assets/ui/forge/button_wood_9p.png"
const TEX_PAPER := "res://assets/ui/forge/button_paper_9p.png"
const TEX_SEAL := "res://assets/ui/forge/button_seal_9p.png"

const TONE_WOOD := "wood"
const TONE_PAPER := "paper"
const TONE_SEAL := "seal"
const TONE_TAB := "tab"

var tone := TONE_WOOD
var accent := Color(0.92, 0.76, 0.44, 1.0)
var _selected := false
var _hover_tw: Tween


func _ready() -> void:
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clip_text = true
	_apply_skin()
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	button_down.connect(_on_down)
	button_up.connect(_on_up)


func setup(p_tone: String, p_accent: Color = Color(0.92, 0.76, 0.44, 1.0)) -> void:
	tone = p_tone
	accent = p_accent
	if is_inside_tree():
		_apply_skin()


func set_selected(v: bool) -> void:
	_selected = v
	if is_inside_tree():
		_apply_skin()


func _apply_skin() -> void:
	var tex_path := TEX_WOOD
	var paper := tone == TONE_PAPER or (tone == TONE_TAB and _selected)
	if tone == TONE_SEAL:
		tex_path = TEX_SEAL
	elif paper:
		tex_path = TEX_PAPER
	var normal := Color(1, 1, 1, 1)
	var hover := Color(1.10, 1.05, 0.96, 1.0)
	var pressed := Color(0.80, 0.77, 0.72, 1.0)
	if tone == TONE_TAB and not _selected:
		normal = Color(0.80, 0.80, 0.80, 1.0)
		hover = Color(1.0, 0.94, 0.80, 1.0)
	add_theme_stylebox_override("normal", _style(tex_path, normal))
	add_theme_stylebox_override("hover", _style(tex_path, hover))
	add_theme_stylebox_override("pressed", _style(tex_path, pressed))
	add_theme_stylebox_override("disabled", _style(tex_path, Color(1, 1, 1, 0.42)))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var text_color := Color(0.93, 0.88, 0.76, 1.0)
	var hover_color := Color(1.0, 0.94, 0.78, 1.0)
	var disabled_color := Color(0.52, 0.49, 0.44, 1.0)
	if paper:
		text_color = Color(0.20, 0.16, 0.11, 1.0)
		hover_color = Color(0.32, 0.19, 0.11, 1.0)
		disabled_color = Color(0.47, 0.43, 0.37, 1.0)
	elif tone == TONE_TAB and not _selected:
		text_color = Color(0.66, 0.62, 0.56, 1.0)
	add_theme_color_override("font_color", text_color)
	add_theme_color_override("font_hover_color", hover_color)
	add_theme_color_override("font_pressed_color", text_color)
	add_theme_color_override("font_focus_color", hover_color)
	add_theme_color_override("font_disabled_color", disabled_color)
	add_theme_constant_override("outline_size", 0 if paper else 1)
	add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02, 0.72))


func _style(path: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = UI.ui_texture(path)
	sb.texture_margin_left = 28
	sb.texture_margin_right = 28
	sb.texture_margin_top = 20
	sb.texture_margin_bottom = 20
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.modulate_color = tint
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _on_hover(on: bool) -> void:
	if disabled:
		return
	if _hover_tw != null and _hover_tw.is_valid():
		_hover_tw.kill()
	_hover_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hover_tw.tween_property(self, "modulate", Color(1.04, 1.02, 0.98) if on else Color.WHITE, 0.14)


func _on_down() -> void:
	if disabled:
		return
	_scale_to(Vector2(0.97, 0.97), 0.06)


func _on_up() -> void:
	_scale_to(Vector2.ONE, 0.12)


func _scale_to(target: Vector2, duration: float) -> void:
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "scale", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
