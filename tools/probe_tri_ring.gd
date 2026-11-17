extends Node
## 三元轮（原三灾轮）通用主动自检：三炁环身、轮转元素、8 次脉冲、翻倍范围、冷却，且不依赖 BOSS / 灾位。

class DummyEnemy extends Node2D:
	var hits: Array = []
	var elems: Array = []
	var debuffs: Array = []

	func _ready() -> void:
		add_to_group("boss")

	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			element: String = "", _from_projectile: bool = false) -> void:
		hits.append(amount)
		elems.append(element)

	func apply_debuff(id: String, _duration: float, _quiet := false) -> bool:
		debuffs.append(id)
		return true

	func has_debuff(_id: String) -> bool:
		return false


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
	print("\n########## 三元轮 · 通用三炁环身 ##########")
	var tpl := ItemDB.get_treasure_template("tr_sanzai_lun")
	_check(String(tpl.get("treasure_name", "")) == "三元轮", "显示名改为三元轮")
	_check(String(tpl.get("active_type", "")) == "tri_ring", "主动类型 tri_ring")
	var stats := ItemDB.treasure_active_stats({}, tpl)
	_check(String(stats.get("kind", "")) == "tri_ring", "主动数值类型")
	_check(is_equal_approx(float(stats.get("ratio", 0.0)), 0.65), "0.65 倍法强")
	_check(is_equal_approx(float(stats.get("radius", 0.0)), 240.0), "240 范围（翻倍）")
	_check(is_equal_approx(float(stats.get("interval", 0.0)), 1.0), "1 秒一轮（减半）")
	var lines := ItemDB.treasure_effect_lines(CharacterData.make_treasure_instance(tpl))
	_check(not lines.is_empty() and String(lines[0]).contains("三炁环绕身"),
		"说明写明三炁环身", str(lines))

	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.set_physics_process(false)
	p.set_process(false)
	p.global_position = Vector2.ZERO
	p.mana = 999.0
	var enemy := DummyEnemy.new()
	enemy.global_position = Vector2(60.0, 0.0)
	add_child(enemy)
	# 旧半径 120 打不到、新半径 240 打得到：直接证明「范围翻倍」生效
	var mid := DummyEnemy.new()
	mid.global_position = Vector2(200.0, 0.0)
	add_child(mid)
	var far := DummyEnemy.new()
	far.global_position = Vector2(400.0, 0.0)
	add_child(far)

	p._start_tri_ring_treasure(CharacterData.make_treasure_instance(tpl), tpl)
	_check(p._tri_ring_left > 7.0, "主动持续 8 秒")
	_check(is_equal_approx(p.mana, 979.0), "消耗 20 灵力", "mana=%.1f" % p.mana)
	_check(is_equal_approx(p.summon_cooldown_left("tr_sanzai_lun"), 40.0), "冷却 40 秒")
	_check(enemy.hits.size() == 1, "开主动立刻落第一跳", str(enemy.hits.size()))
	_check(enemy.elems.size() == 1 and String(enemy.elems[0]) == "wind", "第一跳风")
	_check(enemy.debuffs.has("tri_wind_bind"), "风跳挂风缚")
	_check(mid.hits.size() == 1, "200px 处进入新范围（旧 120 打不到）", str(mid.hits.size()))
	_check(far.hits.is_empty(), "范围外不受伤")

	# 按 interval 推进：启动 1 跳 + 每秒 1 跳 ×7 = 8 秒内共 8 跳
	var step := float(stats.get("interval", 1.0))
	for i in 7:
		p._tick_tri_ring(step)
	_check(enemy.hits.size() == 8, "8 秒共 8 跳", str(enemy.hits.size()))
	_check(enemy.elems == ["wind", "fire", "thunder", "wind", "fire", "thunder", "wind", "fire"],
		"元素轮转", str(enemy.elems))
	_check(enemy.debuffs.has("jie_huo") and enemy.debuffs.has("gan_dian"),
		"火 / 雷跳挂对应状态", str(enemy.debuffs))
	_check(p.tri_ring_left("tr_sanzai_lun") <= step, "剩余时长正确")
	p._tick_tri_ring(step)
	_check(p.tri_ring_left("tr_sanzai_lun") == 0.0, "8 秒后结束")
	_check(not bool(p.summon_cooldown_left("tr_sanzai_lun") <= 0.0), "冷却仍保留")

	# 冷却中不能再次催动
	var before_hits := enemy.hits.size()
	p.mana = 999.0
	p._start_tri_ring_treasure(CharacterData.make_treasure_instance(tpl), tpl)
	_check(enemy.hits.size() == before_hits and p._tri_ring_left == 0.0,
		"冷却中不会重新开环")

	# 旧灾替交互已移除
	_check(not p.has_method("_capture_taiji_sun_seed"), "太极盘火种专属交互已移除")
	_check(BuffDB.get_buff("sanzai_reverse").is_empty(), "旧三灾轮灾替 buff 已移除")

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
