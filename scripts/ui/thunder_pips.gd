class_name ThunderPips
extends Control
## 雷势读数（赫连霄机制）：三枚小雷印，点亮几枚 = 当前几层雷势。
## BOSS 头顶与玩家机制徽记带共用同一套图形，不写文字。

@export var pip_count: int = 3
@export var lit: int = 0
@export var lit_color: Color = Color(0.86, 0.70, 1.0, 1.0)
@export var dim_color: Color = Color(0.28, 0.28, 0.36, 0.90)

const PIP_W := 15.0
const PIP_H := 18.0
const GAP := 3.0
const ROW_H := 18.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_row_width(), ROW_H)
	size = custom_minimum_size


func set_state(count: int) -> void:
	lit = clampi(count, 0, pip_count)
	custom_minimum_size = Vector2(_row_width(), ROW_H)
	size = custom_minimum_size
	queue_redraw()


func _row_width() -> float:
	return float(pip_count) * PIP_W + float(maxi(0, pip_count - 1)) * GAP


func _draw() -> void:
	var total := _row_width()
	var cx := (size.x - total) * 0.5 + PIP_W * 0.5
	var cy := size.y * 0.5
	for i in range(pip_count):
		_draw_bolt(Vector2(cx, cy), i < lit)
		cx += PIP_W + GAP


func _draw_bolt(c: Vector2, on: bool) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-2.4, -8.4), c + Vector2(3.4, -8.4),
		c + Vector2(0.2, -1.2), c + Vector2(5.4, -1.2),
		c + Vector2(-3.2, 8.4), c + Vector2(-0.8, 1.2),
		c + Vector2(-5.6, 1.2),
	])
	if not on:
		draw_colored_polygon(pts, dim_color)
		return
	draw_circle(c, 8.2, Color(lit_color.r, lit_color.g, lit_color.b, 0.16))
	draw_colored_polygon(pts, lit_color)
	# 内芯提亮：让点亮的那枚在小尺寸下也能看出是“雷”
	var inner := PackedVector2Array([
		c + Vector2(-0.8, -5.6), c + Vector2(2.0, -5.6),
		c + Vector2(-0.4, 0.0), c + Vector2(2.6, 0.0),
		c + Vector2(-1.6, 5.6), c + Vector2(-0.2, 0.4),
		c + Vector2(-3.0, 0.4),
	])
	draw_colored_polygon(inner, Color(1.0, 0.96, 0.82, 0.85))
