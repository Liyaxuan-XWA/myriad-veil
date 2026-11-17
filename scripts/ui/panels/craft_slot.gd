class_name CraftDropZone
extends Control
## 舞台上的投料口（丹炉炉口 / 符台皮匣）
##
## 只负责两件事：接住拖拽、把「空 / 有料 / 玩法中 / 悬停可投」画出来。
## 判定与数据全在 CraftStage —— 这里绝不碰材料，避免拖错就丢东西。

var stage: Node = null
var label_text := ""
var material_name := ""
var doses := 0
var accent := Color(0.95, 0.82, 0.45)
var _state := "load"
var _hover_ok := false


func setup(p_stage: Node, rect: Rect2, p_label: String, p_accent: Color) -> void:
	stage = p_stage
	label_text = p_label
	accent = p_accent
	position = rect.position
	size = rect.size
	custom_minimum_size = rect.size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_visual(p_material: String, p_doses: int) -> void:
	material_name = p_material
	doses = p_doses
	queue_redraw()


func set_state(next: String) -> void:
	_state = next
	_hover_ok = false
	queue_redraw()


## 拖拽悬停预判：能投 → 金环，不能投 → 红环（仍然返回 true 接住，交给 CraftStage 给原因）
func set_preview(ok: bool) -> void:
	_hover_ok = ok
	queue_redraw()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if stage == null or _state != "load":
		return false
	if not (data is Dictionary):
		return false
	if String((data as Dictionary).get("kind", "")) != "craft_material":
		return false
	var mid := String((data as Dictionary).get("id", ""))
	set_preview(bool(stage.call("can_accept", mid)))
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if stage != null and is_instance_valid(stage):
		stage.call("add_dose", String((data as Dictionary).get("id", "")))
	_hover_ok = false
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_hover_ok = false
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var rx := size.x * 0.5 - 4.0
	var ry := size.y * 0.5 - 4.0
	var playing := _state == "play"
	var loaded := doses > 0

	# 炉口内的暖光：有料比空炉亮，玩法时再抬一档
	var glow_a := 0.30 if not playing else 0.52
	if not loaded and not playing:
		glow_a = 0.14
	draw_colored_polygon(_ellipse_points(c, Vector2(rx * 0.86, ry * 0.80)),
		Color(1.0, 0.62, 0.26, glow_a))

	# 环：空=虚线提示，有料=实线，悬停=金/红
	var ring_col: Color = accent if not _hover_ok else UIKit.C_OK
	if _hover_ok == false and _state == "load" and not loaded:
		ring_col = Color(accent.r, accent.g, accent.b, 0.42)
	if _state == "blocked":
		ring_col = UIKit.C_DANGER
	for i in 24:
		if _state == "load" and not loaded and i % 2 == 1:
			continue
		var a0 := TAU * float(i) / 24.0
		var a1 := TAU * float(i + 1) / 24.0
		draw_line(_ellipse_point(c, Vector2(rx, ry), a0),
			_ellipse_point(c, Vector2(rx, ry), a1),
			Color(ring_col.r, ring_col.g, ring_col.b, 0.85), 2.0)

	var font := ThemeDB.fallback_font
	var text := label_text
	if loaded:
		text = "%s ×%d" % [material_name, doses]
	if playing:
		text = "炉已封 · 停手看火候"
	draw_string(font, Vector2(0, size.y - 10), text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 14,
		Color(0.96, 0.92, 0.80, 0.95) if loaded or playing else Color(0.78, 0.74, 0.66, 0.75))


func _ellipse_point(center: Vector2, radii: Vector2, angle: float) -> Vector2:
	return center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)


func _ellipse_points(center: Vector2, radii: Vector2, steps: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		pts.append(_ellipse_point(center, radii, TAU * float(i) / float(steps)))
	pts.append(pts[0])
	return pts
