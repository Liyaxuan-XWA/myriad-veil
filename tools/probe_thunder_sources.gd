extends Node
## 雷积·震魂的雷击来源自检（2026-10-30）
## 覆盖：满雷势平A协同雷击、五阵旗每秒雷击都计入 5 次眩晕。
## 用法：godot --headless --path . tools/probe_thunder_sources.tscn -- --no-save

class DummyBoss extends Node2D:
	var hits: Array = []
	var elems: Array = []
	var stuns: Array = []

	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			elem: String = "", _from_projectile: bool = false) -> void:
		hits.append(amount)
		elems.append(elem)

	func hit_spheres() -> Array:
		return [Vector3(0.0, 0.0, 20.0)]

	func is_dead() -> bool:
		return false

	func stun_for(seconds: float) -> void:
		stuns.append(seconds)

	func apply_debuff(_id: String, _duration: float) -> bool:
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


func _make_boss(pos: Vector2) -> DummyBoss:
	var b := DummyBoss.new()
	b.add_to_group("boss")
	b.global_position = pos
	add_child(b)
	return b


func _ready() -> void:
	print("\n########## 雷积·震魂 · 雷击来源 ##########")
	CharacterData.learned_skills.clear()
	CharacterData.active_skill_loadout.clear()
	CharacterData.passive_skill_loadout.clear()
	for sid in ["skill_thunder_verdict", "skill_thunder_accum", "skill_array_plant"]:
		CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = ["skill_thunder_verdict"]
	CharacterData.passive_skill_loadout = ["skill_thunder_accum"]

	var player: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.set_process(false)
	player.is_teleporting = false
	player.invincible_timer = 0.0
	player._refresh_thunder_unlock()
	player._refresh_array_unlock()
	_check(player._thunder_accum_equipped(), "雷积·震魂已装备")

	# ---- 五阵旗每秒雷击 ----
	var zone_boss := _make_boss(Vector2(12.0, 0.0))
	var need: int = SkillDB.THUNDER_ACCUM_REQUIRED
	player._clear_array_flags()
	for i in 5:
		var ang := -PI * 0.5 + TAU * float(i) / 5.0
		player._plant_array_flag(Vector2(cos(ang), sin(ang)) * 220.0, ArrayFlag.Kind.BIND)
	player._tick_array_flags(0.016)
	_check(player._array_zone_complete, "五阵旗区域成立")
	player.max_mana = 200.0
	player.mana = 200.0
	zone_boss.hits.clear()
	zone_boss.elems.clear()
	zone_boss.stuns.clear()
	for i in need:
		player._tick_array_flags(1.01)
	_check(zone_boss.hits.size() == need, "五阵旗雷击命中 %d 次" % need,
		"hits=%d" % zone_boss.hits.size())
	_check(zone_boss.elems.size() == need and not zone_boss.elems.has(null),
		"五阵旗雷击带雷元素", str(zone_boss.elems))
	_check(zone_boss.elems.size() == need and String(zone_boss.elems[0]) == "thunder",
		"五阵旗雷击 = metal", str(zone_boss.elems))
	_check(zone_boss.stuns.size() == 1 and is_equal_approx(float(zone_boss.stuns[0]), 0.5),
		"五阵旗雷击第 %d 次触发震魂" % need, str(zone_boss.stuns))

	player._clear_array_flags()
	zone_boss.queue_free()
	await get_tree().process_frame

	# ---- 满雷势平A协同雷击 ----
	var coop_boss := _make_boss(Vector2(52.0, 0.0))
	player.lei_shi = 3
	player.attack_dir = Vector2.RIGHT
	coop_boss.stuns.clear()
	coop_boss.elems.clear()
	for i in need:
		player._perform_attack_hit()
	var metal_hits := 0
	for e in coop_boss.elems:
		if String(e) == "thunder":
			metal_hits += 1
	_check(metal_hits == need, "满雷势平A协同雷击计入 %d 次" % need, "metal=%d" % metal_hits)
	_check(coop_boss.stuns.size() == 1 and is_equal_approx(float(coop_boss.stuns[0]), 0.5),
		"协同雷击第 %d 次触发震魂" % need, str(coop_boss.stuns))

	coop_boss.queue_free()
	CharacterData.passive_skill_loadout.clear()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
