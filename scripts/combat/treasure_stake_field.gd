class_name TreasureStakeField
extends Node2D
## 禁步桩场地（2026-11-01）
##
## 先埋后触发：0.8 秒收缩圈 → 展开；展开瞬间挂一段较长的禁步，之后持续刷新。
## 「禁步」= 减速 + 禁闪 + 精力停止恢复，不含硬定身 —— 定身是木缚符的动词。
## 只影响施放者的敌对目标：玩家放的圈只管敌方，野修放的圈只管玩家阵营。
## 圈是死的，不会跟着施放者移动；持续时间到点自行淡出。

const SLOW_TICK := 0.25

var arm_time: float = 0.8
var duration: float = 4.0
var radius: float = 110.0
var initial_slow: float = 1.5
var slow_refresh: float = 0.6
var cast_by_player: bool = true
## 施放者本体。棋局里双方都是带 team_id 的 match_piece，
## 只靠 `cast_by_player` 分不出"谁的敌人"—— 两队核心放的圈会互相圈住。
## 为 null 时沿用旧的分派，保证既有调用点行为不变。
var caster: Node = null
var icon_path: String = ""

var _spawn_pos: Vector2 = Vector2.ZERO
var _armed: bool = false
var _t: float = 0.0
var _slow_tick: float = 0.0
var _ring_scale: float = 1.0
var _ring: Sprite2D = null
var _fill: Sprite2D = null
var _stake: Sprite2D = null
var _finished: bool = false


func setup(pos: Vector2, by_player: bool, p_radius: float, p_arm_time: float,
		p_duration: float, p_initial_slow: float, _p_slow_mult: float, p_slow_refresh: float,
		p_icon: String, p_caster: Node = null) -> void:
	_spawn_pos = pos
	cast_by_player = by_player
	caster = p_caster
	radius = maxf(30.0, p_radius)
	arm_time = maxf(0.1, p_arm_time)
	duration = maxf(0.5, p_duration)
	initial_slow = maxf(0.0, p_initial_slow)
	slow_refresh = maxf(0.2, p_slow_refresh)
	icon_path = p_icon
	# 战报：法宝场地自己成一行（归属走 caster）
	set_meta("report_tag", "法宝场地")


func _ready() -> void:
	global_position = _spawn_pos
	z_index = 2
	_ring_scale = radius / TreasureFx.SOFT_RING_RADIUS_PX

	_fill = Sprite2D.new()
	_fill.texture = TreasureFx.soft_disc_texture()
	_fill.centered = true
	_fill.scale = Vector2(_ring_scale, _ring_scale)
	_fill.modulate = Color(0.88, 0.64, 0.20, 0.04)
	_fill.z_index = -1
	add_child(_fill)

	_ring = Sprite2D.new()
	_ring.texture = TreasureFx.soft_ring_texture()
	_ring.centered = true
	_ring.scale = Vector2(_ring_scale * 1.25, _ring_scale * 1.25)
	_ring.modulate = Color(0.92, 0.70, 0.28, 0.20)
	add_child(_ring)

	if icon_path != "" and ResourceLoader.exists(icon_path):
		_stake = Sprite2D.new()
		_stake.texture = load(icon_path)
		_stake.centered = true
		# 钉在目标脚边而不是正下方：正中会被角色身体完整挡住，看不出是什么东西
		_stake.position = Vector2(28.0, -6.0)
		_stake.scale = Vector2(0.05, 0.05)
		_stake.modulate = Color(1.0, 1.0, 1.0, 0.92)
		_stake.z_index = 1
		add_child(_stake)
		var tw := create_tween()
		tw.tween_property(_stake, "scale", Vector2(0.28, 0.28), 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_stake, "rotation", -0.12, 0.22)


func tick(delta: float) -> void:
	if _finished:
		return
	_t += delta
	var total := arm_time + duration
	if _t >= total:
		_fade_and_free()
		return
	if not _armed:
		var k := clampf(_t / arm_time, 0.0, 1.0)
		var s := lerpf(1.25, 1.0, k)
		if _ring != null:
			_ring.scale = Vector2(_ring_scale * s, _ring_scale * s)
			_ring.modulate.a = lerpf(0.20, 0.58, k)
		if _fill != null:
			_fill.modulate.a = lerpf(0.04, 0.11, k)
		if k >= 1.0:
			_armed = true
			_arm()
		return

	_slow_tick -= delta
	if _slow_tick <= 0.0:
		_slow_tick = SLOW_TICK
		_apply_slow()

	var left := total - _t
	if left < 0.35:
		var fade := clampf(left / 0.35, 0.0, 1.0)
		if _ring != null:
			_ring.modulate.a = 0.58 * fade
		if _fill != null:
			_fill.modulate.a = 0.11 * fade
	else:
		var pulse := 0.5 + 0.5 * sin(_t * 4.2)
		if _ring != null:
			_ring.modulate.a = 0.50 + 0.10 * pulse


func _process(delta: float) -> void:
	tick(delta)


## 展开瞬间：圈内挂一段较长的禁步；之后由 _apply_slow 持续刷新
func _arm() -> void:
	for raw in _targets():
		var u := raw as Node
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "jinbu", initial_slow)


func _apply_slow() -> void:
	for raw in _targets():
		var u := raw as Node
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "jinbu", slow_refresh)


## 圈内敌对目标：玩家放的圈只圈非友军 BOSS；野修放的圈只圈玩家阵营
func _targets() -> Array:
	# 棋局：施放者是带队伍号的棋子 ⇒ 走统一入口按队伍筛。
	# 旧写法在这里恒空 —— 12 只棋子全是 is_ally=false，
	# `if group == "boss" and not is_ally_unit(u): continue` 把每一个都跳过了，
	# 于是四只大陆核心的禁步桩在棋盘上谁也圈不住（2026-11-05 审计发现）。
	if caster != null and is_instance_valid(caster) and BossBase.unit_team(caster) >= 0:
		var pieces: Array = []
		for raw in BossBase.hostile_units(caster):
			if not (raw is Node2D):
				continue
			if global_position.distance_to((raw as Node2D).global_position) > radius:
				continue
			pieces.append(raw)
		return pieces
	var out: Array = []
	_collect_group(out, "boss")
	if not cast_by_player:
		_collect_group(out, "player")
	return out


func _collect_group(out: Array, group: String) -> void:
	for raw in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(raw) or not raw is Node2D:
			continue
		var u := raw as Node2D
		if u == self or u == get_parent():
			continue
		if cast_by_player:
			if group != "boss":
				continue
			if BossBase.is_ally_unit(u):
				continue
		else:
			if group == "boss" and not BossBase.is_ally_unit(u):
				continue
		if u.has_method("is_dead") and bool(u.call("is_dead")):
			continue
		if global_position.distance_to(u.global_position) > radius:
			continue
		if not (u in out):
			out.append(u)


func _fade_and_free() -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	var tw := create_tween()
	if _ring != null:
		tw.tween_property(_ring, "modulate:a", 0.0, 0.28)
	if _fill != null:
		tw.parallel().tween_property(_fill, "modulate:a", 0.0, 0.28)
	if _stake != null:
		tw.parallel().tween_property(_stake, "modulate:a", 0.0, 0.28)
	tw.tween_callback(queue_free)
