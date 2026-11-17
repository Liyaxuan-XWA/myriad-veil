class_name SunPips
extends Control
## 日冕读数（离照 · 逐日·天火）：三枚小日轮，点亮几枚 = 当前几层日冕。
## 玩家头顶机制带与离照头顶共用；marker 只在特殊状态出现（如「灼」「夺」「日」）。

@export var pip_count: int = 3
@export var lit: int = 0
@export var lit_color: Color = Color(1.0, 0.80, 0.36, 1.0)
@export var dim_color: Color = Color(0.34, 0.26, 0.22, 0.90)
@export var marker: String = ""
@export var marker_color: Color = Color(1.0, 0.62, 0.24, 1.0)

const PIP_R := 6.4
const GAP := 4.2
const MARGIN := 2.0
const MARKER_W := 13.0
const ROW_H := 17.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_row_width(), ROW_H)
	size = custom_minimum_size


func set_state(count: int, marker_text: String = "") -> void:
	lit = clampi(count, 0, pip_count)
	marker = marker_text
	custom_minimum_size = Vector2(_row_width(), ROW_H)
	size = custom_minimum_size
	queue_redraw()


func _row_width() -> float:
	var w := MARGIN * 2.0 + float(pip_count) * PIP_R * 2.0 \
		+ float(maxi(0, pip_count - 1)) * GAP
	if marker != "":
		w += MARKER_W
	return w


func _draw() -> void:
	var cy := size.y * 0.5
	var total := _row_width()
	var cx := (size.x - total) * 0.5 + MARGIN + PIP_R if size.x > total \
		else MARGIN + PIP_R
	for i in range(pip_count):
		_draw_sun(Vector2(cx, cy), i < lit)
		cx += PIP_R * 2.0 + GAP
	if marker == "":
		return
	var font := get_theme_default_font()
	var pos := Vector2(cx + 1.0, cy + PIP_R * 0.62)
	draw_string_outline(font, pos, marker, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 2,
		Color(0.02, 0.02, 0.03, 0.95))
	draw_string(font, pos, marker, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, marker_color)


func _draw_sun(c: Vector2, on: bool) -> void:
	if not on:
		draw_arc(c, PIP_R, 0.0, TAU, 18, dim_color, 1.0, true)
		return
	draw_circle(c, PIP_R + 2.2, Color(lit_color.r, lit_color.g, lit_color.b, 0.15))
	# 八道短日芒
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var p0 := c + Vector2(cos(a), sin(a)) * (PIP_R + 0.6)
		var p1 := c + Vector2(cos(a), sin(a)) * (PIP_R + 3.4)
		draw_line(p0, p1, Color(lit_color.r, lit_color.g, lit_color.b, 0.85), 1.2, true)
	draw_circle(c, PIP_R, lit_color)
	draw_circle(c, PIP_R * 0.52, Color(1.0, 0.96, 0.80, 0.95))
