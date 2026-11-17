class_name HoloCardView
extends Control
## 华彩卡：三层图（景 / 人 / 描边）在同一个 shader 里做视差、箔光与描边辉光。
## 背景独立 2× 取样；角色与描边共用坐标；描边光只吃结构线 × 角色 alpha。
## 水墨卡复用同一套悬停 / 拖动输入，只换 ink_card 着色器和墨稿 + 方向/保护数据图。

signal clicked

const SHADER_PATH := "res://assets/shaders/holo_card.gdshader"
const INK_SHADER_PATH := "res://assets/shaders/ink_card.gdshader"
const INK_IDLE_CYCLE := 5.0
const INK_DRAG_BOOST := 2.0
const INK_SETTLE_RATE := 1.8

var _surface: ColorRect
var _mat: ShaderMaterial
var _outer_frame: Panel
var _inner_frame: Panel
var _art_tex: Texture2D
var _bg_tex: Texture2D
var _line_tex: Texture2D
var _ink_tex: Texture2D
var _ink_flow_tex: Texture2D
var _ink_guard_tex: Texture2D
var _ink_mode := false
var _ink_strength := 1.0
var _accent := Color(0.86, 0.72, 0.42, 1.0)

var _view := Vector2.ZERO
var _ink_view := Vector2.ZERO
var _ink_phase := 0.0
var _target_view := Vector2.ZERO
var _depth := 0.0
var _contour := 0.15
var _bg_scale := 0.5
var _bg_shift := 0.25
var _prism := 0.22
var _emission_gain := 1.5
var _wide_glow := 0.0
var _aura := 0.0
var _legacy := false
var _idle_motion := false
var _hovered := false
var _dragging := false
var _drag_pointer := -1
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _press_moved := 0.0
var _press_time := 0.0
var _clock := 0.0
var _built := false


## 由**外部**（父按钮）代它喂悬停点。
## 卡片自走棋的手牌挂在一个 flat Button 底下，点击必须归按钮；而 Godot 的
## MOUSE_FILTER_PASS 并不会把按下/松开传回父按钮（实测：子节点设成 PASS 之后牌就点不动了），
## 所以视差不靠自己的输入，改由按钮把 motion 转进来。
## ⚠ 本机 MouseFilter 枚举是 STOP=0 / PASS=1 / IGNORE=2，和文档顺序不一样 ——
##   判据一律用 MOUSE_FILTER_* 常量，别把数字写进日志再去猜。
func set_hover_point(pos: Vector2) -> void:
	_hovered = true
	_last_pos = pos
	_target_view = _view_from_point(pos)


func clear_hover_point() -> void:
	_hovered = false
	if not _dragging:
		_target_view = Vector2.ZERO


func _init() -> void:
	_ensure_built()


func _ready() -> void:
	_ensure_built()
	_sync_geometry()
	_sync_shader()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = false
	# 卡面自己吃「按住拖」做视差（成就收藏册/卡包在可滚列表里）：
	# 不标这一句，ScrollDrag 会先把那一路拖拽抢去滚列表（2026-11-13 实测）。
	set_meta("no_drag_scroll", true)
	# 卡面只按 2:3 的画布尺寸显示，容器给多宽都不拉伸
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_surface = ColorRect.new()
	_surface.name = "Surface"
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	_surface.material = _mat
	add_child(_surface)

	_outer_frame = _make_frame(2.0, 0.62)
	add_child(_outer_frame)
	_inner_frame = _make_frame(1.0, 0.18)
	_inner_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inner_frame.offset_left = 4.0
	_inner_frame.offset_top = 4.0
	_inner_frame.offset_right = -4.0
	_inner_frame.offset_bottom = -4.0
	add_child(_inner_frame)

	resized.connect(_sync_geometry)


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


func configure(art_path: String, bg_path: String, line_path: String,
		accent: Color = Color(0.86, 0.72, 0.42, 1.0)) -> bool:
	_art_tex = _load_tex(art_path)
	_bg_tex = _load_tex(bg_path)
	_line_tex = _load_tex(line_path)
	if _art_tex == null or _bg_tex == null or _line_tex == null:
		push_warning("HoloCardView: 缺图 %s / %s / %s" % [art_path, bg_path, line_path])
		return false
	_ink_mode = false
	_ink_tex = null
	_accent = accent
	_apply_accent()
	_sync_shader()
	return true


## 水墨卡：整卡墨稿 + 笔势方向图 + 保护遮罩；流动在 ink_card.gdshader 里算
func configure_ink(art_path: String, flow_path: String, guard_path: String,
		accent: Color = Color(0.86, 0.72, 0.42, 1.0)) -> bool:
	_ink_tex = _load_tex(art_path)
	_ink_flow_tex = _load_tex(flow_path)
	_ink_guard_tex = _load_tex(guard_path)
	if _ink_tex == null or _ink_flow_tex == null or _ink_guard_tex == null:
		push_warning("HoloCardView: 缺水墨数据 %s / %s / %s" % [
			art_path, flow_path, guard_path])
		return false
	var sh := load(INK_SHADER_PATH) as Shader
	if sh == null:
		push_warning("HoloCardView: 水墨着色器加载失败")
		return false
	_ink_mode = true
	_art_tex = null
	_bg_tex = null
	_line_tex = null
	_accent = accent
	_ink_view = Vector2.ZERO
	_ink_phase = 0.0
	_apply_accent()
	_mat.shader = sh
	_sync_geometry()
	_sync_shader()
	return true


func _apply_accent() -> void:
	for frame in [_outer_frame, _inner_frame]:
		if frame == null:
			continue
		var sb := frame.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			var a := 0.62 if frame == _outer_frame else 0.18
			sb.border_color = Color(_accent.r, _accent.g, _accent.b, a)


func set_ink_strength(value: float) -> void:
	_ink_strength = clampf(value, 0.0, 2.0)
	_sync_shader()


func set_view_speed_immediate(v: Vector2) -> void:
	_target_view = v
	_view = v
	if _ink_mode:
		_ink_view = v
	_sync_shader()


## 截图 / 探针用：把墨流相位钉在某一帧，便于比较纸面与保护区的静止
func set_ink_phase_immediate(value: float) -> void:
	_ink_phase = fmod(value, TAU)
	_sync_shader()


func set_contour(value: float) -> void:
	_contour = clampf(value, 0.0, 3.0)
	_sync_shader()


func set_depth(value: float) -> void:
	_depth = clampf(value, -3.0, 3.0)
	_sync_shader()


func set_effect(scale: float, shift: float, prism: float, gain: float,
		wide: float = 0.0, aura_strength: float = 0.0) -> void:
	_bg_scale = clampf(scale, 0.1, 2.0)
	_bg_shift = clampf(shift, 0.0, 0.6)
	_prism = clampf(prism, 0.0, 1.0)
	_emission_gain = clampf(gain, 0.0, 4.0)
	_wide_glow = clampf(wide, 0.0, 3.0)
	_aura = clampf(aura_strength, 0.0, 3.0)
	_sync_shader()


func set_idle_motion(on: bool) -> void:
	_idle_motion = on


func set_legacy(on: bool) -> void:
	_legacy = on
	_sync_shader()


func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _sync_geometry() -> void:
	var w := maxf(size.x, 1.0)
	var r := clampf(w * 0.045, 9.0, 20.0)
	if _outer_frame != null:
		var sb := _outer_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.set_corner_radius_all(int(round(r)))
	if _inner_frame != null:
		var sb2 := _inner_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if sb2 != null:
			sb2.set_corner_radius_all(int(round(maxf(r - 2.0, 4.0))))
	if _mat != null:
		_mat.set_shader_parameter("card_px", size)
		_mat.set_shader_parameter("corner_px", r)
	queue_redraw()


func _sync_shader() -> void:
	if _mat == null:
		return
	if _ink_mode:
		_mat.set_shader_parameter("ink_tex", _ink_tex)
		_mat.set_shader_parameter("flow_tex", _ink_flow_tex)
		_mat.set_shader_parameter("guard_tex", _ink_guard_tex)
		_mat.set_shader_parameter("view", _ink_view)
		_mat.set_shader_parameter("ink_phase", _ink_phase)
		_mat.set_shader_parameter("ink_strength", _ink_strength)
		return
	_mat.set_shader_parameter("art_tex", _art_tex)
	_mat.set_shader_parameter("bg_tex", _bg_tex)
	_mat.set_shader_parameter("line_tex", _line_tex)
	_mat.set_shader_parameter("view", _view)
	_mat.set_shader_parameter("depth", _depth)
	_mat.set_shader_parameter("contour", _contour)
	_mat.set_shader_parameter("bg_scale", _bg_scale)
	_mat.set_shader_parameter("bg_shift", _bg_shift)
	_mat.set_shader_parameter("prism", _prism)
	_mat.set_shader_parameter("emission_gain", _emission_gain)
	_mat.set_shader_parameter("wide_glow", _wide_glow)
	_mat.set_shader_parameter("aura", _aura)
	_mat.set_shader_parameter("legacy", 1.0 if _legacy else 0.0)


func _process(delta: float) -> void:
	_clock += delta
	var goal := _target_view
	if _idle_motion and not _hovered and not _dragging:
		goal = Vector2(sin(_clock * 0.55) * 0.32, cos(_clock * 0.41) * 0.20)
	_view = _view.lerp(goal, 1.0 - exp(-delta * 7.5))
	if _ink_mode:
		# 视角抬起时墨流先留一下再收；松手约 0.8s 回到轻流
		var rate := 9.0 if _view.length() > _ink_view.length() else INK_SETTLE_RATE
		_ink_view = _ink_view.lerp(_view, 1.0 - exp(-delta * rate))
		var drive := clampf(_ink_view.length(), 0.0, 1.0)
		_ink_phase = fmod(_ink_phase + delta * (TAU / INK_IDLE_CYCLE) * (1.0 + drive * INK_DRAG_BOOST), TAU)
	_sync_shader()


func _input(event: InputEvent) -> void:
	# 鼠标拖出卡面后松手也要回正：_gui_input 收不到卡面外的 release
	if not _dragging or _drag_pointer != -1:
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	var local := get_global_transform_with_canvas().affine_inverse() * mb.position
	if not Rect2(Vector2.ZERO, size).has_point(local):
		_press_moved = 99.0
	# 先标记吃掉事件：_end_drag 可能触发 clicked，卡包会立刻重建并移除本控件
	get_viewport().set_input_as_handled()
	_end_drag(local)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and _drag_pointer == -1:
			_last_pos = mm.position
			_update_drag_target(mm.position)
			press_moved(mm.position)
			accept_event()
		elif not _dragging:
			_hovered = true
			_target_view = _view_from_point(mm.position)
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_drag(-1, mb.position)
			else:
				accept_event()
				_end_drag(mb.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_begin_drag(st.index, st.position)
		else:
			accept_event()
			_end_drag(st.position)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _dragging and _drag_pointer == sd.index:
			_last_pos = sd.position
			_update_drag_target(sd.position)
			press_moved(sd.position)
			accept_event()


func _begin_drag(pointer: int, pos: Vector2) -> void:
	_dragging = true
	_drag_pointer = pointer
	_press_pos = pos
	_last_pos = pos
	_press_moved = 0.0
	_press_time = _clock
	_target_view = _view_from_point(pos)


func _end_drag(pos: Vector2) -> void:
	if not _dragging:
		return
	var was_click := _press_moved <= 8.0 and (_clock - _press_time) <= 0.45
	_dragging = false
	_drag_pointer = -1
	if was_click:
		clicked.emit()
	else:
		_target_view = Vector2.ZERO


func press_moved(pos: Vector2) -> void:
	_press_moved = maxf(_press_moved, pos.distance_to(_press_pos))


func _update_drag_target(pos: Vector2) -> void:
	var center := size * 0.5
	var half := Vector2(maxf(center.x, 1.0), maxf(center.y, 1.0))
	var v := (pos - center) / half
	_target_view = Vector2(clampf(v.x, -1.0, 1.0), clampf(v.y, -1.0, 1.0))


func _view_from_point(pos: Vector2) -> Vector2:
	var center := size * 0.5
	return Vector2(
		clampf((pos.x - center.x) / maxf(center.x, 1.0), -1.0, 1.0) * 0.75,
		clampf((pos.y - center.y) / maxf(center.y, 1.0), -1.0, 1.0) * 0.75)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		if not _dragging:
			_target_view = Vector2.ZERO
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _dragging:
			_dragging = false
			_drag_pointer = -1
			_target_view = Vector2.ZERO


func _draw() -> void:
	# 四角细金线，给卡面一个收口；框体本身由两个 Panel 画
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
