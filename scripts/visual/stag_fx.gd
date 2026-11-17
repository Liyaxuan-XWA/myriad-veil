class_name StagFx
extends Node2D
## 云隐苍角的专属表现层：苔甲/古根/雾隐/鹿鸣。
## 与定阵先生的 ArrayFx 分开：这里只出现苔石、根须、寒雾与冷蓝角光。

const STONE := Color(0.34, 0.43, 0.37, 1.0)
const MOSS := Color(0.38, 0.62, 0.38, 1.0)
const MIST := Color(0.62, 0.86, 0.95, 1.0)
const ANTLER := Color(0.55, 0.90, 1.0, 1.0)


static func _spawn(host: Node) -> StagFx:
	if host == null or not host.is_inside_tree():
		return null
	var fx := StagFx.new()
	host.add_child(fx)
	return fx


static func _ring(fx: StagFx, pos: Vector2, radius: float, color: Color,
		life: float, alpha: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.ring_texture()
	spr.centered = true
	spr.position = pos
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2(radius * 2.0 / 256.0, radius * 2.0 / 256.0)
	spr.modulate = Color(color.r, color.g, color.b, alpha)
	spr.z_index = 3
	fx.add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.25, life)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, life)
	tw.tween_callback(spr.queue_free)


static func _dot(fx: StagFx, pos: Vector2, scale_v: float, color: Color, life: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = SkillFx.dot_texture()
	spr.centered = true
	spr.position = pos
	spr.material = SkillFx.additive_material()
	spr.scale = Vector2(scale_v, scale_v)
	spr.modulate = color
	spr.z_index = 4
	fx.add_child(spr)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 0.0, life)
	tw.parallel().tween_property(spr, "scale", spr.scale * 0.45, life)
	tw.tween_callback(spr.queue_free)


## 根须预警：苔绿柔环 + 几粒苔光；落点 = 判定中心
static func play_root_warn(host: Node, pos: Vector2, radius: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	_ring(fx, pos, radius, MOSS, 0.55, 0.52)
	for i in 5:
		var a := TAU * float(i) / 5.0
		_dot(fx, pos + Vector2(cos(a), sin(a)) * radius * 0.72, 0.16,
			Color(MOSS.r, MOSS.g, MOSS.b, 0.80), 0.45)
	fx.get_tree().create_timer(0.7, true).timeout.connect(fx.queue_free)


## 根须破土：一圈苔环 + 四条向上根须
static func play_root_burst(host: Node, pos: Vector2, radius: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	_ring(fx, pos, radius, MOSS, 0.30, 0.85)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var end := pos + Vector2(cos(a), sin(a)) * radius * 0.7
		var line := Line2D.new()
		line.points = PackedVector2Array([pos, pos + (end - pos) * 0.45 + Vector2(0, -18), end])
		line.width = 3.0
		line.default_color = Color(MOSS.r, MOSS.g, MOSS.b, 0.9)
		line.material = SkillFx.additive_material()
		line.z_index = 3
		fx.add_child(line)
	fx.get_tree().create_timer(0.34, true).timeout.connect(fx.queue_free)


## 雾步：旧位/新位两团寒雾，中间一道淡蓝残影
static func play_miststep(host: Node, from: Vector2, to: Vector2) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	_dot(fx, from, 1.25, Color(MIST.r, MIST.g, MIST.b, 0.30), 0.35)
	_dot(fx, to, 1.55, Color(MIST.r, MIST.g, MIST.b, 0.45), 0.35)
	_ring(fx, to, 62.0, MIST, 0.32, 0.55)
	fx.get_tree().create_timer(0.38, true).timeout.connect(fx.queue_free)


## 鹿鸣：两圈木色回声 + 角光
static func play_roar(host: Node, pos: Vector2, radius: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	_ring(fx, pos, radius * 0.45, MOSS, 0.55, 0.65)
	_ring(fx, pos, radius * 0.72, Color(0.52, 0.78, 0.50, 1.0), 0.62, 0.42)
	_dot(fx, pos + Vector2(0, -170), 0.30, ANTLER, 0.55)
	fx.get_tree().create_timer(0.7, true).timeout.connect(fx.queue_free)


## 雾隐起手：Boss 身上一圈冷雾 + 三团雾影的淡光
static func play_mist_enter(host: Node, pos: Vector2) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	_dot(fx, pos, 2.2, Color(MIST.r, MIST.g, MIST.b, 0.22), 0.5)
	_ring(fx, pos, 92.0, MIST, 0.5, 0.48)
	fx.get_tree().create_timer(0.55, true).timeout.connect(fx.queue_free)


## 雾爆：整片谷心的冷雾冲击
static func play_mist_burst(host: Node, pos: Vector2, radius: float) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	_dot(fx, pos, 3.0, Color(MIST.r, MIST.g, MIST.b, 0.26), 0.45)
	_ring(fx, pos, radius * 0.55, MIST, 0.5, 0.68)
	_ring(fx, pos, radius * 0.9, Color(0.45, 0.72, 0.9, 1.0), 0.62, 0.38)
	fx.get_tree().create_timer(0.7, true).timeout.connect(fx.queue_free)


## 苔甲片破碎：小范围苔石屑
static func play_plate_break(host: Node, pos: Vector2) -> void:
	var fx := _spawn(host)
	if fx == null:
		return
	_ring(fx, pos, 38.0, MOSS, 0.25, 0.72)
	_dot(fx, pos, 0.4, Color(STONE.r, STONE.g, STONE.b, 0.9), 0.25)
	fx.get_tree().create_timer(0.3, true).timeout.connect(fx.queue_free)
