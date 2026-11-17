class_name MechanicPips
extends Control
## 机制徽记条 —— 用图形而不是文字读数（第一个使用者：玩家头顶的两仪势）
##
## 一排 N 枚「阴阳玉佩」+ 一个可选的单字徽记：
##   · 点亮几枚 = 几层势；
##   · 玉佩颜色 = 当前仪态（阳 = 金、阴 = 青，颜色由调用方从 DebuffDB 的阳印 / 阴印取，
##     与 BOSS 头顶那两个标记同一份色，不再各处硬写）；
##   · 「逆」字 = 两仪转挂上的「下一招必定逆式」。
##
## 它不自己决定位置：调用方把它塞进玩家头顶的机制徽记带（VBoxContainer），
## 新机制再加一行就自动往上排，位置已经留好。

## 玉佩数量（势的上限）
@export var bead_count: int = 3
## 点亮的枚数
@export var lit: int = 0
## 点亮色（= 当前仪态颜色）
@export var lit_color: Color = Color(1.0, 0.84, 0.46, 1.0)
## 空槽描边色
@export var dim_color: Color = Color(0.32, 0.34, 0.40, 0.9)
## 单字徽记（空 = 不画），例如「逆」
@export var marker: String = ""
## 徽记颜色
@export var marker_color: Color = Color(1.0, 0.88, 0.45, 1.0)

const BEAD_R := 6.5       ## 玉佩半径
const BEAD_GAP := 4.0     ## 玉佩间距
const MARGIN := 2.0       ## 行内左右留白
const MARKER_W := 13.0    ## 单字徽记的占位宽
const ROW_H := 17.0       ## 一行的高度
const MARKER_FONT := 11   ## 单字徽记字号

## 玉佩整体偏左还是居中（居中时读起来更像挂在身上的佩饰）
var _centered: bool = true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_row_width(), ROW_H)


## 刷新读数（调用方每次状态变化后喊一次）
func set_state(lit_count: int, color_on: Color, marker_text: String = "") -> void:
	lit = clampi(lit_count, 0, bead_count)
	lit_color = color_on
	marker = marker_text
	custom_minimum_size = Vector2(_row_width(), ROW_H)
	queue_redraw()


func _row_width() -> float:
	var w := MARGIN * 2.0 + bead_count * BEAD_R * 2.0 + maxf(0.0, float(bead_count - 1)) * BEAD_GAP
	if marker != "":
		w += MARKER_W
	return w


func _draw() -> void:
	var cy := size.y * 0.5
	var total := _row_width()
	var cx := (size.x - total) * 0.5 + MARGIN + BEAD_R if (_centered and size.x > total) \
			else MARGIN + BEAD_R
	for i in range(bead_count):
		_draw_bead(Vector2(cx, cy), i < lit)
		cx += BEAD_R * 2.0 + BEAD_GAP
	if marker == "":
		return
	# 单字徽记：描边 + 正文，保证压在亮背景上也读得清
	var font := get_theme_default_font()
	var pos := Vector2(cx + 1.0, cy + BEAD_R * 0.62)
	draw_string_outline(font, pos, marker, HORIZONTAL_ALIGNMENT_LEFT, -1, MARKER_FONT, 2,
			Color(0.02, 0.02, 0.03, 0.95))
	draw_string(font, pos, marker, HORIZONTAL_ALIGNMENT_LEFT, -1, MARKER_FONT, marker_color)


## 一枚玉佩：墨底 + 亮色半边 + 鱼眼 + 金边；未点亮只剩一圈暗色轮廓
func _draw_bead(c: Vector2, on: bool) -> void:
	if not on:
		draw_circle(c, BEAD_R, Color(0.10, 0.11, 0.14, 0.55))
		draw_circle(c, BEAD_R, dim_color, false, 1.0)
		return
	draw_circle(c, BEAD_R + 1.8, Color(lit_color.r, lit_color.g, lit_color.b, 0.16))
	draw_circle(c, BEAD_R, Color(0.09, 0.10, 0.13, 0.95))
	_draw_half_disc(c, BEAD_R - 0.8, lit_color, true)
	draw_circle(c + Vector2(0.0, -(BEAD_R - 0.8) * 0.5), (BEAD_R - 0.8) * 0.3,
			Color(0.09, 0.10, 0.13, 0.95))
	draw_circle(c + Vector2(0.0, (BEAD_R - 0.8) * 0.5), (BEAD_R - 0.8) * 0.3, lit_color)
	draw_circle(c, BEAD_R, Color(1.0, 0.92, 0.62, 0.85), false, 1.1)


## 半圆盘（两仪的分界）：right_side = true 取右半，否则左半
func _draw_half_disc(c: Vector2, r: float, color: Color, right_side: bool) -> void:
	var a0 := -PI * 0.5 if right_side else PI * 0.5
	var a1 := PI * 0.5 if right_side else PI * 1.5
	var pts: PackedVector2Array = PackedVector2Array([c])
	for i in range(13):
		var a := lerpf(a0, a1, float(i) / 12.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)
