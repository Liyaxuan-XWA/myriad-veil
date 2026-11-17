class_name TreasureCone
extends Area2D
## 蚀甲锥（2026-11-01）
##
## 不造成伤害，只负责把「蚀甲」钉到目标身上。
## 玩家掷向 BOSS / 野修；野修掷向玩家。目标躲开或处于无敌帧时不挂 debuff。

var source: Node = null
var target_group: String = "boss"
var direction: Vector2 = Vector2.RIGHT
var speed: float = 900.0
var max_distance: float = 400.0
var debuff_id: String = "shixi"
var debuff_time: float = 8.0
var icon_path: String = ""

var _travelled: float = 0.0
var _hit: bool = false
var _spr: Sprite2D = null


func setup(p_source: Node, p_target_group: String, p_dir: Vector2, p_speed: float,
		p_range: float, p_debuff: String, p_time: float, p_icon: String) -> void:
	source = p_source
	target_group = p_target_group
	direction = p_dir.normalized() if p_dir.length_squared() > 0.0001 else Vector2.RIGHT
	speed = maxf(60.0, p_speed)
	max_distance = maxf(30.0, p_range)
	debuff_id = p_debuff
	debuff_time = maxf(0.2, p_time)
	icon_path = p_icon
	# 战报：扇形弹体自己成一行（归属走 source）
	set_meta("report_tag", "法宝扇击")


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 if target_group == "boss" else 1
	monitoring = true
	monitorable = false
	z_index = 6

	var shape := CollisionShape2D.new()
	# ⚠ 判定必须覆盖「一整个身体立柱」，不能用贴在节点原点的小圆：
	#   本项目的角色原点是脚底、碰撞体一律往上长 —— 演武场木桩是竖直胶囊，
	#   底边正好压在 y=0，脚底高度飞行的 r=10 圆只在它底边上擦一下，
	#   900 px/s 每帧跨 15px，物理服务器一次都没报接触 → 锥子直接穿过去
	#   （2026-11-02 用户报「演武场里锥子飞过去了但没反应」）。
	#   竖向立柱同时兼容脚底朝下的大世界单位（它们原点在身体中间）。
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26.0, 104.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -42.0)
	add_child(shape)

	# 暗底上锥体本身偏黑，先垫一层暗绿微光再画图标
	var glow := Sprite2D.new()
	glow.texture = TreasureFx.soft_disc_texture()
	glow.centered = true
	glow.position = Vector2(0.0, -26.0)
	glow.scale = Vector2(0.17, 0.17)
	glow.modulate = Color(0.52, 0.88, 0.42, 0.20)
	glow.z_index = -1
	add_child(glow)
	_spr = Sprite2D.new()
	_spr.centered = true
	_spr.position = Vector2(0.0, -26.0)
	_spr.scale = Vector2(0.22, 0.22)
	_spr.rotation = direction.angle() + PI * 0.5
	if icon_path != "" and ResourceLoader.exists(icon_path):
		_spr.texture = load(icon_path)
	else:
		_spr.texture = SkillFx.dot_texture()
		_spr.modulate = Color(0.60, 0.84, 0.44, 0.9)
		_spr.scale = Vector2(0.6, 0.6)
	add_child(_spr)
	_build_trail()
	body_entered.connect(_on_body_entered)


func _build_trail() -> void:
	var p := CPUParticles2D.new()
	p.texture = SkillFx.dot_texture()
	p.amount = 18
	p.lifetime = 0.3
	p.local_coords = false
	p.direction = -direction
	p.spread = 32.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 38.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.26
	p.color = Color(0.58, 0.84, 0.44, 0.75)
	p.position = Vector2(0.0, -24.0)
	add_child(p)
	p.emitting = true


func _physics_process(delta: float) -> void:
	if _hit:
		return
	global_position += direction * speed * delta
	_travelled += speed * delta
	if _spr != null:
		_spr.rotation += delta * 9.0
	if _travelled >= max_distance:
		queue_free()
		return
	_sweep_step()


## 逐帧形状查询补判定。
## ⚠ 不能只靠 body_entered：2026-11-02 用户报「演武场里锥子飞过去了但没反应」——
##   木桩是 StaticBody2D，Area2D 的移动侦测对它一次都不触发
##   （同一位置直接 intersect_shape 能查到它，所以是信号侧的问题，不是几何问题）。
##   900 px/s 每帧跨 15px，逐帧按自己的判定立柱扫一遍，静态体和动态体就一视同仁。
func _sweep_step() -> void:
	var space = get_world_2d().direct_space_state
	if space == null:
		return
	var q := PhysicsShapeQueryParameters2D.new()
	var probe := RectangleShape2D.new()
	probe.size = Vector2(26.0, 104.0)
	q.shape = probe
	q.transform = Transform2D(0.0, global_position + Vector2(0.0, -42.0))
	q.collision_mask = collision_mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	for hit in space.intersect_shape(q, 4):
		var body: Node = hit.get("collider")
		if body == null:
			continue
		_on_body_entered(body)
		if _hit:
			return


func _on_body_entered(body: Node) -> void:
	if _hit or not is_instance_valid(body):
		return
	# 棋局：施法者与目标都是带 team_id 的 match_piece，`"player"` / `"boss"` 组名
	# 在棋盘上毫无意义 —— 四只大陆核心的风蚀锥固定传 target_group="player"，
	# 搬到棋局里就是**恒不命中**（不崩，只是静默失效）。
	# 走统一入口按队伍筛，其余守卫（死亡/无敌/转阶段）与非棋局分支保持原样。
	var piece_cast := source != null and is_instance_valid(source) \
			and BossBase.unit_team(source) >= 0
	if piece_cast:
		if not BossBase.hostile_units(source).has(body):
			return
		if BossBase.is_unit_dead(body):
			return
	elif target_group == "boss":
		if not body.is_in_group("boss"):
			return
		if BossBase.is_ally_unit(body):
			return
		if body.has_method("is_dead") and bool(body.call("is_dead")):
			return
		var invuln = body.get("_treasure_invuln_left")
		if invuln != null and float(invuln) > 0.0:
			return
		var transitioning = body.get("phase_transitioning")
		if transitioning != null and bool(transitioning):
			return
	else:
		if not body.is_in_group("player"):
			return
		if bool(body.get("is_dead")):
			return
		if bool(body.get("is_dodging")):
			return
		if float(body.get("invincible_timer")) > 0.0:
			return

	_hit = true
	if body.has_method("apply_debuff"):
		body.call("apply_debuff", debuff_id, debuff_time)
	if body is Node2D:
		var center := Vector2(0.0, -46.0)
		if body.has_method("_body_center"):
			center = body.call("_body_center")
		elif body.has_method("head_top_y"):
			center = Vector2(0.0, float(body.call("head_top_y")) * 0.5)
		TreasureFx.attach_corrode(body as Node2D, center, debuff_time)
	TreasureFx.play_cone_hit(get_parent(), global_position + Vector2(0.0, -26.0))
	queue_free()
