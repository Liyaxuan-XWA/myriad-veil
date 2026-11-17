class_name CardFace
extends Control
## 统一卡面：按 style.kind 建不同卡种，收藏册 / 展开 / 单卡共用。
##   kind = "holo" 华彩（视差 + 箔光）/ "ink" 水墨（墨色随视角流转）/ "still" 普通原画卡（静态）。
##   收藏册与展开逻辑不用改（它们只认 CardFace 与 clicked）。
##
## 布局：外层 Control 由调用方给尺寸；卡面自己铺满并画两层细框 + 四角金线。

signal clicked

const STILL_SHADER := "res://assets/shaders/card_still.gdshader"
const PAPER_SHADER := "res://assets/shaders/ink_paper.gdshader"

var _holo: HoloCardView
var _still_mat: ShaderMaterial
var _paper_mode := false
var _paper_interactive := false
var _paper_tilt_enabled := true
var _paper_tilt_scale := 1.0
var _paper_tilt := Vector2.ZERO
var _paper_tilt_target := Vector2.ZERO
var _paper_ripple_age := 99.0
var _paper_ripple_strength := 0.0
var _paper_ripple_center := Vector2(0.5, 0.5)
var _paper_last_shake_ms := 0
var _paper_reveal_tween: Tween
var _outer: Panel
var _inner: Panel
var _accent := Color(0.86, 0.72, 0.42, 1.0)
var _kind := ""
## bare：只出画面、不出卡框与四角金线（收藏册格子里的封面用，外框由格子自己画）
var _bare := false
var _pressed := false
var _press_pos := Vector2.ZERO


func configure(style: Dictionary, card_size: Vector2, accent: Color,
		bare: bool = false) -> bool:
	_kind = String(style.get("kind", "holo"))
	_bare = bare
	_accent = accent
	custom_minimum_size = card_size
	size = card_size
	if _kind == "still":
		return _build_still(style)
	if _kind == "ink":
		return _build_ink(style, accent)
	return _build_holo(style, accent)


func kind() -> String:
	return _kind


func is_paper() -> bool:
	return _paper_mode


## 单卡打开时：墨从眼/口/尾梢/岩台的顺序图里向外渗开，1.8s 后完全定住
func play_paper_reveal(duration: float = 1.8) -> void:
	if not _paper_mode or _still_mat == null:
		return
	if _paper_reveal_tween != null and _paper_reveal_tween.is_valid():
		_paper_reveal_tween.kill()
	_set_paper_reveal(0.0)
	_paper_reveal_tween = create_tween()
	_paper_reveal_tween.tween_method(_set_paper_reveal, 0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_paper_reveal(v: float) -> void:
	if _still_mat != null:
		_still_mat.set_shader_parameter("reveal", clampf(v, 0.0, 1.0))


func set_paper_reveal_immediate(v: float = 1.0) -> void:
	if not _paper_mode:
		return
	if _paper_reveal_tween != null and _paper_reveal_tween.is_valid():
		_paper_reveal_tween.kill()
	_set_paper_reveal(v)


## 单卡页 / 展开页 / 收藏封面都可开：落墨、流转、微倾、水波全套；
## 格子封面空间小，倾斜幅度用 tilt_scale 收小（仍保留反馈）
func set_paper_interactive(on: bool, tilt_enabled: bool = true, tilt_scale: float = 1.0) -> void:
	if not _paper_mode:
		return
	_paper_interactive = on
	_paper_tilt_enabled = tilt_enabled
	_paper_tilt_scale = tilt_scale
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if on:
		pivot_offset = size * 0.5
		set_process(true)
	else:
		set_process(false)
		_paper_tilt = Vector2.ZERO
		_paper_tilt_target = Vector2.ZERO
		_paper_ripple_age = 99.0
		_paper_ripple_strength = 0.0
		rotation = 0.0
		_sync_paper()


func _paper_on_motion(pos: Vector2, relative: Vector2) -> void:
	if not _paper_interactive:
		return
	var local := Vector2(clampf(pos.x / maxf(size.x, 1.0), 0.0, 1.0),
		clampf(pos.y / maxf(size.y, 1.0), 0.0, 1.0))
	if _paper_tilt_enabled:
		_paper_tilt_target = (local * 2.0 - Vector2.ONE).clamp(-Vector2.ONE, Vector2.ONE)
	else:
		_paper_tilt_target = Vector2.ZERO
	var now := Time.get_ticks_msec()
	if relative.length() >= 18.0 and now - _paper_last_shake_ms > 260:
		_paper_last_shake_ms = now
		_paper_ripple_center = local
		_paper_ripple_age = 0.0
		_paper_ripple_strength = 1.0
		_sync_paper()


func _on_paper_mouse_exited() -> void:
	_paper_tilt_target = Vector2.ZERO


func _sync_paper() -> void:
	if _still_mat == null:
		return
	_still_mat.set_shader_parameter("tilt", _paper_tilt)
	_still_mat.set_shader_parameter("ripple_center", _paper_ripple_center)
	_still_mat.set_shader_parameter("ripple_age", _paper_ripple_age)
	_still_mat.set_shader_parameter("ripple_strength", _paper_ripple_strength)


func _process(delta: float) -> void:
	if not _paper_mode or not _paper_interactive:
		return
	if _paper_tilt_enabled:
		_paper_tilt = _paper_tilt.lerp(_paper_tilt_target, 1.0 - exp(-delta * 9.0))
		rotation = _paper_tilt.x * deg_to_rad(2.4) * _paper_tilt_scale
	if _paper_ripple_strength > 0.0:
		_paper_ripple_age += delta
		if _paper_ripple_age >= 1.2:
			_paper_ripple_strength = 0.0
	_sync_paper()


## 华彩卡的内层控件（普通卡返回 null）；探针/截图用它读视差状态
func holo_view() -> HoloCardView:
	return _holo


func set_idle_motion(on: bool) -> void:
	if _holo != null:
		_holo.set_idle_motion(on)


func set_view_speed_immediate(v: Vector2) -> void:
	if _holo != null:
		_holo.set_view_speed_immediate(v)


## 展开页要把输入收给外层卡槽做“拖动换位”，这里统一关掉卡面自己的悬停/点击
func set_input_enabled(on: bool) -> void:
	if _holo != null:
		_holo.mouse_filter = Control.MOUSE_FILTER_PASS if on else Control.MOUSE_FILTER_IGNORE
	if _kind == "still":
		mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		if _paper_mode and not on:
			set_paper_interactive(false)


## 由父按钮代喂悬停点：卡片自走棋里点击归按钮（PASS 的子节点不会把按下传回父按钮，
## 实测会把牌点死），所以卡面自己不接输入，只接收按钮转来的坐标。
func set_hover_point(pos: Vector2) -> void:
	if _holo != null:
		_holo.set_hover_point(pos)
	elif _paper_mode:
		_paper_interactive = true
		_paper_tilt_target = Vector2(clampf(pos.x / maxf(size.x, 1.0), 0.0, 1.0) * 2.0 - 1.0,
				clampf(pos.y / maxf(size.y, 1.0), 0.0, 1.0) * 2.0 - 1.0)
		_paper_tilt = _paper_tilt.lerp(_paper_tilt_target, 0.5)
		rotation = _paper_tilt.x * deg_to_rad(2.4) * _paper_tilt_scale
		_sync_paper()


func clear_hover_point() -> void:
	if _holo != null:
		_holo.clear_hover_point()
	elif _paper_mode:
		_paper_tilt_target = Vector2.ZERO
		rotation = 0.0
		_sync_paper()


func _build_holo(style: Dictionary, accent: Color) -> bool:
	var holo := HoloCardView.new()
	holo.custom_minimum_size = size
	holo.size = size
	holo.mouse_filter = Control.MOUSE_FILTER_PASS
	if not holo.configure(String(style.get("art", "")), String(style.get("bg", "")),
			String(style.get("lines", "")), accent):
		holo.queue_free()
		return false
	holo.set_idle_motion(true)
	holo.set_effect(float(style.get("bg_scale", 0.5)), float(style.get("bg_shift", 0.25)),
		float(style.get("prism", 0.22)), float(style.get("emission_gain", 1.5)),
		float(style.get("wide_glow", 0.0)), float(style.get("aura", 0.0)))
	holo.set_contour(float(style.get("contour", 0.30)))
	holo.set_legacy(bool(style.get("legacy", false)))
	holo.set_depth(0.0)
	holo.clicked.connect(func() -> void: clicked.emit())
	add_child(holo)
	holo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holo = holo
	# 事件交给内层华彩卡（悬停视差 / 拖动都由它处理）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return true


func _build_ink(style: Dictionary, accent: Color) -> bool:
	var holo := HoloCardView.new()
	holo.custom_minimum_size = size
	holo.size = size
	holo.mouse_filter = Control.MOUSE_FILTER_PASS
	if not holo.configure_ink(String(style.get("art", "")),
			String(style.get("flow", "")), String(style.get("guard", "")), accent):
		holo.queue_free()
		return false
	holo.set_ink_strength(float(style.get("ink_strength", 1.0)))
	holo.set_idle_motion(true)
	holo.clicked.connect(func() -> void: clicked.emit())
	add_child(holo)
	holo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holo = holo
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return true


func _build_still(style: Dictionary) -> bool:
	var tex := _load_tex(String(style.get("art", "")))
	if tex == null:
		return false
	_paper_mode = String(style.get("fx", "")) == "paper"
	var face := TextureRect.new()
	face.texture = tex
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_still_mat = ShaderMaterial.new()
	_still_mat.shader = load(PAPER_SHADER if _paper_mode else STILL_SHADER) as Shader
	face.material = _still_mat
	add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if _paper_mode:
		var reveal_tex := _load_tex(String(style.get("reveal", "")))
		if reveal_tex == null:
			push_warning("CardFace: 纸本卡缺落墨顺序图")
			return false
		_still_mat.set_shader_parameter("reveal_tex", reveal_tex)
		_still_mat.set_shader_parameter("reveal", 1.0)
		var flow_tex := _load_tex(String(style.get("flow_tex", "")))
		var guard_tex := _load_tex(String(style.get("guard_tex", "")))
		if flow_tex != null and guard_tex != null:
			_still_mat.set_shader_parameter("flow_tex", flow_tex)
			_still_mat.set_shader_parameter("guard_tex", guard_tex)
			_still_mat.set_shader_parameter("art_px", flow_tex.get_size())
		_still_mat.set_shader_parameter("tilt", Vector2.ZERO)
		_still_mat.set_shader_parameter("ripple_center", Vector2(0.5, 0.5))
		_still_mat.set_shader_parameter("ripple_age", 99.0)
		_still_mat.set_shader_parameter("ripple_strength", 0.0)
		_still_mat.set_shader_parameter("paper_color", Color(0.93, 0.91, 0.86))
		mouse_exited.connect(_on_paper_mouse_exited)

	if not _bare:
		_outer = _make_frame(2.0, 0.62)
		add_child(_outer)
		_inner = _make_frame(1.0, 0.18)
		add_child(_inner)
		_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_inner.offset_left = 4.0
		_inner.offset_top = 4.0
		_inner.offset_right = -4.0
		_inner.offset_bottom = -4.0

	resized.connect(_sync_geometry)
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size * 0.5
	set_process(false)
	_sync_geometry()
	return true


func _make_frame(width: float, alpha: float) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sb.border_color = Color(_accent.r, _accent.g, _accent.b, alpha)
	sb.set_border_width_all(int(width))
	sb.set_corner_radius_all(14)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _sync_geometry() -> void:
	var w := maxf(size.x, 1.0)
	var r := clampf(w * 0.045, 9.0, 20.0)
	for frame in [_outer, _inner]:
		if frame == null:
			continue
		var sb := frame.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.set_corner_radius_all(int(round(r if frame == _outer else maxf(r - 2.0, 4.0))))
	if _still_mat != null:
		_still_mat.set_shader_parameter("card_px", size)
		_still_mat.set_shader_parameter("corner_px", 0.0 if _bare else r)
	if _paper_mode:
		pivot_offset = size * 0.5
	queue_redraw()


## 普通卡没有视差，点击自己收（华彩卡由内层 HoloCardView 发 clicked）
func _gui_input(event: InputEvent) -> void:
	if _kind != "still":
		return
	if _paper_mode and _paper_interactive:
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			_paper_on_motion(mm.position, mm.relative)
			accept_event()
			return
		if event is InputEventScreenDrag:
			var sd := event as InputEventScreenDrag
			_paper_on_motion(sd.position, sd.relative)
			accept_event()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pressed = true
			_press_pos = mb.position
		elif _pressed:
			_pressed = false
			if mb.position.distance_to(_press_pos) <= 8.0:
				clicked.emit()
		accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_pressed = true
			_press_pos = st.position
		elif _pressed:
			_pressed = false
			if st.position.distance_to(_press_pos) <= 8.0:
				clicked.emit()
		accept_event()


func _draw() -> void:
	# 华彩卡的四角金线由 HoloCardView 自己画，别叠第二遍；bare 封面由格子画外框
	if _kind != "still" or _bare:
		return
	var c := Color(_accent.r, _accent.g, _accent.b, 0.72)
	var inset := 10.0
	var ln := 16.0
	var w := 1.6
	var pts := [
		[Vector2(inset, inset + ln), Vector2(inset, inset), Vector2(inset + ln, inset)],
		[Vector2(size.x - inset - ln, inset), Vector2(size.x - inset, inset), Vector2(size.x - inset, inset + ln)],
		[Vector2(inset, size.y - inset - ln), Vector2(inset, size.y - inset), Vector2(inset + ln, size.y - inset)],
		[Vector2(size.x - inset - ln, size.y - inset), Vector2(size.x - inset, size.y - inset), Vector2(size.x - inset, size.y - inset - ln)],
	]
	for p in pts:
		draw_polyline(PackedVector2Array(p as Array), c, w, true)


func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
