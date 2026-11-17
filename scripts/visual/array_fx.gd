class_name ArrayFx
extends Node2D
## 定阵先生「阵旗」一族的表现层（2026-10-28 三色版）。
##
## 与其它 BOSS 的分界：这里只出现「阵」的语言 —— 绞绳、阵钉、阵柱、方框牢笼、
## 旗影与阵纹；颜色永远取旗型（朱砂 / 墨 / 石青），不借用刀光、兽爪、八卦、太极。
## 所有形状按真实判定画：线沿旗→旗、封印在阵心、解阵落在每面旗上、剑气落在预警圈里。

const CORD_TEX := "res://assets/effects/skills/array_line.png"
const RING_TEX := "res://assets/effects/skills/flag_warn_ring.png"


static func kind_color(kind: int) -> Color:
	if kind >= 0 and kind < 3:
		return Color(ArtDB.ARRAY_FLAG_KIND_COLORS[kind])
	return Color(0.96, 0.84, 0.58, 1.0)


static func _spawn(host: Node) -> ArrayFx:
	if host == null or not host.is_inside_tree():
		return null
	var fx := ArrayFx.new()
	host.add_child(fx)
	return fx


# ===================== 入口 =====================

## 插旗：落点一圈同色阵纹 + 四枚阵钉 + 尘土（旗本体由调用方生成）
static func play_plant(host: Node, pos: Vector2, kind: int) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	var c := kind_color(kind)
	fx._ring(Vector2.ZERO, 48.0, c, 0.42, 0.95)
	for i in 4:
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		fx._dot(Vector2(cos(ang), sin(ang)) * 48.0, 0.26,
			Color(0.96, 0.84, 0.58, 1.0), 0.36)
	fx._dust_burst(Vector2.ZERO, 7)
	fx._free_in(0.65)


## 引阵：每段一根绳（不再拆半），颜色取整段 / 多数色
static func play_line(host: Node, segments: Array) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	for raw in segments:
		var h: Dictionary = raw
		var a: Vector2 = h["a"]
		var b: Vector2 = h["b"]
		var k := int(h.get("kind", 0))
		var c := kind_color(k)
		fx._band(a, b, 4.0, Color(1.0, 0.94, 0.86, 0.95), 0.0, 0.30)
		fx._band(a, b, 15.0, Color(c.r, c.g, c.b, 0.28), 0.0, 0.30)
		fx._dot(a, 0.30, Color(0.96, 0.84, 0.58, 1.0), 0.30)
		fx._dot(b, 0.30, Color(0.96, 0.84, 0.58, 1.0), 0.30)
		if k != 2:
			for i in 2:
				fx._mote(a, b, c, 0.06 + 0.10 * float(i))
	fx._free_in(0.55)


## 五旗区域雷击：一道折线雷落到目标脚下，配柔边环与火花
static func play_thunder(host: Node, pos: Vector2, color: Color) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	var glow_c := color.lerp(Color(1.0, 0.82, 0.34, 1.0), 0.72)
	var core := Color(1.0, 0.98, 0.90, 1.0)
	# 直接用白/金 Line2D，不借朱砂绳贴图：避免雷光被绳的红色吞掉
	var straight := PackedVector2Array([Vector2(0.0, -300.0), Vector2.ZERO])
	var zig := PackedVector2Array([
		Vector2(12.0, -260.0), Vector2(-16.0, -190.0), Vector2(10.0, -140.0),
		Vector2(-12.0, -90.0), Vector2(8.0, -40.0), Vector2.ZERO,
	])
	var specs: Array = [
		[straight, 22.0, Color(glow_c.r, glow_c.g, glow_c.b, 0.30)],
		[straight, 6.0, Color(1.0, 0.98, 0.88, 0.72)],
		[zig, 18.0, Color(glow_c.r, glow_c.g, glow_c.b, 0.36)],
		[zig, 5.0, core],
	]
	for spec in specs:
		var line := Line2D.new()
		line.points = spec[0]
		line.width = float(spec[1])
		line.default_color = spec[2]
		line.antialiased = true
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.material = SkillFx.additive_material()
		line.z_index = 4
		fx.add_child(line)
	fx._ring(Vector2.ZERO, 66.0, glow_c, 0.30, 0.72)
	fx._dot(Vector2.ZERO, 1.00, Color(1.0, 0.97, 0.80, 0.95), 0.26)
	fx._dot(Vector2.ZERO, 0.42, Color(1.0, 1.0, 1.0, 1.0), 0.18)
	fx._spark(Vector2.ZERO, glow_c, 12, 180.0)
	fx._free_in(0.36)


## 卷阵：旗从旧位被拉回身侧，沿途一道旗色绳
static func play_pull(host: Node, from: Vector2, to: Vector2, kind: int) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	var c := kind_color(kind)
	fx._band(from, to, 5.0, Color(c.r, c.g, c.b, 0.55), 0.0, 0.36)
	fx._band(from, to, 16.0, Color(c.r, c.g, c.b, 0.22), 0.0, 0.36)
	fx._flag_ghost(from, kind, 0.85, 0.34, from, to)
	fx._free_in(0.6)


## 封阵：方框牢笼（内接正方形）+ 真实 210 圆 + 四角阵柱 + 每跳一次脉冲
static func play_seal(host: Node, center: Vector2, radius: float, kind: int,
		ticks: int, interval: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = center
	var c := kind_color(kind)
	var half := radius * 0.707
	# 真实判定圆（淡）
	fx._ring(Vector2.ZERO, radius, c, 0.55, 0.30)
	# 牢笼方框 + 四角柱
	var corners: Array = [Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		fx._band(a, b, 4.0, Color(c.r, c.g, c.b, 0.85), 0.0, 1.0)
		fx._pillar(a, kind, 0.55)
		fx._dot(a, 0.30, Color(0.96, 0.84, 0.58, 1.0), 0.35)
	for i in maxi(1, ticks):
		fx._pulse(i, float(i) * interval, radius, c)
	fx._free_in(float(ticks) * interval + 0.8)


## 解阵：每面旗原地起一根阵柱 + 旗色爆环（判定半径 140）
static func play_burst(host: Node, flags: Array) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	for f in flags:
		var pos: Vector2 = f["pos"]
		var kind := int(f["kind"])
		var c := kind_color(kind)
		fx._pillar(pos, kind, 0.9)
		fx._ring(pos, 140.0, c, 0.45, 0.85)
		fx._spark(pos, c, 10, 150.0)
		fx._dot(pos, 0.55, Color(c.r, c.g, c.b, 1.0), 0.30)
	fx._free_in(0.8)


## 攻旗轰击：天降一道朱砂剑气（预警圈由 BOSS 自己画，这里只画落地）
static func play_bombard(host: Node, pos: Vector2) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	var c := Color(1.0, 0.52, 0.32, 1.0)
	fx._streak_fall(pos, c, 8.0, 230.0)
	fx._ring(pos, 58.0, c, 0.28, 0.95)
	fx._spark(pos, c, 7, 130.0)
	fx._free_in(0.45)


## 三攻·万剑汇聚：三道剑气错开 0.15 秒落向同一点（每道 0.8×，与判定同拍）
static func play_swords(host: Node, pos: Vector2) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	var c := Color(0.98, 0.42, 0.32, 1.0)
	for i in 3:
		var tw := fx.create_tween()
		tw.tween_interval(0.15 * float(i))
		tw.tween_callback(func() -> void:
			if not is_instance_valid(fx):
				return
			fx._streak_fall(pos, c, 12.0, 300.0)
			fx._ring(pos, 92.0, c, 0.30, 0.95)
			fx._spark(pos, c, 12, 190.0))
	fx._free_in(0.9)


## 三困·定身锁：六枚墨色锁扣从外向内合拢，中心一枚暗环（零伤害）
static func play_lock(host: Node, pos: Vector2, radius: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = pos
	var c := Color(0.40, 0.36, 0.34, 1.0)
	fx._ring(Vector2.ZERO, radius, c, 0.6, 0.55)
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var start := Vector2(cos(ang), sin(ang)) * (radius * 0.85)
		var end := Vector2(cos(ang), sin(ang)) * (radius * 0.28)
		var bar := fx._band(start, start + Vector2(18.0, 0.0), 10.0,
			Color(c.r, c.g, c.b, 0.95), 0.0, 0.42)
		bar.rotation = ang
		var tw := fx.create_tween()
		tw.tween_property(bar, "position", end, 0.22).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(bar, "modulate:a", 0.0, 0.22)
	fx._free_in(0.65)


## 扫阵：三色阵纹组成的扇形（16 段绞绳，红/墨/石青循环），弧长与张角 = 判定
static func play_sweep(host: Node, origin: Vector2, dir: Vector2, reach: float, arc_deg: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	fx.global_position = origin
	var base := dir.angle()
	var half := deg_to_rad(arc_deg) * 0.5
	var r := reach * 0.98
	var segs := 16
	for i in segs:
		var a0 := base - half + (2.0 * half) * float(i) / float(segs)
		var a1 := base - half + (2.0 * half) * float(i + 1) / float(segs)
		var p0 := Vector2(cos(a0), sin(a0)) * r
		var p1 := Vector2(cos(a1), sin(a1)) * r
		var k := i % 3
		var c := kind_color(k)
		fx._band(p0, p1, 7.0, Color(c.r, c.g, c.b, 0.55), 0.0, 0.34)
		if i % 4 == 0:
			fx._dot(p0, 0.24, Color(0.96, 0.84, 0.58, 1.0), 0.30)
	fx._ring(Vector2.ZERO, reach * 0.5, Color(0.96, 0.84, 0.58, 0.55), 0.26, 0.5)
	fx._free_in(0.5)


## 踏阵：起手位一圈阵纹、沿途三道残旗、落点判定环
static func play_step(host: Node, from: Vector2, to: Vector2, kind: int) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	var c := kind_color(kind)
	fx._ring(from, 40.0, c, 0.35, 0.8)
	for i in 3:
		var t := float(i + 1) / 4.0
		fx._flag_ghost(from.lerp(to, t), kind, 0.42 - 0.10 * float(i), 0.30,
			from.lerp(to, t), from.lerp(to, t))
	fx._ring(to, 110.0, c, 0.30, 0.85)
	fx._dust_burst(from, 6)
	fx._free_in(0.55)


## 垒旗：阵钉砸地 + 内接方框 + 120 判定环
static func play_pile(host: Node, pos: Vector2, dir: Vector2, radius: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	var c := Color(0.96, 0.82, 0.56, 1.0)
	fx._streak_fall(pos, c, 16.0, 130.0)
	fx._ring(pos, radius, c, 0.35, 0.9)
	var half := radius * 0.707
	var corners: Array = [Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)]
	for i in 4:
		fx._band(pos + corners[i], pos + corners[(i + 1) % 4], 5.0,
			Color(c.r, c.g, c.b, 0.7), 0.0, 0.5)
	fx._dust_burst(pos, 12)
	fx._spark(pos, c, 10, 160.0)
	fx._free_in(0.6)


# ===================== 零件 =====================

func _free_in(sec: float) -> void:
	if not is_inside_tree():
		return
	get_tree().create_timer(maxf(0.1, sec)).timeout.connect(queue_free)


func _ring(pos: Vector2, radius: float, color: Color, life: float, alpha: float) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.ring_texture()
	spr.centered = true
	spr.position = pos
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2(radius * 2.0 / 256.0, radius * 2.0 / 256.0)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 2
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.12, life)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
	return spr


func _band(a: Vector2, b: Vector2, thickness: float, color: Color,
		delay: float, life: float) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = load(CORD_TEX)
	spr.centered = true
	spr.material = SkillFx.additive_material()
	spr.global_position = (a + b) * 0.5
	spr.rotation = (b - a).angle()
	var len := maxf((b - a).length(), 2.0)
	spr.scale = Vector2(len / 256.0, thickness / 40.0)
	spr.modulate = color
	spr.z_index = 3
	add_child(spr)
	var tw := spr.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(spr, "modulate:a", 0.0, life)
	return spr


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
	tw.parallel().tween_property(spr, "scale", Vector2(scale_v * 0.6, scale_v * 0.6), life)
	return spr


func _mote(a: Vector2, b: Vector2, color: Color, delay: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.dot_texture()
	spr.centered = true
	spr.position = a
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2(0.14, 0.14)
	spr.modulate = Color(color.r, color.g, color.b, 0.9)
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(spr, "position", b, 0.20)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.20)


func _spark(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		var ang := TAU * float(i) / float(maxi(1, count)) + randf() * 0.3
		var dir := Vector2(cos(ang), sin(ang))
		var spr := Sprite2D.new()
		spr.texture = SkillFx.dot_texture()
		spr.centered = true
		spr.position = pos
		spr.material = SkillFx.additive_material()
		spr.scale = Vector2(0.12, 0.12)
		spr.modulate = color
		spr.z_index = 4
		add_child(spr)
		var tw := spr.create_tween()
		tw.tween_property(spr, "position", pos + dir * speed, 0.26)
		tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.26)


func _dust_burst(pos: Vector2, count: int) -> void:
	for i in count:
		var ang := randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var spr := Sprite2D.new()
		spr.texture = SkillFx.smoke_texture()
		spr.centered = true
		spr.position = pos + dir * 10.0
		spr.scale = Vector2(0.22, 0.22)
		spr.modulate = Color(0.35, 0.30, 0.26, 0.55)
		spr.z_index = 1
		add_child(spr)
		var tw := spr.create_tween()
		tw.tween_property(spr, "position", pos + dir * randf_range(30.0, 52.0), 0.35)
		tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.35)


func _pillar(pos: Vector2, kind: int, life: float) -> void:
	var c := kind_color(kind)
	var top := pos + Vector2(0.0, -150.0)
	_band(pos, top, 9.0, Color(c.r, c.g, c.b, 0.60), 0.0, life)
	_band(pos, top, 22.0, Color(c.r, c.g, c.b, 0.18), 0.0, life)
	_dot(pos, 0.40, Color(c.r, c.g, c.b, 1.0), life)


func _streak_fall(pos: Vector2, color: Color, thickness: float, height: float) -> void:
	var top := pos + Vector2(0.0, -height)
	var spr := Sprite2D.new()
	spr.texture = SkillFx.streak_texture()
	spr.centered = true
	spr.global_position = top + Vector2(0.0, height * 0.5)
	spr.scale = Vector2(thickness / 64.0, height / 256.0)
	spr.modulate = Color(color.r, color.g, color.b, 0.95)
	spr.material = SkillFx.additive_material()
	spr.z_index = 4
	add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, 0.16)


func _flag_ghost(pos: Vector2, kind: int, alpha: float, life: float,
		from: Vector2, to: Vector2) -> void:
	var path := String(ArtDB.ARRAY_FLAG_TEXTURES.get(kind, ""))
	if path == "":
		return
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.centered = true
	spr.position = pos + Vector2(0.0, -20.0)
	spr.scale = Vector2(0.28, 0.28)
	spr.modulate = Color(1, 1, 1, alpha)
	spr.z_index = 3
	add_child(spr)
	var tw := spr.create_tween()
	if from.distance_to(to) > 1.0:
		tw.tween_property(spr, "global_position", to + Vector2(0.0, -20.0), life)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)


func _pulse(index: int, delay: float, radius: float, color: Color) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(self):
			return
		_ring(Vector2.ZERO, radius, color, 0.34, 0.9)
		_dot(Vector2.ZERO, 0.6, Color(color.r, color.g, color.b, 0.9), 0.26))
