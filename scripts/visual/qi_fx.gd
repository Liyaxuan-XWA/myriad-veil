class_name QiFx
extends Node2D
## 太虚气君「气」一族的表现层（2026-10-28）。
##
## 与刀光 / 兽爪 / 太极 / 绞绳分开：只用**气环、气流、气柱**三种形状，
## 颜色固定为青色气（0.56,0.86,1.0），治疗用青绿；不借用其它 BOSS 的素材。

const QI := Color(0.56, 0.86, 1.0, 1.0)
const QI_HI := Color(0.78, 0.96, 1.0, 1.0)
const HEAL := Color(0.55, 0.95, 0.75, 1.0)
const RING_TEX := "res://assets/effects/skills/qi_ring.png"


static func _spawn(host: Node) -> QiFx:
	if host == null or not host.is_inside_tree():
		return null
	var fx := QiFx.new()
	host.add_child(fx)
	# 气效必须压在 BOSS 与地面之上，否则贴身的环会被身体挡住（用户"根本没变"的主因之一）
	fx.z_as_relative = false
	fx.z_index = 40
	return fx


## 聚气 / 环数变化：一圈气环向内收
static func play_gather(host: Node, pos: Vector2) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	for i in 3:
		var tw := fx.create_tween()
		tw.tween_interval(0.06 * float(i))
		tw.tween_callback(func() -> void:
			if is_instance_valid(fx):
				var r := fx._qi_ring(Vector2.ZERO, 110.0, 0.38, 0.55)
				var inner := r.create_tween()
				inner.tween_property(r, "scale", r.scale * 0.25, 0.38)
				inner.parallel().tween_property(r, "modulate:a", 0.0, 0.38))
	fx._rise_motes(Vector2.ZERO, 6, QI)
	for k in 6:
		var a0 := TAU * float(k) / 6.0
		var mote := fx._dot(Vector2(cos(a0), sin(a0)) * 120.0, 0.22, Color(QI_HI.r, QI_HI.g, QI_HI.b, 0.9), 0.4)
		var mt := mote.create_tween()
		mt.tween_property(mote, "position", Vector2(cos(a0 + 1.2), sin(a0 + 1.2)) * 16.0, 0.36)
	fx._free_in(0.55)


static func pulse_rings(boss: Node2D, count: int) -> void:
	if not is_instance_valid(boss):
		return
	var fx := _spawn(boss.get_parent())
	if fx == null:
		return
	fx.global_position = boss.global_position + Vector2(0.0, -46.0)
	var r := fx._qi_ring(Vector2.ZERO, 70.0, 0.30, 0.35)
	var tw := r.create_tween()
	tw.tween_property(r, "scale", r.scale * 1.4, 0.3)
	tw.parallel().tween_property(r, "modulate:a", 0.0, 0.3)
	fx._dot(Vector2.ZERO, 0.45, Color(QI.r, QI.g, QI.b, 0.8), 0.28)
	fx._free_in(0.4)


## 冲气·裂空：一条压缩气流（三层带）+ 前端气环
static func play_wave(host: Node, a: Vector2, b: Vector2, empowered: bool) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	var th := 12.0 if empowered else 8.0
	var col := QI_HI if empowered else QI
	fx._band(a, b, th, Color(col.r, col.g, col.b, 0.75), 0.0, 0.22)
	fx._band(a, b, th * 2.6, Color(col.r, col.g, col.b, 0.22), 0.0, 0.22)
	for i in 3:
		fx._mote(a, b, col, 0.02 + 0.05 * float(i))
	fx._qi_ring(b, 46.0 if empowered else 34.0, 0.55, 0.45)
	fx._dot(b, 0.85 if empowered else 0.6, Color(0.95, 1.0, 1.0, 0.95), 0.22)
	fx._free_in(0.4)


## 御风·回旋：两圈反向气旋向外扫
static func play_spin(host: Node, pos: Vector2, radius: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	for i in 2:
		var r := fx._qi_ring(Vector2.ZERO, radius * 0.55, 0.42, 0.55)
		for k in 2:
			var a0 := TAU * float(k) / 2.0 + (0.0 if i == 0 else 1.6)
			var p0 := Vector2(cos(a0), sin(a0)) * radius * 0.5
			var p1 := Vector2(cos(a0 + 1.0), sin(a0 + 1.0)) * radius * 0.86
			fx._band(p0, p1, 10.0, Color(QI_HI.r, QI_HI.g, QI_HI.b, 0.85), 0.0, 0.26)
		var tw := r.create_tween()
		tw.tween_interval(0.05 * float(i))
		tw.tween_property(r, "scale", r.scale * (1.25 + 0.15 * float(i)), 0.3)
		tw.parallel().tween_property(r, "rotation", PI * (0.6 if i == 0 else -0.6), 0.3)
		tw.parallel().tween_property(r, "modulate:a", 0.0, 0.3)
	fx._dot(Vector2.ZERO, 0.9, Color(0.95, 1.0, 1.0, 0.9), 0.20)
	fx._dust_burst(Vector2.ZERO, 6)
	fx._free_in(0.45)


## 气锁·缚脉：扇面里飞出几枚小气环（锁扣）
static func play_lock(host: Node, pos: Vector2, dir: Vector2, reach: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	var base := dir.angle()
	# 气锁不是"一圈环"：三道链节射出去，末端收成一枚锁环（与其它气招一眼分开）
	for i in 3:
		var ang := base + deg_to_rad(-24.0 + 24.0 * float(i))
		var d := Vector2(cos(ang), sin(ang))
		var mid := d * (reach * 0.42)
		var end := d * (reach * 0.72)
		var seg := fx._band(d * 40.0, mid, 9.0, Color(QI.r, QI.g, QI.b, 0.85), 0.0, 0.30)
		var tw := seg.create_tween()
		tw.tween_property(seg, "position", end, 0.22)
		tw.parallel().tween_property(seg, "modulate:a", 0.0, 0.22)
		var r := fx._qi_ring(end, 18.0, 0.55, 0.7)
		var t2 := r.create_tween()
		t2.tween_property(r, "scale", r.scale * 0.55, 0.2)
		t2.parallel().tween_property(r, "modulate:a", 0.0, 0.2)
	fx._free_in(0.5)


## 化劲：贴在施法者身上的气罩，持续 duration 秒（返回节点，调用方也可提前释放）
static func play_ward(host: Node, caster: Node2D, duration: float) -> Node2D:
	if not is_instance_valid(caster):
		return null
	var fx := _spawn(host)
	if fx == null:
		return null
	var spr := Sprite2D.new()
	spr.texture = load(RING_TEX)
	spr.centered = true
	spr.scale = Vector2(1.15, 1.15)
	spr.modulate = Color(QI.r, QI.g, QI.b, 0.72)
	spr.z_index = 4
	var core := Sprite2D.new()
	core.texture = load(RING_TEX)
	core.centered = true
	core.scale = Vector2(0.34, 0.34)
	core.modulate = Color(0.92, 1.0, 1.0, 0.75)
	core.material = SkillFx.additive_material()
	core.z_index = 5
	fx.add_child(core)
	fx.add_child(spr)
	fx.global_position = caster.global_position + Vector2(0.0, -40.0)
	var tw := fx.create_tween()
	tw.tween_property(spr, "rotation", PI * 0.8, duration)
	tw.parallel().tween_property(spr, "scale", Vector2(1.35, 1.35), duration)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, duration)
	tw.tween_callback(fx.queue_free)
	return fx


## 化劲释放 / 气浪：一圈气墙 + 外扩环 + 尘土
static func play_release(host: Node, pos: Vector2, radius: float, strong: bool) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	for i in 3:
		var r := fx._qi_ring(Vector2.ZERO, radius, 0.30, 0.55 if i == 0 else 0.35)
		var tw := r.create_tween()
		tw.tween_interval(0.06 * float(i))
		tw.tween_property(r, "scale", r.scale * 1.18, 0.34)
		tw.parallel().tween_property(r, "modulate:a", 0.0, 0.34)
	fx._dust_burst(Vector2.ZERO, 14 if strong else 8)
	fx._spark(Vector2.ZERO, QI_HI, 12 if strong else 6, 200.0)
	fx._free_in(0.55)


## 踏罡·缩地：起点云气散开 → 终点云气重聚（形成"化云遁走"的位移感）
static func play_cloud_step(host: Node, from: Vector2, to: Vector2, delay_to: float = 0.0) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	# 起点：云气向外散
	for i in 10:
		var ang := randf() * TAU
		var off := Vector2(cos(ang), sin(ang)) * randf_range(6.0, 26.0)
		var puff := Sprite2D.new()
		puff.texture = SkillFx.smoke_texture()
		puff.centered = true
		puff.position = from + off
		puff.scale = Vector2(0.18, 0.18)
		puff.modulate = Color(0.72, 0.90, 0.95, 0.55)
		puff.z_index = 35
		fx.add_child(puff)
		var tw := puff.create_tween()
		tw.tween_property(puff, "position", from + off * 3.2, 0.28)
		tw.parallel().tween_property(puff, "scale", Vector2(0.44, 0.44), 0.28)
		tw.parallel().tween_property(puff, "modulate:a", 0.0, 0.28)
	# 终点：云气从四周向落点收拢
	for i in 10:
		var ang := randf() * TAU
		var off := Vector2(cos(ang), sin(ang)) * randf_range(36.0, 74.0)
		var puff := Sprite2D.new()
		puff.texture = SkillFx.smoke_texture()
		puff.centered = true
		puff.position = to + off
		puff.scale = Vector2(0.34, 0.34)
		puff.modulate = Color(0.76, 0.94, 1.0, 0.0)
		puff.z_index = 35
		fx.add_child(puff)
		var tw := puff.create_tween()
		tw.tween_interval(delay_to)
		tw.tween_property(puff, "position", to + off * 0.12, 0.22)
		tw.parallel().tween_property(puff, "scale", Vector2(0.14, 0.14), 0.22)
		tw.parallel().tween_property(puff, "modulate:a", 0.7, 0.12)
		tw.tween_property(puff, "modulate:a", 0.0, 0.18)
	var rt := fx.create_tween()
	rt.tween_interval(delay_to)
	rt.tween_callback(func() -> void:
		if is_instance_valid(fx):
			fx._qi_ring(to, 36.0, 0.45, 0.35))
	fx._free_in(delay_to + 0.6)


static func play_step(host: Node, from: Vector2, to: Vector2) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	for i in 3:
		var t := float(i + 1) / 4.0
		var p := from.lerp(to, t)
		var s := fx._streak(p + Vector2(0.0, -40.0), 0.35, QI)
		s.rotation = (to - from).angle() + PI * 0.5
	fx._qi_ring(to, 55.0, 0.30, 0.55)
	fx._free_in(0.4)


## 气爆·周天：按环数加强的大爆
static func play_burst(host: Node, pos: Vector2, radius: float, rings: int) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	var power := 1.0 + 0.28 * float(maxi(0, rings))
	for i in 3:
		var r := fx._qi_ring(Vector2.ZERO, radius * (0.55 + 0.2 * float(i)), 0.38, 0.5)
		var tw := r.create_tween()
		tw.tween_interval(0.05 * float(i))
		tw.tween_property(r, "scale", r.scale * (1.25 * power), 0.4)
		tw.parallel().tween_property(r, "modulate:a", 0.0, 0.4)
	fx._dot(Vector2.ZERO, 1.6, Color(1, 1, 1, 0.95), 0.18)
	fx._dot(Vector2.ZERO, 2.6, Color(QI_HI.r, QI_HI.g, QI_HI.b, 0.55), 0.30)
	fx._column(Vector2.ZERO, 220.0 * power, 0.45)
	fx._spark(Vector2.ZERO, QI_HI, 14 + rings * 4, 240.0 * power)
	fx._dust_burst(Vector2.ZERO, 16)
	fx._free_in(0.7)


## 吐纳：贴在施法者身上的气柱 + 治疗绿点（返回节点）
static func play_breath(host: Node, caster: Node2D, duration: float) -> Node2D:
	if not is_instance_valid(caster):
		return null
	var fx := _spawn(host)
	if fx == null:
		return null
	fx.global_position = caster.global_position
	for k in 3:
		var rr := fx._qi_ring(Vector2.ZERO, 70.0 + 26.0 * float(k), 0.40, duration * 0.9)
		var rt := rr.create_tween()
		rt.tween_property(rr, "scale", rr.scale * 1.25, duration * 0.9)
	var col := fx._column(Vector2.ZERO, 200.0, duration * 0.9, HEAL)
	col.z_index = 2
	var tw := fx.create_tween()
	tw.tween_property(col, "modulate:a", 0.0, duration)
	fx._rise_motes(Vector2(0.0, -10.0), 8, HEAL, duration)
	fx._free_in(duration + 0.3)
	return fx


## 二阶段气海：原地留一片气域（3 秒），主环随持续时间淡出 + 三圈脉冲
static func attach_field(host: Node, pos: Vector2, radius: float, duration: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	var main := fx._qi_ring(Vector2.ZERO, radius, 0.30, duration)
	var tw := main.create_tween()
	tw.tween_property(main, "rotation", TAU, duration)
	tw.parallel().tween_property(main, "scale", main.scale * 1.04, duration)
	for i in 3:
		var t := fx.create_tween()
		t.tween_interval(0.9 * float(i))
		t.tween_callback(func() -> void:
			if is_instance_valid(fx):
				fx._qi_ring(Vector2.ZERO, radius, 0.28, 0.5))
	fx._free_in(duration + 0.2)


static func play_heal(host: Node, pos: Vector2, _amount: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	fx._qi_ring(Vector2.ZERO, 60.0, 0.35, 0.6)
	fx._rise_motes(Vector2(0.0, -10.0), 10, HEAL, 0.5)
	fx._free_in(0.6)


# ===================== 零件 =====================

func _free_in(sec: float) -> void:
	if not is_inside_tree():
		return
	get_tree().create_timer(maxf(0.1, sec)).timeout.connect(queue_free)


func _qi_ring(pos: Vector2, radius: float, alpha: float, life: float) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = load(RING_TEX)
	spr.centered = true
	spr.position = pos
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2(radius * 2.0 / 256.0, radius * 2.0 / 256.0)
	spr.modulate = Color(QI.r, QI.g, QI.b, minf(1.0, alpha * 1.6))
	spr.z_index = 3
	add_child(spr)
	# 白热内圈：让环有"能量"而不是一根细线
	var core := Sprite2D.new()
	core.texture = spr.texture
	core.centered = true
	core.position = pos
	core.material = SkillFx.additive_material()
	core.scale = spr.scale * 0.965
	core.modulate = Color(0.92, 0.99, 1.0, minf(0.9, alpha * 1.1))
	core.z_index = 4
	add_child(core)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, life)
	tw.parallel().tween_property(core, "modulate:a", 0.0, life)
	return spr


func _band(a: Vector2, b: Vector2, thickness: float, color: Color, delay: float, life: float) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.streak_texture()
	spr.centered = true
	spr.global_position = (a + b) * 0.5
	spr.rotation = (b - a).angle() + PI * 0.5
	var len := maxf((b - a).length(), 2.0)
	spr.scale = Vector2(thickness / 64.0, len / 256.0)
	spr.modulate = color
	spr.material = SkillFx.additive_material()
	spr.z_index = 3
	add_child(spr)
	var tw := spr.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(spr, "modulate:a", 0.0, life)
	return spr


func _streak(pos: Vector2, alpha: float, color: Color) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.streak_texture()
	spr.centered = true
	spr.position = pos
	spr.scale = Vector2(0.5, 0.9)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.material = SkillFx.additive_material()
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, 0.25)
	return spr


func _column(pos: Vector2, height: float, life: float, color: Color = QI) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.streak_texture()
	spr.centered = false
	spr.position = pos + Vector2(0.0, -height)
	spr.scale = Vector2(0.9, height / 256.0)
	spr.modulate = Color(color.r, color.g, color.b, 0.55)
	spr.material = SkillFx.additive_material()
	spr.z_index = 2
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, life)
	return spr


func _mote(a: Vector2, b: Vector2, color: Color, delay: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.dot_texture()
	spr.centered = true
	spr.position = a
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2(0.13, 0.13)
	spr.modulate = Color(color.r, color.g, color.b, 0.9)
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(spr, "position", b, 0.22)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.22)


func _dot(pos: Vector2, scale_v: float, color: Color, life: float) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.dot_texture()
	spr.centered = true
	spr.position = pos
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2(scale_v, scale_v)
	spr.modulate = color
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, life)
	return spr


func _spark(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		var ang := TAU * float(i) / float(maxi(1, count)) + randf() * 0.3
		var dir := Vector2(cos(ang), sin(ang))
		var spr := Sprite2D.new()
		spr.texture = SkillFx.dot_texture()
		spr.centered = true
		spr.position = pos
		spr.material = SkillFx.additive_material()
		spr.scale = Vector2(0.11, 0.11)
		spr.modulate = color
		spr.z_index = 4
		add_child(spr)
		var tw := spr.create_tween()
		tw.tween_property(spr, "position", pos + dir * speed, 0.28)
		tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.28)


func _dust_burst(pos: Vector2, count: int) -> void:
	for i in count:
		var ang := randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var spr := Sprite2D.new()
		spr.texture = SkillFx.smoke_texture()
		spr.centered = true
		spr.position = pos + dir * 8.0
		spr.scale = Vector2(0.24, 0.24)
		spr.modulate = Color(0.30, 0.40, 0.44, 0.45)
		spr.z_index = 1
		add_child(spr)
		var tw := spr.create_tween()
		tw.tween_property(spr, "position", pos + dir * randf_range(28.0, 50.0), 0.36)
		tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.36)


func _rise_motes(pos: Vector2, count: int, color: Color, life: float = 0.45) -> void:
	for i in count:
		var off := Vector2(randf_range(-28.0, 28.0), randf_range(-6.0, 6.0))
		var spr := Sprite2D.new()
		spr.texture = SkillFx.dot_texture()
		spr.centered = true
		spr.position = pos + off
		spr.material = SkillFx.additive_material()
		spr.scale = Vector2(0.10, 0.10)
		spr.modulate = Color(color.r, color.g, color.b, 0.8)
		spr.z_index = 4
		add_child(spr)
		var tw := spr.create_tween()
		tw.tween_property(spr, "position", pos + off + Vector2(0.0, -70.0), life)
		tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
