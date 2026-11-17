class_name ForgeFx
extends Control
## 工坊演出层：火星、余烬、烟、冲击环、炉火呼吸。
## 纯代码绘制，不依赖序列帧；坐标是工坊世界坐标。

var furnace_pos := Vector2.ZERO
var fire_level := 1.0
var fire_enabled := true

var _t := 0.0
var _ember_acc := 0.0
var _sparks: Array = []
var _embers: Array = []
var _smoke: Array = []
var _rings: Array = []
var _flash: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if fire_enabled and furnace_pos != Vector2.ZERO:
		_ember_acc += delta * (1.8 + fire_level * 3.2)
		while _ember_acc >= 1.0:
			_ember_acc -= 1.0
			_spawn_ember(furnace_pos + Vector2(randf_range(-26, 26), randf_range(-18, 8)),
				Vector2(randf_range(-8, 8), randf_range(-44, -18)),
				randf_range(0.8, 1.6), 2.0)
	_update_particles(delta)
	queue_redraw()


func _update_particles(delta: float) -> void:
	for arr in [_sparks, _embers, _smoke, _rings, _flash]:
		var i := 0
		while i < arr.size():
			var p: Dictionary = arr[i]
			p["life"] = float(p.get("life", 0.0)) - delta
			if float(p["life"]) <= 0.0:
				arr.remove_at(i)
				continue
			var pos: Vector2 = p.get("p", Vector2.ZERO)
			var vel: Vector2 = p.get("v", Vector2.ZERO)
			var kind := String(p.get("kind", ""))
			if kind == "spark" or kind == "ember" or kind == "trail":
				vel.y += float(p.get("gravity", 260.0)) * delta
				vel *= 0.985
			elif kind == "smoke":
				vel *= 0.97
			p["p"] = pos + vel * delta
			p["v"] = vel
			arr[i] = p
			i += 1


func spawn_strike(pos: Vector2, color: Color = Color(1.0, 0.68, 0.26, 1.0),
		count: int = 22, strength: float = 1.0) -> void:
	for i in count:
		var a := randf_range(PI * 0.95, PI * 2.05)
		var sp := randf_range(140.0, 420.0) * strength
		_sparks.append({
			"kind": "spark", "p": pos + Vector2(randf_range(-10, 10), randf_range(-6, 4)),
			"v": Vector2(cos(a), sin(a)) * sp,
			"life": randf_range(0.30, 0.72), "max": 0.72,
			"size": randf_range(1.8, 4.0), "gravity": randf_range(280, 520),
			"color": color.lerp(Color(1.0, 0.96, 0.70), randf_range(0.0, 0.62)),
		})
	for i in 5:
		_smoke.append({
			"kind": "smoke", "p": pos + Vector2(randf_range(-16, 16), randf_range(-10, 2)),
			"v": Vector2(randf_range(-26, 26), randf_range(-28, -10)),
			"life": randf_range(0.7, 1.4), "max": 1.4,
			"size": randf_range(14, 30), "color": Color(0.56, 0.50, 0.42, 0.20),
		})
	_rings.append({
		"kind": "ring", "p": pos, "life": 0.40, "max": 0.40,
		"r0": 8.0, "r1": 72.0 * strength, "color": color,
	})
	# 命中瞬间的实心闪光：把「敲到了」这件事压在画面上
	_flash.append({
		"kind": "flash", "p": pos, "life": 0.16, "max": 0.16,
		"size": 34.0 * strength, "color": color,
	})


func spawn_crystal_trail(from: Vector2, to: Vector2) -> void:
	for i in 3:
		var start := from + Vector2(randf_range(-18, 18), randf_range(-10, 10))
		var mid := start.lerp(to, 0.55) + Vector2(randf_range(-30, 30), randf_range(-55, -18))
		_trails(start, mid, to)
		_spawn_ember(start, (mid - start).normalized() * 80.0, 0.55, 2.2,
			Color(0.42, 0.78, 0.86, 0.95))


func _trails(a: Vector2, b: Vector2, c: Vector2) -> void:
	# 把弧线离散成少量余烬，画出「晶石飞入砧面」的轨迹
	for i in 5:
		var t := float(i) / 4.0
		var p := a.lerp(b, t).lerp(b.lerp(c, t), t)
		_spawn_ember(p, Vector2.ZERO, 0.42, 1.8, Color(0.46, 0.82, 0.90, 0.8), 0.0)


func spawn_melt(pos: Vector2) -> void:
	for i in 4:
		_rings.append({
			"kind": "ring", "p": pos + Vector2(randf_range(-30, 30), randf_range(-12, 12)),
			"life": 0.8 + i * 0.18, "max": 1.4,
			"r0": 24.0, "r1": 170.0 + i * 26.0,
			"color": Color(1.0, 0.56, 0.20, 0.75),
		})
	spawn_strike(pos, Color(1.0, 0.62, 0.20, 1.0), 34, 1.7)


func spawn_treasure(pos: Vector2) -> void:
	for i in 28:
		var a := randf_range(0, TAU)
		_sparks.append({
			"kind": "spark", "p": pos + Vector2(randf_range(-16, 16), randf_range(-16, 16)),
			"v": Vector2(cos(a), sin(a)) * randf_range(40, 140),
			"life": randf_range(0.5, 1.2), "max": 1.2,
			"size": randf_range(1.0, 2.4), "gravity": -20.0,
			"color": Color(1.0, 0.84, 0.42, 0.95),
		})
	_rings.append({
		"kind": "ring", "p": pos, "life": 0.9, "max": 0.9,
		"r0": 12.0, "r1": 130.0, "color": Color(1.0, 0.84, 0.48, 0.9),
	})


func _spawn_ember(pos: Vector2, vel: Vector2, life: float, size: float,
		color: Color = Color(1.0, 0.55, 0.20, 0.8), gravity: float = 26.0) -> void:
	_embers.append({
		"kind": "ember", "p": pos, "v": vel, "life": life, "max": life,
		"size": size, "gravity": gravity, "color": color,
	})


func _draw() -> void:
	# 炉火呼吸：画在原画火苗上方，只做加法感的高光，不盖住原画
	if fire_enabled and furnace_pos != Vector2.ZERO:
		var pulse := 0.78 + 0.22 * sin(_t * 3.2) + 0.06 * sin(_t * 8.7)
		var f := fire_level * pulse
		for i in 3:
			var r := (22.0 + i * 12.0) * f
			var c := Color(1.0, 0.48 + i * 0.08, 0.10, 0.05 + 0.025 * f)
			draw_circle(furnace_pos + Vector2(0, -6 - i * 4), r, c)

	for p in _smoke:
		var u: float = 1.0 - float(p["life"]) / maxf(0.001, float(p["max"]))
		var col: Color = p["color"]
		col.a *= (1.0 - u) * 0.9
		draw_circle(p["p"], float(p["size"]) * (1.0 + u * 1.4), col)

	for p in _embers:
		var u: float = 1.0 - float(p["life"]) / maxf(0.001, float(p["max"]))
		var col: Color = p["color"]
		col.a *= (1.0 - u) * 0.95
		draw_circle(p["p"], float(p["size"]) * (1.0 - u * 0.5), col)
		draw_circle(p["p"], float(p["size"]) * 2.6, Color(col.r, col.g, col.b, col.a * 0.10))

	for p in _rings:
		var u: float = 1.0 - float(p["life"]) / maxf(0.001, float(p["max"]))
		var r: float = lerpf(float(p["r0"]), float(p["r1"]), u)
		var col: Color = p["color"]
		col.a *= (1.0 - u) * 0.9
		draw_arc(p["p"], r, 0.0, TAU, 36, col, maxf(1.0, 3.0 * (1.0 - u)))

	for p in _sparks:
		var u: float = 1.0 - float(p["life"]) / maxf(0.001, float(p["max"]))
		var col: Color = p["color"]
		col.a *= (1.0 - u)
		var pos: Vector2 = p["p"]
		var prev: Vector2 = pos - (p["v"] as Vector2) * 0.035
		draw_line(prev, pos, Color(col.r, col.g, col.b, col.a * 0.85),
			maxf(1.2, float(p["size"]) * (1.0 - u * 0.55)))
		draw_circle(pos, float(p["size"]) * 2.0, Color(col.r, col.g, col.b, col.a * 0.22))

	# 命中闪光画在最上层，火星之外再补一刀「白热」
	for p in _flash:
		var u: float = 1.0 - float(p["life"]) / maxf(0.001, float(p["max"]))
		var col: Color = p["color"]
		col.a *= (1.0 - u)
		var r: float = float(p["size"]) * (0.45 + u * 0.9)
		draw_circle(p["p"], r, Color(1.0, 0.96, 0.82, col.a * 0.55))
		draw_circle(p["p"], r * 0.45, Color(1.0, 1.0, 0.94, col.a * 0.9))
