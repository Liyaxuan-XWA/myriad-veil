extends Node2D
## 符箓的局内演出（2026-10-31）：
##   召唤符卡 → 在玩家面前悬停 → 激活 → 符卡化作元素飞向目标 → 落点生效。
## 真实伤害 / buff 由调用方通过 on_impact 回调在「效果落点」那一帧执行；
## 元素落点表现走 ArtDB.SKILL_FX 的 talisman_* 条目，不在本文件里另画一套。

const COLORS := {
	"metal": Color(1.00, 0.86, 0.42),
	"wood": Color(0.60, 0.94, 0.48),
	"water": Color(0.48, 0.86, 1.00),
	"fire": Color(1.00, 0.58, 0.16),
	"earth": Color(0.78, 0.62, 0.38),
	"wind": Color(0.62, 0.98, 0.82),
	"thunder": Color(0.86, 0.92, 1.00),
}
const FX_IDS := {
	"sword_qi": "talisman_jinfeng",
	"fireball": "talisman_huoqiu",
	"lightning": "talisman_yinlei",
	"root": "talisman_muling",
	"regen_hp": "talisman_shuihui",
	"speed_up": "talisman_fengji",
	"stone_body": "talisman_tushi",
}
const SELF_EFFECTS := ["regen_hp", "speed_up", "stone_body"]

var _caster: Node2D
var _target: Node2D
var _def: Dictionary
var _aim: Vector2
var _aim_offset := Vector2.ZERO
var _impact: Callable
var _effect := ""
var _element := ""
var _color := Color.WHITE
var _card: Sprite2D
var _glow: TextureRect
var _base_scale := Vector2.ONE


## 由玩家在 add_child 之后调用；caster 决定悬停位置，target 用于飞行途中跟随。
func setup(caster: Node2D, target: Node2D, def: Dictionary, aim: Vector2,
		on_impact: Callable) -> void:
	_caster = caster
	_target = target
	_def = def.duplicate(true)
	_aim = aim
	_impact = on_impact
	if is_instance_valid(_target):
		_aim_offset = _aim - _target.global_position
	var eff: Dictionary = def.get("battle_effect", {})
	_effect = String(eff.get("effect", ""))
	_element = String(eff.get("element", ""))
	_color = COLORS.get(_element, Color(0.90, 0.82, 0.62))
	_run()


func _is_self() -> bool:
	return _effect in SELF_EFFECTS


func _cast_dir() -> Vector2:
	if is_instance_valid(_target):
		var v := _target.global_position - _caster.global_position
		if v.length_squared() > 1.0:
			return v.normalized()
	var ad = _caster.get("attack_dir")
	if ad is Vector2 and (ad as Vector2).length_squared() > 0.001:
		return (ad as Vector2).normalized()
	return Vector2.RIGHT


func _live_aim() -> Vector2:
	if is_instance_valid(_target):
		return _target.global_position + _aim_offset
	return _aim


func _run() -> void:
	if not is_instance_valid(_caster):
		queue_free()
		return
	var dir := _cast_dir()
	var self_effect := _is_self()
	var hover := _caster.global_position + dir * (38.0 if self_effect else 54.0) \
		+ Vector2(0.0, -60.0)
	_spawn_card()
	global_position = _caster.global_position + Vector2(0.0, -42.0)
	_card.scale = _base_scale * 0.24
	_glow.modulate.a = 0.0

	# 1) 从手边浮到面前
	var intro := create_tween().set_parallel(true)
	intro.tween_property(self, "global_position", hover, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	intro.tween_property(_card, "scale", _base_scale, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(_card, "rotation", 0.12 if dir.x >= 0.0 else -0.12, 0.16) \
		.set_trans(Tween.TRANS_SINE)
	intro.tween_property(_glow, "modulate:a", 0.30, 0.16)
	await intro.finished

	# 2) 悬停蓄势：卡身轻浮，柔光呼吸
	var bob := create_tween().set_loops()
	bob.tween_property(_card, "position:y", _card.position.y - 5.0, 0.24) \
		.set_trans(Tween.TRANS_SINE)
	bob.tween_property(_card, "position:y", _card.position.y, 0.24) \
		.set_trans(Tween.TRANS_SINE)
	var breathe := create_tween().set_loops()
	breathe.tween_property(_glow, "modulate:a", 0.46, 0.22)
	breathe.tween_property(_glow, "modulate:a", 0.24, 0.22)
	await get_tree().create_timer(0.28).timeout
	bob.kill()
	breathe.kill()
	_glow.modulate.a = 0.30

	# 3) 激活：符卡亮一下、碎裂
	_activate_card()
	await get_tree().create_timer(0.08).timeout

	if self_effect:
		# 功能符：直接绕身生效
		if _impact.is_valid():
			_impact.call()
		var self_point := _caster.global_position + Vector2(0.0, -32.0)
		_play_element(self_point, dir)
		await get_tree().create_timer(1.05).timeout
		queue_free()
		return

	await _release_projectile(dir)
	await get_tree().create_timer(1.15).timeout
	queue_free()


func _spawn_card() -> void:
	var path := String(_def.get("card", ""))
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path)
	if tex == null:
		path = String(_def.get("icon", ""))
		if path != "" and ResourceLoader.exists(path):
			tex = load(path)
	if tex == null:
		tex = SkillFx.dot_texture()
	var target_h := 96.0 if tex.get_height() > tex.get_width() * 1.4 else 64.0
	var base := target_h / maxf(float(tex.get_height()), 1.0)
	_base_scale = Vector2(base, base)

	_glow = UIKit.glow_node(Vector2(250.0, 350.0), _color, 0.0)
	_glow.position = Vector2(-30.0, -34.0)
	_glow.z_index = 28
	add_child(_glow)

	_card = Sprite2D.new()
	_card.texture = tex
	_card.centered = true
	_card.scale = _base_scale
	_card.z_index = 30
	_card.position = Vector2.ZERO
	add_child(_card)

	var shadow := Sprite2D.new()
	shadow.texture = tex
	shadow.centered = true
	shadow.modulate = Color(0.0, 0.0, 0.0, 0.42)
	shadow.position = Vector2(5.0, 7.0)
	shadow.z_index = -1
	_card.add_child(shadow)

	var trail := SkillFx.make_particles(SkillFx.star_texture(), 10, 0.28, 2, true)
	trail.local_coords = false
	trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 6.0
	trail.direction = Vector2.LEFT
	trail.spread = 180.0
	trail.initial_velocity_min = 8.0
	trail.initial_velocity_max = 40.0
	trail.damping_min = 20.0
	trail.damping_max = 40.0
	trail.scale_amount_min = 0.05
	trail.scale_amount_max = 0.12
	trail.color_ramp = SkillFx.make_gradient(
		PackedFloat32Array([0.0, 0.2, 1.0]),
		PackedColorArray([
			Color(_color.r, _color.g, _color.b, 0.0),
			Color(_color.r, _color.g, _color.b, 0.55),
			Color(_color.r, _color.g, _color.b, 0.0),
		]))
	add_child(trail)
	trail.restart()
	trail.emitting = true


func _activate_card() -> void:
	var flash := Sprite2D.new()
	flash.texture = SkillFx.dot_texture()
	flash.centered = true
	flash.material = SkillFx.additive_material()
	flash.modulate = Color(_color.r, _color.g, _color.b, 0.0)
	flash.scale = Vector2(0.55, 0.55)
	flash.z_index = 31
	add_child(flash)
	var ft := flash.create_tween()
	ft.tween_property(flash, "modulate:a", 0.75, 0.05)
	ft.parallel().tween_property(flash, "scale", Vector2(1.8, 1.8), 0.20) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ft.tween_property(flash, "modulate:a", 0.0, 0.18)
	ft.tween_callback(flash.queue_free)
	_burst_card()


func _burst_card() -> void:
	if _card != null and is_instance_valid(_card):
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_card, "modulate:a", 0.0, 0.13)
		tw.tween_property(_card, "scale", _card.scale * 1.16, 0.13) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if _glow != null and is_instance_valid(_glow):
		var gt := create_tween().set_parallel(true)
		gt.tween_property(_glow, "modulate:a", 0.0, 0.20)
		gt.tween_property(_glow, "scale", Vector2(2.0, 2.0), 0.20) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


## 符卡激活后化成的元素飞行物。雷符不飞，直接在目标头顶落雷。
func _release_projectile(dir: Vector2) -> void:
	var start := global_position
	var end := _live_aim()
	if _effect == "lightning":
		await get_tree().create_timer(0.10).timeout
		_resolve_release(_live_aim(), dir)
		return
	var tex_path := ""
	var proj_size := 36.0
	var wait := 0.26
	var spin := false
	match _effect:
		"fireball":
			tex_path = "res://assets/effects/skills/tiger_orb.png"
			proj_size = 42.0
			wait = 0.26
		"sword_qi":
			tex_path = "res://assets/effects/skills/sword_light.png"
			proj_size = 58.0
			wait = 0.19
		"root":
			tex_path = "res://assets/effects/skills/qi_cloud_wisp.png"
			proj_size = 62.0
			wait = 0.28
			spin = true
	var tex: Texture2D = null
	if tex_path != "" and ResourceLoader.exists(tex_path):
		tex = load(tex_path)
	var host := get_parent()
	if host == null:
		_resolve_release(end, dir)
		return
	var proj := Node2D.new()
	proj.z_index = 31
	host.add_child(proj)
	proj.global_position = start
	var spr := Sprite2D.new()
	spr.texture = tex if tex != null else SkillFx.star_texture()
	spr.centered = true
	spr.material = SkillFx.additive_material()
	var s := proj_size / maxf(float(spr.texture.get_height()), 1.0)
	spr.scale = Vector2(s, s)
	spr.modulate = Color(_color.lerp(Color.WHITE, 0.18).r,
		_color.lerp(Color.WHITE, 0.18).g, _color.lerp(Color.WHITE, 0.18).b, 0.96)
	spr.rotation = dir.angle() if _effect != "fireball" else randf_range(-0.2, 0.2)
	proj.add_child(spr)
	if spin:
		var st := spr.create_tween().set_loops()
		st.tween_property(spr, "rotation", spr.rotation + TAU, 0.8)
	var glow := Sprite2D.new()
	glow.texture = SkillFx.dot_texture()
	glow.centered = true
	glow.material = SkillFx.additive_material()
	glow.modulate = Color(_color.r, _color.g, _color.b, 0.26)
	glow.scale = Vector2(0.9, 0.9)
	glow.z_index = -1
	proj.add_child(glow)
	var trail := SkillFx.make_particles(SkillFx.star_texture(), 16, 0.30, 0, true)
	trail.local_coords = false
	trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 8.0
	trail.direction = -dir
	trail.spread = 50.0
	trail.initial_velocity_min = 20.0
	trail.initial_velocity_max = 80.0
	trail.damping_min = 25.0
	trail.damping_max = 60.0
	trail.scale_amount_min = 0.06
	trail.scale_amount_max = 0.16
	trail.color_ramp = SkillFx.make_gradient(
		PackedFloat32Array([0.0, 0.2, 1.0]),
		PackedColorArray([
			Color(_color.r, _color.g, _color.b, 0.0),
			Color(_color.r, _color.g, _color.b, 0.75),
			Color(_color.r, _color.g, _color.b, 0.0),
		]))
	proj.add_child(trail)
	trail.restart()
	trail.emitting = true
	var travel := proj.create_tween()
	travel.tween_method(func(t: float) -> void:
		proj.global_position = start.lerp(_live_aim(), t), 0.0, 1.0, wait) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await travel.finished
	_resolve_release(proj.global_position, dir)
	proj.queue_free()


func _resolve_release(point: Vector2, dir: Vector2) -> void:
	if _impact.is_valid():
		_impact.call()
	_play_element(point, dir)


func _play_element(point: Vector2, dir: Vector2) -> void:
	var host := get_parent()
	if host == null:
		return
	var fx_id := String(FX_IDS.get(_effect, ""))
	if fx_id != "":
		SkillFx.play_at_point(host, fx_id, _fx_form(), dir, point, _caster)
	SkillFx.projectile_impact(host, point, _color)
	_spawn_landing_ring(host, point)


func _fx_form() -> Dictionary:
	match _effect:
		"sword_qi":
			return {"range": 72.0, "angle": 46.0}
		"fireball":
			return {"range": 80.0}
		"lightning":
			return {"range": 80.0, "hit_shape": MoveDB.SHAPE_CIRCLE}
		"root":
			return {"range": 64.0, "angle": 360.0, "width": 40.0}
		"regen_hp":
			return {"range": 90.0}
		"speed_up":
			return {"range": 100.0}
		"stone_body":
			return {"range": 90.0, "hit_shape": MoveDB.SHAPE_CIRCLE}
	return {"range": 80.0}


## 七张符共用的落点柔光环：给金属 / 火 / 木这类没有自带地面圈的落点一个明确范围
func _spawn_landing_ring(host: Node, point: Vector2) -> void:
	var holder := Node2D.new()
	holder.z_index = 1
	host.add_child(holder)
	holder.global_position = point
	var ring := Sprite2D.new()
	ring.texture = SkillFx.ring_texture()
	ring.centered = true
	ring.material = SkillFx.additive_material()
	ring.modulate = Color(_color.r, _color.g, _color.b, 0.0)
	ring.scale = Vector2(0.20, 0.20)
	ring.rotation = randf_range(-0.3, 0.3)
	holder.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 0.55, 0.06)
	tw.parallel().tween_property(ring, "scale", Vector2(0.58, 0.58), 0.34) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.24)
	holder.get_tree().create_timer(0.7).timeout.connect(holder.queue_free)
