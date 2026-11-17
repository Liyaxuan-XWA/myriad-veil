class_name AlchemyHeatGauge
extends Control
## 炼丹火候刻度：指针来回扫，金色竖线是「炉心」
##
## 2026-10-28 改版：停火位置不再只判「成 / 败」，而是**分三档决定这一炉出几成**
##   （一株料 = 一颗丹，所以出数直接就是 投料株数 × 档位比例）。
## 判定与绘制共用下面三个常量，改一处就同步生效。

## 丹眼：正中，全成
const TIER_EYE := 0.08
## 偏温：约六成
const TIER_WARM := 0.16
## 偏猛：约三成；再偏就尽毁
const TIER_HOT := 0.26

var needle := 0.0
var target := 0.5


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 76.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(p_needle: float, p_target: float) -> void:
	needle = p_needle
	target = p_target
	queue_redraw()


## 停火位置的成数比例（0.0 = 尽毁）
func ratio_for(p_needle: float) -> float:
	var a := absf(p_needle - target)
	if a <= TIER_EYE:
		return 1.0
	if a <= TIER_WARM:
		return 0.66
	if a <= TIER_HOT:
		return 0.33
	return 0.0


func tier_text(p_needle: float) -> String:
	var a := absf(p_needle - target)
	if a <= TIER_EYE:
		return "丹眼正火"
	if a < target:
		return "火候偏文"
	return "火候偏武"


func _draw() -> void:
	var x0 := 8.0
	var x1 := maxf(size.x - 8.0, x0 + 1.0)
	var w := x1 - x0
	var cy := size.y * 0.5

	# 炉温轨道：墨槽 + 金线
	var track := Rect2(x0, cy - 15.0, w, 30.0)
	draw_rect(track, Color(0.095, 0.10, 0.135, 0.98))
	draw_rect(track, Color(0.48, 0.40, 0.26, 0.72), false, 1.0)

	# 三档色带：由宽到窄叠上去，越靠炉心越亮
	var tiers: Array = [
		[TIER_HOT, Color(0.86, 0.42, 0.18, 0.20)],
		[TIER_WARM, Color(0.92, 0.68, 0.24, 0.26)],
		[TIER_EYE, Color(0.34, 0.82, 0.48, 0.36)],
	]
	for t in tiers:
		var half: float = t[0]
		var col: Color = t[1]
		draw_rect(Rect2(x0 + (target - half) * w, cy - 15.0, half * 2.0 * w, 30.0), col)
		draw_rect(Rect2(x0 + (target - half) * w, cy + 5.0, half * 2.0 * w, 10.0),
			Color(col.r, col.g, col.b, col.a * 0.55))

	# 刻度
	for i in 11:
		var tx := x0 + w * float(i) / 10.0
		var long := i % 5 == 0
		draw_line(Vector2(tx, cy + 15.0), Vector2(tx, cy + (22.0 if long else 19.0)),
			Color(1, 1, 1, 0.26 if long else 0.14), 1.0)
		draw_line(Vector2(tx, cy - 15.0), Vector2(tx, cy - (19.0 if long else 17.0)),
			Color(1, 1, 1, 0.16 if long else 0.08), 1.0)

	# 炉心基准线
	var gx := x0 + target * w
	draw_line(Vector2(gx, cy - 25.0), Vector2(gx, cy + 25.0), UIKit.C_GREAT, 3.0)
	draw_circle(Vector2(gx, cy), 9.0, Color(1.0, 0.85, 0.30, 0.10))
	draw_circle(Vector2(gx, cy), 15.0, Color(1.0, 0.78, 0.20, 0.05))

	# 指针：颜色跟着当前档位走，扫过丹眼时先变绿
	var ratio := ratio_for(needle)
	var col := UIKit.C_OK if ratio >= 1.0 else (UIKit.C_ACCENT if ratio > 0.0 else UIKit.C_TEXT)
	var nx := x0 + needle * w
	draw_circle(Vector2(nx, cy), 10.0, Color(col.r, col.g, col.b, 0.10))
	draw_line(Vector2(nx, cy - 22.0), Vector2(nx, cy + 22.0), col, 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(nx - 7.0, cy - 31.0), Vector2(nx + 7.0, cy - 31.0), Vector2(nx, cy - 21.0),
	]), col)

	# 三档标注：写在色带里，不往轨道外伸（外面是提示行与出炉盘的位置）
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(x0 + (target - TIER_EYE) * w, cy + 4.0),
		"全成", HORIZONTAL_ALIGNMENT_CENTER, TIER_EYE * 2.0 * w, 10,
		Color(0.62, 0.95, 0.68, 0.95))
	draw_string(font, Vector2(x0 + (target - TIER_WARM) * w, cy + 4.0),
		"六成", HORIZONTAL_ALIGNMENT_CENTER, (TIER_WARM - TIER_EYE) * 2.0 * w, 10,
		Color(0.96, 0.80, 0.40, 0.85))
	draw_string(font, Vector2(x0 + (target + TIER_EYE) * w, cy + 4.0),
		"六成", HORIZONTAL_ALIGNMENT_CENTER, (TIER_WARM - TIER_EYE) * 2.0 * w, 10,
		Color(0.96, 0.80, 0.40, 0.85))
	draw_string(font, Vector2(x0 + (target - TIER_HOT) * w, cy + 4.0),
		"三成", HORIZONTAL_ALIGNMENT_CENTER, (TIER_HOT - TIER_WARM) * 2.0 * w, 10,
		Color(0.92, 0.58, 0.34, 0.8))
	draw_string(font, Vector2(x0 + (target + TIER_WARM) * w, cy + 4.0),
		"三成", HORIZONTAL_ALIGNMENT_CENTER, (TIER_HOT - TIER_WARM) * 2.0 * w, 10,
		Color(0.92, 0.58, 0.34, 0.8))
