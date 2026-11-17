class_name CalamityWheel
extends Control
## 三灾轮读数（玩家 / 晏无咎）：三色灾环 + 当前灾位 + 灾势 + 状态字。
## 玩家头顶机制带与 BOSS 头顶共用；不写具体数值，只给读条。

const C_WIND := Color(0.55, 0.84, 0.76, 1.0)
const C_FIRE := Color(1.0, 0.50, 0.22, 1.0)
const C_THUNDER := Color(0.72, 0.62, 1.0, 1.0)
const C_DIM := Color(0.42, 0.40, 0.46, 0.92)
const C_MARK := Color(1.0, 0.78, 0.34, 1.0)
const C_LOCK := Color(0.72, 0.66, 0.92, 1.0)
const C_WARN := Color(1.0, 0.42, 0.26, 1.0)

@export var large: bool = false
var element: String = ""
var momentum: int = 0
var marker: String = ""

const ROW_H := 18.0
const GAP := 3.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_width_for(), ROW_H + (2.0 if large else 0.0))
	size = custom_minimum_size


func set_state(el: String, stacks: int, mark: String = "") -> void:
	element = el
	momentum = clampi(stacks, 0, 3)
	marker = mark
	custom_minimum_size = Vector2(_width_for(), ROW_H + (2.0 if large else 0.0))
	size = custom_minimum_size
	queue_redraw()


func _width_for() -> float:
	var w := 6.0 + 18.0 + 18.0 + 26.0 + 4.0 + 3.0 * 7.0
	if marker != "":
		w += 15.0
	return w


func _draw() -> void:
	var r := 9.0 if large else 8.0
	var cy := size.y * 0.5
	var cx := r + 4.0
	_draw_ring(Vector2(cx, cy), r)
	var font := get_theme_default_font()
	var label := _element_short(element)
	var col := _element_color(element)
	draw_string_outline(font, Vector2(cx + r + 4.0, cy + 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 2, Color(0.02, 0.02, 0.03, 0.95))
	draw_string(font, Vector2(cx + r + 4.0, cy + 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	# 三枚灾势
	var px := cx + r + 4.0 + 17.0
	for i in range(3):
		var lit := i < momentum
		var c := C_MARK if lit else C_DIM
		draw_circle(Vector2(px, cy), 2.6 if lit else 2.1, c)
		if lit:
			draw_arc(Vector2(px, cy), 4.0, 0.0, TAU, 10, Color(C_MARK.r, C_MARK.g, C_MARK.b, 0.35), 1.0, true)
		px += 7.0
	if marker != "":
		var mc := C_MARK
		if marker == "锁":
			mc = C_LOCK
		elif marker == "危":
			mc = C_WARN
		draw_string_outline(font, Vector2(px + 1.0, cy + 4.0), marker,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 2, Color(0.02, 0.02, 0.03, 0.95))
		draw_string(font, Vector2(px + 1.0, cy + 4.0), marker,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mc)


func _draw_ring(c: Vector2, r: float) -> void:
	var cols := [C_WIND, C_FIRE, C_THUNDER]
	var els := ["wind", "fire", "thunder"]
	for i in range(3):
		var a0 := -PI * 0.5 + TAU * float(i) / 3.0
		var a1 := a0 + TAU / 3.0 - 0.10
		var lit := element == String(els[i])
		var col: Color = cols[i]
		if not lit:
			col = Color(col.r, col.g, col.b, 0.28)
		draw_arc(c, r, a0, a1, 12, col, 3.2 if lit else 2.0, true)
		if lit:
			# 当前灾位外侧一枚小箭头，方便远看
			var mid := (a0 + a1) * 0.5
			var p0 := c + Vector2(cos(mid), sin(mid)) * (r + 1.0)
			var p1 := c + Vector2(cos(mid), sin(mid)) * (r + 4.0)
			draw_line(p0, p1, Color(col.r, col.g, col.b, 0.9), 1.6, true)
	draw_circle(c, 2.2, Color(0.90, 0.86, 0.74, 0.9) if element != "" else C_DIM)


func _element_short(el: String) -> String:
	match el:
		"wind":
			return "风"
		"fire":
			return "火"
		"thunder":
			return "雷"
	return "未定"


func _element_color(el: String) -> Color:
	match el:
		"wind":
			return C_WIND
		"fire":
			return C_FIRE
		"thunder":
			return C_THUNDER
	return C_DIM
