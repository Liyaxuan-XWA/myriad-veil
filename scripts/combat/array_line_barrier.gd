class_name ArrayLineBarrier
extends Node2D
## 阵旗连线的物理阻挡层：每段旗线一个 StaticBody2D。
## 只挡对手 —— 施法者/友军不把自家线层放进自己的碰撞掩码（层由控制方传入）。
## 本节点没有视觉；线的绳/光由各控制方的 line sprite 负责。

const THICKNESS := 14.0
## 两端多探出一点，封住旗位接缝，避免斜缝漏人
const END_PAD := 10.0

var layer_bit: int = 0
var _bodies: Array[StaticBody2D] = []
var _shapes: Array[RectangleShape2D] = []


func setup(layer: int) -> void:
	layer_bit = layer
	for b in _bodies:
		if is_instance_valid(b):
			b.collision_layer = layer_bit


## segments: Array[[Node2D, Node2D]]，按旗的当前世界坐标同步
func sync(segments: Array) -> void:
	if segments.is_empty():
		clear()
		return
	while _bodies.size() < segments.size():
		var body := StaticBody2D.new()
		body.collision_layer = layer_bit
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		shape.shape = rect
		body.add_child(shape)
		add_child(body)
		_bodies.append(body)
		_shapes.append(rect)
	while _bodies.size() > segments.size():
		var body: StaticBody2D = _bodies.pop_back()
		_shapes.pop_back()
		body.queue_free()
	for i in segments.size():
		var seg: Array = segments[i]
		if seg.size() < 2 or not (seg[0] is Node2D) or not (seg[1] is Node2D):
			continue
		var a: Vector2 = (seg[0] as Node2D).global_position
		var b: Vector2 = (seg[1] as Node2D).global_position
		var v := b - a
		var length := v.length()
		var body: StaticBody2D = _bodies[i]
		var shape_node := body.get_child(0) as CollisionShape2D
		var rect: RectangleShape2D = _shapes[i]
		if length < 1.0:
			shape_node.set_deferred("disabled", true)
			continue
		shape_node.set_deferred("disabled", false)
		body.global_position = (a + b) * 0.5
		body.rotation = v.angle()
		rect.size = Vector2(length + END_PAD, THICKNESS)


func clear() -> void:
	for b in _bodies:
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()
	_shapes.clear()
