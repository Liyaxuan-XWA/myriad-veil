extends BossBase

## 虎妖是**兽型**，体量本来就大：1.25 倍像充气，而且会盖过骨骼招式本身的动作。
## 收到 1.12 —— 保留「蓄力鼓起」的可读性，但把注意力让给招式。
func windup_pulse_scale() -> float:
	return 1.12


## 虎妖二阶段只小幅加伤：2.0 倍对练气期玩家过高（用户 2026-10-31 定），改为 1.5。
func _damage_multiplier() -> float:
	return 1.5 if phase == 2 else 1.0


## 原型 BOSS（阶段1：仅用于验证战斗机制，非正式 BOSS 设定）
## 特有机制：
## - 基础招式组：近战横扫（120°扇形）+ 物理投掷 + 元素法球
## - 距离驱动选招（到本体边缘 90px 内近战 / 320px 内远程）
## - 后撤步技能：连续 2 次近战触发，70% 概率递增
## - 突进 + 砸地技能：连续 2 次远程触发，70% 概率递增
## - 二阶段强化：三连砸地 + 5 发投掷 + 大法球
## 共有机制（双阶段、无预警、弹刀规则等）由 BossBase 提供。

# ===== 特有状态（从 100 起避免与基类冲突） =====
enum ProtoState { DASH_BACK = 100, DASH_FORWARD, SMASH }

# ===== 攻击判定参数（运行时可变，供调试面板调整） =====
@export var MELEE_RANGE := 110.0
@export var MELEE_SWEEP_ANGLE := 120.0
@export var MELEE_DAMAGE := 15.0
@export var PROJECTILE_SPEED := 520.0
@export var ELEMENTAL_SPEED := 338.0
@export var PROJECTILE_DAMAGE := 12.0
@export var ELEMENTAL_DAMAGE := 18.0

# ===== 攻击距离阈值 =====
## 判定口径：**到本体边缘**的距离（0 = 贴着），不是中心距离。
## 虎妖物理胶囊贴住立绘（x ±135 / y −147…−3，本体厚度半径 72），
## 按中心距离算的话贴着脸也有 130+，刚好掉进「远程」那一档
## （2026-10-27 用户报「贴近 boss 也放远程」）。
@export var MELEE_DISTANCE := 90.0
@export var RANGED_DISTANCE := 320.0

# ===== 元素技能冷却（二阶段高阶技能） =====
var elemental_cooldown: float = 0.0
@export var ELEMENTAL_COOLDOWN_TIME := 4.0

# ===== 后撤步技能 =====
@export var MELEE_COMBO_TRIGGER := 2
@export var DASH_BACK_BASE_CHANCE := 0.7
@export var DASH_BACK_CHANCE_STEP := 0.1
@export var DASH_BACK_SPEED := 900.0
@export var DASH_BACK_TIME := 0.18
@export var DASH_BACK_TIME_P2 := 0.32
@export var DASH_BACK_BURST_COUNT_P2 := 5
@export var DASH_BACK_BURST_SPEED := 650.0
var melee_attack_count: int = 0
var dash_back_chance: float = DASH_BACK_BASE_CHANCE
var dash_back_dir: Vector2 = Vector2.ZERO
var _dash_back_ready: bool = false

# ===== 突进 + 砸地技能 =====
@export var RANGED_COMBO_TRIGGER := 2
@export var DASH_FORWARD_BASE_CHANCE := 0.7
@export var DASH_FORWARD_CHANCE_STEP := 0.1
@export var DASH_FORWARD_SPEED := 800.0
@export var DASH_FORWARD_MAX_TIME := 0.6
@export var SMASH_RANGE := 120.0
@export var SMASH_RANGE_STEP := 40.0
@export var SMASH_DAMAGE := 25.0
@export var SMASH_WINDUP_TIME := 0.35
@export var SMASH_COUNT_P2 := 3

# ===== 技能名（前摇飘字用；改名字只改这里，别在 _do_attack 里散着写） =====
const NAME_MELEE := "虎爪裂空"
const NAME_PROJECTILE := "碎岩飞砂"
const NAME_ELEMENTAL := "虎煞妖丹"
const NAME_SMASH := "猛虎踏地"
var smash_count: int = 0
var smash_total: int = 1
var ranged_attack_count: int = 0
var dash_forward_chance: float = DASH_FORWARD_BASE_CHANCE
var dash_forward_dir: Vector2 = Vector2.ZERO
var dash_forward_dist: float = 0.0
var _dash_forward_ready: bool = false


## 冷却计时（覆写基类钩子）
func _tick_cooldowns(delta: float) -> void:
	if elemental_cooldown > 0.0:
		elemental_cooldown -= delta


## 特有状态判断
func _is_extra_state(s: int) -> bool:
	return s == ProtoState.DASH_BACK or s == ProtoState.DASH_FORWARD or s == ProtoState.SMASH


## 特有状态处理
func _tick_extra_state(delta: float) -> void:
	match state:
		ProtoState.DASH_BACK:
			_dash_back_step(delta)
		ProtoState.DASH_FORWARD:
			_dash_forward_step(delta)
		ProtoState.SMASH:
			_smash_step(delta)


## 特有技能触发判断（后撤优先，其次突进）
func _should_trigger_special() -> bool:
	if _should_dash_forward():
		_start_dash_forward()
		return true
	if _should_dash_back():
		_start_dash_back()
		return true
	return false


func _trigger_special() -> void:
	pass


## 停步距离按**本体边缘**算：基类的追逐到 RANGED_STOP_DISTANCE 就停下并立刻选招，
## 停得比近战起手距离还远 → 永远停在远程档。所以停步点 = 本体半径 + 近战起手距离。
## 再乘 0.9：正好停在阈值上时浮点误差会让 gap 差一丝就掉回远程档。
func _setup() -> void:
	RANGED_STOP_DISTANCE = body_radius() + MELEE_DISTANCE * 0.9


## 到本体边缘的距离（贴着 = 0）。选招与命中一律走这个口径，见 `BossBase.edge_distance_to`。
func _edge_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return 99999.0
	return edge_distance_to((target as Node2D).global_position)


## 受击球投影到脚底平面。
## 物理胶囊贴着虎身（本地 y −147…−3），但玩家攻击的扇形夹角必须按**地面方向**算：
## 球心留在 y=−75 时，贴脸水平砍会被算成斜上方而漏打（2026-10-26 踩过）。
## 物理碰撞仍用场景里的胶囊，只有距离/夹角判定走这份地面投影。
func hit_spheres() -> Array:
	var out: Array = super.hit_spheres()
	for i in range(out.size()):
		var sv: Vector3 = out[i]
		out[i] = Vector3(sv.x, 0.0, sv.z)
	return out


## 追逐到达距离后的选招
func _on_chase_reached(_dist: float) -> void:
	var gap := _edge_to_target()
	if gap <= MELEE_DISTANCE:
		_begin_attack(AttackKind.PHYSICAL_MELEE)
	elif gap <= RANGED_DISTANCE:
		_begin_attack(_pick_attack_kind_by_distance())


## 选择下一步动作（距离驱动）
func _choose_next_action() -> void:
	var gap := _edge_to_target()
	if gap <= MELEE_DISTANCE:
		_begin_attack(AttackKind.PHYSICAL_MELEE)
	elif gap <= RANGED_DISTANCE:
		_begin_attack(_pick_attack_kind_by_distance())
	else:
		state = BossState.CHASE


## 距离选招：近战范围内近战，否则远程（物理/元素随机）
func _pick_attack_kind_by_distance() -> int:
	if _edge_to_target() <= MELEE_DISTANCE:
		return AttackKind.PHYSICAL_MELEE
	var allow_elemental := phase == 2 and elemental_cooldown <= 0.0
	if allow_elemental and randf() < 0.5:
		return AttackKind.ELEMENTAL
	return AttackKind.PHYSICAL_PROJECTILE


## 攻击类型 → 招式形态 id（与 ArtDB.BOSS_MOVE_ANIMS 的键一致）
## ⚠ 这是虎妖出招时**唯一**决定播哪套骨骼动画的地方。原型 BOSS 原先完全没接动画，
##   实战里只有 _show_windup 的整体缩放，看起来就是「骨骼根本没动、只有放大缩小」。
const FORM_OF_KIND := {
	AttackKind.PHYSICAL_MELEE: "form_slash_single",
	AttackKind.PHYSICAL_PROJECTILE: "form_arrow",
	AttackKind.ELEMENTAL: "form_element_orb",
}


## 播这一招的骨骼动作。
## 时长 = 前摇全时长：动画的最后一帧正好落在伤害判定那一帧（与刀客同一口径）。
## ⚠ 骨骼招式的 length 就该等于前摇（横扫 0.80 = P1 的 0.8），这样 speed_scale = 1，
##   时间是 1:1 的；压进更短的时长会让「定格」这段被吃掉，打击感立刻变软。
##   前摇 P1 0.8 / P2 0.55 秒，二阶段同一套动画会被加速 1.45 倍 —— 这是有意的。
func _play_kind_anim(kind: int) -> void:
	var form := String(FORM_OF_KIND.get(kind, ""))
	if form == "":
		return
	_play_form_anim(form, maxf(_windup_time(), 0.20))


## 蓄力动作表现（三种攻击区分颜色）
func _on_attack_windup(kind: int) -> void:
	match kind:
		AttackKind.PHYSICAL_MELEE:
			_show_windup(Color(1.0, 0.45, 0.3))
		AttackKind.PHYSICAL_PROJECTILE:
			_show_windup(Color(0.85, 0.9, 0.2))
		AttackKind.ELEMENTAL:
			_show_windup(Color(0.35, 0.65, 1.0))
			elemental_cooldown = ELEMENTAL_COOLDOWN_TIME
	# 动作与蓄力同时开始（与刀客 domain_boss_01 同一口径）
	_play_kind_anim(kind)


## 前摇飘字：通用 AttackKind → 技能名
## （技能名已由前摇统一飘出，_do_attack 里不再重复显示）
func _attack_kind_skill_name(kind: int) -> String:
	match kind:
		AttackKind.PHYSICAL_MELEE:
			return NAME_MELEE
		AttackKind.PHYSICAL_PROJECTILE:
			return NAME_PROJECTILE
		AttackKind.ELEMENTAL:
			return NAME_ELEMENTAL
	return ""


## 实际执行攻击（含连击计数）
func _do_attack(kind: int) -> void:
	match kind:
		AttackKind.PHYSICAL_MELEE:
			ranged_attack_count = 0
			_on_melee_attack_fired()
			_do_melee()
		AttackKind.PHYSICAL_PROJECTILE:
			melee_attack_count = 0
			_on_ranged_attack_fired()
			_do_projectile()
		AttackKind.ELEMENTAL:
			# 元素弹 = 吐出凝着虎煞之气的妖丹（skill_db: skill_tiger_orb）
			melee_attack_count = 0
			_on_ranged_attack_fired()
			_do_elemental()


# ===== 近战横扫 =====
func _do_melee() -> void:
	_reset_visual()
	_flash_attack(Color(1.0, 0.3, 0.3))
	_spawn_sweep_visual()
	if target:
		_hit_units_in_sweep(MELEE_DAMAGE * _damage_multiplier())


func _spawn_sweep_visual() -> void:
	# 与玩家虎爪共用 SkillFx；范围 / 张角取虎妖本体的实际判定值
	# ⚠ 半径 = 本体半径 + 射程：从身体中心直接画 MELEE_RANGE 的话，爪光整个埋在自己身体里
	#   （兽型本体厚度半径 72、射程 110），读起来就是「虎爪效果太小」（2026-10-27 用户报）。
	var form := MoveDB.resolve_boss("form_slash_single")
	form["hit_shape"] = MoveDB.SHAPE_FAN
	form["range"] = body_radius() + MELEE_RANGE
	form["angle"] = MELEE_SWEEP_ANGLE
	SkillFx.play_form_at_strike(self, "form_slash_single", form, facing)


## 横扫判定：命中该打的**所有**单位（敌方虎妖打玩家+友军；被召唤的友军虎妖只打敌方 BOSS）
## 每个单位各自算距离与夹角；距离从**本体边缘**量（与爪光半径同一口径）
func _hit_units_in_sweep(damage: float) -> bool:
	var hit := false
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		var p: Vector2 = (u as Node2D).global_position
		if edge_distance_to(p) > MELEE_RANGE:
			continue
		var to_u: Vector2 = p - global_position
		var dist: float = to_u.length()
		if dist >= 0.001:
			var angle_diff := absf(rad_to_deg(to_u.angle() - facing.angle()))
			while angle_diff > 180.0:
				angle_diff -= 360.0
			if absf(angle_diff) > MELEE_SWEEP_ANGLE / 2.0:
				continue
		var before := unit_hp(u)
		if not deal_damage_to(u, damage, "physical_melee"):
			continue
		var after := unit_hp(u)
		if before < 0.0 or after < 0.0 or after < before:
			hit = true
	return hit


# ===== 远程攻击 =====
## 弹道方向：从**出生点**指向目标，不要直接抄 facing。
## ⚠ 嘴 / 爪锚点离身体中心一百多像素（虎妖口部 +126,−74）。照 facing 平射等于把整条
##   弹道平移过去，近距离必打偏（实测沿 facing 射会偏 74px，直接从虎头旁边擦过去）。
func _do_projectile() -> void:
	_reset_visual()
	_flash_attack(Color(1.0, 0.7, 0.2))
	_update_facing_to_target()
	# 掷石：石块从**前爪**甩出去（骨骼锚点，见 boss_rig_data 的 muzzle 表）
	var muzzle := muzzle_position("form_arrow")
	SkillFx.play_form_at_strike(self, "form_arrow", MoveDB.resolve_boss("form_arrow"),
		facing, muzzle)
	var proj := _spawn_projectile("physical_projectile", muzzle)
	if proj:
		_apply_skill_projectile_visual(proj, "form_arrow")
		proj.direction = _aim_from(muzzle)
		proj.speed = PROJECTILE_SPEED
		proj.damage = PROJECTILE_DAMAGE * _damage_multiplier()
		proj.source = self


func _do_elemental() -> void:
	_reset_visual()
	_flash_attack(Color(0.4, 0.6, 1.0))
	_update_facing_to_target()
	# 吐妖丹：妖丹从**口中**喷出（骨骼锚定在 head 上，甩头时跟着走）
	var muzzle := muzzle_position("form_element_orb")
	SkillFx.play_form_at_strike(self, "form_element_orb",
		MoveDB.resolve_boss("form_element_orb"), facing, muzzle)
	var proj := _spawn_projectile("elemental", muzzle)
	if proj:
		_apply_skill_projectile_visual(proj, "form_element_orb")
		proj.direction = _aim_from(muzzle)
		proj.speed = ELEMENTAL_SPEED
		proj.damage = ELEMENTAL_DAMAGE * _damage_multiplier()
		proj.source = self
		proj.set_visual_scale(1.8 if phase == 2 else 1.0)


# ===== 后撤步技能 =====
func _should_dash_back() -> bool:
	if not _dash_back_ready:
		return false
	_dash_back_ready = false
	return true


## 当前阶段的后撤时长（P2 撤得更远）—— 起手算位移距离与状态计时共用，避免两处各写一遍
func _dash_back_time() -> float:
	return DASH_BACK_TIME_P2 if phase == 2 else DASH_BACK_TIME


## 后撤落点处「本体边缘到玩家」的距离（起手时算，需要先定 dash_back_dir）。
## 后撤被墙卡成 ZERO 时落点 = 当前位置 —— 贴身时返回 0。
## ⚠ 不能用「当前边缘距离 − 后撤距离」近似：沿墙切向滑开时位移与连线不共线，
##   近似会把正常的「滑开 → 砂石乱舞」误判成贴身；这里把 hit_spheres 整体
##   平移到落点，按真实几何算（与 edge_distance_to 同一口径）。
func _dash_back_landing_gap() -> float:
	if target == null or not is_instance_valid(target):
		return 99999.0
	var landing := global_position + dash_back_dir * DASH_BACK_SPEED * _dash_back_time()
	var target_pos := (target as Node2D).global_position
	var best := INF
	for sp in hit_spheres():
		var sv: Vector3 = sp
		var c := landing + Vector2(sv.x, sv.y)
		best = minf(best, maxf(0.0, target_pos.distance_to(c) - sv.z))
	return 0.0 if best == INF else best


func _start_dash_back() -> void:
	if not target:
		return
	# 重伤等 debuff 封掉「闪避类位移」→ 后撤步跳不了，改成原地先甩一发砂石
	# （2026-10-23：玩家召唤的刀客用沉步竖斩打中虎妖时也会触发这条）
	if is_dodge_blocked():
		dash_back_chance = DASH_BACK_BASE_CHANCE
		_begin_attack(AttackKind.PHYSICAL_PROJECTILE)
		return
	dash_back_dir = (global_position - target.global_position).normalized()
	# ⚠ 地图边缘防呆（2026-10-23 用户报「虎妖在地图边缘后闪会闪出边界」）：
	#   后闪是**朝玩家反方向**冲 900 像素/秒，玩家贴在墙边打时它会被推出地图外。
	#   BOSS 的 mask 不含边界墙层，物理上拦不住，所以起手就把方向修正成**沿边界切向**；
	#   站在角落里两个方向都顶墙时返回 ZERO → 原地后撤（不影响后摇结束的砂石）。
	dash_back_dir = clamp_burst_dir(dash_back_dir, DASH_BACK_SPEED * _dash_back_time())
	# ⚠ 墙边/角落（2026-11-11 用户报「近距离（墙边）会秒放砂石乱舞」）：
	#   后撤就是砂石乱舞（P2）/ 碎岩飞砂（P1）的**前摇位移**。被墙卡住退不动时，
	#   0.2~0.3 秒后照放弹幕 = 贴脸 + 零位移，玩家没有距离可读，体感就是「秒放」。
	#   落点仍在近战距离内 → 这次后撤作废，改爪击（既有设计：贴身只放爪击）。
	if _dash_back_landing_gap() <= MELEE_DISTANCE:
		melee_attack_count = 0
		dash_back_chance = DASH_BACK_BASE_CHANCE
		_begin_attack(AttackKind.PHYSICAL_MELEE)
		return
	state = ProtoState.DASH_BACK
	state_timer = _dash_back_time()
	# 二阶段后撤结束会接「砂石乱舞」：名字在前摇（后撤）第一帧就飘出，不再等到出手
	if phase == 2:
		show_skill_name_at_windup("砂石乱舞", _dash_back_time(),
			BossBase.skill_name_color("physical_projectile"))
	melee_attack_count = 0
	dash_back_chance = DASH_BACK_BASE_CHANCE
	_flash_attack(Color(1.0, 0.9, 0.4))


func _dash_back_step(delta: float) -> void:
	velocity = dash_back_dir * DASH_BACK_SPEED
	state_timer -= delta
	if state_timer <= 0.0:
		velocity = Vector2.ZERO
		_update_facing_to_target()
		# 兜底：后撤途中玩家追到落点旁，结束时仍贴身 → 同样别贴脸放弹幕
		if _edge_to_target() <= MELEE_DISTANCE:
			_begin_attack(AttackKind.PHYSICAL_MELEE)
		elif phase == 2:
			_fire_burst_projectiles()
		else:
			_begin_attack(AttackKind.PHYSICAL_PROJECTILE)


func _fire_burst_projectiles() -> void:
	# 扇形散出的多发砂石 = skill_db 的「砂石乱舞」（form_arrow_volley）
	_update_facing_to_target()
	# 砂石是前爪刨起来甩出去的 → 出生点锚在前爪上
	var muzzle := muzzle_position("form_arrow_volley")
	SkillFx.play_form_at_strike(self, "form_arrow_volley",
		MoveDB.resolve_boss("form_arrow_volley"), facing, muzzle)
	var base_angle := _aim_from(muzzle).angle()
	var spread := deg_to_rad(80.0)
	var count := DASH_BACK_BURST_COUNT_P2
	for i in range(count):
		var t := 0.0 if count == 1 else float(i) / float(count - 1)
		var angle := base_angle - spread / 2.0 + spread * t
		var dir := Vector2.RIGHT.rotated(angle)
		var proj := _spawn_projectile("physical_projectile", muzzle)
		if proj:
			_apply_skill_projectile_visual(proj, "form_arrow_volley")
			proj.direction = dir
			proj.speed = DASH_BACK_BURST_SPEED
			proj.damage = PROJECTILE_DAMAGE * _damage_multiplier()
			proj.source = self
	state = BossState.RECOVER
	state_timer = _recover_time()


# ===== 突进 + 砸地技能 =====
func _should_dash_forward() -> bool:
	if not _dash_forward_ready:
		return false
	_dash_forward_ready = false
	return true


func _start_dash_forward() -> void:
	if not target:
		return
	dash_forward_dir = (target.global_position - global_position).normalized()
	dash_forward_dist = global_position.distance_to(target.global_position)
	state = ProtoState.DASH_FORWARD
	state_timer = DASH_FORWARD_MAX_TIME
	ranged_attack_count = 0
	dash_forward_chance = DASH_FORWARD_BASE_CHANCE
	_flash_attack(Color(1.0, 0.2, 0.2))


func _dash_forward_step(delta: float) -> void:
	velocity = dash_forward_dir * DASH_FORWARD_SPEED
	state_timer -= delta
	var step_dist := DASH_FORWARD_SPEED * delta
	dash_forward_dist -= step_dist

	var reached_player := false
	if target:
		reached_player = global_position.distance_to(target.global_position) <= 40.0

	if dash_forward_dist <= 0.0 or state_timer <= 0.0 or reached_player:
		velocity = Vector2.ZERO
		_start_smash()


func _start_smash() -> void:
	state = ProtoState.SMASH
	state_timer = SMASH_WINDUP_TIME
	smash_count = 0
	smash_total = SMASH_COUNT_P2 if phase == 2 else 1
	# 技能名在**前摇的这一瞬间**飘出，并一直挂到第一次踏地（hold = 前摇时长）
	# 砸地是物理招式 → 黄字（用户 2026-10-20 定：物理黄 / 法术蓝）
	show_skill_name_at_windup(NAME_SMASH, SMASH_WINDUP_TIME, BossBase.skill_name_color("physical_melee"))
	# 踏地：前摇极短（0.35s），动作压进「前摇 × 1.25」——抬身 + 砸下要在判定前落地
	_play_form_anim("form_smash", SMASH_WINDUP_TIME * 1.25)
	var tween := create_tween()
	tween.tween_property(anim, "scale", Vector2(1.4, 1.4), SMASH_WINDUP_TIME)
	anim.modulate = Color(1.0, 0.6, 0.2)


func _smash_step(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		_do_smash_damage()
		smash_count += 1
		if smash_count < smash_total:
			state_timer = SMASH_WINDUP_TIME * 0.7
			var tween := create_tween()
			tween.tween_property(anim, "scale", Vector2(1.4, 1.4), state_timer)
			anim.modulate = Color(1.0, 0.6, 0.2)
		else:
			_reset_visual()
			state = BossState.RECOVER
			state_timer = _recover_time()


func _do_smash_damage() -> void:
	# 技能名已在前摇（_start_smash）飘出，这里不再重复显示
	var current_range: float = SMASH_RANGE
	if phase == 2:
		current_range = SMASH_RANGE + smash_count * SMASH_RANGE_STEP
	# 震波从本体边缘往外扩：半径 120 的圈连自己的爪子都盖不住（本体厚度半径 72），
	# 所以可见圈 = 本体半径 + 射程；判定同样按边缘距离，两者一致
	_spawn_smash_visual(body_radius() + current_range)
	# 砸地是圆形范围：对该范围内的所有单位结算（含玩家召唤的友军）
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if edge_distance_to((u as Node2D).global_position) <= current_range:
			deal_damage_to(u, SMASH_DAMAGE * _damage_multiplier(), "physical_melee")


## 踏地冲击范围 —— 与 move_db 的砸地形态共用 ArtDB "smash_burst" 条目
## （原来这里手画了一份 ColorRect，与 domain_boss 的播放路径重复，故合并）
func _spawn_smash_visual(smash_radius: float = SMASH_RANGE) -> void:
	# 与玩家猛虎踏地共用 SkillFx；范围取虎妖本次实际砸地半径
	var form := MoveDB.resolve_boss("form_smash")
	form["range"] = smash_radius
	SkillFx.play_form_at_strike(self, "form_smash", form, facing)


# ===== 连击计数（触发后撤/突进） =====
func _on_melee_attack_fired() -> void:
	melee_attack_count += 1
	if melee_attack_count >= MELEE_COMBO_TRIGGER:
		if randf() < dash_back_chance:
			_dash_back_ready = true
			melee_attack_count = 0
		else:
			dash_back_chance = minf(1.0, dash_back_chance + DASH_BACK_CHANCE_STEP)
			melee_attack_count = MELEE_COMBO_TRIGGER - 1


func _on_ranged_attack_fired() -> void:
	ranged_attack_count += 1
	if ranged_attack_count >= RANGED_COMBO_TRIGGER:
		if randf() < dash_forward_chance:
			_dash_forward_ready = true
			ranged_attack_count = 0
		else:
			dash_forward_chance = minf(1.0, dash_forward_chance + DASH_FORWARD_CHANCE_STEP)
			ranged_attack_count = RANGED_COMBO_TRIGGER - 1
