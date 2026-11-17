class_name TitleAbsorbFx
extends Node2D
## 开始界面「被吸入」的高密度演出。
##
## 构成：程序化涡流场（shader）+ 柔光核 + 双层能量环 + 慢速星尘 / 快速星屑
##       + 主角身上的能量拖尾 + 溶解冲击波 + 收束爆闪。
## 纹理全部在这里程序化生成并缓存，不依赖额外的美术资源，也不再用折线/圆环描边。

var radius := 190.0
## 被吸入的主角；拖尾与冲击波以它为锚点
var source: Node2D

var _vortex: Sprite2D
var _vortex_mat: ShaderMaterial
var _halo: Sprite2D
var _core: Sprite2D
var _core_star: Sprite2D
var _ring_a: Sprite2D
var _ring_b: Sprite2D
var _flare: Sprite2D
var _collapse_glow: Sprite2D
var _dust_slow: CPUParticles2D
var _dust_fast: CPUParticles2D
var _wisps: CPUParticles2D
var _burst: CPUParticles2D
var _additive: CanvasItemMaterial

var _elapsed := 0.0
var _intensity := 0.0
var _target_intensity := 0.85
var _spin := 0.7
var _spin_target := 0.7
var _core_boost := 0.0
var _pull_started := false
var _dissolve_started := false
var _collapsed := false
var _deadline := 6.0
var _ring_base_a := Vector2.ONE
var _ring_base_b := Vector2.ONE

static var _tex_cache: Dictionary = {}


func _ready() -> void:
	z_index = 0
	_additive = CanvasItemMaterial.new()
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_build_field()
	_build_particles()
	_build_burst_layers()
	_vortex_mat.set_shader_parameter("intensity", 0.0)
	_vortex_mat.set_shader_parameter("spin", _spin)
	_vortex_mat.set_shader_parameter("core_boost", 0.0)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > _deadline:
		queue_free()
		return
	if _elapsed > 6.0:
		queue_free()
		return

	_intensity = lerpf(_intensity, _target_intensity, minf(1.0, delta * 9.0))
	_spin = lerpf(_spin, _spin_target, minf(1.0, delta * 4.0))
	_vortex_mat.set_shader_parameter("intensity", _intensity)
	_vortex_mat.set_shader_parameter("spin", _spin)
	_vortex_mat.set_shader_parameter("core_boost", _core_boost)

	var pulse := sin(_elapsed * 2.1)
	_halo.scale = Vector2(3.5, 3.5) * (1.0 + 0.022 * pulse)
	if not _collapsed:
		_core.scale = Vector2(0.50, 0.50) * (1.0 + 0.055 * sin(_elapsed * 5.2))
	_ring_a.rotation += delta * (0.22 + _spin * 0.18)
	_ring_b.rotation -= delta * (0.15 + _spin * 0.12)
	_ring_a.scale = _ring_base_a * (1.0 + 0.012 * pulse)
	_ring_b.scale = _ring_base_b * (1.0 - 0.010 * pulse)
	_core_star.rotation += delta * 0.35

	if source != null and is_instance_valid(source):
		var src := source.position - position
		_wisps.position = src
		var dir := (-src).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.LEFT
		dir = (dir + dir.orthogonal() * 0.28).normalized()
		_wisps.direction = dir
	elif _wisps.emitting:
		_wisps.emitting = false

	if _collapsed:
		_flare.rotation = sin(_elapsed * 2.0) * 0.02


# ===================== 事件 =====================

func begin_pull() -> void:
	if _pull_started:
		return
	_pull_started = true
	_target_intensity = 1.02
	_spin_target = 1.45
	_wisps.emitting = true
	var tw := create_tween()
	tw.tween_property(_core_star, "modulate:a", 0.38, 0.35)


func begin_dissolve() -> void:
	if _dissolve_started:
		return
	_dissolve_started = true
	_target_intensity = 1.25
	_spin_target = 2.0
	_core_boost = 0.22
	_spawn_shockwave()
	var tw := create_tween()
	tw.tween_property(_core, "modulate:a", 1.0, 0.16)
	tw.parallel().tween_property(_core_star, "modulate:a", 0.62, 0.2)


func collapse() -> void:
	if _collapsed:
		return
	_collapsed = true
	_deadline = _elapsed + 1.15
	_wisps.emitting = false
	_target_intensity = 1.9
	_spin_target = 2.5
	_core_boost = 0.55

	_burst.restart()
	_burst.emitting = true

	# 柔软的收束光团，替代硬边放射线
	_collapse_glow.visible = true
	_collapse_glow.modulate = Color(0.68, 0.95, 1.0, 0.0)
	_collapse_glow.scale = Vector2(0.9, 0.9)
	var gt := create_tween()
	gt.tween_property(_collapse_glow, "modulate:a", 0.82, 0.07)
	gt.parallel().tween_property(_collapse_glow, "scale", Vector2(2.9, 2.9), 0.36) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	gt.tween_property(_collapse_glow, "modulate:a", 0.0, 0.32)

	_flare.visible = true
	_flare.modulate = Color(0.82, 0.98, 1.0, 0.0)
	_flare.scale = Vector2(0.8, 0.8)
	var ft := create_tween()
	ft.tween_property(_flare, "modulate:a", 0.85, 0.06)
	ft.parallel().tween_property(_flare, "scale", Vector2(1.35, 1.18), 0.4) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ft.tween_property(_flare, "modulate:a", 0.0, 0.36)

	var ct := create_tween()
	ct.tween_property(_core, "scale", Vector2(1.25, 1.25), 0.22) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ct.parallel().tween_property(_core, "modulate:a", 0.0, 0.4).set_delay(0.08)

	get_tree().create_timer(0.10).timeout.connect(
		func() -> void: _target_intensity = 0.0)

	var fade := create_tween()
	fade.tween_interval(0.55)
	fade.tween_property(_halo, "modulate:a", 0.0, 0.4)
	fade.tween_property(_ring_a, "modulate:a", 0.0, 0.4)
	fade.parallel().tween_property(_ring_b, "modulate:a", 0.0, 0.4)


# ===================== 场景层 =====================

func _build_field() -> void:
	var white := _white_texture()
	var side := radius * 2.35
	_vortex = Sprite2D.new()
	_vortex.texture = white
	_vortex.centered = true
	_vortex.scale = Vector2(side / 4.0, side / 4.0)
	_vortex.z_index = 1
	_vortex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vortex_mat = ShaderMaterial.new()
	_vortex_mat.shader = load("res://assets/shaders/title_vortex_field.gdshader")
	_vortex.material = _vortex_mat
	add_child(_vortex)

	_halo = _sprite(_dot_texture(), 1, Color(0.42, 0.86, 1.0, 0.0))
	_halo.scale = Vector2(3.5, 3.5)
	var ht := create_tween()
	ht.tween_property(_halo, "modulate:a", 0.28, 0.4)

	_core = _sprite(_dot_texture(), 5, Color(0.78, 1.0, 1.0, 0.0))
	_core.scale = Vector2(0.50, 0.50)
	var ct := create_tween()
	ct.tween_property(_core, "modulate:a", 0.6, 0.3)

	_core_star = _sprite(_star_texture(), 6, Color(0.75, 0.97, 1.0, 0.0))
	_core_star.scale = Vector2(0.42, 0.42)
	var st := create_tween()
	st.tween_property(_core_star, "modulate:a", 0.22, 0.4)

	_ring_a = _sprite(_ring_texture(), 1, Color(0.42, 0.88, 1.0, 0.0))
	_ring_base_a = Vector2.ONE * (radius * 2.55 / 256.0)
	_ring_a.scale = _ring_base_a
	var ra := create_tween()
	ra.tween_property(_ring_a, "modulate:a", 0.20, 0.45)

	_ring_b = _sprite(_ring_texture(), 1, Color(0.72, 0.96, 1.0, 0.0))
	_ring_base_b = Vector2.ONE * (radius * 1.95 / 256.0)
	_ring_b.scale = _ring_base_b
	_ring_b.rotation = 1.1
	var rb := create_tween()
	rb.tween_property(_ring_b, "modulate:a", 0.13, 0.6)

	_flare = _sprite(_flare_texture(), 9, Color(0.8, 0.98, 1.0, 0.0))
	_flare.scale = Vector2(radius * 3.1 / 512.0, radius * 1.2 / 128.0)
	_flare.visible = false

	_collapse_glow = _sprite(_dot_texture(), 9, Color(0.68, 0.95, 1.0, 0.0))
	_collapse_glow.scale = Vector2(0.9, 0.9)
	_collapse_glow.visible = false


func _sprite(tex: Texture2D, z: int, tint: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.z_index = z
	s.modulate = tint
	s.material = _additive
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(s)
	return s


# ===================== 粒子层 =====================

func _build_particles() -> void:
	_dust_slow = _particles(_dot_texture(), 120, 2.3, 1)
	_dust_slow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	_dust_slow.emission_ring_radius = radius * 1.02
	_dust_slow.emission_ring_inner_radius = radius * 0.48
	_dust_slow.direction = Vector2.RIGHT
	_dust_slow.spread = 180.0
	_dust_slow.initial_velocity_min = 2.0
	_dust_slow.initial_velocity_max = 18.0
	_dust_slow.radial_accel_min = -88.0
	_dust_slow.radial_accel_max = -148.0
	_dust_slow.tangential_accel_min = 38.0
	_dust_slow.tangential_accel_max = 92.0
	_dust_slow.damping_min = 4.0
	_dust_slow.damping_max = 12.0
	_dust_slow.scale_amount_min = 0.10
	_dust_slow.scale_amount_max = 0.22
	_dust_slow.scale_amount_curve = _curve([Vector2(0.0, 0.25), Vector2(0.22, 1.0), Vector2(1.0, 0.12)])
	_dust_slow.color_ramp = _gradient(
		PackedFloat32Array([0.0, 0.14, 0.7, 1.0]),
		PackedColorArray([
			Color(0.35, 0.76, 1.0, 0.0),
			Color(0.55, 0.94, 1.0, 0.38),
			Color(0.30, 0.68, 1.0, 0.20),
			Color(0.20, 0.45, 1.0, 0.0),
		]))
	_dust_slow.preprocess = 1.0
	_dust_slow.emitting = true

	_dust_fast = _particles(_star_texture(), 40, 1.2, 5)
	_dust_fast.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_dust_fast.emission_sphere_radius = radius * 0.92
	_dust_fast.direction = Vector2.LEFT
	_dust_fast.spread = 180.0
	_dust_fast.initial_velocity_min = 6.0
	_dust_fast.initial_velocity_max = 22.0
	_dust_fast.radial_accel_min = -330.0
	_dust_fast.radial_accel_max = -470.0
	_dust_fast.tangential_accel_min = 210.0
	_dust_fast.tangential_accel_max = 340.0
	_dust_fast.damping_min = 12.0
	_dust_fast.damping_max = 26.0
	_dust_fast.scale_amount_min = 0.10
	_dust_fast.scale_amount_max = 0.22
	_dust_fast.scale_amount_curve = _curve([Vector2(0.0, 0.18), Vector2(0.18, 1.0), Vector2(1.0, 0.0)])
	_dust_fast.color_ramp = _gradient(
		PackedFloat32Array([0.0, 0.10, 0.62, 1.0]),
		PackedColorArray([
			Color(0.75, 0.98, 1.0, 0.0),
			Color(0.85, 1.0, 1.0, 0.80),
			Color(0.45, 0.86, 1.0, 0.38),
			Color(0.30, 0.60, 1.0, 0.0),
		]))
	_dust_fast.preprocess = 0.6
	_dust_fast.emitting = true

	_wisps = _particles(_comet_texture(), 90, 0.82, 7)
	_wisps.emitting = false
	_wisps.local_coords = false
	_wisps.particle_flag_align_y = true
	_wisps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_wisps.emission_sphere_radius = 58.0
	_wisps.spread = 24.0
	_wisps.initial_velocity_min = 180.0
	_wisps.initial_velocity_max = 300.0
	_wisps.gravity = Vector2.ZERO
	_wisps.damping_min = 8.0
	_wisps.damping_max = 20.0
	_wisps.scale_amount_min = 0.15
	_wisps.scale_amount_max = 0.28
	_wisps.scale_amount_curve = _curve([Vector2(0.0, 0.35), Vector2(0.16, 1.0), Vector2(1.0, 0.12)])
	_wisps.color_ramp = _gradient(
		PackedFloat32Array([0.0, 0.12, 0.6, 1.0]),
		PackedColorArray([
			Color(0.45, 0.86, 1.0, 0.0),
			Color(0.78, 0.99, 1.0, 0.92),
			Color(0.50, 0.88, 1.0, 0.55),
			Color(0.35, 0.65, 1.0, 0.0),
		]))
	_wisps.preprocess = 0.0


func _build_burst_layers() -> void:
	_burst = _particles(_star_texture(), 52, 0.62, 8)
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	_burst.local_coords = false
	_burst.direction = Vector2.RIGHT
	_burst.spread = 180.0
	_burst.initial_velocity_min = 90.0
	_burst.initial_velocity_max = 290.0
	_burst.damping_min = 28.0
	_burst.damping_max = 82.0
	_burst.scale_amount_min = 0.16
	_burst.scale_amount_max = 0.34
	_burst.scale_amount_curve = _curve([Vector2(0.0, 1.0), Vector2(0.4, 0.8), Vector2(1.0, 0.0)])
	_burst.color_ramp = _gradient(
		PackedFloat32Array([0.0, 0.08, 0.55, 1.0]),
		PackedColorArray([
			Color(0.85, 1.0, 1.0, 0.95),
			Color(0.95, 1.0, 1.0, 1.0),
			Color(0.50, 0.90, 1.0, 0.55),
			Color(0.35, 0.65, 1.0, 0.0),
		]))
	_burst.preprocess = 0.0


func _particles(tex: Texture2D, amount: int, life: float, z: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.lifetime_randomness = 0.18
	p.randomness = 0.4
	p.local_coords = true
	p.z_index = z
	p.material = _additive
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(p)
	return p


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	c.bake_resolution = 24
	return c


func _gradient(offsets: PackedFloat32Array, colors: PackedColorArray) -> Gradient:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	return g


# ===================== 冲击波 =====================

func _spawn_shockwave() -> void:
	var origin := Vector2.ZERO
	if source != null and is_instance_valid(source):
		origin = source.position - position
	_spawn_wave(origin, 0.0, 2.15, 0.62, Color(0.62, 0.94, 1.0, 0.44))
	_spawn_wave(origin, 0.10, 1.65, 0.52, Color(0.92, 1.0, 1.0, 0.30))
	_spawn_wave_flash(origin)


func _spawn_wave(origin: Vector2, delay: float, end_scale: float,
		duration: float, tint: Color) -> void:
	var wave := Sprite2D.new()
	wave.texture = _ring_texture()
	wave.centered = true
	wave.position = origin
	wave.z_index = 8
	wave.material = _additive
	wave.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	wave.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	wave.scale = Vector2(0.22, 0.22)
	add_child(wave)
	var tw := wave.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(wave, "modulate:a", tint.a, 0.06)
	tw.parallel().tween_property(wave, "scale", Vector2(end_scale, end_scale), duration) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(wave, "modulate:a", 0.0, duration * 0.75)
	get_tree().create_timer(duration + delay + 0.2).timeout.connect(wave.queue_free)


func _spawn_wave_flash(origin: Vector2) -> void:
	var flash := Sprite2D.new()
	flash.texture = _dot_texture()
	flash.centered = true
	flash.position = origin
	flash.z_index = 8
	flash.material = _additive
	flash.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	flash.modulate = Color(0.8, 0.98, 1.0, 0.0)
	flash.scale = Vector2(0.18, 0.18)
	add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "modulate:a", 0.70, 0.05)
	tw.parallel().tween_property(flash, "scale", Vector2(1.25, 1.25), 0.30) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.26)
	get_tree().create_timer(0.65).timeout.connect(flash.queue_free)


# ===================== 程序化纹理 =====================

static func _white_texture() -> Texture2D:
	if _tex_cache.has("white"):
		return _tex_cache["white"]
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["white"] = tex
	return tex


static func _dot_texture() -> Texture2D:
	if _tex_cache.has("dot"):
		return _tex_cache["dot"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := exp(-d * d * 5.2) * 0.9 + exp(-d * d * 26.0) * 0.45
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["dot"] = tex
	return tex


static func _star_texture() -> Texture2D:
	if _tex_cache.has("star"):
		return _tex_cache["star"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var nx := (x - c) / c
			var ny := (y - c) / c
			var core := exp(-(nx * nx + ny * ny) * 9.0)
			var horizontal := exp(-abs(nx) * 16.0) * exp(-abs(ny) * 2.8)
			var vertical := exp(-abs(ny) * 16.0) * exp(-abs(nx) * 2.8)
			var diag := 0.30 * (exp(-abs(nx - ny) * 12.0) + exp(-abs(nx + ny) * 12.0)) \
				* exp(-(nx * nx + ny * ny) * 3.5)
			var a := clampf(core * 0.85 + horizontal * 0.72 + vertical * 0.72 + diag, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["star"] = tex
	return tex


static func _ring_texture() -> Texture2D:
	if _tex_cache.has("ring"):
		return _tex_cache["ring"]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var nx := (x - c) / c
			var ny := (y - c) / c
			var d := sqrt(nx * nx + ny * ny)
			var band_t := (d - 0.70) / 0.125
			var halo_t := (d - 0.70) / 0.32
			var band := exp(-band_t * band_t)
			var halo := exp(-halo_t * halo_t) * 0.16
			var arc := 0.70 + 0.30 * (0.5 + 0.5 * sin(atan2(ny, nx) * 3.0 + 0.7))
			var a := clampf((band * 0.72 + halo) * arc, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["ring"] = tex
	return tex


static func _comet_texture() -> Texture2D:
	if _tex_cache.has("comet"):
		return _tex_cache["comet"]
	var w := 96
	var h := 192
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	for y in h:
		var v := float(y) / float(h - 1)
		for x in w:
			var u := (x - cx) / cx
			var dv := v - 0.80
			var head := exp(-(u * u * 26.0 + dv * dv * 74.0))
			var t := clampf(v / 0.80, 0.0, 1.0)
			var width := 0.10 + 0.34 * t
			var wt := u / width
			var tail := exp(-wt * wt) * pow(t, 2.3) * 0.55
			var a := clampf(head + tail, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["comet"] = tex
	return tex


static func _flare_texture() -> Texture2D:
	if _tex_cache.has("flare"):
		return _tex_cache["flare"]
	var w := 512
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var nx := (x - cx) / cx
			var ny := (y - cy) / cy
			var sy := ny / 0.16
			var sx := nx / 0.05
			var streak := exp(-sy * sy) * exp(-abs(nx) * 2.6)
			var stem := exp(-sx * sx) * exp(-abs(ny) * 3.4)
			var core := exp(-(nx * nx * 42.0 + ny * ny * 42.0))
			var a := clampf(streak * 0.78 + stem * 0.42 + core * 0.7, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["flare"] = tex
	return tex


