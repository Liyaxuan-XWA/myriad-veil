extends Node
## 两仪势空条起势 / 被动覆盖自检（2026-10-28）：
##   空条第一发物理/术法都 +1；佩戴「负阴抱阳」后阵旗 / 气环的直接伤害也要能叠势。
## 用法：godot --headless --path . res://tools/probe_player_yinyang.tscn

class DummyBoss extends Node2D:
	var hits: Array = []
	var marks: Dictionary = {}
	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			_element: String = "", _from_projectile: bool = false) -> void:
		hits.append(amount)
	func hit_spheres() -> Array:
		return [Vector3(0.0, 0.0, 20.0)]
	func has_debuff(id: String) -> bool:
		return marks.has(id)
	func apply_debuff(id: String, duration: float) -> bool:
		marks[id] = duration
		return true
	func remove_debuff(id: String) -> void:
		marks.erase(id)
	func edge_distance_to(world_pos: Vector2) -> float:
		return maxf(0.0, global_position.distance_to(world_pos) - 20.0)

var _p: Node2D
var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _reset(polarity: int) -> void:
	_p.yinyang_stacks = 0
	_p.yinyang_polarity = polarity
	_p.remove_buff("yinyang_reverse")


func _hit(kind: String, sid: String) -> float:
	return float(_p._yinyang_modify_damage(null, kind, 100.0, sid))


func _ready() -> void:
	print("\n########## 两仪势空条起势探针 ##########")
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	await get_tree().process_frame
	await get_tree().process_frame
	_p.set_physics_process(false)
	_p.set_process(false)
	_p._yinyang_unlocked = true
	_reset(_p.YINYANG_YANG)

	var d := _hit("physical_melee", "skill_yinyang_palm")
	_check(is_equal_approx(d, 122.4), "空条第一发物理 = 逆式 +20% × 1.02", str(d))
	_check(_p.yinyang_stacks == 1, "空条第一发物理 +1 层", str(_p.yinyang_stacks))
	_check(_p.yinyang_polarity == _p.YINYANG_YANG, "空条物理起势定阳")

	d = _hit("physical_melee", "skill_yinyang_palm")
	_check(is_equal_approx(d, 102.0), "同色顺式不再叠层（1 层 +2%）", str(d))
	_check(_p.yinyang_stacks == 1, "顺式势层不变", str(_p.yinyang_stacks))

	d = _hit("spell", "skill_yinyang_finger")
	_check(is_equal_approx(d, 124.8), "异色法术 = 逆式 +20% × 1.04", str(d))
	_check(_p.yinyang_stacks == 2 and _p.yinyang_polarity == _p.YINYANG_YIN,
		"异色法术 +1 层并转阴", "%d / %d" % [_p.yinyang_stacks, _p.yinyang_polarity])

	_reset(_p.YINYANG_YANG)
	d = _hit("spell", "skill_yinyang_finger")
	_check(is_equal_approx(d, 122.4), "空条第一发法术 = 逆式 +20% × 1.02", str(d))
	_check(_p.yinyang_stacks == 1 and _p.yinyang_polarity == _p.YINYANG_YIN,
		"空条法术起势定阴", "%d / %d" % [_p.yinyang_stacks, _p.yinyang_polarity])

	_reset(_p.YINYANG_YIN)
	d = _hit("physical_melee", "skill_yinyang_palm")
	_check(is_equal_approx(d, 122.4), "空条（阴底）物理也能起势", str(d))
	_check(_p.yinyang_stacks == 1 and _p.yinyang_polarity == _p.YINYANG_YANG,
		"空条物理从阴底转阳", "%d / %d" % [_p.yinyang_stacks, _p.yinyang_polarity])

	# 三层上限
	_reset(_p.YINYANG_YANG)
	for i in range(6):
		_hit("spell" if i % 2 == 0 else "physical_melee",
			"skill_yinyang_finger" if i % 2 == 0 else "skill_yinyang_palm")
	_check(_p.yinyang_stacks == 3, "势层上限 3", str(_p.yinyang_stacks))

	var rules := SkillDB.get_yinyang_rules_text("两仪势")
	print("规则文案：\n", rules)
	_check(rules.contains("势条空时第一发任意颜色都算逆式起势"), "规则文案写明空条起势")

	# 佩戴「负阴抱阳」后，阵旗 / 气环这类直接结算也要走两仪势
	var dummy := DummyBoss.new()
	dummy.add_to_group("boss")
	dummy.global_position = Vector2(80.0, 0.0)
	add_child(dummy)
	CharacterData.learned_skills.append("skill_yinyang_harmony")
	CharacterData.passive_skill_loadout = ["skill_yinyang_harmony"]
	_p._yinyang_unlocked = true
	_p._qi_unlocked = true
	_reset(_p.YINYANG_YANG)
	_p.qi_rings = 1
	var qi_cast: bool = _p._qi_handle_cast("skill_qi_wave", Vector2.RIGHT)
	_check(qi_cast and _p.yinyang_stacks == 1, "被动覆盖气环冲锋",
		"%s / stacks=%d" % [qi_cast, _p.yinyang_stacks])
	_reset(_p.YINYANG_YANG)
	_p._array_line_damage(Vector2.ZERO, Vector2(200.0, 0.0), 1.0)
	_check(_p.yinyang_stacks == 1, "被动覆盖阵旗阵线", str(_p.yinyang_stacks))

	# 后续触发：只吃逆式增伤 + 逆印结算，不叠层、不翻面
	_reset(_p.YINYANG_YANG)
	dummy.marks.clear()
	dummy.hits.clear()
	_p._deal_direct_damage(dummy, 100.0, "elemental", "", "", false)
	_check(_p.yinyang_stacks == 0 and _p.yinyang_polarity == _p.YINYANG_YANG,
		"触发伤害不叠势不翻面", "stacks=%d pol=%d" % [_p.yinyang_stacks, _p.yinyang_polarity])
	_check(is_equal_approx(float(dummy.hits.back()), 120.0), "触发伤害吃逆式 +20%",
		str(dummy.hits.back()))
	dummy.marks["yang_mark"] = 5.0
	dummy.hits.clear()
	_p._deal_direct_damage(dummy, 100.0, "elemental", "", "", false)
	_check(is_equal_approx(float(dummy.hits.back()), 150.0) and not dummy.marks.has("yang_mark"),
		"触发伤害结算逆印 +25%", str(dummy.hits.back()))
	_check(_p.yinyang_stacks == 0, "结算逆印也不叠层", str(_p.yinyang_stacks))
	_reset(_p.YINYANG_YANG)
	dummy.hits.clear()
	_p._deal_direct_damage(dummy, 100.0, "physical", "", "", false)
	_check(is_equal_approx(float(dummy.hits.back()), 100.0) and _p.yinyang_stacks == 0,
		"触发伤害同色不吃逆式", str(dummy.hits.back()))
	_p.apply_buff("yinyang_reverse", 4.0)
	_p._deal_direct_damage(dummy, 100.0, "physical", "", "", false)
	_check(_p.has_buff("yinyang_reverse") and _p.yinyang_stacks == 0,
		"触发伤害不消耗必定逆式", "buff=%s" % _p.has_buff("yinyang_reverse"))
	var buffed := _hit("physical_melee", "skill_yinyang_palm")
	_check(not _p.has_buff("yinyang_reverse") and _p.yinyang_stacks == 1
		and is_equal_approx(buffed, 122.4), "主动命中才消耗必定逆式")

	CharacterData.passive_skill_loadout = []
	_reset(_p.YINYANG_YANG)
	_p._array_line_damage(Vector2.ZERO, Vector2(200.0, 0.0), 1.0)
	_check(_p.yinyang_stacks == 0, "未戴被动时不越权叠势", str(_p.yinyang_stacks))

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
