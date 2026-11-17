class_name QiRingPips
extends Control
## 气环读数（太虚气君机制）：三枚小气环，点亮几枚 = 身上几枚气环。
## 与两仪势的玉佩条并排放在玩家头顶「机制徽记带」里，新机制继续往上排队。

@export var bead_count: int = 3
@export var lit: int = 0
@export var ring_color: Color = Color(0.56, 0.86, 1.0, 1.0)
@export var dim_color: Color = Color(0.30, 0.38, 0.44, 0.9)

const R := 6.5
const GAP := 4.0
const MARGIN := 2.0
const ROW_H := 17.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_row_width(), ROW_H)


func set_state(count: int) -> void:
	lit = clampi(count, 0, bead_count)
	custom_minimum_size = Vector2(_row_width(), ROW_H)
	queue_redraw()


func _row_width() -> float:
	return MARGIN * 2.0 + float(bead_count) * R * 2.0 + float(maxi(0, bead_count - 1)) * GAP


func _draw() -> void:
	var cy := size.y * 0.5
	var total := _row_width()
	var cx := (size.x - total) * 0.5 + MARGIN + R if size.x > total else MARGIN + R
	for i in range(bead_count):
		_draw_ring(Vector2(cx, cy), i < lit)
		cx += R * 2.0 + GAP


func _draw_ring(c: Vector2, on: bool) -> void:
	if not on:
		draw_arc(c, R, 0.0, TAU, 20, dim_color, 1.0, true)
		return
	draw_circle(c, R + 2.4, Color(ring_color.r, ring_color.g, ring_color.b, 0.14))
	draw_arc(c, R, 0.0, TAU, 24, ring_color, 2.0, true)
	# 内圈留一道缺口，读作"气在转"，和两仪的实心玉佩区分开
	draw_arc(c, R - 2.6, 0.4, TAU - 0.9, 20, Color(ring_color.r, ring_color.g, ring_color.b, 0.85), 1.2, true)
	draw_circle(c, 1.6, Color(ring_color.r, ring_color.g, ring_color.b, 0.95))
