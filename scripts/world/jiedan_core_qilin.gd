class_name JiedanCoreQilin
extends WorldEnemy
## 赤金丹霞核心首领「赤金火麟」（2026-10-29）
##
## 一阶段独有机制「霞印」：带 mark 的招式命中玩家 +1 层（弹反 -1，10 秒不续则散），
## 三层时在玩家脚下炸开日蚀。层数用三颗绕身的日火图形表示，不刷飘字。
## 二阶段「日轮当空」：日轮离体悬在场心 —— 每 6 秒脉冲，离场心 300 内 +1 层；
## 离场心 900 外持续灼烧。解锁日蚀·坠光 / 金乌·陨日。
## 八式：裂岩冲 / 踏霞 / 火雨 / 阳炎 / 三连 / 日冕环裂（一阶段）+ 日蚀 / 陨日（二阶段）。

const MARK_LIMIT := 3
const MARK_DECAY := 10.0
const BRAND_RADIUS := 150.0
const BRAND_COEF := 0.90

const SUN_HEIGHT := 200.0
const SUN_BRAND_RADIUS := 300.0
const SUN_SCORCH_RADIUS := 900.0
const SUN_SCORCH_COEF := 0.16
const SUN_SCORCH_TICK := 0.5
const SUN_PULSE_INTERVAL := 6.0

const WARN_COLOR := Color(1.0, 0.62, 0.22, 0.85)

var _mark_stacks := 0
var _mark_left := 0.0
var _mark_once_pending := 0
var _brand_bursting := false
var _motes: Array = []

var _sun: Sprite2D = null
var _sun_center := Vector2.ZERO
var _sun_pulse_left := SUN_PULSE_INTERVAL
var _scorch_left := SUN_SCORCH_TICK
var _sun_fx: Array = []
var _meteor_fields: Array = []


func _ready() -> void:
	super()
	_build_motes()


func _physics_process(delta: float) -> void:
	if _mark_stacks > 0:
		_mark_left -= delta
		if _mark_left <= 0.0:
			_mark_stacks = 0
			_show_enemy_float("霞印消散", Color(1.0, 0.78, 0.42))
	if phase == 2 and _sun != null and is_instance_valid(_sun):
		_tick_sun(delta)
	_tick_meteor_fields(delta)
	_update_motes()
	super(delta)


func _exit_tree() -> void:
	_clear_sun()
	_clear_motes()
	_clear_meteor_fields()


func _die() -> void:
	_clear_sun()
	_clear_motes()
	_clear_meteor_fields()
	super._die()


func _on_phase_two() -> void:
	_spawn_sun()
	_show_enemy_float("日轮当空·离位者灼", Color(1.0, 0.93, 0.66))


## 侧视四足：受击球沿朝向铺开、压到脚底平面（与苍角同口径）
func hit_spheres() -> Array:
	return [
		Vector3(-56.0, 0.0, 54.0),
		Vector3(0.0, 0.0, 62.0),
		Vector3(56.0, 0.0, 54.0),
	]


func on_parried(source: Node) -> void:
	super(source)
	if _mark_stacks > 0:
		_add_mark(-1)
		_show_enemy_float("弹反·卸印", Color(1.0, 0.86, 0.52))


# ===================== 霞印 =====================

## 命中玩家时由带 mark 的招式调用；每发最多叠一次（_mark_once_pending 控制）
func deal_damage_to(unit: Node, amount: float, attack_kind: String,
		element: String = "") -> bool:
	var hit := super(unit, amount, attack_kind, element)
	if hit and _mark_once_pending > 0 and unit == target and not _brand_bursting:
		var n := _mark_once_pending
		_mark_once_pending = 0
		_add_mark(n)
	return hit


func _add_mark(n: int) -> void:
	if state == BossState.DEAD or n == 0:
		return
	if n > 0:
		var before := _mark_stacks
		_mark_stacks = mini(MARK_LIMIT, _mark_stacks + n)
		_mark_left = MARK_DECAY
		if before == 0:
			_show_enemy_float("霞印灼身", Color(1.0, 0.70, 0.26))
		if _mark_stacks >= MARK_LIMIT:
			_burst_brand()
	else:
		_mark_stacks = maxi(0, _mark_stacks + n)
		if _mark_stacks > 0:
			_mark_left = MARK_DECAY


func _burst_brand() -> void:
	if _brand_bursting:
		return
	_brand_bursting = true
	var pos := global_position
	var has_target := target != null and is_instance_valid(target)
	if has_target:
		pos = (target as Node2D).global_position
	_play_brand_fx(pos)
	_show_enemy_float("霞印·日蚀", Color(1.0, 0.82, 0.36))
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > BRAND_RADIUS:
			continue
		deal_damage_to(u, attack_power * BRAND_COEF * _damage_multiplier(),
			"elemental", "fire")
	_mark_stacks = 0
	_mark_left = 0.0
	_brand_bursting = false


func _play_brand_fx(pos: Vector2) -> void:
	SkillFx.play_at_strike(self, "skill_qilin_brand",
		{"range": BRAND_RADIUS, "angle": 360.0}, Vector2.RIGHT, pos)
	_warn_ring(pos, BRAND_RADIUS, Color(1.0, 0.66, 0.24, 0.8), 0.38)


func _build_motes() -> void:
	for i in MARK_LIMIT:
		var spr := Sprite2D.new()
		spr.texture = SkillFx.sun_orb_texture()
		spr.material = SkillFx.additive_material()
		spr.centered = true
		spr.scale = Vector2(0.11, 0.11)
		spr.modulate = Color(1.0, 0.74, 0.30, 0.95)
		spr.z_index = 14
		spr.visible = false
		spr.top_level = true
		get_parent().add_child(spr)
		_motes.append(spr)


func _update_motes() -> void:
	var has_target := target != null and is_instance_valid(target)
	var show := has_target and _mark_stacks > 0
	for i in _motes.size():
		var spr := _motes[i] as Sprite2D
		if spr == null or not is_instance_valid(spr):
			continue
		spr.visible = show
		if not show:
			continue
		# 三格常驻：亮起的枚数 = 当前层数，空格压到很暗但保留轨道位置
		var filled := i < _mark_stacks
		var t := Time.get_ticks_msec() / 1000.0
		var a := t * 2.2 + TAU * float(i) / float(MARK_LIMIT)
		var c := (target as Node2D).global_position + Vector2(0.0, -44.0)
		spr.global_position = c + Vector2(cos(a), sin(a) * 0.55) * 38.0
		spr.scale = Vector2.ONE * (0.11 if filled else 0.07)
		if filled:
			spr.modulate.a = 0.78 + 0.22 * sin(t * 5.4 + float(i))
		else:
			spr.modulate.a = 0.26


func _clear_motes() -> void:
	for m in _motes:
		if is_instance_valid(m):
			(m as Node).queue_free()
	_motes.clear()


# ===================== 日轮当空 =====================

func _spawn_sun() -> void:
	_clear_sun()
	_sun_center = spawn_home
	_sun = Sprite2D.new()
	_sun.texture = SkillFx.sun_orb_texture()
	_sun.material = SkillFx.additive_material()
	_sun.centered = true
	# 巨轮当空：直径 ≈ 540 世界像素，半透明压在 BOSS 身后，形成日冕轮廓
	_sun.scale = Vector2.ONE * 1.6
	_sun.modulate = Color(1.0, 0.78, 0.40, 0.42)
	_sun.z_index = -2
	get_parent().add_child(_sun)
	_sun.global_position = _sun_center + Vector2(0.0, -SUN_HEIGHT)
	_sun_fx.append(_sun)

	# 场心 300 / 900 两道地面环：内环（叠印圈）与灼烧边界
	_sun_fx.append(_make_ground_ring(SUN_SCORCH_RADIUS, Color(0.95, 0.26, 0.08, 0.30)))
	_sun_fx.append(_make_ground_ring(SUN_BRAND_RADIUS, Color(1.0, 0.62, 0.20, 0.34)))

	# 日轮呼吸交给 _tick_sun 的 sin，不用无限循环 tween（退出时会报 Infinite loop）
	_sun_pulse_left = SUN_PULSE_INTERVAL
	_scorch_left = SUN_SCORCH_TICK


func _make_ground_ring(radius: float, color: Color) -> Sprite2D:
	var ring := Sprite2D.new()
	ring.texture = SkillFx.ring_texture()
	ring.material = SkillFx.additive_material()
	ring.centered = true
	ring.z_index = -6
	var s := radius / (128.0 * SkillFx.SUN_RING_EDGE)
	ring.scale = Vector2(s, s)
	ring.modulate = color
	get_parent().add_child(ring)
	ring.global_position = _sun_center
	return ring


func _tick_sun(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_sun.global_position = _sun_center + Vector2(0.0, -SUN_HEIGHT + sin(t * 0.8) * 8.0)
	_sun.rotation = t * 0.18
	_sun.modulate.a = 0.32 + 0.07 * sin(t * 2.0)
	if target == null or not is_instance_valid(target):
		return
	var ppos := (target as Node2D).global_position
	_sun_pulse_left -= delta
	if _sun_pulse_left <= 0.0:
		_sun_pulse_left = SUN_PULSE_INTERVAL
		_sun_pulse(ppos)
	_scorch_left -= delta
	if _scorch_left <= 0.0:
		_scorch_left = SUN_SCORCH_TICK
		if ppos.distance_to(_sun_center) > SUN_SCORCH_RADIUS:
			deal_damage_to(target, attack_power * SUN_SCORCH_COEF * _damage_multiplier(),
				"elemental", "fire")
			_show_enemy_float("日轮灼烧", Color(1.0, 0.52, 0.18))


## 每 6 秒脉冲：离场心 300 内叠 1 层霞印；环向外扩一圈作读秒提示
func _sun_pulse(ppos: Vector2) -> void:
	_warn_ring(_sun_center, SUN_BRAND_RADIUS, Color(1.0, 0.70, 0.30, 0.85), 0.45)
	if _sun != null and is_instance_valid(_sun):
		var tw := create_tween()
		tw.tween_property(_sun, "scale", _sun.scale * 1.18, 0.16)
		tw.tween_property(_sun, "scale", _sun.scale / 1.18, 0.30)
	if ppos.distance_to(_sun_center) <= SUN_BRAND_RADIUS:
		_add_mark(1)


func _clear_sun() -> void:
	for n in _sun_fx:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_sun_fx.clear()
	_sun = null


# ===================== 八式 =====================

func _cast_core_skill() -> void:
	var def := _next_core_skill
	_mark_once_pending = 0
	if def.is_empty():
		super()
		return
	match String(def.get("id", "")):
		"qilin_rain":
			_cast_rain(def)
		"qilin_orb":
			_cast_orb(def)
		"qilin_claw":
			_cast_claw(def)
		"qilin_ring":
			_cast_ring(def)
		"qilin_eclipse":
			_cast_eclipse(def)
		"qilin_meteor":
			_cast_meteor(def)
		"qilin_stomp":
			_mark_once_pending = int(def.get("mark", 0))
			super()
			_mark_once_pending = 0
		_:
			super()


## 与苍角同口径：写冷却 / 收招间隔并清空待放招式
func _qilin_core_done(def: Dictionary) -> void:
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


## 火雨·焚野：玩家周围六处落点，先落警示环，1.0 秒内依次砸下
func _cast_rain(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	_mark_once_pending = int(def.get("mark", 0))
	var center := global_position + facing * 220.0
	if target != null and is_instance_valid(target):
		center = (target as Node2D).global_position
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var points: Array = []
	for i in 6:
		var a := TAU * float(i) / 6.0 + rng.randf_range(-0.35, 0.35)
		var d := rng.randf_range(120.0, 280.0)
		points.append(center + Vector2(cos(a), sin(a)) * d)
	for i in points.size():
		var p: Vector2 = points[i]
		_warn_impact(p, 100.0, WARN_COLOR, 0.72)
		var delay := 0.55 + 0.14 * float(i)
		var timer := get_tree().create_timer(delay, true)
		timer.timeout.connect(_rain_impact.bind(p, float(def.get("damage_scale", 0.38))))
	_qilin_core_done(def)


func _rain_impact(pos: Vector2, scale: float) -> void:
	if not is_inside_tree() or state == BossState.DEAD:
		return
	SkillFx.play_at_strike(self, "skill_qilin_rain",
		{"range": 100.0, "angle": 360.0}, Vector2.RIGHT, pos)
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > 100.0:
			continue
		deal_damage_to(u, attack_power * scale * _damage_multiplier(), "elemental", "fire")


## 阳炎·流火：火球飞向玩家施法时的位置，落点炸开（可走位躲）
func _cast_orb(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	_mark_once_pending = int(def.get("mark", 0))
	var landing := global_position + facing * 320.0
	if target != null and is_instance_valid(target):
		landing = (target as Node2D).global_position
	_warn_impact(landing, 120.0, WARN_COLOR, 0.62)
	var orb := Sprite2D.new()
	orb.texture = SkillFx.sun_orb_texture()
	orb.material = SkillFx.additive_material()
	orb.centered = true
	orb.scale = Vector2.ONE * 0.55
	orb.z_index = 24
	get_parent().add_child(orb)
	orb.global_position = global_position + Vector2(0.0, -120.0)
	var tw := orb.create_tween()
	tw.tween_property(orb, "global_position", landing, 0.62) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(orb, "scale", Vector2.ONE * 0.72, 0.62)
	tw.tween_callback(orb.queue_free)
	var timer := get_tree().create_timer(0.62, true)
	timer.timeout.connect(_orb_impact.bind(landing,
		float(def.get("damage_scale", 0.85))))
	_qilin_core_done(def)


func _orb_impact(pos: Vector2, scale: float) -> void:
	if not is_inside_tree() or state == BossState.DEAD:
		return
	SkillFx.play_at_strike(self, "skill_qilin_orb",
		{"range": 120.0, "angle": 360.0}, Vector2.RIGHT, pos)
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > 120.0:
			continue
		deal_damage_to(u, attack_power * scale * _damage_multiplier(), "elemental", "fire")


## 赤金·三连：三爪各自结算（都能弹反），命中任意一段叠 1 层
func _cast_claw(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	_mark_once_pending = int(def.get("mark", 0))
	var form := MoveDB.resolve_boss("form_slash_single")
	var delay := 0.0
	for i in 3:
		var timer := get_tree().create_timer(delay + 0.01, true)
		timer.timeout.connect(_claw_hit.bind(form,
			float(def.get("damage_scale", 0.38)), i))
		delay += 0.18
	_qilin_core_done(def)


func _claw_hit(form: Dictionary, scale: float, index: int) -> void:
	if not is_inside_tree() or state == BossState.DEAD or form.is_empty():
		return
	_update_facing_to_target()
	_play_form(form, attack_power * scale * _damage_multiplier(),
		"physical_melee", "", 220.0, 120.0, "skill_qilin_claw")
	if index == 2:
		_mark_once_pending = 0


## 日冕·环裂：日轮震出大圈火环，0.35 秒后结算（够玩家跑出 460 圈）
func _cast_ring(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	_mark_once_pending = int(def.get("mark", 0))
	SkillFx.play_at_strike(self, "skill_qilin_ring",
		{"range": 460.0, "angle": 360.0}, facing)
	_warn_ring(global_position, 460.0, WARN_COLOR, 0.42)
	var timer := get_tree().create_timer(0.35, true)
	timer.timeout.connect(_ring_hit.bind(float(def.get("damage_scale", 0.70))))
	_qilin_core_done(def)


func _ring_hit(scale: float) -> void:
	if not is_inside_tree() or state == BossState.DEAD:
		return
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(global_position) > 460.0:
			continue
		deal_damage_to(u, attack_power * scale * _damage_multiplier(), "elemental", "fire")


## 日蚀·坠光：锁定玩家落点，0.55 秒后光柱砸下（150 圈）
func _cast_eclipse(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	_mark_once_pending = int(def.get("mark", 0))
	var landing := global_position + facing * 320.0
	if target != null and is_instance_valid(target):
		landing = (target as Node2D).global_position
	_warn_impact(landing, 150.0, Color(1.0, 0.56, 0.20, 0.92), 0.60)
	_warn_ring(landing, 70.0, Color(1.0, 0.86, 0.46, 0.9), 0.60)
	var timer := get_tree().create_timer(0.58, true)
	timer.timeout.connect(_eclipse_impact.bind(landing,
		float(def.get("damage_scale", 1.15))))
	_qilin_core_done(def)


func _eclipse_impact(pos: Vector2, scale: float) -> void:
	if not is_inside_tree() or state == BossState.DEAD:
		return
	SkillFx.play_at_strike(self, "skill_qilin_eclipse",
		{"range": 150.0, "angle": 360.0}, Vector2.RIGHT, pos)
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > 150.0:
			continue
		deal_damage_to(u, attack_power * scale * _damage_multiplier(), "elemental", "fire")


## 金乌·陨日：落点 180 圈，0.75 秒后落地并留 4 秒燃烧坑
func _cast_meteor(def: Dictionary) -> void:
	_reset_visual()
	_update_facing_to_target()
	_mark_once_pending = int(def.get("mark", 0))
	var landing := global_position + facing * 360.0
	if target != null and is_instance_valid(target):
		landing = (target as Node2D).global_position
	_warn_impact(landing, 180.0, Color(1.0, 0.50, 0.16, 0.92), 0.78)
	var timer := get_tree().create_timer(0.78, true)
	timer.timeout.connect(_meteor_impact.bind(landing,
		float(def.get("damage_scale", 1.45))))
	_qilin_core_done(def)


func _meteor_impact(pos: Vector2, scale: float) -> void:
	if not is_inside_tree() or state == BossState.DEAD:
		return
	SkillFx.play_at_strike(self, "skill_qilin_meteor",
		{"range": 180.0, "angle": 360.0}, Vector2.RIGHT, pos)
	for u in attack_units():
		if u == null or not is_instance_valid(u) or not (u is Node2D):
			continue
		if (u as Node2D).global_position.distance_to(pos) > 180.0:
			continue
		deal_damage_to(u, attack_power * scale * _damage_multiplier(), "elemental", "fire")
	_spawn_meteor_field(pos)


func _spawn_meteor_field(pos: Vector2) -> void:
	var decal := Sprite2D.new()
	decal.texture = load("res://assets/effects/skills/lizhao_sun_seal.png")
	decal.material = SkillFx.additive_material()
	decal.centered = true
	decal.scale = Vector2.ONE * (360.0 / 512.0)
	decal.modulate = Color(1.0, 0.48, 0.16, 0.42)
	decal.z_index = -5
	get_parent().add_child(decal)
	decal.global_position = pos
	# 燃烧坑由 _tick_meteor_fields 逐帧结算：0.5 秒一跳，半径 180，共 4 秒
	_meteor_fields.append({"node": decal, "pos": pos, "left": 4.0, "tick": 0.0})


func _tick_meteor_fields(delta: float) -> void:
	var alive: Array = []
	for raw in _meteor_fields:
		var f: Dictionary = raw
		f["left"] = float(f["left"]) - delta
		f["tick"] = float(f["tick"]) - delta
		if float(f["left"]) <= 0.0:
			if is_instance_valid(f["node"]):
				(f["node"] as Node).queue_free()
			continue
		if float(f["tick"]) <= 0.0:
			f["tick"] = 0.5
			for u in attack_units():
				if u == null or not is_instance_valid(u) or not (u is Node2D):
					continue
				if (u as Node2D).global_position.distance_to(f["pos"]) > 180.0:
					continue
				deal_damage_to(u, attack_power * 0.16 * _damage_multiplier(),
					"elemental", "fire")
		alive.append(f)
	_meteor_fields = alive


func _clear_meteor_fields() -> void:
	for raw in _meteor_fields:
		var f: Dictionary = raw
		if is_instance_valid(f.get("node")):
			(f["node"] as Node).queue_free()
	_meteor_fields.clear()


## 点状落点警示：淡日纹圆盘 + 收拢光环 —— 圆盘标出判定范围，环标倒计时
func _warn_impact(pos: Vector2, radius: float, color: Color, life: float) -> void:
	var decal := Sprite2D.new()
	decal.texture = load("res://assets/effects/skills/lizhao_sun_seal.png")
	decal.material = SkillFx.additive_material()
	decal.centered = true
	decal.z_index = -4
	decal.scale = Vector2.ONE * (radius * 2.0 / 512.0)
	decal.modulate = Color(color.r, color.g, color.b, 0.20)
	get_parent().add_child(decal)
	decal.global_position = pos
	var tw := decal.create_tween()
	tw.tween_property(decal, "modulate:a", 0.0, life)
	tw.tween_callback(decal.queue_free)
	_warn_ring(pos, radius, color, life)


## 地面警示环：加色圆环由大到小收拢，替代贴图序列帧
func _warn_ring(pos: Vector2, radius: float, color: Color, life: float) -> void:
	var ring := Sprite2D.new()
	ring.texture = SkillFx.ring_texture()
	ring.material = SkillFx.additive_material()
	ring.centered = true
	ring.z_index = -4
	var s := radius / (128.0 * SkillFx.SUN_RING_EDGE)
	ring.scale = Vector2(s * 1.12, s * 1.12)
	ring.modulate = color
	get_parent().add_child(ring)
	ring.global_position = pos
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector2(s, s), life)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, life)
	tw.tween_callback(ring.queue_free)
