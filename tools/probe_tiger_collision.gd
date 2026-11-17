extends Node
## 虎妖碰撞体自检（2026-10-28）：
##   物理胶囊必须贴住立绘轮廓、脚底以下没有空白；受击球投影到脚底平面供扇形判定。
## 用法：godot --headless --path . res://tools/probe_tiger_collision.tscn

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _visible_bbox(skin: SkinVisual) -> Rect2:
	var rig: Node = skin.render_node
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for n in rig.find_children("*", "Sprite2D", true, false):
		var spr := n as Sprite2D
		if spr == null or spr.texture == null:
			continue
		var used := spr.texture.get_image().get_used_rect()
		var ts := spr.texture.get_size()
		var p0 := Vector2(used.position)
		var p1 := Vector2(used.end)
		var h := ts * 0.5
		for c in [p0 - h, Vector2(p1.x, p0.y) - h, p1 - h, Vector2(p0.x, p1.y) - h]:
			var p: Vector2 = skin.to_local(spr.global_transform * c)
			mn = mn.min(p)
			mx = mx.max(p)
	return Rect2(mn, mx - mn)


func _ready() -> void:
	print("\n########## 虎妖碰撞体探针 ##########")
	var boss: Node = (load("res://scenes/boss/boss.tscn") as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)

	var cs := boss.get_node("CollisionShape2D") as CollisionShape2D
	var cap := cs.shape as CapsuleShape2D
	_check(cap != null, "碰撞体是胶囊")
	if cap == null:
		get_tree().quit(1)
		return
	_check(is_equal_approx(cap.radius, 72.0) and is_equal_approx(cap.height, 270.0),
		"胶囊尺寸 72×270", "%s×%s" % [cap.radius, cap.height])
	_check(cs.position.is_equal_approx(Vector2(0.0, -75.0)), "胶囊中心 y=−75", str(cs.position))
	_check(absf(wrapf(cs.rotation - PI * 0.5, -PI, PI)) < 0.001, "胶囊横置 90°", str(cs.rotation))

	var axis := cs.transform.basis_xform(Vector2(0.0, 1.0)).normalized()
	var half_len := cap.height * 0.5 - cap.radius
	var ex := absf(axis.x) * half_len + cap.radius
	var ey := absf(axis.y) * half_len + cap.radius
	var col_min := cs.position - Vector2(ex, ey)
	var col_max := cs.position + Vector2(ex, ey)
	print("物理包围盒 ", col_min, " .. ", col_max)

	var vis := _visible_bbox(boss.skin)
	print("立绘包围盒 ", vis.position, " .. ", vis.end)
	_check(col_min.x <= vis.position.x + 3.0 and col_max.x >= vis.end.x - 3.0,
		"胶囊横向盖住头尾", "col %s..%s / vis %s..%s" % [col_min.x, col_max.x, vis.position.x, vis.end.x])
	_check(col_min.y <= vis.position.y + 3.0 and col_max.y >= vis.end.y - 3.0,
		"胶囊纵向盖住身体", "col %s..%s / vis %s..%s" % [col_min.y, col_max.y, vis.position.y, vis.end.y])
	_check(col_max.y >= -6.0 and col_max.y <= 2.0,
		"碰撞底边贴脚底、下方无空白", "bottom=%s（脚底≈0）" % col_max.y)

	var spheres: Array = boss.hit_spheres()
	var sx_min := INF
	var sx_max := -INF
	var all_ground := true
	var all_r := true
	for sp in spheres:
		var sv: Vector3 = sp
		all_ground = all_ground and is_zero_approx(sv.y)
		all_r = all_r and is_equal_approx(sv.z, 72.0)
		sx_min = minf(sx_min, sv.x)
		sx_max = maxf(sx_max, sv.x)
	_check(spheres.size() >= 3, "受击球由胶囊采样", "n=%d" % spheres.size())
	_check(all_ground, "受击球全部投影到脚底平面")
	_check(all_r, "受击球半径 72")
	_check(sx_min <= -60.0 and sx_max >= 60.0, "受击球覆盖头尾", "%s..%s" % [sx_min, sx_max])
	_check(is_equal_approx(boss.body_radius(), 72.0), "本体厚度半径 72", str(boss.body_radius()))
	_check(is_equal_approx(boss.hit_radius(), 135.0), "外接半径 135", str(boss.hit_radius()))
	_check(is_zero_approx(boss.edge_distance_to(boss.global_position)), "脚底点在本体上")
	_check(boss.edge_distance_to(boss.global_position + Vector2(0.0, 200.0)) > 0.0,
		"脚下方 200px 已在本体外")

	boss._set_facing(Vector2.LEFT)
	await get_tree().process_frame
	_check(cs.position.x == 0.0 and absf(wrapf(cs.rotation - PI * 0.5, -PI, PI)) < 0.001,
		"朝左镜像后胶囊不变形", "%s rot=%s" % [cs.position, cs.rotation])
	var left_spheres: Array = boss.hit_spheres()
	_check(left_spheres.size() == spheres.size(), "朝左受击球数量不变")
	boss._set_facing(Vector2.RIGHT)
	await get_tree().process_frame
	boss.phase = 1
	_check(is_equal_approx(boss._damage_multiplier(), 1.0), "虎妖一阶段伤害 ×1.0")
	boss.phase = 2
	_check(is_equal_approx(boss._damage_multiplier(), 1.5), "虎妖二阶段伤害 ×1.5")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
