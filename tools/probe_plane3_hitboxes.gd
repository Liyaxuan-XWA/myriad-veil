extends Node
## 赤霄界三 BOSS 碰撞箱 / 受击框对齐探针（2026-10-29）
## 用法：godot --headless --no-save --path . res://tools/probe_plane3_hitboxes.tscn
##
## 这里只验“数据口径”：场景碰撞体数量、受击球是否压到 y=0、横向覆盖范围。
## 视觉轮廓覆盖率由 tools/check_plane3_hitboxes.py 采样 alpha 像素计算。

class StubPlayer extends Node2D:
	var is_dead := false
	var is_dodging := false
	var is_teleporting := false
	var knockback_velocity := Vector2.ZERO
	func take_damage(_amount: float, _kind: String = "physical", _source: Node = null,
			_elem: String = "") -> void:
		pass
	func apply_debuff(_id: String, _duration: float, _quiet := false) -> bool:
		return true
	func calamity_state() -> String:
		return ""

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 赤霄界三 BOSS 碰撞 / 受击框 ##########")
	await get_tree().process_frame
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _sphere_extents(spheres: Array) -> Dictionary:
	var xmin := INF
	var xmax := -INF
	var ymax := 0.0
	for raw in spheres:
		var sv: Vector3 = raw
		xmin = minf(xmin, sv.x - sv.z)
		xmax = maxf(xmax, sv.x + sv.z)
		ymax = maxf(ymax, absf(sv.y))
	return {"xmin": xmin, "xmax": xmax, "ymax": ymax}


func _test(path: String, label: String, shapes: int, xmin: float, xmax: float,
		min_body: float = 42.0) -> void:
	var sp := StubPlayer.new()
	sp.add_to_group("player")
	add_child(sp)
	var boss: Node2D = (load(path) as PackedScene).instantiate()
	boss.set_physics_process(false)
	boss.set_process(false)
	add_child(boss)
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	var cols := boss.find_children("*", "CollisionShape2D", true, false)
	_check(cols.size() == shapes, label + " 碰撞体数量", "n=%d" % cols.size())
	var spheres: Array = boss.call("hit_spheres")
	var ext := _sphere_extents(spheres)
	_check(not spheres.is_empty(), label + " 受击球非空")
	_check(is_zero_approx(float(ext["ymax"])), label + " 受击球压到 y=0",
		"max|y|=%.2f" % float(ext["ymax"]))
	_check(float(ext["xmin"]) <= xmin, label + " 左缘覆盖", "xmin=%.1f" % float(ext["xmin"]))
	_check(float(ext["xmax"]) >= xmax, label + " 右缘覆盖", "xmax=%.1f" % float(ext["xmax"]))
	_check(float(boss.call("body_radius")) >= min_body, label + " 本体厚度达标",
		"r=%.1f >= %.0f" % [float(boss.call("body_radius")), min_body])
	# 非对称形状掉头时会被 _mirror_collision_shapes 按 x 镜像；验证左右缘互换
	boss.call("_set_facing", Vector2.RIGHT)
	var right_ext := _sphere_extents(boss.call("hit_spheres"))
	boss.call("_set_facing", Vector2.LEFT)
	var left_ext := _sphere_extents(boss.call("hit_spheres"))
	_check(absf(float(left_ext["xmin"]) + float(right_ext["xmax"])) < 2.0,
		label + " 掉头左缘镜像", "L %.1f / R %.1f" % [float(left_ext["xmin"]), float(right_ext["xmax"])])
	_check(absf(float(left_ext["xmax"]) + float(right_ext["xmin"])) < 2.0,
		label + " 掉头右缘镜像", "L %.1f / R %.1f" % [float(left_ext["xmax"]), float(right_ext["xmin"])])
	boss.queue_free()
	sp.queue_free()
	await get_tree().process_frame


func _run() -> void:
	# 赫连霄：10 圆 + 1 支铁笔胶囊；按 idle 剪影重拟（2026-10-30），左鼓/披风到 −86，右笔到 +42
	await _test("res://scenes/boss/domain_boss_03.tscn", "赫连霄", 11, -86.0, 41.0, 26.0)
	# 离照：4 圆；宽袖 −47…+55
	await _test("res://scenes/boss/domain_boss_03_b.tscn", "离照", 4, -45.0, 50.0)
	# 晏无咎：4 圆；破袍 −43…+41
	await _test("res://scenes/boss/domain_boss_03_c.tscn", "晏无咎", 5, -40.0, 38.0)
