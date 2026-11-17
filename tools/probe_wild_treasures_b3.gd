extends Node
## 野修法宝第三组 + 法宝无词条/进阶规则自检（2026-11-01）
## 覆盖：血饲印 / 换位玦 / 棘甲佩 / 回风袋 双端；无属性词条；敲击即进阶；
##       旧法宝迁移（旧词条/普通强化/破损/召唤加成折算）；进阶成长。
## 用法：godot --headless --path . res://tools/probe_wild_treasures_b3.tscn

class DummyBoss extends Node2D:
	var state: int = BossBase.BossState.IDLE
	var is_ally: bool = false
	var knockbacks: Array = []
	var true_hits: Array = []

	func _ready() -> void:
		add_to_group("boss")

	func is_dead() -> bool:
		return false

	func take_knockback(impulse: Vector2) -> void:
		knockbacks.append(impulse)

	func take_true_damage(amount: float, _source: Node = null) -> void:
		true_hits.append(amount)

	func _clamp_to_arena() -> void:
		pass


var _passes := 0
var _fails: Array = []
var _p: Node2D
var _enemy: Node2D


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 野修法宝第三组 / 无词条进阶 自检 ##########")
	await get_tree().process_frame
	_check_data()
	_check_no_affix()
	_check_ascension_stats()
	await _test_forge_ui()
	await _spawn_player()
	_test_player_blood_seal()
	_test_player_swap()
	_test_player_thorns()
	_test_player_gust()
	await _spawn_enemy()
	_test_enemy_blood_seal()
	_test_enemy_swap()
	_test_enemy_thorns()
	_test_enemy_gust()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_data() -> void:
	print("\n-- 数据 / 图鉴 / 池 --")
	var ids := ["tr_xuesi_yin", "tr_huanwei_jue", "tr_jijia_pei", "tr_huifeng_dai"]
	var names := ["血饲印", "换位玦", "棘甲佩", "回风袋"]
	var kinds := ["blood_seal", "swap", "thorns", "gust"]
	for i in ids.size():
		var id: String = ids[i]
		var tpl := ItemDB.get_treasure_template(id)
		_check(not tpl.is_empty(), "模板存在：" + id)
		_check(String(tpl.get("treasure_name", "")) == names[i], "显示名：" + names[i])
		_check(String(tpl.get("active_type", "")) == kinds[i], "主动类型：" + kinds[i])
		_check((tpl.get("attributes", {}) as Dictionary).is_empty(), "模板无词条：" + id)
		var icon := String(tpl.get("icon", ""))
		_check(icon != "" and FileAccess.file_exists(icon), "图标已落盘：" + id)
		_check(CodexDB.SOURCES.has(id), "图鉴来源：" + id)
		var lines := ItemDB.treasure_effect_lines(CharacterData.make_treasure_instance(tpl))
		_check(lines.size() >= 3, "法宝说明至少三行：" + id, str(lines.size()))
	_check(SecretWorldDB.CULTIVATOR_ZHUJI.get("treasure_pool", []).has("tr_jijia_pei"),
		"筑基池含棘甲佩")
	_check(SecretWorldDB.CULTIVATOR_ZHUJI.get("treasure_pool", []).has("tr_huifeng_dai"),
		"筑基池含回风袋")
	_check(SecretWorldDB.CULTIVATOR_JIEDAN.get("treasure_pool", []).has("tr_xuesi_yin"),
		"结丹池含血饲印")
	_check(SecretWorldDB.CULTIVATOR_JIEDAN.get("treasure_pool", []).has("tr_huanwei_jue"),
		"结丹池含换位玦")
	_check(not SecretWorldDB.CULTIVATOR.get("treasure_pool", []).has("tr_xuesi_yin"),
		"练气池不出血饲印")


func _check_no_affix() -> void:
	print("\n-- 法宝无词条 / 旧档迁移 --")
	var taiji := ItemDB.get_treasure_template("tr_taiji_pan")
	var tri := ItemDB.get_treasure_template("tr_sanzai_lun")
	_check((taiji.get("attributes", {}) as Dictionary).is_empty(), "太极盘模板无词条")
	_check((tri.get("attributes", {}) as Dictionary).is_empty(), "三元轮模板无词条")
	var item := CharacterData.make_treasure_instance(taiji)
	_check((item.get("attributes", {}) as Dictionary).is_empty(), "太极盘实例无词条")
	_check(int(item.get("enhancement_limit", -1)) == 0, "法宝实例无普通强化上限")
	var old := {
		"equipment_type": "treasure",
		"attributes": {"strength": 10.0},
		"attributes_base": {"strength": 10.0},
		"enhancement_level": 5,
		"enhance_success_count": 7,
		"enhance_fail_count": 3,
		"enhancement_limit": 10,
		"is_broken": true,
		"attack_bonus_base": 12.0,
		"attack_bonus": 12.0,
		"summon_boost_count": 5,
		"summon_ascend_boost_pct": 1.0,
	}
	CharacterData._normalize_treasure_no_affixes(old)
	_check((old.get("attributes", {}) as Dictionary).is_empty(), "迁移清空词条")
	_check((old.get("attributes_base", {}) as Dictionary).is_empty(), "迁移清空词条基准")
	_check(int(old.get("enhancement_level", -1)) == 0, "迁移清空普通强化等级")
	_check(int(old.get("enhancement_limit", -1)) == 0, "迁移清空强化上限")
	_check(not bool(old.get("is_broken", true)), "迁移解除旧破损")
	_check(int(old.get("summon_boost_count", -1)) == 0, "旧召唤强化级数清零")
	_check(is_equal_approx(float(old.get("summon_ascend_boost_pct", 0.0)), 11.0),
		"旧召唤加成折进进阶加成（1+5×2）")
	_check(is_zero_approx(float(old.get("attack_bonus", 1.0))), "迁移清空攻击加成")


func _ensure_crystals() -> void:
	for raw in CharacterData.inventory:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == CharacterData.ENHANCE_MATERIAL:
			(raw as Dictionary)["count"] = 999
			return
	var mat_def := ItemDB.get_material(CharacterData.ENHANCE_MATERIAL)
	CharacterData.inventory.append({
		"id": CharacterData.ENHANCE_MATERIAL,
		"name": String(mat_def.get("name", "锻造晶石")),
		"type": CharacterData.ITEM_MATERIAL,
		"count": 999,
		"icon": String(mat_def.get("icon", "")),
	})


func _ascend_once(tpl: Dictionary) -> Dictionary:
	var item := CharacterData.make_treasure_instance(tpl)
	var res := {}
	for i in 12:
		res = CharacterData.enhance_item(item)
		if not bool(res.get("ok", false)):
			break
		var result := String(res.get("result", ""))
		if result == ItemDB.ENHANCE_RESULT_ASCEND:
			return {"item": item, "res": res}
		if result != ItemDB.ENHANCE_RESULT_ASCEND_FAIL:
			return {"item": item, "res": res}
	return {"item": item, "res": res}


func _check_ascension_stats() -> void:
	print("\n-- 进阶只增强主动效果 --")
	CharacterData.current_realm = "元婴"
	_ensure_crystals()
	var seal := CharacterData.make_treasure_instance(
		ItemDB.get_treasure_template("tr_xuesi_yin"))
	var asc := _ascend_once(ItemDB.get_treasure_template("tr_xuesi_yin"))
	var seal_up: Dictionary = asc.get("item", {})
	var res: Dictionary = asc.get("res", {})
	_check(String(res.get("result", "")) == ItemDB.ENHANCE_RESULT_ASCEND,
		"法宝敲击直接进阶", str(res.get("message", "")))
	_check((seal_up.get("attributes", {}) as Dictionary).is_empty(),
		"进阶后仍无属性词条")
	var base_stats := ItemDB.treasure_active_stats(seal,
		ItemDB.get_treasure_template("tr_xuesi_yin"))
	var up_stats := ItemDB.treasure_active_stats(seal_up,
		ItemDB.get_treasure_template("tr_xuesi_yin"))
	_check(float(up_stats.get("mana_restore", 0.0)) > float(base_stats.get("mana_restore", 0.0)),
		"血饲印进阶回复更高",
		"%.2f → %.2f" % [float(base_stats.get("mana_restore", 0.0)),
			float(up_stats.get("mana_restore", 0.0))])
	var taiji_base := ItemDB.treasure_active_stats(
		CharacterData.make_treasure_instance(ItemDB.get_treasure_template("tr_taiji_pan")),
		ItemDB.get_treasure_template("tr_taiji_pan"))
	var taiji_item := CharacterData.make_treasure_instance(
		ItemDB.get_treasure_template("tr_taiji_pan"))
	taiji_item["equipment_grade"] = "宝器"
	var taiji_up := ItemDB.treasure_active_stats(taiji_item,
		ItemDB.get_treasure_template("tr_taiji_pan"))
	_check(float(taiji_up.get("duration", 0.0)) > float(taiji_base.get("duration", 0.0)),
		"太极盘进阶持续更长")
	_check(float(taiji_up.get("reduction", 0.0)) > float(taiji_base.get("reduction", 0.0)),
		"太极盘进阶减伤更高")
	var tri_item := CharacterData.make_treasure_instance(
		ItemDB.get_treasure_template("tr_sanzai_lun"))
	tri_item["equipment_grade"] = "宝器"
	var tri_up := ItemDB.treasure_active_stats(tri_item,
		ItemDB.get_treasure_template("tr_sanzai_lun"))
	_check(float(tri_up.get("ratio", 0.0)) > 0.65, "三元轮进阶倍率更高",
		"%.2f" % float(tri_up.get("ratio", 0.0)))
	var sum_res := _ascend_once(ItemDB.get_treasure_template("tr_huyao_ling"))
	var sum_item: Dictionary = sum_res.get("item", {})
	_check(String(sum_res.get("res", {}).get("result", "")) == ItemDB.ENHANCE_RESULT_ASCEND,
		"召唤令进阶成功")
	_check(float(sum_item.get("summon_ascend_boost_pct", 0.0)) >= 6.0,
		"召唤令进阶 +6% 召唤物加成",
		str(sum_item.get("summon_ascend_boost_pct", 0.0)))
	_check(int(sum_item.get("summon_duration_bonus", 0)) >= 1, "召唤令进阶 +5 秒召唤时长")


func _test_forge_ui() -> void:
	print("\n-- 锻造台法宝显示 --")
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var item := CharacterData.make_treasure_instance(
		ItemDB.get_treasure_template("tr_xuesi_yin"))
	panel._anvil_item = item
	panel._refresh_forge()
	var meta := String(panel._plaque_meta.text)
	_check(meta.contains("法宝") and not meta.contains("强化"),
		"砧上法宝显示可进阶而非强化", meta)
	var lines: Array = panel._detail_lines(item, "背包")
	var text := ""
	for raw in lines:
		text += String((raw as Dictionary).get("text", "")) + "\n"
	_check(text.contains("无属性词条") and text.contains("进阶后"),
		"法宝详情讲清无词条与进阶预览", text.left(120))
	_check(not text.contains("属性加成："), "法宝详情不显示属性加成")
	panel.queue_free()


func _spawn_player() -> void:
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	await get_tree().process_frame
	await get_tree().process_frame
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.global_position = Vector2.ZERO


func _fresh_player() -> void:
	_p.reset_player()
	_p.max_hp = 1000.0
	_p.hp = 1000.0
	_p.max_mana = 1000.0
	_p.mana = 1000.0
	_p.invincible_timer = 0.0
	_p._hit_negated_timer = 0.0
	_p.is_dodging = false
	_p.is_parrying = false
	_p._counter_charging = false
	_p.auto_parry_timer = 0.0
	_p.debuffs.clear()
	_p._summon_cooldowns.clear()


func _test_player_blood_seal() -> void:
	print("\n-- 玩家侧：血饲印 --")
	_fresh_player()
	var tpl := ItemDB.get_treasure_template("tr_xuesi_yin")
	var item := CharacterData.make_treasure_instance(tpl)
	_p.hp = 1000.0
	_p.mana = 100.0
	_p.skill_cooldowns["skill_qi_gather"] = 5.0
	_p._start_blood_seal_treasure(item, tpl)
	_check(is_equal_approx(_p.hp, 850.0), "血饲支付 15% 最大气血",
		"hp=%.1f" % _p.hp)
	_check(_p.skill_cooldowns.is_empty(), "全部功法冷却已清")
	_check(is_equal_approx(_p.mana, 400.0), "回复 30% 最大灵力",
		"mana=%.1f" % _p.mana)
	_check(is_equal_approx(_p.summon_cooldown_left("tr_xuesi_yin"), 60.0), "冷却 60 秒")
	_p.hp = 200.0
	_p._summon_cooldowns.clear()
	_p._start_blood_seal_treasure(item, tpl)
	_check(is_equal_approx(_p.hp, 200.0), "气血低于 25% 不能血饲",
		"hp=%.1f" % _p.hp)


func _test_player_swap() -> void:
	print("\n-- 玩家侧：换位玦 --")
	_fresh_player()
	var tpl := ItemDB.get_treasure_template("tr_huanwei_jue")
	var item := CharacterData.make_treasure_instance(tpl)
	var d := DummyBoss.new()
	d.global_position = Vector2(200.0, 0.0)
	add_child(d)
	_p.global_position = Vector2.ZERO
	_p._start_swap_treasure(item, tpl)
	_check(is_equal_approx(_p.global_position.x, 200.0), "玩家换到目标位置",
		str(_p.global_position))
	_check(is_equal_approx(d.global_position.x, 0.0), "目标换到玩家旧位置",
		str(d.global_position))
	_check(_p.invincible_timer >= 0.39, "落地 0.4 秒无敌")
	_check(is_equal_approx(_p.summon_cooldown_left("tr_huanwei_jue"), 45.0),
		"冷却 45 秒")
	_check(is_equal_approx(_p.mana, 980.0), "消耗 20 灵力")
	d.queue_free()


func _test_player_thorns() -> void:
	print("\n-- 玩家侧：棘甲佩 --")
	_fresh_player()
	var tpl := ItemDB.get_treasure_template("tr_jijia_pei")
	var item := CharacterData.make_treasure_instance(tpl)
	var d := DummyBoss.new()
	d.global_position = Vector2(100.0, 0.0)
	add_child(d)
	_p._start_thorns_treasure(item, tpl)
	_check(_p._thorns_left > 3.9, "棘甲持续 4 秒")
	_check(_p.has_buff("jijia"), "HUD 棘甲 buff")
	_check(is_equal_approx(_p._thorns_ratio, 0.30), "反弹 30%")
	_p.hp = 1000.0
	_p.invincible_timer = 0.0
	_p.take_damage(100.0, "physical_melee", d)
	_check(not d.true_hits.is_empty(), "近战受击反弹给攻击者",
		str(d.true_hits))
	_p.hp = 1000.0
	_p.invincible_timer = 0.0
	d.true_hits.clear()
	_p.take_damage(100.0, "elemental", d)
	_check(d.true_hits.is_empty(), "法术受击不反弹")
	_p._tick_thorns_treasure(4.1)
	_check(_p._thorns_left == 0.0 and not _p.has_buff("jijia"), "4 秒后棘甲结束")
	d.queue_free()


func _test_player_gust() -> void:
	print("\n-- 玩家侧：回风袋 --")
	_fresh_player()
	var tpl := ItemDB.get_treasure_template("tr_huifeng_dai")
	var item := CharacterData.make_treasure_instance(tpl)
	var near := DummyBoss.new()
	near.global_position = Vector2(100.0, 0.0)
	add_child(near)
	var near2 := DummyBoss.new()
	near2.global_position = Vector2(180.0, 0.0)
	add_child(near2)
	var far := DummyBoss.new()
	far.global_position = Vector2(500.0, 0.0)
	add_child(far)
	var ally := DummyBoss.new()
	ally.is_ally = true
	ally.global_position = Vector2(120.0, 0.0)
	add_child(ally)
	_p._start_gust_treasure(item, tpl)
	_check(not near.knockbacks.is_empty(), "圈内敌人被推开")
	_check(not near2.knockbacks.is_empty(), "圈内第二个敌人被推开")
	_check(far.knockbacks.is_empty(), "圈外不推")
	_check(ally.knockbacks.is_empty(), "不推友军召唤物")
	_check(is_equal_approx(_p.summon_cooldown_left("tr_huifeng_dai"), 30.0),
		"冷却 30 秒")
	near.queue_free()
	near2.queue_free()
	far.queue_free()
	ally.queue_free()


func _spawn_enemy() -> void:
	_enemy = (load("res://scenes/world/world_enemy.tscn") as PackedScene).instantiate()
	var cfg := {
		"pos": Vector2(180.0, 0.0),
		"max_hp": 1000.0,
		"attack_power": 20.0,
		"visual_id": "player_liqingyun",
		"move_speed": 120.0,
		"aggro_range": 600.0,
		"leash_range": 1000.0,
		"skills": [],
		"treasure_mana_max": 100.0,
		"treasure_trigger_hp_ratio": 0.55,
	}
	_enemy.configure(cfg, "cultivator", "测试野修")
	add_child(_enemy)
	await get_tree().process_frame
	await get_tree().process_frame
	_enemy.set_physics_process(false)
	_enemy.set_process(false)
	_fresh_player()
	_p.global_position = Vector2.ZERO
	_enemy.global_position = Vector2(180.0, 0.0)
	_enemy.spawn_home = Vector2(180.0, 0.0)
	_enemy._engaged = true
	_enemy.target = _p
	_enemy._treasure_mana = 100.0


func _set_enemy_treasure(id: String) -> void:
	var tpl := ItemDB.get_treasure_template(id)
	_enemy.carried_treasure = CharacterData.make_treasure_instance(tpl)
	_enemy._treasure_cooldown_left = 0.0
	_enemy._treasure_mana = 100.0
	_enemy._thorns_left = 0.0
	_enemy._thorns_ratio = 0.0
	_enemy.current_hp = _enemy.max_hp
	_enemy.state = BossBase.BossState.IDLE
	_enemy._treasure_invuln_left = 0.0
	_enemy._skill_cd = 0.0
	_fresh_player()
	_p.global_position = Vector2.ZERO
	_enemy.global_position = Vector2(180.0, 0.0)
	_enemy._engaged = true
	_enemy.target = _p


func _test_enemy_blood_seal() -> void:
	print("\n-- 野修侧：血饲印 --")
	_set_enemy_treasure("tr_xuesi_yin")
	_enemy.current_hp = _enemy.max_hp * 0.6
	_enemy._skill_cd = 3.0
	_enemy._tick_carried_treasure(0.1)
	_check(is_equal_approx(_enemy.current_hp, _enemy.max_hp * 0.45),
		"野修支付 15% 最大气血", "hp=%.1f" % _enemy.current_hp)
	_check(_enemy._skill_cd == 0.0, "野修功法冷却已清")
	_check(is_equal_approx(_enemy._treasure_cooldown_left, 60.0), "野修冷却 60 秒")


func _test_enemy_swap() -> void:
	print("\n-- 野修侧：换位玦 --")
	_set_enemy_treasure("tr_huanwei_jue")
	_enemy.global_position = Vector2(180.0, 0.0)
	_p.global_position = Vector2.ZERO
	_enemy._tick_carried_treasure(0.1)
	_check(is_equal_approx(_enemy.global_position.x, 0.0), "野修换到玩家旧位置",
		str(_enemy.global_position))
	_check(is_equal_approx(_p.global_position.x, 180.0), "玩家换到野修旧位置",
		str(_p.global_position))
	_check(_enemy._treasure_invuln_left >= 0.39, "野修落地 0.4 秒无敌")
	_check(is_equal_approx(_enemy._treasure_mana, 80.0), "野修消耗 20 灵力")


func _test_enemy_thorns() -> void:
	print("\n-- 野修侧：棘甲佩 --")
	_set_enemy_treasure("tr_jijia_pei")
	_enemy.global_position = Vector2(100.0, 0.0)
	_p.global_position = Vector2.ZERO
	_enemy._tick_carried_treasure(0.1)
	_check(_enemy._thorns_left > 3.9, "野修棘甲持续 4 秒")
	_check(is_equal_approx(_enemy._thorns_ratio, 0.30), "野修反弹 30%")
	_p.hp = 1000.0
	_p.invincible_timer = 0.0
	var hp_before: float = _p.hp
	_enemy.take_damage(100.0, _p, "physical", "", false)
	var taken: float = hp_before - float(_p.hp)
	_check(taken > 0.0, "玩家近战打野修会被反伤", "hp_loss=%.1f" % taken)
	_p.hp = 1000.0
	_p.invincible_timer = 0.0
	hp_before = _p.hp
	_enemy.take_damage(100.0, _p, "physical", "", true)
	_check(is_equal_approx(_p.hp, hp_before), "物理投射物不触发反伤")


func _test_enemy_gust() -> void:
	print("\n-- 野修侧：回风袋 --")
	_set_enemy_treasure("tr_huifeng_dai")
	_enemy.global_position = Vector2(100.0, 0.0)
	_p.global_position = Vector2.ZERO
	_enemy._tick_carried_treasure(0.1)
	_check(_p.knockback_velocity.length() > 0.1, "野修把玩家推开")
	_check(is_equal_approx(_enemy._treasure_cooldown_left, 30.0), "野修冷却 30 秒")
