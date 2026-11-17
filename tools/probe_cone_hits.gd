extends Node
## 蚀甲锥真实命中自检（2026-11-02 用户报「打不中人」）
## 用**真实目标场景**（位面 BOSS / 原型 BOSS / 大世界野修）跑物理飞行，
## 而不是直接调 _on_body_entered —— 以前那样测不出碰撞体对不上。
## 用法：godot --headless --path . tools/probe_cone_hits.tscn -- --no-save

const TREASURE_ID := "tr_shixi_zhui"
## 被测目标：[名字, 场景路径, 配置方式]
const TARGETS: Array = [
	["剑客 boss_01_c", "res://scenes/boss/domain_boss_01_c.tscn", "boss"],
	["太虚气君 boss_03_c", "res://scenes/boss/domain_boss_03_c.tscn", "boss"],
	["观澜 boss_04", "res://scenes/boss/domain_boss_04.tscn", "boss"],
	["执烛 boss_04_b", "res://scenes/boss/domain_boss_04_b.tscn", "boss"],
	["原型虎妖 boss", "res://scenes/boss/boss.tscn", "boss"],
	["大世界野修", "res://scenes/world/world_enemy.tscn", "cultivator"],
	["大世界灵兽", "res://scenes/world/world_enemy.tscn", "beast"],
]

var _passes := 0
var _fails: Array = []
var _p: Node2D


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 目标身体碰撞体在纵向上的覆盖区间（相对该节点原点，负值=原点上方）
func _body_y_span(body: Node2D) -> Vector2:
	var lo := 0.0
	var hi := 0.0
	var seen := false
	for cs in body.find_children("*", "CollisionShape2D", true, false):
		var shape2d := (cs as CollisionShape2D).shape as Shape2D
		if shape2d == null:
			continue
		var pos: Vector2 = (cs as CollisionShape2D).position
		var half := 0.0
		if shape2d is CircleShape2D:
			half = (shape2d as CircleShape2D).radius
		elif shape2d is CapsuleShape2D:
			var cap := shape2d as CapsuleShape2D
			# 旋转 90° = 横放胶囊，纵向只剩半径
			var rot := fmod(absf((cs as CollisionShape2D).rotation), PI)
			half = cap.radius if rot > PI * 0.25 and rot < PI * 0.75 else cap.height * 0.5
		elif shape2d is RectangleShape2D:
			half = (shape2d as RectangleShape2D).size.y * 0.5
		else:
			continue
		if not seen:
			lo = pos.y - half
			hi = pos.y + half
			seen = true
		else:
			lo = minf(lo, pos.y - half)
			hi = maxf(hi, pos.y + half)
	return Vector2(lo, hi) if seen else Vector2.ZERO


## 锥子圆心的飞行线：从玩家原点射向目标原点，命中那一帧圆心在目标原点。
## 判定体是 TreasureCone._ready() 里那根立柱（size 26×104，中心抬到 -42）
func _cone_y_span() -> Vector2:
	return Vector2(-42.0 - 52.0, -42.0 + 52.0)


func _ready() -> void:
	print("\n########## 蚀甲锥真实命中探针 ##########")
	await get_tree().process_frame
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	await get_tree().process_frame
	await get_tree().process_frame
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.global_position = Vector2.ZERO
	_p.max_mana = 9999.0
	_p.mana = 9999.0

	var tpl := ItemDB.get_treasure_template(TREASURE_ID)
	_check(not tpl.is_empty(), "蚀甲锥模板存在")
	var stats := ItemDB.treasure_active_stats({}, tpl)
	print("INFO  range=%s speed=%s" % [stats.get("range"), stats.get("speed")])

	for t in TARGETS:
		await _run_one(String(t[0]), String(t[1]), String(t[2]), tpl)

	# 真实战场里玩家与 BOSS 不同一条横线 / 目标会走位：这两种情形也必须命中
	await _run_offset_case(tpl)
	await _run_moving_case(tpl)
	# 演武场木桩（2026-11-02 用户报：锥子飞过去没反应）
	await _run_dummy_case(tpl)

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run_one(label: String, path: String, kind: String, tpl: Dictionary) -> void:
	print("\n-- ", label, " --")
	var node = (load(path) as PackedScene).instantiate()
	if node == null or not (node is Node2D):
		_check(false, "%s 场景实例化失败" % label)
		return
	var body := node as Node2D
	add_child(body)
	await get_tree().process_frame
	if kind == "cultivator" or kind == "beast":
		body.configure({"pos": Vector2(160.0, 0.0), "max_hp": 1000.0, "attack_power": 20.0,
			"visual_id": "player_liqingyun", "move_speed": 0.0, "aggro_range": 0.0,
			"leash_range": 2000.0, "skills": []},
			WorldEnemy.KIND_CULTIVATOR if kind == "cultivator" else WorldEnemy.KIND_BEAST,
			label)
	body.set_physics_process(false)
	body.global_position = Vector2(160.0, 0.0)
	await get_tree().physics_frame

	_check(body.is_in_group("boss"), "%s 在 boss 组（法宝索敌只查这一组）" % label)
	var span := _body_y_span(body)
	var cone := _cone_y_span()
	_check(overlaps(span, cone), "%s 身体碰撞与锥子飞行线有交集" % label,
		"身体 y∈[%.0f,%.0f] 锥心 y∈[%.0f,%.0f]" % [span.x, span.y, cone.x, cone.y])

	_p._summon_cooldowns.clear()
	_p.mana = 9999.0
	_p._start_corrode_treasure({}, tpl)
	for i in 24:
		await get_tree().physics_frame
	_check(bool(body.call("has_debuff", "shixi")), "%s 被锥子真实飞行命中" % label)
	body.queue_free()
	# 清掉可能残留的锥子
	for c in get_children():
		if c is TreasureCone:
			c.queue_free()
	await get_tree().process_frame


## 演武场木桩：StaticBody2D + 竖直胶囊（底边正好压在节点原点），
## 2026-11-02 用户报「锥子飞过去了但没反应」
func _run_dummy_case(tpl: Dictionary) -> void:
	print("\n-- 演武场木桩 --")
	for at in [Vector2(200.0, 0.0), Vector2(200.0, -160.0)]:
		var dummy = (load("res://scenes/combat/training_dummy.tscn") as PackedScene).instantiate()
		# ⚠ StaticBody2D 要先摆好位置再入树，并等两个物理帧：
		#   入树后再改位置，物理服务器还停在原地，探针会误判成「打不中」
		dummy.position = at
		add_child(dummy)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_p._summon_cooldowns.clear()
		_p.mana = 9999.0
		_p._start_corrode_treasure({}, tpl)
		var cones := 0
		var first: TreasureCone = null
		for c in get_children():
			if c is TreasureCone:
				cones += 1
				first = c as TreasureCone
		var shape_info := "无"
		if first != null:
			var kids: Array = first.find_children("*", "CollisionShape2D", true, false)
			if not kids.is_empty():
				var cs := kids[0] as CollisionShape2D
				shape_info = "%s pos=%s size=%s" % [
					str(cs.shape).split(":")[0], str(cs.position),
					str((cs.shape as RectangleShape2D).size) if cs.shape is RectangleShape2D else "-"]
		print("DIAG 掷出锥子数=", cones, " 形状=", shape_info,
			" mask=", 0 if first == null else int(first.collision_mask),
			" 木桩层=", int(dummy.get("collision_layer")),
			" 木桩是Static=", dummy is StaticBody2D)
		# 直接问物理服务器：这个位置上半径 40 的圆能不能查到木桩
		var space = _p.get_world_2d().direct_space_state
		var q := PhysicsShapeQueryParameters2D.new()
		var qq := CircleShape2D.new()
		qq.radius = 40.0
		q.shape = qq
		q.transform = Transform2D(0.0, dummy.global_position + Vector2(0.0, -42.0))
		q.collision_mask = 2
		q.collide_with_bodies = true
		q.collide_with_areas = false
		var hits: Array = space.intersect_shape(q, 8)
		print("DIAG intersect_shape(mask=2) 命中数=", hits.size(),
			" 含木桩=", hits.any(func(h): return h.get("collider") == dummy))
		for i in 30:
			await get_tree().physics_frame
		var d = dummy.get("debuffs")
		var held := d is Dictionary and float((d as Dictionary).get("shixi", 0.0)) > 0.0
		_check(held, "木桩 %s 被蚀甲锥钉上" % str(at),
			"身体 y∈[%.0f,%.0f] 碰撞层=%d" % [_body_y_span(dummy as Node2D).x,
				_body_y_span(dummy as Node2D).y, int(dummy.get("collision_layer"))])
		if not held:
			# 分开测：直接喂一次 body_entered，能挂上就是碰撞没报，挂不上就是处理函数被拦
			var probe_cone: TreasureCone = null
			for c in get_children():
				if c is TreasureCone:
					probe_cone = c as TreasureCone
			print("DIAG 飞行结束：锥子还在场上=", is_instance_valid(probe_cone),
				" 木桩=", dummy.global_position,
				"" if not is_instance_valid(probe_cone) else str(probe_cone.global_position))
			if probe_cone != null:
				probe_cone.call("_on_body_entered", dummy)
				var d2 = dummy.get("debuffs")
				print("DIAG 直接喂 body_entered 后挂上=",
					d2 is Dictionary and float((d2 as Dictionary).get("shixi", 0.0)) > 0.0)
		dummy.queue_free()
		await get_tree().process_frame


func overlaps(a: Vector2, b: Vector2) -> bool:
	return a.y >= b.x and b.y >= a.x


## 玩家与目标不在同一条横线（真实战场就是这样：BOSS 在画面上方）
func _run_offset_case(tpl: Dictionary) -> void:
	print("\n-- 斜向目标（不同 y）--")
	var body = (load("res://scenes/boss/domain_boss_04.tscn") as PackedScene).instantiate()
	add_child(body)
	await get_tree().process_frame
	(body as Node2D).set_physics_process(false)
	(body as Node2D).global_position = Vector2(240.0, -170.0)
	_p._summon_cooldowns.clear()
	_p.mana = 9999.0
	_p._start_corrode_treasure({}, tpl)
	for i in 28:
		await get_tree().physics_frame
	_check(bool(body.call("has_debuff", "shixi")), "斜着掷也能命中不同高度的目标")
	body.queue_free()
	await get_tree().process_frame


## 目标在缓慢横移（大世界里野修散步的速度）：飞行途中也该吃得到
func _run_moving_case(tpl: Dictionary) -> void:
	print("\n-- 慢速横移目标 --")
	var body = (load("res://scenes/world/world_enemy.tscn") as PackedScene).instantiate()
	add_child(body)
	await get_tree().process_frame
	var e := body as WorldEnemy
	e.configure({"pos": Vector2(150.0, -60.0), "max_hp": 1000.0, "attack_power": 20.0,
		"visual_id": "player_liqingyun", "move_speed": 120.0, "aggro_range": 0.0,
		"leash_range": 2000.0, "skills": []}, WorldEnemy.KIND_CULTIVATOR, "散步野修")
	e.global_position = Vector2(150.0, -60.0)
	e.set_physics_process(true)
	_p._summon_cooldowns.clear()
	_p.mana = 9999.0
	_p._start_corrode_treasure({}, tpl)
	for i in 20:
		await get_tree().physics_frame
	_check(bool(e.call("has_debuff", "shixi")), "目标慢速横移时仍能命中")
	e.queue_free()
	await get_tree().process_frame
