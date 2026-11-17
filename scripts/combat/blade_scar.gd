class_name BladeScar
extends Area2D
## 刀痕 —— 留在地面的持续场地状态，被激活时化为一次**瞬间斩击**
##
## 机制（2026-10-18 用户改定，取代旧的「强化刀痕持续灼烧」）：
##   1. 生成：普通刀痕在场地上留存 **10 秒**，期间只占位限制走位，不造成伤害。
##   2. 激活：被刀气 / 刀域激活的那一刻，刀痕**立刻化为一道斩击**，对覆盖范围内的敌人
##      造成一次伤害（类型跟留痕技能一致：物理留痕＝物理，法术留痕＝法术），然后刀痕立即消失。
##   3. 连携奖励：**同一次激活里激活的刀痕越多，这次斩击的伤害系数越高** ——
##      每多激活一个，全体（本次所有）刀痕的伤害系数 +1。
##      即：激活 1 个 → 系数 1；激活 2 个 → 系数 2；激活 N 个 → 系数 N。
##      所以「先铺满刀痕再一次性激活」是这个流派的核心输出手法。
##   4. 归属方：BOSS 留的痕只伤玩家，玩家留的痕只伤 BOSS —— 双方共用同一套规则，
##      因此玩家学会留痕类功法后也能搭出「留痕 → 激活 → 爆发」的联动。
##
## 美术替换：
##   - 刀痕本体形象走 ArtDB.VISUALS 的 `blade_scar`
##   - 激活瞬间的斩击特效走 ArtDB.EFFECTS 的 `scar_slash`
##   换图只改 art_db.gd，本脚本不动。

## ===== 表现参数（占位期专用，接入正式贴图后可整段删除）=====
## 现在没有贴图，只能靠「亮色块 + 呼吸」让玩家看得见刀痕；
## 换成正式美术（刀痕贴图 / 序列帧）后，把 PULSE 开关关掉即可。
const PULSE_ENABLED := true
const PULSE_SPEED := 2.4      ## 弧度 / 秒
const PULSE_AMOUNT := 0.18    ## modulate.a 的波动幅度

const SIDE_PLAYER := "player"
const SIDE_BOSS := "boss"

## 刀痕在场上的留存时间（秒）—— 用户 2026-10-18 定为 10 秒
const SCAR_LIFE := 10.0

## 归属方：只伤害非归属方
var owner_side: String = SIDE_BOSS
## 留痕者本体（BOSS 或玩家）。棋局里"归属方"不够用 —— 双方 BOSS 的 side 都是
## SIDE_BOSS，只有落到具体单位才分得出队伍。为 null 时退回按组名取敌（老行为）。
var owner_unit: Node = null
## 剩余存活时间
var life: float = SCAR_LIFE
## 视觉/碰撞半径（2026-10-22 用户要求加大刀痕范围：34 → **52**）
## ⚠ 判定与显示都读这一个值：改这里「看起来多大」和「能炸到多远」同步生效，不会脱节。
var scar_radius: float = 52.0

## 伤害来源强度（BOSS 取 attack_power；玩家物理留痕取物攻、法术留痕取法强×法技增伤，
## 留痕时快照；玩家的「日冕持种」全伤害乘区在引爆时另外实时乘）
var damage_power: float = 0.0
## 伤害类型：跟留痕技能一致。物理留痕 → physical（吃物抗）；法术留痕 → elemental（吃法抗）。
## BOSS 的刀痕沿用它的招式口径（当前为 elemental）。
var damage_kind: String = "elemental"
## 留痕者的伤害倍率（友军召唤的刀客 = ally_damage_scale，普通 BOSS = 1.0）
## ⚠ 刀痕激活是直接调 take_damage 的，走不到 BossBase.deal_damage_to()，
##   不乘这个系数的话，友军刀客的刀痕吃不到强化加成（2026-10-21 用户报）
var ally_scale: float = 1.0
## 伤害系数（基础值 1.0；实际系数 = 本值 × 本次激活的刀痕数量）
var damage_coeff: float = 1.0

## 呼吸相位（让灼痕缓慢呼吸，不抢角色与伤害数字）
var _pulse_time: float = 0.0
## 灼痕外溢辉光 + 上升余烬
var _glow: Sprite2D = null
var _embers: CPUParticles2D = null
## 肉鸽「余痕」：这道痕是否已经重生过一次（每道只重生一次，防止无限引爆）
var _rekindled: bool = false

@onready var visual: SkinVisual = $Visual/Skin


func _ready() -> void:
	add_to_group("blade_scar")
	collision_layer = 0
	collision_mask = 3  # 同时监测玩家层(1)与BOSS层(2)
	monitoring = true
	if get_node_or_null("CollisionShape2D") == null:
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = scar_radius
		shape.shape = circle
		add_child(shape)
	# 呼吸相位错开，避免所有刀痕同步闪
	_pulse_time = randf() * 6.0
	_refresh_visual()
	_build_atmosphere()


func _refresh_visual() -> void:
	if visual == null:
		return
	visual.visual_id = "blade_scar"
	visual.fallback_visual_id = "blade_scar"
	visual.refresh()
	# 每道痕的裂口角度略有不同，避免整片场地像复制粘贴
	visual.rotation = randf_range(-0.7, 0.7)


## 灼痕辉光与上升余烬；只是视觉，不参与判定
func _build_atmosphere() -> void:
	_glow = Sprite2D.new()
	_glow.texture = SkillFx.dot_texture()
	_glow.centered = true
	_glow.material = SkillFx.additive_material()
	_glow.modulate = Color(1.0, 0.34, 0.10, 0.20)
	_glow.scale = Vector2(1.05, 1.05)
	_glow.z_index = -1
	add_child(_glow)
	_embers = CPUParticles2D.new()
	_embers.texture = SkillFx.dot_texture()
	_embers.amount = 7
	_embers.lifetime = 1.05
	_embers.lifetime_randomness = 0.35
	_embers.randomness = 0.5
	_embers.local_coords = true
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 26.0
	_embers.direction = Vector2.UP
	_embers.spread = 28.0
	_embers.initial_velocity_min = 3.0
	_embers.initial_velocity_max = 16.0
	_embers.gravity = Vector2(0.0, -9.0)
	_embers.damping_min = 1.0
	_embers.damping_max = 4.0
	_embers.scale_amount_min = 0.035
	_embers.scale_amount_max = 0.085
	_embers.scale_amount_curve = SkillFx.make_curve(
		[Vector2(0.0, 0.3), Vector2(0.25, 1.0), Vector2(1.0, 0.0)])
	_embers.color_ramp = SkillFx.make_gradient(
		PackedFloat32Array([0.0, 0.2, 1.0]),
		PackedColorArray([
			Color(1.0, 0.42, 0.10, 0.0),
			Color(1.0, 0.66, 0.24, 0.55),
			Color(0.8, 0.22, 0.05, 0.0),
		]))
	_embers.material = SkillFx.additive_material()
	_embers.one_shot = false
	_embers.emitting = true
	_embers.z_index = 1
	add_child(_embers)
	_embers.restart()
	_embers.emitting = true


func _physics_process(delta: float) -> void:
	_tick_pulse(delta)

	life -= delta
	if life <= 0.0:
		queue_free()
		return


# ===================== 激活：瞬间斩击 =====================

## 激活本刀痕：立刻对覆盖范围内的敌人造成一次伤害（类型跟留痕技能一致），然后刀痕消失
##
## mult：本次激活的刀痕总数（由 ScarField 统一算好传进来）。
##       伤害 = damage_power × damage_coeff × mult —— 激活得越多，每一道斩击越痛。
## 返回命中数（0 = 范围内没有敌人，刀痕照样消失）。
func slash(mult: int = 1) -> int:
	if mult < 1:
		mult = 1
	var hits := _slash_enemies(mult)
	# 激活瞬间：弧光 + 余烬爆裂（SkillFx 程序化层，刀痕本体随后立刻消失）
	SkillFx.scar_burst(get_parent(), global_position,
		Vector2.RIGHT.rotated(randf_range(0.0, TAU)))
	# 肉鸽「余痕」：首爆后不消失，留半条余时再烧一轮（每道只能重生一次）
	# ⚠ 只对玩家侧生效：BOSS 侧的刀痕重生会让「踩痕」变成无限惩罚
	if owner_side == SIDE_PLAYER and RogueRun.active \
			and RogueRun.has_flag("scar_rekindle") and not _rekindled:
		_rekindled = true
		life = maxf(life * 0.5, 2.0)
		if visual != null:
			visual.modulate.a = 0.72
		return hits
	# 触发过就立刻消失，不留残影
	queue_free()
	return hits


## 对覆盖范围内的敌方单位结算一次伤害（damage_kind 由留痕技能决定）
## ⚠ 用几何判定（距离 ≤ 半径）而不是 get_overlapping_bodies()：
##   激活往往发生在生成刀痕的同一帧或下一帧，物理引擎的重叠关系还没刷新，
##   几何判定与普攻的扇形判定思路一致，结果更可靠。
func _slash_enemies(mult: int) -> int:
	var dmg := maxf(0.0, damage_power * damage_coeff * float(mult) * ally_scale)
	# 日冕持种：玩家所有伤害 +12%/层，刀痕在**引爆时**实时吃（与技能结算同口径）
	if owner_side == SIDE_PLAYER:
		dmg *= CharacterData.sun_damage_mult
		# 肉鸽「连斩」：刀痕斩击伤害 +N%（主模式 stat 恒为 0）
		if RogueRun.active:
			dmg *= 1.0 + RogueRun.stat("scar_mult_pct") / 100.0
			# 肉鸽「孤刃」：这一击只引爆了一处刀痕 → 孤注一击的大倍率
			var lone := RogueRun.stat("scar_lone_mult")
			if lone > 1.0 and mult <= 1:
				dmg *= lone
	if dmg <= 0.0:
		return 0

	var victims := _victim_list()
	if victims.is_empty():
		return 0

	var hits := 0
	for body in victims:
		if not is_instance_valid(body) or not body is Node2D:
			continue
		if not body.has_method("take_damage"):
			continue
		if (body as Node2D).global_position.distance_to(global_position) > scar_radius:
			continue
		# 伤害类型跟留痕技能一致：物理刀痕吃物抗，法术刀痕吃法抗；两者都不可弹刀。
		# ⚠ 签名按**目标类型**分流，不按归属方：棋局里 BOSS 侧刀痕要打的也是棋子，
		#   照老写法按 owner_side 分支就会把 attack_kind(String) 塞进 source(Object)，
		#   正是 `boss_base.gd`「对任意单位结算伤害」那条警告指的同一个崩溃。
		if body.is_in_group("player"):
			body.take_damage(dmg, damage_kind, self)
		else:
			var final_dmg := dmg
			if owner_side == SIDE_PLAYER:
				# 玩家留下的刀痕也是玩家伤害来源：佩戴「负阴抱阳」后同样吃两仪势的逆式 / 引爆印
				var src := get_tree().get_first_node_in_group("player")
				if src != null and src.has_method("_yinyang_modify_damage"):
					# 刀痕是「后续触发」：只吃增伤 / 逆印结算，不叠势、不翻面
					final_dmg = float(src.call("_yinyang_modify_damage", body, damage_kind, dmg, "", false))
				# 肉鸽全局乘区：刀痕不走玩家那条伤害出口，必须在这里单独过一遍
				# （否则「破竹 / 斩弱 / 血刃」对刀修一个都不生效）
				final_dmg = RogueRun.modify_outgoing(final_dmg, body, damage_kind, "scar")
			# 伤害统计：刀痕（持续伤 + 引爆）单独一行
			DamageMeter.push("刀痕")
			body.take_damage(final_dmg, self, damage_kind, "")
		hits += 1
	# 肉鸽「饮痕」：斩击命中就按气血上限回血（没打中不回，避免空挥回血）
	if hits > 0 and owner_side == SIDE_PLAYER and RogueRun.active:
		var heal := RogueRun.stat("scar_heal_pct")
		if heal > 0.0 and is_instance_valid(owner_unit) and owner_unit.has_method("rogue_heal_pct"):
			owner_unit.call("rogue_heal_pct", heal)
	return hits


## 这一刀该劈谁。
## 有归属单位 ⇒ 走 `BossBase.hostile_units()`：棋局里双方都是带 team_id 的 match_piece，
## 老写法按组名 `"player"` 取敌在棋盘上恒空 —— 2026-11-05 实测**刀客的招牌刀痕在棋局里
## 一刀不劈**（不崩，只是静默 0 伤害，所以单打与数值模拟都发现不了）。
## 没有归属单位 ⇒ 沿用旧的组名取敌，保证没传 caster 的调用点与老档行为一字不变。
func _victim_list() -> Array:
	if owner_unit != null and is_instance_valid(owner_unit):
		return BossBase.hostile_units(owner_unit)
	var tree := get_tree()
	if tree == null:
		return []
	return tree.get_nodes_in_group(SIDE_PLAYER if owner_side == SIDE_BOSS else SIDE_BOSS)


## 呼吸脉动（占位期可见性）
## ⚠ 只是为了让「色块占位」在深色地面上够显眼；接入正式刀痕美术后可关掉 PULSE_ENABLED。
## 只改 SkinVisual 的 modulate —— 换贴图后同样生效，且不影响碰撞与判定。
func _tick_pulse(delta: float) -> void:
	if not PULSE_ENABLED or visual == null:
		return
	_pulse_time += delta
	# 末尾随剩余时间渐隐：刀痕要消失了，视觉上就该先淡掉
	var fade := clampf(life / 1.0, 0.0, 1.0)
	visual.modulate.a = (0.78 + sin(_pulse_time * PULSE_SPEED) * PULSE_AMOUNT) * fade
	if _glow != null:
		_glow.modulate.a = (0.16 + sin(_pulse_time * PULSE_SPEED * 0.7) * 0.06) * fade
	if _embers != null:
		_embers.emitting = life > 0.8
