class_name DomainBoss03C
extends BossBase
## 赤霄界第 3 位 · 赤霄劫主「晏无咎」—— 三灾 · 轮转（2026-10-29）
##
## 风 / 火 / 雷三方相克；BOSS 与玩家各有灾位。
##   玩家用克位功法命中 → 破灾：BOSS 灾崩、玩家 +1 灾势；
##   同灾位命中 → 伤害变低、BOSS +1 灾势；
##   BOSS 用克位命中玩家 → 玩家受伤加重、锁灾。
## 二阶段「三灾归一」8 秒：三灾同身、无法破灾、BOSS 受伤 +20%。

const F_STEP := "form_calamity_step"
const F_SLASH := "form_calamity_slash"
const F_FIRE_SEAL := "form_calamity_fire_seal"
const F_FIRE_FIELD := "form_calamity_fire_field"
const F_THUNDER_STRIKE := "form_calamity_thunder_strike"
const F_THUNDER_POOL := "form_calamity_thunder_pool"
const F_TURN := "form_calamity_turn"
const F_FINAL := "form_calamity_final"

const SCORED: Array = [F_STEP, F_SLASH, F_FIRE_SEAL, F_FIRE_FIELD,
	F_THUNDER_STRIKE, F_THUNDER_POOL, F_FINAL]

const COOLDOWNS := {
	F_STEP: 7.0, F_SLASH: 7.0, F_FIRE_SEAL: 8.0, F_FIRE_FIELD: 12.0,
	F_THUNDER_STRIKE: 9.0, F_THUNDER_POOL: 13.0, F_TURN: 9.0, F_FINAL: 22.0,
}

const CAL_WIND := "wind"
const CAL_FIRE := "fire"
const CAL_THUNDER := "thunder"
const CAL_FUSION := "fusion"
const MAX_MOMENTUM := 3
const AUTO_TURN := 8.0
const AUTO_TURN_P2 := 5.0
const FUSION_TIME := 8.0
const BREAK_TIME := 3.0
const BREAK_CD := 1.2

enum ExtraState { STEP = 100 }

var _phase_two: bool = false
var _cools: Dictionary = {}
var _recent: Array = []
var _decide_wait: float = 0.0
var _current_skill: String = ""

var _calamity: String = CAL_WIND
var _momentum: int = 0
var _broken_left: float = 0.0
var _break_cd: float = 0.0
var _auto_turn_left: float = AUTO_TURN
var _fusion_left: float = 0.0
var _turn_guard_left: float = 0.0
var _zones: Array = []

var _step_target := Vector2.ZERO
var _step_dir := Vector2.RIGHT
var _step_timer: float = 0.0
var _step_fired: bool = false

var _wheel_ui: CalamityWheel = null
var _wheel_fx: Sprite2D = null
var _aura: Sprite2D = null


func _setup() -> void:
	boss_id = "boss_03_c"
	_cools.clear()
	_recent.clear()
	_zones.clear()
	_phase_two = false
	_calamity = CAL_WIND
	_momentum = 0
	_broken_left = 0.0
	_break_cd = 0.0
	_auto_turn_left = AUTO_TURN
	_fusion_left = 0.0
	_turn_guard_left = 0.0
	_wheel_ui = CalamityWheel.new()
	_wheel_ui.name = "CalamityWheel"
	_wheel_ui.large = true
	_wheel_ui.z_index = 12
	add_child(_wheel_ui)
	_build_wheel_fx()
	_refresh_hud()


func _build_wheel_fx() -> void:
	var tex := SkillFx.skill_texture("calamity_wheel")
	if tex == null:
		tex = SkillFx.ring_texture()
	_wheel_fx = Sprite2D.new()
	_wheel_fx.name = "CalamityWheelFX"
	_wheel_fx.texture = tex
	_wheel_fx.centered = true
	_wheel_fx.material = SkillFx.additive_material()
	# 512² 的术法轮不能按世界像素 1:1 摆：那会在 165px 高的 BOSS 背后铺出
	# 一整屏的环，和 rig 自带的三段劫环叠成六重。这里压到 0.32，
	# 只当「当前灾位」的色光底，真正的轮转交给 rig 的三段环。
	_wheel_fx.position = Vector2(0.0, -70.0)
	_wheel_fx.scale = Vector2(0.32, 0.32)
	_wheel_fx.modulate = Color(0.62, 0.82, 0.78, 0.10)
	_wheel_fx.z_index = -2
	add_child(_wheel_fx)
	_aura = Sprite2D.new()
	_aura.texture = SkillFx.dot_texture()
	_aura.centered = true
	_aura.material = SkillFx.additive_material()
	_aura.position = Vector2(0.0, -46.0)
	_aura.scale = Vector2(0.62, 0.62)
	_aura.modulate = Color(0.70, 0.66, 0.86, 0.08)
	_aura.z_index = -3
	add_child(_aura)
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_wheel_fx, "rotation", TAU, 18.0)


func _physics_process(delta: float) -> void:
	if state == BossState.DEAD:
		return
	_tick_cooldowns(delta)
	_tick_calamity(delta)
	_tick_zones(delta)
	_tick_hud_position()
	if state == ExtraState.STEP:
		_tick_step(delta)
		return
	super._physics_process(delta)


func _tick_cooldowns(delta: float) -> void:
	_decide_wait = maxf(0.0, _decide_wait - delta)
	for k in _cools.keys():
		_cools[k] = maxf(0.0, float(_cools[k]) - delta)


func _tick_calamity(delta: float) -> void:
	_break_cd = maxf(0.0, _break_cd - delta)
	_broken_left = maxf(0.0, _broken_left - delta)
	_turn_guard_left = maxf(0.0, _turn_guard_left - delta)
	if _fusion_left > 0.0:
		_fusion_left = maxf(0.0, _fusion_left - delta)
		if _fusion_left <= 0.0:
			_end_fusion()
	else:
		if _broken_left <= 0.0 and not has_debuff("suo_zai"):
			_auto_turn_left = maxf(0.0, _auto_turn_left - delta)
			if _auto_turn_left <= 0.0 and _ready_cd(F_TURN) \
					and (state == BossState.IDLE or state == BossState.CHASE):
				_begin(F_TURN)
	_refresh_hud()
	_refresh_wheel_visual()


func _end_fusion() -> void:
	_calamity = _counter_of(_player_element())
	_momentum = mini(MAX_MOMENTUM, _momentum + 1)
	_auto_turn_left = AUTO_TURN_P2
	show_windup_line("三灾归一结束 —— 灾轮加速！", 1.2, 19, 260.0,
		Color(0.92, 0.84, 0.72), -190.0)
	_refresh_hud()


func calamity_state() -> String:
	return CAL_FUSION if _fusion_left > 0.0 else _calamity


func calamity_momentum() -> int:
	return _momentum


func gain_calamity_momentum(n: int) -> void:
	_momentum = clampi(_momentum + n, 0, MAX_MOMENTUM)
	_refresh_hud()


func is_calamity_broken() -> bool:
	return _broken_left > 0.0


## 玩家用克位功法命中时调用；返回 true 表示这次真的破灾（玩家可 +1 灾势）
func on_calamity_broken(_source: Node) -> bool:
	if _fusion_left > 0.0 or _broken_left > 0.0 or _break_cd > 0.0:
		return false
	_break_cd = BREAK_CD
	_broken_left = BREAK_TIME
	_momentum = maxi(0, _momentum - 1)
	if _current_skill == F_TURN:
		_current_skill = ""
		state = BossState.STAGGER
		state_timer = 0.7
		if skin != null:
			skin.cancel_one_shot()
		show_windup_line("轮转被打断 · 灾崩！", 0.9, 19, 240.0,
			Color(1.0, 0.76, 0.30), -186.0)
	else:
		stagger_for(0.45)
		show_windup_line("灾崩！", 0.7, 18, 210.0,
			Color(1.0, 0.76, 0.30), -186.0)
	_refresh_hud()
	return true


func on_calamity_lock(seconds: float) -> void:
	apply_debuff("suo_zai", seconds)
	if _current_skill == F_TURN:
		_current_skill = ""
		state = BossState.STAGGER
		state_timer = 0.6
		if skin != null:
			skin.cancel_one_shot()
		show_windup_line("灾轮被锁！", 0.8, 18, 220.0,
			Color(0.84, 0.78, 0.98), -186.0)
	_refresh_hud()


func _refresh_hud() -> void:
	if _wheel_ui == null or not is_instance_valid(_wheel_ui):
		return
	var marker := ""
	if _fusion_left > 0.0:
		marker = "乱"
	elif _broken_left > 0.0:
		marker = "崩"
	elif has_debuff("suo_zai"):
		marker = "锁"
	_wheel_ui.set_state(calamity_state(), _momentum, marker)


func _refresh_wheel_visual() -> void:
	if _wheel_fx == null or not is_instance_valid(_wheel_fx):
		return
	var col := _calamity_color(calamity_state())
	_wheel_fx.modulate = Color(col.r, col.g, col.b, 0.12 if _broken_left <= 0.0 else 0.05)
	if _aura != null:
		_aura.modulate = Color(col.r, col.g, col.b, 0.10 if _broken_left <= 0.0 else 0.04)


## 背后三段劫环（760px 贴图）比身体高得多，直接按 Sprite2D 顶边算会把血条/
## 飘字顶到环顶上去。这里以「身体头顶」封顶：环是背景，不是头饰。
func head_top_y() -> float:
	return maxf(super.head_top_y(), -78.0)


func _tick_hud_position() -> void:
	if _wheel_ui == null or not is_instance_valid(_wheel_ui):
		return
	var w := maxf(_wheel_ui.size.x, 84.0)
	_wheel_ui.position = Vector2(-w * 0.5, head_top_y() - 34.0)


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
	var player_el := _player_element()

	if _fusion_left > 0.0:
		# 三灾归一：全招池；末日权重高但不强制
		if _ready_cd(F_FINAL) and _momentum >= 1 and d <= 520.0:
			_begin(F_FINAL)
			return
		var best_f := ""
		var best_fs := -999.0
		for sid in SCORED:
			if not _ready_cd(String(sid)) or not _in_reach(String(sid)):
				continue
			var sc := _score(String(sid)) + randf()
			if sc > best_fs:
				best_fs = sc
				best_f = String(sid)
		if best_f != "":
			_begin(best_f)
		else:
			state = BossState.CHASE
		return

	# 被玩家克：轮转逃灾（锁灾时逃不了，只能打）
	if _calamity_beats(player_el, _calamity) \
			and _ready_cd(F_TURN) and not has_debuff("suo_zai"):
		_begin(F_TURN)
		return
	# 灾势 ≥2：万劫归一兑现
	# 二阶段灾轮转得更快，归一门槛从 2 层降到 1 层：不是加数值，而是更频繁地兑现灾势。
	var final_need := 1 if phase >= 2 else 2
	if _momentum >= final_need and _ready_cd(F_FINAL) and d <= 520.0:
		_begin(F_FINAL)
		return
	# 同灾位：玩家在喂灾，优先用罚招
	if player_el == _calamity and _ready_cd(F_FINAL) and d <= 520.0:
		_begin(F_FINAL)
		return

	# 当前灾位对应的两式 + 通用的步/斩
	var pool := _element_pool(_calamity)
	var best := ""
	var best_score := -999.0
	for sid in pool:
		if not _usable(String(sid)) or not _in_reach(String(sid)):
			continue
		var sc := _score(String(sid)) + randf() + _combo_bonus(String(sid))
		sc -= _repeat_penalty(String(sid))
		if sc > best_score:
			best_score = sc
			best = String(sid)
	if best == "":
		state = BossState.CHASE
		return
	_begin(best)


func _element_pool(el: String) -> Array:
	match el:
		CAL_WIND:
			return [F_STEP, F_SLASH]
		CAL_FIRE:
			return [F_FIRE_SEAL, F_FIRE_FIELD]
		CAL_THUNDER:
			return [F_THUNDER_STRIKE, F_THUNDER_POOL]
	return [F_STEP, F_SLASH]


func _combo_bonus(sid: String) -> float:
	var last := String(_recent[0]) if not _recent.is_empty() else ""
	if last == F_STEP and sid == F_SLASH:
		return 1.2
	if last == F_FIRE_SEAL and sid == F_FIRE_FIELD:
		return 1.2
	if last == F_THUNDER_STRIKE and sid == F_THUNDER_POOL:
		return 1.2
	if last == F_TURN and sid == F_FINAL:
		return 1.6
	return 0.0


func _usable(sid: String) -> bool:
	if not _ready_cd(sid):
		return false
	if sid == F_FINAL:
		return _momentum >= 1
	if sid == F_TURN:
		return _fusion_left <= 0.0 and not has_debuff("suo_zai") and _broken_left <= 0.0
	if _fusion_left <= 0.0:
		var tag := _form_tag(sid)
		if tag != "" and String(tag) != _calamity:
			return false
	return true


func _form_tag(sid: String) -> String:
	var b := MoveDB.resolve_boss(sid)
	return String(b.get("calamity_tag", ""))


func _ready_cd(sid: String) -> bool:
	return float(_cools.get(sid, 0.0)) <= 0.0


func _in_reach(sid: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var d := _dist()
	match sid:
		F_STEP:
			return d <= 460.0
		F_SLASH:
			return d <= 240.0
		F_FIRE_SEAL:
			return d <= 460.0
		F_FIRE_FIELD:
			return d <= 460.0
		F_THUNDER_STRIKE:
			return d <= 520.0
		F_THUNDER_POOL:
			return d <= 460.0
		F_TURN:
			return d <= 520.0
		F_FINAL:
			return d <= 520.0
	return true


func _score(sid: String) -> float:
	var d := _dist()
	match sid:
		F_STEP:
			return 2.6 - absf(d - 250.0) / 300.0
		F_SLASH:
			return 3.1 - absf(d - 100.0) / 160.0
		F_FIRE_SEAL:
			return 2.6 - absf(d - 300.0) / 240.0
		F_FIRE_FIELD:
			return 2.4 - absf(d - 220.0) / 220.0
		F_THUNDER_STRIKE:
			return 2.8 - absf(d - 300.0) / 240.0
		F_THUNDER_POOL:
			return 2.3 - absf(d - 180.0) / 220.0
		F_TURN:
			return 1.4
		F_FINAL:
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
	var fname := String(b.get("form_name", ""))
	var hold := state_timer
	if sid == F_FINAL or sid == F_FIRE_SEAL or sid == F_THUNDER_STRIKE:
		hold += float(b.get("delay", 0.35))
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
		F_FIRE_SEAL:
			_cast_fire_seal(b)
		F_FIRE_FIELD:
			_cast_fire_field(b)
		F_THUNDER_STRIKE:
			_cast_thunder_strike(b)
		F_THUNDER_POOL:
			_cast_thunder_pool(b)
		F_TURN:
			_cast_turn(b)
		F_FINAL:
			_cast_final(b)
		_:
			_finish_skill()


func _finish_skill() -> void:
	_record(_current_skill)
	_current_skill = ""
	state = BossState.RECOVER
	state_timer = 0.45


func _cast_step(b: Dictionary) -> void:
	var p := _player_node()
	if p == null:
		_finish_skill()
		return
	var dir := (p.global_position - global_position).normalized()
	_step_dir = dir
	_step_target = _clamp_point(p.global_position - dir * 36.0)
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
	var dmg := MoveDB.boss_damage(F_STEP, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_calamity_step", b, _step_dir, null)
	_deal_circle(global_position, 110.0, dmg, "physical_melee", "")
	_finish_skill()


func _cast_slash(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(F_SLASH, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_calamity_slash", b, facing, null)
	_deal_cone(float(b.get("range", 190.0)), float(b.get("angle", 100.0)),
		dmg, "physical_melee", "")
	_finish_skill()


func _cast_fire_seal(b: Dictionary) -> void:
	var target := _player_pos()
	var radius := float(b.get("range", 100.0))
	var delay := float(b.get("delay", 0.25))
	var dmg := MoveDB.boss_damage(F_FIRE_SEAL, attack_power, phase)
	SkillFx.calamity_warn_at(get_parent(), target, radius, delay,
		Color(1.0, 0.52, 0.18))
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or state == BossState.DEAD:
				return
			SkillFx.play_at_strike(self, "skill_calamity_fire_seal", b,
				Vector2.RIGHT, target)
			_deal_circle(target, radius, dmg, "elemental", "fire"))
	_finish_skill()


func _cast_fire_field(b: Dictionary) -> void:
	var target := _player_pos()
	SkillFx.play_at_strike(self, "skill_calamity_fire_field", b, facing, target)
	_zones.append({
		"pos": target,
		"radius": float(b.get("range", 140.0)),
		"left": float(b.get("duration", 4.5)),
		"tick": 0.0,
		"interval": float(b.get("tick_interval", 1.5)),
		"dmg": MoveDB.boss_damage(F_FIRE_FIELD, attack_power, phase),
		"kind": "elemental",
		"elem": "fire",
		"lock": 0.0,
	})
	_finish_skill()


func _cast_thunder_strike(b: Dictionary) -> void:
	var target := _player_pos()
	var radius := float(b.get("range", 120.0))
	var delay := float(b.get("delay", 0.35))
	var dmg := MoveDB.boss_damage(F_THUNDER_STRIKE, attack_power, phase)
	SkillFx.calamity_warn_at(get_parent(), target, radius, delay,
		Color(0.72, 0.64, 1.0))
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or state == BossState.DEAD:
				return
			SkillFx.play_at_strike(self, "skill_calamity_thunder_strike", b,
				Vector2.RIGHT, target)
			_deal_circle(target, radius, dmg, "elemental", "thunder"))
	_finish_skill()


func _cast_thunder_pool(b: Dictionary) -> void:
	var target := _player_pos()
	SkillFx.play_at_strike(self, "skill_calamity_thunder_pool", b, facing, target)
	_zones.append({
		"pos": target,
		"radius": float(b.get("range", 150.0)),
		"left": float(b.get("duration", 4.0)),
		"tick": 0.0,
		"interval": float(b.get("tick_interval", 1.0)),
		"dmg": MoveDB.boss_damage(F_THUNDER_POOL, attack_power, phase),
		"kind": "elemental",
		"elem": "thunder",
		"lock": 3.0,
	})
	_finish_skill()


func _cast_turn(b: Dictionary) -> void:
	if has_debuff("suo_zai") or _fusion_left > 0.0:
		_finish_skill()
		return
	var new_el := _counter_of(_player_element())
	if new_el == "" or new_el == _calamity:
		new_el = _next_of(_calamity)
	_calamity = new_el
	_momentum = mini(MAX_MOMENTUM, _momentum + 1)
	_turn_guard_left = 1.5
	_auto_turn_left = AUTO_TURN_P2 if phase >= 2 else AUTO_TURN
	var dmg := MoveDB.boss_damage(F_TURN, attack_power, phase)
	SkillFx.play_at_strike(self, "skill_calamity_turn", b, facing, null)
	_deal_circle(global_position, float(b.get("range", 120.0)), dmg, "elemental",
		_element_of_calamity(new_el))
	show_windup_line("灾位 · %s" % _calamity_name(_calamity), 0.9, 18, 210.0,
		_calamity_color(_calamity), -186.0)
	_refresh_hud()
	_finish_skill()


func _cast_final(b: Dictionary) -> void:
	var target := _player_pos()
	var radius := float(b.get("range", 200.0))
	var delay := float(b.get("delay", 0.55))
	var stacks := _momentum
	var base := MoveDB.boss_damage(F_FINAL, attack_power, phase)
	var dmg := base * ((1.9 + 0.3 * float(stacks)) / 1.9)
	_momentum = 0
	_refresh_hud()
	var elem := _element_of_calamity(_calamity)
	SkillFx.calamity_warn_at(get_parent(), target, radius, delay,
		Color(0.92, 0.80, 0.58))
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or state == BossState.DEAD:
				return
			SkillFx.play_at_strike(self, "skill_calamity_final", b,
				Vector2.RIGHT, target)
			var hit := _deal_circle(target, radius, dmg, "elemental", elem)
			# 万劫归一命中后给「灾崩」：灾身散了，接下来 3 秒更脆。
			for u in hit:
				if u is Node and u.has_method("apply_debuff"):
					u.call("apply_debuff", "zai_beng", 3.0))
	_finish_skill()


func _deal_circle(pos: Vector2, radius: float, dmg: float, kind: String,
		elem: String) -> Array:
	var hit: Array = []
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > radius + 18.0:
			continue
		if _damage_unit(u, dmg, kind, elem):
			hit.append(u)
	return hit


func _deal_cone(reach: float, angle_deg: float, dmg: float, kind: String,
		elem: String) -> void:
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
		_damage_unit(u, dmg, kind, elem)


func _damage_unit(u: Node, dmg: float, kind: String, elem: String) -> bool:
	var final_dmg := dmg
	var crowd := calamity_state()
	var broke := false
	if u.has_method("calamity_incoming_multiplier"):
		var mult := float(u.call("calamity_incoming_multiplier", crowd))
		broke = mult > 1.001
		final_dmg *= mult
	var before := unit_hp(u)
	deal_damage_to(u, final_dmg, kind, elem)
	var after := unit_hp(u)
	# 闪避 / 弹反 / 无敌帧会让 take_damage 空转：这一下不算命中，附带效果全部不落
	if before >= 0.0 and after >= 0.0 and after >= before:
		return false
	if broke:
		_momentum = mini(MAX_MOMENTUM, _momentum + 1)
		_refresh_hud()
	if u.has_method("apply_calamity_break"):
		u.call("apply_calamity_break", crowd)
	if not (u is Node2D):
		return true
	# 灾身附带的 debuff / 击退（灾崩期间灾身失效；三灾归一同时三种）
	if _broken_left > 0.0:
		return true
	if crowd == CAL_FIRE or crowd == CAL_FUSION:
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "jie_huo", 4.0)
	if crowd == CAL_THUNDER or crowd == CAL_FUSION:
		if u.has_method("apply_debuff"):
			u.call("apply_debuff", "gan_dian", 3.0)
	if (crowd == CAL_WIND or crowd == CAL_FUSION) and kind.begins_with("physical"):
		if u.has_method("take_knockback"):
			var away: Vector2 = ((u as Node2D).global_position - global_position).normalized()
			u.call("take_knockback", away * 200.0)
	return true


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
			var radius := float(z.get("radius", 140.0))
			_deal_circle(z["pos"], radius,
				float(z.get("dmg", 0.0)), String(z.get("kind", "elemental")),
				String(z.get("elem", "fire")))
			# 雷池锁灾只锁「站在池里的人」，且整座池只锁一次。
			# 旧版每跳无条件锁玩家：人已经走出去仍被锁满 4 秒，等于白送控制。
			var lock_left := float(z.get("lock", 0.0))
			if lock_left > 0.0 and not bool(z.get("lock_done", false)):
				var p := _player_node()
				if p != null and p is Node2D:
					if (p as Node2D).global_position.distance_to(z["pos"]) <= radius + 18.0:
						if p.has_method("apply_debuff"):
							p.call("apply_debuff", "suo_zai", lock_left)
						z["lock_done"] = true
		if float(z["left"]) > 0.0:
			keep.append(z)
	_zones = keep


# ===================== 承伤 / 阶段 / 杂项 =====================

func _move_speed() -> float:
	var base := super._move_speed()
	if _broken_left <= 0.0 and _fusion_left <= 0.0 and _calamity == CAL_WIND:
		base *= 1.25
	return base


func damage_taken_multiplier(_kind: String) -> float:
	var m := 1.0
	if _fusion_left > 0.0:
		m *= 1.20
	if _broken_left > 0.0:
		m *= SkillDB.CALAMITY_BREAK_TAKEN_MULT
	if _turn_guard_left > 0.0:
		m *= 0.85
	return m


func on_parried(source: Node) -> void:
	super.on_parried(source)


func _on_phase_two() -> void:
	_phase_two = true
	_fusion_left = FUSION_TIME
	_calamity = CAL_FUSION
	_momentum = mini(MAX_MOMENTUM, _momentum + 1)
	_auto_turn_left = 99.0
	show_windup_line("三灾归一 —— 八秒内无法破灾！", 1.5, 20, 290.0,
		Color(0.96, 0.88, 0.74), -192.0)
	_decide_wait = 0.0
	_cools[F_FINAL] = 0.0
	_refresh_hud()


## 受击球压到地面平面（y=0）：玩家攻击的距离/夹角按俯视地面算。
## 场景里的上/中/下三排球保留原始 y 给物理碰撞；若不投影，贴身横砍会被算成斜向上而漏判。
func hit_spheres() -> Array:
	var out := super.hit_spheres()
	for i in range(out.size()):
		var sv: Vector3 = out[i]
		out[i] = Vector3(sv.x, 0.0, sv.z)
	return out


func _die() -> void:
	_zones.clear()
	super._die()


func _exit_tree() -> void:
	_zones.clear()


func _player_node() -> Node2D:
	# 阵营安全读数：召唤出来的友军晏无咎绝不能把玩家当对手（2026-11-02 用户报）
	return opponent_node()


func _player_pos() -> Vector2:
	var p := _player_node()
	return p.global_position if p != null else global_position + facing * 160.0


func _player_element() -> String:
	var p := _player_node()
	if p != null and p.has_method("calamity_state"):
		return String(p.call("calamity_state"))
	return ""


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


func _calamity_beats(a: String, b: String) -> bool:
	return (a == CAL_WIND and b == CAL_FIRE) \
		or (a == CAL_FIRE and b == CAL_THUNDER) \
		or (a == CAL_THUNDER and b == CAL_WIND)


func _counter_of(el: String) -> String:
	match el:
		CAL_FIRE:
			return CAL_WIND
		CAL_THUNDER:
			return CAL_FIRE
		CAL_WIND:
			return CAL_THUNDER
	return CAL_WIND


func _next_of(el: String) -> String:
	match el:
		CAL_WIND:
			return CAL_FIRE
		CAL_FIRE:
			return CAL_THUNDER
		_:
			return CAL_WIND


## 灾位 → 伤害元素（与 AttributeDB 的 7 元素同名）
func _element_of_calamity(el: String) -> String:
	match el:
		CAL_WIND:
			return "wind"
		CAL_FIRE:
			return "fire"
		CAL_THUNDER:
			return "thunder"
	return ""


func _calamity_name(el: String) -> String:
	match el:
		CAL_WIND:
			return "风灾"
		CAL_FIRE:
			return "火灾"
		CAL_THUNDER:
			return "雷灾"
		CAL_FUSION:
			return "三灾归一"
	return el


func _calamity_color(el: String) -> Color:
	match el:
		CAL_WIND:
			return Color(0.55, 0.84, 0.76, 1.0)
		CAL_FIRE:
			return Color(1.0, 0.50, 0.22, 1.0)
		CAL_THUNDER:
			return Color(0.72, 0.62, 1.0, 1.0)
		CAL_FUSION:
			return Color(0.94, 0.82, 0.62, 1.0)
	return Color(0.8, 0.8, 0.8, 1.0)
