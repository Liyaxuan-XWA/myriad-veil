extends Node2D
## 符箓系统 2026-10-31：数据 / 4 格装符 / 瞬发 / 七效果 / 制作规则

class DummyBoss extends Node2D:
	var hits: Array = []
	var debuffs: Dictionary = {}
	var stuns: Array = []
	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			elem: String = "", _proj: bool = false) -> void:
		hits.append({"amount": amount, "elem": elem})
	func apply_debuff(id: String, duration: float) -> bool:
		debuffs[id] = duration
		return true
	func remove_debuff(id: String) -> void:
		debuffs.erase(id)
	func has_debuff(id: String) -> bool:
		return debuffs.has(id)
	func stun_for(seconds: float) -> void:
		stuns.append(seconds)
	func is_dead() -> bool:
		return false
	func hit_spheres() -> Array:
		return [Vector3(0.0, -20.0, 40.0)]

var _passes := 0
var _fails: Array = []
var _p: Node2D
var _dummy: DummyBoss


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 符箓系统探针 ##########")
	# 真实位面口径（演武场现在是无限符箓，不能用来验扣张）
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01", "boss_id": "boss_huyao",
	}
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	_p.global_position = Vector2.ZERO
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.is_teleporting = false
	_p.invincible_timer = 0.0
	_dummy = DummyBoss.new()
	_dummy.add_to_group("boss")
	_dummy.global_position = Vector2(120.0, 0.0)
	add_child(_dummy)
	await get_tree().process_frame

	_test_data()
	_test_patterns()
	_test_loadout()
	await _test_effects()
	_test_craft_rules()
	_test_legacy_removal()
	_test_storage_rules()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _test_data() -> void:
	var def := ItemDB.get_consumable("tal_jinfeng_lianqi")
	_check(not def.is_empty(), "元素符定义可解析")
	_check(String(def.get("talisman_name", "")) == "金锋符·练气", "名称 = 金锋符·练气",
		String(def.get("talisman_name", "")))
	var eff: Dictionary = def.get("battle_effect", {})
	_check(int(eff.get("damage", 0)) == 60, "金锋练气固定 60", str(eff.get("damage")))
	_check(float(def.get("mana_cost", 0.0)) == 5.0, "激活 5 灵力")
	_check(float(def.get("battle_cooldown", 1.0)) == 0.0, "无战斗冷却")
	var fire := ItemDB.get_consumable("tal_huoqiu_jiedan")
	_check(int((fire.get("battle_effect", {}) as Dictionary).get("damage", 0)) == 500,
		"火球结丹固定 500")
	var water := ItemDB.get_consumable("tal_shuihui_zhuji")
	var weff: Dictionary = water.get("battle_effect", {})
	_check(int(weff.get("heal_per_sec", 0)) == 10 and float(weff.get("heal_time", 0)) == 10.0,
		"水愈筑基 10/s × 10s")
	var recipes := ItemDB.element_talisman_recipes()
	_check(ItemDB.ELEMENT_TALISMAN_QUALITIES.size() == 4, "四品阶（练气/筑基/结丹/元婴）")
	_check(recipes.size() == 28, "七类 × 四品阶 = 28 张", str(recipes.size()))
	_check(ItemDB.all_talisman_recipes().size() == 28, "新 7 × 四品阶 = 28 张配方",
		str(ItemDB.all_talisman_recipes().size()))
	var yy_metal := ItemDB.get_consumable("tal_jinfeng_yuanying")
	_check(String(yy_metal.get("talisman_name", "")) == "金锋符·元婴",
		"元婴金锋符命名", String(yy_metal.get("talisman_name", "")))
	_check(int((yy_metal.get("battle_effect", {}) as Dictionary).get("damage", 0)) == 1800,
		"元婴金锋 1800", str((yy_metal.get("battle_effect", {}) as Dictionary).get("damage", 0)))
	var yy_mats: Dictionary = yy_metal.get("materials", {})
	_check(yy_mats.has("mat_yy_ruishoupi"), "元婴攻击符耗幽冥锐兽皮")
	var yy_water := ItemDB.get_consumable("tal_shuihui_yuanying")
	var yweff: Dictionary = yy_water.get("battle_effect", {})
	_check(int(yweff.get("heal_per_sec", 0)) == 16 and float(yweff.get("heal_time", 0)) == 14.0,
		"元婴水愈 16/s × 14s")
	var yy_wind := ItemDB.get_consumable("tal_fengji_yuanying")
	var ywfeff: Dictionary = yy_wind.get("battle_effect", {})
	_check(float(ywfeff.get("speed_pct", 0)) == 45.0 and float(ywfeff.get("duration", 0)) == 18.0,
		"元婴风疾 +45% / 18 秒")
	var yy_stone := ItemDB.get_consumable("tal_tushi_yuanying")
	var yseff: Dictionary = yy_stone.get("battle_effect", {})
	_check(float(yseff.get("damage_reduction", 0)) == 50.0 and int(yseff.get("hits", 0)) == 6,
		"元婴石附 -50% / 挡 6 次")
	var stone := ItemDB.get_consumable("tal_tushi_jiedan")
	var seff: Dictionary = stone.get("battle_effect", {})
	_check(float(seff.get("damage_reduction", 0)) == 40.0 and int(seff.get("hits", 0)) == 5,
		"石附结丹 -40% / 挡 5 次")
	var wind := ItemDB.get_consumable("tal_fengji_jiedan")
	var weff2: Dictionary = wind.get("battle_effect", {})
	_check(float(weff2.get("speed_pct", 0)) == 40.0 and float(weff2.get("duration", 0)) == 15.0,
		"风疾结丹 +40% / 15 秒")


func _test_patterns() -> void:
	var ids := ["tal_jinfeng_lianqi", "tal_huoqiu_lianqi", "tal_yinlei_lianqi",
		"tal_muling_lianqi", "tal_shuihui_lianqi", "tal_fengji_lianqi", "tal_tushi_lianqi"]
	var seen := {}
	for id in ids:
		var p := TalismanPatterns.for_item(String(id))
		_check(p.size() > 0, "符路存在 " + String(id), str(p.size()))
		var sig := str(p)
		_check(not seen.has(sig), "符路唯一 " + String(id))
		seen[sig] = true
	_check(seen.size() == 7, "7 种符 7 条不同符路", str(seen.size()))
	for e in ["metal", "wood", "water", "fire", "earth", "wind", "thunder"]:
		var card_path := "res://assets/ui/talisman/cards/talisman_card_%s.png" % e
		_check(ResourceLoader.exists(card_path), "元素符卡面存在 " + String(e))
		var img := Image.load_from_file(card_path)
		_check(img != null and img.get_width() == 640 and img.get_height() == 960,
			"卡面 640×960（2:3）" + String(e),
			"%dx%d" % [img.get_width(), img.get_height()] if img != null else "null")
		# 中心必须画满该五行的符胆。实测（同一取样框）：
		#   2026-11-02 新卡面 σ = 40.2 ~ 60.9；旧卡面（一圈外框 + 空椭圆）σ = 1.8 ~ 19.2
		# 阈值取 30：新卡面最空的金属符也留 10 点余量，旧的空中心绝不可能过
		var std := _center_std(img)
		_check(std >= 30.0, "卡面中心已画满符胆 " + String(e), "σ=%.1f" % std)


## 中心区域（横 30%~70%、纵 34%~66%）的亮度标准差
func _center_std(img: Image) -> float:
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var sum_sq := 0.0
	var n := 0
	for y in range(int(h * 0.34), int(h * 0.66), 4):
		for x in range(int(w * 0.30), int(w * 0.70), 4):
			var c := img.get_pixel(x, y)
			# get_pixel 的通道是 0~1，乘回 0~255 才能和 PIL 口径对上
			var v := (c.r + c.g + c.b) / 3.0 * 255.0
			sum += v
			sum_sq += v * v
			n += 1
	if n == 0:
		return 0.0
	var mean := sum / float(n)
	return sqrt(maxf(0.0, sum_sq / float(n) - mean * mean))


func _test_loadout() -> void:
	CharacterData.active_skill_loadout = ["talisman:tal_jinfeng_lianqi", "", "", ""]
	var slots := CharacterData.equipped_active_skills()
	_check(String(slots[0]) == "talisman:tal_jinfeng_lianqi", "4 功法格可装符箓")
	_check(CharacterData.active_skill_count() == 1, "符箓占 1 个功法格")


func _test_effects() -> void:
	CharacterData.active_skill_loadout = ["talisman:tal_jinfeng_lianqi", "", "", ""]
	_give("tal_jinfeng_lianqi", 3)
	_check(_inventory_type_count("talisman") == 0, "符箓不占背包格")
	_check(CharacterData.talisman_count("tal_jinfeng_lianqi") == 3, "符箓进入符匣")
	_p.mana = 100.0
	_dummy.hits.clear()
	_check(_p.use_talisman_slot("talisman:tal_jinfeng_lianqi"), "从功法格瞬发金锋符")
	_check(is_equal_approx(_p.mana, 95.0), "消耗 5 灵力", "%.1f" % _p.mana)
	_check(CharacterData.talisman_count("tal_jinfeng_lianqi") == 2, "消耗 1 张，堆叠变 2")
	_check(_dummy.hits.is_empty(), "符卡落点前不结算")
	await get_tree().create_timer(1.0).timeout
	_check(_dummy.hits.size() == 1 and is_equal_approx(float(_dummy.hits[0]["amount"]), 60.0),
		"金锋固定 60 伤害", str(_dummy.hits))
	_check(String(_dummy.hits[0]["elem"]) == "metal", "金锋伤害元素 = 金")

	_give("tal_huoqiu_lianqi", 1)
	_dummy.hits.clear()
	_dummy.debuffs.clear()
	_p.mana = 100.0
	_check(_p.use_talisman("tal_huoqiu_lianqi"), "瞬发火球符")
	await get_tree().create_timer(1.0).timeout
	_check(_dummy.hits.size() >= 1 and is_equal_approx(float(_dummy.hits[0]["amount"]), 50.0),
		"火球固定 50 伤害", str(_dummy.hits))
	_check(_dummy.has_debuff("burn"), "火球挂灼烧")

	_give("tal_yinlei_lianqi", 1)
	_dummy.hits.clear()
	_p.mana = 100.0
	_check(_p.use_talisman("tal_yinlei_lianqi"), "瞬发引雷符")
	await get_tree().create_timer(1.0).timeout
	_check(_dummy.hits.size() == 1 and is_equal_approx(float(_dummy.hits[0]["amount"]), 50.0),
		"引雷固定 50 伤害", str(_dummy.hits))

	_give("tal_muling_lianqi", 1)
	_dummy.debuffs.clear()
	_p.mana = 100.0
	_check(_p.use_talisman("tal_muling_lianqi"), "瞬发木缚符")
	await get_tree().create_timer(1.0).timeout
	_check(is_equal_approx(float(_dummy.debuffs.get("rooted", 0.0)), 2.0),
		"木缚定身 2 秒", str(_dummy.debuffs))

	_give("tal_shuihui_lianqi", 1)
	_p.hp = 50.0
	_p.mana = 100.0
	_check(_p.use_talisman("tal_shuihui_lianqi"), "瞬发水愈符")
	await get_tree().create_timer(1.0).timeout
	_check(_p.has_buff("talisman_water"), "水愈挂持续恢复")
	_p._tick_talisman_effects(1.0)
	_check(_p.hp > 50.0, "水愈每秒回血", "%.1f" % _p.hp)

	_give("tal_fengji_lianqi", 1)
	_p.mana = 100.0
	var speed_before := float(CharacterData.attribute(AttributeDB.ATTR_SPEED_PCT))
	var move_before := CharacterData.move_speed()
	_check(_p.use_talisman("tal_fengji_lianqi"), "瞬发风疾符")
	await get_tree().create_timer(1.0).timeout
	_check(_p.has_buff("talisman_wind"), "风疾挂移速 buff")
	_check(is_equal_approx(
		float(CharacterData.attribute(AttributeDB.ATTR_SPEED_PCT)) - speed_before, 30.0),
		"风疾练气 +30% 移速")
	_check(_p._talisman_wind_left >= 9.9, "风疾练气持续 10 秒",
		"%.1f" % _p._talisman_wind_left)
	_check(CharacterData.move_speed() >= move_before * 1.29,
		"风疾实际移速明显提升", "%.1f -> %.1f" % [move_before, CharacterData.move_speed()])
	_p._tick_talisman_effects(11.0)
	_check(not _p.has_buff("talisman_wind"), "风疾到期移除")

	_give("tal_tushi_lianqi", 1)
	_p.hp = _p.max_hp
	_p.mana = 100.0
	_check(_p.use_talisman("tal_tushi_lianqi"), "瞬发石附符")
	await get_tree().create_timer(1.0).timeout
	_check(_p.has_buff("talisman_stone") and _p._talisman_stone_hits == 3,
		"石附挡 3 次")
	_p.take_damage(10.0, "physical", null, "")
	_check(_p._talisman_stone_hits == 2, "受伤消耗 1 次", str(_p._talisman_stone_hits))
	_p.invincible_timer = 0.0
	_p.take_damage(10.0, "physical", null, "")
	_p.invincible_timer = 0.0
	_p.take_damage(10.0, "physical", null, "")
	_check(not _p.has_buff("talisman_stone"), "3 次后石附解除")

	# 无目标：攻击符不消耗
	_dummy.global_position = Vector2(2000.0, 0.0)
	_give("tal_yinlei_lianqi", 1)
	var cnt := CharacterData.talisman_count("tal_yinlei_lianqi")
	_p.mana = 100.0
	_check(not _p.use_talisman("tal_yinlei_lianqi"), "无目标时引雷不施放")
	_check(CharacterData.talisman_count("tal_yinlei_lianqi") == cnt and is_equal_approx(_p.mana, 100.0),
		"无目标不扣符/灵力")
	_dummy.global_position = Vector2(120.0, 0.0)


func _test_craft_rules() -> void:
	var saved_realm := CharacterData.current_realm
	var saved_stage := CharacterData.realm_stage
	var saved_exp := CharacterData.realm_exp
	CharacterData.current_realm = "练气"
	CharacterData.realm_stage = 0
	_check(is_equal_approx(ItemDB.talisman_success_rate("练气"), 1.0), "同级制作 100%")
	_check(is_equal_approx(ItemDB.talisman_success_rate("筑基"), 0.05), "越一级 5%")
	_check(is_equal_approx(ItemDB.talisman_success_rate("结丹"), 0.0), "越两级不可制作")
	CharacterData.realm_exp = 500.0
	_check(CharacterData.spend_realm_exp(10.0) and is_equal_approx(CharacterData.realm_exp, 490.0),
		"制作扣修为 10")
	_check(not CharacterData.spend_realm_exp(1000.0), "修为不足拒绝制作")
	# 同级制作：100% 成功，扣材料 + 修为
	CharacterData.current_realm = "练气"
	CharacterData.realm_stage = 0
	CharacterData.realm_exp = 500.0
	CharacterData.add_item({"id": "mat_ruishoupi", "type": "material", "count": 1})
	var recipe := ItemDB.get_talisman_recipe("recipe_tal_huoqiu_lianqi")
	var before := CharacterData.talisman_count("tal_huoqiu_lianqi")
	var bag_before := CharacterData.inventory.size()
	var res := CharacterData.craft_talisman(recipe, 1)
	_check(bool(res.get("ok", false)) and bool(res.get("success", false)),
		"同级制符 100% 成功", String(res.get("message", "")))
	_check(CharacterData.talisman_count("tal_huoqiu_lianqi") == before + 1, "制符产出 1 张")
	_check(_inventory_type_count("talisman") == 0, "制符不占背包格")
	_check(is_equal_approx(CharacterData.realm_exp, 490.0), "制符扣 10 修为")
	# 批量：同级 100% 时 3 张全成，材料与修为按张扣
	CharacterData.add_item({"id": "mat_ruishoupi", "type": "material", "count": 3})
	var batch_res := CharacterData.craft_talisman(recipe, 3)
	_check(int(batch_res.get("attempts", 0)) == 3 and int(batch_res.get("success_count", 0)) == 3,
		"批量 3 张同级全成", String(batch_res.get("message", "")))
	_check(CharacterData.talisman_count("tal_huoqiu_lianqi") == before + 4, "批量产出 3 张")
	_check(is_equal_approx(CharacterData.realm_exp, 460.0), "批量扣 30 修为")
	var cross := ItemDB.get_talisman_recipe("recipe_tal_huoqiu_jiedan")
	var res2 := CharacterData.craft_talisman(cross, 1)
	_check(not bool(res2.get("ok", false)), "越两级制符被拒绝", String(res2.get("message", "")))
	CharacterData.current_realm = saved_realm
	CharacterData.realm_stage = saved_stage
	CharacterData.realm_exp = saved_exp



func _test_legacy_removal() -> void:
	CharacterData.add_item({
		"id": "tal_pofengfu", "name": "烈火符", "type": "talisman", "count": 2,
	})
	CharacterData.active_skill_loadout[0] = "talisman:tal_pofengfu"
	var removed := CharacterData.migrate_remove_legacy_talismans()
	_check(removed == 1, "旧符读档迁移移除物品", str(removed))
	_check(CharacterData.talisman_count("tal_pofengfu") == 0, "旧符物品清零")
	_check(String(CharacterData.active_skill_loadout[0]) == "", "旧符功法格清空")


func _give(item_id: String, count: int) -> void:
	var def := ItemDB.get_consumable(item_id)
	CharacterData.add_item({
		"id": item_id,
		"name": String(def.get("pill_name", def.get("talisman_name", item_id))),
		"type": "talisman",
		"count": count,
		"icon": String(def.get("icon", "")),
	})


func _inventory_type_count(item_type: String) -> int:
	var n := 0
	for it in CharacterData.inventory:
		if String((it as Dictionary).get("type", "")) == item_type:
			n += 1
	return n


## 符匣边界：旧背包符迁移、丢弃白名单、符匣不计背包格
func _test_storage_rules() -> void:
	var saved_inv := CharacterData.inventory.duplicate(true)
	var saved_stock := CharacterData.talisman_stock.duplicate(true)
	# 1) 旧档背包里的符整堆迁进符匣，丹药留在背包
	CharacterData.talisman_stock = {}
	CharacterData.inventory = [
		{"id": "tal_huoqiu_lianqi", "name": "火球符·练气", "type": "talisman", "count": 2},
		{"id": "pill_juli", "name": "巨力丹", "type": "pill", "count": 1},
	]
	var moved := CharacterData.migrate_talismans_to_cabinet()
	_check(moved == 1, "旧背包符迁移到符匣", str(moved))
	_check(CharacterData.talisman_count("tal_huoqiu_lianqi") == 2, "迁移保留张数")
	_check(_inventory_type_count("talisman") == 0 and CharacterData.inventory.size() == 1,
		"迁移后背包只剩丹药")
	# 2) 丢弃白名单：突破材料不可丢，其它可丢
	_check(CharacterData.can_discard_item({"id": "pill_juli", "type": "pill"}), "丹药可丢弃")
	_check(CharacterData.can_discard_item({"id": "mat_ruishoupi", "type": "material"}),
		"普通材料可丢弃")
	_check(not CharacterData.can_discard_item({"id": "mat_pojing_zhuji", "type": "material"}),
		"突破材料不可丢弃")
	_check(ItemDB.is_breakthrough_material("mat_pojing_huashen"),
		"突破材料判定覆盖占位材料")
	# 3) 符匣消耗 / 归零
	CharacterData.talisman_stock = {"tal_jinfeng_lianqi": 1}
	_check(CharacterData.consume_talisman("tal_jinfeng_lianqi"), "符匣可消耗")
	_check(CharacterData.talisman_count("tal_jinfeng_lianqi") == 0
		and not CharacterData.talisman_stock.has("tal_jinfeng_lianqi"), "最后一张归零移除")
	CharacterData.inventory = saved_inv
	CharacterData.talisman_stock = saved_stock
