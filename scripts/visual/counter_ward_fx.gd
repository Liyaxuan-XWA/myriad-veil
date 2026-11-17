class_name CounterWardFx
extends Node2D
## 纳势反击的蓄力护势：柔和金色罩体 + 环绕星尘，蓄得越久越亮。
## 由 SkillFx.play_counter_ward 创建，挂在玩家身上；玩家每帧喂蓄力进度，
## 释放/取消时 finish() 渐隐。不是硬边圆环：主体是柔光罩 + 漂浮光点。

var caster: Node2D
var cfg: Dictionary = {}

var _ratio := 0.0
var _hits := 0
var _last_hits := 0
var _dead := false
var _time := 0.0
var _sprite: Sprite2D
var _glow: Sprite2D
var _motes: CPUParticles2D


func setup(_form: Dictionary) -> void:
	z_index = 0
	position = _body_center()
	_sprite = Sprite2D.new()
	_sprite.texture = SkillFx.skill_texture("ward")
	_sprite.centered = true
	_sprite.material = SkillFx.additive_material()
	_sprite.modulate = Color(1.0, 0.82, 0.46, 0.0)
	_sprite.scale = Vector2(0.86, 0.86)
	_sprite.z_index = -1
	add_child(_sprite)
	_glow = Sprite2D.new()
	_glow.texture = SkillFx.dot_texture()
	_glow.centered = true
	_glow.material = SkillFx.additive_material()
	_glow.modulate = Color(0.95, 0.62, 0.22, 0.0)
	_glow.scale = Vector2(1.62, 1.62)
	_glow.z_index = -1
	add_child(_glow)
	_motes = CPUParticles2D.new()
	_motes.texture = SkillFx.dot_texture()
	_motes.amount = 20
	_motes.lifetime = 0.9
	_motes.lifetime_randomness = 0.3
	_motes.randomness = 0.5
	_motes.local_coords = true
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	_motes.emission_ring_radius = 58.0
	_motes.emission_ring_inner_radius = 38.0
	_motes.direction = Vector2.RIGHT
	_motes.spread = 180.0
	_motes.initial_velocity_min = 0.0
	_motes.initial_velocity_max = 18.0
	_motes.tangential_accel_min = 45.0
	_motes.tangential_accel_max = 110.0
	_motes.radial_accel_min = -28.0
	_motes.radial_accel_max = -8.0
	_motes.gravity = Vector2.ZERO
	_motes.damping_min = 4.0
	_motes.damping_max = 12.0
	_motes.scale_amount_min = 0.05
	_motes.scale_amount_max = 0.12
	_motes.scale_amount_curve = SkillFx.make_curve([Vector2(0.0, 0.4), Vector2(0.25, 1.0), Vector2(1.0, 0.0)])
	_motes.color_ramp = SkillFx.make_gradient(
		PackedFloat32Array([0.0, 0.2, 1.0]),
		PackedColorArray([
			Color(1.0, 0.86, 0.5, 0.0),
			Color(1.0, 0.9, 0.62, 0.55),
			Color(0.95, 0.55, 0.16, 0.0),
		]))
	_motes.material = SkillFx.additive_material()
	_motes.z_index = 2
	_motes.one_shot = false
	_motes.emitting = true
	add_child(_motes)
	set_process(true)


func set_charge(ratio: float, hits: int) -> void:
	if _dead:
		return
	_ratio = clampf(ratio, 0.0, 1.0)
	_hits = maxi(hits, _hits)
	if hits > _last_hits:
		_hit_pulse()
	_last_hits = hits


func _hit_pulse() -> void:
	var flash := Sprite2D.new()
	flash.texture = SkillFx.star_texture()
	flash.centered = true
	flash.material = SkillFx.additive_material()
	flash.modulate = Color(1.0, 0.9, 0.6, 0.75)
	flash.scale = Vector2(0.35, 0.35)
	flash.z_index = 3
	add_child(flash)
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(1.15, 1.15), 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.24)
	get_tree().create_timer(0.3).timeout.connect(flash.queue_free)


func _process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	rotation += delta * (0.10 + _ratio * 0.28)
	var target_a := 0.06 + 0.10 * _ratio + 0.015 * mini(_hits, 5)
	_sprite.modulate.a = lerpf(_sprite.modulate.a, target_a, minf(1.0, delta * 6.0))
	var pulse := 1.0 + 0.025 * sin(_time * 4.2) + 0.07 * _ratio
	_sprite.scale = Vector2(0.86, 0.86) * pulse
	_glow.modulate.a = lerpf(_glow.modulate.a,
		0.18 + 0.13 * _ratio + 0.022 * mini(_hits, 5), minf(1.0, delta * 5.0))


func finish() -> void:
	if _dead:
		return
	_dead = true
	_motes.emitting = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.24)
	tw.tween_property(_glow, "modulate:a", 0.0, 0.24)
	get_tree().create_timer(0.32).timeout.connect(queue_free)


func _body_center() -> Vector2:
	if is_instance_valid(caster) and caster.has_method("_body_center"):
		var v = caster.call("_body_center")
		if v is Vector2:
			return v
	return Vector2(0.0, -30.0)
