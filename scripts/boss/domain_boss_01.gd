class_name DomainBoss01
extends BossBase
## 凡界守关 BOSS —— 刀客（刀痕博弈）
##
## 设计案：《万界秘境》刀客 BOSS 战斗机制设计案 V1.0
##
## 四个互相关联的系统：
##   1. ~~刀势（0-100）~~ —— **已于 2026-10-22 用户要求整体删除**。
##      原规则：只释放招式就涨（每招 +20），60 起满势断岳按概率抢跑、100 必放。
##      现在满势断岳改为「**目标站在刀痕上时释放**」，刀势相关的变量/评分/HUD 全部移除。
##   2. 行为读取 —— 每轮收招后按「距离 / 方位 / 近期行为 / 场地 / 风险 / 重复」评分选招，
##      不使用固定技能循环
##   3. 刀痕场地 —— 部分物理招式留下刀痕（留存 10 秒）；法术激活时刀痕当场化为
##      一次斩击（法术伤害，系数 = 本次激活数量），斩后刀痕消失（共用 ScarField）
##   4. 攻防博弈 —— 出招承诺：蓄力后段锁定方向，收招不能取消，玩家可读招破解
##
## 遵守的既有硬约束：
##   - 无韧性条、无破防、无 UI 预警 / 红圈 / 范围标记
##   - 双阶段（50%），二阶段只强化既有招式，不加新机制
##   - 物理近战可弹刀；法术不可弹；弹中给短暂僵直（时长按该招伤害系数决定）
##   - 远程物理（投射物）弹反不给僵直（由 BossBase.on_parried 的调用路径保证）
##
## 招式数据在 MoveDB（共享形态），本脚本只负责「什么时候用、怎么用」。

# ===================== 招式 id（MoveDB.FORMS 的键）=====================
const SKILL_P1 := "form_blade_slash"
const SKILL_P2 := "form_blade_heavy"
const SKILL_P3 := "form_blade_dash"
const SKILL_P4 := "form_blade_turn"
const SKILL_P5 := "form_blade_scar"
const SKILL_M1 := "form_blade_qi"
const SKILL_M2 := "form_blade_field"
const SKILL_M3 := "form_blade_counter"
const SKILL_M4 := "form_blade_peak"

const PHYSICAL_SKILLS: Array = [SKILL_P1, SKILL_P2, SKILL_P3, SKILL_P4, SKILL_P5]
const SPELL_SKILLS: Array = [SKILL_M1, SKILL_M2, SKILL_M3, SKILL_M4]
const ALL_SKILLS: Array = [SKILL_P1, SKILL_P2, SKILL_P3, SKILL_P4, SKILL_P5,
	SKILL_M1, SKILL_M2, SKILL_M3, SKILL_M4]

# ===================== 满势断岳的触发条件（2026-10-22 用户定）=====================
## 旧规则（刀势）已整体删除，现在的触发条件只有一条：
##   **目标正站在任意一处刀痕上** → 满势断岳进入候选（仍受它自身的法术冷却约束）
## 这样刀客的博弈从「攒刀势」变成「把玩家逼进刀痕 / 玩家自己躲开刀痕」。
## ⚠ 判定用 `target`（仇恨目标）而不是硬取玩家：仇恨系统可能让刀客盯着召唤物。

# ===================== 僵直 =====================
## 弹刀僵直 = 基础值 + 招式伤害系数 × 系数权重
## 让高伤招式被弹开后获得更长的输出窗口
const STAGGER_BASE := 0.45
const STAGGER_PER_COEFF := 4.5

# ===================== 决策参数 =====================
## 同一招式连续使用两次后的权重惩罚
const REPEAT_PENALTY_1 := 3.0
const REPEAT_PENALTY_2 := 6.0
## 平局时的随机抖动幅度
const SCORE_JITTER := 0.6

## 「其它近战招式」的判定射程上限（2026-10-23 用户定）
## 取所有近战扇形/圆形招式里 range 最大的那个 —— 留痕斩 220
## （横斩 150 / 沉步竖斩 165 / 回身斩 115 / 纳势反击 210 / 封路刀域 210）。
## 玩家站得比这个更远时，除突进斩以外**没有任何近战招式够得着**，
## 此时破步突进斩就是刀客唯一能"自己贴上去"的手段 → 权重上调。
const NEAR_MELEE_REACH := 220.0

# ===================== 运行时状态 =====================
## 当前正在执行的招式 id（空 = 未在出招）
var current_skill: String = ""
## 法术独立冷却：form_id -> 剩余秒
var spell_cooldowns: Dictionary = {}
## 最近使用过的招式（新→旧），用于重复惩罚
var _recent_skills: Array = []
## 蓄力阶段方向是否已锁定
var _windup_locked := false
## 本次蓄力的总时长（用于判断锁定时机）
var _windup_total := 0.0
## 蓄力开始时玩家位置（判定「是否靠移动脱离」）
var _player_pos_at_windup: Vector2 = Vector2.ZERO
## 该位置是否有效（没有真正蓄力过时不要拿默认值误判「脱离」）
var _windup_pos_valid: bool = false
## 玩家最近一次释放功法的时间（秒，来自 Time）
var _player_skill_time: float = -999.0
## 突进状态
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_remaining: float = 0.0
var _dash_speed: float = 0.0
## 连续突进斩还剩几段（破步突进斩 = 2，见 MoveDB 的 dash_times）
var _dash_left: int = 0
## 段间停顿剩余时间：>0 时停在原地蓄下一段，不移动也不结算
var _dash_pause: float = 0.0
## 阶段二是否已进入（用于二阶段倍率）
var _phase2: bool = false
## 二阶段专属「弹刀」留下的追击 buff：下一次近战招式出手前先闪到能打中目标的位置
## （由 try_parry_player_projectile 置位，_consume_parry_chase 消费）
var _parry_chase_ready: bool = false

## 弹回远程时的伤害倍率（相对玩家原本打出的伤害）
## ⚠ 不能直接 100% 反射：玩家打 BOSS 的伤害远高于自己血量（实测一发 100 伤害能把
##   100 血的玩家直接打死，五连射全弹回等于自杀）。0.3 是"痛但不致死"的取舍，可调。
const PARRY_REFLECT_MULT := 0.3

# ===================== 额外状态 =====================
enum ExtraState { DASH = 100, CASTING_SPELL = 101 }


func _setup() -> void:
	boss_id = "boss_01"
	spell_cooldowns.clear()
	_recent_skills.clear()


# ===================== 主循环 =====================

func _physics_process(delta: float) -> void:
	# 蓄力前段仍可追踪玩家；后段锁定方向，保证玩家能靠走位破解
	if state == BossState.WINDUP and not _windup_locked:
		if state_timer <= _windup_total * 0.35:
			_windup_locked = true
		else:
			_update_facing_to_target()
	super._physics_process(delta)


## 法术冷却（刀势机制已删除，这里只管冷却）
func _tick_cooldowns(delta: float) -> void:
	# 法术冷却（阶段切换不重置）
	for sid in spell_cooldowns.keys():
		var left := float(spell_cooldowns[sid]) - delta
		if left <= 0.0:
			spell_cooldowns.erase(sid)
		else:
			spell_cooldowns[sid] = left


func _is_extra_state(s: int) -> bool:
	return s == ExtraState.DASH or s == ExtraState.CASTING_SPELL


func _tick_extra_state(delta: float) -> void:
	if state == ExtraState.DASH:
		_dash_step(delta)


# ===================== 目标与距离辅助 =====================

func _distance_to_player() -> float:
	if target == null or not is_instance_valid(target):
		return 99999.0
	return global_position.distance_to(target.global_position)


## 玩家相对 BOSS 的方位系数：1 = 正前，-1 = 正后
func _player_front_factor() -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	var to_player: Vector2 = target.global_position - global_position
	if to_player.length_squared() < 0.0001:
		return 1.0
	return facing.normalized().dot(to_player.normalized())


## 玩家是否刚刚（窗口内）释放过功法 —— 纳势反击的触发条件
func _player_just_used_skill(window: float = 1.4) -> bool:
	return (Time.get_ticks_msec() / 1000.0 - _player_skill_time) <= window


## 玩家在战斗中的技能释放会被记录（由 player 通过 group 广播式调用）
func notify_player_skill_used() -> void:
	_player_skill_time = Time.get_ticks_msec() / 1000.0


# ===================== 选招 =====================

func _on_chase_reached(_dist: float) -> void:
	_choose_next_action()


func _choose_next_action() -> void:
	# 出招承诺：正在蓄力/出手/收招时不允许换招（由状态机保证，这里只做兜底）
	if state == BossState.WINDUP or state == BossState.ATTACK or state == BossState.RECOVER:
		return

	# 满势断岳不再「抢跑」：它和其它招式一起走评分，只是可用条件是「目标踩在刀痕上」
	var best := _pick_best_skill()
	if best == "":
		state = BossState.CHASE
		return
	_begin_skill(best)


## 目标是否正站在某处刀痕上（满势断岳的唯一触发条件）
## ⚠ 用 target（仇恨目标）而不是直接取玩家：仇恨系统可能让刀客盯着召唤物
func _target_on_scar() -> bool:
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return false
	var tp: Vector2 = (target as Node2D).global_position
	for s in get_tree().get_nodes_in_group("blade_scar"):
		if not is_instance_valid(s) or not (s is Node2D):
			continue
		if tp.distance_to((s as Node2D).global_position) <= float(s.get("scar_radius")):
			return true
	return false


## 对所有可用招式打分，返回最高分招式 id（无可用返回空串）
func _pick_best_skill() -> String:
	var scored: Array = []
	for sid in ALL_SKILLS:
		var skill_id := String(sid)
		if not _skill_available(skill_id):
			continue
		scored.append({"id": skill_id, "score": _score_skill(skill_id)})
	if scored.is_empty():
		return ""

	# 加一点随机抖动，避免同样的局面每次都出同一招（「随机只用于打破平局」）
	for entry in scored:
		entry["score"] = float(entry["score"]) + randf() * SCORE_JITTER

	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	return String(scored[0]["id"])


## 招式是否进入候选集（距离、方位、资源、冷却）
func _skill_available(skill_id: String) -> bool:
	var dist := _distance_to_player()
	var b := MoveDB.resolve_boss(skill_id)
	if b.is_empty():
		return false

	# 法术必须冷却就绪
	if skill_id in SPELL_SKILLS and spell_cd_left(skill_id) > 0.0:
		return false

	match skill_id:
		SKILL_P1, SKILL_P2:
			return dist <= 190.0
		SKILL_P3:
			return dist > 140.0 and dist <= 430.0
		SKILL_P4:
			# 放宽：玩家在**侧面**即可触发（原设计要求绕到侧后方，实测几乎打不出来）
			return dist <= 210.0 and _player_front_factor() < 0.35
		SKILL_P5:
			return dist > 120.0 and dist <= 330.0 and _normal_scar_count() < ScarField.MAX_NORMAL
		SKILL_M1:
			return dist >= 170.0
		SKILL_M2:
			# 场地没有普通刀痕就没意义，不浪费决策
			return _normal_scar_count() > 0
		SKILL_M3:
			# 放宽：原为 dist <= 175 + 1.4s 窗口，实战几乎碰不到（玩家近身施法太少），
			# 导致这门反制招「永远不触发」。改成中近距离 + 更长窗口。
			return dist <= 260.0 and _player_just_used_skill(2.0)
		SKILL_M4:
			# 「目标踩在刀痕上」才可用（法术冷却由上面的通用检查保证）
			return _target_on_scar()
	return false


## 评分：S = D（距离/方位） + B（行为） + E（联动） + G（场地） - R（风险） - Q（重复）
## ⚠ E 分量现在**只对满势断岳有意义**：刀势机制已删除（2026-10-22），
##   满势断岳改为「目标踩刀痕」触发，E 这里给它一个保底高分，让它踩中条件时能被选中。
func _score_skill(skill_id: String) -> float:
	var dist := _distance_to_player()
	var front := _player_front_factor()
	var b := MoveDB.resolve_boss(skill_id)

	var d_score := 0.0
	var b_score := 0.0
	var e_score := 0.0
	var g_score := 0.0
	var r_score := 0.0

	match skill_id:
		SKILL_P1:
			# 近距离正面：距离越近越好，正面加成
			d_score = 3.0 - absf(dist - 110.0) / 90.0
			if front > 0.6:
				b_score += 1.5
		SKILL_P2:
			d_score = 2.6 - absf(dist - 120.0) / 90.0
			# 玩家持续正面移动时权重提高
			if front > 0.75:
				b_score += 2.0
			r_score = 1.0  # 起手慢，容易被打断位置
		SKILL_P3:
			d_score = 2.8 - absf(dist - 280.0) / 160.0
			# 玩家躲在**其它近战招式射程之外**时权重显著提高（2026-10-23 用户定）：
			# 这个距离上横斩/竖斩/回身斩/留痕斩全都够不着，突进是唯一能主动贴上来的近战。
			# 旧口径只有 dist > 220 时 +2.2，起手太保守，玩家一退就只会站着放刀气。
			if dist > NEAR_MELEE_REACH:
				b_score += 4.8
				# 330 以上其它近战彻底无望（留痕斩上限 330），再叠一档
				if dist > 330.0:
					b_score += 1.2
			r_score = 1.8  # 突进落空收招长
		SKILL_P4:
			# 理想距离放宽到 150（大张角转身斩，中距离也能用）
			d_score = 2.6 - absf(dist - 150.0) / 110.0
			# 玩家在侧方即视为高价值（分数提到 4.0，保证每场都能见到）
			b_score += 4.0
			r_score = 0.6
		SKILL_P5:
			d_score = 2.4 - absf(dist - 240.0) / 120.0
			# 中距离停留
			if dist > 170.0:
				b_score += 1.6
			# 场地还能再放刀痕才划算
			g_score += 2.2 if _normal_scar_count() < 2 else 0.8
			r_score = 0.9
		SKILL_M1:
			d_score = 2.2 - absf(dist - 320.0) / 220.0
			if dist > 260.0:
				b_score += 1.4
			# 场上有普通刀痕 → 激活收益（激活即斩击，越多道伤害系数越高）
			if _normal_scar_count() > 0:
				g_score += 2.6
			r_score = 1.2
		SKILL_M2:
			d_score = 1.6
			# 玩家待在刀痕附近时封路价值高
			var near := _nearest_scar_distance()
			if near < 120.0:
				b_score += 2.4
			g_score += 2.6 + float(_normal_scar_count()) * 0.4
			r_score = 1.0
		SKILL_M3:
			d_score = 2.0 - absf(dist - 170.0) / 130.0
			b_score += 3.2  # 玩家刚刚出招，反击窗口
			r_score = 1.4  # 玩家可能已经拉走
		SKILL_M4:
			d_score = 1.8
			# 能进候选就说明「目标正踩在刀痕上」—— 这是设计上最想打的一击，给足权重
			e_score += 5.0
			# 玩家明显在侧向时收益下降
			if absf(front) < 0.35:
				r_score += 2.5
			r_score += 1.2

	# 通用：玩家贴脸时，远距离招式风险更高
	if skill_id in SPELL_SKILLS and dist < 60.0:
		r_score += 2.0

	var repeat := _repeat_penalty(skill_id)
	return d_score + b_score + e_score + g_score - r_score - repeat


## 重复惩罚：连续使用同一招权重下降，避免「看起来灵活实际总同一招」
func _repeat_penalty(skill_id: String) -> float:
	if _recent_skills.is_empty():
		return 0.0
	if String(_recent_skills[0]) != skill_id:
		return 0.0
	if _recent_skills.size() >= 2 and String(_recent_skills[1]) == skill_id:
		return REPEAT_PENALTY_2
	return REPEAT_PENALTY_1


# ===================== 出招 =====================

## 进入蓄力（出招承诺开始）
## 蓄力时的体型脉动倍率。基类默认 1.25（兽型的「充气」感），人形用 1.15：
## 脉动太夸张会把「挥刀」这个主表演盖掉 —— 玩家看到的是"BOSS 胀大了一下"，
## 而不是"它把刀抡圆了"。2026-10-26 用户要求大幅挥刀时一并调低。
func windup_pulse_scale() -> float:
	return 1.15


func _begin_skill(skill_id: String) -> void:
	current_skill = skill_id
	_windup_locked = false
	_windup_total = _windup_time_for(skill_id)
	state = BossState.WINDUP
	state_timer = _windup_total
	# 招式型起手也要广播（新手指引靠它等抬手；漏了教学对真 BOSS 不触发）
	attack_windup.emit(_attack_kind_of(skill_id), _windup_total)
	if target != null and is_instance_valid(target):
		_set_facing((target.global_position - global_position).normalized())
		_player_pos_at_windup = target.global_position
		_windup_pos_valid = true
	# 技能名在**前摇的这一瞬间**飘出，并一直挂到技能释放（hold = 前摇时长）
	# 颜色按招式类型：物理黄 / 法术蓝（用户 2026-10-20 定）
	show_skill_name_at_windup(_form_name_of(skill_id), _windup_total,
		BossBase.skill_name_color(_attack_kind_of(skill_id)))
	# 起手动作与蓄力同时开始，压进「前摇 + 出手」：最后一帧落在伤害判定那一帧上，
	# 玩家看到刀挥到哪就知道这一招打到哪 —— 动作本身就是唯一预警（无红圈 / 无 UI 提示）
	_play_form_anim(skill_id, _windup_total + 0.15)
	_on_attack_windup(0)


## 招式的显示名（招式表 form_name —— 前摇飘字用它，与技能面板口径一致）
func _form_name_of(skill_id: String) -> String:
	return String(MoveDB.resolve_boss(skill_id).get("form_name", ""))


func _windup_time_for(skill_id: String) -> float:
	var b := MoveDB.resolve_boss(skill_id)
	var base := float(b.get("windup", 0.8))
	if _phase2:
		base *= float(b.get("windup_mult_p2", 1.0))
	return maxf(0.15, base)


func _on_attack_windup(_kind: int) -> void:
	# 无 UI 预警：只用身体蓄力色与缩放表达（不同招式不同色）
	var color := Color(1.0, 0.42, 0.28)
	match current_skill:
		SKILL_P2:
			color = Color(1.0, 0.55, 0.2)
		SKILL_P3:
			color = Color(1.0, 0.35, 0.35)
		SKILL_P4:
			color = Color(0.9, 0.5, 0.6)
		SKILL_P5:
			color = Color(0.95, 0.65, 0.3)
		SKILL_M1, SKILL_M4:
			color = Color(1.0, 0.75, 0.45)
		SKILL_M2:
			color = Color(1.0, 0.5, 0.35)
		SKILL_M3:
			color = Color(1.0, 0.85, 0.4)
	_show_windup(color)


## 蓄力结束 → 出手
func _fire_attack() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	_reset_visual()
	GameState.play_sfx("boss_attack")
	# 弹刀追击：若上一段是「弹开玩家远程」后的追击 buff，近战出手前先贴到目标身前
	_consume_parry_chase()
	_execute_skill(current_skill)


func _do_attack(_kind: int) -> void:
	# 由 _fire_attack 直接调用 _execute_skill，这里不重复实现
	pass


## 执行具体招式
func _execute_skill(skill_id: String) -> void:
	var b := MoveDB.resolve_boss(skill_id)
	if b.is_empty():
		state = BossState.RECOVER
		state_timer = _recover_time()
		return

	_record_used(skill_id)
	# 法术进冷却
	if skill_id in SPELL_SKILLS:
		_start_spell_cooldown(skill_id)

	_play_skill_visual(skill_id, b)

	match skill_id:
		SKILL_P3:
			_start_dash(skill_id, b)
			return
		SKILL_M2:
			_cast_field(b)
			_finish_skill()
			return
		SKILL_M1, SKILL_M4:
			_fire_blade_qi(skill_id, b)
			return
		SKILL_P5:
			# 留痕斩：斩完在攻击终点留下刀痕（`scar_effect: "create"`）
			# ⚠ 之前没有这个分支，P5 落到默认分支只结算命中，所以「不留痕」
			var hit5 := _hit_player_in_form(b)
			if hit5:
				_apply_hit_side_effects(b)
			_spawn_scar_for(b, facing)
			_finish_skill()
			return
		_:
			var hit := _hit_player_in_form(b)
			if hit:
				_apply_hit_side_effects(b)
			_finish_skill()


## 招式视觉（走 ArtDB.EFFECTS，换美术只改表）
func _play_skill_visual(skill_id: String, b: Dictionary) -> void:
	# ⚠ 招式名不在这里显示：改为前摇瞬间由 _begin_skill 统一飘出（释放时才淡出）
	# 与玩家共用同一套 SkillFx：BOSS 已在出手帧，直接播命中层
	if SkillFx.play_form_at_strike(self, String(b.get("form_id", skill_id)), b, facing):
		return
	var visual_id := String(b.get("visual_id", ""))
	if visual_id == "":
		return
	var params := {
		# 从身体中心发出，不是脚底（否则贴图越高越像「扫地板」）
		"position": body_center(),
		"rotation": facing.angle(),
		"lifetime": maxf(0.14, float(b.get("active", 0.12)) + 0.12),
	}
	var shape := String(b.get("hit_shape", ""))
	if shape == MoveDB.SHAPE_FAN or shape == MoveDB.SHAPE_CIRCLE:
		params["radius"] = float(b.get("range", 120.0)) * 0.8
		params["sweep_deg"] = float(b.get("angle", 90.0))
	elif shape == MoveDB.SHAPE_PROJECTILE:
		params["radius"] = 16.0
	FxPlayer.spawn(self, visual_id, params)


## 扇形/圆形判定：命中返回 true
## 扇形/圆形判定：命中**所有**该打的单位（敌方刀客打玩家+友军；被召唤的友军刀客只打敌方 BOSS）
## 每个单位各自算距离与夹角，召唤物站得远就不会被误伤
func _hit_player_in_form(b: Dictionary) -> bool:
	var reach := float(b.get("range", 120.0))
	var shape := String(b.get("hit_shape", MoveDB.SHAPE_FAN))
	var dmg := MoveDB.boss_damage(String(b.get("form_id", "")), attack_power, phase)
	var kind := String(b.get("attack_kind", "physical_melee"))
	var half := deg_to_rad(float(b.get("angle", 90.0)) * 0.5)
	var hit := false
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - global_position
		var dist := to_u.length()
		if dist > reach:
			continue
		if shape != MoveDB.SHAPE_CIRCLE and dist > 1.0:
			if facing.normalized().dot(to_u / dist) < cos(half):
				continue
		if _apply_damage_to_unit(u, dmg, kind):
			hit = true
	return hit


## 对单个单位结算并判断「是否真掉血」（玩家可能处于无敌帧 / 弹反）
func _apply_damage_to_unit(unit: Node, amount: float, attack_kind: String) -> bool:
	var before := unit_hp(unit)
	if not deal_damage_to(unit, amount, attack_kind):
		return false
	var after := unit_hp(unit)
	if before < 0.0 or after < 0.0:
		return true
	return after < before


## 兼容入口：只对当前 target 结算（剑客的反击 / 天剑阵等「锁定单人」的伤害仍走这里）
func _deal_damage_to_player(amount: float, attack_kind: String) -> bool:
	return _apply_damage_to_unit(target, amount, attack_kind)


## 命中附带效果：小减速（slow_on_hit）与 debuff（debuff_on_hit）两条路，互不排斥
## 2026-10-23：沉步竖斩不再用小减速，改成挂「重伤」（见 MoveDB 的 debuff_on_hit）
func _apply_hit_side_effects(b: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var db := String(b.get("debuff_on_hit", ""))
	# ⚠ 玩家与 BOSS 的同名接口参数语义**不一样**，必须按类型分派，不能统一传 self：
	#   Player.apply_slow(duration, ratio)        / BossBase.apply_slow(mult, seconds)  ← 前两参顺序相反
	#   Player.apply_debuff(id, dur, quiet:bool)  / BossBase.apply_debuff(id, dur, from_unit:Node)
	# 传错类型会直接抛 "Cannot convert argument 3 from Object to bool" 把整局崩掉（2026-11-09 刀客实测）。
	if target is BossBase:
		if bool(b.get("slow_on_hit", false)):
			target.apply_slow(float(b.get("slow_ratio", 0.35)), float(b.get("slow_time", 0.6)))
		if db != "":
			# 第三个参数只给战报认归属：点燃的跳伤要记到**挂上它的那只**名下，
			# 不然持续伤害会在表里凭空消失（自洽判据差一截）。
			target.apply_debuff(db, float(b.get("debuff_time", 3.0)), self)
	else:
		# 玩家 / 分身 / 木桩：只有两参有效，第三个位置是 quiet(bool)，这里不能传实例
		if bool(b.get("slow_on_hit", false)) and target.has_method("apply_slow"):
			target.apply_slow(float(b.get("slow_time", 0.6)), float(b.get("slow_ratio", 0.35)))
		if db != "" and target.has_method("apply_debuff"):
			target.apply_debuff(db, float(b.get("debuff_time", 3.0)))


## 招式收尾：进入收招
func _finish_skill() -> void:
	state = BossState.RECOVER
	state_timer = _recover_time() * _recover_mult_for(current_skill)
	_windup_locked = false


func _recover_mult_for(skill_id: String) -> float:
	# 落空代价已在评分里体现；这里给突进类稍长收招
	match skill_id:
		SKILL_P3:
			return 1.35
		SKILL_P2:
			return 1.2
		_:
			return 1.0


# ===================== 突进斩 =====================

func _start_dash(skill_id: String, b: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		_finish_skill()
		return
	# 段数来自招式表（破步突进斩 = 2，其它突进技仍是 1）
	_dash_left = maxi(1, int(b.get("dash_times", 1)))
	_dash_pause = 0.0
	_begin_dash_segment(b)


## 起一段突进：**每一段都重新取一次玩家方位**（第二段会追着玩家拐）
## 2026-10-23 用户定：BOSS 侧第二次突进斩要根据玩家方位重新改方向。
func _begin_dash_segment(b: Dictionary) -> void:
	_dash_dir = (target.global_position - global_position).normalized() \
		if target != null and is_instance_valid(target) \
		else facing.normalized()
	_set_facing(_dash_dir)
	_dash_speed = float(b.get("dash_speed", 600.0))
	if _phase2:
		_dash_speed *= float(b.get("dash_p2_mult", 1.0))
	_dash_remaining = float(b.get("dash_time", 0.22))
	state = ExtraState.DASH
	state_timer = _dash_remaining


## 段间停顿结束后开下一段（重新读一次招式表；方向在 _begin_dash_segment 里重新取玩家方位）
func _begin_next_dash_segment() -> void:
	if target == null or not is_instance_valid(target):
		_finish_skill()
		return
	_dash_pause = 0.0
	var b := MoveDB.resolve_boss(current_skill)
	# ⚠ 第二段必须**自己再播一次**刀光与出手音效（2026-10-23 用户报「第二段攻击效果丢失」）：
	#   `_execute_skill()` 只在起手时播过一次视觉，第二段只调 _begin_dash_segment 的话，
	#   会出现「有位移、有伤害判定，但屏幕上什么都没有」——第二刀看起来像凭空挨的。
	#   顺序不能反：先 _begin_dash_segment（它会把 facing 改成新的突进方向），
	#   再播视觉，否则第二刀会朝上一段的老方向扫。
	_reset_visual()
	_begin_dash_segment(b)
	_play_skill_visual(current_skill, b)
	GameState.play_sfx("boss_attack")


func _dash_step(delta: float) -> void:
	# 段间停顿：站定蓄下一段（给玩家一个能看清第二刀要来的窗口）
	if _dash_pause > 0.0:
		velocity = Vector2.ZERO
		_dash_pause -= delta
		if _dash_pause <= 0.0:
			_begin_next_dash_segment()
		return
	var b := MoveDB.resolve_boss(current_skill)
	# 冲过头保护（2026-10-23）：突进斩的伤害是「突进**结束后**身前的扇形」，
	# 一旦这一步越过目标，扇形就永远扫不到人 —— 距离翻倍后这件事变得非常容易发生，
	# 表现就是「第二段明明冲了却打空」（第一段已经把人甩在身后了）。
	# 所以靠近目标时提前收步，停在射程的一半处，两段都能落到人身上。
	if target != null and is_instance_valid(target):
		var gap: Vector2 = (target as Node2D).global_position - global_position
		var keep := float(b.get("range", 130.0)) * 0.5
		if gap.length() <= _dash_speed * delta + keep:
			velocity = Vector2.ZERO
			_dash_remaining = 0.0
			_finish_dash_segment(b)
			return
	velocity = _dash_dir * _dash_speed
	_dash_remaining -= delta
	if _dash_remaining > 0.0:
		return
	velocity = Vector2.ZERO
	_finish_dash_segment(b)


## 一段突进收尾：落刀 + 留痕（两段各结算一次，总伤害是原来的 2 倍）
## 返回后由调用方决定是否继续下一段
func _finish_dash_segment(b: Dictionary) -> void:
	var hit := _hit_player_in_form(b)
	if hit:
		_apply_hit_side_effects(b)
	_spawn_scar_for(b, _dash_dir)
	_dash_left -= 1
	if _dash_left > 0:
		_dash_pause = maxf(float(b.get("dash_gap", 0.0)), 0.0)
		if _dash_pause <= 0.0:
			_begin_next_dash_segment()
		return
	_finish_skill()


# ===================== 刀痕 =====================

## 只读查询用：没有刀痕系统时返回 null，统计类函数按 0 处理
func _field() -> ScarField:
	return ScarField.get_active()


func _normal_scar_count() -> int:
	var f := _field()
	return f.normal_count() if f != null else 0


func _nearest_scar_distance() -> float:
	var f := _field()
	if f == null or target == null or not is_instance_valid(target):
		return 99999.0
	return f.nearest_scar_distance(target.global_position, BladeScar.SIDE_BOSS, self)


## 按形态的 scar_effect 生成刀痕
## 注意：刀痕是刀客功法流派的玩法组件，只有真的有招式要留痕时才创建（ensure）
func _spawn_scar_for(b: Dictionary, dir: Vector2) -> void:
	if String(b.get("scar_effect", "")) != "create":
		return
	var f := ScarField.ensure()
	if f == null:
		return
	var offset := float(b.get("scar_offset", 120.0))
	var pos := global_position + dir.normalized() * offset
	# 二阶段刀痕也吃本招的 damage_mult_p2，否则「伤害翻倍」只覆盖直伤、铺刀流不涨
	var power := attack_power * (float(b.get("damage_mult_p2", 1.0)) if _phase2 else 1.0)
	var scar := f.spawn_scar(pos, BladeScar.SIDE_BOSS, power, SCAR_BOSS_DAMAGE_COEFF,
			target, "elemental", self)
	# 友军召唤物：刀痕激活不走 deal_damage_to()，倍率必须显式带过去
	if scar != null and is_instance_valid(scar):
		scar.ally_scale = ally_damage_scale if is_ally else 1.0

## BOSS 刀痕的伤害系数（× attack_power）
## 实际系数 = 本值 × 本次激活的刀痕数量，所以「铺满刀痕再一次激活」才是这个流派的满伤手法。
## 2026-10-22 用户要求调高刀痕伤害：1.0 → **1.6**（同时把判定/显示半径 34 → 52，见 blade_scar.gd）
const SCAR_BOSS_DAMAGE_COEFF := 1.6


# ===================== 法术：刀气 / 刀域 =====================

## 刀气追击 / 满势断岳：直线投射物 + 沿途激活刀痕
func _fire_blade_qi(skill_id: String, b: Dictionary) -> void:
	var reach := float(b.get("range", 560.0))
	# 沿途激活刀痕（最多 scar_ignite_max 处）；没有刀痕就不创建场管理器
	var f := ScarField.get_active()
	if f != null and String(b.get("scar_effect", "")) == "ignite_path":
		f.ignite_in_path(global_position, global_position + facing * reach,
			int(b.get("scar_ignite_max", 1)), BladeScar.SIDE_BOSS, self)

	# 刀气从**刀尖**甩出（骨骼锚点，见 daoke_rig/rig.tres 的 muzzle 表）；
	# 没登记锚点（满势断岳走 ult_windup）就回落身体前方 20px 的老口径
	var spawn := muzzle_position(skill_id)
	var proj := _spawn_projectile("elemental", spawn)
	if proj == null:
		_finish_skill()
		return
	# 出生点在刀尖（比身体高、靠前），方向必须按「刀尖 → 目标」算，不能抄 facing
	proj.direction = _aim_from(spawn)
	proj.speed = float(b.get("speed", 560.0))
	proj.damage = MoveDB.boss_damage(skill_id, attack_power, phase)
	proj.source = self
	# 与玩家共用同一门功法的弹体外观（刀气追击 / 满势断岳 = skill_blade_qi）
	_apply_skill_projectile_visual(proj, String(b.get("form_id", skill_id)))
	# 投射物命中后由 boss_projectile 自行处理，这里只管收招
	_finish_skill()


## 封路刀域：激活范围内刀痕
func _cast_field(b: Dictionary) -> void:
	# 没有刀痕可激活时直接空放（评分阶段已保证至少有一处才会选这招）
	var f := ScarField.get_active()
	if f == null:
		return
	var radius := float(b.get("range", 210.0))
	f.ignite_in_radius(global_position, radius, int(b.get("scar_ignite_max", 2)),
		BladeScar.SIDE_BOSS, self)


# ===================== 法术冷却 =====================

func spell_cd_left(skill_id: String) -> float:
	return float(spell_cooldowns.get(skill_id, 0.0))


func _start_spell_cooldown(skill_id: String) -> void:
	var b := MoveDB.resolve_boss(skill_id)
	var cd := float(b.get("cooldown_p2", 0.0)) if _phase2 else float(b.get("cooldown_p1", 0.0))
	if cd > 0.0:
		spell_cooldowns[skill_id] = cd


# ===================== 记录 =====================

func _record_used(skill_id: String) -> void:
	_recent_skills.push_front(skill_id)
	if _recent_skills.size() > 4:
		_recent_skills.resize(4)


# ===================== 阶段 =====================

func _on_phase_two() -> void:
	_phase2 = true
	# 阶段切换：不重置法术冷却、不清刀痕、不回血、不瞬移（设计案硬要求）
	# 提高移动速度（由 MOVE_SPEED_P2 提供）与决策倾向；
	# 伤害 ×2 走各招的 damage_mult_p2（MoveDB，用户 2026-10-27 定），不在这里乘 attack_power


# ===================== 弹刀僵直 =====================

## 弹刀成功：僵直时长按当前招式的伤害系数决定
## 高伤招式被弹开后给玩家更长的输出窗口
func on_parried(source: Node) -> void:
	if state == BossState.DEAD:
		return
	var coeff := float(MoveDB.resolve_boss(current_skill).get("stagger_coeff", 0.12))
	state = BossState.STAGGER
	state_timer = STAGGER_BASE + coeff * STAGGER_PER_COEFF
	velocity = Vector2.ZERO
	_windup_locked = false
	_flash_attack(Color(1.0, 1.0, 0.3))
	# 踉跄位移：被格开后沿来源方向后退
	# ⚠ 先 is_instance_valid 再 `is`：对已释放实例用 `is` 会报 freed 错误（顺序不能反）
	if source != null and is_instance_valid(source) and source is Node2D:
		var back := (global_position - (source as Node2D).global_position).normalized()
		_bump_back(back * 120.0)


# ===================== 二阶段专属：弹开玩家的物理远程 =====================
## 用户 2026-10-20 定：刀客转二阶段后获得「弹刀」能力（不是功法，玩家学不到）。
##   - 玩家的**物理远程**攻击 → 必定被完美弹开，本次伤害完全作废
##   - 玩家的近战 / 法术攻击 → 完全不受影响（永远不触发）
## 由 BossBase.take_damage 在收到 from_projectile=true 且 damage_kind=physical 时调用。
## 返回 true = 已弹开（伤害不再结算）。
func try_parry_player_projectile(source: Node = null) -> bool:
	if not _phase2:
		return false
	if state == BossState.DEAD:
		return false
	# ① 把这次攻击原样弹回玩家（2026-10-21 用户定）：方向取「刀客 → 玩家」，
	#    伤害沿用玩家原本打出的数值，由投射物自己飞回去结算
	if source != null and is_instance_valid(source) and source.has_method("deflect"):
		var back := facing.normalized()
		if target != null and is_instance_valid(target):
			back = ((target as Node2D).global_position - global_position).normalized()
		source.call("deflect", back, PARRY_REFLECT_MULT)
	# ② 表现：金色光芒迸发（大）+ 小火花（叠层次）+ 身体金光 + 头顶飘字
	FxPlayer.spawn(self, "fx_boss_parry_gold", {
		"position": body_center() + facing * 14.0,
		"lifetime": 0.42,
	})
	FxPlayer.spawn(self, "fx_deflect_spark", {
		"position": body_center() + facing * 14.0,
		"lifetime": 0.18,
		"radius": 30.0,
	})
	_flash_attack(Color(1.0, 0.95, 0.55))
	GameState.play_sfx("attack_hit")
	# 飘字用「物理黄」，与技能名飘字同一套配色
	# 抬到与技能名同一层，避开玩家伤害数字；刀客头顶血条也不会挤在一起
	show_windup_line("弹刀！", 0.45, 20, 160.0, UIKit.C_DMG_PHYS, -170.0)
	# 追击 buff：下一次近战招式出手前先贴到目标身前
	_parry_chase_ready = true
	# 临时调试：确认弹刀真的触发了（编辑器「输出」面板可见），排查完可删
	print("[boss_parry] 刀客二阶段弹开并弹回玩家远程（%.0f%% 血）" % (current_hp / max_hp * 100.0))
	return true


## 弹刀后的追击：下一次**近战**招式出手前，先闪到能打中目标的位置
## - 远程招式（hit_shape = projectile）不消耗 buff，继续等近战
## - 落点保持在招式射程的 70%，既不落空也不会贴脸到看不见动作
func _consume_parry_chase() -> void:
	if not _parry_chase_ready:
		return
	var b := MoveDB.resolve_boss(current_skill)
	if String(b.get("hit_shape", "")) == MoveDB.SHAPE_PROJECTILE:
		return
	_parry_chase_ready = false
	if target == null or not is_instance_valid(target):
		return
	var reach := maxf(40.0, float(b.get("range", 120.0)) * 0.7)
	var to_self: Vector2 = global_position - (target as Node2D).global_position
	var dir := to_self.normalized() if to_self.length_squared() > 0.0001 else facing.normalized()
	# 追击表现：原地留一团火花，再瞬间贴上去（省略中间的飞行过程，读起来像"瞬步"）
	FxPlayer.spawn(self, "fx_deflect_spark", {
		"position": Vector2.ZERO,
		"lifetime": 0.16,
		"radius": 26.0,
	})
	global_position = (target as Node2D).global_position + dir * reach
	_set_facing(-dir)


# ===================== 调试信息 =====================

func is_phase_two() -> bool:
	return _phase2
