class_name StunFx
extends Node2D
## 眩晕头顶表现：三颗金色小星绕头旋转 + 一圈柔光底衬。
## 挂在**受击者本体**上随目标移动；目标 is_stunned() 变假或时长到点自动收尾。
## 玩家 / BOSS / 野怪共用 —— 入口是 Player.apply_debuff("stun") 与 BossBase.stun_for()。

const META := "stun_fx"
const COLOR := Color(1.0, 0.86, 0.35, 1.0)
const CORE := Color(1.0, 0.97, 0.82, 1.0)
const STAR_COUNT := 3
const FADE_IN := 0.07
const FADE_OUT := 0.16

var _target: Node2D
var _left: float = 0.0
var _t: float = 0.0
var _star_scale: float = 0.26
var _rx: float = 24.0
var _ry: float = 9.0
var _halo: Sprite2D
var _stars: Array[Sprite2D] = []
var _closing: bool = false


## 挂到目标身上；重复施加只延长/刷新，不会叠出第二套星
static func attach(target: Node2D, seconds: float) -> StunFx:
	if target == null or not is_instance_valid(target) or seconds <= 0.0:
		return null
	if not target.is_inside_tree():
		return null
	var old = target.get_meta(META) if target.has_meta(META) else null
	if old is StunFx and is_instance_valid(old) and not old.is_queued_for_deletion():
		old.refresh(seconds)
		return old
	var fx := StunFx.new()
	fx.name = "StunFx"
	fx._target = target
	fx._left = seconds
	target.set_meta(META, fx)
	target.add_child(fx)
	return fx


func refresh(seconds: float) -> void:
	_left = maxf(_left, seconds)


func _ready() -> void:
	z_index = 70
	position = Vector2(0.0, _anchor_y())
	# 目标越高（BOSS / 巨兽）星环越大，但设上下限，避免小怪头上顶一圈巨光
	var span := clampf(absf(position.y) / 100.0, 1.0, 2.2)
	_star_scale = 0.26 * span
	_rx = 95.0 * _star_scale
	_ry = 34.0 * _star_scale

	_halo = Sprite2D.new()
	_halo.texture = SkillFx.dot_texture()
	_halo.material = SkillFx.additive_material()
	_halo.modulate = Color(COLOR.r, COLOR.g, COLOR.b, 0.0)
	_halo.scale = Vector2.ONE * _star_scale * 1.8
	add_child(_halo)
	for i in STAR_COUNT:
		var star := Sprite2D.new()
		star.texture = SkillFx.star_texture()
		star.material = SkillFx.additive_material()
		star.modulate = CORE
		star.scale = Vector2.ONE * _star_scale
		add_child(star)
		_stars.append(star)


func _anchor_y() -> float:
	if _target != null and is_instance_valid(_target) and _target.has_method("stun_fx_anchor_y"):
		return float(_target.call("stun_fx_anchor_y"))
	return -100.0


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _target.is_queued_for_deletion():
		_finish()
		return
	_left -= delta
	if _left <= 0.0 or not _still_stunned():
		_finish()
		return
	_t += delta
	var alpha := clampf(_t / FADE_IN, 0.0, 1.0) * clampf(_left / FADE_OUT, 0.0, 1.0)
	modulate.a = alpha
	var spin := _t * 5.0
	for i in _stars.size():
		var ang := spin + TAU * float(i) / float(STAR_COUNT)
		var depth := 0.5 + 0.5 * sin(ang)
		var star := _stars[i]
		star.position = Vector2(cos(ang) * _rx, sin(ang) * _ry)
		star.scale = Vector2.ONE * _star_scale * (0.82 + 0.24 * depth)
		star.modulate.a = 0.55 + 0.45 * depth
	if _halo != null and is_instance_valid(_halo):
		_halo.modulate.a = 0.24 * alpha
		_halo.scale = Vector2.ONE * _star_scale * (1.8 + 0.08 * sin(_t * 4.0))


func _still_stunned() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if _target.has_method("is_stunned"):
		return bool(_target.call("is_stunned"))
	return true


func _finish() -> void:
	if _closing:
		return
	_closing = true
	if _target != null and is_instance_valid(_target) \
			and _target.has_meta(META) and _target.get_meta(META) == self:
		_target.remove_meta(META)
	queue_free()
