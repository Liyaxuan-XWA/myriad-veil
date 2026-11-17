extends Control
## 万界秘境 · 位面星图（旋转木马）
##
## 结构口径（2026-11-06 用户拍定）：前排 3 格可选可点 + 深处 1 格调暗不可点。
## 从右往左滑 = 时间前进方向：最左那格旋进深处、深处那格旋出到最右，回滑镜像。
## 门本身是 4 张独立 sprite（纯黑底、加性合成），底图只有星云 —— 门要跟着槽位走，
## 画死在底图里就会和代码环打架出重影。

signal gate_entered(domain_id: String)
signal locked_picked(domain_id: String, reason: String)
signal page_changed(page: int)

const SRC_SIZE := Vector2(2730.0, 1536.0)

## 槽位按「环序」排列，不是按屏幕左右排：推进一格 = 沿 中央→左→深处→右→中央 走一格。
## 这个顺序才让「从右往左滑」读得通：前排整体左移、掉出左端的不消失而是绕到后面去。
## dim 是加性层的整体明度，tilt 是转体角 —— 进出深处必须三条一起走（位置/缩放/亮度）
## 才读得出「绕到星图背面去了」，只挪位置会像平移淡入淡出。
##
## 坐标是源图（2730×1536）里的位置，但**不再需要对着画好的门量**：底图现在没有门了。
## 半径比改版前小约 12%，因为面板可视区只有 1082×532（底图按 cover 缩放后要上下各裁掉一块），
## 原尺寸下门的辉光会一路压到信息条，铭牌没地方挂。
const SLOTS := [
	{"center": Vector2(1365.0, 800.0), "radius": 228.0, "dim": 1.00, "tilt": 0.0},
	{"center": Vector2(654.0, 786.0), "radius": 196.0, "dim": 0.94, "tilt": -7.0},
	{"center": Vector2(1365.0, 292.0), "radius": 134.0, "dim": 0.45, "tilt": 0.0},
	{"center": Vector2(2074.0, 768.0), "radius": 192.0, "dim": 0.94, "tilt": 7.0},
]
const DEPTH_SLOT := 2
## 位面序号 -> 起始槽位。0/1/3/2 是把 赤霄界 和 照影界 对调了一次，
## 为的是开局仍等于画师原来的排布（凡界中央、冲和左、赤霄右、照影在深处）。
const INITIAL_SLOT := [0, 1, 3, 2]

## 超出 4 格时的兜底：沿星云涡流外圈补位，绝不允许「位面存在但界面上没有门」
const EXTRA_RING_RADIUS := Vector2(1180.0, 520.0)
const EXTRA_RING_CENTER := Vector2(1365.0, 720.0)
const GATE_COLORS := [
	Color(0.48, 0.86, 1.00),
	Color(1.00, 0.78, 0.38),
	Color(0.86, 0.66, 1.00),
	Color(0.82, 0.90, 1.00),
]
const INFO_HEIGHT := 96.0

## sprite 是 1024² 的正方图，但环带不在 512px 处 —— 每张生成时辉光外扩不同。
## 这两个数是 tools/assemble_star_map_gates.py 用径向亮度剖面实测出来的，
## 拿 512 当环半径会让每扇门都差 10~20%，四扇门还各差不一样。
const GATE_SPRITE_FMT := "res://assets/ui/realm_gate_%s.png"
const GATE_SPRITE_PX := 1024.0
const GATE_RING_PX := {
	"domain_01": 258.0,
	"domain_02": 308.0,
	"domain_03": 333.0,
	"domain_04": 334.0,
}
## 没实测过半径的新位面按这个走：宁可略大也别小到压不住铭牌
const GATE_RING_PX_FALLBACK := 320.0

## 拖拽：超过这个像素才算拖，否则算点门。手机和鼠标共用一个口径。
const DRAG_THRESHOLD := 18.0
## 拖过「面板宽 × 这个系数」= 前进一格
const DRAG_PX_PER_SLOT := 0.45
const ROT_SPEED := 7.5
## 停在半格会让「深处那格」既不可点又看得见，必须吸附
const REST_EPS := 0.02

var _domains: Array = []
var _gates: Array = []
var _selected_id := ""
var _time := 0.0
var _built := false

var _rot := 0.0
var _rot_target := 0
var _dragging := false
var _drag_x := 0.0
var _drag_rot := 0.0
var _drag_moved := false

var _info_bar: PanelContainer
var _info_name: Label
var _info_meta: HBoxContainer
var _info_desc: Label
var _info_foot: Label
var _info_state: HBoxContainer
var _cta: Button
var _turn_left: Button
var _turn_right: Button
var _page_dots: HBoxContainer
var _info_accent := GATE_COLORS[0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(true)
	_build()
	_built = true
	_layout()
	_refresh_gate_visuals()
	_update_info()


func setup(domains: Array, selected_id: String = "") -> void:
	_domains = domains.duplicate()
	_selected_id = selected_id
	if _built:
		_rebuild_gates()
		_layout()
		_refresh_gate_visuals()
		_update_info()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()


func _process(delta: float) -> void:
	_time += delta
	var moving := absf(_rot - float(_rot_target)) > REST_EPS
	if moving:
		_rot += float(_rot_target - _rot) * minf(1.0, delta * ROT_SPEED)
		if absf(_rot - float(_rot_target)) <= REST_EPS:
			_rot = float(_rot_target)
			_ensure_front_selection()
	_apply_gate_layout()
	for g in _gates:
		if not is_instance_valid(g.glow):
			continue
		var pulse := sin(_time * 1.5 + float(g.phase)) * 0.06
		g.glow.modulate.a = maxf(0.0, float(g.glow_alpha) + pulse)
		g.ring.modulate.a = maxf(0.0, float(g.ring_alpha) + pulse * 0.5)


# ===================== 构建 =====================

func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = UIKit.ui_texture(UIKit.TEX_BG_REALM_SELECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.05, 0.18)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var top_shade := TextureRect.new()
	top_shade.texture = UIKit.vertical_gradient(Color(0.01, 0.02, 0.045, 0.72), Color(0.01, 0.02, 0.045, 0.0))
	top_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_shade.stretch_mode = TextureRect.STRETCH_SCALE
	top_shade.anchor_right = 1.0
	top_shade.offset_bottom = 120.0
	top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_shade)

	var bottom_shade := TextureRect.new()
	bottom_shade.texture = UIKit.vertical_gradient(Color(0.01, 0.02, 0.045, 0.0), Color(0.01, 0.02, 0.045, 0.92))
	bottom_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom_shade.stretch_mode = TextureRect.STRETCH_SCALE
	bottom_shade.anchor_top = 1.0
	bottom_shade.anchor_right = 1.0
	bottom_shade.anchor_bottom = 1.0
	bottom_shade.offset_top = -180.0
	bottom_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_shade)

	_build_turn_buttons()
	_build_info_bar()
	_rebuild_gates()


## 左右两个转格箭头：拖拽之外必须有可点的东西，否则触屏用户只会乱拖门。
func _build_turn_buttons() -> void:
	_turn_left = _make_turn_button("◀")
	_turn_left.anchor_top = 0.5
	_turn_left.anchor_bottom = 0.5
	_turn_left.offset_top = -26.0
	_turn_left.offset_bottom = 26.0
	_turn_left.offset_left = 10.0
	_turn_left.offset_right = 58.0
	_turn_left.pressed.connect(_turn.bind(-1))
	add_child(_turn_left)

	_turn_right = _make_turn_button("▶")
	_turn_right.anchor_left = 1.0
	_turn_right.anchor_right = 1.0
	_turn_right.anchor_top = 0.5
	_turn_right.anchor_bottom = 0.5
	_turn_right.offset_top = -26.0
	_turn_right.offset_bottom = 26.0
	_turn_right.offset_left = -58.0
	_turn_right.offset_right = -10.0
	_turn_right.pressed.connect(_turn.bind(1))
	add_child(_turn_right)


func _make_turn_button(glyph: String) -> Button:
	var b := Button.new()
	b.text = glyph
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0, 0.72))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	UIKit.attach_click_sfx(b, "ui_tab")
	return b


func _rebuild_gates() -> void:
	for g in _gates:
		if is_instance_valid(g.root):
			g.root.queue_free()
		if is_instance_valid(g.plaque):
			g.plaque.queue_free()
	_gates.clear()

	for i in range(_domains.size()):
		var d: Dictionary = _domains[i]
		var did := String(d.get("domain_id", ""))
		var accent: Color = GATE_COLORS[i % GATE_COLORS.size()]
		var locked := not CharacterData.is_domain_unlocked(did)

		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

		# 门本体：纯黑底 sprite + 加性材质。用普通 alpha 混合会把星云压成一块死黑方框。
		var sprite := TextureRect.new()
		sprite.texture = UIKit.ui_texture(String(GATE_SPRITE_FMT % did))
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_SCALE
		sprite.material = UIKit.additive_material()
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(sprite)

		var glow := UIKit.glow_node(Vector2(10, 10), accent if not locked else Color(0.45, 0.48, 0.55), 0.30)
		root.add_child(glow)

		var ring := UIKit.glow_node(Vector2(10, 10), accent if not locked else Color(0.40, 0.43, 0.50),
			0.28, UIKit.TEX_RING_SOFT)
		root.add_child(ring)

		var particles := CPUParticles2D.new()
		particles.amount = 14
		particles.lifetime = 4.6
		particles.preprocess = 2.5
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		particles.direction = Vector2(0, -1)
		particles.spread = 38.0
		particles.gravity = Vector2.ZERO
		particles.initial_velocity_min = 5.0
		particles.initial_velocity_max = 16.0
		particles.scale_amount_min = 0.07
		particles.scale_amount_max = 0.20
		particles.color = Color(accent.r, accent.g, accent.b, 0.55)
		particles.texture = UIKit.ui_texture(UIKit.TEX_DOT_SOFT)
		particles.emitting = not locked
		particles.visible = not locked
		root.add_child(particles)

		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		hit.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		UIKit.attach_click_sfx(hit, "ui_tab")
		# 不用 pressed 信号：门上要同时支持「点门」和「按住拖转」，两者得自己判
		hit.gui_input.connect(_on_gate_gui_input.bind(did))
		hit.mouse_entered.connect(_set_focus.bind(did))
		root.add_child(hit)

		var plaque := _make_plaque(did, accent, String(d.get("name", did)))
		add_child(plaque)

		_gates.append({
			"domain_id": did, "accent": accent, "locked": locked,
			"root": root, "sprite": sprite, "glow": glow, "ring": ring, "hit": hit,
			"particles": particles, "plaque": plaque,
			"name": plaque.get_child(0).get_child(0), "sub": plaque.get_child(0).get_child(1),
			"phase": float(i) * 1.7, "glow_alpha": 0.30, "ring_alpha": 0.28,
			"slot0": float(INITIAL_SLOT[i]) if i < INITIAL_SLOT.size() else float(i),
			"center": Vector2.ZERO, "radius": 60.0, "dim": 1.0,
			"in_depth": false,
		})

	_ensure_front_selection()
	if _selected_id == "" and not _gates.is_empty():
		_selected_id = String(_gates[0].domain_id)
	_update_page_dots()


## 铭牌：四格共用一套尺寸与锚点，一律贴在各自环的正下方。
## ⚠ 2026-11-06 用户「不要下面的框和红色方块」⇒ 这里只剩两行**没有底板的字**：
##   界名 + 进度。原来那枚 96² 的「已通关」红印既撑高了铭牌（TextureRect 默认
##   EXPAND_KEEP_SIZE，它的最小尺寸会把 PanelContainer 顶到 96 高），
##   又和右上角的图例、底部信息条的「已通关」章重复 —— 通关状态由那两处负责，
##   星图上的门只负责"这是哪一界、能不能点"。
func _make_plaque(did: String, accent: Color, realm_name: String) -> PanelContainer:
	var plaque := PanelContainer.new()
	plaque.mouse_filter = Control.MOUSE_FILTER_STOP
	plaque.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	plaque.custom_minimum_size = Vector2(196.0, 46.0)
	plaque.gui_input.connect(_on_gate_gui_input.bind(did))
	plaque.mouse_entered.connect(_set_focus.bind(did))

	var pb := UIKit.vbox(0)
	pb.alignment = BoxContainer.ALIGNMENT_CENTER
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(pb)
	var name_l := UIKit.outlined_label(realm_name, 19, accent, 1)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_child(name_l)
	var sub_l := UIKit.outlined_label("", 10, Color(0.80, 0.84, 0.92, 0.86), 1)
	sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_child(sub_l)
	return plaque


func _build_info_bar() -> void:
	_info_bar = PanelContainer.new()
	_info_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_bar.anchor_left = 0.0
	_info_bar.anchor_top = 1.0
	_info_bar.anchor_right = 1.0
	_info_bar.anchor_bottom = 1.0
	_info_bar.offset_left = 12.0
	_info_bar.offset_right = -12.0
	_info_bar.offset_top = -(INFO_HEIGHT + 12.0)
	_info_bar.offset_bottom = -12.0
	add_child(_info_bar)

	# 两栏：左文右钮。以前左栏里又塞按钮又塞提示，读起来像三栏。
	var row := UIKit.hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_bar.add_child(row)

	var info := UIKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var head := UIKit.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(head)
	_info_name = UIKit.label("", 22, Color(0.96, 0.94, 0.88))
	_info_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_info_name)
	_info_meta = UIKit.hbox(8)
	_info_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_info_meta)

	_info_desc = UIKit.readable_label("", 12, Color(0.74, 0.78, 0.86, 0.95))
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc.max_lines_visible = 2
	_info_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_info_desc)

	_info_foot = UIKit.label("", 10, Color(0.62, 0.68, 0.78, 0.92))
	_info_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_info_foot)

	var action := UIKit.vbox(4)
	action.custom_minimum_size = Vector2(176.0, 0.0)
	action.alignment = BoxContainer.ALIGNMENT_CENTER
	action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(action)
	_info_state = UIKit.hbox(6)
	_info_state.alignment = BoxContainer.ALIGNMENT_END
	_info_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action.add_child(_info_state)
	var hint := UIKit.label("左右拖动 · 旋转星图", 9, Color(0.60, 0.66, 0.76, 0.86))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_state.add_child(hint)
	_page_dots = UIKit.hbox(5)
	_page_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_page_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action.add_child(_page_dots)
	_cta = UIKit.primary_button("踏入此界", Vector2(156, 40), Color(0.52, 0.84, 1.0))
	UIKit.set_click_sfx(_cta, "ui_confirm")
	_cta.add_theme_font_size_override("font_size", UIKit.F_BODY)
	_cta.pressed.connect(_on_cta_pressed)
	action.add_child(_cta)


# ===================== 槽位与布局 =====================

## 第 i 个门当前的连续槽位坐标（0..n，可以带小数，落在两格之间就是在转）
func _slot_pos(g: Dictionary) -> float:
	var n := maxi(_gates.size(), 1)
	return fposmod(float(g.slot0) + _rot, float(n))


## 槽位坐标 -> 几何。跨 0 的那一格必须走「上一格 -> 第 0 格」，不能直接跳。
func _slot_at(pos: float) -> Dictionary:
	var n := maxi(_gates.size(), 1)
	var i0 := int(floor(pos))
	var i1 := i0 + 1
	var f := smoothstep(0.0, 1.0, pos - floor(pos))
	var a := _raw_slot(posmod(float(i0), float(n)))
	var b := _raw_slot(posmod(float(i1), float(n)))
	return {
		"center": (a.center as Vector2).lerp(b.center as Vector2, f),
		"radius": lerpf(float(a.radius), float(b.radius), f),
		"dim": lerpf(float(a.dim), float(b.dim), f),
		"tilt": lerpf(float(a.tilt), float(b.tilt), f),
	}


func _raw_slot(idx: int) -> Dictionary:
	if idx < SLOTS.size():
		return SLOTS[idx]
	var n := maxi(_gates.size(), SLOTS.size() + 1)
	var ang := -PI * 0.5 + float(idx - SLOTS.size()) * (TAU / float(n))
	push_warning("DomainStarMap: 位面数超过已登记槽位数，第 %d 格走外圈兜底" % (idx + 1))
	return {
		"center": EXTRA_RING_CENTER + EXTRA_RING_RADIUS * Vector2(cos(ang), sin(ang)),
		"radius": 190.0,
		"dim": 0.80,
		"tilt": 0.0,
	}


func _layout() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	_apply_gate_layout()
	_update_page_dots()


func _apply_gate_layout() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var scale := maxf(size.x / SRC_SIZE.x, size.y / SRC_SIZE.y)
	var drawn := SRC_SIZE * scale
	var offset := (size - drawn) * 0.5
	var info_top := size.y - INFO_HEIGHT - 24.0

	for g in _gates:
		var pos := _slot_pos(g)
		var slot := _slot_at(pos)
		var center: Vector2 = offset + (slot.center as Vector2) * scale
		var r := float(slot.radius) * scale
		var reach := maxf(r * 1.62, 88.0)
		g.center = center
		g.radius = r
		g.dim = float(slot.dim)
		# 深处那格按「离它有多远」判，不按整数格判：转到一半时它既不该可点也不该进选中态
		g.in_depth = float(slot.dim) < 0.70

		var root: Control = g.root
		root.position = center - Vector2(reach, reach)
		root.size = Vector2(reach * 2.0, reach * 2.0)
		root.pivot_offset = Vector2(reach, reach)
		root.rotation_degrees = float(slot.tilt)
		root.modulate = Color(1, 1, 1, float(slot.dim))

		var sprite: TextureRect = g.sprite
		var side := _sprite_side(g, r)
		sprite.size = Vector2(side, side)
		sprite.position = Vector2(reach, reach) - sprite.size * 0.5
		sprite.pivot_offset = sprite.size * 0.5

		var glow: TextureRect = g.glow
		glow.size = Vector2(r * 2.60, r * 2.60)
		glow.position = Vector2(reach, reach) - glow.size * 0.5
		glow.pivot_offset = glow.size * 0.5

		var ring: TextureRect = g.ring
		ring.size = Vector2(r * 2.15, r * 2.15)
		ring.position = Vector2(reach, reach) - ring.size * 0.5
		ring.pivot_offset = ring.size * 0.5

		var hit: Button = g.hit
		hit.size = Vector2(r * 1.9, r * 1.9)
		hit.position = Vector2(reach, reach) - hit.size * 0.5
		# 直接跟着本帧算出的 in_depth 走。以前另存一个 hit_clickable 给
		# _refresh_gate_visuals() 写、这里读，结果永远慢一帧：刚转进深处的门还点得动。
		hit.mouse_filter = Control.MOUSE_FILTER_IGNORE if bool(g.in_depth) else Control.MOUSE_FILTER_STOP

		var particles: CPUParticles2D = g.particles
		particles.position = Vector2(reach, reach)
		particles.emission_sphere_radius = r * 0.75

		# 铭牌同一套尺寸与样式，只分两种挂法：
		#   前排 → 挂在环的正下方（下方是辉光最淡的一侧，且离信息条还有余地）
		#   深处 → 居中刻在环里。它下方正对着中央那扇门，挂下去会压在别人的环上，
		#          而深处那格本来就不给点，名字写在门里读作「远景里的字」，不违和。
		var plaque: PanelContainer = g.plaque
		var pw := 196.0
		var ph := 46.0
		var ppos: Vector2
		if bool(g.in_depth):
			ppos = center - Vector2(pw * 0.5, ph * 0.5)
		else:
			ppos = Vector2(center.x - pw * 0.5, center.y + r * 1.5 + 12.0)
		plaque.position = Vector2(clampf(ppos.x, 8.0, size.x - pw - 8.0),
			clampf(ppos.y, 8.0, info_top - ph - 8.0))
		plaque.size = Vector2(pw, ph)
		plaque.modulate = Color(1, 1, 1, lerpf(0.62, 1.0, float(slot.dim)))

	_reorder_depth()


## 深处那格必须真的排在后排，否则转起来会从别的门上面擦过去。
## 铭牌不参与排序，一律压在最后：它们要始终读得清，不能被后排的门盖住。
func _reorder_depth() -> void:
	var by_dim := _gates.duplicate()
	by_dim.sort_custom(func(a, b): return float(a.dim) < float(b.dim))
	# 逐个压到末尾，顺序自然就成了「远的在下、近的在上」，不用去数前面有几个静态节点
	for g in by_dim:
		if is_instance_valid(g.root):
			move_child(g.root, get_child_count() - 1)
	for g in _gates:
		if is_instance_valid(g.plaque):
			move_child(g.plaque, get_child_count() - 1)


func _sprite_side(g: Dictionary, r: float) -> float:
	var ring_px := float(GATE_RING_PX.get(String(g.domain_id), GATE_RING_PX_FALLBACK))
	return r * GATE_SPRITE_PX / maxf(ring_px, 1.0)


func _update_page_dots() -> void:
	if _page_dots == null:
		return
	UIKit.clear_children(_page_dots)
	for g in _gates:
		var on := String(g.domain_id) == _selected_id
		var w := 16.0 if on else 7.0
		var dot := UIKit.glow_node(Vector2(w, 7),
			_info_accent if on else Color(0.55, 0.60, 0.72), 1.0 if on else 0.55)
		dot.custom_minimum_size = Vector2(w, 7)
		_page_dots.add_child(dot)


# ===================== 旋转 =====================

func _turn(dir: int) -> void:
	_rot_target += dir
	_refresh_gate_visuals()
	_update_info()
	page_changed.emit(_rot_target)


func _at_rest() -> bool:
	return absf(_rot - float(_rot_target)) <= REST_EPS


## 选中态只准在前排三格里移动：深处那格不可点，也不该占着信息栏。
func _ensure_front_selection() -> void:
	if _gates.is_empty():
		return
	for g in _gates:
		if String(g.domain_id) == _selected_id and not bool(g.in_depth):
			return
	var best := ""
	var best_score := -1.0
	for g in _gates:
		if bool(g.in_depth):
			continue
		# 优先中央那格（槽位 0），其次任意前排格
		var score := 2.0 if _slot_pos(g) < 0.5 or _slot_pos(g) > float(_gates.size()) - 0.5 else 1.0
		if score > best_score:
			best_score = score
			best = String(g.domain_id)
	if best != "":
		_selected_id = best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_turn(-1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_turn(1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_drag(mb.global_position.x)
			else:
				_end_drag(mb.global_position.x)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_move_drag((event as InputEventMouseMotion).global_position.x)
		accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_begin_drag(st.position.x)
		else:
			_end_drag(st.position.x)
		accept_event()
	elif event is InputEventScreenDrag and _dragging:
		_move_drag((event as InputEventScreenDrag).position.x)
		accept_event()


func _on_gate_gui_input(event: InputEvent, domain_id: String) -> void:
	# 门上也要能拖：门的命中圈盖住了大半张图，只让空白处拖等于拖不动
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_begin_drag(mb.global_position.x)
		else:
			_end_drag(mb.global_position.x)
			if not _drag_moved and _at_rest():
				_press_gate(domain_id)
	elif event is InputEventMouseMotion and _dragging:
		_move_drag((event as InputEventMouseMotion).global_position.x)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_begin_drag(st.position.x)
		else:
			_end_drag(st.position.x)
			if not _drag_moved and _at_rest():
				_press_gate(domain_id)
	elif event is InputEventScreenDrag and _dragging:
		_move_drag((event as InputEventScreenDrag).position.x)


func _begin_drag(x: float) -> void:
	_dragging = true
	_drag_x = x
	_drag_rot = _rot
	_drag_moved = false


func _move_drag(x: float) -> void:
	if not _dragging:
		return
	var dx := x - _drag_x
	if absf(dx) > DRAG_THRESHOLD:
		_drag_moved = true
	# rot 的单位就是「格」。拖过 45% 屏宽 = 前进一格，和门有几只无关。
	# 往左拖（dx<0）内容跟着往左 = 前排往左掉进深处，所以 rot 增加。
	_rot = _drag_rot - dx / maxf(size.x * DRAG_PX_PER_SLOT, 1.0)


func _end_drag(_x: float) -> void:
	if not _dragging:
		return
	_dragging = false
	if _drag_moved:
		_rot_target = int(round(_rot))
		_refresh_gate_visuals()
		_update_info()
		_update_page_dots()
		page_changed.emit(_rot_target)


# ===================== 状态 =====================

func _gate_progress(domain_id: String) -> Dictionary:
	var d := WorldDB.get_domain(domain_id)
	var boss_ids: Array = d.get("boss_ids", [])
	var killed := 0
	for b in boss_ids:
		if CharacterData.is_boss_cleared(domain_id, String(b)):
			killed += 1
	return {"killed": killed, "total": boss_ids.size(), "ids": boss_ids}


func _gate_sub_text(domain_id: String) -> String:
	var p := _gate_progress(domain_id)
	if not CharacterData.is_domain_unlocked(domain_id):
		return CharacterData.domain_lock_reason(domain_id)
	return "%d/%d" % [int(p.killed), int(p.total)]


func _set_focus(domain_id: String) -> void:
	if domain_id == "" or domain_id == _selected_id:
		return
	for g in _gates:
		if String(g.domain_id) == domain_id and bool(g.in_depth):
			return
	_selected_id = domain_id
	_refresh_gate_visuals()
	_update_info()


func _refresh_gate_visuals() -> void:
	for g in _gates:
		var did := String(g.domain_id)
		var locked := bool(g.locked)
		var depth := bool(g.in_depth)
		var chosen := did == _selected_id and not depth
		var accent: Color = g.accent if not locked else Color(0.48, 0.50, 0.56)
		# 光门本体现在是 sprite 画的，这两个节点只是「选中态」的提示。
		# 改版前它们是门的全部亮度（0.30/0.56），照搬到有 sprite 的版本上
		# 实测四扇门一起过曝成白团 —— 选中要靠铭牌描边和这层薄光，不是靠把门点着。
		g.glow_alpha = 0.10 if chosen and not locked else (0.05 if not locked else 0.03)
		g.ring_alpha = 0.34 if chosen and not locked else (0.12 if not locked else 0.05)
		var glow: TextureRect = g.glow
		glow.modulate = Color(accent.r, accent.g, accent.b, float(g.glow_alpha))
		var ring: TextureRect = g.ring
		ring.modulate = Color(accent.r, accent.g, accent.b, float(g.ring_alpha))
		var particles: CPUParticles2D = g.particles
		particles.emitting = not locked and not depth
		particles.visible = not locked and not depth
		particles.color = Color(accent.r, accent.g, accent.b, 0.55)

		var name_l: Label = g.name
		name_l.add_theme_color_override("font_color", accent if not locked else UIKit.C_DISABLE)
		var sub_l: Label = g.sub
		sub_l.text = _gate_sub_text(did)
		sub_l.add_theme_color_override("font_color",
			UIKit.C_DISABLE if locked else Color(0.80, 0.84, 0.92, 0.86))

		var plaque: PanelContainer = g.plaque
		var tip := "点击光门 · 选择守关者" if not locked else CharacterData.domain_lock_reason(did)
		if depth:
			tip = "此界在星图深处 · 左右拖动转过来再选"
		plaque.tooltip_text = tip
		## 底板整个摘掉（用户：不要下面的框）。选中态不再靠框，
		## 由底部信息条的界名 + 守关者菱形 + 这行字的描边色共同承担。
		plaque.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var hit: Button = g.hit
		hit.tooltip_text = tip


func _update_info() -> void:
	var d := WorldDB.get_domain(_selected_id)
	if d.is_empty():
		return
	var accent: Color = GATE_COLORS[0]
	for g in _gates:
		if String(g.domain_id) == _selected_id:
			accent = g.accent
			break
	_info_accent = accent
	_info_bar.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(accent, 0.92, 0.48, 8))

	var required := String(d.get("realm_required", ""))
	var realm_ok := CharacterData.is_domain_realm_ok(_selected_id)
	var locked := not CharacterData.is_domain_unlocked(_selected_id)
	var cleared := CharacterData.is_domain_cleared(_selected_id)
	var p := _gate_progress(_selected_id)
	var killed := int(p.killed)
	var boss_ids: Array = p.ids

	_info_name.text = String(d.get("name", _selected_id))
	_info_name.add_theme_color_override("font_color", Color(0.98, 0.95, 0.86))

	UIKit.clear_children(_info_meta)
	if cleared:
		_info_meta.add_child(UIKit.chip("已通关", UIKit.C_OK))
	elif locked:
		_info_meta.add_child(UIKit.chip("未开放", UIKit.C_DISABLE))
	elif realm_ok:
		_info_meta.add_child(UIKit.chip("可挑战", accent))
	else:
		_info_meta.add_child(UIKit.chip("可硬闯", UIKit.C_WARN))
	_info_meta.add_child(UIKit.chip("境界 %s" % required,
		UIKit.C_OK if realm_ok else UIKit.C_WARN))

	_info_desc.text = String(d.get("desc", ""))

	# 守关者进度只在这一处出现：以前铭牌和图例各写一遍，三处口径互相打脸
	var parts: Array[String] = []
	for b in boss_ids:
		parts.append("◆" if CharacterData.is_boss_cleared(_selected_id, String(b)) else "◇")
	var progress := "守关者 %d/%d　%s" % [killed, boss_ids.size(), " ".join(parts)]
	var prev_id := String(d.get("prev_domain", ""))
	var prev_text := ""
	if prev_id != "":
		prev_text = "　前置：%s %s" % [
			WorldDB.get_domain_name(prev_id),
			"已完成" if CharacterData.is_domain_cleared(prev_id) else "未完成",
		]
	_info_foot.text = progress + prev_text
	_info_foot.add_theme_color_override("font_color",
		UIKit.C_DISABLE if locked else Color(0.68, 0.74, 0.84, 0.94))

	_cta.disabled = locked
	if locked:
		_cta.text = "尚未开放"
		_cta.tooltip_text = CharacterData.domain_lock_reason(_selected_id)
	elif cleared:
		_cta.text = "再入此界"
		_cta.tooltip_text = "已通关，可重新挑战守关者"
	else:
		_cta.text = "踏入此界"
		_cta.tooltip_text = "境界不足也可硬闯" if not realm_ok else "进入此界，选择守关者"
	_update_page_dots()


func _press_gate(domain_id: String) -> void:
	for g in _gates:
		if String(g.domain_id) == domain_id and bool(g.in_depth):
			# 深处那格点了不报错、也不进信息栏，只给一句「转过来」
			GameState.play_ui("ui_deny")
			return
	_set_focus(domain_id)
	if CharacterData.is_domain_unlocked(domain_id):
		gate_entered.emit(domain_id)
	else:
		_shake_gate(domain_id)
		locked_picked.emit(domain_id, CharacterData.domain_lock_reason(domain_id))


func _on_cta_pressed() -> void:
	if _selected_id == "":
		return
	if CharacterData.is_domain_unlocked(_selected_id):
		gate_entered.emit(_selected_id)
	else:
		_shake_gate(_selected_id)
		locked_picked.emit(_selected_id, CharacterData.domain_lock_reason(_selected_id))


func _shake_gate(domain_id: String) -> void:
	for g in _gates:
		if String(g.domain_id) != domain_id:
			continue
		var plaque: PanelContainer = g.plaque
		var base := plaque.position
		var tw := create_tween()
		tw.tween_property(plaque, "position:x", base.x - 6.0, 0.05)
		tw.tween_property(plaque, "position:x", base.x + 6.0, 0.07)
		tw.tween_property(plaque, "position:x", base.x, 0.05)
		break
