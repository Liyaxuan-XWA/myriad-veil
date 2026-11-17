class_name DomainBoss01C
extends BossBase
## 凡界第 3 位守关 BOSS —— 剑客（剑意蓄压体系）
##
## 设计案（用户 2026-10-19 口述，已按项目口径落地）：
##
## 一、剑意（0~5，Boss 头顶 5 格显示）
##   - 释放「刺 / 撩 / 斩 / 云」+1；该招**成功命中玩家**再 +1
##   - 二阶段翻倍（释放 +2 / 命中 +2）
##   - BOSS 每累计被打 5 次，剑意 -1（玩家进攻能压制资源）
##   - 「穿」「万剑归宗」「一剑开天」不产生剑意（用户只列了上面四个技能）
##
## 二、四个常规技能
##   刺：快、远、窄（line，1.0 系数）
##   撩：速度/距离/范围中等（fan，2.0 系数）
##   斩：距离短、范围大、前摇大（fan，3.0 系数）
##   云：远程物理飞剑（projectile，1.0 系数，可弹反）
##
## 三、穿（机制技，不在评分池）
##   原地锁定玩家方向突刺，落到玩家身后；**连续释放两次远程（云）后强制触发**
##
## 四、万剑归宗（一阶段大招，CD 15s）
##   2 + 剑意×2 把飞剑从身侧飞出，放完清空剑意；二阶段禁用
##
## 五、一剑开天（二阶段解锁）
##   消耗全部剑意，每层 +18 射程；**满 5 层变为法术且范围巨大**
##   （form_sword_heaven_full，BOSS 专属形态，玩家学不到）
##
## 六、转阶段（HP ≤ 50%）
##   1. 推开玩家后，在玩家身边插三把剑连成三角形，2 秒后阵内斩决（3.0 法术系数）
##   2. 随后启动天剑阵：连续 5 把剑从天而降插地，玩家须躲开并打掉；
##      5 把落完后 5 秒仍未清完 → 每剩余一把回复 BOSS 5% 血量
##   3. 二阶段：伤害 ×1.5、移速/攻速提升、剑意获取翻倍、万剑归宗禁用
##
## ⚠ 二阶段伤害倍率用 1.5（用户指定），不是 BossBase 共有的 ×2 —— 本脚本不走
##   _damage_multiplier()，一律走 MoveDB.boss_damage(..., phase)。

# ===================== 招式 id =====================
const SKILL_STAB := "form_sword_stab"
const SKILL_LIFT := "form_sword_lift"
const SKILL_CHOP := "form_sword_chop"
const SKILL_CLOUD := "form_sword_cloud"
const SKILL_PIERCE := "form_sword_pierce"
const SKILL_MYRIAD := "form_sword_myriad"
const SKILL_HEAVEN := "form_sword_heaven"
const SKILL_HEAVEN_FULL := "form_sword_heaven_full"
const SKILL_TRIANGLE := "form_sword_triangle"

## 评分池：穿是机制技不参与，万剑归宗一阶段专属、一剑开天二阶段专属
const RANGED_SKILLS: Array = [SKILL_CLOUD]
const ALL_SKILLS: Array = [SKILL_STAB, SKILL_LIFT, SKILL_CHOP, SKILL_CLOUD,
	SKILL_MYRIAD, SKILL_HEAVEN]

# ===================== 剑意 =====================
const INTENT_MAX := 5
## 释放刺/撩/斩/云获得的剑意
const INTENT_PER_CAST := 1
## 该招成功命中玩家再获得的剑意
const INTENT_PER_HIT := 1
## BOSS 每累计被打这么多次，剑意 -1
const INTENT_DECAY_HITS := 5
## 一剑开天射程：每层剑意 +18 像素
const HEAVEN_RANGE_PER_INTENT := 18.0
## 满层剑意数（达到即「一剑开天」变法术巨斩）
const HEAVEN_FULL_INTENT := 5
## 满剑意一剑开天：招名飘字挂到**伤害打出的那一刻**才开始慢慢消失

# ===================== 穿 =====================
## 连续释放多少次远程后强制触发穿
const PIERCE_RANGED_STREAK := 2
## 招式表里没配时的兜底（正常都从 form_sword_pierce 的 dash_speed / dash_time 读）
const PIERCE_SPEED_FALLBACK := 950.0
const PIERCE_TIME_FALLBACK := 0.34

# ===================== 万剑归宗 =====================
const MYRIAD_BASE_COUNT := 2     ## 基础飞剑数
const MYRIAD_PER_INTENT := 2     ## 每层剑意追加的飞剑数
const MYRIAD_COOLDOWN := 15.0    ## 冷却（秒）

# ===================== 一剑开天 =====================
const HEAVEN_COOLDOWN := 12.0
## 满层形态（剑意盈天）在**对局里**一局能放几次（2026-11-03 用户：剑客实战太强，
## 建议改成满层的一剑开天只能用一次）。秘境 / 塔 / 演武场不看这个数 ——
## 判定在 `_heaven_full_allowed()`，那里 `team_id < 0` 直接放行。
const HEAVEN_FULL_CASTS_MATCH := 1

# ===================== 转阶段演出 =====================
## 三角封绝：三把剑插在玩家身边，这么久后斩决
const TRIANGLE_DELAY := 2.0
const TRIANGLE_RADIUS := 120.0
## 天剑阵：连续落下多少把、每把间隔、落完后多久结算、每把剩余回多少血
const SKY_SWORD_COUNT := 5
const SKY_SWORD_INTERVAL := 0.7
const SKY_SWORD_CHECK_DELAY := 5.0
const SKY_SWORD_HEAL_PER := 0.05
## 天剑命中系数（× attack_power）
const SKY_SWORD_DAMAGE_COEFF := 1.0

# ===================== 决策 =====================
const REPEAT_PENALTY_1 := 3.0
const REPEAT_PENALTY_2 := 6.0
const SCORE_JITTER := 0.6

# ===================== 运行时状态 =====================
## 当前剑意层数
var intent: int = 0
## BOSS 累计受击次数（每 INTENT_DECAY_HITS 次削一层剑意）
var _hits_taken: int = 0
## 连续释放远程的次数（云）
var _ranged_streak: int = 0
## 大招冷却计时
var _myriad_cd: float = 0.0
var _heaven_cd: float = 0.0
## 二阶段标记
var _phase2: bool = false
## 当前招式 id（弹刀僵直系数按它查）
var _current_form: String = ""
## 最近使用过的招式（新→旧），重复惩罚用
var _recent_skills: Array = []
## 蓄力方向锁定（同刀客：前 35% 可追踪，之后锁定）
var _windup_locked := false
var _windup_total := 0.0
## 法术类冷却：form_id → 剩余秒（云）
var spell_cooldowns: Dictionary = {}

## 穿：突进状态（方向与速度都在起手瞬间锁定，途中不变）
var _pierce_dir: Vector2 = Vector2.ZERO
var _pierce_speed: float = 950.0
var _pierce_remaining: float = 0.0
var _pierce_hit_done: bool = false

## 三角封绝：三把剑 + 倒计时
var _triangle_swords: Array = []
var _triangle_timer: float = 0.0
var _triangle_armed: bool = false

## 一剑开天：光柱在**前摇开始**就升起，劈到地面那一刻才结算伤害
## ⚠ 以前是前摇结束才播特效、并且当场就把伤害结掉：光柱还要再蓄 1.30 秒才落，
##   表现就是「先掉血，1.4 秒后才看见剑落地」（2026-10-27 用户报）。
var _heaven_fx: SwordHeavenFx = null
## 已定下的这一剑：形态（含按剑意加长的范围）、伤害、五行
var _heaven_form: Dictionary = {}
var _heaven_dmg: float = 0.0
var _heaven_elem: String = ""
## 这一剑起手时定下来是不是满层形态（`_fire_heaven` 记账时要用，
## 光看 intent 不行 —— 起手到落地的 1.3 秒里挨几下就会被 `_lose_intent` 削下去）
var _heaven_is_full: bool = false
## 满层形态已经放过几次。**只有对局棋子会拿它做"一局一次"的限制**
## （2026-11-03 用户：剑客实战表现太强）；秘境 / 塔 / 演武场不看这个数。
var _heaven_full_casts: int = 0

## 天剑阵：0 未启动 / 1 释放中 / 2 等待击破 / 3 已结算
var _sky_state: int = 0
var _sky_spawned: int = 0
var _sky_timer: float = 0.0
var _sky_check: float = 0.0

## 剑意 UI（头顶 5 个小剑条）
var _intent_icons: Array = []

enum ExtraState { PIERCE = 100 }

const SKY_SWORD_SCENE := preload("res://scenes/boss/sky_sword.tscn")


func _setup() -> void:
	boss_id = "boss_01_c"
	intent = 0
	_hits_taken = 0
	_ranged_streak = 0
	_myriad_cd = 0.0
	_heaven_cd = 0.0
	_heaven_is_full = false
	_heaven_full_casts = 0
	_phase2 = false
	_recent_skills.clear()
	spell_cooldowns.clear()
	_build_intent_ui()


# ===================== 主循环 =====================

func _physics_process(delta: float) -> void:
	if state == BossState.WINDUP and not _windup_locked:
		if state_timer <= _windup_total * 0.35:
			_windup_locked = true
		else:
			_update_facing_to_target()
	_tick_sky_phase(delta)
	_tick_triangle(delta)
	super._physics_process(delta)


func _tick_cooldowns(delta: float) -> void:
	for sid in spell_cooldowns.keys():
		var left := float(spell_cooldowns[sid]) - delta
		if left <= 0.0:
			spell_cooldowns.erase(sid)
		else:
			spell_cooldowns[sid] = left
	_myriad_cd = maxf(0.0, _myriad_cd - delta)
	_heaven_cd = maxf(0.0, _heaven_cd - delta)


func _is_extra_state(s: int) -> bool:
	return s == ExtraState.PIERCE


func _tick_extra_state(delta: float) -> void:
	if state == ExtraState.PIERCE:
		_pierce_step(delta)


# ===================== 剑意 =====================

## 剑意获取倍率：二阶段翻倍（用户指定「技能积攒剑意层数翻倍」）
func _intent_mult() -> int:
	return 2 if _phase2 else 1


func _gain_intent(n: int) -> void:
	if n <= 0 or intent >= INTENT_MAX:
		return
	var before := intent
	intent = mini(INTENT_MAX, intent + n)
	if intent > before:
		_refresh_intent_ui()
		# 每层剑意一点视觉反馈（无贴图时是程序化光环）
		FxPlayer.spawn(self, "fx_sword_intent", {
			"position": body_center() + Vector2(0.0, -34.0),
			"lifetime": 0.4,
		})


func _lose_intent(n: int) -> void:
	if n <= 0 or intent <= 0:
		return
	intent = maxi(0, intent - n)
	_refresh_intent_ui()


## 头顶 5 格剑意条（HP 条上方）
## ⚠ 用 ColorRect 占位（与 HP 条同一套做法）；想要剑形图标就往 assets/ui/icon/
##   丢图后改这里为 UIKit.icon_node —— 位置与点亮逻辑不变
func _build_intent_ui() -> void:
	for i in range(INTENT_MAX):
		var ic := ColorRect.new()
		ic.size = Vector2(5.0, 14.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ic)
		_intent_icons.append(ic)
	_refresh_intent_ui()


func _refresh_intent_ui() -> void:
	for i in range(_intent_icons.size()):
		var ic := _intent_icons[i] as ColorRect
		if ic == null:
			continue
		# HP 条在 y=-62~-54，剑意条放它上面 16px
		ic.position = Vector2(-26.0 + float(i) * 11.0, -78.0)
		ic.color = Color(0.55, 0.92, 1.0, 1.0) if i < intent else Color(0.16, 0.20, 0.24, 0.85)


# ===================== 受击（剑意衰减）=====================

## from_projectile 与基类同签名（玩家远程投射物命中时传 true）；
## 剑客没有弹刀机制，这里只是原样转交给 BossBase
func take_damage(amount: float, source: Node = null, damage_kind: String = "physical",
		element: String = "", from_projectile: bool = false) -> void:
	var hp_before := current_hp
	super.take_damage(amount, source, damage_kind, element, from_projectile)
	# 只有真掉血（非无敌期/非转阶段保护）才算「被打一次」
	if current_hp >= hp_before:
		return
	_hits_taken += 1
	if _hits_taken >= INTENT_DECAY_HITS:
		_hits_taken = 0
		_lose_intent(1)


# ===================== 选招 =====================

func _on_chase_reached(_dist: float) -> void:
	_choose_next_action()


func _choose_next_action() -> void:
	# 出招承诺：蓄力/出手/收招中不换招
	if state == BossState.WINDUP or state == BossState.ATTACK or state == BossState.RECOVER:
		return
	if _is_extra_state(state):
		return

	# 1. 穿：连续两次远程后强制触发（机制技优先于一切评分）
	if _ranged_streak >= PIERCE_RANGED_STREAK:
		_begin_skill(SKILL_PIERCE)
		return

	# 2. 满层一剑开天：剑意满时高概率抢放（二阶段专属大招）
	#    棋盘里满层形态一局一次，用掉之后这条抢放就退出 —— 否则每次满层都白抢一下
	if _phase2 and _heaven_will_be_full() and _heaven_cd <= 0.0 and randf() < 0.55:
		_begin_skill(SKILL_HEAVEN)
		return

	# 3. 常规评分
	var best := _pick_best_skill()
	if best == "":
		state = BossState.CHASE
		return
	_begin_skill(best)


func _pick_best_skill() -> String:
	var scored: Array = []
	for sid in ALL_SKILLS:
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
	var dist := _distance_to_player()
	var b := MoveDB.resolve_boss(skill_id)
	if b.is_empty():
		return false
	if skill_id in RANGED_SKILLS and spell_cd_left(skill_id) > 0.0:
		return false
	match skill_id:
		SKILL_STAB:
			return dist >= 50.0 and dist <= 250.0
		SKILL_LIFT:
			return dist <= 185.0
		SKILL_CHOP:
			return dist <= 135.0
		SKILL_CLOUD:
			return dist >= 190.0 and dist <= 540.0
		SKILL_MYRIAD:
			# 一阶段专属（二阶段禁用）+ 冷却就绪
			return not _phase2 and _myriad_cd <= 0.0
		SKILL_HEAVEN:
			return _phase2 and _heaven_cd <= 0.0
	return false


## 评分：距离为主，行为/资源为辅，减去重复惩罚
func _score_skill(skill_id: String) -> float:
	var dist := _distance_to_player()
	var front := _player_front_factor()
	var d_score := 0.0
	var b_score := 0.0
	var e_score := 0.0

	match skill_id:
		SKILL_STAB:
			d_score = 3.0 - absf(dist - 150.0) / 100.0
			if front > 0.6:
				b_score += 1.0
		SKILL_LIFT:
			d_score = 2.6 - absf(dist - 90.0) / 80.0
			if front > 0.6:
				b_score += 1.2
		SKILL_CHOP:
			d_score = 2.8 - absf(dist - 70.0) / 70.0
			if front > 0.75:
				b_score += 1.6
			# 前摇大，略降权重
			d_score -= 0.4
		SKILL_CLOUD:
			d_score = 2.4 - absf(dist - 350.0) / 200.0
			if dist > 280.0:
				b_score += 1.5
			# 远程连续两次会触发穿，第三下云之前给点折扣避免无限风筝
			if _ranged_streak >= 1:
				d_score -= 1.2
		SKILL_MYRIAD:
			d_score = 1.6
			# 剑意越高越想放大招（0 层也想放，基础 2 把剑）
			e_score += float(intent) * 0.7
		SKILL_HEAVEN:
			d_score = 1.8
			e_score += float(intent) * 0.8
			# 只有真的能放满层形态才给这一票（棋盘里唯一一次用掉后就不必再为它腾节奏）
			if _heaven_will_be_full():
				e_score += 2.0

	return d_score + b_score + e_score - _repeat_penalty(skill_id)


func _repeat_penalty(skill_id: String) -> float:
	if _recent_skills.is_empty():
		return 0.0
	if String(_recent_skills[0]) != skill_id:
		return 0.0
	if _recent_skills.size() >= 2 and String(_recent_skills[1]) == skill_id:
		return REPEAT_PENALTY_2
	return REPEAT_PENALTY_1


func _player_front_factor() -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	var to_player: Vector2 = target.global_position - global_position
	if to_player.length_squared() < 0.0001:
		return 1.0
	return facing.normalized().dot(to_player.normalized())


## 与玩家的距离（无目标时给一个大值，保证「远程招式不可用」）
func _distance_to_player() -> float:
	if target == null or not is_instance_valid(target):
		return 99999.0
	return global_position.distance_to(target.global_position)


# ===================== 出招 =====================

func _begin_skill(skill_id: String) -> void:
	_current_form = skill_id
	_windup_locked = false
	_windup_total = _windup_time_for(skill_id)
	state = BossState.WINDUP
	state_timer = _windup_total
	# 招式型起手也要广播（新手指引靠它等抬手；漏了教学对真 BOSS 不触发）
	attack_windup.emit(_attack_kind_of(skill_id), _windup_total)
	if target != null and is_instance_valid(target):
		_set_facing((target.global_position - global_position).normalized())
	# 技能名在**前摇的这一瞬间**飘出，并一直挂到技能释放（hold = 前摇时长）
	# 满剑意一剑开天用满层招名：字号更大、更宽，同样挂到伤害打出才开始淡出
	# （满层判定与 `_start_heaven_strike` 同源：前摇期间剑意不变，此刻就能确定是不是满层。
	#   棋盘里唯一一次已经用掉时，这里也必须跟着换成常规招名，别报盈天、落普通一剑）
	if skill_id == SKILL_HEAVEN and _heaven_will_be_full():
		show_skill_line(_form_name_of(SKILL_HEAVEN_FULL), _windup_total, 22, 280.0,
			BossBase.skill_name_color(_attack_kind_of(skill_id)))
	else:
		# 颜色按招式类型：物理黄 / 法术蓝（用户 2026-10-20 定）
		show_skill_name_at_windup(_form_name_of(skill_id), _windup_total,
			BossBase.skill_name_color(_attack_kind_of(skill_id)))
	# ⚠ 起手动作必须**在这里**接：前摇一结束就是伤害判定，动画压进「前摇 + 0.15」
	#   正好让剑指递到最尽头那一帧落在判定上 —— 玩家看指到哪就知道打到哪
	#   （剑客没有红圈、没有 UI 预警，动作本身就是唯一的预警）。
	#   刀客那边一直有这一行，剑客从换骨骼起**漏接了**：
	#   表现就是「出招时人不动、只有飘字和飞剑特效」。查这类问题别直接调下游函数，
	#   要从 `_begin_skill` 这个真实入口看。
	_play_form_anim(skill_id, _windup_total + 0.15)
	# 一剑开天：光柱在**前摇第一帧**就升起（蓄力时长 = 本次前摇），掉落砸地才结算伤害
	if skill_id == SKILL_HEAVEN:
		_start_heaven_strike()
	_on_attack_windup(0)


## 招式的显示名（招式表 form_name —— 前摇飘字与调试都用它）
func _form_name_of(skill_id: String) -> String:
	return String(MoveDB.resolve_boss(skill_id).get("form_name", ""))


func _windup_time_for(skill_id: String) -> float:
	var b := MoveDB.resolve_boss(skill_id)
	var base := float(b.get("windup", 0.8))
	if _phase2:
		base *= float(b.get("windup_mult_p2", 1.0))
	return maxf(0.15, base)


func _on_attack_windup(_kind: int) -> void:
	# 无 UI 预警：只用身体蓄力色与缩放表达（按招式区分）
	var color := Color(0.30, 0.62, 0.70)
	match _current_form:
		SKILL_LIFT:
			color = Color(0.36, 0.70, 0.76)
		SKILL_CHOP:
			color = Color(0.24, 0.55, 0.66)
		SKILL_CLOUD, SKILL_MYRIAD:
			color = Color(0.45, 0.78, 0.86)
		SKILL_HEAVEN, SKILL_HEAVEN_FULL:
			color = Color(0.55, 0.88, 1.0)
		SKILL_PIERCE:
			color = Color(0.40, 0.75, 0.82)
	_show_windup(color)


func _fire_attack() -> void:
	state = BossState.ATTACK
	state_timer = 0.15
	_reset_visual()
	GameState.play_sfx("boss_attack")
	_execute_skill(_current_form)


func _do_attack(_kind: int) -> void:
	# 由 _fire_attack 直接调 _execute_skill，这里不重复实现
	pass


func _execute_skill(skill_id: String) -> void:
	var b := MoveDB.resolve_boss(skill_id)
	if b.is_empty():
		_finish_skill()
		return

	_record_used(skill_id)

	match skill_id:
		SKILL_STAB, SKILL_LIFT, SKILL_CHOP:
			# 释放即 +1（二阶段翻倍）
			_gain_intent(INTENT_PER_CAST * _intent_mult())
			_play_skill_visual(skill_id, b)
			var hit := _hit_player_in_form(b)
			if hit:
				# 成功命中再 +1
				_gain_intent(INTENT_PER_HIT * _intent_mult())
			_finish_skill()
		SKILL_CLOUD:
			_gain_intent(INTENT_PER_CAST * _intent_mult())
			_play_skill_visual(skill_id, b)
			_ranged_streak += 1
			_start_spell_cooldown(skill_id)
			_fire_sword(b)
			_finish_skill()
		SKILL_PIERCE:
			_ranged_streak = 0
			_start_pierce(b)
			# 由 PIERCE 状态收尾，这里不 finish
		SKILL_MYRIAD:
			_fire_myriad(b)
			_finish_skill()
		SKILL_HEAVEN:
			_fire_heaven(b)
			_finish_skill()
		_:
			_finish_skill()


## 招式视觉（走 ArtDB.EFFECTS，换美术只改表）
func _play_skill_visual(skill_id: String, b: Dictionary) -> void:
	# ⚠ 技能名不在这里显示：改为前摇瞬间由 _begin_skill 统一飘出（释放时才淡出）
	var visual_id := String(b.get("visual_id", ""))
	# 一剑开天：四段表现（蓄力 → 劈落 → 撞击 → 地面劈痕）—— 与玩家侧同一套驱动、同一份形态数据
	if bool(b.get("fx_heaven", false)):
		SwordHeavenFx.play(self, b, facing)
		return
	# 竖直光柱类（通用能力）：不跟随朝向旋转（保持屏幕竖直），落点在身前 fx_forward 处；
	# 时长交给 ArtDB 条目
	if bool(b.get("fx_vertical", false)):
		if visual_id != "":
			FxPlayer.spawn(self, visual_id, {
				"position": body_center() + facing * float(b.get("fx_forward", 0.0)),
			})
		return
	# 与玩家共用同一套 SkillFx：BOSS 已在出手帧，直接播命中层
	if SkillFx.play_form_at_strike(self, String(b.get("form_id", skill_id)), b, facing):
		return
	if visual_id == "":
		return
	var params := {}
	params["position"] = body_center()
	params["rotation"] = facing.angle()
	params["lifetime"] = maxf(0.14, float(b.get("active", 0.12)) + 0.12)
	var shape := String(b.get("hit_shape", ""))
	if shape == MoveDB.SHAPE_FAN or shape == MoveDB.SHAPE_CIRCLE:
		params["radius"] = float(b.get("range", 120.0)) * 0.8
		params["sweep_deg"] = float(b.get("angle", 90.0))
	elif shape == MoveDB.SHAPE_PROJECTILE:
		params["radius"] = 16.0
	elif shape == MoveDB.SHAPE_RECT:
		params["rect_size"] = Vector2(float(b.get("range", 1000.0)), float(b.get("width", 160.0)))
	FxPlayer.spawn(self, visual_id, params)


# ===================== 命中判定 =====================

## 扇形/圆形/直线判定：命中返回 true
##   dmg_override  >= 0 时用给定伤害（一剑开天要按实际消耗的剑意算范围）
##   elem          五行属性（法术招式用）
## 扇形/圆形/矩形判定：命中**所有**该打的单位（敌方剑客打玩家+友军；被召唤的友军剑客只打敌方 BOSS）
## 每个单位各自算几何，召唤物只在自己被覆盖到时才掉血
func _hit_player_in_form(b: Dictionary, dmg_override: float = -1.0, elem: String = "") -> bool:
	var reach := float(b.get("range", 120.0))
	var dmg := dmg_override
	if dmg < 0.0:
		dmg = MoveDB.boss_damage(String(b.get("form_id", "")), attack_power, phase)
	var kind := String(b.get("attack_kind", "physical_melee"))
	var shape := String(b.get("hit_shape", MoveDB.SHAPE_FAN))
	var axis: Vector2 = facing.normalized()
	var half := deg_to_rad(float(b.get("angle", 90.0)) * 0.5)
	var hit := false
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - global_position
		var dist := to_u.length()
		# 矩形长条（一剑开天·满层）：正交投影判定，必须在 dist 检查之前——
		# 矩形角区 fwd≤length 但斜距 > length，先查 dist 会误杀
		if shape == MoveDB.SHAPE_RECT:
			var side_vec: Vector2 = Vector2(-axis.y, axis.x)
			var half_w := float(b.get("width", 160.0)) * 0.5
			var fwd := to_u.dot(axis)
			var lat := absf(to_u.dot(side_vec))
			if fwd < -24.0 or fwd > reach + 24.0 or lat > half_w + 24.0:
				continue
		else:
			if dist > reach:
				continue
			if shape != MoveDB.SHAPE_CIRCLE and dist > 1.0:
				if axis.dot(to_u / dist) < cos(half):
					continue
		if _apply_damage_to_unit(u, dmg, kind, elem):
			hit = true
	return hit


## 对单个单位结算并判断「是否真掉血」（玩家可能处于无敌帧 / 弹反）
func _apply_damage_to_unit(unit: Node, amount: float, attack_kind: String, elem: String = "") -> bool:
	var before := unit_hp(unit)
	if not deal_damage_to(unit, amount, attack_kind, elem):
		return false
	var after := unit_hp(unit)
	if before < 0.0 or after < 0.0:
		return true
	return after < before


## 兼容入口：只对当前 target 结算（反击 / 天剑阵等「锁定单人」的伤害仍走这里）
func _deal_damage_to_player(amount: float, attack_kind: String, elem: String = "") -> bool:
	return _apply_damage_to_unit(target, amount, attack_kind, elem)


# ===================== 云：飞剑投射物 =====================

## 生成一把飞剑（云 / 万剑归宗共用）
##   dir 飞行方向；on_hit 命中玩家回调（云用来加剑意）
func _spawn_sword(dir: Vector2, dmg: float, speed: float, on_hit: Callable = Callable()) -> Node2D:
	var proj := _spawn_projectile("physical_projectile")
	if proj == null:
		return null
	proj.direction = dir.normalized()
	proj.speed = speed
	proj.damage = dmg
	proj.source = self
	# on_hit_player 是运行期加的脚本变量，用 set() 写入（避免静态类型访问告警）
	if on_hit.is_valid():
		proj.set("on_hit_player", on_hit)
	# 外观：竖直长剑（清风剑）；初始朝向对齐飞行方向
	# ⚠ 只转 Skin 这一层 —— 外层 Visual 与 Skin 同时转会叠加成两倍角；
	#    追踪剑开启 align_visual 后由 boss_projectile 每帧跟进同一个字段
	# ⚠ 补偿量是 **-PI/2**：剑图「竖直、刃尖朝下」（+Y = 90°），减 90° 才让刃尖指向 dst。
	#    这里是一次性朝向（斩云的直飞剑不开 align_visual），写错会一路反着飞
	var skin := proj.get_node_or_null("Visual/Skin") as SkinVisual
	if skin != null:
		skin.visual_id = "boss_sword_projectile"
		skin.refresh()
		skin.rotation = dir.angle() - PI * 0.5
	return proj


func _fire_sword(b: Dictionary) -> void:
	var dmg := MoveDB.boss_damage(SKILL_CLOUD, attack_power, phase)
	var dir := _aim_dir()
	var proj := _spawn_sword(dir, dmg, float(b.get("speed", 460.0)),
		func() -> void: _gain_intent(INTENT_PER_HIT * _intent_mult()))
	if proj != null:
		proj.global_position = global_position + dir * 34.0 + Vector2(0.0, -30.0)
		_apply_skill_projectile_visual(proj, "form_sword_cloud")


func _aim_dir() -> Vector2:
	if target != null and is_instance_valid(target):
		return (target.global_position - global_position).normalized()
	return facing


# ===================== 穿：突刺到玩家身后 =====================

func _start_pierce(b: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		_finish_skill()
		return
	# 技能名在前摇时就已飘出（_begin_skill），这里不再重复显示
	# ⚠ 方向在**前摇结束的这一刻**定死：之后无论玩家怎么跑都不再改向、也不追踪
	_pierce_dir = (target.global_position - global_position).normalized()
	_pierce_speed = float(b.get("dash_speed", PIERCE_SPEED_FALLBACK))
	_set_facing(_pierce_dir)
	_pierce_remaining = float(b.get("dash_time", PIERCE_TIME_FALLBACK))
	_pierce_hit_done = false
	state = ExtraState.PIERCE
	var pierce_form := MoveDB.resolve_boss(SKILL_PIERCE)
	SkillFx.play_form_at_strike(self, SKILL_PIERCE, pierce_form, _pierce_dir)


func _pierce_step(delta: float) -> void:
	# 沿锁定方向直冲；方向在 _start_pierce 定死后**全程不变**
	velocity = _pierce_dir * _pierce_speed
	# 穿过玩家的瞬间结算一次伤害（落点到身后后再判定会打不中）
	if not _pierce_hit_done and target != null and is_instance_valid(target):
		var to_p: Vector2 = target.global_position - global_position
		var dist := to_p.length()
		if dist <= 46.0 or to_p.dot(_pierce_dir) <= 0.0:
			_pierce_hit_done = true
			var dmg := MoveDB.boss_damage(SKILL_PIERCE, attack_power, phase)
			_deal_damage_to_player(dmg, "physical_melee")

	_pierce_remaining -= delta
	if _pierce_remaining > 0.0:
		return
	# 冲到就停下，**不再瞬移到玩家身后**（旧做法在玩家已经跑开时看着像瞬移）
	velocity = Vector2.ZERO
	_finish_skill()


# ===================== 万剑归宗 =====================

## 连续发射的间隔（秒）—— 剑意多出来的剑要「快速连着放」，不是同帧齐射
const MYRIAD_INTERVAL := 0.09
## 每把剑离开发射点时的侧偏角（度）：左右交替斜飞，再弧线转向玩家
const MYRIAD_SIDE_ANGLE := 65.0
## 弧线转向速度（度/秒）：越大越早拐向玩家，越小弧线越舒展
const MYRIAD_TURN_SPEED := 200.0


func _fire_myriad(b: Dictionary) -> void:
	var count := MYRIAD_BASE_COUNT + intent * MYRIAD_PER_INTENT
	intent = 0
	_refresh_intent_ui()
	_myriad_cd = MYRIAD_COOLDOWN
	# 技能名已在前摇时飘出，这里不再重复显示

	var dmg := MoveDB.boss_damage(SKILL_MYRIAD, attack_power, phase)
	var speed := float(b.get("speed", 420.0))
	# 交替左右逐把放出：第 1 把左侧、第 2 把右侧、第 3 把左侧…
	for i in range(count):
		var side := -1.0 if (i % 2 == 0) else 1.0
		_schedule_sword(float(i) * MYRIAD_INTERVAL, side, dmg, speed)
	var myriad_form := MoveDB.resolve_boss(SKILL_MYRIAD)
	SkillFx.play_form_at_strike(self, SKILL_MYRIAD, myriad_form, facing)


## 延迟放一把剑（delay <= 0 立即放）
func _schedule_sword(delay: float, side: float, dmg: float, speed: float) -> void:
	if delay <= 0.0:
		_launch_one_sword(side, dmg, speed)
		return
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		# BOSS 可能已死/已离场：这时不再放
		if is_inside_tree() and state != BossState.DEAD:
			_launch_one_sword(side, dmg, speed)
	)


## 放一把飞剑：从身侧斜着出发，之后弧线转向玩家
func _launch_one_sword(side: float, dmg: float, speed: float) -> void:
	# 初始方向 = 朝向前方左右各偏 35°（身侧斜飞），不是正面散射
	var dir := facing.rotated(side * deg_to_rad(MYRIAD_SIDE_ANGLE))
	var proj := _spawn_sword(dir, dmg, speed)
	if proj == null:
		return
	proj.global_position = global_position + dir * 26.0 + Vector2(0.0, -30.0)
	_apply_skill_projectile_visual(proj, "form_sword_myriad")
	# 弧线追踪：放出后逐渐拐向玩家（用 set() 写入运行期字段，避免静态类型告警）
	proj.set("launch_side", side)
	proj.set("turn_speed_deg", MYRIAD_TURN_SPEED)
	proj.set("homing_target", target)
	proj.set("align_visual", true)
	# 出手一点点特效反馈
	FxPlayer.spawn(self, "fx_sword_cloud", {
		"position": proj.global_position,
		"rotation": dir.angle(),
		"lifetime": 0.16,
	})


# ===================== 一剑开天 =====================

## 满层形态（一剑开天·剑意盈天）还能不能放：**只有对局棋子**受"一局一次"的限制
## （2026-11-03 用户：剑客实战表现太强，建议改成满层的一剑开天只能用一次）。
## 秘境 / 万界塔 / 演武场的 `team_id` 是 -1，这条一律放行，行为一字不变。
func _heaven_full_allowed() -> bool:
	return team_id < 0 or _heaven_full_casts < HEAVEN_FULL_CASTS_MATCH


## 下一次一剑开天会不会是满层形态。招名、评分、强制抢放、起手定形态**五处**都必须
## 读同一个判定 —— 少读一处就会出现"报了盈天的名字、落的是常规那一剑"的错位。
func _heaven_will_be_full() -> bool:
	return intent >= HEAVEN_FULL_INTENT and _heaven_full_allowed()


func _fire_heaven(_b: Dictionary) -> void:
	# 伤害与特效都不在这里：光柱在前摇期就升起，落地回调 `_on_heaven_land` 结算。
	# 这里只做收尾记账（清剑意、进冷却）。
	intent = 0
	_refresh_intent_ui()
	_heaven_cd = HEAVEN_COOLDOWN
	# 满层那一发要记账给"一局一次"的闸门用。记在这里而不是起手：
	# 起手后被打断（弹刀 / 僵直）的这剑由 `_abort_heaven` 作废，不该白烧掉唯一一次。
	if _heaven_is_full:
		_heaven_full_casts += 1


## 一剑开天起手：定下这一剑（形态 / 伤害 / 五行），并把光柱挂上去。
## 蓄力时长传 `_windup_total` —— 光柱落地正好是本招伤害判定的那一帧。
func _start_heaven_strike() -> void:
	var full := _heaven_will_be_full()
	_heaven_is_full = full
	var form_id := SKILL_HEAVEN_FULL if full else SKILL_HEAVEN
	var fb := MoveDB.resolve_boss(form_id)
	if not full:
		# 范围随消耗的剑意层数放大（满层走法术巨斩形态，范围已内置）
		fb["range"] = float(fb.get("range", 220.0)) + float(intent) * HEAVEN_RANGE_PER_INTENT
	_heaven_form = fb
	_heaven_dmg = MoveDB.boss_damage(form_id, attack_power, phase)
	_heaven_elem = String(fb.get("damage_element", ""))
	_heaven_fx = SwordHeavenFx.play(self, fb, facing, "", _on_heaven_land, _windup_total)


## 光柱砸地：伤害就在这一刻，与劈痕同一帧
func _on_heaven_land() -> void:
	_heaven_fx = null
	if _heaven_form.is_empty():
		return
	# 蓄力期间被弹刀 / 打死：这一剑作废
	if state == BossState.DEAD or state == BossState.STAGGER:
		_heaven_form = {}
		return
	var hit := _hit_player_in_form(_heaven_form, _heaven_dmg, _heaven_elem)
	_heaven_form = {}
	if hit:
		GameState.trigger_hit_stop()


## 打断这一剑（弹刀 / 离场）：连光柱一起撤掉，否则它会在僵直里照常砸下来
func _abort_heaven() -> void:
	# 作废的这一剑不算"用过"：唯一一次不能白烧在弹刀上
	_heaven_is_full = false
	if _heaven_fx != null and is_instance_valid(_heaven_fx):
		_heaven_fx.queue_free()
	_heaven_fx = null
	_heaven_form = {}


# ===================== 穿招收尾 =====================

func _finish_skill() -> void:
	state = BossState.RECOVER
	state_timer = _recover_time() * _recover_mult_for(_current_form)
	_windup_locked = false


func _recover_mult_for(skill_id: String) -> float:
	match skill_id:
		SKILL_CHOP:
			return 1.2
		SKILL_HEAVEN, SKILL_HEAVEN_FULL:
			return 1.35
		SKILL_MYRIAD:
			return 1.15
		SKILL_PIERCE:
			return 1.3
		_:
			return 1.0


func _record_used(skill_id: String) -> void:
	_recent_skills.push_front(skill_id)
	if _recent_skills.size() > 4:
		_recent_skills.resize(4)


# ===================== 法术冷却（云）====================

func spell_cd_left(skill_id: String) -> float:
	return float(spell_cooldowns.get(skill_id, 0.0))


func _start_spell_cooldown(skill_id: String) -> void:
	var b := MoveDB.resolve_boss(skill_id)
	var cd := float(b.get("cooldown_p2", 0.0)) if _phase2 else float(b.get("cooldown_p1", 0.0))
	if cd > 0.0:
		spell_cooldowns[skill_id] = cd


# ===================== 阶段 =====================

func _on_phase_two() -> void:
	_phase2 = true
	# 万剑归宗一阶段专属：二阶段禁用（_skill_available 已挡，这里清冷却双保险）
	_myriad_cd = 99999.0
	# 转阶段保护期玩家被推开；等推力结束再在玩家当前位置插剑
	await get_tree().create_timer(PHASE_TRANSITION_TIME).timeout
	if not is_inside_tree() or state == BossState.DEAD:
		return
	_start_triangle()


# ===================== 三角封绝 =====================

func _start_triangle() -> void:
	if target == null or not is_instance_valid(target):
		return
	_triangle_swords.clear()
	var center := target.global_position
	for i in range(3):
		var ang := -PI * 0.5 + TAU * float(i) / 3.0
		var pos := center + Vector2(cos(ang), sin(ang)) * TRIANGLE_RADIUS
		var sw := SKY_SWORD_SCENE.instantiate()
		sw.mode = SkySword.Mode.TRIANGLE
		sw.global_position = pos
		sw.source = self
		get_parent().add_child(sw)
		_triangle_swords.append(sw)
	_triangle_timer = TRIANGLE_DELAY
	_triangle_armed = true
	_show_skill_text("三角封绝")


func _tick_triangle(delta: float) -> void:
	if not _triangle_armed:
		return
	_triangle_timer -= delta
	if _triangle_timer > 0.0:
		return
	_triangle_armed = false
	_detonate_triangle()


func _detonate_triangle() -> void:
	# 以三把剑的几何中心为爆发点
	var center := Vector2.ZERO
	var n := 0
	for sw in _triangle_swords:
		if is_instance_valid(sw):
			center += sw.global_position
			n += 1
	if n > 0:
		center /= float(n)
		var dmg := MoveDB.boss_damage(SKILL_TRIANGLE, attack_power, phase)
		_show_skill_text("封绝斩")
		FxPlayer.spawn(self, "fx_sword_triangle", {
			"position": center,
			"lifetime": 0.35,
			"radius": float(MoveDB.get_form(SKILL_TRIANGLE).get("range", 150.0)) * 0.8,
		})
		if target != null and is_instance_valid(target):
			var reach := float(MoveDB.get_form(SKILL_TRIANGLE).get("range", 150.0))
			if target.global_position.distance_to(center) <= reach + 30.0:
				_deal_damage_to_player(dmg, "elemental", "metal")
	for sw in _triangle_swords:
		if is_instance_valid(sw):
			sw.dismiss()
	_triangle_swords.clear()
	# 三角斩结束后启动天剑阵
	_start_sky_sword_phase()


# ===================== 天剑阵 =====================

func _start_sky_sword_phase() -> void:
	if _sky_state != 0:
		return
	_sky_state = 1
	_sky_spawned = 0
	_sky_timer = 0.0
	_show_skill_text("万剑临空")
	# 机制说明提示（2026-10-19 用户要求）：告诉玩家这一波该怎么破
	# ⚠ 长文案必须显式给 width + 居中对齐，且停留久一点（hold），否则读不完就没了
	_show_status_text("小心三角剑阵，攻击其余散落剑阵，防止其给剑客回血",
		16, 400.0, 2.4, -120.0)


func _tick_sky_phase(delta: float) -> void:
	if _sky_state == 0 or state == BossState.DEAD:
		return
	if _sky_state == 1:
		_sky_timer -= delta
		if _sky_timer > 0.0:
			return
		_spawn_one_sky_sword()
		_sky_spawned += 1
		_sky_timer = SKY_SWORD_INTERVAL
		if _sky_spawned >= SKY_SWORD_COUNT:
			# 全部落完，开始 5 秒击破倒计时
			_sky_state = 2
			_sky_check = SKY_SWORD_CHECK_DELAY
		return
	if _sky_state == 2:
		_sky_check -= delta
		if _sky_check <= 0.0:
			_settle_sky_swords()


func _spawn_one_sky_sword() -> void:
	if target == null or not is_instance_valid(target):
		return
	# 落点在玩家当前位置附近随机偏移：有压迫感但躲得开
	var pos := target.global_position + Vector2(randf_range(-70.0, 70.0), randf_range(-40.0, 40.0))
	var sw := SKY_SWORD_SCENE.instantiate()
	sw.mode = SkySword.Mode.FALLING
	sw.global_position = pos
	sw.damage = attack_power * SKY_SWORD_DAMAGE_COEFF
	sw.attack_kind = "physical_melee"
	sw.source = self
	# 友军召唤物：天剑不走 deal_damage_to()，倍率必须显式带过去
	sw.ally_scale = ally_damage_scale if is_ally else 1.0
	get_parent().add_child(sw)


## ⚠ `breakable_sword` 是**异构组**：天剑（SkySword）、阵旗（ArrayFlag）、碣板（StagPlate）
##   都在里面，只有 SkySword 有 `source` 与 `dismiss()`。
##   单打剑客时组里只有天剑，所以直接读字段一直没露馅；**棋局里 12 只 BOSS 同场**，
##   定阵先生一插旗就 `Invalid access to property or key 'source'`（每帧刷，实机 116 条）。
##   口径与 `player.gd:2017` 那两处一致：先按类型筛，再谈归属。
func _remaining_sky_swords() -> int:
	var n := 0
	for sw in get_tree().get_nodes_in_group("breakable_sword"):
		if not is_instance_valid(sw) or not sw is SkySword:
			continue
		if sw.source != self:
			continue
		n += 1
	return n


func _settle_sky_swords() -> void:
	_sky_state = 3
	var remain := _remaining_sky_swords()
	if remain <= 0:
		_show_status_text("剑阵尽破")
		return
	# 每剩余一把回复 5% 血量
	# 走统一入口：被暗「蚀」时这口回复同样只剩 10%
	apply_heal(max_hp * SKY_SWORD_HEAL_PER * float(remain))
	_show_status_text("剑阵归位 +%d%%" % int(SKY_SWORD_HEAL_PER * 100.0 * float(remain)))
	# 回血后剩余剑一并消散，不永久挡路
	# ⚠ 同样必须先筛类型：少了 `is SkySword` 这一道，这里会去给阵旗/碣板调
	#   根本不存在的 dismiss()（而且真有的话就等于剑客替定阵先生拆旗）。
	for sw in get_tree().get_nodes_in_group("breakable_sword"):
		if is_instance_valid(sw) and sw is SkySword and sw.source == self:
			sw.dismiss()


# ===================== 弹刀僵直 =====================

func on_parried(source: Node) -> void:
	if state == BossState.DEAD:
		return
	# 正在蓄的一剑开天被弹开：连光柱一起撤掉（否则僵直里还会砸下来）
	_abort_heaven()
	var b := MoveDB.resolve_boss(_current_form)
	var coeff := float(b.get("stagger_coeff", 0.12))
	state = BossState.STAGGER
	state_timer = 0.45 + coeff * 4.5
	velocity = Vector2.ZERO
	_windup_locked = false
	_flash_attack(Color(1.0, 1.0, 0.3))
	# ⚠ 先 is_instance_valid 再 `is`：对已释放实例用 `is` 会报 freed 错误（顺序不能反）
	if source != null and is_instance_valid(source) and source is Node2D:
		var back := (global_position - (source as Node2D).global_position).normalized()
		_bump_back(back * 120.0)


# ===================== 调试信息 =====================

## 当前剑意层数（验证脚本 / 调试面板读取用）
func get_intent() -> int:
	return intent


## BOSS 累计受击次数（剑意衰减的进度）
func get_hits_taken() -> int:
	return _hits_taken


## 连续远程释放次数（穿的触发进度）
func get_ranged_streak() -> int:
	return _ranged_streak


## 天剑阵状态：0 未启动 / 1 释放中 / 2 等待击破 / 3 已结算
func get_sky_state() -> int:
	return _sky_state


## 万剑归宗剩余冷却
func get_myriad_cd() -> float:
	return _myriad_cd


## 是否已解锁一剑开天（二阶段）
func is_heaven_unlocked() -> bool:
	return _phase2
