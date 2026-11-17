class_name DomainBoss02C
extends BossBase
## 冲和界第 3 位 —— 太虚气君（气环 · 化劲）
##
## 机制：身周最多 3 枚**气环**。
##   · 聚气：引气 / 缩地 / 吐纳各凝 1 枚；
##   · 花气：冲气花 1 枚加长加痛；气爆一次引爆全部；
##   · 化劲：三环齐时起手，2.2 秒内受伤 -40%，把 60% 存下来（上限 140），
##     结束时连本带利放一道气浪（物理近战，可弹反 / 可躲）。
## 弱点：化劲时停手就只是拖延；吐纳是最大的输出窗（打疼它能打断）。
## 数值与设计见 docs/太虚气君BOSS完整资料.md；招式数据全在 MoveDB。

const F_GATHER := "form_qi_gather"
const F_WAVE := "form_qi_wave"
const F_SPIN := "form_qi_spin"
const F_LOCK := "form_qi_lock"
const F_WARD := "form_qi_ward"
const F_STEP := "form_qi_step"
const F_BURST := "form_qi_burst"
const F_BREATH := "form_qi_breath"
const SCORED: Array = [F_GATHER, F_WAVE, F_SPIN, F_LOCK, F_WARD, F_STEP, F_BURST, F_BREATH]

const MAX_QI := 3
const COOLDOWNS := {
	F_GATHER: 3.5, F_WAVE: 5.0, F_SPIN: 6.0, F_LOCK: 8.5,
	F_WARD: 14.0, F_STEP: 6.0, F_BURST: 18.0, F_BREATH: 16.0,
}

enum ExtraState { WARD = 100, CHANNEL = 101, STEP_DASH = 102 }

var _qi: int = 0
var _ring_nodes: Array = []
var _cools: Dictionary = {}
var _recent: Array = []
var _decide_wait: float = 0.0
## 环身气：气环绕体，贴脸会被擦伤（气环本身也是威胁，不只是资源）
var _ring_touch_cd: float = 0.0
## 最近受击量（化劲要不要起手，看玩家是不是真的在打它）
var _recent_damage: float = 0.0
var _phase_two: bool = false
# 化劲
var _ward_left: float = 0.0
var _ward_stored: float = 0.0
var _ward_cap: float = 140.0
var _ward_store: float = 0.60
var _ward_release_coeff: float = 1.20
var _ward_release_radius: float = 260.0
var _ward_dome: Node2D = null
# 吐纳
var _channel_left: float = 0.0
var _channel_damage: float = 0.0
var _channel_break: float = 0.08
var _channel_fx: Node2D = null
# 缩地
var _step_dir: Vector2 = Vector2.RIGHT
var _step_from: Vector2 = Vector2.ZERO
## 二阶段：化劲结束后气海不散，留下 3 秒气域（持续伤害 + 滞气）
var _field_left: float = 0.0
var _field_tick: float = 0.0
var _field_pos: Vector2 = Vector2.ZERO


func _setup() -> void:
	boss_id = "boss_02_c"
	_qi = 0
	_ring_nodes.clear()
	_cools.clear()
	_recent.clear()


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_rings(delta)
	_tick_qi_field(delta)
	if state == ExtraState.WARD:
		_tick_ward(delta)
		return
	if state == ExtraState.CHANNEL:
		_tick_channel(delta)
		return
	if state == ExtraState.STEP_DASH:
		_tick_step(delta)
		return
	super._physics_process(delta)


func _tick_cooldowns(delta: float) -> void:
	_decide_wait = maxf(0.0, _decide_wait - delta)
	_recent_damage = maxf(0.0, _recent_damage - 18.0 * delta)
	_ring_touch_cd = maxf(0.0, _ring_touch_cd - delta)
	for k in _cools.keys():
		_cools[k] = maxf(0.0, float(_cools[k]) - delta)


## 三枚气环绕着身周转：点亮 = 现有气环，暗 = 空槽
func _tick_rings(delta: float) -> void:
	if _ring_nodes.is_empty():
		for i in MAX_QI:
			var spr := Sprite2D.new()
			spr.texture = load(ArtDB.QI_RING_TEX)
			spr.centered = true
			spr.scale = Vector2(0.34, 0.34)
			spr.z_index = 3
			spr.visible = false
			add_child(spr)
			_ring_nodes.append(spr)
	var t := float(Time.get_ticks_msec()) * 0.001
	# 浮空：整幅立绘轻微上下浮动 + 左右微摆（没有骨骼时的最低限度呼吸感）
	var vis := get_node_or_null("Visual") as Node2D
	if vis != null:
		vis.position.y = -2.0 + sin(t * 2.2) * 3.0
		vis.rotation = sin(t * 1.1) * 0.018
	for i in _ring_nodes.size():
		var spr: Sprite2D = _ring_nodes[i]
		var ang := t * 1.1 + TAU * float(i) / float(MAX_QI)
		# 轨道压在身体中段（原来偏上 52px，站下半身像挨不到环）
		spr.position = Vector2(cos(ang) * 76.0, sin(ang) * 34.0 - 18.0)
		spr.rotation += delta * 1.4
		var on := i < _qi
		spr.visible = on
		if on:
			spr.modulate = Color(0.60, 0.88, 1.0, 0.92)
	# 环身气：有环且玩家贴身 → 每 1.2 秒擦一下（0.30×，附带 0.8 秒滞气）
	if _qi > 0 and _ring_touch_cd <= 0.0 and target != null and is_instance_valid(target):
		# 判定按**本体边缘**量：站在下半身（甚至贴着袍摆）也算贴身，不再只认圆心 92
		if edge_distance_to((target as Node2D).global_position) <= 44.0:
			_ring_touch_cd = 1.2
			deal_damage_to(target, attack_power * 0.30 * (1.25 if phase == 2 else 1.0),
				"elemental", "")
			_debuff(target, "qi_stagnation", 0.8)
			QiFx.pulse_rings(self, _qi)


func _add_qi(n: int) -> void:
	var before := _qi
	_qi = clampi(_qi + n, 0, MAX_QI)
	if _qi != before:
		QiFx.pulse_rings(self, _qi)


func _qi_color() -> Color:
	return Color(0.56, 0.86, 1.0, 1.0)


# ===================== 选招 =====================

func _on_chase_reached(_dist: float) -> void:
	_choose()


func _choose() -> void:
	if state != BossState.IDLE and state != BossState.CHASE:
		return
	if is_skill_locked():
		return
	if _decide_wait > 0.0:
		return
	_decide_wait = 0.3
	# 1. 三环齐：玩家正在打它才化劲；不打就花一环出气浪，不站着挨看
	if _qi >= MAX_QI and _ready_cd(F_WARD) and (_recent_damage > 15.0 or _dist() <= 340.0):
		_begin(F_WARD, 0.0)
		return
	if _qi >= MAX_QI and _ready_cd(F_WARD):
		_begin(F_WAVE, 0.0)
		return
	# 1.4 已有两环且化劲就绪、玩家在近处 → 一定先补到三环（抱气起势）
	if _qi == 2 and _ready_cd(F_WARD) and _dist() <= 340.0 and _ready_cd(F_GATHER):
		_begin(F_GATHER, 0.0)
		return
	# 1.5 玩家在压它 → 攒环准备化劲（被打得越狠越会先抱气）
	if _recent_damage > 20.0 and _qi < 2 and _ready_cd(F_GATHER) and randf() < 0.35:
		_begin(F_GATHER, 0.0)
		return
	# 2. 残血且没满环 → 吐纳（会被打断的输出窗）
	if _hp_ratio() <= 0.45 and _qi < MAX_QI and _ready_cd(F_BREATH) and randf() < 0.7:
		_begin(F_BREATH, 0.0)
		return
	# 3. 没环才补气（有环优先打；缩地也会凝环，别把出手全花在抱气上）
	if _qi == 0 and _ready_cd(F_GATHER) and randf() < 0.5:
		_begin(F_GATHER, 0.0)
		return
	# 3.5 玩家在中远距离且环不满 → 缩地贴过去，顺手凝一枚
	if _dist() > 260.0 and _qi < MAX_QI and _ready_cd(F_STEP) and randf() < 0.5:
		_begin(F_STEP, 0.0)
		return
	# 4. 二阶段且环多 → 气爆
	if _phase_two and _qi >= 2 and _ready_cd(F_BURST):
		_begin(F_BURST, 0.0)
		return
	# 5. 评分
	var best := ""
	var best_score := -999.0
	for sid in SCORED:
		if not _usable(String(sid)):
			continue
		if not _in_reach(String(sid)):
			continue
		var combo := 0.0
		var last := String(_recent[0]) if not _recent.is_empty() else ""
		if last == F_GATHER and (sid == F_WAVE or sid == F_LOCK):
			combo = 1.4
		elif last == F_STEP and sid == F_SPIN:
			combo = 1.6
		elif last == F_SPIN and sid == F_WAVE:
			combo = 1.0
		var sc := _score(String(sid)) + randf() * 1.0 + combo - _repeat_penalty(String(sid))
		if sc > best_score:
			best_score = sc
			best = String(sid)
	if best == "":
		state = BossState.CHASE
		return
	_begin(best, 0.0)


func _begin(sid: String, _arg: float = 0.0) -> void:
	if is_skill_locked():
		return
	_current_skill = sid
	state = BossState.WINDUP
	var b := MoveDB.resolve_boss(sid)
	state_timer = maxf(0.2, float(b.get("windup", 0.7)))
	_play_form_anim(sid, state_timer + 0.15)
	if target != null and is_instance_valid(target):
		_set_facing(((target as Node2D).global_position - global_position).normalized())
	# 技能名在**前摇第一帧**出现，只报招名，不带应对提示；
	# 化劲与吐纳的招名再延长到持续阶段，跟住整段动作。
	var fname := String(b.get("form_name", ""))
	if sid == F_WARD:
		show_skill_line(fname,
			state_timer + float(b.get("qi_ward_time", 2.2)), 22, 240.0,
			BossBase.skill_name_color(String(b.get("attack_kind", ""))), -178.0)
	elif sid == F_BREATH:
		show_skill_line(fname,
			state_timer + float(b.get("channel_time", 1.2)), 20, 220.0,
			BossBase.skill_name_color(String(b.get("attack_kind", ""))), -178.0)
	elif fname != "":
		show_skill_line(fname, state_timer, 17, 210.0,
			BossBase.skill_name_color(String(b.get("attack_kind", ""))), -178.0)


func _usable(sid: String) -> bool:
	if not _ready_cd(sid):
		return false
	match sid:
		F_WARD:
			return _qi >= MAX_QI
		F_WAVE, F_BURST:
			return true
		F_GATHER:
			return _qi < MAX_QI
		F_BREATH:
			return _qi < MAX_QI
	return true


func _ready_cd(sid: String) -> bool:
	return float(_cools.get(sid, 0.0)) <= 0.0


func _in_reach(sid: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var d := _dist()
	match sid:
		F_WAVE:
			return d <= 560.0
		F_SPIN:
			return d <= 190.0
		F_LOCK:
			return d <= 250.0
		F_BURST:
			return d <= 300.0
		F_STEP:
			return d <= 480.0
	return true


func _score(sid: String) -> float:
	var d := _dist()
	match sid:
		F_WAVE:
			return 2.8 - absf(d - 300.0) / 260.0
		F_SPIN:
			return 3.4 - absf(d - 90.0) / 110.0
		F_LOCK:
			return 2.6 - absf(d - 160.0) / 160.0
		F_STEP:
			# 缩地是「贴远」的手段：中远距离分最高，近距离让位给回旋/冲气
			return 3.2 - absf(d - 330.0) / 200.0
		F_GATHER:
			return 0.8
		F_BURST:
			return 2.2
	return 0.6


func _repeat_penalty(sid: String) -> float:
	if _recent.size() >= 2 and String(_recent[0]) == sid and String(_recent[1]) == sid:
		return 99.0
	if _recent.size() >= 1 and String(_recent[0]) == sid:
		return 2.0
	return 0.0


func _record(sid: String) -> void:
	_recent.push_front(sid)
	if _recent.size() > 3:
		_recent.resize(3)
	_cools[sid] = float(COOLDOWNS.get(sid, 6.0))


# ===================== 出招 =====================

var _current_skill: String = ""


func _fire_skill() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	var b := MoveDB.resolve_boss(_current_skill)
	if b.is_empty():
		_finish_skill()
		return
	match _current_skill:
		F_GATHER:
			_cast_gather(b)
		F_WAVE:
			_cast_wave(b)
		F_SPIN:
			_cast_spin(b)
		F_LOCK:
			_cast_lock(b)
		F_WARD:
			_cast_ward(b)
		F_STEP:
			_cast_step(b)
		F_BURST:
			_cast_burst(b)
		F_BREATH:
			_cast_breath(b)
		_:
			_finish_skill()


func _finish_skill() -> void:
	_record(_current_skill)
	_current_skill = ""
	state = BossState.RECOVER
	state_timer = 0.5


func _cast_gather(b: Dictionary) -> void:
	_add_qi(1)
	_fx(b, F_GATHER)
	_finish_skill()


func _cast_wave(b: Dictionary) -> void:
	var spent := 0
	if _qi > 0:
		_qi -= 1
		spent = 1
	_qi = clampi(_qi, 0, MAX_QI)
	var coeff := float(b.get("damage_coeff", 1.05)) + float(b.get("qi_bonus_coeff", 0.35)) * float(spent)
	var reach := float(b.get("range", 460.0)) + float(b.get("qi_bonus_range", 90.0)) * float(spent)
	var dir := facing
	if target != null and is_instance_valid(target):
		dir = ((target as Node2D).global_position - global_position).normalized()
	_set_facing(dir)
	var a := global_position
	var end := a + dir * reach
	var dmg := attack_power * coeff * (1.25 if phase == 2 else 1.0)
	for u in attack_units():
		if u is Node2D and _point_segment_distance((u as Node2D).global_position, a, end) <= 50.0:
			deal_damage_to(u, dmg, "elemental", "")
	_fx(b, F_WAVE)
	_finish_skill()


func _cast_spin(b: Dictionary) -> void:
	var hit := _hit_all_in_form(F_SPIN)
	var kb := float(b.get("knockback", 320.0))
	if hit:
		for u in attack_units():
			if u is Node2D and (u as Node2D).global_position.distance_to(global_position) <= 168.0:
				if u.has_method("take_knockback"):
					var dir := ((u as Node2D).global_position - global_position).normalized()
					u.call("take_knockback", dir * kb)
	_fx(b, F_SPIN)
	_finish_skill()


func _cast_lock(b: Dictionary) -> void:
	_hit_all_in_form(F_LOCK)
	_fx(b, F_LOCK)
	_finish_skill()


func _cast_ward(b: Dictionary) -> void:
	if _qi < MAX_QI:
		_finish_skill()
		return
	_qi = 0
	_ward_stored = 0.0
	_ward_cap = float(b.get("qi_ward_cap", 140.0))
	_ward_store = float(b.get("qi_ward_store", 0.60))
	_ward_release_coeff = float(b.get("qi_release_coeff", 1.20))
	_ward_release_radius = float(b.get("qi_release_radius", 260.0))
	_ward_left = float(b.get("qi_ward_time", 2.2))
	state = ExtraState.WARD
	_ward_dome = QiFx.play_ward(get_parent(), self, _ward_left)


func _tick_ward(delta: float) -> void:
	_ward_left -= delta
	if _ward_left > 0.0:
		return
	_ward_left = 0.0
	var dmg := attack_power * _ward_release_coeff * (1.25 if phase == 2 else 1.0) + _ward_stored
	var radius := _ward_release_radius
	var hit_any := false
	for u in attack_units():
		if u is Node2D and (u as Node2D).global_position.distance_to(global_position) <= radius:
			if deal_damage_to(u, dmg, "physical_melee", ""):
				hit_any = true
	QiFx.play_release(get_parent(), global_position, radius, hit_any)
	if _phase_two:
		_field_left = 3.0
		_field_tick = 0.0
		_field_pos = global_position
		QiFx.attach_field(get_parent(), _field_pos, 260.0, 3.0)
	if is_instance_valid(_ward_dome):
		_ward_dome.queue_free()
	_ward_dome = null
	_record(F_WARD)
	_current_skill = ""
	state = BossState.RECOVER
	state_timer = 0.65


## 化劲期间受伤减 40%，把 60% 存下来（上限 140）
## 二阶段气海：化劲之后原地留 3 秒气域，每 0.5 秒擦伤 + 滞气
func _tick_qi_field(delta: float) -> void:
	if _field_left <= 0.0:
		return
	_field_left = maxf(0.0, _field_left - delta)
	_field_tick -= delta
	if _field_tick <= 0.0:
		_field_tick = 0.5
		for u in attack_units():
			if not (u is Node2D):
				continue
			if (u as Node2D).global_position.distance_to(_field_pos) <= 260.0:
				deal_damage_to(u, attack_power * 0.20 * (1.25 if phase == 2 else 1.0),
					"elemental", "")
				_debuff(u, "qi_stagnation", 0.6)
	if _field_left <= 0.0:
		pass


func damage_taken_multiplier(_damage_kind: String) -> float:
	if state == ExtraState.WARD:
		return 0.60
	return 1.0


func after_damage_taken(amount: float) -> void:
	_recent_damage = minf(400.0, _recent_damage + amount)
	if state == ExtraState.WARD:
		_ward_stored = minf(_ward_cap, _ward_stored + amount * _ward_store)
	elif state == ExtraState.CHANNEL:
		_channel_damage += amount


func _cast_step(b: Dictionary) -> void:
	var dest := global_position
	if target != null and is_instance_valid(target):
		dest = (target as Node2D).global_position
	var dv := dest - global_position
	_step_dir = dv.normalized() if dv.length() > 1.0 else facing
	_set_facing(_step_dir)
	_step_from = global_position
	var dest_est := global_position + _step_dir * 198.0
	QiFx.play_cloud_step(get_parent(), _step_from, dest_est, 0.24)
	var vis := get_node_or_null("Visual")
	if vis != null:
		(vis as CanvasItem).modulate.a = 0.0
	state = ExtraState.STEP_DASH
	state_timer = 0.26


func _tick_step(delta: float) -> void:
	velocity = _step_dir * 760.0
	state_timer -= delta
	move_and_slide()
	_clamp_to_arena()
	_update_skin_motion()
	if state_timer > 0.0:
		return
	velocity = Vector2.ZERO
	_hit_all_in_form(F_STEP)
	var vis2 := get_node_or_null("Visual")
	if vis2 != null:
		(vis2 as CanvasItem).modulate.a = 1.0
	_finish_skill()


func _cast_burst(b: Dictionary) -> void:
	var rings := _qi
	_qi = 0
	var coeff := float(b.get("damage_coeff", 1.0)) + float(b.get("qi_per_coeff", 0.60)) * float(rings)
	var dmg := attack_power * coeff * (1.25 if phase == 2 else 1.0)
	var radius := float(b.get("range", 240.0))
	for u in attack_units():
		if u is Node2D and (u as Node2D).global_position.distance_to(global_position) <= radius:
			deal_damage_to(u, dmg, "elemental", "")
	_fx(b, F_BURST)
	_finish_skill()


func _cast_breath(b: Dictionary) -> void:
	_channel_damage = 0.0
	_channel_break = float(b.get("channel_break_damage", 0.08))
	_channel_left = float(b.get("channel_time", 1.2))
	state = ExtraState.CHANNEL
	_channel_fx = QiFx.play_breath(get_parent(), self, _channel_left)


func _tick_channel(delta: float) -> void:
	_channel_left -= delta
	if _channel_damage >= max_hp * _channel_break:
		# 被打断：没有回复、没有气环，进僵直（输出窗）
		if is_instance_valid(_channel_fx):
			_channel_fx.queue_free()
		_channel_fx = null
		show_windup_line("吐纳被打断！", 0.8, 18, 200.0, Color(0.98, 0.72, 0.40), -170.0)
		stagger_for(0.9)
		_record(F_BREATH)
		_current_skill = ""
		return
	if _channel_left > 0.0:
		return
	var healed := apply_heal(max_hp * 0.10)
	if is_instance_valid(_channel_fx):
		_channel_fx.queue_free()
	_channel_fx = null
	QiFx.play_heal(get_parent(), global_position, healed)
	_finish_skill()


# ===================== 通用 =====================

func _hit_all_in_form(form_id: String) -> bool:
	var b := MoveDB.resolve_boss(form_id)
	if b.is_empty():
		return false
	var dmg := MoveDB.boss_damage(form_id, attack_power, phase)
	var kind := String(b.get("attack_kind", "physical_melee"))
	var elem := String(b.get("damage_element", ""))
	var reach := float(b.get("range", 120.0))
	var half := deg_to_rad(float(b.get("angle", 90.0)) * 0.5)
	var hit := false
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - global_position
		var d := to_u.length()
		if d > reach + 18.0:
			continue
		if b.get("hit_shape", MoveDB.SHAPE_FAN) == MoveDB.SHAPE_FAN and d > 1.0:
			if facing.normalized().dot(to_u / d) < cos(half):
				continue
		if deal_damage_to(u, dmg, kind, elem):
			_apply_form_debuff(u, b)
			hit = true
	return hit


## 气君八式统一走 SkillFx 的成熟管线（Shader 弧 / 粒子 / 激波 / 震屏），
## 不再用那套只有圆环的 QiFx
func _fx(b: Dictionary, sid: String) -> void:
	SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(sid)), b, facing)


func _debuff(unit: Node, id: String, duration: float, quiet: bool = true) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("apply_debuff"):
		return
	if unit.is_in_group("player"):
		unit.call("apply_debuff", id, duration, quiet)
	else:
		unit.call("apply_debuff", id, duration)


func _apply_form_debuff(unit: Node, b: Dictionary) -> void:
	var did := String(b.get("debuff_on_hit", ""))
	if did == "":
		return
	_debuff(unit, did, float(b.get("debuff_time", 3.0)))


func _dist() -> float:
	return _distance_to_target()


func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _hp_ratio() -> float:
	return current_hp / maxf(max_hp, 1.0)


func _on_phase_two() -> void:
	_phase_two = true
	show_windup_line("气海倒卷 · 化劲之后，气海不散！", 1.1, 22, 240.0, _qi_color(), -190.0)


func _fire_attack() -> void:
	_fire_skill()


func _exit_tree() -> void:
	if is_instance_valid(_ward_dome):
		_ward_dome.queue_free()
	if is_instance_valid(_channel_fx):
		_channel_fx.queue_free()
