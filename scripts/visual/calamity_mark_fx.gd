class_name CalamityMarkFx
extends Node2D
## 三灾痕读数（2026-10-31）：目标头顶三枚小印，风 / 火 / 雷各一枚。
## 亮 = 目标身上有对应灾痕，可按规则用克制属性引爆；熄灭 = 已消耗或过期。
## 只在未装备「三灾·灾身」（走灾劫连锁）时挂载，避免和玩家灾轮 HUD 抢读数。

const META := "calamity_mark_fx"
const PIP_GAP := 20.0
const FADE_SPEED := 7.0
const IDLE_EXIT := 0.35

var _target: Node2D
var _pips: Array[Sprite2D] = []
var _backs: Array[Sprite2D] = []
var _idle := 0.0
var _t := 0.0
var _closing := false


static func attach(target: Node2D) -> CalamityMarkFx:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var old = target.get_meta(META) if target.has_meta(META) else null
	if old is CalamityMarkFx and is_instance_valid(old) and not old.is_queued_for_deletion():
		old._idle = 0.0
		return old
	var fx := CalamityMarkFx.new()
	fx.name = "CalamityMarkFx"
	fx._target = target
	target.set_meta(META, fx)
	target.add_child(fx)
	return fx


func _ready() -> void:
	z_index = 68
	position = _anchor_pos()
	modulate.a = 0.0
	var ids: Array = SkillDB.CALAMITY_MARK_IDS
	for i in ids.size():
		var back := Sprite2D.new()
		back.texture = SkillFx.dot_texture()
		back.position = Vector2(0.0, (float(i) - 1.0) * PIP_GAP)
		back.scale = Vector2.ONE * 0.22
		back.modulate = Color(0.02, 0.03, 0.04, 0.60)
		add_child(back)
		_backs.append(back)
		var pip := Sprite2D.new()
		pip.texture = SkillFx.dot_texture()
		pip.material = SkillFx.additive_material()
		pip.position = back.position
		pip.scale = Vector2.ONE * 0.13
		pip.modulate = Color(1.0, 1.0, 1.0, 0.0)
		add_child(pip)
		_pips.append(pip)


func _process(delta: float) -> void:
	if _closing:
		return
	if _target == null or not is_instance_valid(_target) or _target.is_queued_for_deletion():
		_finish()
		return
	_t += delta
	var ids: Array = SkillDB.CALAMITY_MARK_IDS
	var active_count := 0
	for i in _pips.size():
		var id := String(ids[i])
		var active := _target.has_method("has_debuff") \
			and bool(_target.call("has_debuff", id))
		var col := DebuffDB.color(id)
		var pip := _pips[i]
		var back := _backs[i]
		var pulse := 0.82 + 0.18 * sin(_t * 5.0 + float(i) * 1.7)
		if active:
			active_count += 1
			pip.modulate = Color(col.r, col.g, col.b, pulse)
			pip.scale = Vector2.ONE * (0.17 + 0.015 * sin(_t * 5.0 + float(i)))
			back.modulate.a = 0.60
		else:
			pip.modulate = Color(col.r, col.g, col.b, 0.20)
			pip.scale = Vector2.ONE * 0.10
			back.modulate.a = 0.30
	if active_count > 0:
		_idle = 0.0
		modulate.a = move_toward(modulate.a, 1.0, delta * FADE_SPEED)
	else:
		_idle += delta
		modulate.a = move_toward(modulate.a, 0.0, delta * FADE_SPEED)
		if modulate.a <= 0.01 and _idle >= IDLE_EXIT:
			_finish()


## 挂在 BOSS 头侧偏下：避开头顶血条 / 阶段字，三枚竖排更易读。
## 侧别朝屏幕内侧选，BOSS 贴右墙时印记不会被裁出画面。
func _anchor_pos() -> Vector2:
	var top := -120.0
	if _target != null and is_instance_valid(_target) and _target.has_method("head_top_y"):
		top = float(_target.call("head_top_y"))
	var side := 1.0
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var p := players[0] as Node2D
		if p != null and is_instance_valid(p) \
				and _target != null and _target.global_position.x > p.global_position.x:
			side = -1.0
	return Vector2(118.0 * side, top + 26.0)


func _finish() -> void:
	if _closing:
		return
	_closing = true
	if _target != null and is_instance_valid(_target) and _target.has_meta(META):
		if _target.get_meta(META) == self:
			_target.remove_meta(META)
	queue_free()
