class_name BossIntroCard
extends CanvasLayer
## BOSS 入场卡：进 BOSS 战时停，压暗战场 → 墨迹晕开 → 竖卡浮出 → 落印 → 点卡外开战。
##
## 结构：全屏压暗（屏幕纹理着色器）/ 墨烟 / 卡片组（卡面 + 底部信息 + 右侧竖题 + 印章）/ 点击层
## 交互：入场中点击 = 快进到完整亮起；亮起后点卡外或 ESC/空格 = 解除；
##       鼠标移动让整卡轻微倾斜（±5°，触屏不做）；鼠标停 2 秒自动回正。
## 时间：本层 PROCESS_MODE_ALWAYS + 所有 Tween 显式 TWEEN_PAUSE_PROCESS，停时期间照常演完。

signal closed

const CARD_SIZE := Vector2(420.0, 630.0)
const TITLE_GAP := 22.0
const TITLE_W := 84.0
## 左右各留出竖题的空间，让卡片本体居中、题款挂在右侧
const SIDE_W := TITLE_GAP + TITLE_W
const GROUP_SIZE := Vector2(CARD_SIZE.x + SIDE_W * 2.0, CARD_SIZE.y + 48.0)
## 卡面比卡框大一圈：倾斜时卡面会平移，不露出底色
const ART_BLEED := 8.0
const MAX_TILT_DEG := 5.0
const TILT_IDLE_MS := 2000
const HINT_TEXT := "点击卡片外 · 开战"

const DIM_SHADER := "res://assets/shaders/boss_intro_dim.gdshader"
const INK_SHADER := "res://assets/shaders/boss_intro_ink.gdshader"
const SEAL_TEX := "res://assets/ui/panel/button_seal_9p.png"
const BRUSH_LINE := "res://assets/ui/panel/brush_line.png"

var _entry: Dictionary = {}
var _title_text := ""
var _source_line := ""

var _dim_mat: ShaderMaterial
var _backdrop: Control
var _group: Control
var _card: Control
var _art: TextureRect
var _info: Control
var _frame: Control
var _sweep: TextureRect
var _title_col: Control
var _seal: Control
var _hint: Label
var _mists: Array[ColorRect] = []
var _stagger: Array[Control] = []

var _art_base := Vector2.ZERO
var _frame_base := Vector2.ZERO
var _info_base := Vector2.ZERO
var _title_base := Vector2.ZERO
var _title_height := 0.0
var _seal_base := Vector2.ZERO

var _hud: CanvasLayer
var _hud_alphas: Array = []
var _music: AudioStreamPlayer
var _music_db := BgmPlayer.BATTLE_VOLUME_DB

var _entrance_done := false
var _closing := false
var _tweens: Array[Tween] = []
var _hint_tween: Tween
var _hint_shown := false
var _touch := false
var _dim_progress := 0.0

var _tilt := Vector2.ZERO
var _tilt_target := Vector2.ZERO
var _last_mouse_ms := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 140


func open(entry: Dictionary, opts: Dictionary = {}) -> void:
	_entry = entry
	_title_text = String(opts.get("title", ""))
	_source_line = String(opts.get("source_line", entry.get("subtitle", "")))
	_hud = opts.get("hud", null)
	_touch = VirtualPad.is_touch_enabled()
	add_to_group("boss_intro")
	if _touch:
		# 触屏战斗按键会盖在停时画面上，也会把「点卡外」抢成攻击/闪避
		VirtualPad.set_overlay_blocked(true)
	_build()
	_fade_hud(0.0, 0.30)
	_play_entrance()


## 战斗场景把 BGM 播放器交进来：卡片期间压低 6dB，解除时拉回
func attach_music(player: AudioStreamPlayer, base_db: float) -> void:
	_music = player
	_music_db = base_db
	if _music != null:
		_music.call("fade_to_db", base_db - 6.0, 0.5)


# ===================== 构建 =====================

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 压暗层：读屏幕纹理做去色 + 压暗，并画一团从中心晕开的墨
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = load(DIM_SHADER)
	_dim_mat.set_shader_parameter("progress", 0.0)
	_dim_mat.set_shader_parameter("ink_radius", 0.22)
	_dim_mat.set_shader_parameter("ink_alpha", 0.95)
	dim.material = _dim_mat
	root.add_child(dim)

	# 点击层：卡片以外的任何位置都算「开战」
	_backdrop = Control.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	root.add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_group = Control.new()
	_group.custom_minimum_size = GROUP_SIZE
	_group.size = GROUP_SIZE
	_group.pivot_offset = GROUP_SIZE * 0.5
	_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_group)

	_build_mist()
	_build_card()
	_build_title_column()
	_build_seal()
	_build_hint()


func _build_mist() -> void:
	for i in 2:
		var m := ColorRect.new()
		m.size = Vector2(420.0, 420.0)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load(INK_SHADER)
		mat.set_shader_parameter("seed", float(i) * 3.7 + 1.0)
		mat.set_shader_parameter("alpha", 0.24 if i == 0 else 0.18)
		m.material = mat
		m.position = Vector2(SIDE_W - 150.0, 40.0) if i == 0 \
			else Vector2(SIDE_W + CARD_SIZE.x - 230.0, 250.0)
		_group.add_child(m)
		_mists.append(m)
		var base := m.position
		var drift := create_tween()
		drift.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		drift.tween_property(m, "position", base + Vector2(8.0, -12.0), 5.0) \
			.set_trans(Tween.TRANS_SINE)
		drift.tween_property(m, "position", base, 5.5).set_trans(Tween.TRANS_SINE)
		drift.set_loops()


func _build_card() -> void:
	_card = Control.new()
	_card.name = "Card"
	_card.position = Vector2(SIDE_W, 0.0)
	_card.size = CARD_SIZE
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.clip_contents = true
	_group.add_child(_card)

	_art = TextureRect.new()
	_art.position = Vector2(-ART_BLEED, -ART_BLEED)
	_art.size = CARD_SIZE + Vector2(ART_BLEED, ART_BLEED) * 2.0
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture = _load_tex(String(_entry.get("portrait", "")))
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_art)
	_art_base = _art.position

	var shade := TextureRect.new()
	shade.position = Vector2(0.0, CARD_SIZE.y - 320.0)
	shade.size = Vector2(CARD_SIZE.x, 320.0)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.texture = _make_shade_texture()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(shade)

	_info = Control.new()
	_info.position = Vector2(20.0, CARD_SIZE.y - 292.0)
	_info.size = Vector2(CARD_SIZE.x - 40.0, 274.0)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_info)
	_info_base = _info.position

	var col := UIKit.vbox(5)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(col)

	var name_lbl := UIKit.label(String(_entry.get("name", "")), 34, Color(0.99, 0.94, 0.83))
	UIKit.soft_text_shadow(name_lbl, 1)
	_add_stagger(col, name_lbl)

	var epithet := UIKit.label(String(_entry.get("epithet", "")), 15, Color(0.90, 0.80, 0.60))
	UIKit.soft_text_shadow(epithet, 1)
	_add_stagger(col, epithet)

	var source := UIKit.label(_source_line, 12, Color(0.74, 0.68, 0.56))
	UIKit.soft_text_shadow(source, 1)
	_add_stagger(col, source)

	var divider := TextureRect.new()
	divider.texture = UIKit.ui_texture(BRUSH_LINE)
	divider.custom_minimum_size = Vector2(0.0, 3.0)
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	divider.modulate = Color(0.92, 0.78, 0.45, 0.55)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_stagger(col, divider)

	var mech_title := "◆  " + String(_entry.get("mechanic_title", ""))
	var mech := UIKit.label(mech_title, 15, UIKit.C_ACCENT)
	UIKit.soft_text_shadow(mech, 1)
	_add_stagger(col, mech)

	var hint := UIKit.readable_label(String(_entry.get("intro_hint", "")), 12,
		Color(0.88, 0.86, 0.80))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIKit.soft_text_shadow(hint, 1)
	_add_stagger(col, hint)

	var tags: Array = _entry.get("tags", [])
	var tag_text := " · ".join(tags)
	var tag_lbl := UIKit.label(tag_text, 11, Color(0.68, 0.62, 0.48))
	UIKit.soft_text_shadow(tag_lbl, 1)
	_add_stagger(col, tag_lbl)

	_sweep = TextureRect.new()
	_sweep.texture = UIKit.ui_texture(BRUSH_LINE)
	_sweep.size = Vector2(720.0, 46.0)
	_sweep.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sweep.stretch_mode = TextureRect.STRETCH_SCALE
	_sweep.rotation = -0.28
	_sweep.modulate = Color(1.0, 0.94, 0.72, 0.0)
	_sweep.position = Vector2(-720.0, 380.0)
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_sweep)

	_frame = Control.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_frame)
	_frame_base = _frame.position
	var outer := PanelContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0, 0, 0, 0)
	osb.border_color = Color(0.94, 0.81, 0.47, 0.78)
	osb.set_border_width_all(2)
	osb.set_corner_radius_all(4)
	outer.add_theme_stylebox_override("panel", osb)
	_frame.add_child(outer)
	var inner := PanelContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 6.0
	inner.offset_top = 6.0
	inner.offset_right = -6.0
	inner.offset_bottom = -6.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0, 0, 0, 0)
	isb.border_color = Color(0.94, 0.81, 0.47, 0.22)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(3)
	inner.add_theme_stylebox_override("panel", isb)
	_frame.add_child(inner)


func _build_title_column() -> void:
	_title_col = Control.new()
	_title_col.position = Vector2(SIDE_W + CARD_SIZE.x + TITLE_GAP, 6.0)
	_title_col.size = Vector2(TITLE_W, CARD_SIZE.y - 120.0)
	_title_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.add_child(_title_col)
	_title_base = _title_col.position

	var col := UIKit.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_col.add_child(col)
	var chars := 0
	for i in _title_text.length():
		var ch := _title_text.substr(i, 1)
		if ch.strip_edges() == "":
			continue
		chars += 1
		var l := UIKit.label(ch, 26, Color(0.97, 0.91, 0.78))
		l.custom_minimum_size = Vector2(TITLE_W, 30.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UIKit.soft_text_shadow(l, 1)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	_title_height = float(chars) * 30.0


func _build_seal() -> void:
	var boss_name := String(_entry.get("name", ""))
	_seal = PanelContainer.new()
	_seal.size = Vector2(64.0, 64.0)
	_seal.custom_minimum_size = Vector2(64.0, 64.0)
	_seal.position = Vector2(SIDE_W + CARD_SIZE.x + TITLE_GAP + 8.0, 6.0 + _title_height + 22.0)
	_seal.pivot_offset = Vector2(32.0, 32.0)
	_seal.rotation = -0.07
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.add_child(_seal)
	_seal_base = _seal.position

	var sb := StyleBoxTexture.new()
	sb.texture = UIKit.ui_texture(SEAL_TEX)
	sb.texture_margin_left = 20
	sb.texture_margin_right = 20
	sb.texture_margin_top = 14
	sb.texture_margin_bottom = 14
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_seal.add_theme_stylebox_override("panel", sb)

	var col := UIKit.vbox(-4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal.add_child(col)
	for i in mini(2, boss_name.length()):
		var ch := boss_name.substr(i, 1)
		var l := UIKit.label(ch, 19, Color(0.97, 0.88, 0.72))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)


func _build_hint() -> void:
	_hint = UIKit.readable_label(HINT_TEXT, 12, Color(0.92, 0.85, 0.66))
	_hint.position = Vector2(SIDE_W, CARD_SIZE.y + 12.0)
	_hint.size = Vector2(CARD_SIZE.x, 26.0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.soft_text_shadow(_hint, 1)
	_hint.modulate.a = 0.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.add_child(_hint)


func _make_shade_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.025, 0.02, 0.0))
	grad.set_color(1, Color(0.03, 0.025, 0.02, 0.95))
	grad.add_point(0.45, Color(0.03, 0.025, 0.02, 0.22))
	grad.add_point(0.75, Color(0.03, 0.025, 0.02, 0.70))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex


func _add_stagger(col: VBoxContainer, node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.modulate.a = 0.0
	col.add_child(node)
	_stagger.append(node)


func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# ===================== 入场 =====================

func _play_entrance() -> void:
	_group.modulate.a = 0.0
	_group.scale = Vector2(0.90, 0.90)
	_group.rotation = deg_to_rad(-6.0)
	_seal.modulate.a = 0.0
	_seal.scale = Vector2(1.9, 1.9)
	_sweep.modulate.a = 0.0
	GameState.play_sfx("boss_intro_whoosh")

	var dim_t := _tw()
	dim_t.tween_method(_apply_dim, 0.0, 1.0, 0.45)
	dim_t.parallel().tween_method(_apply_ink, 0.0, 1.0, 0.72)

	var card_t := _tw()
	card_t.tween_interval(0.10)
	card_t.tween_property(_group, "modulate:a", 1.0, 0.34)
	card_t.parallel().tween_property(_group, "scale", Vector2.ONE, 0.52) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	card_t.parallel().tween_property(_group, "rotation", 0.0, 0.52) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var sweep_t := _tw()
	sweep_t.tween_interval(0.50)
	sweep_t.tween_callback(func() -> void:
		_sweep.modulate.a = 0.55
		GameState.play_sfx("boss_intro_shimmer"))
	sweep_t.tween_property(_sweep, "position", Vector2(360.0, 205.0), 0.42) \
		.set_trans(Tween.TRANS_SINE)
	sweep_t.parallel().tween_property(_sweep, "modulate:a", 0.0, 0.42)

	var i := 0
	for node in _stagger:
		var st := _tw()
		st.tween_interval(0.62 + 0.05 * float(i))
		st.tween_property(node, "modulate:a", 1.0, 0.24)
		i += 1

	var seal_t := _tw()
	seal_t.tween_interval(0.94)
	seal_t.tween_callback(func() -> void: GameState.play_sfx("boss_intro_seal"))
	seal_t.tween_property(_seal, "modulate:a", 1.0, 0.10)
	seal_t.parallel().tween_property(_seal, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var done_t := _tw()
	done_t.tween_interval(1.30)
	done_t.tween_callback(_mark_entrance_done)


func _apply_dim(p: float) -> void:
	_dim_progress = p
	_dim_mat.set_shader_parameter("progress", p)


func _apply_ink(t: float) -> void:
	_dim_mat.set_shader_parameter("ink_radius", lerpf(0.22, 2.4, t))
	_dim_mat.set_shader_parameter("ink_alpha", lerpf(0.95, 0.0, t))


func _mark_entrance_done() -> void:
	if _entrance_done or _closing:
		return
	_entrance_done = true
	set_process(not _touch)
	_show_hint()


## 入场中点击：不直接开战，先把所有动画推到终态
func _finish_entrance() -> void:
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_apply_dim(1.0)
	_apply_ink(1.0)
	_group.modulate.a = 1.0
	_group.scale = Vector2.ONE
	_group.rotation = 0.0
	for node in _stagger:
		node.modulate.a = 1.0
	_seal.modulate.a = 1.0
	_seal.scale = Vector2.ONE
	_sweep.modulate.a = 0.0
	_entrance_done = true
	set_process(not _touch)
	_snap_hud(0.0)
	_show_hint()


func _show_hint() -> void:
	if _hint_shown:
		return
	_hint_shown = true
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = _tw()
	_hint_tween.tween_property(_hint, "modulate:a", 0.9, 0.30)
	_hint_tween.tween_interval(4.0)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.6)


func _hide_hint() -> void:
	if not _hint_shown or _hint.modulate.a <= 0.01:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	var t := _tw()
	t.tween_property(_hint, "modulate:a", 0.0, 0.25)


# ===================== 交互 =====================

func _on_backdrop_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _closing:
		return
	if not _entrance_done:
		_finish_entrance()
		return
	_dismiss()


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var key := event as InputEventKey
		if key.physical_keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			if not _entrance_done:
				_finish_entrance()
			else:
				_dismiss()
		return
	if _touch or not _entrance_done:
		return
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	_tilt_target = Vector2(
		clampf((mm.position.x / vp.x - 0.5) * 2.0, -1.0, 1.0),
		clampf((mm.position.y / vp.y - 0.5) * 2.0, -1.0, 1.0))
	_last_mouse_ms = Time.get_ticks_msec()
	_hide_hint()


func _process(delta: float) -> void:
	if not _entrance_done or _closing:
		return
	if Time.get_ticks_msec() - _last_mouse_ms > TILT_IDLE_MS:
		_tilt_target = Vector2.ZERO
	var k := 1.0 - exp(-delta * 8.0)
	_tilt = _tilt.lerp(_tilt_target, k)
	_apply_tilt()


## 伪分层：整卡旋转 + 卡面/边框/信息/竖题各自反向微移，做出厚度
func _apply_tilt() -> void:
	_group.rotation = deg_to_rad(_tilt.x * MAX_TILT_DEG)
	_group.scale = Vector2(1.0 + _tilt.x * 0.006, 1.0 - absf(_tilt.y) * 0.015)
	_art.position = _art_base + _tilt * Vector2(4.0, 3.0)
	_frame.position = _frame_base + _tilt * Vector2(0.8, 0.6)
	_info.position = _info_base - _tilt * Vector2(1.4, 1.0)
	_title_col.position = _title_base - _tilt * Vector2(2.6, 1.8)
	_seal.position = _seal_base - _tilt * Vector2(3.4, 2.4)


func _dismiss() -> void:
	if _closing:
		return
	_closing = true
	set_process(false)
	GameState.play_sfx("boss_intro_start")
	_restore_music()
	if _touch:
		VirtualPad.set_overlay_blocked(false)
	_fade_hud(1.0, 0.18)
	var t := _tw()
	t.tween_property(_group, "scale", Vector2(0.97, 0.97), 0.20)
	t.parallel().tween_property(_group, "modulate:a", 0.0, 0.20)
	t.parallel().tween_method(_apply_dim, _dim_progress, 0.0, 0.22)
	t.tween_callback(func() -> void:
		# HUD 补间可能还没走完就被本体释放打断，这里强制落到原值
		_snap_hud(1.0)
		closed.emit()
		queue_free())


func _restore_music() -> void:
	if _music != null:
		_music.call("fade_to_db", _music_db, 0.35)


# ===================== HUD / 工具 =====================

## 记下 HUD 每个控件原本的透明度，淡出后按原值恢复（不要把本来就隐藏的元素一起点亮）
func _fade_hud(target_scale: float, duration: float) -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if _hud_alphas.is_empty():
		for c in _hud.get_children():
			var ci := c as CanvasItem
			if ci == null or ci.name == "ArenaGrade":
				continue
			_hud_alphas.append({"node": ci, "a": ci.modulate.a})
	for rec in _hud_alphas:
		var ci: CanvasItem = rec["node"]
		if not is_instance_valid(ci):
			continue
		var to := float(rec["a"]) * target_scale
		var t := _tw()
		t.tween_property(ci, "modulate:a", to, duration)


func _tw() -> Tween:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tweens.append(t)
	return t


## 快进时把 HUD 透明度直接压到终态（只杀 tween 会停在半透明）
func _snap_hud(target_scale: float) -> void:
	for rec in _hud_alphas:
		var ci: CanvasItem = rec["node"]
		if is_instance_valid(ci):
			ci.modulate.a = float(rec["a"]) * target_scale
