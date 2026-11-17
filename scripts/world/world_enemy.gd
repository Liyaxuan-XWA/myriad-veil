class_name WorldEnemy
extends BossBase
## 大世界敌人：灵兽 / 野外修士 / 核心首领
##
## 复用 BossBase 的状态机、受击、仇恨与弹刀规则，但换成「大世界」规则：
##   - 有仇恨半径与脱战半径：玩家跑远后脱战回原位并回满血
##   - 灵兽 / 修士只有一阶段；核心首领保留二阶段
##   - 死亡不发 GameState.boss_died（结算由大世界管理器接 world_died 处理）
##
## 全部数值来自 SecretWorldDB（configure() 注入），本文件不写死任何个体数值。

signal world_died(enemy: WorldEnemy)

const KIND_BEAST := "beast"
const KIND_CULTIVATOR := "cultivator"
const KIND_CORE := "core"

## 修士施法专用攻击类型（避开 BossBase.AttackKind 的三种基础招式）
const KIND_SKILL := 100
## 大陆核心首领的招式（form_id 来自 SecretWorldDB.CORE_SKILLS，不走 SkillDB）
const KIND_CORE_SKILL := 101
## 脱战回家状态（与其它 BOSS 的 100+ 自定义状态错开）
const STATE_RETURN_HOME := 200
## 修士空闲时的「踱步」状态：没目标时在出生点附近慢慢走两步，不再杵着
const STATE_IDLE_ACT := 201

## 待机动作间隔（秒）与踱步半径（像素）
const IDLE_ACT_GAP_MIN := 2.4
const IDLE_ACT_GAP_MAX := 5.0
const IDLE_PACE_RADIUS := 84.0
## 追逐时为了避免「一条直线怼脸」加的一点侧向弧度（最大占比）
const CHASE_ARC := 0.18

var enemy_kind: String = KIND_BEAST
var display_name: String = ""
## 在战斗箱庭里使用时置 true：死亡额外发 BossBase.died 供场景结算；
## 大世界模式保持 false，只发 world_died，避免触发关卡结算。
var standalone: bool = false
var spawn_home: Vector2 = Vector2.ZERO
var node_id: String = ""
## 击杀掉落（管理器读取后生成地面掉落物）
var drop_materials: Array = []
## 修士随机装备的功法 id
var skill_ids: Array = []
## 修士出生时携带的法宝实例（空 = 没带宝）；死亡时必定掉落这一件
var carried_treasure: Dictionary = {}

var _treasure_mana: float = 100.0
var _treasure_mana_max: float = 100.0
var _treasure_cooldown_left: float = 0.0
var _treasure_channel_left: float = 0.0
var _treasure_tick: float = 0.0
var _treasure_trigger_ratio: float = 0.55
## 逐电环：3 秒内移速固定为 800
var _treasure_haste_left: float = 0.0
var _treasure_haste_speed: float = 0.0
var _treasure_fx: Node2D = null

## 断念铃：摇铃前摇（可被眩晕 / 封技打断）
var _bell_pending: bool = false
var _bell_cast_left: float = 0.0
var _bell_silence: float = 1.8
var _bell_range: float = 300.0
var _bell_charge_fx: Node2D = null
## 禁步桩场地
var _stake_field: Node2D = null
## 续命灯：点亮窗口 + 触发后的 1 秒回复
var _lamp_left: float = 0.0
var _lamp_heal_left: float = 0.0
var _lamp_heal_rate: float = 0.0
var _lamp_heal_ratio: float = 0.15
var _lamp_invuln: float = 0.8
var _lamp_knockback: float = 200.0
var _lamp_fx: Node2D = null
## 棘甲佩：近战反伤状态
var _thorns_left: float = 0.0
var _thorns_ratio: float = 0.0
var _thorns_fx: Node2D = null

var _visual_id: String = ""
var _aggro_range: float = 330.0
var _leash_range: float = 720.0
var _melee_range: float = 78.0
var _melee_angle: float = 110.0
var _melee_coeff: float = 0.7
var _attack_name: String = "攻击"
var _melee_fx: String = ""
var _body_radius: float = 0.0
var _cast_coeff: float = 0.35
var _cast_range: float = 480.0
var _phase2_allowed: bool = false

var _engaged: bool = false
var _returning: bool = false
var _skill_cd: float = 0.0
var _next_skill: String = ""
## 当前施放功法在 BOSS 侧的伤害类型（physical_melee / physical_projectile / elemental）
## 修士的功法来自凡界 BOSS 招式，**不是所有功法都是法术**：
## 横斩 / 突进斩这类物理招必须按物理表现（橙色前摇、可弹反），只有元素招才是蓝色。
var _pending_skill_kind: String = "physical_melee"
var _skill_index: int = 0
## 核心首领技能组（SecretWorldDB.CORE_SKILLS）与每个技能的独立冷却
var _core_skills: Array = []
var _core_skill_cds: Dictionary = {}
var _next_core_skill: Dictionary = {}
var _last_core_skill: String = ""
var _core_attack_cd: float = 0.0
## 当前招式的自定义前摇（秒）；<=0 时走 BossBase 的阶段默认前摇
var _pending_windup: float = -1.0
var _name_label: Label
var _hp_bar: ColorRect
var _died_emitted: bool = false

## 血条 / 名字配色覆盖（alpha = 0 表示不覆盖，仍按 enemy_kind 分色）。
## 用途：试炼之路里全是敌人，山魈射手借修士 AI 却会被刷成「野修蓝」血条。
var _hp_tint: Color = Color(0.0, 0.0, 0.0, 0.0)
var _name_tint: Color = Color(0.0, 0.0, 0.0, 0.0)

## 待机动作：距下一次踱步的秒数 / 目标点
var _idle_act_cd: float = 0.0
var _idle_pace_target: Vector2 = Vector2.ZERO
## 追逐侧向弧度相位（每个实例错开，避免同屏敌人步伐整齐划一）
var _strafe_phase: float = 0.0

## 被挡住时的绕行（当前意图速度、卡住计时、绕行方向）
var _chase_intent: Vector2 = Vector2.ZERO
var _blocked_time: float = 0.0
var _avoid_time: float = 0.0
var _avoid_dir: Vector2 = Vector2.ZERO
var _avoid_sign: float = 1.0


## 入树前调用（管理器 instantiate 之后、add_child 之前）
## cfg 直接取 SecretWorldDB 的条目（已附带 pos）
func configure(cfg: Dictionary, p_kind: String, p_name: String) -> void:
	enemy_kind = p_kind
	display_name = p_name
	spawn_home = Vector2(cfg.get("pos", Vector2.ZERO))
	max_hp = float(cfg.get("max_hp", 100.0))
	attack_power = float(cfg.get("attack_power", 10.0))
	_visual_id = String(cfg.get("visual_id", ""))
	_aggro_range = float(cfg.get("aggro_range", 330.0))
	_leash_range = float(cfg.get("leash_range", 720.0))
	_melee_range = float(cfg.get("melee_range", 78.0))
	_melee_angle = float(cfg.get("melee_angle", 110.0))
	_melee_coeff = float(cfg.get("melee_coeff", 0.7))
	_attack_name = String(cfg.get("attack_name", "攻击"))
	_melee_fx = String(cfg.get("melee_fx", ""))
	_body_radius = float(cfg.get("body_radius", 0.0))
	_cast_coeff = float(cfg.get("cast_coeff", 0.35))
	# 可选：血条 / 名字配色覆盖（缺省按 enemy_kind 分色，见 _hp_color / _name_color）
	var hp_tint: Variant = cfg.get("hp_color", null)
	if hp_tint is Color:
		_hp_tint = hp_tint
	var name_tint: Variant = cfg.get("name_color", null)
	if name_tint is Color:
		_name_tint = name_tint
	skill_ids = (cfg.get("skills", []) as Array).duplicate()
	_treasure_mana_max = float(cfg.get("treasure_mana_max", 100.0))
	_treasure_mana = _treasure_mana_max
	_treasure_trigger_ratio = clampf(float(cfg.get("treasure_trigger_hp_ratio", 0.55)), 0.0, 1.0)
	if enemy_kind == KIND_CORE:
		_core_skills = (cfg.get("core_skills", []) as Array).duplicate(true)
		_core_skill_cds.clear()
		for raw in _core_skills:
			_core_skill_cds[String((raw as Dictionary).get("id", ""))] = 0.0
		_core_attack_cd = 0.6

	var spd := float(cfg.get("move_speed", 100.0))
	MOVE_SPEED_P1 = spd
	MOVE_SPEED_P2 = spd * 1.3
	_skill_cd = randf_range(0.4, 1.6)
	_strafe_phase = randf() * TAU
	_idle_act_cd = randf_range(0.8, 2.2)
	var cfg_windup := float(cfg.get("windup", -1.0))

	match enemy_kind:
		KIND_CULTIVATOR:
			RANGED_STOP_DISTANCE = 280.0
			WINDUP_TIME_P1 = 0.60
			WINDUP_TIME_P2 = 0.60
			RECOVER_TIME_P1 = 0.75
			RECOVER_TIME_P2 = 0.75
			_cast_range = 520.0
		KIND_CORE:
			# 停止距离必须小于近战距离（150），否则核心首领会停在 150 之外永远打不到玩家
			RANGED_STOP_DISTANCE = 120.0
			WINDUP_TIME_P1 = cfg_windup if cfg_windup > 0.0 else 0.85
			WINDUP_TIME_P2 = maxf(0.4, WINDUP_TIME_P1 - 0.2)
			RECOVER_TIME_P1 = 0.7
			RECOVER_TIME_P2 = 0.55
			_phase2_allowed = true
		_:
			RANGED_STOP_DISTANCE = 30.0
			WINDUP_TIME_P1 = 0.55
			WINDUP_TIME_P2 = 0.55
			RECOVER_TIME_P1 = 0.55
			RECOVER_TIME_P2 = 0.55


func _ready() -> void:
	super()
	if display_name != "":
		_build_name_label()
	_sync_skin_motion()


func _physics_process(delta: float) -> void:
	super(delta)
	if state == BossState.DEAD:
		return
	_tick_blocked(delta)
	if enemy_kind == KIND_CULTIVATOR:
		_tick_carried_treasure(delta)
		_tick_idle_act_cd(delta)
	_sync_skin_motion()


## 大世界敌人的动画驱动：静止播待机（修士复用主角的 daiji 呼吸帧），
## 移动时播侧向行走帧。以前没人调 set_moving，修士会一直用行走帧原地踏步。
func _sync_skin_motion() -> void:
	if skin == null:
		return
	var moving := velocity.length_squared() > 9.0
	skin.set_moving(moving)
	skin.set_facing(velocity if moving else facing)


## 逐电环生效时把走位速度抬到 800；普通移动仍吃重伤等 debuff 倍率
func _move_speed() -> float:
	if _treasure_haste_left > 0.0 and _treasure_haste_speed > 0.0:
		return _treasure_haste_speed * debuff_move_mult()
	return super()


func _setup() -> void:
	if _visual_id != "" and skin != null:
		skin.visual_id = _visual_id
		skin.refresh()
	_apply_body_radius()
	_hp_bar = get_node_or_null("HPBarBG/HPBar") as ColorRect
	if _hp_bar != null:
		_hp_bar.color = _hp_color()
		# 对局棋子的**队伍色优先**于按 enemy_kind 的分色：本函数跑在
		# BossBase._ready() 的上色之后，不重申一次就会把我方核心刷成红色血条。
		_tint_head_hp_bar()
	# 血条 / 名字挂到身体上方（核心首领比灵兽高得多，统一按实际视觉高度抬）
	# ⚠ 用 top_extent() 而不是 visual_rect.end.y：接入立绘后 anchor_bottom 让底边落在原点，
	#   end.y≈0，会把血条压到脚底。top_extent 是「以原点为基准的上边界」（负值）。
	var top := 46.0
	if skin != null:
		top = maxf(24.0, -skin.top_extent() + 12.0)
	var bar_w := 96.0 if enemy_kind == KIND_CORE else 64.0
	var bar_bg := get_node_or_null("HPBarBG") as Control
	if bar_bg != null:
		bar_bg.size = Vector2(bar_w, 8.0)
		bar_bg.position = Vector2(-bar_w * 0.5, -top)
	if _name_label != null:
		var name_w := 220.0 if enemy_kind == KIND_CORE else 160.0
		_name_label.size = Vector2(name_w, 20.0)
		_name_label.position = Vector2(-name_w * 0.5, -top - 24.0)
	# 血条宽度改过之后要立刻按新宽度重算填充比例，否则满血时看起来只有 2/3
	_update_head_hp_bar()


## 不同体型的受击半径（玩家判定读 hit_radius()）
func _apply_body_radius() -> void:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return
	var r := 22.0
	if _body_radius > 0.0:
		r = _body_radius
	else:
		match enemy_kind:
			KIND_CULTIVATOR:
				r = 18.0
			KIND_CORE:
				r = 40.0
			_:
				r = 26.0 if max_hp >= 220.0 else 22.0
	var circle := (cs.shape as CircleShape2D).duplicate() as CircleShape2D
	circle.radius = r
	cs.shape = circle


func _build_name_label() -> void:
	var top := 46.0
	if skin != null:
		top = maxf(24.0, -skin.top_extent() + 12.0)
	_name_label = UIKit.label(display_name, UIKit.F_SMALL, _name_color())
	var name_w := 220.0 if enemy_kind == KIND_CORE else 160.0
	_name_label.size = Vector2(name_w, 20.0)
	_name_label.position = Vector2(-name_w * 0.5, -top - 24.0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)


## 招式特效（SkillFx）按施法者震屏；大世界相机在玩家身上，转发过去
func _screen_shake(intensity: float, duration: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("_screen_shake"):
		p.call("_screen_shake", intensity, duration)


# ===================== 仇恨 / 脱战 =====================
## 覆写基类：基类会在任意距离锁玩家，大世界需要「仇恨半径 + 脱战回家」
## 圈内选目标完全交给基类仇恨表（与位面挑战一致），圈外才套大世界的进战/脱战规则
func _tick_threat(delta: float) -> void:
	if state == BossState.DEAD:
		return
	# 对局棋子（team_id >= 0）：大世界的「进战半径 + 脱战回家」整套不成立 ——
	# 棋盘上没有玩家，下面那段会在每帧把 target 清成 null，基类仇恨表根本没机会
	# 把对面的棋子选为目标，四只核心实测因此 0 输出。
	# 而且 spawn_home 是出生格，走回家 / 脱战回满血在棋局里都是错的。
	# 所以直接交回基类：它按 enemy_units() 的选目标，队伍号已经在 BossBase 里分支好了。
	if team_id >= 0:
		super._tick_threat(delta)
		return
	# 被玩家五旗环围住：优先旗目标（与 BossBase 同一套）
	if _tick_player_array_trap_override():
		return
	var p := get_tree().get_first_node_in_group("player") as Node2D
	var player_dead := p != null and bool(p.get("is_dead"))
	if p == null or player_dead:
		target = null
		threat_target = null
		_threat.clear()
		if not _returning and global_position.distance_to(spawn_home) > _home_limit():
			_start_return_home()
		return

	if _returning:
		target = null
		threat_target = null
		return

	var dist := global_position.distance_to(p.global_position)
	var home_dist := global_position.distance_to(spawn_home)

	if not _engaged:
		# 先让基类跑一遍：衰减伤害窗口、清理已消散的召唤物
		# （未进战时它选出的目标下面会被清掉，不会在圈外提前开打）
		super._tick_threat(delta)
		# 被远程打中也要进入战斗（否则在仇恨圈外用远程蹭怪，怪永远不还手）
		var provoked := _provoked()
		if (dist <= _aggro_range or provoked) and dist <= _leash_range and home_dist <= _leash_range:
			_engaged = true
		else:
			target = null
			threat_target = null
			if home_dist > _home_limit():
				_start_return_home()
			return

	if dist > _leash_range or home_dist > _leash_range:
		_disengage()
		return

	super._tick_threat(delta)


## 是否有任何单位对本体记账（只算伤害/嘲讽，**不含距离仇恨**）
## ⚠ 不能直接用 threat_of_unit(p)：距离仇恨在 600 码内都 > 0，仇恨圈会变成 600
func _provoked() -> bool:
	for u in _threat.keys():
		if u == null or not is_instance_valid(u):
			continue
		var rec: Dictionary = _threat[u]
		for key in ["dmg", "taunt", "flat"]:
			if not (rec.get(key, []) as Array).is_empty():
				return true
	return false


## 脱战：清空目标与仇恨表、回满血、走回出生点
func _disengage() -> void:
	_engaged = false
	target = null
	threat_target = null
	_threat.clear()
	velocity = Vector2.ZERO
	current_hp = max_hp
	# 脱战回满后允许下次接战重新使用携带法宝
	_treasure_cooldown_left = 0.0
	_treasure_channel_left = 0.0
	_treasure_tick = 0.0
	_treasure_haste_left = 0.0
	_treasure_haste_speed = 0.0
	if is_instance_valid(_treasure_fx):
		_treasure_fx.queue_free()
	_treasure_fx = null
	_clear_treasure_runtime()
	_treasure_mana = _treasure_mana_max
	_update_head_hp_bar()
	_start_return_home()


func _start_return_home() -> void:
	if _returning:
		return
	_returning = true
	velocity = Vector2.ZERO
	_idle_pace_target = Vector2.ZERO
	state = STATE_RETURN_HOME
	state_timer = 0.0


func _is_extra_state(s: int) -> bool:
	return s == STATE_RETURN_HOME or s == STATE_IDLE_ACT


func _tick_extra_state(delta: float) -> void:
	match state:
		STATE_RETURN_HOME:
			_tick_return_home(delta)
		STATE_IDLE_ACT:
			_tick_idle_act(delta)


func _tick_return_home(delta: float) -> void:
	var to_home := spawn_home - global_position
	if to_home.length() <= 16.0:
		global_position = spawn_home
		velocity = Vector2.ZERO
		_returning = false
		current_hp = max_hp
		_update_head_hp_bar()
		state = BossState.IDLE
		state_timer = _idle_time()
		return
	var dir := to_home.normalized()
	velocity = dir * _move_speed() * 1.6
	_face_dir(dir)
	if delta < 0.0:
		velocity = Vector2.ZERO


# ===================== 待机动作（野外修士） =====================
## 脱战空闲时每 2.4~5 秒踱一小步：在出生点附近选个点慢慢走过去，
## 走完回到 IDLE（播呼吸帧）。玩家一进仇恨圈立刻中断去追击。
func _tick_idle_act_cd(delta: float) -> void:
	if _engaged or target != null:
		_idle_act_cd = maxf(_idle_act_cd, 1.0)
		return
	if state != BossState.IDLE:
		return
	_idle_act_cd -= delta
	if _idle_act_cd > 0.0:
		return
	_idle_act_cd = randf_range(IDLE_ACT_GAP_MIN, IDLE_ACT_GAP_MAX)
	_start_idle_act()


## 允许离出生点多远：踱步时放宽到踱步半径，否则按原来的 20 码回位阈值
## （不放宽会在踱出 20 码的瞬间被「回家」打断，看起来只挪了一小步）
func _home_limit() -> float:
	return IDLE_PACE_RADIUS + 24.0 if state == STATE_IDLE_ACT else 20.0


func _start_idle_act() -> void:
	if _returning or _engaged or target != null:
		return
	if global_position.distance_to(spawn_home) > IDLE_PACE_RADIUS + 24.0:
		return
	_idle_pace_target = spawn_home + Vector2.RIGHT.rotated(randf_range(0.0, TAU)) \
		* randf_range(32.0, IDLE_PACE_RADIUS)
	state = STATE_IDLE_ACT
	state_timer = randf_range(1.0, 2.0)


func _tick_idle_act(delta: float) -> void:
	# 玩家进圈：立刻结束踱步，下一帧交给正常行为树（不要先站着发 1 秒呆）
	if target != null or _engaged:
		_end_idle_act(true)
		return
	state_timer -= delta
	var to_target := _idle_pace_target - global_position
	if state_timer <= 0.0 or to_target.length() <= 6.0:
		_end_idle_act(false)
		return
	var dir := to_target.normalized()
	velocity = dir * _move_speed() * 0.42
	_face_dir(dir)


func _end_idle_act(immediate: bool) -> void:
	velocity = Vector2.ZERO
	_idle_pace_target = Vector2.ZERO
	state = BossState.IDLE
	state_timer = 0.0 if immediate else randf_range(0.8, 1.8)


# ===================== 选招 =====================
func _tick_cooldowns(delta: float) -> void:
	if _skill_cd > 0.0:
		_skill_cd -= delta
	if _core_attack_cd > 0.0:
		_core_attack_cd = maxf(0.0, _core_attack_cd - delta)
	for id in _core_skill_cds.keys():
		if float(_core_skill_cds[id]) > 0.0:
			_core_skill_cds[id] = maxf(0.0, float(_core_skill_cds[id]) - delta)


# ===================== 携带法宝（野修） =====================
## 野修在战斗中主动使用携带法宝：
##   凝水佩 → 血量降到阈值以下后引导回血，按秒扣灵力；
##   逐电环 → 一进战就催动，30 灵力换 3 秒移速 800；
##   断念铃 → 摇铃 0.45 秒后封玩家功法；前摇可被眩晕 / 封技打断；
##   禁步桩 → 在玩家脚下埋桩；续命灯 → 低血点灯；蚀甲锥 → 掷锥破护体。
## 所有法宝共用一次携带冷却；脱战后冷却与灵力重置。
func _tick_carried_treasure(delta: float) -> void:
	if carried_treasure.is_empty() or state == BossState.DEAD:
		return
	_tick_lamp_state(delta)
	_tick_thorns_state(delta)
	_tick_bell_telegraph(delta)
	if _treasure_cooldown_left > 0.0:
		_treasure_cooldown_left = maxf(0.0, _treasure_cooldown_left - delta)
	if _treasure_haste_left > 0.0:
		_treasure_haste_left = maxf(0.0, _treasure_haste_left - delta)

	if not _engaged or target == null:
		return

	if _treasure_channel_left <= 0.0 and _treasure_cooldown_left <= 0.0 \
			and not _bell_pending:
		var start_stats := ItemDB.treasure_active_stats(carried_treasure)
		if not start_stats.is_empty():
			var kind := String(start_stats.get("kind", ""))
			var want := false
			var dist := global_position.distance_to(target.global_position)
			if kind == "heal":
				want = current_hp <= max_hp * _treasure_trigger_ratio
			elif kind == "haste":
				want = _treasure_haste_left <= 0.0
			elif kind == "mind_lock":
				want = dist <= float(start_stats.get("range", 300.0))
				if want and target.has_method("is_treasure_bell_immune") \
						and bool(target.call("is_treasure_bell_immune")):
					want = false
			elif kind == "stake":
				want = dist <= float(start_stats.get("range", 300.0))
			elif kind == "lamp":
				var ratio := float(start_stats.get("trigger_hp_ratio", 0.4))
				want = _lamp_left <= 0.0 and current_hp <= max_hp * ratio
			elif kind == "corrode":
				want = dist <= float(start_stats.get("range", 400.0))
			elif kind == "blood_seal":
				var min_ratio := float(start_stats.get("min_hp_ratio", 0.25))
				want = current_hp > max_hp * min_ratio and _skill_cd > 1.0
			elif kind == "swap":
				want = dist <= 220.0
			elif kind == "thorns":
				want = dist <= 160.0 and _thorns_left <= 0.0
			elif kind == "gust":
				want = dist <= 180.0
			if want and _treasure_mana >= float(start_stats.get("mana", 10.0)):
				_activate_carried_treasure(start_stats)

	if _treasure_channel_left <= 0.0:
		return
	var stats := ItemDB.treasure_active_stats(carried_treasure)
	if stats.is_empty() or String(stats.get("kind", "")) != "heal":
		_treasure_channel_left = 0.0
		return
	_treasure_channel_left -= delta
	_treasure_tick += delta
	while _treasure_tick >= 1.0:
		_treasure_tick -= 1.0
		var cost := float(stats.get("mana", 10.0))
		if _treasure_mana < cost:
			_treasure_channel_left = 0.0
			_show_enemy_float("灵力不足", UIKit.C_FLOAT_WARN)
			return
		_treasure_mana -= cost
		var healed := apply_heal(float(stats.get("heal", 5.0)))
		if healed > 0.0:
			_show_enemy_float("+%d" % int(round(healed)), Color(0.52, 1.0, 0.68))
		if _treasure_channel_left <= 0.0:
			return


func _activate_carried_treasure(stats: Dictionary) -> void:
	var kind := String(stats.get("kind", ""))
	var duration := float(stats.get("duration", 3.0))
	var tid := String(carried_treasure.get("id", ""))
	if tid != "":
		_treasure_cooldown_left = float(stats.get("cooldown", 30.0))
	if kind == "heal":
		_treasure_channel_left = duration
		_treasure_tick = 0.0
		_show_enemy_float("凝水佩", Color(0.52, 0.9, 1.0))
		TreasureFx.play_water_gather(self, _treasure_body_center())
	elif kind == "haste":
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 30.0)))
		_treasure_haste_left = duration
		_treasure_haste_speed = float(stats.get("speed", 800.0))
		_treasure_fx = TreasureFx.attach_thunder(self, _treasure_body_center(), duration)
		_show_enemy_float("逐电环", TreasureFx.THUNDER_COLOR)
	elif kind == "mind_lock":
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 20.0)))
		_bell_pending = true
		_bell_cast_left = float(stats.get("telegraph", 0.45))
		_bell_silence = float(stats.get("silence", 1.8))
		_bell_range = float(stats.get("range", 300.0))
		_bell_charge_fx = TreasureFx.attach_bell_charge(self, _treasure_body_center(),
			_bell_cast_left)
		_show_enemy_float("断念铃", DebuffDB.color("duannian"))
	elif kind == "stake":
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 15.0)))
		var tpl := ItemDB.get_treasure_template(String(carried_treasure.get("id", "")))
		if is_instance_valid(_stake_field):
			_stake_field.queue_free()
		_stake_field = TreasureStakeField.new()
		_stake_field.setup(target.global_position, false,
			float(stats.get("radius", 110.0)),
			float(stats.get("arm_time", 0.8)),
			float(stats.get("duration", 4.0)),
			float(stats.get("initial_slow", 1.5)),
			float(stats.get("slow_mult", 0.65)),
			float(stats.get("slow_refresh", 0.6)),
			String(tpl.get("icon", "")), self)
		get_parent().add_child(_stake_field)
		_show_enemy_float("禁步桩", DebuffDB.color("jinbu"))
	elif kind == "lamp":
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 25.0)))
		_lamp_left = duration
		_lamp_heal_left = 0.0
		_lamp_heal_ratio = float(stats.get("heal_ratio", 0.15))
		_lamp_invuln = float(stats.get("invuln", 0.8))
		_lamp_knockback = float(stats.get("knockback_radius", 200.0))
		if is_instance_valid(_lamp_fx):
			_lamp_fx.queue_free()
		_lamp_fx = TreasureFx.attach_lamp(self, _treasure_body_center(), _lamp_left)
		_show_enemy_float("续命灯", Color(1.0, 0.86, 0.46))
	elif kind == "corrode":
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 15.0)))
		var dir := (target.global_position - global_position)
		if dir.length_squared() < 0.0001:
			dir = facing
		dir = dir.normalized()
		var tpl := ItemDB.get_treasure_template(String(carried_treasure.get("id", "")))
		var cone := TreasureCone.new()
		cone.setup(self, "player", dir, float(stats.get("speed", 900.0)),
			float(stats.get("range", 400.0)), "shixi",
			float(stats.get("duration", 8.0)), String(tpl.get("icon", "")))
		get_parent().add_child(cone)
		# 判定是一根身体立柱 + 逐帧形状查询（见 treasure_cone.gd），静态体也拦不住
		cone.global_position = global_position + dir * 26.0
		_show_enemy_float("蚀甲锥", DebuffDB.color("shixi"))
	elif kind == "blood_seal":
		var min_ratio := float(stats.get("min_hp_ratio", 0.25))
		if current_hp <= max_hp * min_ratio:
			return
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 0.0)))
		var cost_hp := max_hp * float(stats.get("hp_ratio", 0.15))
		current_hp = maxf(1.0, current_hp - cost_hp)
		health_changed.emit(current_hp, max_hp)
		_update_head_hp_bar()
		_skill_cd = 0.0
		TreasureFx.play_blood_seal(self, _treasure_body_center())
		_show_enemy_float("血饲印", Color(0.86, 0.32, 0.28))
	elif kind == "swap":
		if target == null or not is_instance_valid(target):
			return
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 20.0)))
		var my_pos := global_position
		var target_pos := target.global_position
		target.global_position = my_pos
		global_position = target_pos
		_clamp_to_arena()
		_treasure_invuln_left = maxf(_treasure_invuln_left, float(stats.get("invuln", 0.4)))
		TreasureFx.play_swap(get_parent(), my_pos, target_pos)
		_show_enemy_float("换位玦", Color(0.56, 0.86, 0.78))
	elif kind == "thorns":
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 15.0)))
		_thorns_left = duration
		_thorns_ratio = float(stats.get("reflect_ratio", 0.30))
		if is_instance_valid(_thorns_fx):
			_thorns_fx.queue_free()
		_thorns_fx = TreasureFx.attach_thorns(self, _treasure_body_center(), _thorns_left)
		_show_enemy_float("棘甲佩", Color(0.92, 0.46, 0.38))
	elif kind == "gust":
		_treasure_mana = maxf(0.0, _treasure_mana - float(stats.get("mana", 15.0)))
		var radius := float(stats.get("radius", 220.0))
		var push := float(stats.get("push", 240.0))
		for raw in attack_units():
			if not is_instance_valid(raw) or not raw is Node2D:
				continue
			var u := raw as Node2D
			if global_position.distance_to(u.global_position) > radius:
				continue
			if not u.has_method("take_knockback"):
				continue
			var dir := u.global_position - global_position
			if dir.length_squared() <= 0.0001:
				continue
			u.call("take_knockback", dir.normalized() * push)
		TreasureFx.play_gust(self, _treasure_body_center(), radius)
		_show_enemy_float("回风袋", Color(0.64, 0.86, 0.84))


## 续命灯：亮着的时候按帧回血，窗口结束自动熄灯
func _tick_lamp_state(delta: float) -> void:
	if _lamp_heal_left > 0.0:
		var step := minf(delta, _lamp_heal_left)
		_lamp_heal_left -= step
		if state != BossState.DEAD and _lamp_heal_rate > 0.0:
			# 续命灯的回血同样吃治疗乘区：被蚀时只剩 10%，这就是暗对"奶流"目标的用处
			apply_heal(_lamp_heal_rate * step)
	if _lamp_left <= 0.0:
		return
	_lamp_left = maxf(0.0, _lamp_left - delta)
	if _lamp_left <= 0.0 and is_instance_valid(_lamp_fx):
		_lamp_fx.queue_free()
		_lamp_fx = null


## 棘甲佩：持续期间近战物理受击反伤
func _tick_thorns_state(delta: float) -> void:
	if _thorns_left <= 0.0:
		return
	_thorns_left = maxf(0.0, _thorns_left - delta)
	if _thorns_left <= 0.0:
		_thorns_ratio = 0.0
		if is_instance_valid(_thorns_fx):
			_thorns_fx.queue_free()
		_thorns_fx = null


func _reflect_thorns(mitigated: float, source: Node, damage_kind: String,
		from_projectile: bool) -> float:
	if _thorns_left <= 0.0 or damage_kind != "physical" or from_projectile:
		return 0.0
	if source == null or not is_instance_valid(source) or source == self:
		return 0.0
	if not source.has_method("take_true_damage"):
		return 0.0
	TreasureFx.play_thorns_burst(self, _treasure_body_center())
	return mitigated * _thorns_ratio


## 断念铃：前摇内被眩晕 / 封技打断则不进冷却
func _tick_bell_telegraph(delta: float) -> void:
	if not _bell_pending:
		return
	if state == BossState.DEAD or target == null or not is_instance_valid(target) \
			or is_stunned() or is_skill_locked():
		_cancel_bell()
		return
	_bell_cast_left -= delta
	if _bell_cast_left <= 0.0:
		_resolve_bell()


func _resolve_bell() -> void:
	_bell_pending = false
	if is_instance_valid(_bell_charge_fx):
		_bell_charge_fx.queue_free()
	_bell_charge_fx = null
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > _bell_range + 20.0:
		_show_enemy_float("断念落空", Color(0.7, 0.7, 0.75))
		return
	if target.has_method("is_treasure_bell_immune") \
			and bool(target.call("is_treasure_bell_immune")):
		return
	if target.has_method("apply_debuff"):
		target.call("apply_debuff", "duannian", _bell_silence)
	if target.has_method("mark_treasure_bell_immune"):
		target.call("mark_treasure_bell_immune", 8.0)
	TreasureFx.play_bell_ring(self, _treasure_body_center(), _bell_range,
		DebuffDB.color("duannian"))


func _cancel_bell() -> void:
	_bell_pending = false
	_bell_cast_left = 0.0
	if is_instance_valid(_bell_charge_fx):
		_bell_charge_fx.queue_free()
	_bell_charge_fx = null
	# 打断不进完整冷却，只留 0.6 秒避免同一帧反复重试
	_treasure_cooldown_left = minf(_treasure_cooldown_left, 0.6)
	_show_enemy_float("断念被打断", UIKit.C_FLOAT_WARN)


## 续命灯：第一次致死伤害改为留 1 点气血
func _adjust_lethal_damage(amount: float) -> float:
	if state != BossState.DEAD and _lamp_left > 0.0 and amount >= current_hp:
		_trigger_lamp_save()
		return maxf(0.0, current_hp - 1.0)
	return amount


func _trigger_lamp_save() -> void:
	var heal_ratio := _lamp_heal_ratio
	_lamp_left = 0.0
	_lamp_heal_left = 1.0
	_lamp_heal_rate = max_hp * heal_ratio
	_treasure_invuln_left = maxf(_treasure_invuln_left, _lamp_invuln)
	if is_instance_valid(_lamp_fx):
		_lamp_fx.queue_free()
	_lamp_fx = null
	TreasureFx.play_lamp_break(self, _treasure_body_center())
	for raw in attack_units():
		if not is_instance_valid(raw) or not raw is Node2D:
			continue
		var u := raw as Node2D
		if global_position.distance_to(u.global_position) > _lamp_knockback:
			continue
		if u.has_method("take_knockback"):
			var dir: Vector2 = (u.global_position - global_position)
			if dir.length_squared() > 0.0001:
				u.call("take_knockback", dir.normalized() * 280.0)
	_show_enemy_float("灯替一死", Color(1.0, 0.88, 0.50))


## 死亡 / 脱战：铃、桩、灯一起收掉
func _clear_treasure_runtime() -> void:
	_bell_pending = false
	_bell_cast_left = 0.0
	if is_instance_valid(_bell_charge_fx):
		_bell_charge_fx.queue_free()
	_bell_charge_fx = null
	if is_instance_valid(_stake_field):
		_stake_field.queue_free()
	_stake_field = null
	_lamp_left = 0.0
	_lamp_heal_left = 0.0
	_lamp_heal_rate = 0.0
	if is_instance_valid(_lamp_fx):
		_lamp_fx.queue_free()
	_lamp_fx = null
	_thorns_left = 0.0
	_thorns_ratio = 0.0
	if is_instance_valid(_thorns_fx):
		_thorns_fx.queue_free()
	_thorns_fx = null


func _treasure_body_center() -> Vector2:
	if skin != null:
		return skin.body_center()
	return Vector2(0.0, -34.0)


## 野修头顶的小飘字（法宝启动 / 回血），不抢 BossBase 的技能名前摇
func _show_enemy_float(text: String, color: Color) -> void:
	var label := UIKit.readable_label(text, 17, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(-50.0, -86.0)
	label.size = Vector2(100.0, 22.0)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 20
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 24.0, 0.75)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.75)
	tween.tween_callback(label.queue_free)


func _choose_next_action() -> void:
	if target == null or not is_instance_valid(target):
		target = null
		threat_target = null
		if global_position.distance_to(spawn_home) > 20.0:
			_start_return_home()
		else:
			state = BossState.IDLE
			state_timer = _idle_time()
		return
	_pick_and_begin(_distance_to_target())


func _on_chase_reached(dist: float) -> void:
	if target != null and is_instance_valid(target):
		_pick_and_begin(dist)


func _pick_and_begin(dist: float) -> void:
	match enemy_kind:
		KIND_BEAST:
			# ⚠ 起手距离必须 ≤ 实际命中距离（_do_melee 用的是 _melee_range）。
			#   原来乘了 1.2：在 78~94 之间起手，起手时速度已清零、前摇里不会补步，
			#   于是这一爪必定砍空 —— 玩家看到的就是「小怪在攻击范围外挥爪」。
			if dist <= _melee_range:
				_begin_attack(AttackKind.PHYSICAL_MELEE)
			else:
				state = BossState.CHASE
		KIND_CULTIVATOR:
			# 只有目标进了「这一招的实际命中距离」才起手：以前按固定 520 施法距离，
			# 会在仇恨圈边缘甩出 160 码的扇形刀气，整招打空气。
			if _skill_cd <= 0.0 and not skill_ids.is_empty():
				var candidate := String(skill_ids[_skill_index % skill_ids.size()])
				if dist <= _skill_reach(candidate):
					_next_skill = candidate
					_skill_index += 1
					_pending_skill_kind = _skill_attack_kind(_next_skill)
					_begin_attack(KIND_SKILL)
					return
			if dist <= _melee_range:
				_begin_attack(AttackKind.PHYSICAL_MELEE)
			else:
				state = BossState.CHASE
		KIND_CORE:
			# 首领行为树：技能就绪且距离合适 → 按权重选招；否则近战 / 追击。
			# _core_attack_cd 是「两招之间的收招间隔」，避免连续甩技能。
			if _core_attack_cd > 0.0:
				if dist <= _melee_range:
					state = BossState.IDLE
					state_timer = 0.25
				else:
					state = BossState.CHASE
				return
			var skill := _pick_core_skill(dist)
			if not skill.is_empty():
				_start_core_skill(skill)
				return
			if dist <= _melee_range:
				_begin_attack(AttackKind.PHYSICAL_MELEE)
				_core_attack_cd = 0.25
			else:
				state = BossState.CHASE
		_:
			if dist <= _melee_range:
				_begin_attack(AttackKind.PHYSICAL_MELEE)
			elif _skill_cd <= 0.0:
				_begin_attack(AttackKind.ELEMENTAL if randf() < 0.35 else AttackKind.PHYSICAL_PROJECTILE)
			else:
				state = BossState.CHASE


## 核心首领选招：相位 / 冷却 / 距离窗口 / 权重 / 不连续重复同一招
## 比原来「近战 or 随机远程」多了一层：远距离优先投掷，贴身优先震地，二阶段解锁大范围爆发。
func _pick_core_skill(dist: float) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for raw in _core_skills:
		var def: Dictionary = raw
		if int(def.get("phase", 1)) > phase:
			continue
		var id := String(def.get("id", ""))
		if id == "" or float(_core_skill_cds.get(id, 0.0)) > 0.0:
			continue
		var min_r := float(def.get("min_range", 0.0))
		var max_r := float(def.get("range", 200.0))
		if dist < min_r or dist > max_r:
			continue
		var ideal := float(def.get("ideal_range", (min_r + max_r) * 0.5))
		var fit := 1.0 - clampf(absf(dist - ideal) / maxf(max_r - min_r, 1.0), 0.0, 1.0) * 0.5
		var score := float(def.get("weight", 1.0)) * fit * randf_range(0.85, 1.15)
		if id == _last_core_skill:
			score *= 0.35
		if score > best_score:
			best_score = score
			best = def
	return best


func _start_core_skill(def: Dictionary) -> void:
	_next_core_skill = def
	_pending_skill_kind = String(def.get("attack_kind", "physical_melee"))
	var windup := float(def.get("windup", 0.8))
	if phase == 2:
		windup *= 0.85
	_pending_windup = maxf(0.2, windup)
	_begin_attack(KIND_CORE_SKILL)
	# 核心首领的骨骼招式：每招在 CORE_SKILLS 里有自己的 anim 名（多招共用 form 也能分开）
	if skin != null:
		var anim := String(def.get("anim", ""))
		if anim != "":
			skin.play_one_shot(anim, maxf(0.2, windup) + 0.15)
		else:
			_play_form_anim(String(def.get("form_id", "")), maxf(0.2, windup) + 0.15)


## 功法实际能打到的距离（以 MoveDB 的命中配置为准）
## 扇形 / 圆形 / 直线用命中半径，投射物用飞行距离；都留一点余量防边缘打空
func _skill_reach(skill_id: String) -> float:
	var form_id := SkillDB.get_form_id(skill_id)
	if form_id == "":
		return _cast_range
	var form := MoveDB.resolve_boss(form_id)
	if form.is_empty():
		return _cast_range
	var r := float(form.get("range", _cast_range))
	if String(form.get("hit_shape", "")) == MoveDB.SHAPE_PROJECTILE:
		return minf(_cast_range, r * 0.95)
	return minf(_cast_range, r * 0.85)


# ===================== 移动 / 行为树 =====================
## 战斗中的待机空档（攻击后摇结束到下一招之间）不再站着：
## 贴身就后撤半步、太远就压上去、距离合适就侧移绕圈
func _tick_state(delta: float) -> void:
	super(delta)
	if state == BossState.IDLE and not phase_transitioning \
			and target != null and is_instance_valid(target):
		_combat_idle_move(delta)


func _combat_idle_move(delta: float) -> void:
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	if dist <= 0.001:
		velocity = Vector2.ZERO
		return
	var dir := to_target / dist
	_strafe_phase += delta * 1.4
	var keep := _melee_range * 0.9
	var move := Vector2.ZERO
	if dist < keep * 0.8:
		move = -dir * 0.5
	elif dist > keep * 1.6:
		move = dir * 0.6
	else:
		move = dir.orthogonal() * (0.55 if sin(_strafe_phase) >= 0.0 else -0.55)
	velocity = move * _move_speed()
	_face_dir(dir)


## 覆写基类追逐：修士不再停在 280 码等技能冷却 ——
##   技能可用且目标在实际命中距离内 → 起手（_on_chase_reached 会立刻选招）
##   否则压到近战距离用近战顶上，全程保持移动
## 另外加一点侧向弧度与「被挡住就侧绕」，避免一条直线怼脸、卡在障碍/玩家身上
func _chase_target(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = null
		threat_target = null
		velocity = Vector2.ZERO
		_chase_intent = Vector2.ZERO
		return
	var to_target: Vector2 = target.global_position - global_position
	var dist := to_target.length()
	var dir := to_target.normalized()

	var stop_dist := RANGED_STOP_DISTANCE
	if enemy_kind == KIND_CULTIVATOR:
		stop_dist = _melee_range * 0.8
	if dist <= stop_dist:
		velocity = Vector2.ZERO
		_chase_intent = Vector2.ZERO
		_face_dir(dir)
		return
	if dist < 40.0:
		velocity = -dir * _move_speed()
		_face_dir(dir)
		_chase_intent = velocity
		return

	var move_dir := dir
	if _avoid_time > 0.0 and _avoid_dir != Vector2.ZERO:
		move_dir = (_avoid_dir + dir * 0.35).normalized()
	else:
		_strafe_phase += delta * 1.6
		var arc := clampf((dist - 140.0) / 300.0, 0.0, 1.0) * CHASE_ARC
		move_dir = (dir + dir.orthogonal() * sin(_strafe_phase) * arc).normalized()

	velocity = move_dir * _move_speed()
	_face_dir(velocity)
	_chase_intent = velocity


## 被墙 / 玩家挡住时（实际位移远小于意图速度）向侧面绕 0.5 秒
func _tick_blocked(delta: float) -> void:
	if _avoid_time > 0.0:
		_avoid_time = maxf(0.0, _avoid_time - delta)
	var real := get_real_velocity()
	if _chase_intent.length_squared() > 100.0 and real.length() < _chase_intent.length() * 0.35:
		_blocked_time += delta
		if _blocked_time >= 0.22 and _avoid_time <= 0.0:
			_blocked_time = 0.0
			_avoid_sign = -_avoid_sign
			_avoid_time = 0.5
			_avoid_dir = _chase_intent.normalized().orthogonal() * _avoid_sign
	else:
		_blocked_time = 0.0
	_chase_intent = Vector2.ZERO


func _face_dir(dir: Vector2) -> void:
	if dir.length_squared() <= 0.0001:
		return
	facing = dir.normalized()
	anim.scale.x = 1.0 if facing.x >= 0.0 else -1.0


## 出招前清掉追逐速度：以前「边追边起手」会把 0.6 秒前摇滑成一段漂移
func _begin_attack(kind: int) -> void:
	velocity = Vector2.ZERO
	_chase_intent = Vector2.ZERO
	_avoid_time = 0.0
	if kind != KIND_CORE_SKILL:
		_pending_windup = -1.0
	super(kind)
	# 核心首领的平A也走骨骼；没人登记 attack 时 SkinVisual 会静默跳过
	if enemy_kind == KIND_CORE and kind != KIND_CORE_SKILL and skin != null:
		skin.play_one_shot("attack", maxf(_windup_time(), 0.2) + 0.15)


## 核心首领的招式可以单独配置前摇；其它攻击沿用 BossBase 的阶段默认值
func _windup_time() -> float:
	if _pending_windup > 0.0:
		return _pending_windup
	return super()


func _enter_phase_two() -> void:
	if not _phase2_allowed:
		return
	super()
	# 转阶段后二阶段招式立刻可用，演出结束就能接「山崩地裂 / 青岚灵爆」
	for id in _core_skill_cds.keys():
		_core_skill_cds[id] = 0.0
	_core_attack_cd = maxf(_core_attack_cd, 0.4)


func _damage_multiplier() -> float:
	return super() if _phase2_allowed else 1.0


# ===================== 出招 =====================
func _attack_kind_skill_name(kind: int) -> String:
	match kind:
		AttackKind.PHYSICAL_MELEE:
			return _attack_name
		AttackKind.PHYSICAL_PROJECTILE:
			return "裂石投掷"
		AttackKind.ELEMENTAL:
			return "灵压震荡"
		KIND_SKILL:
			return SkillDB.get_skill_name(_next_skill) if _next_skill != "" else "术法"
		KIND_CORE_SKILL:
			return String(_next_core_skill.get("name", "首领招式"))
	return ""


func _on_attack_windup(kind: int) -> void:
	if kind == KIND_SKILL or kind == KIND_CORE_SKILL:
		_show_windup(_skill_flash_color(_pending_skill_kind))
	elif kind == AttackKind.PHYSICAL_MELEE:
		_show_windup(Color(1.0, 0.55, 0.35))
	else:
		_show_windup(Color(0.45, 0.7, 1.0))
	# 修士复用主角素材：前摇期间播攻击序列帧（占位贴图的敌人会自动忽略）
	if skin != null:
		skin.play_one_shot("attack", maxf(0.2, _windup_time()))


## 基类的前摇缩放会把 scale 拉回正方向，向左出招时会「中途转身」；
## 这里保留当前左右朝向，只做放大
func _show_windup(color: Color) -> void:
	var sx := -1.0 if anim.scale.x < 0.0 else 1.0
	var tween := create_tween()
	tween.tween_property(anim, "scale", Vector2(1.25 * sx, 1.25), _windup_time())
	anim.modulate = color


func _reset_visual() -> void:
	var sx := -1.0 if anim.scale.x < 0.0 else 1.0
	var tween := create_tween()
	tween.tween_property(anim, "scale", Vector2(sx, 1.0), 0.1)


func _windup_color(kind: int) -> Color:
	if kind == KIND_SKILL or kind == KIND_CORE_SKILL:
		return BossBase.skill_name_color(_pending_skill_kind)
	if kind == AttackKind.PHYSICAL_MELEE or kind == AttackKind.PHYSICAL_PROJECTILE:
		return UIKit.C_DMG_PHYS
	return UIKit.C_DMG_SPELL


func _do_attack(kind: int) -> void:
	match kind:
		AttackKind.PHYSICAL_MELEE:
			_do_melee()
		AttackKind.PHYSICAL_PROJECTILE:
			_do_projectile()
		AttackKind.ELEMENTAL:
			_do_elemental()
		KIND_SKILL:
			_cast_skill()
		KIND_CORE_SKILL:
			_cast_core_skill()


func _do_melee() -> void:
	_reset_visual()
	_flash_attack(Color(1.0, 0.45, 0.35))
	_update_facing_to_target()
	if _melee_fx != "":
		# 灵兽 / 核心首领的专属近战表现；张角与距离直接取判定值，保证「看到的扇面 = 打到的扇面」
		SkillFx.play_at_strike(self, _melee_fx, {
			"hit_shape": MoveDB.SHAPE_FAN,
			"range": _melee_range,
			"angle": _melee_angle,
		}, facing)
	else:
		FxPlayer.spawn(self, "boss_blade_arc", {
			"rotation": facing.angle(),
			"radius": _melee_range,
			"sweep_deg": _melee_angle,
		})
	var dmg := attack_power * _melee_coeff * _damage_multiplier()
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - global_position
		if to_u.length() > _melee_range:
			continue
		if to_u.length() > 0.001:
			var diff := absf(rad_to_deg(wrapf(to_u.angle() - facing.angle(), -PI, PI)))
			if diff > _melee_angle * 0.5:
				continue
		deal_damage_to(u, dmg, "physical_melee")


func _do_projectile() -> void:
	_reset_visual()
	_flash_attack(Color(1.0, 0.75, 0.3))
	_update_facing_to_target()
	var proj := _spawn_projectile("physical_projectile")
	if proj != null:
		proj.set("direction", facing)
		proj.set("speed", 460.0)
		proj.set("damage", attack_power * 0.55 * _damage_multiplier())
		proj.set("life_timer", 2.0)
		proj.set("source", self)
	_skill_cd = randf_range(2.8, 4.2)


func _do_elemental() -> void:
	_reset_visual()
	_flash_attack(Color(0.45, 0.65, 1.0))
	_update_facing_to_target()
	var proj := _spawn_projectile("elemental")
	if proj != null:
		proj.set("direction", facing)
		proj.set("speed", 340.0)
		proj.set("damage", attack_power * 0.75 * _damage_multiplier())
		proj.set("life_timer", 2.6)
		proj.set("source", self)
		proj.call("set_visual_scale", 1.5)
	_skill_cd = randf_range(4.0, 6.0)


# ===================== 修士施法 =====================
## 修士功法的伤害类型以 MoveDB 的 BOSS 招式配置为唯一口径：
## 横斩 / 突进斩 / 箭术 = 物理（橙色飘字、可弹反）；法球 / 剑阵 / 剑意 = 元素（蓝色）
## 取不到招式时才退回「按功法主属性判断」
func _skill_attack_kind(skill_id: String) -> String:
	var form_id := SkillDB.get_form_id(skill_id)
	if form_id != "":
		var kind := String(MoveDB.resolve_boss(form_id).get("attack_kind", ""))
		if kind != "":
			return kind
	return "elemental" if SkillDB.is_spell_skill(skill_id) else "physical_melee"


## 前摇光效与释放闪光共用：物理橙、元素蓝
func _skill_flash_color(attack_kind: String) -> Color:
	if attack_kind.begins_with("physical"):
		return Color(1.0, 0.62, 0.32)
	return Color(0.45, 0.7, 1.0)


## 按 MoveDB 的命中形状通用结算 —— 修士随机装的功法不需要逐个写特化代码
func _cast_skill() -> void:
	if _next_skill == "":
		return
	_reset_visual()
	_update_facing_to_target()
	var form_id := SkillDB.get_form_id(_next_skill)
	var form := MoveDB.resolve_boss(form_id)
	if form.is_empty():
		_do_projectile()
		return

	var attack_kind := String(form.get("attack_kind", _pending_skill_kind))
	var element := String(form.get("damage_element", ""))
	var dmg := attack_power * _cast_coeff * _damage_multiplier()
	_play_form(form, dmg, attack_kind, element)
	_skill_cd = randf_range(3.2, 4.8)


## 大陆首领招式：参数来自 SecretWorldDB.CORE_SKILLS，表现仍走 MoveDB 的 form
func _cast_core_skill() -> void:
	var def := _next_core_skill
	if def.is_empty():
		_do_melee()
		return
	_reset_visual()
	_update_facing_to_target()
	var form := MoveDB.resolve_boss(String(def.get("form_id", "")))
	if form.is_empty():
		_do_melee()
		_next_core_skill = {}
		_pending_windup = -1.0
		return

	var attack_kind := String(def.get("attack_kind", form.get("attack_kind", _pending_skill_kind)))
	var element := String(def.get("damage_element", form.get("damage_element", "")))
	var dmg := attack_power * float(def.get("damage_scale", 1.0)) * _damage_multiplier()
	_play_form(form, dmg, attack_kind, element,
		float(def.get("range", -1.0)), float(def.get("angle", -1.0)),
		String(def.get("fx_id", "")))

	var id := String(def.get("id", ""))
	if id != "":
		var cd := float(def.get("cooldown", 5.0))
		if phase == 2:
			cd *= 0.8
		_core_skill_cds[id] = cd
	_last_core_skill = id
	_core_attack_cd = 0.35 if phase == 2 else 0.55
	_next_core_skill = {}
	_pending_windup = -1.0


## 通用招式表现 + 判定；核心首领可覆盖命中距离 / 张角
func _play_form(form: Dictionary, dmg: float, attack_kind: String, element: String,
		range_override: float = -1.0, angle_override: float = -1.0,
		fx_id: String = "") -> void:
	var shape := String(form.get("hit_shape", MoveDB.SHAPE_FAN))
	var rng := float(form.get("range", 160.0))
	if range_override > 0.0:
		rng = range_override
	var angle := float(form.get("angle", 90.0))
	if angle_override > 0.0:
		angle = angle_override
	var visual := String(form.get("visual_id", ""))
	_flash_attack(_skill_flash_color(attack_kind))
	# 判定用的 range / angle 也要喂给特效：古猿的砸地按 CORE_SKILLS 的 190/300 出圈，
	# 不能拿 MoveDB form_smash 默认的 120 —— 否则特效圈比真正挨打的圈小一大截。
	var fx_form := form.duplicate(true)
	fx_form["range"] = rng
	fx_form["angle"] = angle
	# 野修与玩家共用 SkillFx；核心首领用 CORE_SKILLS 的 fx_id（专属形状/配色）
	var visual_handled := false
	if fx_id != "":
		visual_handled = SkillFx.play_at_strike(self, fx_id, fx_form, facing) != null
	else:
		visual_handled = SkillFx.play_form_at_strike(
			self, String(form.get("form_id", "")), fx_form, facing)

	match shape:
		MoveDB.SHAPE_PROJECTILE:
			_cast_projectiles(form, dmg, element, attack_kind, rng, fx_id)
		MoveDB.SHAPE_CIRCLE:
			if not visual_handled:
				_spawn_form_fx(visual, {"radius": rng})
			_hit_circle(rng, dmg, attack_kind, element)
		MoveDB.SHAPE_LINE:
			if not visual_handled:
				_spawn_form_fx(visual, {"rotation": facing.angle(), "radius": rng, "sweep_deg": angle})
			_hit_line(rng, angle, dmg, attack_kind, element)
		MoveDB.SHAPE_RECT:
			if not visual_handled:
				_spawn_form_fx(visual, {"rotation": facing.angle(), "radius": rng})
			_hit_line(rng, 60.0, dmg, attack_kind, element)
		_:
			if not visual_handled:
				_spawn_form_fx(visual, {
					"rotation": facing.angle(),
					"radius": rng,
					"sweep_deg": angle,
				})
			_hit_fan(rng, angle, dmg, attack_kind, element)


func _spawn_form_fx(visual: String, params: Dictionary) -> void:
	if visual == "":
		FxPlayer.spawn(self, "boss_blade_arc", params)
		return
	FxPlayer.spawn(self, visual, params)


func _cast_projectiles(form: Dictionary, dmg: float, _element: String, attack_kind: String,
		range_override: float = -1.0, fx_id: String = "") -> void:
	var count := maxi(1, int(form.get("count", 1)))
	var spread := float(form.get("spread", 0.0))
	var speed := float(form.get("speed", 420.0))
	var range_len := float(form.get("range", 520.0))
	if range_override > 0.0:
		range_len = range_override
	var pk := "elemental" if attack_kind == "elemental" else "physical_projectile"
	var base := facing.angle()
	for i in count:
		var t := 0.0 if count == 1 else float(i) / float(count - 1) - 0.5
		var dir := Vector2.RIGHT.rotated(base + deg_to_rad(spread) * t)
		var proj := _spawn_projectile(pk)
		if proj == null:
			continue
		proj.set("direction", dir)
		proj.set("speed", speed)
		proj.set("damage", dmg)
		proj.set("life_timer", range_len / maxf(speed, 1.0) + 0.2)
		proj.set("source", self)
		if fx_id != "":
			_apply_fx_projectile_visual(proj, fx_id)
		else:
			_apply_skill_projectile_visual(proj, String(form.get("form_id", "")))


## CORE_SKILLS 的投射物外观：直接读 SKILL_FX 条目里的 projectile_*，
## 不走 SkillDB 反查（这些是大陆首领自己的招式，不对应玩家功法）
func _apply_fx_projectile_visual(proj: Node2D, fx_id: String) -> void:
	if not is_instance_valid(proj) or fx_id == "":
		return
	var fx := ArtDB.get_skill_fx(fx_id)
	if fx.is_empty():
		return
	var pv := String(fx.get("projectile_visual", ""))
	if pv != "" and proj.has_method("set_visual_override"):
		proj.call("set_visual_override", pv)
	if bool(fx.get("projectile_align", false)):
		proj.set("align_visual", true)
	var sc := float(fx.get("projectile_scale", 1.0))
	if not is_equal_approx(sc, 1.0) and proj.has_method("set_visual_scale"):
		proj.call("set_visual_scale", sc)


func _hit_circle(radius: float, dmg: float, attack_kind: String, element: String) -> void:
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if global_position.distance_to((u as Node2D).global_position) <= radius:
			deal_damage_to(u, dmg, attack_kind, element)


func _hit_line(length: float, half_angle: float, dmg: float, attack_kind: String, element: String) -> void:
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - global_position
		if to_u.length() > length:
			continue
		if to_u.length() > 0.001:
			var diff := absf(rad_to_deg(wrapf(to_u.angle() - facing.angle(), -PI, PI)))
			if diff > maxf(half_angle, 6.0) * 0.5:
				continue
		deal_damage_to(u, dmg, attack_kind, element)


func _hit_fan(radius: float, angle: float, dmg: float, attack_kind: String, element: String) -> void:
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var to_u: Vector2 = (u as Node2D).global_position - global_position
		if to_u.length() > radius:
			continue
		if to_u.length() > 0.001:
			var diff := absf(rad_to_deg(wrapf(to_u.angle() - facing.angle(), -PI, PI)))
			if diff > angle * 0.5:
				continue
		deal_damage_to(u, dmg, attack_kind, element)


# ===================== 死亡 =====================
## 大世界敌人死亡：不广播 GameState.boss_died（那是关卡的结算信号），
## 只发 world_died 让管理器处理掉落与刷新计时，然后自行消散
func _die() -> void:
	if _died_emitted:
		return
	_died_emitted = true
	_clear_treasure_runtime()
	state = BossState.DEAD
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	for cs in find_children("*", "CollisionShape2D", true, false):
		(cs as CollisionShape2D).set_deferred("disabled", true)
	world_died.emit(self)
	if standalone:
		died.emit(boss_id)
	anim.modulate = Color(0.45, 0.45, 0.45)
	_play_death_animation()
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(self):
		queue_free()


func _name_color() -> Color:
	if _name_tint.a > 0.0:
		return _name_tint
	match enemy_kind:
		KIND_CORE:
			return UIKit.C_GREAT
		KIND_CULTIVATOR:
			return UIKit.C_DMG_SPELL
		_:
			return UIKit.C_TEXT_DIM


func _hp_color() -> Color:
	if _hp_tint.a > 0.0:
		return _hp_tint
	match enemy_kind:
		KIND_CORE:
			return Color(0.95, 0.35, 0.25, 1.0)
		KIND_CULTIVATOR:
			return Color(0.4, 0.65, 1.0, 1.0)
		_:
			return Color(0.9, 0.2, 0.2, 1.0)
