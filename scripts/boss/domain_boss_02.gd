class_name DomainBoss02
extends BossBase
## 位面 02 第 1 位 BOSS —— 两仪真人（两仪护体 / 阴阳易位）
##
## 设计案：docs/两仪真人BOSS完整资料.md
##
## 第一战的核心不是「玩家有没有两仪功法」，而是「读盾」：
##   · 护体有阳 / 阴两种仪态；同属性伤害减半、**只有异属性伤害才削盾**（-14）；
##   · 弹反 / 完美闪避各震 20、起手闪避震 6 —— 单流派也能靠防御手段破盾；
##   · 破盾 → 硬直 + 翻面，之后 3 秒内任何攻击都削不动盾（回盾安全窗）。
## 两仪转是「必成」动作：前摇不再被打断（用户 2026-10-27 改口径，只留读色与躲开的空间）。
## 玩家打完 BOSS、在塔第 4 层学到八门两仪功法后，才会解锁「两仪势」奖励层
## （见 player.gd 的 _yinyang_*；第一战不参与任何计算）。
##
## 本脚本只负责「什么时候用、怎么用」，招式数值全在 MoveDB.FORMS。

# ===================== 招式 id =====================
const SKILL_PALM := "form_yinyang_palm"
const SKILL_FINGER := "form_yinyang_finger"
const SKILL_FLIP := "form_yinyang_flip"
const SKILL_COLLAPSE := "form_yinyang_collapse"
const SKILL_TRIPLE := "form_yinyang_triple"
const SKILL_WIND := "form_yinyang_wind"
const SKILL_FISH := "form_yinyang_fish"
const SKILL_COUNTER := "form_yinyang_counter"

const ALL_SKILLS: Array = [SKILL_PALM, SKILL_FINGER, SKILL_TRIPLE, SKILL_WIND,
	SKILL_FISH, SKILL_COUNTER, SKILL_FLIP, SKILL_COLLAPSE]
## 会被评分选中的招式（转 / 倒悬由条件驱动，不参与常规评分）
const SCORED_SKILLS: Array = [SKILL_PALM, SKILL_FINGER, SKILL_TRIPLE, SKILL_WIND,
	SKILL_FISH, SKILL_COLLAPSE]

# ===================== 护体 =====================
const POLARITY_YANG := 0
const POLARITY_YIN := 1
const SHIELD_MAX := 100.0
## 每次伤害事件扣的护体值：**只有异属性伤害削盾**（同属性只减伤、不磨盾）
const SHIELD_CHIP_OPPOSITE := 14.0
## 防御手段震盾（不看颜色，所以纯物理 / 纯法术 build 也能破）
const SHIELD_CHIP_PARRY := 20.0
const SHIELD_CHIP_PERFECT_DODGE := 20.0
const SHIELD_CHIP_DODGE := 6.0
## 防止万剑归宗一帧破盾：护体伤害 0.12 秒内置冷却
const SHIELD_CHIP_INTERVAL := 0.12
## 破盾后 3 秒内任何来源都削不动盾：给回盾留一段安全窗，别被连续秒破
const SHIELD_CHIP_LOCK_AFTER_BREAK := 3.0
## 封窗期（还是锁着的时候）回盾速度翻倍：它趁这段时间把护体抢回来
const SHIELD_REGEN_LOCK_MULT := 2.0
## 平A（不带功法的普攻）削盾减半：破盾要靠异色功法或防御手段，不能站着狂点左键
const SHIELD_CHIP_NORMAL_MULT := 0.5
const SHIELD_REGEN_P1 := 8.0
const SHIELD_REGEN_P2 := 6.0
const SHIELD_BREAK_STAGGER_P1 := 1.2
const SHIELD_BREAK_STAGGER_P2 := 0.9
const SHIELD_VULN_P1 := 1.3
const SHIELD_VULN_P2 := 1.4
## 护体即将破时，BOSS 主动翻面的阈值
const SHIELD_FLIP_THRESHOLD := 35.0
## 同属性连打触发倒悬的次数
const COUNTER_STREAK := 3
const PLAYER_TYPE_WINDOW := 3.0

# ===================== 决策 =====================
const REPEAT_PENALTY_1 := 3.0
const REPEAT_PENALTY_2 := 6.0
const SCORE_JITTER := 0.6
const TRIPLE_STEPS := 3
const TRIPLE_DASH_TIME := 0.20
const TRIPLE_GAP := 0.10
const TRIPLE_SPEED := 720.0
const WIND_TICKS := 3
const WIND_INTERVAL := 0.45
const COUNTER_WINDOW := 0.8

# ===================== 冷却 =====================
## 只给「机制 / 大招」上冷却；普通招式靠评分与重复惩罚控制节奏。
const SKILL_COOLDOWNS := {
	SKILL_FLIP: 12.0,
	SKILL_COUNTER: 8.0,
	SKILL_COLLAPSE: 18.0,
	SKILL_WIND: 10.0,
	SKILL_FISH: 6.0,
	SKILL_TRIPLE: 6.0,
	SKILL_FINGER: 4.0,
	SKILL_PALM: 2.5,
}

enum ExtraState { DASH = 100, COUNTER = 101, WIND = 102 }

# ===================== 状态 =====================
var _phase2: bool = false
var _current_skill: String = ""
var _recent_skills: Array = []
var _skill_cooldowns: Dictionary = {}
var _windup_locked: bool = false
var _windup_total: float = 0.0
var _player_skill_time: float = -999.0

# 护体
var _shield_polarity: int = POLARITY_YANG
var _shield_hp: float = SHIELD_MAX
var _shield_break_timer: float = 0.0
var _shield_regen_active: bool = false
var _shield_regen_left: float = 0.0
var _shield_chip_cd: float = 0.0
var _shield_chip_lock: float = 0.0
## 这一发是不是普攻（玩家在扣血前 notify_normal_attack_hit；take_damage 顶部消费掉）
var _normal_attack_pending: bool = false
var _shield_ui: ColorRect = null
var _shield_bg: ColorRect = null
var _polarity_label: Label = null
var _mark_yang_label: Label = null
var _mark_yin_label: Label = null

# 玩家近期行为
var _player_last_type: String = ""
var _player_same_type: int = 0
var _player_type_timer: float = 0.0

# 突进
var _dash_left: int = 0
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_timer: float = 0.0
var _dash_pause: float = 0.0

# 阴风
var _wind_center: Vector2 = Vector2.ZERO
var _wind_ticks_left: int = 0
var _wind_timer: float = 0.0

# 倒悬
var _counter_active: bool = false
var _counter_timer: float = 0.0
var _counter_absorbed: float = 0.0


# ===================== 初始化 =====================

func _setup() -> void:
	boss_id = "boss_02"
	_recent_skills.clear()
	_skill_cooldowns.clear()
	_shield_polarity = POLARITY_YANG
	_shield_hp = SHIELD_MAX
	_shield_break_timer = 0.0
	_shield_chip_cd = 0.0
	_shield_chip_lock = 0.0
	_shield_regen_active = false
	_update_shield_ui()


func _build_shield_ui() -> void:
	# 血条在场景里（BossBase 要求 $HPBarBG/HPBar）；护体条与标记在代码里建，
	# 避免 .tscn 里堆一堆 ColorRect/Label。换皮只改颜色，不改结构。
	if _shield_bg != null and is_instance_valid(_shield_bg):
		return
	_shield_bg = ColorRect.new()
	_shield_bg.name = "ShieldBarBG"
	_shield_bg.position = Vector2(-32.0, -194.0)
	_shield_bg.size = Vector2(64.0, 5.0)
	_shield_bg.color = Color(0.06, 0.07, 0.08, 0.85)
	_shield_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_bg.z_index = 70
	add_child(_shield_bg)

	_shield_ui = ColorRect.new()
	_shield_ui.name = "ShieldBar"
	_shield_ui.position = Vector2.ZERO
	_shield_ui.size = Vector2(64.0, 5.0)
	_shield_ui.color = _polarity_color()
	_shield_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_bg.add_child(_shield_ui)

	_polarity_label = Label.new()
	_polarity_label.name = "PolarityLabel"
	_polarity_label.position = Vector2(-36.0, -232.0)
	_polarity_label.size = Vector2(72.0, 20.0)
	_polarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_polarity_label.add_theme_font_size_override("font_size", 15)
	_polarity_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	_polarity_label.add_theme_constant_override("outline_size", 4)
	_polarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_polarity_label.z_index = 71
	add_child(_polarity_label)

	_mark_yang_label = _make_mark_label("阳印", Color(1.0, 0.84, 0.46, 1.0), -56.0)
	_mark_yin_label = _make_mark_label("阴印", Color(0.46, 0.82, 0.86, 1.0), 6.0)


func _make_mark_label(text: String, color: Color, x: float) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(x, -254.0)
	label.size = Vector2(50.0, 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 71
	label.visible = false
	add_child(label)
	return label


func _polarity_color() -> Color:
	return Color(0.98, 0.82, 0.38, 1.0) if _shield_polarity == POLARITY_YANG \
		else Color(0.36, 0.86, 0.94, 1.0)


# ===================== 主循环 =====================

func _physics_process(delta: float) -> void:
	# 蓄力前段仍可追踪玩家；后段锁定方向，给玩家走位/弹反的窗口
	if state == BossState.WINDUP and not _windup_locked:
		if state_timer <= _windup_total * 0.35:
			_windup_locked = true
		else:
			_update_facing_to_target()
	_tick_skill_cooldowns(delta)
	_tick_shield(delta)
	_tick_player_type_window(delta)
	_update_shield_ui()
	super._physics_process(delta)


func _tick_skill_cooldowns(delta: float) -> void:
	for sid in _skill_cooldowns.keys():
		var left := float(_skill_cooldowns[sid]) - delta
		if left <= 0.0:
			_skill_cooldowns.erase(sid)
		else:
			_skill_cooldowns[sid] = left


func _tick_shield(delta: float) -> void:
	_shield_chip_cd = maxf(0.0, _shield_chip_cd - delta)
	_shield_chip_lock = maxf(0.0, _shield_chip_lock - delta)
	if _shield_break_timer > 0.0:
		_shield_break_timer = maxf(0.0, _shield_break_timer - delta)
		if _shield_break_timer <= 0.0:
			# 硬直结束 → 开始回盾
			_shield_regen_active = true
			_shield_regen_left = SHIELD_REGEN_P2 if _phase2 else SHIELD_REGEN_P1
			_shield_hp = 0.0
		return
	if _shield_regen_active:
		_shield_regen_left = maxf(0.0, _shield_regen_left - delta)
		var duration := SHIELD_REGEN_P2 if _phase2 else SHIELD_REGEN_P1
		# 封窗期里回得更快（×2）：这段时间谁也削不动盾，等于它在空档里抢护体
		var rate := SHIELD_MAX / maxf(duration, 0.1)
		if _shield_chip_lock > 0.0:
			rate *= SHIELD_REGEN_LOCK_MULT
		_shield_hp = minf(SHIELD_MAX, _shield_hp + rate * delta)
		if _shield_regen_left <= 0.0 or _shield_hp >= SHIELD_MAX - 0.001:
			_shield_hp = SHIELD_MAX
			_shield_regen_active = false


func _tick_player_type_window(delta: float) -> void:
	if _player_type_timer > 0.0:
		_player_type_timer = maxf(0.0, _player_type_timer - delta)
		if _player_type_timer <= 0.0:
			_player_same_type = 0
			_player_last_type = ""


func _is_extra_state(s: int) -> bool:
	return s == ExtraState.DASH or s == ExtraState.COUNTER or s == ExtraState.WIND


func _tick_extra_state(delta: float) -> void:
	match state:
		ExtraState.DASH:
			_tick_dash(delta)
		ExtraState.COUNTER:
			_tick_counter(delta)
		ExtraState.WIND:
			_tick_wind(delta)


func _update_shield_ui() -> void:
	if state == BossState.DEAD:
		if _shield_bg != null and is_instance_valid(_shield_bg):
			_shield_bg.visible = false
		if _polarity_label != null and is_instance_valid(_polarity_label):
			_polarity_label.visible = false
		if _mark_yang_label != null and is_instance_valid(_mark_yang_label):
			_mark_yang_label.visible = false
		if _mark_yin_label != null and is_instance_valid(_mark_yin_label):
			_mark_yin_label.visible = false
		return
	if _shield_ui == null or not is_instance_valid(_shield_ui):
		_build_shield_ui()
		if _shield_ui == null:
			return
	var ratio := clampf(_shield_hp / SHIELD_MAX, 0.0, 1.0)
	var sealed := _shield_chip_lock > 0.0
	_shield_ui.size = Vector2(64.0 * ratio, 5.0)
	_shield_ui.color = Color(0.55, 0.55, 0.60, 0.8) if sealed else _polarity_color()
	if _polarity_label != null:
		if _shield_break_timer > 0.0:
			_polarity_label.text = "破"
			_polarity_label.add_theme_color_override("font_color", Color(1.0, 0.40, 0.34, 1.0))
		elif sealed:
			# 封窗期：条已变灰，字写「封」，玩家看得见「这段时间削不动」
			_polarity_label.text = "封"
			_polarity_label.add_theme_color_override("font_color", Color(0.74, 0.76, 0.82, 1.0))
		else:
			_polarity_label.text = "阳" if _shield_polarity == POLARITY_YANG else "阴"
			_polarity_label.add_theme_color_override("font_color", _polarity_color())
	if _mark_yang_label != null:
		_mark_yang_label.visible = has_debuff("yang_mark")
	if _mark_yin_label != null:
		_mark_yin_label.visible = has_debuff("yin_mark")


# ===================== 距离 / 行为 =====================

func _dist() -> float:
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return 99999.0
	return edge_distance_to((target as Node2D).global_position)


func _front_factor() -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	var to_p: Vector2 = (target as Node2D).global_position - global_position
	if to_p.length_squared() < 0.0001:
		return 1.0
	return facing.normalized().dot(to_p.normalized())


func _has_ally_summon() -> bool:
	return not get_tree().get_nodes_in_group("ally_summon").is_empty()


func notify_player_skill_used() -> void:
	_player_skill_time = Time.get_ticks_msec() / 1000.0


## 玩家在**扣血前**调用：这一发是普攻（不带功法）。护体只认一半削盾量。
## take_damage 顶部会立刻消费这个标记，所以哪怕这一发被无敌帧吞掉也不会泄到下一发。
func notify_normal_attack_hit() -> void:
	_normal_attack_pending = true


# ===================== 选招 =====================

func _on_chase_reached(_dist: float) -> void:
	_choose_next_action()


func _choose_next_action() -> void:
	if state == BossState.WINDUP or state == BossState.ATTACK or state == BossState.RECOVER:
		return
	if _is_extra_state(state):
		return

	# 1. 玩家连续同属性 → 倒悬（反制连打）
	if _player_same_type >= COUNTER_STREAK and _skill_available(SKILL_COUNTER) \
			and randf() < 0.85:
		_begin_skill(SKILL_COUNTER)
		return

	# 2. 护体快破 → 主动翻面，重置玩家的属性优势
	if _shield_hp <= SHIELD_FLIP_THRESHOLD and _shield_hp > 0.0 \
			and _skill_available(SKILL_FLIP) and randf() < 0.8:
		_begin_skill(SKILL_FLIP)
		return

	# 3. 常规评分
	var best := _pick_best_skill()
	if best == "":
		state = BossState.CHASE
		return
	_begin_skill(best)


func _pick_best_skill() -> String:
	var scored: Array = []
	for sid in SCORED_SKILLS:
		if not _skill_available(String(sid)):
			continue
		scored.append({"id": String(sid), "score": _score_skill(String(sid))})
	if scored.is_empty():
		return ""
	for entry in scored:
		entry["score"] = float(entry["score"]) + randf() * SCORE_JITTER
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	return String(scored[0]["id"])


func _skill_available(skill_id: String) -> bool:
	if not ALL_SKILLS.has(skill_id):
		return false
	if _skill_cd_left(skill_id) > 0.0:
		return false
	var b := MoveDB.resolve_boss(skill_id)
	if b.is_empty():
		return false
	if skill_id == SKILL_COLLAPSE:
		return _phase2
	var dist := _dist()
	match skill_id:
		SKILL_PALM:
			return dist <= 240.0
		SKILL_FINGER:
			return dist <= 460.0
		SKILL_TRIPLE:
			return dist <= 620.0
		SKILL_WIND:
			return dist <= 560.0
		SKILL_FISH:
			return dist <= 540.0
		SKILL_COUNTER:
			return dist <= 220.0
	return true


func _score_skill(skill_id: String) -> float:
	var dist := _dist()
	var score := 0.0
	match skill_id:
		SKILL_PALM:
			score = 3.2 - absf(dist - 80.0) / 120.0
			if dist < 150.0:
				score += 0.6
		SKILL_FINGER:
			score = 2.4 - absf(dist - 260.0) / 220.0
			if dist > 160.0:
				score += 0.5
		SKILL_TRIPLE:
			score = 2.6 - absf(dist - 360.0) / 260.0
			if dist > 280.0:
				score += 1.2
		SKILL_WIND:
			score = 2.2 - absf(dist - 320.0) / 260.0
			if dist > 220.0 and dist < 520.0:
				score += 0.5
			if _has_ally_summon():
				score += 1.4
		SKILL_FISH:
			score = 2.3 - absf(dist - 280.0) / 220.0
			if dist > 160.0 and dist < 420.0:
				score += 0.4
		SKILL_COLLAPSE:
			score = 2.4 - absf(dist - 120.0) / 160.0
			if dist > 320.0:
				score -= 2.0
		SKILL_COUNTER:
			score = 0.8
			if _player_same_type >= COUNTER_STREAK:
				score += 4.0
		_:
			score = 0.0
	return score - _repeat_penalty(skill_id)


func _repeat_penalty(skill_id: String) -> float:
	if _recent_skills.is_empty():
		return 0.0
	if String(_recent_skills[0]) != skill_id:
		return 0.0
	if _recent_skills.size() >= 2 and String(_recent_skills[1]) == skill_id:
		return REPEAT_PENALTY_2
	return REPEAT_PENALTY_1


func _record_used(skill_id: String) -> void:
	_recent_skills.push_front(skill_id)
	if _recent_skills.size() > 4:
		_recent_skills.resize(4)


func _skill_cd_left(skill_id: String) -> float:
	return float(_skill_cooldowns.get(skill_id, 0.0))


func _start_skill_cooldown(skill_id: String) -> void:
	var cd := float(SKILL_COOLDOWNS.get(skill_id, 0.0))
	if cd > 0.0:
		_skill_cooldowns[skill_id] = cd


# ===================== 出招 =====================

func _begin_skill(skill_id: String) -> void:
	_current_skill = skill_id
	_windup_total = _windup_time_for(skill_id)
	_windup_locked = false
	state = BossState.WINDUP
	state_timer = _windup_total
	# 招式型起手也要广播（新手指引靠它等抬手；漏了教学对真 BOSS 不触发）
	attack_windup.emit(_attack_kind_of(skill_id), _windup_total)
	if target != null and is_instance_valid(target):
		_set_facing(((target as Node2D).global_position - global_position).normalized())
	var b := MoveDB.resolve_boss(skill_id)
	var color := skill_name_color(String(b.get("attack_kind", "")))
	show_skill_name_at_windup(String(b.get("form_name", skill_id)), _windup_total, color)
	_play_form_anim(skill_id, _windup_total + 0.15)


func _windup_time_for(skill_id: String) -> float:
	var b := MoveDB.resolve_boss(skill_id)
	var w := float(b.get("windup", WINDUP_TIME_P1))
	if phase == 2:
		w *= float(b.get("windup_mult_p2", 1.0))
	return maxf(0.12, w)


func _fire_attack() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	_reset_visual()
	GameState.play_sfx("boss_attack")
	_fire_skill()


func _fire_skill() -> void:
	var b := MoveDB.resolve_boss(_current_skill)
	if b.is_empty():
		_finish_skill()
		return
	match _current_skill:
		SKILL_PALM:
			_cast_palm(b)
		SKILL_FINGER:
			_cast_finger(b)
		SKILL_FLIP:
			_cast_flip(b)
		SKILL_COLLAPSE:
			_cast_collapse(b)
		SKILL_TRIPLE:
			_begin_triple(b)
		SKILL_WIND:
			_begin_wind(b)
		SKILL_FISH:
			_cast_fish(b)
		SKILL_COUNTER:
			_begin_counter(b)
		_:
			_finish_skill()


func _finish_skill() -> void:
	var b := MoveDB.resolve_boss(_current_skill)
	_record_used(_current_skill)
	_start_skill_cooldown(_current_skill)
	state = BossState.RECOVER
	state_timer = maxf(0.20, float(b.get("recover", RECOVER_TIME_P1)) * (0.85 if _phase2 else 1.0))
	velocity = Vector2.ZERO
	_windup_locked = false
	_current_skill = ""


# ===================== 八式 =====================

## 招式 → 特效条目（BOSS 侧三叠 / 风 / 双鱼 / 倒悬用更浓的 fx_* 变体，其余与玩家同一条目）
const FX_IDS := {
	SKILL_PALM: "skill_yinyang_palm",
	SKILL_FINGER: "skill_yinyang_finger",
	SKILL_FLIP: "skill_yinyang_flip",
	SKILL_COLLAPSE: "skill_yinyang_collapse",
	SKILL_TRIPLE: "fx_yinyang_triple",
	SKILL_WIND: "fx_yinyang_wind",
	SKILL_FISH: "fx_yinyang_fish",
	SKILL_COUNTER: "fx_yinyang_counter",
}


## 在**出手帧**播特效。BOSS 的状态机这时已经把判定打出去了，所以必须走 play_at_strike：
## 玩家版的 play() 会再等一遍前摇，两仪的前摇 0.6~1.2 秒 → 特效比判定晚整整一拍（用户报的
## 「出伤时机不吻合」）。位置也交给 SkillFx 自己算：近战取身体中心，field / stomp 贴脚下。
## origin 只给「点状出生」的招（风场中心），扇形与圆形 AOE 必须留在本体原点。
func _play_yinyang_fx(fx_id: String, b: Dictionary, dir: Vector2, origin: Variant = null) -> void:
	var real := String(FX_IDS.get(fx_id, fx_id))
	SkillFx.play_at_strike(self, real, b, dir, origin)


func _cast_palm(b: Dictionary) -> void:
	_play_yinyang_fx(SKILL_PALM, b, facing)
	_hit_all_in_form(SKILL_PALM)
	_finish_skill()


func _cast_finger(b: Dictionary) -> void:
	_play_yinyang_fx(SKILL_FINGER, b, facing)
	_hit_all_in_form(SKILL_FINGER)
	_finish_skill()


func _cast_flip(_b: Dictionary) -> void:
	# 只翻仪态，不回盾：玩家刚磨掉的护体仍然保留，只是属性优势被重置
	_shield_polarity = POLARITY_YIN if _shield_polarity == POLARITY_YANG else POLARITY_YANG
	_update_shield_ui()
	_play_yinyang_fx(SKILL_FLIP, _b, facing)
	show_windup_line("阴阳易位！", 0.7, 19, 170.0, _polarity_color(), -180.0)
	# 翻面时把贴脸的玩家推开，给 BOSS 一个重新拉开距离的窗口
	if target != null and is_instance_valid(target) and target.has_method("take_knockback"):
		var away: Vector2 = (target as Node2D).global_position - global_position
		if away.length_squared() > 0.0001:
			target.take_knockback(away.normalized() * 240.0)
	_finish_skill()


func _cast_collapse(b: Dictionary) -> void:
	_play_yinyang_fx(SKILL_COLLAPSE, b, facing)
	_hit_all_in_form(SKILL_COLLAPSE)
	_finish_skill()


# ---------- 阳关三叠：三段突进 ----------

func _begin_triple(_b: Dictionary) -> void:
	_dash_left = TRIPLE_STEPS
	_dash_pause = 0.0
	_start_dash_segment()
	state = ExtraState.DASH
	state_timer = 0.0
	# 起手不播特效：这一式命中的是每段冲到头的那一下（_tick_dash），
	# 在起手播会让玩家以为「一抬脚就出伤」，也给不出三段的节奏


func _start_dash_segment() -> void:
	if target != null and is_instance_valid(target):
		var to_p: Vector2 = (target as Node2D).global_position - global_position
		if to_p.length_squared() > 0.0001:
			_dash_dir = clamp_burst_dir(to_p.normalized(), 150.0)
	_set_facing(_dash_dir)
	_dash_timer = TRIPLE_DASH_TIME


func _tick_dash(delta: float) -> void:
	if _dash_pause > 0.0:
		_dash_pause = maxf(0.0, _dash_pause - delta)
		velocity = Vector2.ZERO
		if _dash_pause <= 0.0:
			_start_dash_segment()
		return
	velocity = _dash_dir * TRIPLE_SPEED
	_dash_timer -= delta
	if _dash_timer > 0.0:
		return
	velocity = Vector2.ZERO
	_hit_all_in_form(SKILL_TRIPLE)
	# 第几段就盖几条卦爻：1 → 2 → 3，三踏叠齐正好是乾卦 ☰
	var fb := MoveDB.resolve_boss(SKILL_TRIPLE)
	fb["sigil_bars"] = 4 - _dash_left
	_play_yinyang_fx(SKILL_TRIPLE, fb, _dash_dir)
	_dash_left -= 1
	if _dash_left <= 0:
		_finish_skill()
	else:
		_dash_pause = TRIPLE_GAP


# ---------- 阴风蚀骨：目标点三段风场 ----------

func _begin_wind(b: Dictionary) -> void:
	if target != null and is_instance_valid(target):
		_wind_center = (target as Node2D).global_position
	else:
		_wind_center = global_position + facing * 220.0
	_wind_ticks_left = WIND_TICKS
	_wind_timer = 0.0
	state = ExtraState.WIND
	state_timer = 0.0
	_spawn_wind_visual(b)
	_tick_wind(0.0)


func _tick_wind(delta: float) -> void:
	if delta > 0.0:
		_wind_timer -= delta
		if _wind_timer > 0.0:
			return
	_hit_all_in_form(SKILL_WIND, -1.0, "", _wind_center)
	_wind_ticks_left -= 1
	if _wind_ticks_left <= 0:
		_finish_skill()
		return
	_wind_timer = WIND_INTERVAL


func _spawn_wind_visual(b: Dictionary) -> void:
	# 风场是「点状出生」的招：origin 传目标点，出来的领域圈正好压住三跳的判定圆
	_play_yinyang_fx(SKILL_WIND, b, Vector2.RIGHT, _wind_center)


# ---------- 阴阳双鱼：一物理一法术 ----------

func _cast_fish(b: Dictionary) -> void:
	var dir := _aim_dir()
	var dmg := MoveDB.boss_damage(SKILL_FISH, attack_power, phase)
	# 两枚同向出手，靠**反相的正弦横移**分开并交叉：阳先摆左、阴先摆右，
	# 途中对调侧别 —— 看着就是两条鱼交错游过来，而不是两发散射。
	# 平均航线仍在瞄准线上，所以远程不会因为越飞越开而打空。
	_launch_fish(dir, "physical_projectile", dmg, 0.0, b)
	_launch_fish(dir, "elemental", dmg, PI, b)
	_play_yinyang_fx(SKILL_FISH, b, facing)
	_finish_skill()


func _launch_fish(dir: Vector2, kind: String, dmg: float, swim_phase: float, b: Dictionary) -> void:
	var proj := _spawn_projectile(kind, muzzle_position(SKILL_FISH))
	if proj == null:
		return
	# 双鱼本体形象：一阳金、一阴青；之前没指定外观，走的是 18px 占位方块
	var is_yang := kind != "elemental"
	proj.call("set_visual_override",
		"liangyi_fish_yang" if is_yang else "liangyi_fish_yin")
	proj.set("align_visual", true)
	proj.set("align_visual_right", true)
	# 鱼身后面垫一层同色柔光：暗场地里平涂贴图会像贴纸，加法光晕才读作术法
	var glow := Sprite2D.new()
	glow.texture = SkillFx.dot_texture()
	glow.material = SkillFx.additive_material()
	glow.centered = true
	glow.z_index = -1
	glow.scale = Vector2(0.72, 0.46)
	glow.modulate = Color(1.0, 0.82, 0.40, 0.34) if is_yang \
		else Color(0.44, 0.88, 1.0, 0.34)
	proj.add_child(glow)
	proj.set("direction", dir.normalized())
	proj.set("speed", 520.0)
	proj.set("damage", dmg)
	proj.set("source", self)
	proj.set("life_timer", 3.0)
	proj.set("homing_target", null)
	proj.set("swim_amp", float(b.get("swim_amp", 0.0)))
	proj.set("swim_freq", float(b.get("swim_freq", 0.0)))
	proj.set("swim_phase", swim_phase)
	proj.set("launch_side", 1.0 if is_zero_approx(swim_phase) else -1.0)


# ---------- 两仪倒悬：同属性吸收 / 异属性打断 ----------

func _begin_counter(b: Dictionary) -> void:
	_counter_active = true
	_counter_timer = COUNTER_WINDOW
	_counter_absorbed = 0.0
	state = ExtraState.COUNTER
	state_timer = 0.0
	velocity = Vector2.ZERO
	_update_facing_to_target()
	show_skill_name_at_windup(String(b.get("form_name", "两仪倒悬")), COUNTER_WINDOW,
		skill_name_color("physical_melee"))
	_play_form_anim(SKILL_COUNTER, COUNTER_WINDOW + 0.15)
	_play_yinyang_fx(SKILL_COUNTER, b, facing)


func _tick_counter(delta: float) -> void:
	if not _counter_active:
		# 架招被异属性打断：不进入反击，立即收招（破盾时已经被 STAGGER 接管）
		state = BossState.RECOVER
		state_timer = 0.25
		velocity = Vector2.ZERO
		return
	_counter_timer -= delta
	if _counter_timer <= 0.0:
		_fire_counter_burst()


func _fire_counter_burst() -> void:
	if not _counter_active:
		return
	_counter_active = false
	var b := MoveDB.resolve_boss(SKILL_COUNTER)
	var mult := 1.0 + minf(_counter_absorbed * 0.004, 1.0)
	var dmg := MoveDB.boss_damage(SKILL_COUNTER, attack_power, phase) * mult
	state = BossState.ATTACK
	state_timer = 0.15
	_play_yinyang_fx("fx_yinyang_counter_hit", b, facing)
	_hit_all_in_form(SKILL_COUNTER, dmg, "fire")
	_counter_absorbed = 0.0
	_finish_skill()


# ===================== 命中判定 =====================

## 通用命中：扇形 / 直线 / 圆形。center_override 用于风场这类「目标点圆形」。
func _hit_all_in_form(form_id: String, dmg_override: float = -1.0,
		element_override: String = "", center_override: Variant = null) -> bool:
	var b := MoveDB.resolve_boss(form_id)
	if b.is_empty():
		return false
	var dmg := dmg_override
	if dmg < 0.0:
		dmg = MoveDB.boss_damage(form_id, attack_power, phase)
	var kind := String(b.get("attack_kind", "physical_melee"))
	var elem := element_override if element_override != "" else String(b.get("damage_element", ""))
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
		var dist := to_u.length()
		if dist > reach + maxf(16.0, body_radius() * 0.5):
			continue
		if shape != MoveDB.SHAPE_CIRCLE and center_override == null and dist > 1.0:
			if facing.normalized().dot(to_u / dist) < cos(half):
				continue
		if _deal_damage_to_unit(u, dmg, kind, elem):
			_apply_form_debuff(u, b)
			hit = true
	return hit


func _apply_form_debuff(unit: Node, b: Dictionary) -> void:
	var debuff_id := String(b.get("debuff_on_hit", ""))
	if debuff_id == "" or not unit.has_method("apply_debuff"):
		return
	unit.call("apply_debuff", debuff_id, float(b.get("debuff_time", 3.0)))


func _deal_damage_to_unit(unit: Node, amount: float, attack_kind: String, element: String) -> bool:
	var before := unit_hp(unit)
	if not deal_damage_to(unit, amount, attack_kind, element):
		return false
	var after := unit_hp(unit)
	if before < 0.0 or after < 0.0:
		return true
	return after < before


func _aim_dir() -> Vector2:
	if target != null and is_instance_valid(target):
		var d: Vector2 = (target as Node2D).global_position - global_position
		if d.length_squared() > 0.0001:
			return d.normalized()
	return facing


# ===================== 护体结算 =====================

func _is_same_polarity(is_yang_attack: bool) -> bool:
	return (is_yang_attack and _shield_polarity == POLARITY_YANG) \
		or (not is_yang_attack and _shield_polarity == POLARITY_YIN)


func _chip_shield(amount: float, bypass_cd: bool = false) -> void:
	if _shield_hp <= 0.0 or _shield_break_timer > 0.0:
		return
	# 破盾后的 3 秒封窗：任何来源（伤害 / 弹反 / 完美闪避）都削不动，
	# 让玩家那段窗口用来打输出，而不是把刚立起来的盾连秒破
	if _shield_chip_lock > 0.0:
		return
	if not bypass_cd and _shield_chip_cd > 0.0:
		return
	_shield_chip_cd = SHIELD_CHIP_INTERVAL
	_shield_hp = maxf(0.0, _shield_hp - amount)
	if _shield_hp <= 0.0:
		_break_shield()


func _break_shield() -> void:
	if _shield_break_timer > 0.0:
		return
	_shield_hp = 0.0
	_shield_regen_active = false
	_shield_break_timer = SHIELD_BREAK_STAGGER_P2 if _phase2 else SHIELD_BREAK_STAGGER_P1
	_shield_chip_lock = SHIELD_CHIP_LOCK_AFTER_BREAK
	_counter_active = false
	_current_skill = ""
	# 破盾必翻面：玩家的属性优势被重置，下一轮要重新读颜色
	_shield_polarity = POLARITY_YIN if _shield_polarity == POLARITY_YANG else POLARITY_YANG
	state = BossState.STAGGER
	state_timer = _shield_break_timer
	velocity = Vector2.ZERO
	_windup_locked = false
	_tween_pulse(1.0, 0.0)
	_play_yinyang_fx("fx_yinyang_shield_break",
		{"hit_shape": MoveDB.SHAPE_CIRCLE, "range": 140.0}, Vector2.RIGHT)
	GameState.play_sfx("attack_hit")
	show_windup_line("护体崩碎！", 0.8, 22, 220.0, _polarity_color(), -190.0)


func take_damage(amount: float, source: Node = null, damage_kind: String = "physical",
		element: String = "", from_projectile: bool = false) -> void:
	# 普攻标记在入口就消费掉：哪怕这一发被无敌帧 / 转阶段吞掉，也不会泄到下一发
	var is_normal_hit := _normal_attack_pending
	_normal_attack_pending = false
	if state == BossState.DEAD or phase_transitioning:
		super.take_damage(amount, source, damage_kind, element, from_projectile)
		return
	var is_yang_attack := damage_kind.begins_with("physical")

	# 两仪转的前摇**必成**，不吃伤害打断：抢这一口气只能靠弹反 / 闪避
	# 倒悬架招：同属性吸收，异属性打断
	if _counter_active:
		if _is_same_polarity(is_yang_attack):
			_counter_absorbed += amount
			show_windup_line("倒悬·卸力", 0.35, 15, 140.0, _polarity_color(), -178.0)
			_flash_attack(Color(1.0, 0.95, 0.55))
			return
		_counter_active = false
		_counter_timer = 0.0
		_current_skill = ""
		state = BossState.STAGGER
		state_timer = 0.45
		_chip_shield(30.0, true)
		show_windup_line("倒悬·破！", 0.5, 18, 160.0, Color(1.0, 0.45, 0.38, 1.0), -178.0)

	var same := _is_same_polarity(is_yang_attack)
	var mult := 0.5 if same else 1.3
	if _shield_break_timer > 0.0:
		mult *= SHIELD_VULN_P2 if _phase2 else SHIELD_VULN_P1
	# 同色伤害只减伤、**不磨盾**：盾要靠异色伤害或防御手段削
	if not same:
		# 普攻只削一半（7）：破盾的正解是异色功法与弹反 / 完美闪避，不是站着点左键
		var chip := SHIELD_CHIP_OPPOSITE * (SHIELD_CHIP_NORMAL_MULT if is_normal_hit else 1.0)
		_chip_shield(chip)

	var before := current_hp
	super.take_damage(amount * mult, source, damage_kind, element, from_projectile)
	if current_hp < before - 0.001:
		_track_player_type(damage_kind)


func _track_player_type(damage_kind: String) -> void:
	var t := "physical" if damage_kind.begins_with("physical") else "elemental"
	if t == _player_last_type:
		_player_same_type += 1
	else:
		_player_last_type = t
		_player_same_type = 1
	_player_type_timer = PLAYER_TYPE_WINDOW


func on_parried(source: Node) -> void:
	if state == BossState.DEAD:
		return
	super.on_parried(source)
	_current_skill = ""
	_chip_shield(SHIELD_CHIP_PARRY, true)
	show_windup_line("震盾！", 0.45, 17, 130.0, Color(1.0, 0.92, 0.62, 1.0), -176.0)


## 玩家完美闪避：由 player.gd 在 _trigger_perfect_dodge() 里广播
func notify_perfect_dodge() -> void:
	if state == BossState.DEAD or phase_transitioning:
		return
	_chip_shield(SHIELD_CHIP_PERFECT_DODGE, true)
	show_windup_line("闪避震盾！", 0.45, 16, 160.0, Color(0.55, 0.90, 1.0, 1.0), -176.0)


## 玩家普通闪避：只在 BOSS 正在出招时给一点小震盾，避免无脑翻滚刷盾
func notify_dodge_started() -> void:
	if state == BossState.DEAD or phase_transitioning:
		return
	if state != BossState.WINDUP and state != BossState.ATTACK:
		return
	_chip_shield(SHIELD_CHIP_DODGE)


# ===================== 阶段 =====================

func _on_phase_two() -> void:
	_phase2 = true
	_current_skill = ""
	# 二阶段重置护体：玩家必须再破一次盾，压力升级
	_shield_hp = SHIELD_MAX
	_shield_break_timer = 0.0
	_shield_chip_cd = 0.0
	_shield_chip_lock = 0.0
	_shield_regen_active = false
	_shield_polarity = POLARITY_YIN if _shield_polarity == POLARITY_YANG else POLARITY_YANG
	_update_shield_ui()
	show_windup_line("阴阳合一！", 1.0, 24, 240.0, Color(1.0, 0.88, 0.45, 1.0), -196.0)
	FxPlayer.spawn(self, "fx_phase_gather", {
		"position": body_center(),
		"lifetime": 0.8,
	})


func is_phase_two() -> bool:
	return _phase2


func shield_ratio() -> float:
	return clampf(_shield_hp / SHIELD_MAX, 0.0, 1.0)


func shield_polarity_name() -> String:
	return "阳" if _shield_polarity == POLARITY_YANG else "阴"
