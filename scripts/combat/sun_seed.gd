class_name SunSeed
extends Node2D
## 天火种（离照 · 逐日·天火，2026-10-29）
##
## 场上唯一可被双方争夺的火种：
##   FREE   落在地上，0.6 秒抢锁后可被玩家 / 离照拾取；
##   HELD   跟着持有者，每 1.6 秒叠 1 层日冕（最多 3 层）；满层 3 秒后爆裂；
##   GONE   被投出/引爆/爆裂后消失，由离照脚本按重生计时再落一枚。
##
## 火种只管「持有权 / 层数 / 计时 / 表现」，伤害由双方的招式脚本按自己的公式结算。

signal picked(unit: Node2D)
signal stolen(unit: Node2D, from: Node2D)
signal dropped(world_pos: Vector2)
signal consumed

enum State { FREE, HELD, GONE }

const PICKUP_RADIUS := 46.0
const CLAIM_LOCK := 0.6
const STACK_TIME := 1.6
const MAX_STACKS := 3
## 火种上限：肉鸽爬塔「层数上限 +N」改这里；主模式恒等于 MAX_STACKS
func max_stacks() -> int:
	if RogueRun.active:
		return RogueRun.cap("sun_max")
	return MAX_STACKS
const UNSTABLE_TIME := 3.0
const BOSS_BURST_PCT := 0.06
const PLAYER_BURST_PCT := 0.12
const FOLLOW_LERP := 14.0
const BOSS_STOP_RADIUS := 46.0

var state: int = State.FREE
var holder: Node2D = null
## 上一次飞行的出发持有者：太极盘据此只接「离照投出的火种」，不干扰玩家自己的投日
var last_holder: Node2D = null
var stacks: int = 0
## 离照本体（用于重生 / 通知）；玩家自凝的火种为 null。
var source_boss: Node2D = null

var _claim_lock: float = CLAIM_LOCK
var _stack_timer: float = 0.0
var _unstable_left: float = 0.0
var _time: float = 0.0
var _flying := false
var _flight_tw: Tween = null
var _orb: Sprite2D
var _corona: Sprite2D
var _ring: Sprite2D
var _embers: CPUParticles2D


func _ready() -> void:
	add_to_group("sun_seed")
	z_index = 4
	_build_visuals()
	_apply_stack_visual()


func _build_visuals() -> void:
	var orb_tex := SkillFx.skill_texture("sun_orb")
	if orb_tex == null:
		orb_tex = SkillFx.dot_texture()
	_orb = Sprite2D.new()
	_orb.texture = orb_tex
	_orb.material = SkillFx.additive_material()
	_orb.scale = Vector2(0.20, 0.20)
	_orb.modulate = Color(1.0, 0.86, 0.52, 0.95)
	_orb.z_index = 4
	add_child(_orb)

	_corona = Sprite2D.new()
	_corona.texture = orb_tex
	_corona.material = SkillFx.additive_material()
	_corona.scale = Vector2(0.44, 0.44)
	_corona.modulate = Color(1.0, 0.42, 0.14, 0.28)
	_corona.z_index = 3
	add_child(_corona)

	_ring = Sprite2D.new()
	_ring.texture = SkillFx.ring_texture()
	_ring.material = SkillFx.additive_material()
	_ring.scale = Vector2(0.36, 0.36)
	_ring.modulate = Color(1.0, 0.62, 0.26, 0.58)
	_ring.z_index = 1
	add_child(_ring)

	_embers = SkillFx.make_particles(SkillFx.dot_texture(), 20, 1.1, 4, true)
	_embers.emitting = true
	_embers.amount = 20
	_embers.lifetime = 1.1
	_embers.explosiveness = 0.0
	_embers.randomness = 0.75
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 20.0
	_embers.direction = Vector2.UP
	_embers.spread = 65.0
	_embers.gravity = Vector2(0.0, -18.0)
	_embers.initial_velocity_min = 10.0
	_embers.initial_velocity_max = 42.0
	_embers.scale_amount_min = 0.04
	_embers.scale_amount_max = 0.12
	_embers.color = Color(1.0, 0.62, 0.24, 0.8)
	add_child(_embers)


func _physics_process(delta: float) -> void:
	_time += delta
	match state:
		State.FREE:
			_claim_lock = maxf(0.0, _claim_lock - delta)
			_tick_free()
		State.HELD:
			_tick_held(delta)
	_animate(delta)


func _tick_free() -> void:
	if _claim_lock > 0.0:
		return
	var best: Node2D = null
	var best_d := PICKUP_RADIUS
	var p := _player()
	if _can_hold(p):
		var d := global_position.distance_to(p.global_position)
		if d <= best_d:
			best = p
			best_d = d
	for raw in get_tree().get_nodes_in_group("boss"):
		var b := raw as Node2D
		if not _can_hold(b):
			continue
		var d := global_position.distance_to(b.global_position)
		if d < best_d:
			best = b
			best_d = d
	if best != null:
		pickup(best)


func _tick_held(delta: float) -> void:
	if not _can_hold(holder):
		var old := holder
		drop(global_position)
		if old != null:
			_notify_lost(old)
		return
	# 跟随持有者：火种浮在身侧/胸前，不跟角色翻转
	var off := Vector2(0.0, -46.0)
	if holder.is_in_group("boss"):
		off = Vector2(-38.0, -44.0)
	var target := holder.global_position + off
	global_position = global_position.lerp(target, clampf(delta * FOLLOW_LERP, 0.0, 1.0))
	if stacks < max_stacks():
		_stack_timer += delta
		# 肉鸽「引火」：叠层速度按倍率加快（主模式 RogueRun.stat 恒 0）
		var need_time := STACK_TIME / (1.0 + maxf(0.0, RogueRun.stat("sun_gain_pct")) / 100.0)
		if _stack_timer >= need_time:
			_stack_timer -= need_time
			stacks = mini(max_stacks(), stacks + 1)
			_apply_stack_visual()
			_emit_ring_burst()
			if stacks >= max_stacks():
				_unstable_left = UNSTABLE_TIME
				_notify_full(holder)
				_show_unstable_warning()
	else:
		_unstable_left = maxf(0.0, _unstable_left - delta)
		if _unstable_left <= 0.0:
			_burst_on_holder()


## 飞出：从当前位置沿抛物线落到 world_pos；飞行中不可拾取，落地后保留 0.6 秒抢锁。
## ignore_boss：本次飞行的出发持有者（从它手里掀出来时忽略它，避免原地撞停）。
func fly_to(world_pos: Vector2, duration: float, arc_height: float = 32.0,
		ignore_boss: Node = null) -> void:
	if state == State.GONE:
		return
	_stop_flight()
	var old_holder := holder
	last_holder = old_holder
	var from := global_position
	# 从 BOSS 手里/身上出发时，从朝落点的一侧边缘起飞，别从身体里穿过去
	if ignore_boss != null and old_holder == ignore_boss \
			and is_instance_valid(ignore_boss) and ignore_boss is Node2D:
		var src := ignore_boss as Node2D
		var out := world_pos - src.global_position
		if out.length_squared() > 1.0 \
				and src.global_position.distance_to(from) <= BOSS_STOP_RADIUS + 30.0:
			from = src.global_position + out.normalized() * (BOSS_STOP_RADIUS + 2.0)
			global_position = from
	holder = null
	holder = null
	state = State.FREE
	if old_holder != null:
		_notify_lost(old_holder)
	if stacks >= max_stacks():
		_unstable_left = UNSTABLE_TIME
	_claim_lock = maxf(0.0, duration) + CLAIM_LOCK
	_flying = true
	_flight_tw = create_tween()
	_flight_tw.tween_method(
		_flight_step.bind(from, world_pos, arc_height, ignore_boss),
		0.0, 1.0, maxf(duration, 0.01))
	_flight_tw.tween_callback(_land_from_flight.bind(world_pos))


func _flight_step(t: float, from: Vector2, to: Vector2, arc_height: float,
		ignore_boss: Node) -> void:
	if not _flying or state == State.GONE:
		return
	# 碰撞按地面投影判定：抛物线抬高的只是视觉，不能从 BOSS 头顶掠过去
	var ground := from.lerp(to, t)
	var p := ground
	p.y -= arc_height * sin(PI * t)
	for raw in get_tree().get_nodes_in_group("boss"):
		var b := raw as Node2D
		if b == null or not is_instance_valid(b) or b == ignore_boss:
			continue
		if b.global_position.distance_to(ground) <= BOSS_STOP_RADIUS:
			global_position = ground
			_stop_flight()
			_claim_lock = CLAIM_LOCK
			_emit_ring_burst()
			return
	global_position = p


func _land_from_flight(world_pos: Vector2) -> void:
	if state == State.GONE:
		return
	global_position = world_pos
	_flying = false
	_flight_tw = null
	_emit_ring_burst()


func _stop_flight() -> void:
	if _flight_tw != null and _flight_tw.is_valid():
		_flight_tw.kill()
	_flight_tw = null
	_flying = false


func _animate(delta: float) -> void:
	var bob := sin(_time * 3.4) * 3.0
	if _orb != null:
		_orb.position.y = bob
		_orb.rotation += delta * (0.9 if state != State.HELD else 1.6)
	if _corona != null:
		_corona.position.y = bob
		_corona.scale = Vector2(0.44, 0.44) * (1.0 + 0.06 * sin(_time * 4.1))
		_corona.rotation -= delta * 0.35
	if _ring != null:
		_ring.scale = Vector2(0.36, 0.36) * (1.0 + 0.05 * sin(_time * 3.0))
		_ring.rotation += delta * 0.55
	if state == State.HELD and stacks >= max_stacks():
		var pulse := 0.5 + 0.5 * sin(_time * 12.0)
		if _orb != null:
			_orb.modulate = Color(1.0, 0.62 + 0.18 * pulse, 0.32, 1.0)
		if _corona != null:
			_corona.modulate = Color(1.0, 0.30, 0.08, 0.32 + 0.20 * pulse)


func _apply_stack_visual() -> void:
	var k := 1.0 + float(stacks) * 0.16
	if _orb != null:
		_orb.scale = Vector2(0.20, 0.20) * k
	if _corona != null:
		_corona.scale = Vector2(0.44, 0.44) * k
	if _ring != null:
		_ring.modulate.a = 0.52 + float(stacks) * 0.12


func _emit_ring_burst() -> void:
	if not is_inside_tree():
		return
	var spr := Sprite2D.new()
	spr.texture = SkillFx.ring_texture()
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2(0.20, 0.20)
	spr.modulate = Color(1.0, 0.70, 0.30, 0.65)
	spr.z_index = 3
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", Vector2(0.85, 0.85), 0.32)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.32)
	tw.tween_callback(spr.queue_free)


func _show_unstable_warning() -> void:
	if holder == null or not is_instance_valid(holder):
		return
	if holder.has_method("_show_float_text"):
		holder.call("_show_float_text", "烈阳！火种将爆", Color(1.0, 0.52, 0.22))
	elif holder.has_method("show_windup_line"):
		holder.call("show_windup_line", "天火种 · 烈阳", 0.6, 16, 220.0,
			Color(1.0, 0.52, 0.22), -186.0)


func _notify_full(unit: Node) -> void:
	if unit != null and is_instance_valid(unit) and unit.has_method("on_sun_seed_full"):
		unit.call("on_sun_seed_full", self)


func _notify_lost(unit: Node) -> void:
	if unit != null and is_instance_valid(unit) and unit.has_method("on_sun_seed_lost"):
		unit.call("on_sun_seed_lost", self)


func _burst_on_holder() -> void:
	var unit := holder
	SkillFx.sun_burst_at(get_parent(), global_position, 150.0, 0.85)
	if unit != null and is_instance_valid(unit) and unit.has_method("on_sun_seed_burst"):
		unit.call("on_sun_seed_burst", self)
		_notify_lost(unit)
	consume()


func _can_hold(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit.is_in_group("player"):
		var dead = unit.get("is_dead")
		if dead is bool and dead:
			return false
		return true
	# 敌方 BOSS 与「法宝召唤出来的友军 BOSS」都要能拾火：友军入的是 ally_summon 组
	# 而不是 boss 组，只查 boss 会让火正令召来的离照永远捡不起火种（2026-11-02 用户报）。
	# 真正的门槛是 uses_sun_seed()，所以虎妖 / 刀客这类不会玩火的召唤物仍然拿不到。
	if unit.is_in_group("boss") or unit.is_in_group("ally_summon"):
		if unit.has_method("uses_sun_seed") and unit.call("uses_sun_seed") == true:
			var st = unit.get("state")
			return st == null or int(st) != 6
	return false


func _player() -> Node2D:
	var arr := get_tree().get_nodes_in_group("player")
	for raw in arr:
		var p := raw as Node2D
		if p != null:
			var dead = p.get("is_dead")
			if not (dead is bool) or not dead:
				return p
	return null


## 玩家侧日轮凝种：先给一小段抢锁，避免刚生成就被对手顺手捡走
func set_claim_lock(seconds: float) -> void:
	_claim_lock = maxf(_claim_lock, seconds)


## 消耗一层日冕（满日冕引燃炸到敌人时由玩家调用）；返回是否真的扣掉一层
func consume_layer() -> bool:
	if stacks <= 0:
		return false
	stacks -= 1
	_unstable_left = 0.0
	_apply_stack_visual()
	return true


## 拾取（自由火种）
func pickup(unit: Node2D) -> void:
	if state != State.FREE or not _can_hold(unit):
		return
	_stop_flight()
	holder = unit
	state = State.HELD
	_claim_lock = 0.0
	_stack_timer = 0.0
	if stacks >= max_stacks():
		_unstable_left = UNSTABLE_TIME
	picked.emit(unit)
	_notify_gained(unit)


## 夺火：从另一名持有者手里抢过来（层数保留）
func steal_by(unit: Node2D) -> void:
	if not _can_hold(unit) or state == State.GONE:
		return
	_stop_flight()
	var from := holder
	if from == unit:
		return
	if from != null:
		_notify_lost(from)
	holder = unit
	state = State.HELD
	_claim_lock = 0.0
	_stack_timer = 0.0
	if stacks >= max_stacks():
		_unstable_left = UNSTABLE_TIME
	if from != null:
		stolen.emit(unit, from)
	else:
		picked.emit(unit)
	_notify_gained(unit)


## 打落 / 主动放下：火种落地，层数保留，3 秒缓冲
func drop(world_pos: Vector2) -> void:
	_stop_flight()
	var from := holder
	holder = null
	state = State.FREE
	global_position = world_pos
	_claim_lock = CLAIM_LOCK
	_stack_timer = 0.0
	if stacks >= max_stacks():
		_unstable_left = UNSTABLE_TIME
	dropped.emit(world_pos)
	if from != null:
		_notify_lost(from)


## 被投日 / 日蚀消耗：直接消失
func consume() -> void:
	if state == State.GONE:
		return
	_stop_flight()
	var from := holder
	holder = null
	state = State.GONE
	visible = false
	set_physics_process(false)
	if from != null:
		_notify_lost(from)
	consumed.emit()
	queue_free()


func _notify_gained(unit: Node) -> void:
	if unit != null and is_instance_valid(unit) and unit.has_method("on_sun_seed_gained"):
		unit.call("on_sun_seed_gained", self)


func is_held_by(unit: Node) -> bool:
	return state == State.HELD and holder == unit


## 日轮阵把自由火种往阵心拉（不改变抢锁，只挪位置）
func pull_toward(world_pos: Vector2, step: float) -> void:
	if state != State.FREE or _flying:
		return
	global_position = global_position.move_toward(world_pos, maxf(0.0, step))


func is_free() -> bool:
	return state == State.FREE
