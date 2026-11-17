class_name DomainBoss03
extends BossBase
## 赤霄界第 1 位 —— 雷部判官·赫连霄（判词 · 天律）
##
## 核心不是地面物、不是护盾、不是层数，而是**规则**：
##   宣判 / 判词会按目标最近 1.5 秒的行为落一条律（禁行 / 禁攻 / 禁避 / 禁立）。
##   违律 → 落雷 + 雷势 +1；守律 → 顺天 + 雷势 -1；宣判是物理笔锋，可弹反（抗辩）。
## 二阶段：双律 + 雷牢进入常规选招。
##
## 这里只负责「什么时候用、怎么用、律怎么判」；招式数值全在 MoveDB。
## 设计见 docs/赤霄界首位BOSS_设计案.md / docs/赫连霄BOSS完整资料.md。

const F_VERDICT := "form_thunder_verdict"
const F_EXECUTE := "form_thunder_execute"
const F_DRUM := "form_thunder_drum"
const F_LOCK := "form_thunder_lock"
const F_STEP := "form_thunder_step"
const F_GATHER := "form_thunder_gather"
const F_NINE := "form_thunder_nine"
const F_PRISON := "form_thunder_prison"
const SCORED: Array = [F_VERDICT, F_EXECUTE, F_DRUM, F_LOCK, F_STEP, F_GATHER, F_NINE, F_PRISON]

## 冷却（秒）：与 MoveDB 各招 boss.cooldown_p1 同口径，这里集中一份方便手调
const COOLDOWNS := {
	F_VERDICT: 9.0, F_EXECUTE: 6.5, F_DRUM: 7.0, F_LOCK: 9.0,
	F_STEP: 8.0, F_GATHER: 14.0, F_NINE: 24.0, F_PRISON: 16.0,
}

const MAX_LEI := 3
const VERDICT_RANGE := 380.0
const LAWS: Array = ["verdict_no_move", "verdict_no_attack", "verdict_no_dodge", "verdict_no_still"]
const LAW_HINTS := {
	"verdict_no_move": "站住！",
	"verdict_no_attack": "收手！",
	"verdict_no_dodge": "别闪！",
	"verdict_no_still": "动起来！",
}
## 每条律的违律雷击系数（× 攻击力）
const LAW_COEF := {
	"verdict_no_move": 0.80,
	"verdict_no_attack": 0.90,
	"verdict_no_dodge": 0.80,
	"verdict_no_still": 0.70,
}
## 双律允许的搭配（禁行 + 禁立 是死锁，永不同时出现）
const LAW_PAIRS := {
	"verdict_no_move": ["verdict_no_attack", "verdict_no_dodge"],
	"verdict_no_attack": ["verdict_no_move", "verdict_no_dodge", "verdict_no_still"],
	"verdict_no_dodge": ["verdict_no_move", "verdict_no_attack", "verdict_no_still"],
	"verdict_no_still": ["verdict_no_attack", "verdict_no_dodge"],
}

enum ExtraState { GATHER = 100, STEP = 101 }

var _phase_two: bool = false
var _cools: Dictionary = {}
var _recent: Array = []
var _decide_wait: float = 0.0
var _current_skill: String = ""
var _lei_shi: int = 0
var _pips: ThunderPips = null

## 挂在玩家身上的判词：[{id, left, total, violations, cd}]
var _verdicts: Array = []
var _pending_laws: Array = []
var _verdict_cancelled: bool = false

## 玩家行为窗口（1.5 秒）：决定下一条律
var _prev_player_pos := Vector2.INF
var _player_move_window: float = 0.0
var _player_attack_window: float = 0.0
var _player_dodge_window: float = 0.0
var _prev_player_dodging: bool = false
var _move_accum: float = 0.0
var _still_time: float = 0.0

## 玩家给 BOSS 下律后的「收敛行为」计时：先守一段，再决定违律
var _caution_left: float = 0.0

## 聚雷引导
var _gather_left: float = 0.0
var _gather_damage: float = 0.0
var _gather_tick: float = 0.0
var _gather_fx: Node2D = null

## 雷遁
var _step_dir := Vector2.RIGHT
var _step_target := Vector2.ZERO
var _step_timer: float = 0.0
var _step_fired: bool = false


func _setup() -> void:
	boss_id = "boss_03"
	_lei_shi = 0
	_verdicts.clear()
	_pending_laws.clear()
	_cools.clear()
	_recent.clear()
	_pips = ThunderPips.new()
	_pips.name = "LeiPips"
	add_child(_pips)
	_refresh_pips()


func _physics_process(delta: float) -> void:
	if state == BossState.DEAD:
		return
	_tick_watch(delta)
	_tick_verdicts(delta)
	_tick_pips_position()
	if state == ExtraState.GATHER:
		_tick_cooldowns(delta)
		_tick_gather(delta)
		return
	if state == ExtraState.STEP:
		_tick_cooldowns(delta)
		_tick_step(delta)
		return
	super._physics_process(delta)


func _tick_cooldowns(delta: float) -> void:
	_decide_wait = maxf(0.0, _decide_wait - delta)
	_caution_left = maxf(0.0, _caution_left - delta)
	_player_move_window = maxf(0.0, _player_move_window - delta)
	_player_attack_window = maxf(0.0, _player_attack_window - delta)
	_player_dodge_window = maxf(0.0, _player_dodge_window - delta)
	for k in _cools.keys():
		_cools[k] = maxf(0.0, float(_cools[k]) - delta)


## 记录玩家最近行为：移动 / 闪避 / 出手（出手在 take_damage 里记）
func _tick_watch(delta: float) -> void:
	var p := _law_subject()
	if p == null or BossBase.is_unit_dead(p):
		if not _verdicts.is_empty():
			_clear_laws()
		return
	var pos: Vector2 = p.global_position
	if _prev_player_pos == Vector2.INF:
		_prev_player_pos = pos
		return
	var moved := pos.distance_to(_prev_player_pos)
	# 仇恨可能落到玩家的镜像分身身上，分身没有这两个字段：用 == true 比较，
	# 别写 bool(p.get(...))（拿 null 会报「Nonexistent 'bool' constructor」）
	var dodging: bool = p.get("is_dodging") == true
	var teleporting: bool = p.get("is_teleporting") == true
	# 被击退 / 传送位移不算「自己移动」（否则玩家会被判词冤枉）
	var kb: Vector2 = Vector2.ZERO
	var raw_kb = p.get("knockback_velocity")
	if raw_kb is Vector2:
		kb = raw_kb
	if moved > 0.6 and kb.length() < 20.0 and not teleporting:
		_player_move_window = 1.5
		if not dodging:
			_move_accum += moved
	if dodging and not _prev_player_dodging:
		_player_dodge_window = 1.5
		_violate_by_id("verdict_no_dodge")
	_prev_player_dodging = dodging
	if moved < 1.2 and not dodging and not teleporting:
		_still_time += delta
	else:
		_still_time = 0.0
	_prev_player_pos = pos


func _tick_verdicts(delta: float) -> void:
	if _verdicts.is_empty():
		return
	var expired: Array = []
	for raw in _verdicts:
		var law: Dictionary = raw
		law["left"] = float(law.get("left", 0.0)) - delta
		law["cd"] = maxf(0.0, float(law.get("cd", 0.0)) - delta)
		var id := String(law.get("id", ""))
		match id:
			"verdict_no_move":
				if float(law["cd"]) <= 0.0 and _move_accum >= 110.0:
					_move_accum = 0.0
					_violate(law)
			"verdict_no_still":
				if float(law["cd"]) <= 0.0 and _still_time >= 0.9:
					_still_time = 0.0
					_violate(law)
		if float(law["left"]) <= 0.0:
			expired.append(law)
	for law in expired:
		_expire_law(law)
		_verdicts.erase(law)


func _tick_pips_position() -> void:
	if _pips == null or not is_instance_valid(_pips):
		return
	var w := maxf(_pips.size.x, 54.0)
	_pips.position = Vector2(-w * 0.5, head_top_y() - 30.0)


func _refresh_pips() -> void:
	if _pips != null and is_instance_valid(_pips):
		_pips.set_state(_lei_shi)


# ===================== 判词 =====================

func _player_node() -> Node2D:
	# 统一走基类的阵营读数：友军召唤物的对手是它的 target，不是玩家
	return opponent_node()


## 判词/执法的对象：敌方 BOSS 判玩家；召唤出来的友军判它的 target（敌方 BOSS）。
func _law_subject() -> Node2D:
	if is_ally:
		if target != null and is_instance_valid(target) and target is Node2D:
			return target as Node2D
		return null
	return _player_node()


func _has_law() -> bool:
	return not _verdicts.is_empty()


func _has_law_on_player(id: String = "") -> bool:
	if id == "":
		return not _verdicts.is_empty()
	for raw in _verdicts:
		if String((raw as Dictionary).get("id", "")) == id:
			return true
	return false


## 按玩家最近行为选律；二阶段再配一条不冲突的第二律
func _choose_laws() -> Array:
	var primary := "verdict_no_still"
	if _player_dodge_window > 0.0:
		primary = "verdict_no_dodge"
	elif _player_attack_window > 0.0:
		primary = "verdict_no_attack"
	elif _player_move_window > 0.0:
		primary = "verdict_no_move"
	if not _phase_two:
		return [primary]
	var options: Array = LAW_PAIRS.get(primary, [])
	if options.is_empty():
		return [primary]
	# 第二律优先取「玩家另一种最近行为」，否则随机
	var second := ""
	if primary != "verdict_no_attack" and _player_attack_window > 0.0 and "verdict_no_attack" in options:
		second = "verdict_no_attack"
	elif primary != "verdict_no_move" and _player_move_window > 0.0 and "verdict_no_move" in options:
		second = "verdict_no_move"
	elif primary != "verdict_no_dodge" and _player_dodge_window > 0.0 and "verdict_no_dodge" in options:
		second = "verdict_no_dodge"
	if second == "":
		second = String(options[randi() % options.size()])
	return [primary, second]


func _law_text(laws: Array) -> String:
	var names: Array[String] = []
	for raw in laws:
		# display_name 本身带「判词·」前缀；这里用于「判词 · X」组合，先剥掉避免重复
		names.append(DebuffDB.display_name(String(raw)).replace("判词·", ""))
	return " + ".join(names)


func _law_hint(laws: Array) -> String:
	if laws.is_empty():
		return "天律加身"
	if laws.size() >= 2:
		return "双律 · 两件事都不能做"
	return String(LAW_HINTS.get(String(laws[0]), "守律"))


func _apply_laws(laws: Array) -> void:
	_clear_laws()
	var duration := float(MoveDB.resolve_boss(F_VERDICT).get("verdict_time", 5.0))
	if _phase_two:
		duration = float(MoveDB.resolve_boss(F_VERDICT).get("verdict_time_p2", 6.0))
	var p := _law_subject()
	for raw in laws:
		var id := String(raw)
		_verdicts.append({"id": id, "left": duration, "total": duration, "violations": 0, "cd": 0.0})
		if p != null and p.has_method("apply_debuff"):
			if p.is_in_group("player"):
				p.call("apply_debuff", id, duration, true)
			else:
				# 敌方 BOSS / 野怪：BossBase.apply_debuff 只有 (id, duration)
				p.call("apply_debuff", id, duration)
	var names := _law_text(laws)
	_float_at_player("判词 · %s —— %s" % [names, _law_hint(laws)],
		Color(0.82, 0.66, 1.0), 0.0)
	# 判词落印：目标脚下一圈雷印
	if p != null:
		SkillFx.thunder_mark(get_parent(), p.global_position, 58.0,
			Color(0.80, 0.62, 1.0), 0.45)


func _clear_laws() -> void:
	var p := _law_subject()
	for raw in _verdicts:
		if p == null:
			break
		var id := String((raw as Dictionary).get("id", ""))
		if p.has_method("clear_debuff"):
			p.call("clear_debuff", id)
		elif p.has_method("remove_debuff"):
			p.call("remove_debuff", id)
	_verdicts.clear()
	_move_accum = 0.0
	_still_time = 0.0


func _expire_law(law: Dictionary) -> void:
	var id := String(law.get("id", ""))
	var p := _law_subject()
	if p != null:
		if p.has_method("clear_debuff"):
			p.call("clear_debuff", id)
		elif p.has_method("remove_debuff"):
			p.call("remove_debuff", id)
	if int(law.get("violations", 0)) <= 0 and p != null and not BossBase.is_unit_dead(p):
		# 守律：顺天 + 削它一层雷势
		if p.has_method("apply_shuntian"):
			p.call("apply_shuntian", 6.0)
		_lei_shi = maxi(0, _lei_shi - 1)
		_refresh_pips()
		_float_at_player("守律 · 顺天", UIKit.C_TEXT_DIM, 0.0)


func _violate(law: Dictionary) -> void:
	var p := _law_subject()
	if p == null or BossBase.is_unit_dead(p):
		return
	law["violations"] = int(law.get("violations", 0)) + 1
	law["cd"] = 0.35
	_lei_shi = mini(MAX_LEI, _lei_shi + 1)
	_refresh_pips()
	var id := String(law.get("id", ""))
	var pos: Vector2 = p.global_position
	var dmg := attack_power * float(LAW_COEF.get(id, 0.8)) * (1.15 if phase >= 2 else 1.0)
	_float_at_player("违律！", UIKit.C_TEXT_DIM, 0.0)
	SkillFx.thunder_mark(get_parent(), pos, 58.0, Color(0.86, 0.66, 1.0), 0.25)
	get_tree().create_timer(0.25, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self) or state == BossState.DEAD:
			return
		var p2 := _law_subject()
		if p2 == null or BossBase.is_unit_dead(p2):
			return
		SkillFx.play_at_strike(self, "fx_thunder_violation",
			{"range": 60.0, "hit_shape": MoveDB.SHAPE_CIRCLE}, Vector2.RIGHT, pos)
		if p2.global_position.distance_to(pos) <= 62.0:
			deal_damage_to(p2, dmg, "elemental", "thunder"))


func _violate_by_id(id: String) -> void:
	for raw in _verdicts:
		var law: Dictionary = raw
		if String(law.get("id", "")) == id and float(law.get("cd", 0.0)) <= 0.0:
			_violate(law)
			return


func _float_at_player(text: String, color: Color, hold: float) -> void:
	var p := _law_subject()
	if p == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 4)
	label.size = Vector2(320.0, 24.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = p.global_position + Vector2(-160.0, -96.0)
	label.z_index = 70
	get_parent().add_child(label)
	var tw := label.create_tween()
	if hold > 0.0:
		tw.tween_interval(hold)
	tw.tween_property(label, "position:y", label.position.y - 26.0, 0.55)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.55)
	tw.tween_callback(label.queue_free)


# ===================== 选招 =====================

func _on_chase_reached(_dist: float) -> void:
	_choose()


func _choose() -> void:
	if state != BossState.IDLE and state != BossState.CHASE:
		return
	if _decide_wait > 0.0:
		return
	_decide_wait = 0.3
	var p := _law_subject()
	if p == null or BossBase.is_unit_dead(p):
		return
	var d := _dist()

	# 1. 立律优先：没有判词在身、玩家在宣判范围内
	if not _has_law() and _ready_cd(F_VERDICT) and d <= VERDICT_RANGE:
		_begin(F_VERDICT)
		return
	# 2. 执刑：玩家带律 + 定刑就绪 → 惩罚
	if _has_law() and _ready_cd(F_EXECUTE) and d <= 460.0:
		_begin(F_EXECUTE)
		return
	# 3. 雷势 ≥2 → 九霄
	if _lei_shi >= 2 and _ready_cd(F_NINE) and d <= 520.0:
		_begin(F_NINE)
		return
	# 4. 二阶段：禁避 + 雷牢 = 逼你在“吃雷环 / 违律”里选
	if _phase_two and _ready_cd(F_PRISON) and d <= 520.0 \
			and _has_law_on_player("verdict_no_dodge"):
		_begin(F_PRISON)
		return
	# 5. 残血 / 雷势低 → 聚雷（可打断的输出窗）
	if _hp_ratio() <= 0.55 and _lei_shi < 2 and _ready_cd(F_GATHER) and randf() < 0.7:
		_begin(F_GATHER)
		return
	# 6. 被下「禁攻」：先收手一小段，不白送违律
	if _caution_left > 0.0 and _player_law_id() == "verdict_no_attack":
		_chase_target(0.0)
		return
	# 7. 被下「禁行」：不主动走；优先原地招
	if _player_law_id() == "verdict_no_move":
		if _ready_cd(F_EXECUTE) and d <= 460.0:
			_begin(F_EXECUTE)
			return
		if _ready_cd(F_LOCK) and d <= 340.0:
			_begin(F_LOCK)
			return
	# 8. 远距：雷遁贴人
	if d > 260.0 and _ready_cd(F_STEP) and _player_law_id() != "verdict_no_dodge" and randf() < 0.55:
		_begin(F_STEP)
		return
	# 9. 评分
	var best := ""
	var best_score := -999.0
	for sid in SCORED:
		if not _usable(String(sid)):
			continue
		if not _in_reach(String(sid)):
			continue
		var combo := 0.0
		var last := String(_recent[0]) if not _recent.is_empty() else ""
		if last == F_VERDICT and (sid == F_EXECUTE or sid == F_DRUM or sid == F_LOCK):
			combo = 2.0
		elif last == F_STEP and sid == F_DRUM:
			combo = 1.4
		elif last == F_LOCK and sid == F_NINE:
			combo = 1.0
		elif last == F_GATHER and sid == F_NINE:
			combo = 0.8
		var sc := _score(String(sid)) + randf() * 1.0 + combo - _repeat_penalty(String(sid))
		# 被玩家下律后的收敛：禁攻期间不主动出手；禁避期间不雷遁
		if _caution_left > 0.0 and _player_law_id() == "verdict_no_attack":
			continue
		if _player_law_id() == "verdict_no_dodge" and sid == F_STEP:
			sc -= 99.0
		if sc > best_score:
			best_score = sc
			best = String(sid)
	if best == "":
		state = BossState.CHASE
		return
	_begin(best)


## 玩家给 BOSS 挂的判词（只看 debuffs，不看 _verdicts）
func _player_law_id() -> String:
	for id in LAWS:
		if has_debuff(String(id)):
			return String(id)
	return ""


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
	if target != null and is_instance_valid(target):
		_set_facing(((target as Node2D).global_position - global_position).normalized())
	# 招名：前摇第一帧出现，只报招名，hold 至少盖住前摇
	var fname := String(b.get("form_name", ""))
	match sid:
		F_VERDICT:
			_pending_laws = _choose_laws()
			_verdict_cancelled = false
			show_skill_line(fname,
				state_timer, 20, 280.0,
				BossBase.skill_name_color(String(b.get("attack_kind", ""))), -184.0)
		F_GATHER:
			show_skill_line(fname,
				state_timer + float(b.get("channel_time", 1.4)),
				20, 240.0,
				BossBase.skill_name_color(String(b.get("attack_kind", ""))), -184.0)
		F_PRISON:
			show_skill_line(fname,
				state_timer + float(b.get("closing_time", 1.2)),
				20, 240.0,
				BossBase.skill_name_color(String(b.get("attack_kind", ""))), -184.0)
		F_NINE:
			show_skill_line(fname, state_timer, 18, 230.0,
				BossBase.skill_name_color(String(b.get("attack_kind", ""))), -184.0)
		_:
			if fname != "":
				show_skill_line(fname, state_timer, 17, 210.0,
					BossBase.skill_name_color(String(b.get("attack_kind", ""))), -184.0)


func _usable(sid: String) -> bool:
	if not _ready_cd(sid):
		return false
	match sid:
		F_VERDICT:
			return not _has_law()
		F_GATHER:
			return _lei_shi < MAX_LEI
		F_PRISON:
			return _phase_two
		F_NINE:
			return _lei_shi >= 1
		F_STEP:
			return _player_law_id() != "verdict_no_dodge"
	return true


func _ready_cd(sid: String) -> bool:
	return float(_cools.get(sid, 0.0)) <= 0.0


func _in_reach(sid: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var d := _dist()
	match sid:
		F_VERDICT:
			return d <= VERDICT_RANGE
		F_EXECUTE:
			return d <= 460.0
		F_DRUM:
			return d <= 210.0
		F_LOCK:
			return d <= 340.0
		F_STEP:
			return d >= 160.0 and d <= 520.0
		F_GATHER:
			return d <= 640.0
		F_NINE:
			return d <= 520.0
		F_PRISON:
			return d <= 520.0
	return true


func _score(sid: String) -> float:
	var d := _dist()
	match sid:
		F_VERDICT:
			return 3.2
		F_EXECUTE:
			return 2.8 - absf(d - 300.0) / 260.0 + (1.6 if _has_law() else 0.0)
		F_DRUM:
			return 3.4 - absf(d - 90.0) / 110.0
		F_LOCK:
			return 2.6 - absf(d - 180.0) / 180.0
		F_STEP:
			return 3.2 - absf(d - 340.0) / 220.0
		F_GATHER:
			return 0.35
		F_NINE:
			return 2.6 + 0.25 * float(_lei_shi)
		F_PRISON:
			return 2.4
	return 0.6


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
	var cd := float(COOLDOWNS.get(sid, 8.0))
	if phase >= 2:
		cd *= 0.9
	_cools[sid] = cd


# ===================== 出招 =====================

func _fire_skill() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	var b := MoveDB.resolve_boss(_current_skill)
	if b.is_empty():
		_finish_skill()
		return
	match _current_skill:
		F_VERDICT:
			_cast_verdict(b)
		F_EXECUTE:
			_cast_execute(b)
		F_DRUM:
			_cast_drum(b)
		F_LOCK:
			_cast_lock(b)
		F_STEP:
			_cast_step(b)
		F_GATHER:
			_cast_gather(b)
		F_NINE:
			_cast_nine(b)
		F_PRISON:
			_cast_prison(b)
		_:
			_finish_skill()


func _finish_skill() -> void:
	_record(_current_skill)
	_current_skill = ""
	state = BossState.RECOVER
	state_timer = 0.45


func _cast_verdict(b: Dictionary) -> void:
	var reach := float(b.get("range", 320.0))
	var width := float(b.get("width", 56.0))
	var dmg := MoveDB.boss_damage(F_VERDICT, attack_power, phase)
	var dir := facing
	if target != null and is_instance_valid(target):
		dir = ((target as Node2D).global_position - global_position).normalized()
	_set_facing(dir)
	_hit_line(reach, width, dmg, "physical_melee", "")
	SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(F_VERDICT)), b, dir, null)
	if _verdict_cancelled:
		# 抗辩：弹反撤销判词，不进 RECOVER（保留 super.on_parried 的僵直）
		_record(F_VERDICT)
		_current_skill = ""
		return
	_apply_laws(_pending_laws)
	_pending_laws.clear()
	_finish_skill()


func _cast_execute(b: Dictionary) -> void:
	var p := _law_subject()
	if p == null:
		_finish_skill()
		return
	var pos: Vector2 = p.global_position
	var delay := float(b.get("delay", 0.45))
	var radius := float(b.get("range", 90.0))
	var dmg := MoveDB.boss_damage(F_EXECUTE, attack_power, phase)
	var bonus := float(b.get("verdict_bonus", 0.5)) if _has_law() else 0.0
	SkillFx.thunder_mark(get_parent(), pos, radius, Color(0.86, 0.66, 1.0), delay)
	get_tree().create_timer(delay, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self) or state == BossState.DEAD:
			return
		SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(F_EXECUTE)),
			b, Vector2.RIGHT, pos)
		for u in attack_units():
			if u is Node2D and (u as Node2D).global_position.distance_to(pos) <= radius + 18.0:
				deal_damage_to(u, dmg * (1.0 + bonus), "elemental", "thunder"))
	_finish_skill()


func _cast_drum(b: Dictionary) -> void:
	var radius := float(b.get("range", 180.0))
	var dmg := MoveDB.boss_damage(F_DRUM, attack_power, phase)
	var kb := float(b.get("knockback", 360.0))
	SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(F_DRUM)), b, facing, null)
	# 雷鼓在背上（属于身体贴图）：在鼓面位置补一圈赤金雷闪，读作“鼓被敲响”
	SkillFx.thunder_mark(get_parent(), global_position + Vector2(-52.0, -40.0), 46.0,
		Color(1.0, 0.84, 0.42), 0.42)
	for u in attack_units():
		if not (u is Node2D):
			continue
		var d: float = (u as Node2D).global_position.distance_to(global_position)
		if d > radius + 18.0:
			continue
		deal_damage_to(u, dmg, "physical_melee", "")
		if u.has_method("take_knockback") and d > 0.1:
			var away := ((u as Node2D).global_position - global_position).normalized()
			u.call("take_knockback", away * kb)
	_finish_skill()


func _cast_lock(b: Dictionary) -> void:
	var reach := float(b.get("range", 300.0))
	var width := float(b.get("width", 54.0))
	var dmg := MoveDB.boss_damage(F_LOCK, attack_power, phase)
	var dir := facing
	if target != null and is_instance_valid(target):
		dir = ((target as Node2D).global_position - global_position).normalized()
	_set_facing(dir)
	SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(F_LOCK)), b, dir, null)
	_hit_line(reach, width, dmg, "elemental", "thunder", b)
	_finish_skill()


func _cast_step(b: Dictionary) -> void:
	var p := _law_subject()
	if p == null:
		_finish_skill()
		return
	var to_player: Vector2 = p.global_position - global_position
	var dir := to_player.normalized() if to_player.length() > 1.0 else facing
	_step_dir = dir
	var dist := float(b.get("teleport_dist", 110.0))
	# 落在玩家侧后：从玩家位置往回退 dist，避免和玩家重叠
	_step_target = p.global_position - dir * dist
	_step_target = _clamp_point(_step_target)
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
	SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(F_STEP)), b,
		_step_dir, null)
	for u in attack_units():
		if u is Node2D and (u as Node2D).global_position.distance_to(global_position) <= 128.0:
			deal_damage_to(u, dmg, "physical_melee", "")
	_finish_skill()


func _cast_gather(b: Dictionary) -> void:
	_gather_damage = 0.0
	_gather_left = float(b.get("channel_time", 1.4))
	_gather_tick = 0.0
	state = ExtraState.GATHER
	_gather_fx = SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(F_GATHER)),
		b, facing, null)


func _tick_gather(delta: float) -> void:
	var b := MoveDB.resolve_boss(F_GATHER)
	_gather_left -= delta
	if _gather_damage >= max_hp * float(b.get("channel_break_damage", 0.08)):
		_interrupt_gather()
		return
	if _gather_left <= 0.0:
		_lei_shi = mini(MAX_LEI, _lei_shi + int(b.get("gather_lei", 1)))
		_refresh_pips()
		show_windup_line("聚雷已成 · 雷势 +1", 0.9, 18, 220.0,
			Color(0.84, 0.68, 1.0), -184.0)
		SkillFx.thunder_mark(get_parent(), global_position, 90.0,
			Color(0.84, 0.68, 1.0), 0.35)
		_finish_skill()
		return
	_gather_tick -= delta
	if _gather_tick > 0.0:
		return
	_gather_tick = float(b.get("gather_bolt_interval", 0.35))
	var spread := float(b.get("gather_bolt_spread", 200.0))
	var radius := float(b.get("gather_bolt_radius", 80.0))
	var pos := global_position + Vector2(
		randf_range(-spread, spread), randf_range(-spread * 0.58, spread * 0.58))
	pos = _clamp_point(pos)
	var dmg := attack_power * float(b.get("gather_bolt_coeff", 0.35)) \
		* (1.25 if phase >= 2 else 1.0)
	SkillFx.thunder_mark(get_parent(), pos, radius, Color(0.80, 0.62, 1.0), 0.22)
	get_tree().create_timer(0.22, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self) or state == BossState.DEAD:
			return
		SkillFx.play_at_strike(self, "fx_thunder_violation",
			{"range": radius, "hit_shape": MoveDB.SHAPE_CIRCLE}, Vector2.RIGHT, pos)
		for u in attack_units():
			if u is Node2D and (u as Node2D).global_position.distance_to(pos) <= radius + 16.0:
				deal_damage_to(u, dmg, "elemental", "thunder"))


func _interrupt_gather() -> void:
	if is_instance_valid(_gather_fx):
		_gather_fx.queue_free()
	_gather_fx = null
	show_windup_line("聚雷被打断！", 0.9, 18, 220.0, Color(0.98, 0.72, 0.40), -180.0)
	stagger_for(0.9)
	_record(F_GATHER)
	_current_skill = ""
	_gather_left = 0.0


func _cast_nine(b: Dictionary) -> void:
	var p := _law_subject()
	if p == null:
		_finish_skill()
		return
	var center: Vector2 = p.global_position
	var count := int(b.get("pillar_count_base", 2)) + _lei_shi
	_lei_shi = 0
	_refresh_pips()
	var radius := float(b.get("range", 100.0))
	var spread := float(b.get("pillar_spread", 120.0))
	var dmg := MoveDB.boss_damage(F_NINE, attack_power, phase)
	var dir := facing
	var offsets: Array = [Vector2.ZERO]
	for i in range(1, maxi(1, count)):
		var ang := TAU * float(i - 1) / float(maxi(1, count - 1)) + randf_range(-0.2, 0.2)
		offsets.append(Vector2(cos(ang), sin(ang) * 0.62) * spread)
	for i in range(count):
		var pos: Vector2 = _clamp_point(center + (offsets[i % offsets.size()] as Vector2))
		SkillFx.thunder_mark(get_parent(), pos, radius, Color(0.86, 0.66, 1.0), 0.42)
		get_tree().create_timer(0.42, true, false, true).timeout.connect(func() -> void:
			if not is_instance_valid(self) or state == BossState.DEAD:
				return
			SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(F_NINE)),
				b, Vector2.RIGHT, pos)
			for u in attack_units():
				if u is Node2D and (u as Node2D).global_position.distance_to(pos) <= radius + 18.0:
					deal_damage_to(u, dmg, "elemental", "thunder"))
	_finish_skill()


func _cast_prison(b: Dictionary) -> void:
	var p := _law_subject()
	if p == null:
		_finish_skill()
		return
	var center: Vector2 = p.global_position
	var radius := float(b.get("prison_radius", 170.0))
	var closing := float(b.get("closing_time", 1.2))
	var dmg := MoveDB.boss_damage(F_PRISON, attack_power, phase)
	SkillFx.play_at_strike(self, String(SkillDB.get_skill_id_by_form(F_PRISON)),
		b, Vector2.RIGHT, center)
	get_tree().create_timer(closing, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self) or state == BossState.DEAD:
			return
		var p2 := _law_subject()
		if p2 == null or BossBase.is_unit_dead(p2):
			return
		if p2.global_position.distance_to(center) <= radius:
			deal_damage_to(p2, dmg, "elemental", "thunder")
			if p2.has_method("apply_debuff"):
				p2.call("apply_debuff", "stun", 1.0))
	_finish_skill()


# ===================== 通用 =====================

func _hit_line(reach: float, width: float, dmg: float, kind: String, elem: String,
		b: Dictionary = {}) -> void:
	var dir := facing
	var a := global_position
	var end := a + dir * reach
	for u in attack_units():
		if not (u is Node2D):
			continue
		if _point_segment_distance((u as Node2D).global_position, a, end) > width * 0.5 + 18.0:
			continue
		deal_damage_to(u, dmg, kind, elem)
		if not b.is_empty():
			_apply_form_debuff(u, b)


func _apply_form_debuff(unit: Node, b: Dictionary) -> void:
	var did := String(b.get("debuff_on_hit", ""))
	if did == "":
		return
	_debuff(unit, did, float(b.get("debuff_time", 3.0)))


func _debuff(unit: Node, id: String, duration: float) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("apply_debuff"):
		return
	if unit.is_in_group("player"):
		unit.call("apply_debuff", id, duration, true)
	else:
		unit.call("apply_debuff", id, duration)


func _dist() -> float:
	return _distance_to_target()


func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _clamp_point(pos: Vector2) -> Vector2:
	var lim := _arena_limit()
	if lim == Vector2.ZERO:
		return pos
	return Vector2(
		clampf(pos.x, arena_center.x - lim.x, arena_center.x + lim.x),
		clampf(pos.y, arena_center.y - lim.y, arena_center.y + lim.y))


func _hp_ratio() -> float:
	return current_hp / maxf(max_hp, 1.0)


# ===================== 受击 / 行为响应 =====================

func take_damage(amount: float, source: Node = null, damage_kind: String = "physical",
		element: String = "", from_projectile: bool = false) -> void:
	super.take_damage(amount, source, damage_kind, element, from_projectile)
	if state == BossState.DEAD or phase_transitioning:
		return
	if is_ally:
		_player_attack_window = 1.5
		if _has_law_on_player("verdict_no_attack"):
			_violate_by_id("verdict_no_attack")
	elif _is_player_source(source) and amount > 0.0:
		_player_attack_window = 1.5
		if _has_law_on_player("verdict_no_attack"):
			_violate_by_id("verdict_no_attack")


func _is_player_source(src: Node) -> bool:
	if src == null or not is_instance_valid(src):
		return false
	if src.is_in_group("player"):
		return true
	for key in ["source", "owner_unit"]:
		var raw = src.get(key)
		if raw is Node and is_instance_valid(raw) and (raw as Node).is_in_group("player"):
			return true
	return false


## 玩家给 BOSS 挂判词：先「守律」一段，再按律调整行为
## ⚠ 参数必须与 BossBase.apply_debuff 完全一致（含战报用的 from_unit）：
##   GDScript 的覆写签名不一致会直接把整个子类脚本判成解析错误。
func apply_debuff(id: String, duration: float, from_unit: Node = null) -> bool:
	var fresh := super.apply_debuff(id, duration, from_unit)
	if id.begins_with("verdict_"):
		_caution_left = 1.4
		if is_instance_valid(_pips):
			_pips.modulate = Color(0.86, 0.70, 1.0, 1.0)
	return fresh


func after_damage_taken(amount: float) -> void:
	if state == ExtraState.GATHER:
		_gather_damage += amount


## 被下「禁行」时先站住；被下「禁立」时绕着目标侧移 —— 这两条是看得见的行为响应
func _chase_target(delta: float) -> void:
	var law := _player_law_id()
	if law == "verdict_no_move" and _caution_left > 0.0:
		velocity = Vector2.ZERO
		_update_facing_to_target()
		return
	if law == "verdict_no_still":
		if target != null and is_instance_valid(target):
			var to: Vector2 = (target as Node2D).global_position - global_position
			var d := to.length()
			if d < 1.0:
				return
			var dir := to / d
			var side_sign := 1.0 if int(Time.get_ticks_msec() / 750) % 2 == 0 else -1.0
			var side := dir.rotated(PI * 0.5) * side_sign
			velocity = (dir * 0.35 + side * 0.9).normalized() * _move_speed()
			_set_facing(dir)
			return
	super._chase_target(delta)


func on_parried(source: Node) -> void:
	var was_verdict := _current_skill == F_VERDICT
	super.on_parried(source)
	if was_verdict:
		_verdict_cancelled = true
		_pending_laws.clear()
		_lei_shi = maxi(0, _lei_shi - 1)
		_refresh_pips()
		show_windup_line("抗辩！判词撤销", 1.0, 20, 220.0,
			Color(1.0, 0.86, 0.46), -186.0)
		_float_at_player("抗辩成功 · 判词撤销", UIKit.C_TEXT_DIM, 0.0)


## 玩家给 BOSS 挂的判词走完未违律：与玩家守律对称，BOSS 雷势 -1
func on_player_law_kept() -> void:
	_lei_shi = maxi(0, _lei_shi - 1)
	_refresh_pips()


func _on_phase_two() -> void:
	_phase_two = true
	_lei_shi = mini(MAX_LEI, _lei_shi + 1)
	_refresh_pips()
	show_windup_line("天律双判 · 雷牢加身！", 1.4, 22, 260.0,
		Color(0.86, 0.68, 1.0), -190.0)
	# 二阶段第一发优先宣判（双律）：把选招节流放开，AI 的优先级 1 会立刻接上
	_decide_wait = 0.0
	_cools[F_VERDICT] = 0.0


func _fire_attack() -> void:
	_fire_skill()


## 受击球压到地面平面（y=0）：玩家攻击的距离/夹角按俯视地面算。
## 场景里的上/中/下三排球保留原始 y 给物理碰撞；若不投影，贴身横砍会被算成斜向上而漏判。
func hit_spheres() -> Array:
	var out := super.hit_spheres()
	for i in range(out.size()):
		var sv: Vector3 = out[i]
		out[i] = Vector3(sv.x, 0.0, sv.z)
	return out


func _die() -> void:
	_clear_laws()
	if is_instance_valid(_gather_fx):
		_gather_fx.queue_free()
	super._die()


func _exit_tree() -> void:
	if is_instance_valid(_gather_fx):
		_gather_fx.queue_free()
