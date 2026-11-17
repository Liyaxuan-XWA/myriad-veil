extends Node
## 太极盘「接化发」自检（2026-10-29）：
##   护体期间敌弹进入身周 → 接住绕玩家一周 → 变我方攻击反打来源；
##   护体结束后不再接。
## 用法：godot --headless --path . res://tools/probe_taiji_capture.tscn

class DummyBoss extends Node2D:
	var hits: Array = []

	func _ready() -> void:
		add_to_group("boss")

	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			_element: String = "", _from_projectile: bool = false) -> void:
		hits.append(amount)


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
	print("\n########## 太极盘接化发自检 ##########")
	var tpl := ItemDB.get_treasure_template("tr_taiji_pan")
	_check(String(tpl.get("active_type", "")) == "taiji_guard", "太极盘仍是护体主动")
	var lines: Array = ItemDB.treasure_effect_lines(CharacterData.make_treasure_instance(tpl))
	var copy_ok := false
	for line in lines:
		if String(line).contains("接化"):
			copy_ok = true
	_check(copy_ok, "法宝说明写明接化效果", str(lines.size()) + " 行")

	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	player.global_position = Vector2.ZERO
	player.invincible_timer = 0.0
	var dummy := DummyBoss.new()
	dummy.global_position = Vector2(600.0, 0.0)
	add_child(dummy)
	var spawner = (load("res://scenes/boss/domain_boss_02.tscn") as PackedScene).instantiate()
	spawner.global_position = Vector2(900.0, 0.0)
	add_child(spawner)
	await get_tree().process_frame
	await get_tree().process_frame
	spawner.set_physics_process(false)
	spawner.set_process(false)

	# 护体开启
	player.set("_taiji_guard_id", "tr_taiji_pan")
	player.set("_taiji_guard_left", 5.0)
	player.set("_taiji_guard_pct", 0.3)

	var proj := spawner.call("_spawn_projectile", "physical_projectile") as Area2D
	_check(proj != null, "BOSS 能生成敌弹")
	if proj == null:
		_finish()
		return
	proj.set("source", dummy)
	proj.set("damage", 77.0)
	proj.set("direction", Vector2.LEFT)
	proj.set("speed", 520.0)
	proj.global_position = Vector2(120.0, 0.0)
	_check(proj.is_in_group("enemy_projectile"), "敌弹已进 enemy_projectile 组")

	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(bool(proj.get("_capture_active")), "护体期间敌弹被接住")
	_check(int(proj.get("collision_mask")) == 0, "接住期间关闭碰撞",
		"mask=%d" % int(proj.get("collision_mask")))
	await get_tree().create_timer(0.25, true, false, true).timeout
	var orbit_d: float = player.global_position.distance_to(proj.global_position)
	_check(orbit_d > 40.0 and orbit_d < 180.0, "敌弹绕着玩家飞",
		"d=%.1f" % orbit_d)

	await get_tree().create_timer(0.65, true, false, true).timeout
	_check(bool(proj.get("is_deflected")), "绕完一圈后变为我方攻击")
	_check(is_equal_approx(float(proj.get("deflect_damage")), 77.0), "反打沿用敌弹伤害",
		str(proj.get("deflect_damage")))
	_check(int(proj.get("collision_mask")) == 2, "反打只检测 BOSS 层")
	proj.call("_on_body_entered", dummy)
	_check(dummy.hits.size() == 1 and is_equal_approx(float(dummy.hits[0]), 77.0),
		"反打命中 BOSS", str(dummy.hits))

	# 护体结束后不再接
	player.set("_taiji_guard_left", 0.0)
	var proj2 := spawner.call("_spawn_projectile", "physical_projectile") as Area2D
	proj2.set("source", dummy)
	proj2.set("direction", Vector2.LEFT)
	proj2.set("speed", 0.0)
	proj2.global_position = Vector2(120.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not bool(proj2.get("_capture_active")), "护体结束后不再接弹")

	_finish()


func _finish() -> void:
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
