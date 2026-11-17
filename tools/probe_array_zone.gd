extends Node
## 五旗阵自检（玩家侧，2026-10-29）：
##   五旗闭合 → 单线阻挡层 / 攻防 +30% / 对手 -10% 攻 / 1s 雷击扣 10 法力 / 耗尽撤旗。
## 用法：godot --headless --path . res://tools/probe_array_zone.tscn

class DummyBoss extends Node2D:
	var hits: Array = []
	var zone_mults: Dictionary = {}

	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			_element: String = "", _from_projectile: bool = false) -> void:
		hits.append(amount)

	func apply_debuff(_id: String, _duration: float) -> bool:
		return true

	func has_debuff(_id: String) -> bool:
		return false

	func remove_debuff(_id: String) -> void:
		pass

	func set_zone_attack_mult(source: String, mult: float) -> void:
		zone_mults[source] = mult


var _player: Node2D
var _boss: DummyBoss
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
	print("\n########## 五旗阵自检（玩家侧） ##########")
	for sid in ["skill_array_plant"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	_boss = DummyBoss.new()
	_boss.add_to_group("boss")
	add_child(_boss)
	_boss.global_position = Vector2(12.0, 0.0)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	await get_tree().process_frame
	await get_tree().process_frame
	_player.global_position = Vector2.ZERO
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.is_teleporting = false
	_player.invincible_timer = 0.0
	_player.auto_parry_timer = 0.0
	_player._refresh_array_unlock()
	_player._clear_array_flags()

	for i in 5:
		var ang := -PI * 0.5 + TAU * float(i) / 5.0
		_player._plant_array_flag(Vector2(cos(ang), sin(ang)) * 220.0, ArrayFlag.Kind.ATTACK)
	_player._tick_array_flags(0.016)

	_check(_player.array_flags.size() == 5, "五旗齐", "flags=%d" % _player.array_flags.size())
	_check(_player._array_line_visuals.size() == 5, "五段各一根线", "vis=%d" % _player._array_line_visuals.size())
	var barrier: ArrayLineBarrier = _player._array_line_barrier
	_check(barrier != null and barrier._bodies.size() == 5, "五段阻挡体", "n=%d" % (barrier._bodies.size() if barrier != null else -1))
	_check(barrier != null and barrier.layer_bit == ArrayFlag.LINE_LAYER_PLAYER,
		"玩家线用玩家层", str(barrier.layer_bit if barrier != null else -1))
	_check((_player.collision_mask & ArrayFlag.LINE_LAYER_BOSS) != 0,
		"玩家被敌方线挡", "mask=%d" % _player.collision_mask)
	_check((_player.collision_mask & ArrayFlag.LINE_LAYER_PLAYER) == 0,
		"玩家不被自己的线挡", "mask=%d" % _player.collision_mask)

	_check(_player._array_zone_complete, "五旗区域成立")
	_check(is_equal_approx(_player._array_zone_self_attack_mult, 1.30),
		"阵内攻击 +30%", str(_player._array_zone_self_attack_mult))
	_check(absf(_player._array_zone_defense_mult - 1.0 / 1.30) < 0.001,
		"阵内防御 +30% → 受伤 ×1/1.3", str(_player._array_zone_defense_mult))
	_check(is_equal_approx(CharacterData.array_zone_attack_mult, 1.30),
		"攻击乘区写入 CharacterData", str(CharacterData.array_zone_attack_mult))
	_check(_player.has_buff("array_zone"), "阵内 buff 标签已挂")
	_check(_player._array_zone_fill != null and _player._array_zone_fill.visible,
		"区域填充可见")
	_check(is_equal_approx(float(_boss.zone_mults.get("enemy", 1.0)), 0.90),
		"区域内对手攻击 -10%", str(_boss.zone_mults.get("enemy", 1.0)))

	# 雷击：1 秒一次，一次扣 10 法力，命中区域内的 BOSS
	_player.mana = _player.max_mana
	_boss.hits.clear()
	_player._tick_array_flags(1.01)
	_check(is_equal_approx(_player.mana, _player.max_mana - 10.0),
		"雷击扣 10 法力", "mana=%.1f" % _player.mana)
	_check(_boss.hits.size() == 1, "雷击命中区域内 BOSS", "hits=%d" % _boss.hits.size())
	var expected: float = CharacterData.spell_attack() * 0.6
	_check(not _boss.hits.is_empty() and absf(float(_boss.hits[0]) - expected) < 0.2,
		"雷击 = 0.6×法攻（含阵内 +30%）", "%.2f / %.2f" % [float(_boss.hits[0]) if not _boss.hits.is_empty() else -1.0, expected])

	# 区域外不扣蓝、不打雷，攻击削减解除
	_boss.global_position = Vector2(460.0, 0.0)
	_player._tick_array_flags(0.016)
	var mana_before: float = _player.mana
	_boss.hits.clear()
	_player._tick_array_flags(1.01)
	_check(is_equal_approx(_player.mana, mana_before), "区域外不扣法力", "mana=%.1f" % _player.mana)
	_check(_boss.hits.is_empty(), "区域外不落雷")
	_check(is_equal_approx(float(_boss.zone_mults.get("enemy", 1.0)), 1.0),
		"离开区域恢复对手攻击", str(_boss.zone_mults.get("enemy", 1.0)))

	# 法力不足：旗全部消失，线/区域/减攻一起清掉
	_boss.global_position = Vector2(12.0, 0.0)
	_player._tick_array_flags(0.016)
	_player.mana = 5.0
	_player._tick_array_flags(1.01)
	_check(_player.array_flags.is_empty(), "法力不足五旗消散")
	_check(not _player._array_zone_complete, "区域关闭")
	_check(_player._array_line_barrier._bodies.is_empty(), "阻挡体清空")
	_check(is_equal_approx(CharacterData.array_zone_attack_mult, 1.0),
		"攻击乘区还原", str(CharacterData.array_zone_attack_mult))

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
