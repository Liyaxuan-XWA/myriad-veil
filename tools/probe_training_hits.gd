extends Node2D
## 演武场木桩命中回归
## 1) 技能自瞄取受击球加权中心，不是脚底原点（玄冥指等窄线功法近距离必中）
## 2) 突进技越过目标后，用本段起手位置补一次判定（破步突进斩 / 穿 / 阳关三叠）
## 3) 补判定不会让同段重复命中

var _passes := 0
var _fails: Array = []
var _player: Node2D
var _dummy: Node2D


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 演武场木桩命中回归 ##########")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ARENA}
	BattleResolver.skip_next_intro = true
	for sid in ["skill_yinyang_finger", "skill_tiger_claw", "skill_yinyang_palm",
			"skill_blade_dash", "skill_sword_stab", "skill_sword_pierce",
			"skill_yinyang_triple", "skill_sword_heaven", "skill_yinyang_fish",
			"skill_yinyang_collapse"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_player = arena.player
	_dummy = arena.training_dummy
	_player.set_physics_process(false)

	# 演武场符箓：试招场不扣张（0 张也能继续用）
	var tid := "tal_huoqiu_lianqi"
	for i in 3:
		CharacterData.add_item({"id": tid, "name": "火球符·练气", "type": "talisman", "count": 1})
	if CharacterData.active_skill_loadout.is_empty():
		CharacterData.active_skill_loadout.append("talisman:" + tid)
	else:
		CharacterData.active_skill_loadout[0] = "talisman:" + tid
	_player.global_position = _dummy.global_position + Vector2(-120.0, 0.0)
	_player.mana = 100.0
	var tal_before := CharacterData.count_item(tid)
	var tal_ok: bool = _player.use_talisman_slot("talisman:" + tid)
	await get_tree().create_timer(0.5).timeout
	_check(tal_ok and CharacterData.count_item(tid) == tal_before,
		"演武场使用符箓不扣张", "before=%d after=%d" % [tal_before, CharacterData.count_item(tid)])
	# 把库存清到 0，仍应能施放（训练场按无限张处理）
	if CharacterData.inventory.size() > 0:
		CharacterData.inventory.clear()
	_player.mana = 100.0
	var tal_zero_ok: bool = _player.use_talisman_slot("talisman:" + tid)
	await get_tree().create_timer(0.5).timeout
	_check(tal_zero_ok and CharacterData.count_item(tid) == 0,
		"演武场 0 张仍可试用符箓")
	_player.global_position = _dummy.global_position

	var point: Vector2 = _player._boss_aim_point(_dummy)
	_check(point.y < _dummy.global_position.y - 30.0,
		"自瞄点落在木桩体内（不是脚底）", str(point))
	var finger_form := SkillDB.get_skill_form("skill_yinyang_finger")
	for d in [60.0, 120.0, 200.0]:
		_player.global_position = _dummy.global_position + Vector2(-d, 0.0)
		_dummy.reset_training_stats()
		var auto_dir: Vector2 = _player._skill_aim_dir()
		_player._apply_skill_hit("skill_yinyang_finger", finger_form, auto_dir)
		await get_tree().process_frame
		_check(_dummy.hit_count == 1, "玄冥指自瞄命中 dist=%.0f" % d,
			"dir=%s hits=%d" % [str(auto_dir), _dummy.hit_count])

	_player.set_physics_process(true)
	var reps := ["skill_tiger_claw", "skill_yinyang_palm", "skill_blade_dash",
		"skill_sword_stab", "skill_sword_pierce", "skill_yinyang_triple",
		"skill_sword_heaven", "skill_yinyang_fish", "skill_yinyang_collapse"]
	for sid in reps:
		await _cast_close(sid, 120.0)

	# 突进技在正常距离（不会越过目标）不应被兜底重复结算：每段最多 1 次
	var stage_limits := {
		"skill_blade_dash": 2, "skill_sword_pierce": 1, "skill_yinyang_triple": 3,
	}
	for sid in stage_limits.keys():
		_player.set_physics_process(true)
		_player.global_position = _dummy.global_position + Vector2(-260.0, 0.0)
		_player.velocity = Vector2.ZERO
		_player.mana = 999.0
		_player.stamina = 9
		_player.skill_cooldowns.clear()
		_equip(sid)
		_dummy.reset_training_stats()
		var ok: bool = _player.try_use_skill(sid)
		await get_tree().create_timer(2.2).timeout
		_check(ok and _dummy.hit_count >= 1 and _dummy.hit_count <= int(stage_limits[sid]),
			"突进技每段最多 1 次命中：" + sid, "hits=%d" % _dummy.hit_count)

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _equip(sid: String) -> void:
	if CharacterData.active_skill_loadout.is_empty():
		CharacterData.active_skill_loadout.append(sid)
	else:
		CharacterData.active_skill_loadout[0] = sid


func _cast_close(sid: String, dist: float) -> void:
	_player.set_physics_process(true)
	_player.global_position = _dummy.global_position + Vector2(-dist, 0.0)
	_player.velocity = Vector2.ZERO
	_player.mana = 999.0
	_player.stamina = 9
	_player.skill_cooldowns.clear()
	_equip(sid)
	_dummy.reset_training_stats()
	var ok: bool = _player.try_use_skill(sid)
	await get_tree().create_timer(1.3).timeout
	_check(ok and _dummy.hit_count >= 1, "技法命中木桩：" + sid,
		"ok=%s hits=%d dmg=%.1f" % [ok, _dummy.hit_count, _dummy.total_damage])
