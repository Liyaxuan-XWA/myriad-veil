extends Node
## 破阵反噬自检（2026-10-29）：
##   完整五旗被敌对破去一面 → 玩家眩晕 5 秒 + 「破阵反噬」15 秒；
##   反噬期间插旗 / 踏阵 / 垒旗全部不可用，且不扣灵力/精力/冷却。
##   玩家自己解阵清旗、只有 4 旗时被破，都不触发。
## 用法：godot --headless --path . res://tools/probe_array_recoil.tscn

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _make_boss() -> Node2D:
	var boss = (load("res://scenes/boss/domain_boss_02_b.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	boss.set_process(false)
	return boss


func _ready() -> void:
	print("\n########## 破阵反噬自检 ##########")
	for sid in ["skill_array_plant", "skill_array_step", "skill_array_pile"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.global_position = Vector2.ZERO
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	p._refresh_array_unlock()
	var boss := _make_boss()
	boss.global_position = Vector2(600.0, 0.0)
	await get_tree().process_frame

	# 完整五旗：敌对破一面 → 反噬
	p._clear_array_flags()
	p.debuffs.erase("array_recoil")
	for i in 5:
		var ang := -PI * 0.5 + TAU * float(i) / 5.0
		p._plant_array_flag(Vector2(cos(ang), sin(ang)) * 200.0, ArrayFlag.Kind.ATTACK)
	var victim: Node = p.array_flags[0]
	for i in 3:
		victim.call("take_damage", 10.0, boss, "physical", "", false)
	_check(p.has_debuff("array_recoil"), "敌对破掉完整五旗的一面 → 破阵反噬")
	_check(float(p.debuffs.get("array_recoil", 0.0)) >= 14.95, "反噬持续 15 秒",
		"left=%.2f" % float(p.debuffs.get("array_recoil", 0.0)))
	_check(p.has_debuff("stun"), "反噬附带眩晕")
	_check(float(p.debuffs.get("stun", 0.0)) >= 4.95, "眩晕持续 5 秒",
		"left=%.2f" % float(p.debuffs.get("stun", 0.0)))
	# 隔离眩晕，单测「15 秒内不能插旗」的门禁本身
	p.debuffs.erase("stun")

	p.mana = p.max_mana
	p.stamina = p.max_stamina
	p.skill_cooldowns.clear()
	var mana0: float = p.mana
	var stam0: int = p.stamina
	var cds0: Dictionary = p.skill_cooldowns.duplicate()
	_check(not p.try_use_skill("skill_array_plant"), "反噬期间不能插旗")
	_check(is_equal_approx(p.mana, mana0) and p.stamina == stam0 and p.skill_cooldowns == cds0,
		"插旗被拦不扣资源/冷却")
	_check(not p.try_use_skill("skill_array_step"), "反噬期间不能踏阵")
	_check(not p.try_use_skill("skill_array_pile"), "反噬期间不能垒旗")

	# 玩家自己清阵不触发
	p._clear_array_flags()
	p.debuffs.erase("array_recoil")
	for i in 5:
		var a2 := -PI * 0.5 + TAU * float(i) / 5.0
		p._plant_array_flag(Vector2(cos(a2), sin(a2)) * 200.0, ArrayFlag.Kind.ATTACK)
	var by_player: Node = p.array_flags[0]
	for i in 3:
		by_player.call("take_hit")
	_check(not p.has_debuff("array_recoil") and not p.has_debuff("stun"),
		"玩家自己清旗不触发反噬/眩晕")

	# 只有 4 旗时被破：不触发
	p._clear_array_flags()
	p.debuffs.erase("array_recoil")
	for i in 4:
		var a3 := -PI * 0.5 + TAU * float(i) / 4.0
		p._plant_array_flag(Vector2(cos(a3), sin(a3)) * 200.0, ArrayFlag.Kind.ATTACK)
	var four_flag: Node = p.array_flags[0]
	for i in 3:
		four_flag.call("take_damage", 10.0, boss, "physical", "", false)
	_check(not p.has_debuff("array_recoil") and not p.has_debuff("stun"),
		"四旗被破不触发反噬/眩晕")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
