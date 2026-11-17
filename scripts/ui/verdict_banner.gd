class_name VerdictBanner
extends Control
## 判词读数（玩家头顶）：BOSS 落下的律 + 剩余时间。
## 只有身上有判词时才显示；单律显示名字，双律显示「双律」（第二条看 debuff 栏）。
## 与雷势的三枚雷印分开：那是资源，这是“现在什么行为犯法”。

const ROW_W := 128.0
const ROW_H := 18.0
const FONT_SIZE := 11

var _ids: Array = []
var _seconds: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ROW_W, ROW_H)
	size = custom_minimum_size
	visible = false


func set_laws(ids: Array, seconds: float) -> void:
	var changed := ids != _ids
	_ids = ids.duplicate()
	_seconds = seconds
	var should_show := not _ids.is_empty()
	if visible != should_show:
		visible = should_show
	if changed or visible:
		queue_redraw()


func _draw() -> void:
	if _ids.is_empty():
		return
	var color := DebuffDB.color(String(_ids[0]))
	var cy := size.y * 0.5
	var text := ""
	if _ids.size() >= 2:
		text = "判词·双律"
	else:
		text = String(DebuffDB.display_name(String(_ids[0])))
	if _seconds > 0.0:
		text += " %.1fs" % _seconds
	var font := get_theme_default_font()
	# 左侧雷印：单律一枚，双律两枚
	var x := 4.0
	for i in range(mini(_ids.size(), 2)):
		var c := Vector2(x + 5.0, cy)
		var pts := PackedVector2Array([
			c + Vector2(-2.0, -5.5), c + Vector2(2.6, -5.5),
			c + Vector2(0.0, -0.6), c + Vector2(3.6, -0.6),
			c + Vector2(-2.4, 5.5), c + Vector2(-0.4, 0.8),
			c + Vector2(-4.0, 0.8),
		])
		draw_colored_polygon(pts, DebuffDB.color(String(_ids[i])))
		x += 13.0
	var pos := Vector2(x + 2.0, cy + 4.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3,
		Color(0.02, 0.02, 0.03, 0.95))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
