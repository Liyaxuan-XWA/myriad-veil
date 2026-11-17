extends Node
## 被动「雷积·震魂」自检（2026-10-30）
## 9 次雷击功法命中 → 0.5 秒眩晕；每消耗 1 雷势 → 全主动 CD -1 秒。
## 用法：godot --headless --path . tools/probe_thunder_passive.tscn -- --no-save

class StunBoss extends Node2D:
	var stuns: Array = []
	var hits: Array = []
	var state := 0
	var is_dead := false

	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			_elem: String = "") -> void:
		hits.append(amount)

	func stagger_for(seconds: float) -> void:
		stuns.append(seconds)

	func head_top_y() -> float:
		return -110.0


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
	print("\n########## 雷积·震魂被动探针 ##########")
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector2.ZERO
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	CharacterData.learned_skills.append("skill_thunder_accum")
	CharacterData.passive_skill_loadout = ["skill_thunder_accum"]
	p._refresh_thunder_unlock()
	_check(p._thunder_accum_equipped(), "被动已装备")
	var need: int = p.THUNDER_ACCUM_REQUIRED
	_check(need == 9, "触发阈值 = 9 次", str(need))
	_check(WorldDB.get_floor_reward_skills(7).has("skill_thunder_accum"),
		"被动在塔 7 层感悟池")
	_check(String(SkillDB.get_passive_by_effect("thunder_accum_stun").get("skill_id", ""))
		== "skill_thunder_accum", "被动按 passive_effect 可查")

	var a := StunBoss.new()
	a.add_to_group("boss")
	a.global_position = Vector2(200.0, 0.0)
	add_child(a)
	var b := StunBoss.new()
	b.add_to_group("boss")
	b.global_position = Vector2(-200.0, 0.0)
	add_child(b)

	_check(p._is_thunder_attack("skill_thunder_drum", ""), "雷鼓算雷击")
	_check(p._is_thunder_attack("skill_thunder_verdict", "thunder"), "判词算雷击")
	_check(p._is_thunder_attack("skill_calamity_thunder_strike", "thunder"),
		"雷灾算雷击")
	_check(p._is_thunder_attack("", "thunder"), "metal 元素命中算雷击")
	_check(not p._is_thunder_attack("skill_blade_slash", ""), "普通物理不算雷击")

	for i in need - 1:
		p._note_thunder_skill_hit(a, "skill_thunder_drum", "")
	_check(a.stuns.is_empty() and int(a.get_meta(p.THUNDER_ACCUM_META, 0)) == need - 1,
		"%d 次雷击不眩晕、计数 %d" % [need - 1, need - 1],
		str(a.get_meta(p.THUNDER_ACCUM_META, 0)))
	p._note_thunder_skill_hit(a, "skill_thunder_verdict", "thunder")
	_check(a.stuns.size() == 1 and is_equal_approx(float(a.stuns[0]), 0.5),
		"第 %d 次雷击眩晕 0.5 秒" % need, str(a.stuns))
	_check(int(a.get_meta(p.THUNDER_ACCUM_META, 0)) == 0, "触发后计数清零")

	for i in need - 1:
		p._note_thunder_skill_hit(b, "skill_thunder_lock", "")
	p._note_thunder_skill_hit(b, "skill_blade_slash", "")
	_check(int(b.get_meta(p.THUNDER_ACCUM_META, 0)) == need - 1,
		"非雷击不计数", str(b.get_meta(p.THUNDER_ACCUM_META, 0)))
	p._note_thunder_skill_hit(b, "skill_calamity_thunder_strike", "thunder")
	_check(b.stuns.size() == 1, "两只敌人计数独立 / 第 %d 次触发" % need, str(b.stuns))

	# 真实伤害入口也要计数（_deal_direct_damage → _note_thunder_skill_hit）
	var c := StunBoss.new()
	c.add_to_group("boss")
	c.global_position = Vector2(0.0, 200.0)
	add_child(c)
	for i in need - 1:
		p._deal_direct_damage(c, 1.0, "elemental", "thunder", "skill_thunder_drum")
	_check(c.hits.size() == need - 1 and c.stuns.is_empty(),
		"真实伤害入口累计 %d 次" % (need - 1))
	p._deal_direct_damage(c, 1.0, "elemental", "thunder", "skill_thunder_drum")
	_check(c.stuns.size() == 1 and is_equal_approx(float(c.stuns[0]), 0.5),
		"真实伤害第 %d 次触发眩晕" % need, str(c.stuns))

	p.lei_shi = 3
	p.skill_cooldowns = {"skill_a": 5.0, "skill_b": 2.0}
	var spent: int = p._spend_lei(2)
	_check(spent == 2 and p.lei_shi == 1, "消耗 2 雷势", "spent=%d lei=%d" % [spent, p.lei_shi])
	_check(is_equal_approx(float(p.skill_cooldowns.get("skill_a", 0.0)), 3.0)
		and not p.skill_cooldowns.has("skill_b"),
		"每点雷势让全主动 CD -1 秒", str(p.skill_cooldowns))

	CharacterData.passive_skill_loadout.clear()
	p.lei_shi = 2
	p.skill_cooldowns = {"skill_a": 5.0}
	p._spend_lei(1)
	_check(is_equal_approx(float(p.skill_cooldowns.get("skill_a", 0.0)), 5.0),
		"没戴被动不减少 CD", str(p.skill_cooldowns))

	a.queue_free()
	b.queue_free()
	c.queue_free()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
