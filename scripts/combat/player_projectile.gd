extends Area2D
## 玩家功法投射物（箭矢 / 法球 / 万剑归宗飞剑）
##
## 与 BOSS 的 boss_projectile.gd 区分开，因为两者对「受伤方的函数签名」不同：
##   - BOSS 投射物命中玩家：player.take_damage(amount, attack_kind, source) —— 3 参
##   - 玩家投射物命中 BOSS：boss.take_damage(amount, source)             —— 2 参
## 硬凑一个类会到处写分支，反而更容易出错，故拆成两个。
##
## 视觉走 SkinVisual（ArtDB.VISUALS 的 visual_id 条目，默认 "player_projectile"），
## 换美术只改 art_db.gd，本脚本不动。
## 万剑归宗的飞剑会把 visual_id 指向 "boss_sword_projectile"（与 BOSS 侧共用飞剑形象）。

## 来源功法 id（用于伤害追溯/调试）
var skill_id: String = ""
## 发射者（玩家）。用于命中 BOSS 前走两仪势结算（逆式 / 势 / 印）
var source: Node = null
## 命中伤害（已由 CharacterData.calc_skill_damage 算好，这里只负责投递）
var damage: float = 0.0
## 伤害类型与五行元素：由受击方据此扣抗性
var damage_kind: String = "physical"
var element: String = ""
var speed: float = 600.0
var max_distance: float = 600.0
var direction: Vector2 = Vector2.RIGHT
## 视觉条目 id（ArtDB.VISUALS 的键）—— 万剑归宗飞剑改指 "boss_sword_projectile"
var visual_id: String = "player_projectile"

var _travelled: float = 0.0

## ===== 被 BOSS 弹回（二阶段刀客的弹刀）=====
## true 时方向已反转、碰撞改为检测玩家层，命中后打玩家而不是 BOSS。
## ⚠ 伤害沿用玩家原本打出的 damage（以其人之道还治其人之身），不再重新计算
var is_deflected: bool = false
## 玩家所在的物理层（player.tscn 根节点默认 layer = 1）
const PLAYER_LAYER := 1

## ===== 弧线追踪（万剑归宗的飞剑用，字段与 boss_projectile.gd 同名同义）=====
## 转向速度（度/秒）：0 = 直线飞行；>0 = 每帧把 direction 朝目标转一点，
## 于是「从身侧斜着放出 → 逐渐拐向目标」，形成弧线而非散射直线。
var turn_speed_deg: float = 0.0
## ⚠ 防绕圈（2026-10-22 用户报「某个站位上万剑归宗绕着目标转圈到消失」）：
##   固定角速度下 **转弯半径 = 速度 / 角速度**（420 / 200°·s ≈ 120px）。
##   目标距离一旦接近这个半径，飞剑就锁进稳定圆轨道，永远咬不住。
##   所以角速度按当前距离自适应放大，保证 转弯半径 < 距离 / ORBIT_GUARD：
##   远处仍是舒展弧线，近处自动收得更紧，轨迹必定向内收敛。
const ORBIT_GUARD := 1.8
## 贴到这么近就直接算命中：既兜住绕圈，也兜住高速下的穿透（一帧位移 > 目标碰撞体）
const HOMING_HIT_RADIUS := 26.0
## 追踪目标（留空 = 不追踪，保持直线）
var homing_target: Node2D = null
## 视觉是否每帧对齐飞行方向（细长剑类需要；球类开了也无害但是白做）
var align_visual: bool = false
## 发射时记下的侧别（-1 左 / +1 右，供验证与调试读取）
var launch_side: float = 0.0

## ===== 侧向正弦摆动（阴阳双鱼的「鱼」）=====
## 沿垂直于飞行方向做简谐横移：两条鱼取反相（0 与 π），轨迹就会在途中互相交叉。
## 平均航线仍压在瞄准线上 —— 看着绕，实际不像散射那样越远越散、容易打空。
var swim_amp: float = 0.0      ## 摆幅（像素）
var swim_freq: float = 0.0     ## 频率（Hz）：飞行 1 秒摆几个完整周期
var swim_phase: float = 0.0    ## 初相（弧度）
var _swim_t: float = 0.0

## 技能投射物的外观众参数（由 ArtDB.SKILL_FX 自动填充；也可由生成方手动覆盖）
var visual_color: Color = Color.WHITE
var visual_scale: float = 1.0
var trail_kind: String = ""
var trail_color: Color = Color(0, 0, 0, 0)

@onready var visual: SkinVisual = $Visual/Skin


func _ready() -> void:
	var sfx := ArtDB.get_skill_fx(skill_id)
	if not sfx.is_empty():
		if visual_id == "player_projectile":
			var pv := String(sfx.get("projectile_visual", ""))
			if pv != "":
				visual_id = pv
		if visual_color == Color.WHITE:
			var c: Color = sfx.get("projectile_color", Color.WHITE)
			visual_color = c
		if is_equal_approx(visual_scale, 1.0):
			visual_scale = float(sfx.get("projectile_scale", 1.0))
		if trail_kind == "":
			trail_kind = String(sfx.get("projectile_trail", ""))
		if trail_color.a <= 0.001:
			var tc: Color = sfx.get("spark", sfx.get("glow", Color.WHITE))
			trail_color = tc
		if bool(sfx.get("projectile_align", false)):
			align_visual = true
	visual.visual_id = visual_id
	visual.refresh()
	if visual_color != Color.WHITE:
		visual.modulate = visual_color
	if not is_equal_approx(visual_scale, 1.0):
		visual.scale *= visual_scale
	# 刀气 / 剑光用加法混合：暗红雾底不会变成黑方块，同时更像能量体
	if visual_id == "skill_blade_qi" or visual_id == "skill_sword_light":
		if visual.render_node is Sprite2D:
			(visual.render_node as Sprite2D).material = SkillFx.additive_material()
	body_entered.connect(_on_body_entered)
	if trail_kind != "":
		_build_trail()


## 投射物拖尾：粒子留在世界坐标，弹体飞走后仍能看到一段尾迹
func _build_trail() -> void:
	var is_material_trail := trail_kind == "smoke" or trail_kind == "sand"
	var tex: Texture2D
	match trail_kind:
		"smoke", "sand":
			tex = SkillFx.smoke_texture()
		"sword", "ember":
			tex = SkillFx.star_texture()
		_:
			tex = SkillFx.dot_texture()
	var glow := Sprite2D.new()
	glow.texture = SkillFx.dot_texture()
	glow.centered = true
	if is_material_trail:
		glow.modulate = Color(trail_color.r, trail_color.g, trail_color.b, 0.14)
	else:
		glow.material = SkillFx.additive_material()
		glow.modulate = Color(trail_color.r, trail_color.g, trail_color.b, 0.34)
	glow.scale = Vector2(1.6, 1.6)
	glow.z_index = -1
	add_child(glow)

	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = 26 if trail_kind == "sword" else 16
	p.lifetime = 0.56 if is_material_trail else (0.30 if trail_kind == "sword" else 0.36)
	p.lifetime_randomness = 0.28
	p.randomness = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 32.0
	p.gravity = Vector2(0.0, 28.0) if is_material_trail else Vector2.ZERO
	p.damping_min = 8.0
	p.damping_max = 28.0
	p.scale_amount_min = 0.16 if is_material_trail else 0.06
	p.scale_amount_max = 0.30 if is_material_trail else 0.14
	p.scale_amount_curve = SkillFx.make_curve(
		[Vector2(0.0, 0.35), Vector2(0.2, 1.0), Vector2(1.0, 0.0)])
	p.color_ramp = SkillFx.make_gradient(
		PackedFloat32Array([0.0, 0.12, 0.7, 1.0]),
		PackedColorArray([
			Color(trail_color.r, trail_color.g, trail_color.b, 0.0),
			Color(trail_color.r, trail_color.g, trail_color.b, 0.45 if is_material_trail else 0.85),
			Color(trail_color.r, trail_color.g, trail_color.b, 0.22),
			Color(trail_color.r, trail_color.g, trail_color.b, 0.0),
		]))
	p.z_index = -1
	p.one_shot = false
	p.emitting = true
	if not is_material_trail:
		p.material = SkillFx.additive_material()
	add_child(p)
	p.restart()
	p.emitting = true


func _physics_process(delta: float) -> void:
	# 弧线追踪：每帧朝目标方向转一点（转角受 turn_speed_deg 限制，转太快的「折线」不好看）
	if turn_speed_deg > 0.0 and homing_target != null and is_instance_valid(homing_target) \
			and not is_deflected:
		var to_target: Vector2 = homing_target.global_position - global_position
		var dist := to_target.length()
		# 贴脸兜底：绕圈/穿透都能在这里结算掉，不靠物理碰撞
		if dist <= HOMING_HIT_RADIUS:
			_hit_target(homing_target)
			return
		var desired: Vector2 = to_target / maxf(dist, 0.0001)
		var cur: float = direction.angle()
		var diff: float = wrapf(desired.angle() - cur, -PI, PI)
		# 距离越近 → 允许的角速度越大（转弯半径必须小于当前距离，否则就会绕圈）
		var omega := maxf(deg_to_rad(turn_speed_deg), ORBIT_GUARD * speed / maxf(dist, 1.0))
		var turn_step: float = omega * delta
		direction = Vector2.RIGHT.rotated(cur + clampf(diff, -turn_step, turn_step))
	# 视觉对齐：细长剑必须每帧跟着转向，否则「剑身横着飞」
	# ⚠ 修正量是 **-PI/2**：剑图统一为「竖直、刃尖朝下」（+Y = 90°），
	#   减去 90° 才能让刃尖指向 direction（早前写成 +PI/2，实剑贴图接入后剑尖朝反方向）
	if align_visual and is_instance_valid(visual):
		visual.rotation = direction.angle() - PI * 0.5
	var step := speed * delta
	global_position += direction * step
	_travelled += step
	if swim_amp > 0.0 and swim_freq > 0.0:
		# 横移按速度积分（amp·ω·cos），合成轨迹就是标准正弦；
		# 本体朝向跟着合速度偏一点，看着才是「斜着游」而不是平移的圆片
		_swim_t += delta
		var w := TAU * swim_freq
		var lateral := direction.orthogonal() * (swim_amp * w * cos(w * _swim_t + swim_phase))
		global_position += lateral * delta
		if not align_visual:
			rotation = (direction * speed + lateral).angle()
	if _travelled >= max_distance:
		queue_free()


## 被 BOSS 弹回：反向飞向玩家，改为攻击玩家（刀客二阶段的弹刀调用）
## new_dir       一般传「BOSS → 玩家」的方向
## damage_mult   弹回后的伤害倍率（刀客传 0.3，避免"玩家被自己一发秒掉"）
## ⚠ 必须清掉追踪：万剑归宗的飞剑 homing_target 仍指向 BOSS，
##   不清的话弹回去会自己拐回 BOSS，变成"弹了个寂寞"
func deflect(new_dir: Vector2, damage_mult: float = 1.0) -> void:
	if is_deflected:
		return
	is_deflected = true
	if new_dir.length_squared() > 0.0001:
		direction = new_dir.normalized()
	speed *= 1.35            # 弹回加速，气势更足
	collision_mask = PLAYER_LAYER   # 改检测玩家层，不再撞 BOSS
	homing_target = null
	turn_speed_deg = 0.0
	damage *= maxf(0.0, damage_mult)
	# 视觉：金色提亮 + 略微放大（和弹反的金光呼应）
	if is_instance_valid(visual):
		visual.modulate = Color(1.0, 0.88, 0.45)
		visual.scale = visual.scale * 1.15


## 命中 BOSS：BossBase.take_damage(amount, source, damage_kind, element, from_projectile)
## ⚠ 最后一个参数必须传 true：受击方要靠它区分「远程投射物」与近战/法术，
##   刀客二阶段会据此把玩家的物理远程必定弹开（见 domain_boss_01.try_parry_player_projectile）
func _on_body_entered(body: Node) -> void:
	# 被弹回的投射物：反过来打玩家
	if is_deflected:
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage, "physical_projectile", self)
			GameState.trigger_hit_stop()
			GameState.play_sfx("player_hit")
			queue_free()
		return
	if not body.has_method("take_damage"):
		return
	_hit_target(body)


## 结算命中：物理碰撞（_on_body_entered）与「贴脸兜底」（追踪时距离过近）共用同一条
## ⚠ 最后那个 true 必须传：受击方靠它区分「远程投射物」与近战/法术，
##   刀客二阶段据此把玩家的物理远程必定弹开（domain_boss_01.try_parry_player_projectile）
func _hit_target(body: Node) -> void:
	if is_deflected or not is_instance_valid(body) or not body.has_method("take_damage"):
		return
	# 两仪势：投射物命中 BOSS 也要走同一套逆式 / 势 / 印结算
	if body.is_in_group("boss") and source != null and is_instance_valid(source) \
			and source.has_method("_yinyang_modify_damage"):
		damage = float(source.call("_yinyang_modify_damage", body, damage_kind, damage, skill_id))
		# 肉鸽爬塔的伤害乘区（主模式原样返回）
		if source.has_method("_rogue_modify_damage"):
			damage = float(source.call("_rogue_modify_damage", damage, body, damage_kind, skill_id))
	# 伤害统计：玩家投射物按它携带的功法归属（没带就记「飞剑」）
	DamageMeter.push("飞剑" if skill_id == "" else SkillDB.get_skill_name(skill_id))
	body.take_damage(damage, self, damage_kind, element, true)
	# 肉鸽「命中附加」（虎妖·迷眼）：投射物不走 player 的近战结算，
	# 所以这里单独补一次；主模式该函数是空操作
	if source != null and is_instance_valid(source) \
			and source.has_method("_rogue_apply_hit_debuff"):
		source.call("_rogue_apply_hit_debuff", body, skill_id)
	if source != null and is_instance_valid(source) \
			and source.has_method("notify_calamity_element_hit"):
		source.call("notify_calamity_element_hit", body, element, skill_id)
	# ⚠ 被刀客弹回时 take_damage 内部会调 deflect() 把 is_deflected 置 true，
	#   这时**不能销毁**——投射物要掉头飞回去打玩家
	if is_deflected:
		return
	GameState.trigger_hit_stop()
	GameState.play_sfx("attack_hit")
	var impact_color := trail_color if trail_color.a > 0.0 else Color(0.8, 0.95, 1.0)
	SkillFx.projectile_impact(get_parent(), global_position, impact_color)
	queue_free()
