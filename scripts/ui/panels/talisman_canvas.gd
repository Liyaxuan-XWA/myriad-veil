class_name TalismanCanvas
extends Control
## 画符台：按住鼠标沿金色符路走笔，笔迹盖满符路即成符
##
## 判定用「轨迹覆盖」而不是逐点点击：符路预先采样成一串点，笔迹经过
## 判定半径内就算画到，因此可以分几笔描、描得歪一点；
## 代价是墨量有限（约为符路全长的 2.5 倍），乱涂会先把墨耗光。

signal completed
signal ink_empty

const TOLERANCE := 17.0
const STEP := 4.0
const COVERAGE_NEED := 0.92
const INK_MAX := 1600.0
## 符纸（长条）宽 / 与画布边缘的距离
const STRIP_W := 220.0
const STRIP_MARGIN := 18.0
const INK_BAR_H := 10.0

## 符路（符纸内归一化坐标）：竖脊 + 顶横 + 两道回勾 + 中横 + 底勾
const STROKES: Array = [
	[Vector2(0.50, 0.08), Vector2(0.50, 0.92)],
	[Vector2(0.22, 0.16), Vector2(0.78, 0.16)],
	[Vector2(0.22, 0.16), Vector2(0.22, 0.34), Vector2(0.34, 0.44)],
	[Vector2(0.78, 0.16), Vector2(0.78, 0.34), Vector2(0.66, 0.44)],
	[Vector2(0.30, 0.56), Vector2(0.70, 0.56)],
	[Vector2(0.38, 0.72), Vector2(0.50, 0.80), Vector2(0.64, 0.72)],
]

var _strokes: Array = STROKES
## 批量绘制：符纸后方叠纸，UI 另显示 ×N
var batch_count: int = 1
var _guide_polys: Array = []
var _guide := PackedVector2Array()
var _visited := PackedByteArray()
var _visited_count := 0
var _drawn: Array = []
var _ink := INK_MAX
var _active := false
var _drawing := false
var _done := false
var _cursor := Vector2.ZERO
var _paper_tex: Texture2D = null


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 270.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_paper_tex = UIKit.ui_texture(UIKit.TEX_TALISMAN_PAPER)
	resized.connect(_on_resized)


func _on_resized() -> void:
	if _active:
		_resample()


# ===================== 生命周期 =====================

## 每种符用独立符路；必须在 activate() 之前设置。
func set_strokes(strokes: Array) -> void:
	if strokes.is_empty():
		_strokes = STROKES
	else:
		_strokes = strokes


func set_batch_count(n: int) -> void:
	batch_count = maxi(1, n)
	queue_redraw()


func activate() -> void:
	_active = true
	_drawing = false
	_done = false
	_ink = INK_MAX
	_drawn.clear()
	_resample()
	queue_redraw()


func deactivate() -> void:
	_active = false
	_drawing = false
	queue_redraw()


func ink_ratio() -> float:
	return clampf(_ink / INK_MAX, 0.0, 1.0)


func coverage() -> float:
	if _guide.is_empty():
		return 0.0
	return float(_visited_count) / float(_guide.size())


# ===================== 输入 =====================

func _gui_input(event: InputEvent) -> void:
	if not _active or _done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_drawing = false
		accept_event()
	elif event is InputEventMouseMotion:
		_cursor = event.position
		if _drawing:
			_extend_stroke(event.position)
			accept_event()
		queue_redraw()


func _begin_stroke(p: Vector2) -> void:
	if not _active or _done or _ink <= 0.0:
		return
	_drawing = true
	_cursor = p
	_drawn.append(PackedVector2Array([p]))
	_mark(p)
	queue_redraw()


func _extend_stroke(p: Vector2) -> void:
	if not _active or _done or not _drawing or _drawn.is_empty():
		return
	var stroke: PackedVector2Array = _drawn[_drawn.size() - 1]
	if stroke.is_empty():
		return
	var last := stroke[stroke.size() - 1]
	var dist := last.distance_to(p)
	if dist < 1.5:
		return

	# 快速划动时沿途补点，避免判定漏掉中段
	var steps := maxi(int(dist / STEP), 1)
	for i in range(1, steps + 1):
		_mark(last.lerp(p, float(i) / float(steps)))

	stroke.append(p)
	_drawn[_drawn.size() - 1] = stroke
	_ink = maxf(_ink - dist, 0.0)

	if _ink <= 0.0:
		_active = false
		_drawing = false
		queue_redraw()
		ink_empty.emit()
		return
	if coverage() >= COVERAGE_NEED:
		_done = true
		_active = false
		_drawing = false
		queue_redraw()
		completed.emit()


## 笔迹经过符路采样点 → 记为已画到
func _mark(p: Vector2) -> void:
	for i in range(_guide.size()):
		if _visited[i] == 1:
			continue
		if _guide[i].distance_to(p) <= TOLERANCE:
			_visited[i] = 1
			_visited_count += 1


# ===================== 符路采样 =====================

func _strip_rect() -> Rect2:
	var inner_h := size.y - INK_BAR_H - 14.0
	var w := minf(STRIP_W, maxf(size.x - STRIP_MARGIN * 2.0, 10.0))
	return Rect2(Vector2((size.x - w) * 0.5, 4.0), Vector2(w, maxf(inner_h - 4.0, 10.0)))


func _resample() -> void:
	_guide_polys.clear()
	_guide.clear()
	_visited_count = 0
	if size.x < 40.0 or size.y < 60.0:
		return

	var strip := _strip_rect()
	# 符纸内再让出 16px 给纸边，符路不贴边
	var area := Rect2(strip.position + Vector2(16, 16), strip.size - Vector2(32, 32))
	for stroke in _strokes:
		var poly := PackedVector2Array()
		var prev := _map(stroke[0], area)
		poly.append(prev)
		_guide.append(prev)
		for i in range(1, stroke.size()):
			var cur := _map(stroke[i], area)
			var d := prev.distance_to(cur)
			var n := maxi(int(d / STEP), 1)
			for k in range(1, n + 1):
				var q := prev.lerp(cur, float(k) / float(n))
				poly.append(q)
				_guide.append(q)
			prev = cur
		_guide_polys.append(poly)

	_visited.resize(_guide.size())
	_visited.fill(0)


func _map(n: Vector2, area: Rect2) -> Vector2:
	return area.position + n * area.size


# ===================== 绘制 =====================

func _draw() -> void:
	var strip := _strip_rect()
	# 台面：暖墨木案，不是一块死黑
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.075, 0.068, 0.057, 0.97))
	for i in range(5):
		var rr := strip.get_center()
		draw_circle(rr, strip.size.y * (0.52 + 0.08 * float(i)),
			Color(0.92, 0.64, 0.30, 0.012))
	draw_rect(Rect2(Vector2(10, 10), size - Vector2(20, 20)),
		Color(0.52, 0.41, 0.25, 0.36), false, 1.0)
	for corner in [Vector2(10, 10), Vector2(size.x - 10, 10),
			Vector2(10, size.y - 10), Vector2(size.x - 10, size.y - 10)]:
		var dx := 16.0 if corner.x < size.x * 0.5 else -16.0
		var dy := 16.0 if corner.y < size.y * 0.5 else -16.0
		draw_line(corner, corner + Vector2(dx, 0), Color(0.78, 0.60, 0.32, 0.5), 1.0)
		draw_line(corner, corner + Vector2(0, dy), Color(0.78, 0.60, 0.32, 0.5), 1.0)

	# 批量：符纸后方叠纸（最多画 4 层，数字由 UI 标出）
	for i in range(mini(batch_count, 4) - 1, 0, -1):
		var off := Vector2(6.0 * float(i), 4.0 * float(i))
		draw_rect(Rect2(strip.position + off, strip.size), Color(0.72, 0.64, 0.48, 0.22))
		draw_rect(Rect2(strip.position + off, strip.size),
			Color(0.50, 0.15, 0.13, 0.28), false, 1.0)

	# 符纸：投影 + 纸纹 + 朱砂双线
	draw_rect(Rect2(strip.position + Vector2(5, 7), strip.size), Color(0, 0, 0, 0.36))
	if _paper_tex != null:
		draw_texture_rect(_paper_tex, strip, false, Color(1, 1, 1, 1))
	else:
		draw_rect(strip, Color(0.87, 0.81, 0.67, 0.98))
	draw_rect(strip, Color(0.50, 0.15, 0.13, 0.92), false, 2.0)
	draw_rect(Rect2(strip.position + Vector2(6, 6), strip.size - Vector2(12, 12)),
		Color(0.50, 0.15, 0.13, 0.32), false, 1.0)
	var line_col := Color(0.52, 0.16, 0.14, 0.55)
	draw_line(Vector2(strip.position.x + 12, strip.position.y + 11),
		Vector2(strip.end.x - 12, strip.position.y + 11), line_col, 1.0)
	draw_line(Vector2(strip.position.x + 12, strip.end.y - 11),
		Vector2(strip.end.x - 12, strip.end.y - 11), line_col, 1.0)

	# 右上角小朱印：纸上有「已开坛」的仪式感
	var seal := 22.0
	var seal_rect := Rect2(Vector2(strip.end.x - seal - 14, strip.position.y + 16),
		Vector2(seal, seal))
	draw_rect(seal_rect, Color(0.62, 0.20, 0.13, 0.92))
	draw_rect(seal_rect.grow(-4), Color(0.96, 0.90, 0.78, 0.45), false, 1.0)
	draw_line(seal_rect.position + Vector2(6, 11), seal_rect.position + Vector2(16, 11),
		Color(0.96, 0.90, 0.78, 0.50), 1.0)
	draw_line(seal_rect.position + Vector2(11, 6), seal_rect.position + Vector2(11, 16),
		Color(0.96, 0.90, 0.78, 0.50), 1.0)

	# 符路：未画到是淡金虚线，画到的点变成朱砂色
	for poly in _guide_polys:
		if poly.size() >= 2:
			draw_polyline(poly, Color(0.55, 0.36, 0.11, 0.50), 4.0)
	for i in range(_guide.size()):
		if _visited[i] == 1:
			draw_circle(_guide[i], 2.2, Color(0.74, 0.22, 0.16, 0.78))

	# 笔迹
	for s in _drawn:
		var poly: PackedVector2Array = s
		if poly.size() >= 2:
			draw_polyline(poly, Color(0.58, 0.09, 0.07, 0.96), 4.0)
	if _drawing:
		draw_circle(_cursor, 5.0, Color(0.58, 0.09, 0.07, 0.22))
		draw_circle(_cursor, 3.2, Color(0.58, 0.09, 0.07, 0.85))

	# 墨量条：金线墨槽，低于四分之一转赤
	var bar := Rect2(Vector2(12.0, size.y - INK_BAR_H - 5.0),
		Vector2(size.x - 24.0, INK_BAR_H))
	draw_rect(bar.grow(1), Color(0.46, 0.36, 0.22, 0.75), false, 1.0)
	draw_rect(bar, Color(0.075, 0.068, 0.058, 0.96))
	var ratio := ink_ratio()
	var col := Color(0.80, 0.61, 0.27, 0.95) if ratio > 0.25 else Color(0.95, 0.20, 0.15, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), col)
	if ratio > 0.0:
		draw_rect(Rect2(bar.position, Vector2(maxf(2.0, bar.size.x * ratio), 1.0)),
			Color(1.0, 0.94, 0.72, 0.5))
