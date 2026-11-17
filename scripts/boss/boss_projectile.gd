extends Area2D
## BOSS投掷物 / 元素法球
## 依据任务书 2.13.1：物理投掷可弹刀，元素法球不可弹刀

var direction: Vector2 = Vector2.DOWN
var speed: float = 260.0
var damage: float = 10.0
var attack_kind: String = "physical_projectile"

## 发射者阵营（**在 setter 里发射时记下**）
## ⚠ 召唤物到时消散（queue_free）后，它射出的投射物还在飞，此时 source 是**已释放实例**，
##   命中判定里绝不能再读它（对 freed 对象用 `is` / 读属性会报
##   "previously freed instance"，2026-10-21 用户报的「召唤后闪退」就是这里）。
##   所以阵营在赋值 source 的那一刻抄写成 bool，之后只读这个标志。
var source_is_ally: bool = false
## 发射者的**队伍号**（同样在发射时抄写，理由与 source_is_ally 一致：source 可能已释放）。
## -1 = 不参与对局（现有全部玩法）。>=0 = 卡片自走棋的棋子。
## 没有这个快照的话，两只棋子都是 `is_ally == false`，
## 命中判定里 `source_is_ally == target.is_ally` 恒为真 → 远程永远不结算伤害。
var source_team: int = -1
## 发射者的伤害倍率（**发射时记下**，理由同 source_is_ally：消散后 source 不能碰）
## ⚠ 友军召唤物的伤害倍率 `ally_damage_scale` 原本只在 `deal_damage_to()` 里生效，
##   投射物是**直接调 take_damage** 的，走不到那里 → 召唤物的远程技能吃不到加成
##   （2026-10-21 用户报「有些技能还没享受到伤害增加」）。这里补上。
var ally_scale: float = 1.0
var source: Node = null:
	set(v):
		source = v
		# 先判有效性再 `is`：顺序反了对 freed 实例照样报错
		source_is_ally = is_instance_valid(v) and v is BossBase and bool((v as BossBase).is_ally)
		source_team = BossBase.unit_team(v) if is_instance_valid(v) else -1
		# 对局棋子的弹体必须能物理碰到棋子。`_spawn_projectile` 给敌方写的 mask 是
		# 玩家(1) | 友军召唤物(16) | 阵旗(256)，**不含棋子所在的 BOSS 层 2** →
		# 弹体从对手身上直接穿过去，就是用户报的「远程打不中人」。
		# 放在 setter 而不是 _ready：`source` 是各调用方在 add_child **之后**才赋的，
		# _ready 跑的时候这里还是 -1，修了也来不及。
		if source_team >= 0:
			collision_mask |= BossBase.BOSS_LAYER

## 命中玩家且**造成实际伤害**后的回调（无参 Callable）
## 剑客的「云」用它给剑意 +1：弹反/无敌帧下的命中不算「成功命中」
var on_hit_player: Callable = Callable()

## ===== 弧线追踪（万剑归宗的飞剑用）=====
## 转向速度（度/秒）：0 = 直线飞行；>0 = 每帧把 direction 朝目标转一点，
## 于是「从身侧斜着放出 → 逐渐拐向玩家」，形成弧线而非散射直线。
var turn_speed_deg: float = 0.0
## 追踪目标（留空 = 不追踪，保持直线）
var homing_target: Node2D = null
## 防绕圈：转弯半径 = 速度 / 角速度，必须让它小于 距离 / ORBIT_GUARD，轨迹才向内收敛
## （与 player_projectile 同名同义，2026-10-22 修「万剑归宗绕着目标转圈到消失」）
const ORBIT_GUARD := 1.8
## 视觉是否每帧对齐飞行方向（细长剑类需要；球类开了也无害但是白做）
var align_visual: bool = false
## 贴图本身朝右（鱼形符箓）：旋转直接用 aim.angle()，朝左时 flip_v 防止肚皮朝上。
## 默认 false 走旧的「贴图朝下」口径（剑/刀气）。
var align_visual_right: bool = false
## 发射时记下的侧别（-1 左 / +1 右，供验证与调试读取）
## ⚠ 必须在脚本里声明：只靠外部 set() 写一个未声明的字段是不会生效的
var launch_side: float = 0.0

## ===== 侧向正弦摆动（阴阳双鱼的「鱼」）=====
## 与 player_projectile 同名同义：两条鱼取反相（0 与 π）→ 途中互相交叉，
## 平均航线仍压在瞄准线上，不像 ±7° 散射那样越远越散。
var swim_amp: float = 0.0      ## 摆幅（像素）
var swim_freq: float = 0.0     ## 频率（Hz）
var swim_phase: float = 0.0    ## 初相（弧度）
var _swim_t: float = 0.0

## ===== 太极盘「接化发」（2026-10-29）=====
## 护体期间被玩家接住的敌弹不再走直线，而是绕玩家转一圈再反打来源。
var _capture_active: bool = false
var _capture_target: Node2D = null
var _capture_angle: float = 0.0
var _capture_radius: float = 90.0
var _capture_t: float = 0.0
var _capture_duration: float = 0.7

var life_timer: float = 5.0
## 技能投射物外观覆盖：由 BOSS / 野修按对应功法 skill_id 填入，
## 让敌人放同一门功法时也使用玩家的弹体外观
var visual_id_override: String = ""
## 被弹反后的剩余寿命上限（秒）：弹回的剑只负责"反打一下"，不该赖在场上
const DEFLECT_LIFE := 1.6
var is_deflected: bool = false  # 是否已被弹反
var deflect_damage: float = 12.0  # 弹反后对BOSS造成的伤害（与玩家攻击一致）
var visual_scale: float = 1.0   # 视觉缩放（二阶段元素法球变大）

## 视觉接入点（美术替换只改 ArtDB，不动本脚本）
## 物理投掷 = boss_projectile；元素法球 = boss_projectile_elemental
@onready var visual: SkinVisual = $Visual/Skin


func _ready() -> void:
	# 符箓「罡风 / 石阵」要按组清弹幕：统一登记，再按 source_is_ally 过滤
	add_to_group("boss_projectile")
	# 视觉：技能投射物优先用覆盖外观；普攻投射物按攻击类型选皮肤表条目
	visual.visual_id = visual_id_override if visual_id_override != "" \
		else ("boss_projectile_elemental" if attack_kind == "elemental" else "boss_projectile")
	visual.refresh()
	visual.scale = Vector2(visual_scale, visual_scale)
	_style_skill_visual()

	# 连接命中信号（代码连接，确保可靠）
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


## 技能投射物外观覆盖（入树后调用；同时负责加法混合，避免刀气/剑光出现黑底）
func set_visual_override(id: String) -> void:
	if id == "":
		return
	visual_id_override = id
	if not is_instance_valid(visual) or not is_inside_tree():
		return
	visual.visual_id = id
	visual.refresh()
	visual.scale = Vector2(visual_scale, visual_scale)
	_style_skill_visual()


func _style_skill_visual() -> void:
	if not is_instance_valid(visual):
		return
	if visual.visual_id == "skill_blade_qi" or visual.visual_id == "skill_sword_light":
		if visual.render_node is Sprite2D:
			(visual.render_node as Sprite2D).material = SkillFx.additive_material()


## 设置视觉缩放（供 BOSS 在生成后调整法球大小）
func set_visual_scale(s: float) -> void:
	visual_scale = s
	if is_instance_valid(visual):
		visual.scale = Vector2(s, s)


func _physics_process(delta: float) -> void:
	# 时停：弹体悬在半空（窗口里由 SceneTreeTimer 新发射的那颗也必须静止，
	# 否则 pause 拦不住它，落点伤害虽然被 deal_damage_to 挡了，看着仍是时间在走）
	if BossBase.world_frozen:
		return
	life_timer -= delta
	if life_timer <= 0.0:
		queue_free()
		return
	if _capture_active:
		_tick_taiji_capture(delta)
		return
	# 弧线追踪：每帧朝目标方向转一点（转角受 turn_speed_deg 限制，转太快的「折线」不好看）
	# ⚠ 与 player_projectile 同一套防绕圈处理：固定角速度下 转弯半径 = 速度/角速度，
	#   目标距离接近该半径时会锁进稳定圆轨道再也咬不住（2026-10-22 用户报的万剑归宗绕圈）。
	#   角速度按距离自适应放大 → 转弯半径始终小于当前距离，轨迹向内收敛。
	if turn_speed_deg > 0.0 and homing_target != null and is_instance_valid(homing_target):
		var to_target: Vector2 = homing_target.global_position - global_position
		var dist := to_target.length()
		var desired: Vector2 = to_target / maxf(dist, 0.0001)
		var cur: float = direction.angle()
		var diff: float = wrapf(desired.angle() - cur, -PI, PI)
		var omega := maxf(deg_to_rad(turn_speed_deg), ORBIT_GUARD * speed / maxf(dist, 1.0))
		var step: float = omega * delta
		direction = Vector2.RIGHT.rotated(cur + clampf(diff, -step, step))
	global_position += direction * speed * delta
	var lateral := Vector2.ZERO
	if swim_amp > 0.0 and swim_freq > 0.0:
		# 横移按速度积分（amp·ω·cos），合成轨迹是标准正弦；
		# 本体朝向跟着合速度偏一点，才是「斜着游」而不是平移的圆片
		_swim_t += delta
		var w := TAU * swim_freq
		lateral = direction.orthogonal() * (swim_amp * w * cos(w * _swim_t + swim_phase))
		global_position += lateral * delta
		if not align_visual:
			rotation = (direction * speed + lateral).angle()
	# 视觉对齐：细长剑必须每帧跟着转向，否则「剑身横着飞」
	# ⚠ 剑图竖直、刃尖朝下（+Y = 90°），用 **-PI/2** 让刃尖指向飞行方向；
	#   鱼形符箓本身朝右，用 **0** 并靠 flip_v 处理向左，避免肚皮朝上。
	if align_visual and is_instance_valid(visual):
		var aim := direction
		if swim_amp > 0.0 and swim_freq > 0.0:
			aim = (direction * speed + lateral).normalized()
		if align_visual_right:
			visual.rotation = aim.angle()
			var render := visual.render_node as Sprite2D
			if render != null:
				render.flip_v = aim.x < -0.001
		else:
			visual.rotation = aim.angle() - PI * 0.5


## 被太极护体接住：锁定玩家，绕身一周；期间关闭碰撞，避免半路打到自己
func begin_taiji_capture(player: Node2D, duration: float = 0.7) -> void:
	if _capture_active or is_deflected or source_is_ally:
		return
	if not is_instance_valid(player):
		return
	_capture_active = true
	_capture_target = player
	_capture_t = 0.0
	_capture_duration = maxf(0.30, duration)
	var rel := global_position - player.global_position
	_capture_radius = clampf(rel.length(), 56.0, 150.0)
	_capture_angle = rel.angle()
	life_timer = maxf(life_timer, _capture_duration + 1.4)
	collision_mask = 0
	if is_instance_valid(visual):
		visual.modulate = Color(0.86, 0.94, 1.0, 1.0)


func _tick_taiji_capture(delta: float) -> void:
	if not is_instance_valid(_capture_target):
		queue_free()
		return
	_capture_t += delta
	_capture_angle += TAU * delta / _capture_duration
	var t := clampf(_capture_t / _capture_duration, 0.0, 1.0)
	var radius := lerpf(_capture_radius, 62.0, t)
	var center := _capture_target.global_position + Vector2(0.0, -34.0)
	global_position = center + Vector2.RIGHT.rotated(_capture_angle) * radius
	# 弹体顺着切线方向转（鱼头/剑尖跟着绕圈）
	var tangent := Vector2.RIGHT.rotated(_capture_angle + PI * 0.5)
	if is_instance_valid(visual):
		if align_visual:
			if align_visual_right:
				visual.rotation = tangent.angle()
				var render := visual.render_node as Sprite2D
				if render != null:
					render.flip_v = tangent.x < -0.001
			else:
				visual.rotation = tangent.angle() - PI * 0.5
		else:
			rotation = tangent.angle()
	if _capture_t < _capture_duration:
		return
	_capture_active = false
	var boss := _find_reflect_target()
	if boss == null:
		queue_free()
		return
	# 反打伤害沿用敌弹自己的伤害：这是「接化发」，不是额外白嫖一发玩家倍率
	deflect_damage = damage
	deflect((boss.global_position - global_position).normalized())
	# 接化发要真的飞回来源，不能像弹反那样 1.6 秒就消失
	life_timer = maxf(life_timer, 2.2)


## 反打目标：优先原发射者（BOSS/野修），否则场上最近的 BOSS
func _find_reflect_target() -> Node2D:
	if is_instance_valid(source) and source is Node2D and not source_is_ally:
		return source as Node2D
	var best: Node2D = null
	var best_d := INF
	for raw in get_tree().get_nodes_in_group("boss"):
		var b := raw as Node2D
		if b == null or not is_instance_valid(b):
			continue
		# 尸体还挂在 "boss" 组里直到淡出动画放完，别把它当反打目标
		if BossBase.is_unit_dead(b):
			continue
		var d := global_position.distance_squared_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


## 命中玩家阵旗的实体命中体（Area2D 层 256）：一次投射物算一刀
func _on_area_entered(area: Area2D) -> void:
	if not is_instance_valid(area):
		return
	if _capture_active or is_deflected or source_is_ally:
		return
	var f := area.get_parent()
	if is_instance_valid(f) and f is ArrayFlag and not bool((f as ArrayFlag).owner_is_boss):
		if f.has_method("take_damage"):
			f.call("take_damage", damage * ally_scale,
				source if is_instance_valid(source) else null, "physical", "", true)
		queue_free()


func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return
	if _capture_active:
		return
	if is_deflected:
		# 弹反后：命中 BOSS 造成伤害（此时 collision_mask 只检测 BOSS 层）
		if body.has_method("take_damage"):
			body.take_damage(deflect_damage, null)
			queue_free()
		return
	# 友军召唤物的投射物打敌方 BOSS / 演武场木桩：走 BOSS 版签名
	# （amount, source, damage_kind, element, from_projectile）
	# ⚠ 木桩不是 BossBase，但在 "boss" 组且使用同一套签名；漏掉它会像打玩家一样
	#   把 attack_kind 塞进 source 参数，报类型转换错误并中断战斗。
	if body is BossBase or body.is_in_group("boss"):
		var target_boss := body as BossBase
		if target_boss != null:
			# ⚠ 双保险：绝不打自己、也不打同阵营（投射物出生在发射者身上，层配错就会自伤）
			#   source 可能已释放（召唤物消散后投射物还在飞）→ 身份比较前先判有效性，
			#   阵营用发射时记下的 source_is_ally / source_team，不再去碰 source 本体
			if is_instance_valid(source) and target_boss == source:
				return
			var tt := BossBase.unit_team(target_boss)
			if source_team >= 0 and tt >= 0:
				# 两只棋子：按队伍号判。旧那句 `source_is_ally == is_ally` 对
				# 两个 is_ally=false 的棋子恒为真，会把所有远程结算挡掉。
				if source_team == tt:
					return
			elif source_is_ally == target_boss.is_ally:
				return
		var dk := "elemental" if attack_kind == "elemental" else "physical"
		# 传给 take_damage 的 source 也兜一层：freed 实例传进去会在受伤方的方向判定里炸
		body.take_damage(damage * ally_scale, source if is_instance_valid(source) else null, dk, "", false)
		if on_hit_player.is_valid():
			on_hit_player.call()
		if not is_deflected:
			queue_free()
		return
	# 命中玩家（source 传投掷物自身，供玩家区分近战/远程弹刀）
	if body.has_method("take_damage"):
		# 用 get() 动态读取血量：无敌帧下的碰撞不算「成功命中」，回调不该触发
		var hp_before = body.get("hp")
		body.take_damage(damage * ally_scale, attack_kind, self)
		var hp_after = body.get("hp")
		var really_hit := hp_before == null or hp_after == null or float(hp_after) < float(hp_before)
		if really_hit and on_hit_player.is_valid():
			on_hit_player.call()
		# 若被弹反，则不销毁，继续飞出；否则命中销毁
		if not is_deflected:
			queue_free()


## 被弹反：沿随机方向反弹（玩家面向 ±120° 内随机）
func deflect(new_dir: Vector2) -> void:
	if is_deflected:
		return
	is_deflected = true
	direction = new_dir.normalized()
	speed = speed * 1.5  # 反弹加速
	# 反弹后改为检测 BOSS 层（2），不再伤害玩家
	collision_mask = 2
	# ⚠ 必须清掉追踪（2026-10-22 用户报「弹反万剑归宗后剑一直吸附在玩家脚底」）：
	#   万剑归宗的飞剑 homing_target 指着玩家、turn_speed_deg 还有 200°/s，
	#   只改方向不清追踪的话，剑拐个弯又咬回玩家；而反弹后 mask 只打 BOSS 层，
	#   它永远打不到玩家也打不到别人，就绕着玩家脚底转到寿命结束 —— 看起来像"吸附"。
	homing_target = null
	turn_speed_deg = 0.0
	# 弹回的剑不再绕圈，给个短寿命收尾：打不中 BOSS 也会很快消失，不留残影
	life_timer = minf(life_timer, DEFLECT_LIFE)
	# 视觉变化：提亮 + 略微放大（用 modulate 对贴图 / 占位一律生效）
	if is_instance_valid(visual):
		visual.modulate = Color(1.0, 1.0, 0.7)
		visual.scale = Vector2(1.3, 1.3) * visual_scale
	# 反弹火花：在当前位置迸发一簇小粒子，凸显反弹轨迹
	# 外观走 ArtDB.EFFECTS 的 "fx_deflect_spark"（换美术只改表）
	FxPlayer.spawn(self, "fx_deflect_spark")
