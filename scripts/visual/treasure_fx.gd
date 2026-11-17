class_name TreasureFx
extends RefCounted
## 主动法宝的共享表现：凝水佩的蓝色聚拢、逐电环的雷电覆体与拖尾、太极盘的脚下太极护体。
## 玩家与野修共用，避免两边各写一套粒子参数。

const THUNDER_COLOR := Color(1.0, 0.92, 0.30, 1.0)
const AURA_NAME := "TreasureThunderAura"
const TAIJI_COLOR := Color(0.98, 0.90, 0.68, 1.0)
const TAIJI_GUARD_NAME := "TreasureTaijiGuard"
const TAIJI_TEX := "res://assets/effects/skills/liangyi_taiji.png"
const TRI_RING_NAME := "TreasureTriRing"
const TRI_RING_TEX := "res://assets/effects/skills/calamity_wheel.png"
const TRI_RING_COLOR := Color(0.90, 0.84, 0.68, 1.0)


static func play_water_gather(host: Node2D, body_center: Vector2) -> void:
	if not is_instance_valid(host):
		return
	FxPlayer.spawn(host, "fx_treasure_water_gather", {"position": body_center})


## 附着 3 秒雷电：身体周围随机雷弧 + 世界坐标拖尾粒子，随宿主移动留下电光轨迹
static func attach_thunder(host: Node2D, body_center: Vector2, duration: float) -> Node2D:
	if not is_instance_valid(host):
		return null
	var old := host.get_node_or_null(AURA_NAME)
	if old != null:
		old.name = AURA_NAME + "Old"
		old.queue_free()
	var aura := ThunderAura.new()
	aura.name = AURA_NAME
	aura.host = host
	aura.duration = maxf(0.1, duration)
	aura.position = body_center
	aura.z_index = 6
	host.add_child(aura)
	FxPlayer.spawn(host, "fx_treasure_thunder_burst", {"position": body_center})
	return aura


static func tri_ring_color(elem: String) -> Color:
	match elem:
		"wind":
			return Color(0.55, 0.84, 0.76, 1.0)
		"fire":
			return Color(1.0, 0.50, 0.22, 1.0)
		"thunder":
			return Color(0.72, 0.62, 1.0, 1.0)
	return TRI_RING_COLOR


## 三元轮·三炁环身：风 / 火 / 雷三圈光环绕身旋转，按当前轮换元素逐圈提亮
static func attach_tri_ring(host: Node2D, body_center: Vector2, duration: float) -> Node2D:
	if not is_instance_valid(host):
		return null
	var old := host.get_node_or_null(TRI_RING_NAME)
	if old != null:
		old.name = TRI_RING_NAME + "Old"
		old.queue_free()
	var aura := TriRingAura.new()
	aura.name = TRI_RING_NAME
	aura.duration = maxf(0.1, duration)
	aura.position = body_center
	aura.z_index = 5
	host.add_child(aura)
	return aura


## 太极盘·太极护体：脚下铺一张缓缓自转的太极盘（加色混合），消失前淡出
static func attach_taiji_guard(host: Node2D, body_center: Vector2, duration: float) -> Node2D:
	if not is_instance_valid(host):
		return null
	var old := host.get_node_or_null(TAIJI_GUARD_NAME)
	if old != null:
		old.name = TAIJI_GUARD_NAME + "Old"
		old.queue_free()
	var guard := TaijiGuard.new()
	guard.name = TAIJI_GUARD_NAME
	guard.duration = maxf(0.1, duration)
	guard.position = body_center
	guard.z_index = 1
	host.add_child(guard)
	return guard


class TaijiGuard:
	extends Node2D

	var duration: float = 6.0
	var _t: float = 0.0
	var _spr: Sprite2D = null

	func _ready() -> void:
		var tex: Texture2D = load(TAIJI_TEX)
		_spr = Sprite2D.new()
		_spr.texture = tex
		_spr.centered = true
		_spr.scale = Vector2(0.52, 0.52)     # 512 → 266px，托住接化发的绕身轨道
		_spr.position = Vector2(0.0, 58.0)   # body_center 在胸口，+58 落到脚底
		_spr.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_spr.material = mat
		add_child(_spr)

	func _process(delta: float) -> void:
		_t += delta
		if _spr == null or not is_instance_valid(_spr):
			return
		var left := duration - _t
		if left <= 0.0:
			queue_free()
			return
		# 进场 0.18 秒淡入、退场 0.35 秒淡出
		var a := clampf(_t / 0.18, 0.0, 1.0) * clampf(left / 0.35, 0.0, 1.0)
		_spr.rotation += delta * 0.85
		_spr.modulate.a = 0.5 * a
		var breathe := 1.0 + 0.02 * sin(_t * 5.0)
		_spr.scale = Vector2(0.52, 0.52) * breathe


class ThunderAura:
	extends Node2D

	const BOLT_COUNT := 4
	const REDRAW_INTERVAL := 0.055

	var host: Node2D
	var duration: float = 3.0

	var _left: float = 0.0
	var _redraw_left: float = 0.0
	var _rng := RandomNumberGenerator.new()
	var _bolts: Array[PackedVector2Array] = []
	var _sparks := PackedVector2Array()
	var _trail: CPUParticles2D


	func _ready() -> void:
		_left = duration
		_rng.randomize()
		_build_trail()
		_rebuild_bolts()


	func _process(delta: float) -> void:
		_left -= delta
		if _left <= 0.0:
			queue_free()
			return
		modulate.a = clampf(_left / 0.22, 0.0, 1.0)
		if _trail != null:
			_update_trail_direction()
		_redraw_left -= delta
		if _redraw_left <= 0.0:
			_redraw_left = REDRAW_INTERVAL
			_rebuild_bolts()


	func _update_trail_direction() -> void:
		var v := Vector2.ZERO
		if is_instance_valid(host):
			var raw = host.get("velocity")
			if raw is Vector2:
				v = raw
		_trail.direction = -v.normalized() if v.length_squared() > 100.0 else Vector2.DOWN


	func _rebuild_bolts() -> void:
		_bolts.clear()
		_sparks.clear()
		for i in BOLT_COUNT:
			var pts := PackedVector2Array()
			pts.append(Vector2(_rng.randf_range(-18.0, 18.0), -36.0))
			var phase := _rng.randf_range(0.0, TAU)
			for j in range(1, 7):
				var t := float(j) / 6.0
				var spread := 22.0 * (0.45 + t * 0.55)
				var x := _rng.randf_range(-spread, spread) + sin(t * PI + phase + float(i)) * 7.0
				pts.append(Vector2(x, lerpf(-36.0, 30.0, t)))
			_bolts.append(pts)
		for i in 5:
			_sparks.append(Vector2(_rng.randf_range(-26.0, 26.0), _rng.randf_range(-34.0, 28.0)))
		queue_redraw()


	func _draw() -> void:
		for pts in _bolts:
			draw_polyline(pts, Color(1.0, 0.78, 0.08, 0.22), 6.0, true)
			draw_polyline(pts, Color(1.0, 0.96, 0.55, 0.82), 2.2, true)
			draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.9), 0.9, true)
		for p in _sparks:
			draw_circle(p, 4.0, Color(1.0, 0.9, 0.2, 0.18))
			draw_circle(p, 1.8, Color(1.0, 0.98, 0.58, 0.92))


	func _build_trail() -> void:
		_trail = CPUParticles2D.new()
		_trail.name = "Trail"
		_trail.amount = 56
		_trail.lifetime = 0.5
		_trail.local_coords = false
		_trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_trail.emission_sphere_radius = 18.0
		_trail.direction = Vector2.DOWN
		_trail.spread = 60.0
		_trail.initial_velocity_min = 24.0
		_trail.initial_velocity_max = 90.0
		_trail.gravity = Vector2(0.0, 40.0)
		_trail.scale_amount_min = 0.7
		_trail.scale_amount_max = 1.7
		_trail.color = Color(1.0, 0.93, 0.35, 1.0)
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 1.0, 0.78, 1.0))
		ramp.set_color(1, Color(1.0, 0.72, 0.08, 0.0))
		_trail.color_ramp = ramp
		_trail.texture = _make_spark_texture()
		add_child(_trail)
		_trail.emitting = true


	func _make_spark_texture() -> Texture2D:
		var size := 12
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var center := Vector2(size * 0.5 - 0.5, size * 0.5 - 0.5)
		for y in size:
			for x in size:
				var d := Vector2(x, y).distance_to(center) / (size * 0.5)
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
		return ImageTexture.create_from_image(img)


class TriRingAura:
	extends Node2D

	const RING_COLORS := [
		Color(0.55, 0.84, 0.76, 1.0),
		Color(1.0, 0.50, 0.22, 1.0),
		Color(0.72, 0.62, 1.0, 1.0),
	]

	var duration: float = 8.0
	var _t: float = 0.0
	var _rings: Array[Sprite2D] = []

	func _ready() -> void:
		var tex: Texture2D = load(TRI_RING_TEX)
		for i in 3:
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = true
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			spr.material = mat
			spr.rotation = float(i) * TAU / 3.0
			spr.modulate = Color(RING_COLORS[i].r, RING_COLORS[i].g, RING_COLORS[i].b, 0.0)
			add_child(spr)
			_rings.append(spr)

	func _process(delta: float) -> void:
		_t += delta
		var left := duration - _t
		if left <= 0.0:
			queue_free()
			return
		var fade := clampf(_t / 0.18, 0.0, 1.0) * clampf(left / 0.32, 0.0, 1.0)
		var active := int(floor(_t / 2.0)) % 3
		for i in _rings.size():
			var spr := _rings[i]
			var pulse := 0.5 + 0.5 * sin(_t * 3.2 + float(i) * TAU / 3.0)
			var base := 0.22 + 0.08 * float(i)
			spr.scale = Vector2(base, base) * (1.0 + 0.05 * pulse)
			spr.rotation += delta * (0.9 + 0.25 * float(i)) * (1.0 if i % 2 == 0 else -1.0)
			var alpha := (0.46 if i == active else 0.14) + 0.10 * pulse
			var c: Color = RING_COLORS[i]
			spr.modulate = Color(c.r, c.g, c.b, alpha * fade)


# ===================== 野修法宝第二组（2026-11-01）=====================
## 柔边圆环 / 柔边圆盘：禁步桩、断念铃共用。
## 用户明确不要硬边圆环，所以这里用预生成的柔边贴图，而不是 draw_arc。
const SOFT_RING_RADIUS_PX := 112.0
const LAMP_NAME := "TreasureLampAura"
const LAMP_ICON := "res://assets/ui/icon/tr_xuming_deng.png"
const CORRODE_NAME := "TreasureCorrodeNail"
const CONE_ICON := "res://assets/ui/icon/tr_shixi_zhui.png"
const THORNS_NAME := "TreasureThornsAura"
const BLOOD_SEAL_ICON := "res://assets/ui/icon/tr_xuesi_yin.png"

static var _soft_ring_tex: Texture2D = null
static var _soft_disc_tex: Texture2D = null


static func soft_ring_texture() -> Texture2D:
	if _soft_ring_tex == null:
		_soft_ring_tex = _make_radial_texture(true)
	return _soft_ring_tex


static func soft_disc_texture() -> Texture2D:
	if _soft_disc_tex == null:
		_soft_disc_tex = _make_radial_texture(false)
	return _soft_disc_tex


static func _make_radial_texture(ring: bool) -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5 - 0.5, size * 0.5 - 0.5)
	var edge := SOFT_RING_RADIUS_PX
	var feather := 11.0
	for y in size:
		for x in size:
			var d := Vector2(float(x), float(y)).distance_to(center)
			var a := 0.0
			if ring:
				a = clampf(1.0 - absf(d - edge) / feather, 0.0, 1.0)
				a = a * a
			else:
				a = clampf(1.0 - d / edge, 0.0, 1.0)
				a = a * a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


## 断念铃：以施法者为中心向外扩一圈柔边铃波
static func play_bell_ring(host: Node2D, body_center: Vector2, radius: float,
		tint: Color) -> void:
	if not is_instance_valid(host):
		return
	var fx := BellRing.new()
	fx.name = "TreasureBellRing"
	fx.radius = maxf(60.0, radius)
	fx.tint = tint
	fx.position = body_center
	fx.z_index = 6
	host.add_child(fx)


class BellRing:
	extends Node2D

	var radius: float = 300.0
	var tint: Color = Color(0.74, 0.62, 0.98, 1.0)
	var _t: float = 0.0
	var _life: float = 0.45
	var _spr: Sprite2D = null
	var _base_scale: float = 1.0

	func _ready() -> void:
		_spr = Sprite2D.new()
		_spr.texture = TreasureFx.soft_ring_texture()
		_spr.centered = true
		_base_scale = radius / TreasureFx.SOFT_RING_RADIUS_PX
		_spr.scale = Vector2(_base_scale * 0.22, _base_scale * 0.22)
		_spr.modulate = Color(tint.r, tint.g, tint.b, 0.0)
		add_child(_spr)

	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / _life, 0.0, 1.0)
		var s := lerpf(0.22, 1.0, k)
		if _spr != null:
			_spr.scale = Vector2(_base_scale * s, _base_scale * s)
			_spr.modulate.a = (1.0 - k) * 0.78
		if k >= 1.0:
			queue_free()


## 野修断念铃：摇铃前摇的可读光圈（向内收束）
static func attach_bell_charge(host: Node2D, body_center: Vector2, duration: float) -> Node2D:
	if not is_instance_valid(host):
		return null
	var fx := BellCharge.new()
	fx.name = "TreasureBellCharge"
	fx.duration = maxf(0.1, duration)
	fx.position = body_center
	fx.z_index = 6
	host.add_child(fx)
	return fx


class BellCharge:
	extends Node2D

	var duration: float = 0.45
	var _t: float = 0.0
	var _spr: Sprite2D = null

	func _ready() -> void:
		_spr = Sprite2D.new()
		_spr.texture = TreasureFx.soft_ring_texture()
		_spr.centered = true
		_spr.modulate = Color(0.74, 0.62, 0.98, 0.0)
		add_child(_spr)

	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / duration, 0.0, 1.0)
		if _spr != null:
			var s := lerpf(1.05, 0.18, k)
			_spr.scale = Vector2(s, s)
			_spr.modulate.a = k * 0.72
		if k >= 1.0:
			queue_free()


## 续命灯：暖黄灯晕 + 挂在身侧的小灯
static func attach_lamp(host: Node2D, body_center: Vector2, duration: float) -> Node2D:
	if not is_instance_valid(host):
		return null
	var old := host.get_node_or_null(LAMP_NAME)
	if old != null:
		old.name = LAMP_NAME + "Old"
		old.queue_free()
	var aura := LampAura.new()
	aura.name = LAMP_NAME
	aura.duration = maxf(0.1, duration)
	aura.position = body_center
	aura.z_index = 6
	host.add_child(aura)
	return aura


class LampAura:
	extends Node2D

	var duration: float = 10.0
	var _t: float = 0.0
	var _glow: Sprite2D = null
	var _icon: Sprite2D = null

	func _ready() -> void:
		_glow = Sprite2D.new()
		_glow.texture = TreasureFx.soft_disc_texture()
		_glow.centered = true
		_glow.modulate = Color(1.0, 0.76, 0.30, 0.18)
		_glow.scale = Vector2(0.62, 0.62)
		_glow.z_index = -1
		add_child(_glow)
		var tex: Texture2D = load(TreasureFx.LAMP_ICON)
		if tex != null:
			_icon = Sprite2D.new()
			_icon.texture = tex
			_icon.centered = true
			_icon.scale = Vector2(0.11, 0.11)
			_icon.position = Vector2(14.0, -18.0)
			add_child(_icon)

	func _process(delta: float) -> void:
		_t += delta
		var left := duration - _t
		if left <= 0.0:
			queue_free()
			return
		var fade := clampf(_t / 0.2, 0.0, 1.0) * clampf(left / 0.3, 0.0, 1.0)
		var pulse := 0.85 + 0.15 * sin(_t * 3.4)
		if _glow != null:
			_glow.modulate.a = 0.18 * fade * pulse
			_glow.scale = Vector2(0.62, 0.62) * (0.96 + 0.06 * sin(_t * 3.4))
		if _icon != null:
			_icon.position.y = -18.0 + sin(_t * 2.2) * 3.0
			_icon.modulate.a = 0.9 * fade


static func play_lamp_break(host: Node2D, body_center: Vector2) -> void:
	if not is_instance_valid(host):
		return
	FxPlayer.spawn(host, "fx_treasure_lamp_break", {"position": body_center})


## 蚀甲锥命中：把锥子插在目标身上，持续期间显示蚀痕
static func attach_corrode(host: Node2D, body_center: Vector2, duration: float) -> Node2D:
	if not is_instance_valid(host):
		return null
	var old := host.get_node_or_null(CORRODE_NAME)
	if old != null:
		old.queue_free()
	var nail := CorrodeNail.new()
	nail.name = CORRODE_NAME
	nail.duration = maxf(0.1, duration)
	nail.position = body_center
	nail.z_index = 7
	host.add_child(nail)
	return nail


class CorrodeNail:
	extends Node2D

	var duration: float = 8.0
	var _t: float = 0.0
	var _spr: Sprite2D = null
	var _glow: Sprite2D = null

	func _ready() -> void:
		_glow = Sprite2D.new()
		_glow.texture = TreasureFx.soft_disc_texture()
		_glow.centered = true
		_glow.scale = Vector2(0.16, 0.16)
		_glow.modulate = Color(0.55, 0.85, 0.42, 0.10)
		add_child(_glow)
		var tex: Texture2D = load(TreasureFx.CONE_ICON)
		if tex != null:
			_spr = Sprite2D.new()
			_spr.texture = tex
			_spr.centered = true
			_spr.scale = Vector2(0.14, 0.14)
			_spr.rotation = -0.42
			add_child(_spr)

	func _process(delta: float) -> void:
		_t += delta
		var left := duration - _t
		if left <= 0.0:
			queue_free()
			return
		var fade := clampf(_t / 0.12, 0.0, 1.0) * clampf(left / 0.3, 0.0, 1.0)
		if _spr != null:
			_spr.modulate.a = 0.95 * fade
			_spr.rotation = -0.42 + sin(_t * 3.0) * 0.05
		if _glow != null:
			_glow.modulate.a = (0.10 + 0.04 * sin(_t * 5.0)) * fade


static func play_cone_hit(host: Node, world_pos: Vector2) -> void:
	if not is_instance_valid(host):
		return
	FxPlayer.spawn(host, "fx_treasure_cone_hit", {"global_position": world_pos})


# ===================== 野修法宝第三组（2026-11-01）=====================

## 柔边环的通用播放入口（血饲 / 换位 / 回风共用）
static func play_soft_ring(host: Node2D, body_center: Vector2, radius: float,
		tint: Color) -> void:
	if not is_instance_valid(host):
		return
	var fx := BellRing.new()
	fx.name = "TreasureSoftRing"
	fx.radius = maxf(20.0, radius)
	fx.tint = tint
	fx.position = body_center
	fx.z_index = 6
	host.add_child(fx)


## 换位：两个世界坐标各放一圈玉色柔边环
static func play_swap(parent: Node, from_pos: Vector2, to_pos: Vector2) -> void:
	if not (parent is Node2D):
		return
	var p := parent as Node2D
	for pos in [from_pos, to_pos]:
		var fx := BellRing.new()
		fx.name = "TreasureSwapRing"
		fx.radius = 74.0
		fx.tint = Color(0.56, 0.86, 0.78, 1.0)
		fx.z_index = 6
		p.add_child(fx)
		fx.global_position = pos


static func play_blood_seal(host: Node2D, body_center: Vector2) -> void:
	if not is_instance_valid(host):
		return
	play_soft_ring(host, body_center, 96.0, Color(0.84, 0.24, 0.20, 1.0))
	FxPlayer.spawn(host, "fx_treasure_blood_seal", {"position": body_center})
	# 短暂浮起一枚血印，和棘甲的红色环区分开
	var tex: Texture2D = load(BLOOD_SEAL_ICON) if ResourceLoader.exists(BLOOD_SEAL_ICON) else null
	if tex == null:
		return
	var mark := Sprite2D.new()
	mark.texture = tex
	mark.centered = true
	mark.scale = Vector2(0.12, 0.12)
	mark.position = body_center + Vector2(0.0, -34.0)
	mark.z_index = 7
	host.add_child(mark)
	var tw := mark.create_tween()
	tw.tween_property(mark, "position:y", mark.position.y - 16.0, 0.5)
	tw.parallel().tween_property(mark, "modulate:a", 0.0, 0.55)
	tw.tween_callback(mark.queue_free)


static func play_thorns_burst(host: Node2D, body_center: Vector2) -> void:
	if not is_instance_valid(host):
		return
	FxPlayer.spawn(host, "fx_treasure_thorns_burst", {"position": body_center})


## 棘甲佩：暗红棘环绕身
static func attach_thorns(host: Node2D, body_center: Vector2, duration: float) -> Node2D:
	if not is_instance_valid(host):
		return null
	var old := host.get_node_or_null(THORNS_NAME)
	if old != null:
		old.name = THORNS_NAME + "Old"
		old.queue_free()
	var aura := ThornsAura.new()
	aura.name = THORNS_NAME
	aura.duration = maxf(0.1, duration)
	aura.position = body_center
	aura.z_index = 6
	host.add_child(aura)
	return aura


class ThornsAura:
	extends Node2D

	var duration: float = 4.0
	var _t: float = 0.0
	var _ring: Sprite2D = null
	var _glow: Sprite2D = null

	func _ready() -> void:
		_glow = Sprite2D.new()
		_glow.texture = TreasureFx.soft_disc_texture()
		_glow.centered = true
		_glow.scale = Vector2(0.34, 0.34)
		_glow.modulate = Color(0.70, 0.18, 0.16, 0.16)
		_glow.z_index = -1
		add_child(_glow)
		_ring = Sprite2D.new()
		_ring.texture = TreasureFx.soft_ring_texture()
		_ring.centered = true
		_ring.scale = Vector2(0.46, 0.46)
		_ring.modulate = Color(0.90, 0.32, 0.24, 0.52)
		add_child(_ring)

	func _process(delta: float) -> void:
		_t += delta
		var left := duration - _t
		if left <= 0.0:
			queue_free()
			return
		var fade := clampf(_t / 0.16, 0.0, 1.0) * clampf(left / 0.28, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_t * 8.0)
		if _ring != null:
			_ring.rotation += delta * 2.6
			_ring.modulate.a = (0.42 + 0.18 * pulse) * fade
			_ring.scale = Vector2(0.46, 0.46) * (1.0 + 0.05 * pulse)
		if _glow != null:
			_glow.modulate.a = (0.13 + 0.05 * pulse) * fade


static func play_gust(host: Node2D, body_center: Vector2, radius: float) -> void:
	if not is_instance_valid(host):
		return
	play_soft_ring(host, body_center, radius, Color(0.64, 0.86, 0.84, 1.0))
	FxPlayer.spawn(host, "fx_treasure_gust", {"position": body_center})
