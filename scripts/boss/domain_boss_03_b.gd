class_name DomainBoss03B
extends BossBase
## 赤霄界第 2 位 · 赤霄火正「离照」—— 逐日 · 天火（2026-10-29）
##
## 核心：场上一枚「天火种」可被双方拾取 / 夺取 / 投掷 / 引爆。
##   持种者每 1.6 秒叠 1 层日冕（最多 3 层）；BOSS 持种额外 15% 减伤；
##   3 层后灼心，3 秒后爆裂。八式全部围绕火种转。
##
## 与赫连霄的区别：不靠「行为律法」，靠「持有权争夺」；不攒资源放大招，
## 而是决定「现在抢不抢、什么时候兑现」。

const F_STEP := "form_sun_step"
const F_SLASH := "form_sun_slash"
const F_THROW := "form_sun_throw"
const F_PULL := "form_sun_pull"
const F_WIND := "form_sun_wind"
const F_ECLIPSE := "form_sun_eclipse"
const F_WHEEL := "form_sun_wheel"
const F_METEOR := "form_sun_meteor"

## 连续两次夺火落空 → 火忌：6 秒内四招抢火全部哑火
const GRAB_BAN_ID := "sun_fire_ban"
const GRAB_BAN_TIME := 6.0
const GRAB_FORMS := ["form_sun_step", "form_sun_pull", "form_sun_wind", "form_sun_eclipse"]

const SCORED: Array = [F_STEP, F_SLASH, F_THROW, F_PULL, F_WIND, F_ECLIPSE, F_WHEEL, F_METEOR]

const COOLDOWNS := {
	F_STEP: 8.0, F_SLASH: 7.0, F_THROW: 6.5, F_PULL: 11.0,
	F_WIND: 9.0, F_ECLIPSE: 10.0, F_WHEEL: 13.0, F_METEOR: 18.0,
}

const SEED_FIRST_DELAY := 3.0
const SEED_RESPAWN_P1 := 8.0
const SEED_RESPAWN_P2 := 6.0
const ATK_PER_CROWN := 0.08
const CROWN_DR := 0.85
const VULN_BONUS := 1.15

enum ExtraState { STEP = 100 }

var _phase_two: bool = false
var _cools: Dictionary = {}
var _recent: Array = []
var _decide_wait: float = 0.0
var _current_skill: String = ""

var _seed: SunSeed = null
var _seed_respawn_left: float = SEED_FIRST_DELAY
var _sun_stacks: int = 0
var _vuln_left: float = 0.0
var _sun_pips: SunPips = null
var _aura: Sprite2D = null
var _zones: Array = []
## 连续夺火落空计数：两次就上火忌
var _grab_whiffs: int = 0

var _step_target := Vector2.ZERO
var _step_dir := Vector2.RIGHT
var _step_timer: float = 0.0
var _step_fired: bool = false
## 逐日步落点在前摇第一帧就钉死，整段前摇都是玩家的反应窗口。
var _step_anchor := Vector2.ZERO
var _step_anchor_ready := false


func _setup() -> void:
	boss_id = "boss_03_b"
	_cools.clear()
	_recent.clear()
	_zones.clear()
	_phase_two = false
	_sun_stacks = 0
	_vuln_left = 0.0
	_seed = null
	_seed_respawn_left = SEED_FIRST_DELAY
	_sun_pips = SunPips.new()
	_sun_pips.name = "SunPips"
	_sun_pips.z_index = 12
	add_child(_sun_pips)
	# 背后一层柔和的日冕背光：暗色祭袍在暗石战场上要靠它立起来
	_aura = Sprite2D.new()
	_aura.name = "SunAura"
	_aura.texture = SkillFx.sun_orb_texture()
	_aura.material = SkillFx.additive_material()
	_aura.centered = true
	_aura.position = Vector2(0.0, -58.0)
	_aura.scale = Vector2(1.00, 1.00)
	_aura.modulate = Color(1.0, 0.56, 0.18, 0.24)
	_aura.z_index = -1
	add_child(_aura)
	var atw := _aura.create_tween()
	atw.set_loops()
	atw.tween_property(_aura, "scale", Vector2(1.12, 1.12), 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	atw.parallel().tween_property(_aura, "modulate:a", 0.32, 1.6)
	atw.tween_property(_aura, "scale", Vector2(1.00, 1.00), 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	atw.parallel().tween_property(_aura, "modulate:a", 0.22, 1.6)
	_refresh_pips()


func uses_sun_seed() -> bool:
	return true


func _physics_process(delta: float) -> void:
	if state == BossState.DEAD:
		return
	_tick_cooldowns(delta)
	_tick_seed(delta)
	_tick_zones(delta)
	_tick_pips_position()
	if state == ExtraState.STEP:
		_tick_step(delta)
		return
	super._physics_process(delta)


func _tick_cooldowns(delta: float) -> void:
	_decide_wait = maxf(0.0, _decide_wait - delta)
	_vuln_left = maxf(0.0, _vuln_left - delta)
	for k in _cools.keys():
		_cools[k] = maxf(0.0, float(_cools[k]) - delta)


# ===================== 天火种 =====================

## 只认**自己那颗**火种。
## 旧写法返回组里第一只活着的种子，单打时场上只有一颗所以看不出来；
## 棋局里两只离照（或离照 + 玩家自凝的种子）同场就会串：
## 后落的那只永远 `_find_seed() != null` ⇒ 既不补种、又把 `_seed` 指到别人的火上，
## `_connect_seed` 还把 picked/stolen/consumed 接到两个本体上 ——
## 别人被夺火，这只也会喊「火种被夺！」并把 `_decide_wait` 归零白捡一次出手。
## 归属筛不动拾取规则：`_can_hold` 仍允许任何离照抢火，「争夺」口径保持原样。
func _find_seed() -> SunSeed:
	for raw in get_tree().get_nodes_in_group("sun_seed"):
		var s := raw as SunSeed
		if s == null or not is_instance_valid(s):
			continue
		if s.state == SunSeed.State.GONE:
			continue
		if s.source_boss != self:
			continue
		return s
	return null


func _tick_seed(delta: float) -> void:
	var found := _find_seed()
	if found != _seed:
		_seed = found
		if _seed != null:
			_connect_seed(_seed)
	if _seed != null and is_instance_valid(_seed):
		if _seed.is_held_by(self):
			_sun_stacks = _seed.stacks
		else:
			_sun_stacks = 0
		_refresh_pips()
		return
	_seed = null
	_sun_stacks = 0
	_refresh_pips()
	if _seed_respawn_left > 0.0:
		_seed_respawn_left -= delta
	# 计时到 0 时若场上仍无火种就落一枚（兼容计时器被外部直接归零的情况）
	if _seed_respawn_left <= 0.0 and _find_seed() == null:
		_spawn_seed()


func _connect_seed(seed: SunSeed) -> void:
	if not seed.picked.is_connected(_on_seed_picked):
		seed.picked.connect(_on_seed_picked)
	if not seed.stolen.is_connected(_on_seed_stolen):
		seed.stolen.connect(_on_seed_stolen)
	if not seed.consumed.is_connected(_on_seed_consumed):
		seed.consumed.connect(_on_seed_consumed)


func _spawn_seed() -> void:
	if _find_seed() != null:
		return
	var half := arena_half_extents
	if half.x <= 0.0 or half.y <= 0.0:
		half = Vector2(560.0, 360.0)
	var center := arena_center if arena_center != Vector2.ZERO else global_position
	var best := center
	for i in 10:
		var p := center + Vector2(randf_range(-half.x * 0.55, half.x * 0.55),
			randf_range(-half.y * 0.55, half.y * 0.55))
		p = _clamp_point(p)
		var dp := p.distance_to(_player_pos())
		var db := p.distance_to(global_position)
		if dp >= 120.0 and db >= 140.0:
			best = p
			break
		best = p
	var seed := SunSeed.new()
	get_parent().add_child(seed)
	seed.global_position = best
	seed.source_boss = self
	_seed = seed
	_seed_respawn_left = 0.0
	_connect_seed(seed)
	show_windup_line("天火种降世 —— 抢！", 1.0, 18, 240.0,
		Color(1.0, 0.72, 0.28), -190.0)


func _on_seed_consumed() -> void:
	_seed = null
	_sun_stacks = 0
	_seed_respawn_left = SEED_RESPAWN_P2 if _phase_two else SEED_RESPAWN_P1
	_refresh_pips()


func _on_seed_picked(unit: Node2D) -> void:
	if unit == self:
		show_windup_line("日冕加身！", 0.8, 17, 220.0, Color(1.0, 0.74, 0.30), -186.0)
	else:
		show_windup_line("火种被夺！", 0.8, 17, 220.0, Color(1.0, 0.50, 0.22), -186.0)
		_decide_wait = 0.0


func _on_seed_stolen(unit: Node2D, from: Node2D) -> void:
	if unit == self:
		show_windup_line("夺火！", 0.7, 17, 200.0, Color(1.0, 0.74, 0.30), -186.0)
	elif from == self:
		show_windup_line("火种被夺！", 0.8, 17, 220.0, Color(1.0, 0.46, 0.20), -186.0)
	_decide_wait = 0.0


func on_sun_seed_full(seed: SunSeed) -> void:
	if seed != null and seed.is_held_by(self):
		show_skill_line(String(MoveDB.resolve_boss(F_THROW).get("form_name", "投日")),
			0.7, 18, 230.0,
			BossBase.skill_name_color(_attack_kind_of(F_THROW)), -186.0)
		_decide_wait = 0.0


func on_sun_seed_burst(seed: SunSeed) -> void:
	if seed == null:
		return
	# 持种满层爆裂：BOSS 也吃自己的火（6% 最大气血）
	take_damage(max_hp * float(SunSeed.BOSS_BURST_PCT), null, "elemental", "fire")
	_sun_stacks = 0


func _refresh_pips() -> void:
	if _sun_pips == null or not is_instance_valid(_sun_pips):
		return
	var banned := has_debuff(GRAB_BAN_ID)
	var vis := banned or (_seed != null and is_instance_valid(_seed))
	_sun_pips.visible = vis
	if not vis:
		return
	if banned:
		# 火忌：日轮全灭 + 倒计时，让玩家知道自己换来了 6 秒安全窗
		_sun_pips.marker_color = Color(0.64, 0.82, 1.0, 1.0)
		_sun_pips.set_state(0, "禁%d" % int(ceilf(float(debuffs.get(GRAB_BAN_ID, 0.0)))))
		return
	_sun_pips.marker_color = Color(1.0, 0.62, 0.24, 1.0)
	var marker := ""
	if _seed.is_held_by(self) and _seed.stacks >= SunSeed.MAX_STACKS:
		marker = "灼"
	elif _seed.holder != null and _seed.holder.is_in_group("player"):
		marker = "夺"
	elif _seed.is_free():
		marker = "日"
	_sun_pips.set_state(_sun_stacks, marker)


func _tick_pips_position() -> void:
	if _sun_pips == null or not is_instance_valid(_sun_pips):
		return
	var w := maxf(_sun_pips.size.x, 54.0)
	_sun_pips.position = Vector2(-w * 0.5, head_top_y() - 30.0)


# ===================== 选招 =====================

func _on_chase_reached(_dist: float) -> void:
	_choose()


func _choose() -> void:
	if state != BossState.IDLE and state != BossState.CHASE:
		return
	if _decide_wait > 0.0:
		return
	_decide_wait = 0.3
	var p := _player_node()
	if p == null or BossBase.is_unit_dead(p):
		return
	var d := _dist()
	var seed := _seed
	var holder: Node2D = seed.holder if seed != null and is_instance_valid(seed) else null

	# 0. 二阶段：火种不在自己手里 → 天火坠直接砸火种/玩家
	if _phase_two and _ready_cd(F_METEOR) and seed != null and holder != self and d <= 520.0:
		_begin(F_METEOR)
		return

	# 1. 火种自由：先抢
	if seed != null and seed.is_free():
		var ds := global_position.distance_to(seed.global_position)
		if _ready_cd(F_STEP) and ds <= 380.0:
			_begin(F_STEP)
			return
		if _ready_cd(F_PULL) and ds <= 420.0:
			_begin(F_PULL)
			return

	# 2. 玩家持种：日蚀逼松手 → 逐日步夺火 → 焚风掀种 → 牵日远程抢
	if holder != null and holder.is_in_group("player"):
		if _ready_cd(F_ECLIPSE) and d <= 460.0:
			_begin(F_ECLIPSE)
			return
		if _ready_cd(F_STEP) and d <= 380.0:
			_begin(F_STEP)
			return
		if _ready_cd(F_WIND) and d <= 230.0:
			_begin(F_WIND)
			return
		if _ready_cd(F_PULL) and d <= 420.0:
			_begin(F_PULL)
			return

	# 3. 自己持种：2 层以上赶紧兑现
	if holder == self:
		if _sun_stacks >= 2:
			if _ready_cd(F_THROW) and d <= 520.0:
				_begin(F_THROW)
				return
			if _phase_two and _ready_cd(F_METEOR):
				_begin(F_METEOR)
				return
		if _ready_cd(F_SLASH) and d <= 230.0:
			_begin(F_SLASH)
			return
		if _ready_cd(F_WHEEL) and d <= 480.0:
			_begin(F_WHEEL)
			return

	# 4. 远距先贴人（逐日步也能顺手抢种）
	if d > 280.0 and _ready_cd(F_STEP) and randf() < 0.5:
		_begin(F_STEP)
		return

	# 5. 评分
	var best := ""
	var best_score := -999.0
	for sid in SCORED:
		if not _usable(String(sid)):
			continue
		if not _in_reach(String(sid)):
			continue
		var combo := _combo_bonus(String(sid))
		var sc := _score(String(sid)) + randf() * 1.0 + combo - _repeat_penalty(String(sid))
		if sc > best_score:
			best_score = sc
			best = String(sid)
	if best == "":
		state = BossState.CHASE
		return
	_begin(best)


func _combo_bonus(sid: String) -> float:
	var last := String(_recent[0]) if not _recent.is_empty() else ""
	if last == F_STEP and sid == F_SLASH:
		return 1.6
	if last == F_PULL and sid == F_THROW:
		return 1.5
	if last == F_WIND and sid == F_ECLIPSE:
		return 1.2
	return 0.0


func _usable(sid: String) -> bool:
	if not _ready_cd(sid):
		return false
	var seed := _seed
	var holder: Node2D = seed.holder if seed != null and is_instance_valid(seed) else null
	match sid:
		F_THROW:
			return holder == self
		F_PULL:
			return seed != null and holder != self
		F_ECLIPSE:
			return seed != null and holder != self
		F_METEOR:
			return _phase_two and seed != null and holder != self
	return true


func _ready_cd(sid: String) -> bool:
	# 火忌期间四招抢火全部哑火；伤害招照常
	if sid in GRAB_FORMS and has_debuff(GRAB_BAN_ID):
		return false
	return float(_cools.get(sid, 0.0)) <= 0.0


func _in_reach(sid: String) -> bool:
	var p := _player_node()
	if p == null:
		return false
	var d := global_position.distance_to(p.global_position)
	var seed := _seed
	var ds := global_position.distance_to(seed.global_position) if seed != null else 9999.0
	match sid:
		F_STEP:
			return d <= 520.0
		F_SLASH:
			return d <= 190.0
		F_THROW:
			return d <= 520.0
		F_PULL:
			return ds <= 420.0
		F_WIND:
			# 与扇形判定同距：焚风 230，打不到就不出招，免得白送一次「火忌」计数
			return d <= 230.0
		F_ECLIPSE:
			return d <= 460.0
		F_WHEEL:
			return d <= 480.0
		F_METEOR:
			return d <= 520.0
	return true


func _score(sid: String) -> float:
	var p := _player_node()
	var d := global_position.distance_to(p.global_position) if p != null else 9999.0
	var seed := _seed
	var holder: Node2D = seed.holder if seed != null and is_instance_valid(seed) else null
	match sid:
		F_STEP:
			return 2.6 + (1.4 if seed != null and holder != self else 0.0)
		F_SLASH:
			return 3.2 - absf(d - 100.0) / 150.0 + (0.5 if holder == self else 0.0)
		F_THROW:
			return 3.0 + (0.8 if holder == self else 0.0)
		F_PULL:
			return 2.8 + (0.8 if holder != null and holder != self else 0.0)
		F_WIND:
			return 2.7 - absf(d - 100.0) / 180.0
		F_ECLIPSE:
			return 2.5 + (1.0 if holder != null and holder.is_in_group("player") else 0.0)
		F_WHEEL:
			return 2.2
		F_METEOR:
			return 2.8
	return 0.5


func _repeat_penalty(sid: String) -> float:
	if _recent.size() >= 2 and String(_recent[0]) == sid and String(_recent[1]) == sid:
		return 99.0
	if _recent.size() >= 1 and String(_recent[0]) == sid:
		return 2.0
	return 0.0


func _record(sid: String) -> void:
	if sid == "":
		return
	_recent.push_front(sid)
	if _recent.size() > 3:
		_recent.resize(3)
	var b := MoveDB.resolve_boss(sid)
	var cd := float(b.get("cooldown_p1", COOLDOWNS.get(sid, 8.0)))
	if phase >= 2:
		cd = float(b.get("cooldown_p2", cd))
	_cools[sid] = cd


# ===================== 出招 =====================

func _begin(sid: String) -> void:
	if is_skill_locked():
		return
	_current_skill = sid
	state = BossState.WINDUP
	var b := MoveDB.resolve_boss(sid)
	var windup := maxf(0.2, float(b.get("windup", 0.7)))
	if phase >= 2:
		windup *= float(b.get("windup_mult_p2", 1.0))
	state_timer = windup
	_play_form_anim(sid, state_timer + 0.15)
	var p := _player_node()
	if p != null:
		_set_facing((p.global_position - global_position).normalized())
	_step_anchor_ready = false
	# 逐日步：前摇第一帧就把落点钉死，并用黑日预警圈把落点画给玩家看；
	# 整段前摇 + 0.18 秒突进都是反应窗口，站着不动才会被夺火。
	if sid == F_STEP and p != null:
		var goal := p.global_position
		if _seed != null and is_instance_valid(_seed) and _seed.is_free():
			goal = _seed.global_position
		var to := goal - global_position
		var dir := to.normalized() if to.length() > 1.0 else facing
		_step_anchor = _clamp_point(goal - dir * 36.0)
		_step_anchor_ready = true
		SkillFx.sun_warn_at(get_parent(), _step_anchor,
			float(b.get("range", 110.0)), windup + float(b.get("dash_time", 0.18)))
	# 招名在前摇第一帧出现，只报招名，不带应对提示
	var fname := String(b.get("form_name", ""))
	var hold := state_timer
	if sid == F_ECLIPSE:
		hold += float(b.get("delay", 0.45))
	elif sid == F_METEOR:
		hold += float(b.get("delay", 0.55))
	show_skill_line(fname, hold, 18, 250.0,
		BossBase.skill_name_color(String(b.get("attack_kind", ""))), -190.0)


func _fire_attack() -> void:
	_fire_skill()


func _fire_skill() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	var b := MoveDB.resolve_boss(_current_skill)
	if b.is_empty():
		_finish_skill()
		return
	match _current_skill:
		F_STEP:
			_cast_step(b)
		F_SLASH:
			_cast_slash(b)
		F_THROW:
			_cast_throw(b)
		F_PULL:
			_cast_pull(b)
		F_WIND:
			_cast_wind(b)
		F_ECLIPSE:
			_cast_eclipse(b)
		F_WHEEL:
			_cast_wheel(b)
		F_METEOR:
			_cast_meteor(b)
		_:
			_finish_skill()


func _finish_skill() -> void:
	_record(_current_skill)
	_current_skill = ""
	state = BossState.RECOVER
	state_timer = 0.45


func _sun_atk() -> float:
	return attack_power * (1.0 + ATK_PER_CROWN * float(_sun_stacks))


func _move_damage(sid: String, b: Dictionary, extra: float = 0.0) -> float:
	var dmg := MoveDB.boss_damage(sid, _sun_atk(), phase)
	if extra > 0.0:
		dmg *= (1.0 + extra)
	return dmg


func _deal_circle(pos: Vector2, radius: float, dmg: float, kind: String,
		elem: String, debuff_id: String = "", debuff_time: float = 0.0) -> void:
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var d := (u as Node2D).global_position.distance_to(pos)
		if d > radius + 18.0:
			continue
		deal_damage_to(u, dmg, kind, elem)
		if debuff_id != "" and u.has_method("apply_debuff"):
			u.call("apply_debuff", debuff_id, debuff_time)


func _deal_cone(reach: float, angle_deg: float, dmg: float, kind: String,
		elem: String, debuff_id: String = "", debuff_time: float = 0.0) -> void:
	var dir := facing.normalized()
	var half := deg_to_rad(angle_deg * 0.5)
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to: Vector2 = (u as Node2D).global_position - global_position
		var d := to.length()
		if d > reach + 18.0:
			continue
		if d > 1.0 and dir.dot(to / d) < cos(half):
			continue
		deal_damage_to(u, dmg, kind, elem)
		if debuff_id != "" and u.has_method("apply_debuff"):
			u.call("apply_debuff", debuff_id, debuff_time)


func _deal_line(reach: float, width: float, dmg: float, kind: String,
		elem: String) -> void:
	var a := global_position
	var b := global_position + facing.normalized() * reach
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if _point_segment_distance((u as Node2D).global_position, a, b) <= width * 0.5 + 16.0:
			deal_damage_to(u, dmg, kind, elem)


func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 与 _deal_cone 完全同一套判定：位置在扇形里才算「被扫到」
func _in_cone(pos: Vector2, reach: float, angle_deg: float) -> bool:
	var to: Vector2 = pos - global_position
	var d := to.length()
	if d > reach + 18.0:
		return false
	if d <= 1.0:
		return true
	return facing.normalized().dot(to / d) >= cos(deg_to_rad(angle_deg * 0.5))


## 玩家靠走位躲开了这一发的火种结算，给一条明确回执；连续两次就上火忌
func _seed_whiff(form_name: String, msg: String) -> void:
	if has_debuff(GRAB_BAN_ID):
		return
	_grab_whiffs += 1
	if _grab_whiffs >= 2:
		_apply_grab_ban()
		return
	show_skill_line(form_name + " · " + msg, 0.75, 16, 220.0,
		Color(0.55, 0.86, 0.62), -186.0)


## 火忌：连续两次抢火落空，火种拒绝他 6 秒
func _apply_grab_ban() -> void:
	_grab_whiffs = 0
	apply_debuff(GRAB_BAN_ID, GRAB_BAN_TIME)
	show_windup_line("火忌 · 6 秒夺不了火！", 1.4, 18, 250.0,
		Color(0.72, 0.88, 1.0), -186.0)


## 任意一招真的把火抢到手 / 掀落 / 烧掉，连续落空归零
func _grab_landed() -> void:
	_grab_whiffs = 0


func _cast_step(b: Dictionary) -> void:
	var p := _player_node()
	if p == null:
		_finish_skill()
		return
	# 前摇第一帧已经锁过落点：玩家在那段时间里走开，这一发就扑空
	if _step_anchor_ready:
		var to_a := _step_anchor - global_position
		_step_dir = to_a.normalized() if to_a.length() > 1.0 else facing
		_step_target = _step_anchor
	else:
		var goal := p.global_position
		var seed := _seed
		if seed != null and is_instance_valid(seed) and seed.is_free():
			goal = seed.global_position
		var to := goal - global_position
		_step_dir = to.normalized() if to.length() > 1.0 else facing
		_step_target = _clamp_point(goal - _step_dir * 36.0)
	_step_timer = 0.18
	_step_fired = false
	state = ExtraState.STEP
	var tw := create_tween()
	tw.tween_property(anim, "modulate:a", 0.0, 0.08)


func _tick_step(delta: float) -> void:
	_step_timer -= delta
	if _step_timer <= 0.10 and not _step_fired:
		_step_fired = true
		global_position = _step_target
		var tw := create_tween()
		tw.tween_property(anim, "modulate:a", 1.0, 0.02)
	if _step_timer > 0.0:
		return
	var b := MoveDB.resolve_boss(F_STEP)
	var dmg := _move_damage(F_STEP, b)
	SkillFx.play_at_strike(self, "skill_sun_step", b, _step_dir, null)
	_deal_circle(global_position, float(b.get("range", 110.0)), dmg, "physical_melee", "")
	var seed := _seed
	var steal_reach := float(b.get("steal_range", 130.0))
	if seed != null and is_instance_valid(seed):
		if seed.is_free() and global_position.distance_to(seed.global_position) <= 120.0:
			seed.pickup(self)
		elif seed.holder != null and seed.holder.is_in_group("player"):
			if global_position.distance_to((seed.holder as Node2D).global_position) <= steal_reach:
				seed.steal_by(self)
				_grab_landed()
			else:
				_seed_whiff("逐日步", "夺火落空！")
	_vuln_left = float(b.get("vulnerable_after", 0.7))
	_finish_skill()


func _cast_slash(b: Dictionary) -> void:
	var holding := _seed != null and is_instance_valid(_seed) and _seed.is_held_by(self)
	var dmg := _move_damage(F_SLASH, b,
		float(b.get("seed_bonus", 0.25)) if holding else 0.0)
	SkillFx.play_at_strike(self, "skill_sun_slash", b, facing, null)
	_deal_cone(float(b.get("range", 190.0)), float(b.get("angle", 110.0)),
		dmg, "elemental", "fire",
		"sunburn" if holding else "", float(b.get("debuff_time", 3.0)))
	_finish_skill()


func _cast_throw(b: Dictionary) -> void:
	var seed := _seed
	if seed == null or not is_instance_valid(seed) or not seed.is_held_by(self):
		_finish_skill()
		return
	var p := _player_node()
	if p == null:
		_finish_skill()
		return
	var target := p.global_position
	var dmg := _move_damage(F_THROW, b)
	var dist := global_position.distance_to(target)
	var fly_time := clampf(dist / 1400.0, 0.18, 0.32)
	seed.fly_to(target, fly_time, clampf(dist * 0.10, 18.0, 48.0), self)
	SkillFx.sun_tether(get_parent(), global_position, target, Color(1.0, 0.62, 0.22), fly_time)
	get_tree().create_timer(fly_time, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or state == BossState.DEAD:
				return
			SkillFx.play_at_strike(self, "skill_sun_throw", b, facing, target)
			_deal_circle(target, 100.0, dmg, "elemental", "fire",
				"sunburn", float(b.get("debuff_time", 3.0))))
	_finish_skill()


func _cast_pull(b: Dictionary) -> void:
	var seed := _seed
	if seed == null or not is_instance_valid(seed) or seed.is_held_by(self):
		_finish_skill()
		return
	var reach := float(b.get("steal_range", 420.0))
	if global_position.distance_to(seed.global_position) > reach:
		_finish_skill()
		return
	var dmg := _move_damage(F_PULL, b)
	SkillFx.sun_tether(get_parent(), seed.global_position, global_position,
		Color(1.0, 0.72, 0.30), 0.35)
	SkillFx.play_at_strike(self, "skill_sun_pull", b, facing, null)
	var width := float(b.get("width", 50.0))
	_deal_line(reach, width, dmg, "elemental", "fire")
	# 金丝走廊在出手瞬间就定了；0.2 秒后持有者还在这条里才夺火，侧移出去就拉住失败
	var origin := global_position
	var line_dir := facing.normalized()
	var half_w := width * 0.5 + 16.0
	get_tree().create_timer(0.20, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or state == BossState.DEAD:
				return
			if not is_instance_valid(seed):
				return
			if seed.holder != null and is_instance_valid(seed.holder) \
					and seed.holder.is_in_group("player"):
				if _point_segment_distance((seed.holder as Node2D).global_position,
						origin, origin + line_dir * reach) <= half_w:
					seed.steal_by(self)
					_grab_landed()
				else:
					_seed_whiff("牵日", "没拉住！")
			elif global_position.distance_to(seed.global_position) <= reach + 40.0:
				seed.steal_by(self)
				_grab_landed())
	_vuln_left = float(b.get("vulnerable_after", 0.5))
	_finish_skill()


func _cast_wind(b: Dictionary) -> void:
	var dmg := _move_damage(F_WIND, b)
	SkillFx.play_at_strike(self, "skill_sun_wind", b, facing, null)
	var reach := float(b.get("range", 230.0))
	var angle := float(b.get("angle", 90.0))
	# 掀种只认正中 60°（扇形外沿照样吃伤害与击退）—— 侧移就能把火种保住
	var knock_angle := float(b.get("seed_knock_angle", 60.0))
	_deal_cone(reach, angle, dmg, "elemental", "fire")
	var seed := _seed
	if seed != null and is_instance_valid(seed):
		if seed.holder != null and seed.holder.is_in_group("player"):
			if _in_cone((seed.holder as Node2D).global_position, reach, knock_angle):
				seed.fly_to(seed.holder.global_position + facing.normalized() * 140.0, 0.20, 28.0, self)
				_grab_landed()
			else:
				_seed_whiff("焚风", "没掀掉！")
		elif seed.is_free() and _in_cone(seed.global_position, reach, knock_angle):
			seed.fly_to(seed.global_position + facing.normalized() * 120.0, 0.18, 22.0, self)
	for u in attack_units():
		if u != null and is_instance_valid(u) and u.is_in_group("player") \
				and u.has_method("take_knockback"):
			var away: Vector2 = (u.global_position - global_position).normalized()
			u.call("take_knockback", away * float(b.get("knockback", 300.0)))
	_finish_skill()


func _cast_eclipse(b: Dictionary) -> void:
	var seed := _seed
	if seed == null or not is_instance_valid(seed) or seed.is_held_by(self):
		_finish_skill()
		return
	var target := seed.global_position
	if seed.holder != null and seed.holder.is_in_group("player"):
		target = seed.holder.global_position
	var delay := float(b.get("delay", 0.55))
	var radius := float(b.get("range", 140.0))
	# 烧掉火种只要 0.72 半径（101）：走 0.55 秒（约 121 像素）就保得住，
	# 想连伤害一起吃掉则要出 140+18 的整圈。
	var keep := radius * 0.72
	var dmg := _move_damage(F_ECLIPSE, b)
	SkillFx.sun_warn_at(get_parent(), target, radius, delay)
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or state == BossState.DEAD:
				return
			SkillFx.play_at_strike(self, "skill_sun_eclipse", b, facing, target)
			SkillFx.sun_burst_at(get_parent(), target, radius, 0.85, 0.55)
			_deal_circle(target, radius, dmg, "elemental", "fire",
				"sunburn", float(b.get("debuff_time", 3.0)))
			var s2 := _seed
			if s2 == null or not is_instance_valid(s2) or s2.is_held_by(self):
				return
			if s2.is_free():
				if s2.global_position.distance_to(target) <= keep:
					s2.consume()
			elif s2.holder != null and is_instance_valid(s2.holder) \
					and s2.holder.is_in_group("player"):
				# 黑日预警圈画的是 140，烧掉火种只要在 0.72 半径内；提前跨出就保得住
				if (s2.holder as Node2D).global_position.distance_to(target) <= keep:
					s2.consume()
					_grab_landed()
				else:
					_seed_whiff("日蚀", "没烧掉！"))
	_finish_skill()


func _cast_wheel(b: Dictionary) -> void:
	var seed := _seed
	var target := _player_pos()
	if seed != null and is_instance_valid(seed) and not seed.is_held_by(self):
		target = seed.global_position
	SkillFx.play_at_strike(self, "skill_sun_wheel", b, facing, target)
	var zone := {
		"pos": target,
		"radius": float(b.get("range", 130.0)),
		"left": float(b.get("duration", 4.5)),
		"tick": 0.0,
		"interval": float(b.get("tick_interval", 1.5)),
		"dmg": _move_damage(F_WHEEL, b),
		"debuff": "sunburn",
		"debuff_time": float(b.get("debuff_time", 2.0)),
		"pull": bool(b.get("pull_seed", true)),
	}
	_zones.append(zone)
	_finish_skill()


func _cast_meteor(b: Dictionary) -> void:
	var seed := _seed
	var target := _player_pos()
	if seed != null and is_instance_valid(seed) and not seed.is_held_by(self):
		target = seed.global_position
	var delay := float(b.get("delay", 0.55))
	var radius := float(b.get("range", 180.0))
	var holding := _seed != null and is_instance_valid(_seed) and _seed.is_held_by(self)
	var dmg := _move_damage(F_METEOR, b,
		float(b.get("seed_bonus", 0.25)) if holding else 0.0)
	SkillFx.sun_warn_at(get_parent(), target, radius, delay)
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or state == BossState.DEAD:
				return
			SkillFx.play_at_strike(self, "skill_sun_meteor", b, facing, target)
			SkillFx.sun_burst_at(get_parent(), target, radius, 0.95, 0.7)
			_deal_circle(target, radius, dmg, "elemental", "fire",
				"sunburn", float(b.get("debuff_time", 4.0)))
			var burn := {
				"pos": target,
				"radius": radius * 0.75,
				"left": float(b.get("ground_burn_time", 4.0)),
				"tick": 0.0,
				"interval": float(b.get("ground_burn_tick", 1.0)),
				"dmg": attack_power * float(b.get("ground_burn_coeff", 0.25)),
				"debuff": "",
				"debuff_time": 0.0,
				"pull": false,
			}
			_zones.append(burn))
	_finish_skill()


func _tick_zones(delta: float) -> void:
	if _zones.is_empty():
		return
	var keep: Array = []
	for raw in _zones:
		var z: Dictionary = raw
		z["left"] = float(z.get("left", 0.0)) - delta
		z["tick"] = float(z.get("tick", 0.0)) - delta
		if float(z["tick"]) <= 0.0 and float(z["left"]) > 0.0:
			z["tick"] = float(z.get("interval", 1.0))
			_deal_circle(z["pos"], float(z.get("radius", 130.0)),
				float(z.get("dmg", 0.0)), "elemental", "fire",
				String(z.get("debuff", "")), float(z.get("debuff_time", 0.0)))
			if bool(z.get("pull", false)):
				var s := _seed
				if s != null and is_instance_valid(s) and s.is_free():
					s.pull_toward(z["pos"], 70.0)
		if float(z["left"]) > 0.0:
			keep.append(z)
	_zones = keep


# ===================== 承伤 / 阶段 / 杂项 =====================

func damage_taken_multiplier(_damage_kind: String) -> float:
	var m := 1.0
	var seed := _seed
	if seed != null and is_instance_valid(seed) and seed.is_held_by(self):
		m *= CROWN_DR
	if _vuln_left > 0.0:
		m *= VULN_BONUS
	return m


func after_damage_taken(amount: float) -> void:
	# 聚雷类打断不存在；这里只给「日轮/天火」留钩子，当前不需要额外处理。
	pass


func on_parried(source: Node) -> void:
	var seed := _seed
	if seed != null and is_instance_valid(seed) and seed.is_held_by(self):
		seed.fly_to(global_position + facing.normalized() * 70.0, 0.16, 16.0, self)
		show_windup_line("弹反 · 火种脱手！", 0.9, 18, 240.0,
			Color(1.0, 0.72, 0.28), -186.0)
	super.on_parried(source)


func _on_phase_two() -> void:
	_phase_two = true
	_seed_respawn_left = minf(_seed_respawn_left, 4.0)
	show_windup_line("二阶段 · 天火坠加入出招！", 1.4, 20, 270.0,
		Color(1.0, 0.58, 0.22), -190.0)
	_decide_wait = 0.0
	_cools[F_METEOR] = 0.0


## 受击球压到地面平面（y=0）：玩家攻击的距离/夹角按俯视地面算。
## 场景里的上/中/下三排球保留原始 y 给物理碰撞；若不投影，贴身横砍会被算成斜向上而漏判。
func hit_spheres() -> Array:
	var out := super.hit_spheres()
	for i in range(out.size()):
		var sv: Vector3 = out[i]
		out[i] = Vector3(sv.x, 0.0, sv.z)
	return out


func _die() -> void:
	if _seed != null and is_instance_valid(_seed):
		_seed.consume()
	_zones.clear()
	super._die()


func _exit_tree() -> void:
	if _seed != null and is_instance_valid(_seed):
		_seed.queue_free()
	_zones.clear()


func _player_node() -> Node2D:
	# 阵营安全读数：召唤出来的友军离照绝不能把玩家当对手（2026-11-02 用户报）
	return opponent_node()


func _player_pos() -> Vector2:
	var p := _player_node()
	return p.global_position if p != null else global_position + facing * 160.0


func _dist() -> float:
	var p := _player_node()
	return global_position.distance_to(p.global_position) if p != null else 9999.0


func _clamp_point(pos: Vector2) -> Vector2:
	if arena_half_extents == Vector2.ZERO:
		return pos
	var half := arena_half_extents - Vector2(arena_margin, arena_margin)
	var c := arena_center
	return Vector2(clampf(pos.x, c.x - half.x, c.x + half.x),
		clampf(pos.y, c.y - half.y, c.y + half.y))
