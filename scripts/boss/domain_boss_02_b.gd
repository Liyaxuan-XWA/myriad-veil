class_name DomainBoss02B
extends BossBase
## 冲和界第 2 位 —— 定阵先生（阵旗 · 连线）
##
## 机制：最多 5 面**三色阵旗**（攻·朱砂 / 困·墨 / 守·石青），旗打三次才倒、不会自然消失。
##   · 攻旗：150px 内自动轰击，命中叠「阵伤」
##   · 困旗：90px 内锁步（移速 -40% + 禁闪避），零伤害
##   · 守旗：任意存活 → BOSS 受伤 -50%；凑齐三同色还各有成套杀招
##   · 布点：插旗·定星 / 用线：引阵·朱弦 / 卷阵·收旗 / 封阵·四象
##   · 不依赖旗：扫阵·横天 / 踏阵·走罡 / 垒旗·镇岳 / 解阵·雷落（二阶段）
## 第一战只用现有物理 / 法术 / 弹反 / 闪避即可应对：拔旗、走位、读插旗点。
## 数值与设计见 docs/定阵先生BOSS完整资料.md；招式数据全在 MoveDB。

const SKILL_PLANT := "form_array_plant"
const SKILL_LINE := "form_array_line"
const SKILL_PULL := "form_array_pull"
const SKILL_SEAL := "form_array_seal"
const SKILL_SWEEP := "form_array_sweep"
const SKILL_STEP := "form_array_step"
const SKILL_PILE := "form_array_pile"
const SKILL_BURST := "form_array_burst"

const SCORED: Array = [SKILL_PLANT, SKILL_LINE, SKILL_PULL, SKILL_SEAL,
	SKILL_SWEEP, SKILL_STEP, SKILL_PILE, SKILL_BURST]

const MAX_FLAGS := 5
const KIND_ATTACK := ArrayFlag.Kind.ATTACK
const KIND_BIND := ArrayFlag.Kind.BIND
const KIND_GUARD := ArrayFlag.Kind.GUARD
const KINDS: Array = [KIND_ATTACK, KIND_BIND, KIND_GUARD]
## 封阵固定要 4 面（四象），上限涨到 5 也不变
const FLAG_RANGE := 330.0
const LINE_HALF_WIDTH := 22.0
## 五旗阵（2026-10-29 用户定）：五旗成环后，区域内使用者 +30% 攻/防，
## 对手 -10% 攻；每秒雷击 0.6×，每次扣 10 阵力（隐藏池 100），耗尽撤旗。
const ZONE_ENERGY_MAX := 100.0
const ZONE_ENERGY_COST := 10.0
const ZONE_LIGHTNING_INTERVAL := 1.0
const ZONE_LIGHTNING_COEF := 0.6
const ZONE_ATTACK_BUFF := 1.30
const ZONE_DEFENSE_DIV := 1.30
const ZONE_ENEMY_ATTACK_MULT := 0.90

## 攻旗自动轰击（用户 2026-10-28 定）
const ATTACK_FLAG_RADIUS := 150.0
const ATTACK_FLAG_INTERVAL := 2.6
const ATTACK_FLAG_WARN := 0.5
const ATTACK_FLAG_COEF := 0.45
const ATTACK_FLAG_HIT_RADIUS := 58.0
const ATTACK_STACK_MAX := 3
const ATTACK_STACK_CLEAR := 4.0
## 困旗锁步
const BIND_FLAG_RADIUS := 90.0
## 守旗：任意一面存活 → BOSS 受伤减半；破后 8 秒不补
const GUARD_REDUCTION := 0.50
const GUARD_REPLANT_LOCK := 8.0
## 三色成套（5 面旗最多凑一套）
const FORMATION_COOLDOWN := 9.0
const FORMATION_ATTACK_COEF := 0.80
const FORMATION_ATTACK_RADIUS := 72.0

const COOLDOWNS := {
	SKILL_PLANT: 5.0, SKILL_LINE: 7.0, SKILL_PULL: 8.0, SKILL_SEAL: 15.0,
	SKILL_SWEEP: 3.2, SKILL_STEP: 7.0, SKILL_PILE: 10.0, SKILL_BURST: 17.0,
}

enum ExtraState { STEP_DASH = 100, SEAL_FIELD = 101, FORMATION = 102 }

var _flags: Array = []
var _line_visuals: Array = []
var _line_barrier: ArrayLineBarrier = null
var _zone_fill: Polygon2D = null
var _zone_energy := ZONE_ENERGY_MAX
var _zone_timer := 0.0
var _zone_complete := false
var _zone_attack_mult := 1.0
var _zone_defense_mult := 1.0
var _zone_affected_units: Array = []
var _cools: Dictionary = {}
var _recent: Array = []
var _plant_wait: float = 0.0
## 选招决策节流：_choose 每帧都会被 CHASE 调一次，不节流的话概率门槛等于"第一帧就中"
var _decide_wait: float = 0.0
# 封阵/解阵的延时结算
var _seal_ticks: int = 0
var _seal_timer: float = 0.0
var _seal_center: Vector2 = Vector2.ZERO
var _seal_kind: int = KIND_ATTACK
var _seal_guard: bool = false
## 守牢：10 秒减伤；记录成阵的旗，任一旗被破立即结束
var _seal_guard_left: float = 0.0
var _seal_guard_flags: Array = []
# 插旗预告（前摇 0.6 秒内先亮同色阵纹）
var _pending_plant_pos: Vector2 = Vector2.ZERO
var _pending_plant_kind: int = KIND_ATTACK
var _plant_mark: Sprite2D = null
# 攻旗轰击 / 阵伤 / 困锁 / 守旗补位锁
var _strikes: Array = []
var _flag_cd: Dictionary = {}
var _wound_stacks: int = 0
var _wound_clear: float = 0.0
var _guard_lock: float = 0.0
var _guard_prev: int = 0
# 成套
var _formation_cd: float = 0.0
var _hp_emit_timer: float = 0.5
var _form_kind: int = -1
var _form_t: float = 0.0
var _form_pos: Vector2 = Vector2.ZERO
var _form_marks: Array = []
var _form_strikes: int = 0
# 常驻可见环（守旗护罩 / 成套）
var _guard_aura: Sprite2D = null
var _form_aura: Sprite2D = null


func _setup() -> void:
	boss_id = "boss_02_b"
	_flags.clear()
	_cools.clear()
	_recent.clear()
	_strikes.clear()
	_flag_cd.clear()
	_wound_stacks = 0
	_wound_clear = 0.0
	_guard_lock = 0.0
	_guard_prev = 0
	_formation_cd = 0.0
	_form_kind = -1
	_seal_kind = KIND_ATTACK
	_seal_guard = false
	_seal_guard_left = 0.0
	_seal_guard_flags.clear()
	_zone_energy = ZONE_ENERGY_MAX
	_zone_timer = 0.0
	_zone_complete = false
	_zone_attack_mult = 1.0
	_zone_defense_mult = 1.0
	set_zone_attack_mult("self", 1.0)


## 旗是挂在**父节点**下的独立节点：BOSS 本身退场（含阵旗令召唤到期）时要把自己的旗带走，
## 否则召唤结束后会留下永久的无主红旗
func _exit_tree() -> void:
	_clear_zone_effects()
	for f in _flags:
		if is_instance_valid(f):
			f.queue_free()
	_flags.clear()
	if _line_barrier != null and is_instance_valid(_line_barrier):
		_line_barrier.clear()


# ===================== 主循环 =====================

func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_flags(delta)
	if _plant_wait > 0.0:
		_plant_wait = maxf(0.0, _plant_wait - delta)
	if state == ExtraState.SEAL_FIELD:
		_tick_seal(delta)
		return
	if state == ExtraState.STEP_DASH:
		_tick_step(delta)
		return
	if state == ExtraState.FORMATION:
		_tick_formation(delta)
		return
	super._physics_process(delta)


func _tick_cooldowns(delta: float) -> void:
	_decide_wait = maxf(0.0, _decide_wait - delta)
	_formation_cd = maxf(0.0, _formation_cd - delta)
	_guard_lock = maxf(0.0, _guard_lock - delta)
	for k in _cools.keys():
		_cools[k] = maxf(0.0, float(_cools[k]) - delta)
	for k in _flag_cd.keys():
		_flag_cd[k] = maxf(0.0, float(_flag_cd[k]) - delta)


## 每帧：同步数组 + 阵线 + 三色被动（攻轰击 / 困锁步 / 守减伤）+ 阵线接触
func _tick_flags(delta: float) -> void:
	_flags = _flags.filter(func(f): return is_instance_valid(f) and not bool(f.get("_dead")))
	_sync_line_visuals()
	_tick_seal_guard(delta)
	_tick_zone(delta)
	_tick_guard_state(delta)
	_tick_attack_flags(delta)
	_tick_bind_flags()
	_tick_strikes(delta)
	_tick_auras(delta)


func _kind_counts() -> Dictionary:
	var c := {KIND_ATTACK: 0, KIND_BIND: 0, KIND_GUARD: 0}
	for f in _flags:
		if is_instance_valid(f):
			var k := int(f.get("kind"))
			c[k] = int(c.get(k, 0)) + 1
	return c


func _guard_count() -> int:
	return int(_kind_counts().get(KIND_GUARD, 0))


func _hp_ratio() -> float:
	return current_hp / maxf(max_hp, 1.0)


## 守旗：任意存活 → 减伤；刚被玩家打掉 → 8 秒内不再补；三守成套 → 70% + 每秒 1% 回血
func _tick_guard_state(delta: float) -> void:
	var gc := _guard_count()
	if _guard_prev > 0 and gc == 0:
		_guard_lock = GUARD_REPLANT_LOCK
	_guard_prev = gc
	if _formation_kind() == KIND_GUARD and not is_dead:
		# 常驻回复也吃治疗乘区（蚀 = 只剩 10%）；这里保持原来的节流 emit，不逐帧发信号
		current_hp = minf(max_hp, current_hp + max_hp * 0.01 * delta * debuff_heal_mult())
		_hp_emit_timer -= delta
		if _hp_emit_timer <= 0.0:
			_hp_emit_timer = 0.5
			health_changed.emit(current_hp, max_hp)
			_update_head_hp_bar()


## 攻旗：玩家站进 150px → 每 2.6 秒落一道预警剑气；命中叠「阵伤」，离开 4 秒清空
func _tick_attack_flags(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var tp: Vector2 = (target as Node2D).global_position
	var in_range := false
	for f in _flags:
		if int(f.get("kind")) != KIND_ATTACK:
			continue
		if (f as Node2D).global_position.distance_to(tp) > ATTACK_FLAG_RADIUS:
			continue
		in_range = true
		var key: int = int((f as Node).get_instance_id())
		if float(_flag_cd.get(key, 0.0)) <= 0.0:
			_flag_cd[key] = ATTACK_FLAG_INTERVAL
			_schedule_strike(tp)
	if in_range:
		_wound_clear = 0.0
	elif _wound_stacks > 0:
		_wound_clear += delta
		if _wound_clear >= ATTACK_STACK_CLEAR:
			_clear_wound()


func _schedule_strike(pos: Vector2) -> void:
	_strikes.append({"pos": pos, "t": ATTACK_FLAG_WARN})
	_spawn_mark(ArtDB.ARRAY_FLAG_WARN_TEX, pos, ATTACK_FLAG_HIT_RADIUS,
		ATTACK_FLAG_WARN, Color(1, 1, 1, 0.9))


func _tick_strikes(delta: float) -> void:
	if _strikes.is_empty():
		return
	for s in _strikes.duplicate():
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) > 0.0:
			continue
		_strikes.erase(s)
		var pos: Vector2 = s["pos"]
		for u in attack_units():
			if not (u is Node2D):
				continue
			if (u as Node2D).global_position.distance_to(pos) > ATTACK_FLAG_HIT_RADIUS:
				continue
			deal_damage_to(u, attack_power * ATTACK_FLAG_COEF * (1.25 if phase == 2 else 1.0),
				"elemental", "fire")
			_add_wound(u)
		ArrayFx.play_bombard(get_parent(), pos)


## 统一施加 debuff：玩家侧支持 quiet（不刷飘字），BOSS 侧只有两参 ——
## 召唤成友军时会拿同一套招去打敌方 BOSS，参数对不上会直接报错
func _debuff(unit: Node, id: String, duration: float, quiet: bool = true) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("apply_debuff"):
		return
	if unit.is_in_group("player"):
		unit.call("apply_debuff", id, duration, quiet)
	else:
		unit.call("apply_debuff", id, duration)


func _add_wound(unit: Node) -> void:
	if not unit.has_method("apply_debuff"):
		return
	_wound_stacks = mini(_wound_stacks + 1, ATTACK_STACK_MAX)
	for i in 3:
		var id := "array_wound_%d" % (i + 1)
		if unit.has_method("clear_debuff"):
			unit.call("clear_debuff", id)
		elif unit.has_method("remove_debuff"):
			unit.call("remove_debuff", id)
	_debuff(unit, "array_wound_%d" % _wound_stacks, 6.0)


func _clear_wound() -> void:
	_wound_stacks = 0
	var u: Node = target
	if u == null or not is_instance_valid(u):
		return
	for i in 3:
		var id := "array_wound_%d" % (i + 1)
		if u.has_method("clear_debuff"):
			u.call("clear_debuff", id)
		elif u.has_method("remove_debuff"):
			u.call("remove_debuff", id)


## 困旗：90px 内锁步（移速 ×0.6 + 禁闪避），零伤害
func _tick_bind_flags() -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("apply_debuff"):
		return
	var tp: Vector2 = (target as Node2D).global_position
	for f in _flags:
		if int(f.get("kind")) != KIND_BIND:
			continue
		if (f as Node2D).global_position.distance_to(tp) <= BIND_FLAG_RADIUS:
			_debuff(target, "lock_step", 0.35)
			break


## 阵线：n 面旗连成 n-1 段，满 5 面补一段收口
func _segments() -> Array:
	var out: Array = []
	for i in range(_flags.size() - 1):
		out.append([_flags[i], _flags[i + 1]])
	if _flags.size() >= 5:
		out.append([_flags[4], _flags[0]])
	return out


## 阵线视觉：每段一根（不再拆半），颜色取多数旗色；同时挂阻挡层。
## 敌方 BOSS 的线挡玩家/友军，友军召唤物的线挡敌方 BOSS，施法者穿自己的线。
func _sync_line_visuals() -> void:
	var segs := _segments()
	var need := segs.size()
	while _line_visuals.size() < need:
		var rope := Sprite2D.new()
		rope.texture = load("res://assets/effects/skills/array_line.png")
		rope.centered = true
		rope.material = additive_material_fx()
		rope.z_index = 1
		add_child(rope)
		var glow := Sprite2D.new()
		glow.texture = rope.texture
		glow.centered = true
		glow.material = additive_material_fx()
		glow.z_index = 0
		add_child(glow)
		_line_visuals.append([rope, glow])
	while _line_visuals.size() > need:
		var pair = _line_visuals.pop_back()
		for sp in pair:
			if is_instance_valid(sp):
				sp.queue_free()
	if _line_barrier == null or not is_instance_valid(_line_barrier):
		_line_barrier = ArrayLineBarrier.new()
		_line_barrier.name = "LineBarrier"
		_line_barrier.top_level = true
		_line_barrier.setup(ArrayFlag.LINE_LAYER_PLAYER if is_ally else ArrayFlag.LINE_LAYER_BOSS)
		add_child(_line_barrier)
	_line_barrier.sync(segs)
	var c := _line_color()
	for i in range(segs.size()):
		var a: Vector2 = (segs[i][0] as Node2D).global_position
		var b: Vector2 = (segs[i][1] as Node2D).global_position
		_place_line(_line_visuals[i], a, b, c)


func _line_color() -> Color:
	var c := Color(ArtDB.ARRAY_FLAG_KIND_COLORS.get(_majority_kind(), Color(0.96, 0.84, 0.58)))
	return c.lerp(Color(0.98, 0.86, 0.60), 0.35)


func _place_line(pair: Array, a: Vector2, b: Vector2, color: Color) -> void:
	var v := b - a
	var rope: Sprite2D = pair[0]
	var glow: Sprite2D = pair[1]
	var center := (a + b) * 0.5
	var ang := v.angle()
	var sx := maxf(v.length(), 1.0) / 256.0
	rope.global_position = center
	rope.rotation = ang
	rope.scale = Vector2(sx, 1.0)
	rope.modulate = Color(1.3, 1.25, 1.15, 1.0)
	glow.global_position = center
	glow.rotation = ang
	glow.scale = Vector2(sx, 1.7)
	glow.modulate = Color(color.r, color.g, color.b, 0.24)


func additive_material_fx() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


# ===================== 选招 =====================

func _on_chase_reached(_dist: float) -> void:
	_choose()

func _choose() -> void:
	if state != BossState.IDLE and state != BossState.CHASE:
		return
	if _decide_wait > 0.0:
		return
	_decide_wait = 0.3
	# 0. 三色成套：凑齐三同色且冷却好 → 直接起手（万剑 / 定身锁）
	var fk := _formation_kind()
	if fk != -1 and _formation_cd <= 0.0 and _formation_can_cast(fk):
		_begin_formation(fk)
		return
	# 1. 旗不足 → 先布点（插旗不造成伤害，所以单独卡节奏）
	# 布点到四面就停：第五面由「垒旗」「踏阵」顺带插上，不靠站桩刷旗
	# ⚠ 必须查插旗自己的冷却：这里直接 _begin，绕过了 _usable 的冷却检查（曾导致 2.3 秒一插）
	if _flags.size() < 4 and _plant_wait <= 0.0 and _ready_cd(SKILL_PLANT):
		var plant_chance := 0.8 if _flags.size() < 2 else 0.25
		if randf() < plant_chance:
			_begin(SKILL_PLANT, 0.0)
			return
	# 2. 四面齐 → 封阵 / 二阶段解阵
	if _flags.size() >= 4:
		if _phase_two and _ready_cd(SKILL_BURST) and randf() < 0.55:
			_begin(SKILL_BURST, 0.0)
			return
		if _ready_cd(SKILL_SEAL):
			_begin(SKILL_SEAL, 0.0)
			return
	# 2.5 差一面就齐：优先补旗（封阵/解阵才有机会出现）
	if _flags.size() == 3 and _plant_wait <= 0.0 and _ready_cd(SKILL_PLANT) and randf() < 0.7:
		_begin(SKILL_PLANT, 0.0)
		return
	# 3. 距离评分
	var best := ""
	var best_score := -999.0
	for sid in SCORED:
		if not _usable(String(sid)):
			continue
		# 除"插旗"（布点）外，打不到的招一律不进候选 —— 避免原地空放
		if str(sid) != SKILL_PLANT and not _in_reach(str(sid)):
			continue
		# 串联偏好：让招式成"组合"而不是随机抽（布点→用线→贴脸/位移）
		var combo := 0.0
		var last := String(_recent[0]) if not _recent.is_empty() else ""
		if last == SKILL_PLANT and (sid == SKILL_LINE or sid == SKILL_PULL):
			combo = 1.6
		elif last == SKILL_PULL and sid == SKILL_STEP:
			combo = 1.2
		elif last == SKILL_STEP and (sid == SKILL_SWEEP or sid == SKILL_PILE):
			combo = 1.6
		elif last == SKILL_LINE and (sid == SKILL_STEP or sid == SKILL_SEAL):
			combo = 1.0
		var sc := _score(String(sid)) + randf() * 1.1 + combo - _repeat_penalty(String(sid))
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
	# 技能名在**前摇第一帧**飘出，hold = 前摇时长；释放时不再重复报一次
	var fname := String(b.get("form_name", ""))
	if fname != "":
		show_skill_line(fname, state_timer, 18, 180.0,
			BossBase.skill_name_color(String(b.get("attack_kind", ""))), -190.0)
	_play_form_anim(sid, state_timer + 0.15)
	if target != null and is_instance_valid(target):
		_set_facing(((target as Node2D).global_position - global_position).normalized())
	if sid == SKILL_PLANT:
		_pending_plant_pos = _plant_point()
		_pending_plant_kind = _next_kind()
		_show_plant_telegraph()


## 这一招现在能不能真的打到玩家（防原地空放）
## ⚠ 按招式**实际判定形状**逐招算，不能一律拿"BOSS→玩家距离 vs range"：
##   引阵/卷阵的判定在旗线上、封阵在旗阵中心、解阵在每面旗下、踏阵是冲刺落点。
##   统一口径会把打不到的招放出去（2026-10-28 模拟实测：427px 外放引阵必空）
const LINE_REACH_PAD := 56.0   # 线判定半宽 42 + 玩家身位

func _in_reach(sid: String, margin: float = 18.0) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var b := MoveDB.resolve_boss(sid)
	if b.is_empty():
		return false
	var tp: Vector2 = (target as Node2D).global_position
	var reach := float(b.get("range", 120.0))
	match sid:
		SKILL_LINE:
			if _flags.size() >= 2:
				return _player_on_any_line(tp)
			# 无旗兜底：朝玩家拉一道 460 直线
			return _dist() <= 460.0 + margin
		SKILL_PULL:
			if _flags.is_empty():
				return false
			return _pull_line_distance(tp) <= LINE_REACH_PAD + margin
		SKILL_SEAL:
			return tp.distance_to(_flags_centroid()) <= reach + 18.0 + margin
		SKILL_BURST:
			for f in _flags:
				if tp.distance_to((f as Node2D).global_position) <= reach + 18.0 + margin:
					return true
			return false
		SKILL_STEP:
			# 踏阵是**位移**（补距离），不是站桩攻击：够得着的距离内都该放
			# 设计口径见 docs/定阵先生BOSS完整资料.md：≥320 也要靠它贴人
			return _dist() <= 480.0
	# 扇形张角不再卡：`_begin` 出手瞬间会把朝向对准玩家，起手时判"能不能打到"只看距离
	return _dist() <= reach + margin


## 玩家是否压在任意一道阵线上（含 5 旗时首尾收口那一道）
func _player_on_any_line(tp: Vector2) -> bool:
	for seg in _segments():
		if _point_segment_distance(tp, (seg[0] as Node2D).global_position,
				(seg[1] as Node2D).global_position) <= LINE_REACH_PAD:
			return true
	return false


## 卷阵：旗→BOSS 这条线的判定距离（取最靠近玩家的那面旗）
func _pull_line_distance(tp: Vector2) -> float:
	var best := 999999.0
	for f in _flags:
		best = minf(best, _point_segment_distance(tp, (f as Node2D).global_position, global_position))
	return best


func _usable(sid: String) -> bool:
	if not _ready_cd(sid):
		return false
	match sid:
		SKILL_PLANT:
			return _flags.size() < 4
		SKILL_LINE, SKILL_PULL:
			return _flags.size() >= 2
		SKILL_SEAL:
			return _flags.size() >= 4
		SKILL_BURST:
			return _phase_two and _flags.size() >= 1
	return true


func _ready_cd(sid: String) -> bool:
	return float(_cools.get(sid, 0.0)) <= 0.0


func _score(sid: String) -> float:
	var d := _dist()
	match sid:
		SKILL_SWEEP:
			return 3.8 - absf(d - 90.0) / 110.0
		SKILL_PILE:
			return 3.4 - absf(d - 100.0) / 120.0
		SKILL_STEP:
			return 2.4 - absf(d - 300.0) / 220.0
		SKILL_PULL:
			return 2.4 - absf(d - 220.0) / 220.0
		SKILL_LINE:
			return 2.6 - absf(d - 260.0) / 260.0
		SKILL_SEAL:
			return 1.6
		SKILL_BURST:
			return 1.4
	return 0.4


func _repeat_penalty(sid: String) -> float:
	# 连打同一招是"单调"的根源：第二连降权、第三连直接封掉（用户 2026-10-28 反馈实战太单调）
	if _recent.size() >= 2 and String(_recent[0]) == sid and String(_recent[1]) == sid:
		return 99.0
	if _recent.size() >= 1 and String(_recent[0]) == sid:
		return 2.4
	return 0.0


func _record(sid: String) -> void:
	_recent.push_front(sid)
	if _recent.size() > 3:
		_recent.resize(3)
	_cools[sid] = float(COOLDOWNS.get(sid, 5.0))


# ===================== 出招 =====================

func _fire_skill() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	GameState.play_sfx("boss_attack")
	var b := MoveDB.resolve_boss(_current_skill)
	if b.is_empty():
		_finish_skill()
		return
	match _current_skill:
		SKILL_PLANT:
			_cast_plant(b)
		SKILL_LINE:
			_cast_line(b)
		SKILL_PULL:
			_cast_pull(b)
		SKILL_SEAL:
			_cast_seal(b)
		SKILL_SWEEP:
			_cast_sweep(b)
		SKILL_STEP:
			_cast_step(b)
		SKILL_PILE:
			_cast_pile(b)
		SKILL_BURST:
			_cast_burst(b)
		_:
			_finish_skill()


var _current_skill: String = ""


func _finish_skill() -> void:
	_record(_current_skill)
	_current_skill = ""
	state = BossState.RECOVER
	state_timer = 0.45


# ---------- 布点 ----------
func _cast_plant(_b: Dictionary) -> void:
	ArrayFx.play_plant(get_parent(), _pending_plant_pos, _pending_plant_kind)
	_plant_flag(_pending_plant_pos, _pending_plant_kind)
	if _plant_mark != null and is_instance_valid(_plant_mark):
		_plant_mark.queue_free()
	_plant_mark = null
	_plant_wait = 1.4
	_finish_skill()


func _plant_point() -> Vector2:
	# 选点规则（用户 2026-10-28 定）：新旗要能和**已有的旗**连成一道穿过玩家的线，
	# 而且离玩家不能太近（近了等于贴脸插旗，没有"读点走位"的空间）。
	var player_pos := global_position
	if target != null and is_instance_valid(target):
		player_pos = (target as Node2D).global_position
	var min_from_player := 170.0
	var max_from_player := 430.0
	# ① 场上已有旗：把它关于玩家做镜像 → 连线必然穿过玩家
	if not _flags.is_empty():
		var best: Node2D = null
		var best_score := -999.0
		for f in _flags:
			var fp: Vector2 = (f as Node2D).global_position
			var d := fp.distance_to(player_pos)
			if d < 60.0 or d > max_from_player:
				continue
			var score := -absf(d - 260.0)   # 离 260 越近越好：线段够长、够读
			if score > best_score:
				best_score = score
				best = f as Node2D
		if best != null:
			var mirror := player_pos * 2.0 - best.global_position
			var dir := (mirror - player_pos)
			if dir.length() < 1.0:
				dir = Vector2.RIGHT
			dir = dir.normalized()
			var dist := clampf(mirror.distance_to(player_pos), min_from_player, max_from_player)
			return player_pos + dir * dist
	# ② 场上没旗 / 没有合适的旗：插在玩家**斜前方 240**，保证下一道线有角度可拉
	var fwd := (player_pos - global_position)
	if fwd.length() < 1.0:
		fwd = facing
	fwd = fwd.normalized()
	var side := Vector2(-fwd.y, fwd.x) * 130.0 * (1.0 if randf() < 0.5 else -1.0)
	return player_pos + fwd * 240.0 + side


func _plant_flag(pos: Vector2, kind_id: int = -1) -> void:
	if _flags.size() >= MAX_FLAGS:
		return
	# 全阵清空后重新起阵：阵力补满（玩家要在这轮雷击耗尽前拆旗）
	if _flags.is_empty():
		_zone_energy = ZONE_ENERGY_MAX
	if kind_id < 0:
		kind_id = _next_kind()
	var f := ArrayFlag.new()
	f.setup(true, not is_ally, kind_id)
	get_parent().add_child(f)
	f.global_position = pos
	_flags.append(f)
	# 新旗给的起手延迟：不让它落地瞬间就轰/锁
	_flag_cd[f.get_instance_id()] = 0.8


# ---------- 用线 ----------
## 五旗区域：BOSS 在自家阵内 +30% 攻/防；区域内对手 -10% 攻，每秒雷击（10 阵力）
func _tick_zone(delta: float) -> void:
	var poly := _zone_polygon()
	if poly.size() < MAX_FLAGS:
		if _zone_complete:
			_clear_zone_effects()
			show_windup_line("阵势已散", 0.7, 18, 220.0, Color(0.78, 0.70, 0.56), -190.0)
		return
	if not _zone_complete:
		_zone_complete = true
		show_windup_line("五旗成阵！", 0.9, 20, 220.0, _line_color(), -190.0)
	var inside := Geometry2D.is_point_in_polygon(global_position, poly)
	_zone_attack_mult = ZONE_ATTACK_BUFF if inside else 1.0
	_zone_defense_mult = 1.0 / ZONE_DEFENSE_DIV if inside else 1.0
	set_zone_attack_mult("self", _zone_attack_mult)
	_update_zone_fill(poly)
	var units := _zone_units_inside(poly)
	_apply_zone_unit_debuff(units)
	if units.is_empty():
		_zone_timer = 0.0
		return
	_zone_timer += delta
	if _zone_timer < ZONE_LIGHTNING_INTERVAL:
		return
	_zone_timer = 0.0
	if _zone_energy < ZONE_ENERGY_COST:
		show_windup_line("阵力枯竭，阵旗消散", 1.0, 18, 240.0, Color(0.72, 0.80, 0.92), -190.0)
		_clear_all_flags()
		return
	_zone_energy -= ZONE_ENERGY_COST
	var dmg := attack_power * ZONE_LIGHTNING_COEF
	var c := _line_color()
	for u in units:
		if deal_damage_to(u, dmg, "elemental", ""):
			ArrayFx.play_thunder(get_parent(), (u as Node2D).global_position, c)


func _zone_polygon() -> PackedVector2Array:
	var poly := PackedVector2Array()
	if _flags.size() < MAX_FLAGS:
		return poly
	for f in _flags:
		if is_instance_valid(f) and f is Node2D:
			poly.append((f as Node2D).global_position)
	if poly.size() < MAX_FLAGS:
		return PackedVector2Array()
	return poly


func _zone_units_inside(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for u in attack_units():
		if u is Node2D and Geometry2D.is_point_in_polygon((u as Node2D).global_position, poly):
			out.append(u)
	return out


func _apply_zone_unit_debuff(units: Array) -> void:
	for u in _zone_affected_units.duplicate():
		if not is_instance_valid(u) or not (u in units):
			_set_zone_unit_debuff(u, false)
			_zone_affected_units.erase(u)
	for u in units:
		_set_zone_unit_debuff(u, true)
		if not (u in _zone_affected_units):
			_zone_affected_units.append(u)


## ⚠ 形参**不写** `: Node`。`_zone_affected_units` 里会留着刚死掉的棋子，
##   把已释放实例传进带类型的形参，调用在引擎边界就被拒（函数体根本进不去，
##   里面那道 `is_instance_valid` 守卫等于不存在）—— 实测棋盘上每帧刷一条
##   `Invalid type in function '_set_zone_unit_debuff'`，而且那条记录永远删不掉。
##   秘境里对手是玩家不会消失，所以这条只有棋局会踩到。
func _set_zone_unit_debuff(u, on: bool) -> void:
	if u == null or not is_instance_valid(u):
		return
	var mult := ZONE_ENEMY_ATTACK_MULT if on else 1.0
	if u.is_in_group("player") and u.has_method("set_array_zone_enemy_attack_mult"):
		u.call("set_array_zone_enemy_attack_mult", mult)
	elif u.has_method("set_zone_attack_mult"):
		u.call("set_zone_attack_mult", "enemy", mult)


func _update_zone_fill(poly: PackedVector2Array) -> void:
	if _zone_fill == null or not is_instance_valid(_zone_fill):
		_zone_fill = Polygon2D.new()
		_zone_fill.name = "ZoneFill"
		_zone_fill.top_level = true
		_zone_fill.z_as_relative = false
		_zone_fill.z_index = -8
		add_child(_zone_fill)
	_zone_fill.polygon = poly
	var c := _line_color()
	_zone_fill.color = Color(c.r, c.g, c.b, 0.06)
	_zone_fill.visible = true


func _clear_zone_effects() -> void:
	_zone_complete = false
	_zone_timer = 0.0
	_zone_attack_mult = 1.0
	_zone_defense_mult = 1.0
	set_zone_attack_mult("self", 1.0)
	_apply_zone_unit_debuff([])
	if _zone_fill != null and is_instance_valid(_zone_fill):
		_zone_fill.visible = false


func _cast_line(b: Dictionary) -> void:
	var segments: Array = []
	if _flags.size() >= 2:
		# 引阵：每段一根线，整段按多数旗色结算（不再拆半）
		var fk := _majority_kind()
		for seg in _segments():
			var a: Vector2 = (seg[0] as Node2D).global_position
			var bp: Vector2 = (seg[1] as Node2D).global_position
			segments.append({"a": a, "b": bp, "kind": fk})
			_apply_line_effect(a, bp, fk)
		_plant_wait = 0.6
	else:
		# 没旗兜底：朝玩家拉一道直线，保证它任何旗数下都有威胁
		var aim := facing
		if target != null and is_instance_valid(target):
			aim = ((target as Node2D).global_position - global_position).normalized()
		segments.append({"a": global_position, "b": global_position + aim * 460.0,
			"kind": KIND_ATTACK})
		_damage_segment(global_position, global_position + aim * 460.0,
			float(b.get("damage_coeff", 1.1)) * 0.8, "elemental")
	ArrayFx.play_line(get_parent(), segments)
	_finish_skill()


## 引阵的整段结算：红＝0.8× 灼烧；黑＝锁步 1.0 秒零伤害；蓝＝不参与杀伤
func _apply_line_effect(a: Vector2, b: Vector2, kind: int) -> void:
	if kind == KIND_GUARD:
		return
	var dmg := attack_power * 0.8 * (1.25 if phase == 2 else 1.0)
	for u in attack_units():
		if not (u is Node2D):
			continue
		if _point_segment_distance((u as Node2D).global_position, a, b) > LINE_HALF_WIDTH + 20.0:
			continue
		if kind == KIND_ATTACK:
			deal_damage_to(u, dmg, "elemental", "fire")
			if u.has_method("apply_debuff"):
				_debuff(u, "wounded", 1.2)
		elif u.has_method("apply_debuff"):
			_debuff(u, "lock_step", 1.0)


func _cast_pull(b: Dictionary) -> void:
	if not _flags.is_empty():
		# 卷最靠近玩家的那面旗：判定线和选招检查同一口径，放出来就是真能扫到
		var f: Node2D = _flags[0]
		if target != null and is_instance_valid(target):
			var tp: Vector2 = (target as Node2D).global_position
			var best := 999999.0
			for cand in _flags:
				var d := _point_segment_distance(tp, (cand as Node2D).global_position, global_position)
				if d < best:
					best = d
					f = cand as Node2D
		var from := f.global_position
		# 只把旗"卷"到身侧，不再销毁：撤旗太频繁会把线全清空（用户 2026-10-29）
		f.global_position = global_position + facing * 110.0
		ArrayFx.play_pull(get_parent(), from, f.global_position, int(f.get("kind")))
		match int(f.get("kind")):
			KIND_ATTACK:
				var hit := _damage_segment(from, global_position,
					float(b.get("damage_coeff", 0.9)), "physical")
				for u in hit:
					if u.has_method("apply_debuff"):
						_debuff(u, "burn", 3.0)
			KIND_BIND:
				if target != null and is_instance_valid(target) and target.has_method("take_knockback"):
					var dir := (f.global_position - (target as Node2D).global_position).normalized()
					if dir.length() < 0.5:
						dir = facing
					target.call("take_knockback", dir * 520.0)   # 拽向旗位约 120px
			_:
				pass   # 守旗：只把旗收回身侧，继续吃减伤
	_finish_skill()


func _cast_seal(b: Dictionary) -> void:
	if _flags.size() >= 4:
		_seal_center = _flags_centroid()
		_seal_kind = _majority_kind()
		_seal_guard = _seal_kind == KIND_GUARD
		ArrayFx.play_seal(get_parent(), _seal_center, 210.0, _seal_kind, 4, 0.55)
		if _seal_guard:
			# 守牢：10 秒减伤 buff（不锁 BOSS 行动）；任一面成阵旗被破立即结束
			_seal_guard_left = 10.0
			_seal_guard_flags.clear()
			for f in _flags:
				if is_instance_valid(f) and not bool(f.get("_dead")):
					_seal_guard_flags.append(f)
			_seal_ticks = 0
			_finish_skill()
			return
		# 攻 / 困牢：四跳，每 0.55 秒
		_seal_ticks = 4
		_seal_timer = 0.0
		state = ExtraState.SEAL_FIELD
		state_timer = 0.0
		return
	_finish_skill()


func _tick_seal(delta: float) -> void:
	_seal_timer -= delta
	if _seal_timer > 0.0:
		return
	_seal_timer = 0.55
	_seal_ticks -= 1
	match _seal_kind:
		KIND_ATTACK:
			# 杀阵牢：每跳 ×1.25
			for u in attack_units():
				if u is Node2D and (u as Node2D).global_position.distance_to(_seal_center) <= 210.0:
					deal_damage_to(u, MoveDB.boss_damage(SKILL_SEAL, attack_power, phase) * 1.25,
						"elemental", "fire")
		KIND_BIND:
			# 困阵牢：零伤害，牢内 5 秒眩晕（已眩晕不刷新）
			for u in attack_units():
				if u is Node2D and (u as Node2D).global_position.distance_to(_seal_center) <= 210.0:
					_stun_unit(u, 5.0)
		_:
			pass   # 守阵牢由 _cast_seal 分支处理，不进入四跳
	if _seal_ticks <= 0:
		_finish_skill()


## 守牢计时与「旗破瞬间消失」：记录的成阵旗任一失效 → 立刻结束
func _tick_seal_guard(delta: float) -> void:
	if not _seal_guard:
		return
	_seal_guard_left = maxf(0.0, _seal_guard_left - delta)
	var intact := _flags.size() >= 4
	if intact:
		for f in _seal_guard_flags:
			if not is_instance_valid(f) or bool(f.get("_dead")) or not (f in _flags):
				intact = false
				break
	if _seal_guard_left <= 0.0 or not intact:
		var broken := not intact
		_seal_guard = false
		_seal_guard_left = 0.0
		_seal_guard_flags.clear()
		if broken:
			show_windup_line("守阵已破", 0.7, 18, 220.0, Color(0.78, 0.70, 0.56), -190.0)


## BOSS 侧眩晕：玩家走 stun debuff，其它单位走 stagger_for；已在眩晕中不刷新
func _stun_unit(u: Node, seconds: float) -> void:
	if u == null or not is_instance_valid(u):
		return
	if u.is_in_group("player"):
		if u.has_method("has_debuff") and bool(u.call("has_debuff", "stun")):
			return
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "stun", seconds)
		return
	if u.has_method("stagger_for"):
		if int(u.get("state")) == BossState.STAGGER:
			return
		u.call("stagger_for", seconds)
		return
	if u.has_method("apply_debuff"):
		if u.has_method("has_debuff") and bool(u.call("has_debuff", "stun")):
			return
		u.call("apply_debuff", "stun", seconds)


# ---------- 不依赖旗 ----------
func _cast_sweep(_b: Dictionary) -> void:
	ArrayFx.play_sweep(get_parent(), global_position, facing, 160.0, 150.0)
	_hit_all_in_form(SKILL_SWEEP)
	_finish_skill()


func _cast_step(_b: Dictionary) -> void:
	var dest := global_position
	if target != null and is_instance_valid(target):
		var tp: Vector2 = (target as Node2D).global_position
		# 默认冲玩家；若有旗比"人"更靠近玩家（旗是绕玩家插的），就冲那面旗
		# —— 只挑比当前距离更近的目标，否则会出现"往侧后方跳"的空放位移
		var best := global_position.distance_to(tp)
		dest = tp
		for f in _flags:
			var fd: float = (f as Node2D).global_position.distance_to(tp)
			if fd < best - 20.0:
				best = fd
				dest = (f as Node2D).global_position
	var delta_v := dest - global_position
	_step_dir = delta_v.normalized() if delta_v.length() > 1.0 else facing
	_set_facing(_step_dir)
	_step_from = global_position
	_step_kind = _next_kind()
	_plant_flag(global_position, _step_kind)
	state = ExtraState.STEP_DASH
	state_timer = 0.26   # 0.26×760 ≈ 198px：够从 300 外一步贴到判定圈内


var _step_dir: Vector2 = Vector2.RIGHT
var _step_from: Vector2 = Vector2.ZERO
var _step_kind: int = KIND_ATTACK


func _tick_step(delta: float) -> void:
	velocity = _step_dir * 760.0
	state_timer -= delta
	# ⚠ 特有状态会在 super._physics_process 之前 return，move_and_slide 必须自己调：
	#   否则"踏阵"只播了个动画，人根本没位移（2026-10-28 模拟里 289px 外踏阵必空才查出来）
	move_and_slide()
	_clamp_to_arena()
	_update_skin_motion()
	if state_timer > 0.0:
		return
	velocity = Vector2.ZERO
	ArrayFx.play_step(get_parent(), _step_from, global_position, _step_kind)
	_hit_all_in_form(SKILL_STEP)
	_finish_skill()


func _cast_pile(_b: Dictionary) -> void:
	ArrayFx.play_pile(get_parent(), global_position, facing, 120.0)
	_hit_all_in_form(SKILL_PILE)
	_plant_flag(global_position + facing * 90.0)
	_finish_skill()


func _cast_burst(_b: Dictionary) -> void:
	var fx_flags: Array = []
	for f in _flags:
		if is_instance_valid(f):
			fx_flags.append({"pos": (f as Node2D).global_position, "kind": int(f.get("kind"))})
	ArrayFx.play_burst(get_parent(), fx_flags)
	if not _flags.is_empty():
		var dmg := MoveDB.boss_damage(SKILL_BURST, attack_power, phase)
		for f in _flags.duplicate():
			var p: Vector2 = (f as Node2D).global_position
			var fk := int(f.get("kind"))
			if fk == KIND_GUARD:
				apply_heal(max_hp * 0.08)
				continue
			for u in attack_units():
				if not (u is Node2D) or (u as Node2D).global_position.distance_to(p) > 140.0:
					continue
				match fk:
					KIND_ATTACK:
						deal_damage_to(u, dmg, "elemental", "fire")
					KIND_BIND:
						if u.has_method("apply_debuff"):
							_debuff(u, "lock_step", 2.0)
					_:
						pass
		_clear_all_flags()
	_finish_skill()


# ===================== 工具 =====================

func _flags_centroid() -> Vector2:
	if _flags.is_empty():
		return global_position
	var s := Vector2.ZERO
	for f in _flags:
		s += (f as Node2D).global_position
	return s / float(_flags.size())


func _clear_all_flags() -> void:
	for f in _flags:
		if is_instance_valid(f):
			f.queue_free()
	_flags.clear()
	_guard_prev = 0
	_flag_cd.clear()
	_seal_guard = false
	_seal_guard_left = 0.0
	_seal_guard_flags.clear()
	_clear_zone_effects()
	_sync_line_visuals()


func _damage_segment(a: Vector2, b: Vector2, coeff: float, kind: String) -> Array:
	var out: Array = []
	var dmg := attack_power * coeff * (1.25 if phase == 2 else 1.0)
	for u in attack_units():
		if u is Node2D and _point_segment_distance((u as Node2D).global_position, a, b) <= LINE_HALF_WIDTH + 20.0:
			if deal_damage_to(u, dmg, kind, "fire"):
				out.append(u)
	return out


func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ===================== 三色 / 成套 =====================

## 下一面旗插什么色：先补三才 → 有 45% 概率把某色凑成三同色 → 再按局面
func _next_kind() -> int:
	var c := _kind_counts()
	for k in KINDS:
		if int(c.get(k, 0)) == 2 and not (k == KIND_GUARD and _guard_lock > 0.0):
			if randf() < 0.45:
				return k
	for k in KINDS:
		if int(c.get(k, 0)) == 0 and not (k == KIND_GUARD and _guard_lock > 0.0):
			return k
	if _dist() <= 240.0:
		return KIND_ATTACK
	if _hp_ratio() <= 0.5 and _guard_lock <= 0.0:
		return KIND_GUARD
	return KIND_BIND


## 封阵多数色（平票 攻 > 困 > 守）
func _majority_kind() -> int:
	var c := _kind_counts()
	var best := KIND_ATTACK
	var best_n := -1
	for k in KINDS:
		if int(c.get(k, 0)) > best_n:
			best_n = int(c.get(k, 0))
			best = k
	return best


## 当前成套：某色 ≥3 面（5 面旗最多只可能凑成一套）
func _formation_kind() -> int:
	var c := _kind_counts()
	for k in KINDS:
		if int(c.get(k, 0)) >= 3:
			return k
	return -1


func _formation_can_cast(fk: int) -> bool:
	match fk:
		KIND_ATTACK:
			return _dist() <= 620.0
		KIND_BIND:
			return _inside_bind_triangle()
	return false


## 玩家是否站在三面困旗围出的三角形里（取离玩家最近的三面）
func _inside_bind_triangle() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var tp: Vector2 = (target as Node2D).global_position
	var pts: Array = []
	for f in _flags:
		if int(f.get("kind")) == KIND_BIND:
			pts.append((f as Node2D).global_position)
	if pts.size() < 3:
		return false
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(tp) < b.distance_to(tp))
	return Geometry2D.is_point_in_polygon(tp, PackedVector2Array([pts[0], pts[1], pts[2]]))


## 成套杀招起手：万剑汇聚（三攻） / 定身锁（三困）。守（三守）是被动，不起手
func _begin_formation(fk: int) -> void:
	_form_kind = fk
	_form_t = 0.0
	_form_strikes = 0
	_form_pos = (target as Node2D).global_position
	state = ExtraState.FORMATION
	_current_skill = ""
	_play_form_anim(SKILL_LINE if fk == KIND_ATTACK else SKILL_SEAL, 1.5)
	var col := Color(ArtDB.ARRAY_FLAG_KIND_COLORS.get(fk, Color.WHITE))
	if fk == KIND_ATTACK:
		show_skill_line("三攻·万剑汇聚", 1.2, 22, 240.0, col, -190.0)
		_spawn_mark(ArtDB.ARRAY_FLAG_WARN_TEX, _form_pos, FORMATION_ATTACK_RADIUS, 1.25,
			Color(1, 1, 1, 0.95))
	else:
		show_skill_line("三困·定身锁", 1.2, 22, 240.0, col, -190.0)
		_spawn_mark(ArtDB.ARRAY_FLAG_BIND_TEX, _form_pos, 100.0, 0.75,
			Color(1, 1, 1, 0.9))


func _tick_formation(delta: float) -> void:
	_form_t += delta
	if _form_kind == KIND_ATTACK:
		# 1.2 秒预警 → 三道剑气，每 0.15 秒落一道（每道 0.8×，物理，可弹）
		if _form_t >= 1.2:
			var want := mini(3, 1 + int((_form_t - 1.2) / 0.15))
			if _form_strikes == 0 and want > 0:
				ArrayFx.play_swords(get_parent(), _form_pos)
			while _form_strikes < want:
				_form_strikes += 1
				for u in attack_units():
					if not (u is Node2D):
						continue
					if (u as Node2D).global_position.distance_to(_form_pos) > FORMATION_ATTACK_RADIUS:
						continue
					deal_damage_to(u, attack_power * FORMATION_ATTACK_COEF
						* (1.25 if phase == 2 else 1.0), "physical_melee", "")
				_spawn_mark(ArtDB.ARRAY_FLAG_WARN_TEX, _form_pos, FORMATION_ATTACK_RADIUS, 0.16,
					Color(1, 0.90, 0.80, 1.0))
				GameState.trigger_hit_stop(0.03)
		if _form_t >= 1.65:
			_end_formation()
	elif _form_kind == KIND_BIND:
		if _form_strikes == 0 and _form_t >= 0.7:
			_form_strikes = 1
			for u in attack_units():
				if not (u is Node2D):
					continue
				if (u as Node2D).global_position.distance_to(_form_pos) > 100.0:
					continue
				if u.has_method("apply_debuff"):
					u.call("apply_debuff", "rooted", 1.5)
			ArrayFx.play_lock(get_parent(), _form_pos, 100.0)
		if _form_t >= 0.95:
			_end_formation()


func _end_formation() -> void:
	_form_kind = -1
	_formation_cd = FORMATION_COOLDOWN
	state = BossState.RECOVER
	state_timer = 0.6


## 插旗预告：落点先亮同色阵纹（前摇 0.6 秒内可读）
func _show_plant_telegraph() -> void:
	if _plant_mark != null and is_instance_valid(_plant_mark):
		_plant_mark.queue_free()
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/effects/skills/array_decal.png")
	spr.centered = true
	spr.position = _pending_plant_pos
	spr.scale = Vector2(0.18, 0.18)
	var c := Color(ArtDB.ARRAY_FLAG_KIND_COLORS.get(_pending_plant_kind, Color.WHITE))
	spr.modulate = Color(c.r, c.g, c.b, 0.78)
	spr.z_index = 1
	get_parent().add_child(spr)
	_plant_mark = spr
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.18, 0.6)


## 地面提示环（预警 / 定身 / 命中闪）：半径按判定给，贴图 256 宽
func _spawn_mark(tex_path: String, pos: Vector2, radius: float, life: float, tint: Color) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = load(tex_path)
	spr.centered = true
	spr.position = pos
	var sc := radius * 2.0 / 256.0
	spr.scale = Vector2(sc, sc)
	spr.modulate = tint
	spr.z_index = 1
	get_parent().add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, maxf(0.12, life))
	tw.tween_callback(spr.queue_free)
	return spr


## 守旗护罩环 / 成套环：常驻，不自动销毁
func _ensure_auras() -> void:
	if _guard_aura == null or not is_instance_valid(_guard_aura):
		_guard_aura = Sprite2D.new()
		_guard_aura.texture = load(ArtDB.ARRAY_FLAG_GUARD_TEX)
		_guard_aura.centered = true
		_guard_aura.position = Vector2(0.0, 18.0)
		_guard_aura.scale = Vector2(0.86, 0.86)
		_guard_aura.z_index = 1
		_guard_aura.visible = false
		add_child(_guard_aura)
	if _form_aura == null or not is_instance_valid(_form_aura):
		_form_aura = Sprite2D.new()
		_form_aura.texture = load(ArtDB.ARRAY_FLAG_GUARD_TEX)
		_form_aura.centered = true
		_form_aura.position = Vector2(0.0, 12.0)
		_form_aura.scale = Vector2(1.18, 1.18)
		_form_aura.z_index = 1
		_form_aura.visible = false
		add_child(_form_aura)


func _tick_auras(delta: float) -> void:
	_ensure_auras()
	var fk := _formation_kind()
	var guard_on := _guard_count() > 0 or _seal_guard or fk == KIND_GUARD
	_guard_aura.visible = guard_on and not is_dead
	if _guard_aura.visible:
		_guard_aura.rotation += delta * 0.35
		var a := 0.34 + 0.10 * sin(float(Time.get_ticks_msec()) * 0.004)
		_guard_aura.modulate = Color(0.55, 0.95, 1.0, a)
	_form_aura.visible = fk != -1 and not is_dead
	if _form_aura.visible:
		_form_aura.rotation -= delta * 0.55
		var c := Color(ArtDB.ARRAY_FLAG_KIND_COLORS.get(fk, Color.WHITE))
		_form_aura.modulate = Color(c.r, c.g, c.b, 0.42)


## 守旗减伤 / 守阵牢 / 龟甲阵：BossBase.take_damage 在抗性之后读这里
func damage_taken_multiplier(_damage_kind: String) -> float:
	var m := 1.0
	if _formation_kind() == KIND_GUARD:
		m = 0.30
	elif _seal_guard:
		m = 0.30
	elif _guard_count() > 0:
		m = GUARD_REDUCTION
	# 五旗阵内：防御 +30% → 受伤 ×1/1.3
	if _zone_defense_mult < 1.0:
		m *= _zone_defense_mult
	return m


## 死亡时立刻清阵：阵线/区域/对玩家的减速与减攻都要一起消失，不能等退场
func _die() -> void:
	_clear_all_flags()
	super._die()


func _on_phase_two() -> void:
	_phase_two = true
	show_windup_line("阵成，四象皆动！", 1.0, 22, 240.0, Color(0.92, 0.36, 0.28), -190.0)


func is_phase_two() -> bool:
	return _phase_two


var _phase_two: bool = false


func _dist() -> float:
	return _distance_to_target()


func _fire_attack() -> void:
	_fire_skill()


## 通用命中（扇形 / 圆形）：与两仪 / 刀客同一套口径
func _hit_all_in_form(form_id: String, center_override: Variant = null) -> bool:
	var b := MoveDB.resolve_boss(form_id)
	if b.is_empty():
		return false
	var dmg := MoveDB.boss_damage(form_id, attack_power, phase)
	var kind := String(b.get("attack_kind", "physical_melee"))
	var elem := String(b.get("damage_element", ""))
	var shape := String(b.get("hit_shape", MoveDB.SHAPE_FAN))
	var reach := float(b.get("range", 120.0))
	var half := deg_to_rad(float(b.get("angle", 90.0)) * 0.5)
	var center := global_position
	if center_override != null:
		center = Vector2(center_override)
	var hit := false
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - center
		var d := to_u.length()
		if d > reach + 18.0:
			continue
		if shape != MoveDB.SHAPE_CIRCLE and center_override == null and d > 1.0:
			if facing.normalized().dot(to_u / d) < cos(half):
				continue
		if deal_damage_to(u, dmg, kind, elem):
			_apply_form_debuff(u, b)
			hit = true
	return hit


func _apply_form_debuff(unit: Node, b: Dictionary) -> void:
	var did := String(b.get("debuff_on_hit", ""))
	if did == "" or not unit.has_method("apply_debuff"):
		return
	unit.call("apply_debuff", did, float(b.get("debuff_time", 3.0)))
