extends Node
## 五旗阵自检（BOSS 侧，2026-10-29）：
##   敌方五旗 → 玩家/友军挡线层 / BOSS 在阵内 +30% 攻防 / 玩家 -10% 攻 /
##   1s 雷击扣 10 阵力 / 阵力耗尽撤旗 / 重新起阵补满。
## 用法：godot --headless --path . res://tools/probe_array_zone_boss.tscn

class DummyPlayer extends Node2D:
	var hp: float = 10000.0
	var hits: Array = []
	var debuffs: Array = []
	var enemy_attack_mult: float = 1.0

	func _ready() -> void:
		add_to_group("player")

	func take_damage(amount: float, _attack_kind: String, _source: Node = null,
			_element: String = "") -> void:
		hits.append(amount)
		hp -= amount

	func apply_debuff(id: String, duration: float, _quiet: bool = true) -> bool:
		debuffs.append([id, duration])
		return true

	func has_debuff(id: String) -> bool:
		for d in debuffs:
			if String((d as Array)[0]) == id:
				return true
		return false

	func stagger_for(_seconds: float) -> void:
		pass

	func set_array_zone_enemy_attack_mult(mult: float) -> void:
		enemy_attack_mult = mult


var _player: DummyPlayer
var _boss: Node2D
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
	print("\n########## 五旗阵自检（BOSS 侧） ##########")
	_player = DummyPlayer.new()
	add_child(_player)
	_player.global_position = Vector2.ZERO
	_boss = (load("res://scenes/boss/domain_boss_02_b.tscn") as PackedScene).instantiate()
	add_child(_boss)
	await get_tree().process_frame
	await get_tree().process_frame
	_boss.set_physics_process(false)
	_boss.set_process(false)
	_boss.set("target", _player)
	_boss.global_position = Vector2.ZERO
	var base_attack: float = float(_boss.get("attack_power"))
	for i in 5:
		var ang := -PI * 0.5 + TAU * float(i) / 5.0
		_boss.call("_plant_flag", Vector2(cos(ang), sin(ang)) * 220.0, ArrayFlag.Kind.BIND)
	_boss.call("_tick_flags", 0.016)

	_check(_boss.get("_flags").size() == 5, "BOSS 五旗齐")
	_check(bool(_boss.get("_zone_complete")), "BOSS 五旗区域成立")
	var barrier = _boss.get("_line_barrier")
	_check(barrier != null and barrier._bodies.size() == 5, "BOSS 五段阻挡体",
		"n=%d" % (barrier._bodies.size() if barrier != null else -1))
	_check(barrier != null and barrier.layer_bit == ArrayFlag.LINE_LAYER_BOSS,
		"敌方 BOSS 线用 BOSS 层", str(barrier.layer_bit if barrier != null else -1))
	_check((_boss.collision_mask & ArrayFlag.LINE_LAYER_PLAYER) != 0,
		"BOSS 被玩家线挡", "mask=%d" % _boss.collision_mask)
	_check((_boss.collision_mask & ArrayFlag.LINE_LAYER_BOSS) == 0,
		"BOSS 不被自己的线挡", "mask=%d" % _boss.collision_mask)

	_check(is_equal_approx(float(_boss.get("_zone_attack_mult")), 1.30),
		"BOSS 阵内攻击 +30%", str(_boss.get("_zone_attack_mult")))
	_check(absf(float(_boss.get("_zone_defense_mult")) - 1.0 / 1.30) < 0.001,
		"BOSS 阵内防御 +30% → 受伤 ×1/1.3", str(_boss.get("_zone_defense_mult")))
	_check(absf(float(_boss.get("attack_power")) - base_attack * 1.30) < 0.01,
		"BOSS 攻击力已乘 1.3", "%.2f → %.2f" % [base_attack, float(_boss.get("attack_power"))])
	_check(absf(float(_boss.call("damage_taken_multiplier", "physical")) - 1.0 / 1.30) < 0.001,
		"BOSS 受击减伤读取阵内防御", str(_boss.call("damage_taken_multiplier", "physical")))
	_check(is_equal_approx(_player.enemy_attack_mult, 0.90),
		"区域内玩家攻击 -10%", str(_player.enemy_attack_mult))

	# 雷击：1 秒一次，一次扣 10 阵力
	var hp_before: float = _player.hp
	_player.hits.clear()
	_boss.call("_tick_flags", 1.01)
	_check(is_equal_approx(float(_boss.get("_zone_energy")), 90.0),
		"雷击扣 10 阵力", "energy=%.1f" % float(_boss.get("_zone_energy")))
	_check(_player.hits.size() == 1, "雷击命中区域内玩家", "hits=%d" % _player.hits.size())
	var expected: float = float(_boss.get("attack_power")) * 0.6
	_check(not _player.hits.is_empty() and absf(float(_player.hits[0]) - expected) < 0.2,
		"雷击 = 0.6×BOSS 攻击力", "%.2f / %.2f" % [float(_player.hits[0]) if not _player.hits.is_empty() else -1.0, expected])
	_check(_player.hp < hp_before, "玩家实际掉血")

	# 区域外不扣阵力、不打雷，攻击削减解除
	_player.global_position = Vector2(460.0, 0.0)
	_boss.call("_tick_flags", 0.016)
	var energy_before: float = float(_boss.get("_zone_energy"))
	_player.hits.clear()
	_boss.call("_tick_flags", 1.01)
	_check(is_equal_approx(float(_boss.get("_zone_energy")), energy_before),
		"区域外不扣阵力", "energy=%.1f" % float(_boss.get("_zone_energy")))
	_check(_player.hits.is_empty(), "区域外不落雷")
	_check(is_equal_approx(_player.enemy_attack_mult, 1.0),
		"离开区域恢复玩家攻击", str(_player.enemy_attack_mult))

	# 阵力不足：旗全部消失，线/区域/减攻一起清掉
	_player.global_position = Vector2.ZERO
	_boss.call("_tick_flags", 0.016)
	_boss.set("_zone_energy", 5.0)
	_boss.call("_tick_flags", 1.01)
	_check(_boss.get("_flags").is_empty(), "阵力不足五旗消散")
	_check(not bool(_boss.get("_zone_complete")), "BOSS 区域关闭")
	_check(barrier._bodies.is_empty(), "BOSS 阻挡体清空")
	_check(absf(float(_boss.get("attack_power")) - base_attack) < 0.01,
		"BOSS 攻击力还原", "%.2f" % float(_boss.get("attack_power")))
	_check(is_equal_approx(_player.enemy_attack_mult, 1.0),
		"玩家攻击削减还原", str(_player.enemy_attack_mult))

	# 重新起阵：阵力补满
	_boss.call("_plant_flag", Vector2(0.0, -220.0), ArrayFlag.Kind.BIND)
	_check(is_equal_approx(float(_boss.get("_zone_energy")), 100.0),
		"重新起阵阵力补满", "energy=%.1f" % float(_boss.get("_zone_energy")))

	print("-- 封阵·四象：守牢 10 秒 / 破旗即散 / 困牢眩晕 5 秒")
	_boss.call("_clear_all_flags")
	_player.global_position = Vector2.ZERO
	_boss.global_position = Vector2.ZERO
	for i in 4:
		var ang := -PI * 0.5 + TAU * float(i) / 4.0
		_boss.call("_plant_flag", Vector2(cos(ang), sin(ang)) * 180.0, ArrayFlag.Kind.GUARD)
	_boss.call("_cast_seal", {})
	_check(bool(_boss.get("_seal_guard")), "守牢已开启")
	_check(is_equal_approx(float(_boss.get("_seal_guard_left")), 10.0),
		"守牢持续 10 秒", "left=%.1f" % float(_boss.get("_seal_guard_left")))
	_check(absf(float(_boss.call("damage_taken_multiplier", "physical")) - 0.30) < 0.001,
		"守牢减伤 70%", str(_boss.call("damage_taken_multiplier", "physical")))
	var guard_flags: Array = _boss.get("_flags")
	(guard_flags[0] as Node).set("_dead", true)
	_boss.call("_tick_flags", 0.016)
	_check(not bool(_boss.get("_seal_guard")) and is_equal_approx(float(_boss.get("_seal_guard_left")), 0.0),
		"破旗瞬间结束守牢", "left=%.1f" % float(_boss.get("_seal_guard_left")))
	for f in _boss.get("_flags"):
		f.set("kind", ArrayFlag.Kind.ATTACK)   # 排除守旗被动，单看守牢减伤是否消失
	_check(absf(float(_boss.call("damage_taken_multiplier", "physical")) - 1.0) < 0.001,
		"破旗后守牢减伤消失", str(_boss.call("damage_taken_multiplier", "physical")))

	_boss.call("_clear_all_flags")
	_player.debuffs.clear()
	_boss.global_position = Vector2.ZERO
	for i in 4:
		var ang2 := -PI * 0.5 + TAU * float(i) / 4.0
		_boss.call("_plant_flag", Vector2(cos(ang2), sin(ang2)) * 180.0, ArrayFlag.Kind.BIND)
	_boss.call("_cast_seal", {})
	_boss.call("_tick_seal", 0.016)
	_check(_player.debuffs.size() == 1 and String((_player.debuffs[0] as Array)[0]) == "stun"
		and is_equal_approx(float((_player.debuffs[0] as Array)[1]), 5.0),
		"困牢：玩家眩晕 5 秒", str(_player.debuffs))
	_boss.call("_tick_seal", 0.55)
	_check(_player.debuffs.size() == 1, "已眩晕的玩家不重复刷新")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
