extends Node2D
## 晏无咎 / 三灾轮转 全链路自检（2026-10-29）

class StubPlayer extends Node2D:
	var is_dead := false
	var is_dodging := false
	var is_teleporting := false
	var knockback_velocity := Vector2.ZERO
	var debuffs: Dictionary = {}
	var hits: Array = []
	var calamity_element: String = ""
	func take_damage(amount: float, _kind: String = "physical", _source: Node = null,
			_elem: String = "") -> void:
		hits.append(amount)
	func apply_debuff(id: String, duration: float, _quiet := false) -> bool:
		debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
		return true
	func clear_debuff(id: String) -> void:
		debuffs.erase(id)
	func head_top_y() -> float:
		return -110.0
	func calamity_state() -> String:
		return calamity_element

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
	print("\n########## 晏无咎 · 三灾轮转 探针 ##########")
	await get_tree().process_frame
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	_test_data()
	await _test_boss()
	await _test_ai_pool()
	await _test_player()
	_test_ordinary_break()
	_test_resolve()


func _test_data() -> void:
	var forms := ["form_calamity_step", "form_calamity_slash", "form_calamity_fire_seal",
		"form_calamity_fire_field", "form_calamity_thunder_strike",
		"form_calamity_thunder_pool", "form_calamity_turn", "form_calamity_final"]
	for f in forms:
		_check(MoveDB.has_form(String(f)), "形态已登记 " + String(f))
		_check(not MoveDB.resolve_boss(String(f)).is_empty(), "BOSS 侧可解析 " + String(f))
		_check(not MoveDB.resolve_player(String(f)).is_empty(), "玩家侧可解析 " + String(f))
	var ids := ["skill_calamity_step", "skill_calamity_slash", "skill_calamity_fire_seal",
		"skill_calamity_fire_field", "skill_calamity_thunder_strike",
		"skill_calamity_thunder_pool", "skill_calamity_turn", "skill_calamity_final"]
	for sid in ids:
		var sk := SkillDB.get_skill(String(sid))
		_check(not sk.is_empty(), "功法已登记 " + String(sid))
		_check(bool(sk.get("calamity", false)), "功法带 calamity 标记 " + String(sid))
		_check(SkillDB.get_effect_lines(String(sid)).size() >= 3,
			"功法效果行 >=3 " + String(sid))
	var passive := SkillDB.get_skill("skill_calamity_body")
	_check(not passive.is_empty() and String(passive.get("passive_effect", "")) == "calamity_stance",
		"三灾·灾身被动已登记")
	_check(SkillDB.get_effect_lines("skill_calamity_body").size() >= 3,
		"三灾·灾身被动说明 >=3 行")
	_check(WorldDB.get_boss_name("boss_03_c") == "晏无咎", "boss_03_c 定名晏无咎")
	_check(WorldDB.get_boss_scene("boss_03_c").ends_with("domain_boss_03_c.tscn"),
		"BOSS 场景已登记")
	_check(not WorldDB.get_boss_moves("boss_03_c").is_empty(), "BOSS 招式组已登记")
	_check(String(WorldDB.get_floor(9).get("boss_id", "")) == "boss_03_c",
		"塔第 9 层 = 晏无咎")
	_check(WorldDB.get_floor_reward_skills(9).size() == 9, "塔 9 层感悟池 = 9 门",
		"n=%d" % WorldDB.get_floor_reward_skills(9).size())
	var codex := CodexDB.boss_entry("boss_03_c")
	_check(not codex.is_empty(), "图鉴卡已登记")
	_check((codex.get("mechanic_points", []) as Array).size() >= 8, "图鉴机制要点 >=8")
	_check(CodexDB.boss_status_info("boss_03_c").size() >= 4, "图鉴状态 >=4")
	_check(not ItemDB.get_drops_for_boss("boss_03_c").is_empty(), "掉落表已登记")
	var drop_table := ItemDB.get_drops_for_boss("boss_03_c")
	var table_ids: Array = []
	for d in drop_table:
		table_ids.append(String((d as Dictionary).get("item_id", "")))
	_check("eq_jiefeng" in table_ids and "eq_jiehui_fayi" in table_ids,
		"掉落表含两件装备", str(table_ids))
	_check("mat_chixiao_jiehui" in table_ids, "掉落表含赤霄劫灰", str(table_ids))
	_check(not ItemDB.soul_for_boss("boss_03_c").is_empty(), "元魂对应配方")
	var plane_rec := ItemDB.get_plane_treasure_recipe("domain_03")
	_check(plane_rec.get("result_id", "") == "tr_sanzai_lun", "位面法宝产物 = 三灾轮")
	_check((plane_rec.get("material_ids", []) as Array).size() == 3, "三件材料配方")
	_check(not ItemDB.get_equipment_template("eq_jiefeng").is_empty(), "劫锋已登记")
	_check(not ItemDB.get_equipment_template("eq_jiehui_fayi").is_empty(), "劫灰法衣已登记")
	_check(not ItemDB.get_material("mat_chixiao_jiehui").is_empty(), "赤霄劫灰已登记")
	_check(not ItemDB.get_material("soul_yanwujiu").is_empty(), "晏无咎元魂已登记")
	_check(not ItemDB.get_treasure_template("tr_jiezhu_ling").is_empty(), "劫主令已登记")
	_check(not ItemDB.get_treasure_template("tr_sanzai_lun").is_empty(), "三灾轮已登记")
	_check(not ItemDB.get_synth_recipe_by_soul("soul_yanwujiu").is_empty(), "劫主令配方已登记")
	_check(not ItemDB.get_plane_treasure_recipe("domain_03").is_empty(),
		"domain_03 位面法宝配方已登记")
	for p in ["res://assets/ui/codex/card_boss_wujiu.png",
			"res://assets/scenes/calamity_arena_ground.png",
			"res://assets/characters/boss/wujiu_rig/rig.tres",
			"res://assets/effects/skills/calamity_wheel.png",
			"res://assets/ui/icon/equip_jiefeng.png",
			"res://assets/ui/icon/equip_jiehui_fayi.png",
			"res://assets/ui/icon/mat_chixiao_jiehui.png",
			"res://assets/ui/icon/soul_yanwujiu.png",
			"res://assets/ui/icon/tr_jiezhu_ling.png",
			"res://assets/ui/icon/tr_sanzai_lun.png"]:
		_check(ResourceLoader.exists(String(p)), "美术资源存在", String(p))
	for sid in ids:
		_check(ResourceLoader.exists(String(SkillDB.get_skill(String(sid)).get("icon", ""))),
			"技能图标存在 " + String(sid))
	var rule_has_guard := false
	for line in SkillDB.get_calamity_rules():
		if String(line).contains("灾替"):
			rule_has_guard = true
	_check(rule_has_guard, "功法库规则卡解释灾替")
	_check(String(BuffDB.get_buff("sanzai_guard").get("desc", "")).contains("免疫"),
		"轮转灾替 buff 写明免破")
	_check(SkillDB.get_group_rules("boss_03_c").get("title", "").contains("三灾"),
		"功法库组规则卡已挂")
	_check(not BuffDB.get_buff("sanzai_guard").is_empty(), "灾替 buff 已登记")
	for did in ["jie_huo", "gan_dian", "suo_zai", "zai_beng"]:
		_check(not DebuffDB.get_debuff(String(did)).is_empty(), "状态已登记 " + String(did))
	_check(DebuffDB.effect_text("suo_zai").contains("灾位"), "锁灾效果文字含灾位")
	var domain_bosses: Array = WorldDB.get_domain("domain_03").get("boss_ids", [])
	_check("boss_03_c" in domain_bosses, "domain_03 含晏无咎")
	var groups := SkillDB.get_library_groups()
	var found_group := false
	for g in groups:
		if String((g as Dictionary).get("group_id", "")) == "boss_03_c":
			found_group = true
			_check(int((g as Dictionary).get("total", 0)) == 9, "功法库晏无咎组 9 门")
	_check(found_group, "功法库出现晏无咎分组")
	_check(WorldDB.get_floors().size() >= 10, "万界塔至少排到照影界首位（第 10 层）")


func _test_boss() -> void:
	var sp := StubPlayer.new()
	sp.add_to_group("player")
	sp.global_position = Vector2(220.0, 0.0)
	sp.calamity_element = "fire"
	add_child(sp)
	var boss = (load("res://scenes/boss/domain_boss_03_c.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.set_arena_bounds(Vector2(600.0, 380.0), Vector2.ZERO)
	boss.target = sp
	boss._update_threat_target(true)
	_check(is_equal_approx(boss.max_hp, 20500.0), "BOSS 血量按结丹后期反推",
		"hp=%.0f" % boss.max_hp)
	_check(is_equal_approx(boss.attack_power, 108.0), "BOSS 攻击按结丹后期反推",
		"atk=%.0f" % boss.attack_power)
	_check(boss.calamity_state() == "wind", "初始灾位风")
	_check(boss._wheel_ui != null and is_instance_valid(boss._wheel_ui), "BOSS 三灾轮 HUD 已创建")
	_check(boss._wheel_ui.visible, "BOSS 三灾轮显示")
	# 破灾：玩家火克风（火克雷、雷克风、风克火；火不克风）→ 用雷克风
	sp.calamity_element = "thunder"
	var before_hp: float = boss.current_hp
	var broke: bool = boss.on_calamity_broken(sp)
	_check(broke, "克位命中触发破灾")
	_check(boss.is_calamity_broken(), "破灾后进入灾崩")
	_check(is_equal_approx(boss.damage_taken_multiplier("physical"), 1.30),
		"灾崩受伤 +30%")
	_check(String(DebuffDB.get_debuff("zai_beng").get("desc", "")).contains("30%"),
		"灾崩状态描述同步 30%")
	# 不只查函数：真正走 take_damage，防止基础 clamp 把 >1 的易伤吃掉
	boss._broken_left = 0.0
	boss._fusion_left = 0.0
	boss._turn_guard_left = 0.0
	var hp_n: float = boss.current_hp
	boss.take_damage(100.0)
	var d_n: float = hp_n - boss.current_hp
	boss._broken_left = 3.0
	var hp_b: float = boss.current_hp
	boss.take_damage(100.0)
	var d_b: float = hp_b - boss.current_hp
	_check(d_b > d_n * 1.25, "灾崩易伤真正进入结算",
		"normal %.1f / broken %.1f" % [d_n, d_b])
	boss._broken_left = 0.0
	boss._fusion_left = 1.0
	var hp_f: float = boss.current_hp
	boss.take_damage(100.0)
	var d_f: float = hp_f - boss.current_hp
	_check(d_f > d_n * 1.15, "三灾归一易伤真正进入结算",
		"normal %.1f / fusion %.1f" % [d_n, d_f])
	boss._fusion_left = 0.0
	# 玩家挂的感电在 BOSS 端也要真正加伤
	boss._broken_left = 0.0
	boss._turn_guard_left = 0.0
	boss.debuffs.erase("gan_dian")
	var hp_g0: float = boss.current_hp
	boss.take_damage(100.0)
	var d_g0: float = hp_g0 - boss.current_hp
	boss.apply_debuff("gan_dian", 3.0)
	var hp_g1: float = boss.current_hp
	boss.take_damage(100.0)
	var d_g1: float = hp_g1 - boss.current_hp
	_check(d_g1 > d_g0 * 1.10, "感电在 BOSS 端真正增伤",
		"normal %.1f / gan_dian %.1f" % [d_g0, d_g1])
	boss.debuffs.erase("gan_dian")
	_check(boss._momentum == 0, "破灾扣 BOSS 灾势")
	# 轮转
	boss._calamity = "fire"
	boss._momentum = 1
	boss._cast_turn(MoveDB.resolve_boss("form_calamity_turn"))
	_check(boss.calamity_state() != "fire", "三灾轮转换了灾位", boss.calamity_state())
	# 万劫归一（含命中后的灾崩 debuff）
	boss._momentum = 2
	sp.global_position = Vector2(150.0, 0.0)
	sp.debuffs.clear()
	boss._cast_final(MoveDB.resolve_boss("form_calamity_final"))
	await get_tree().create_timer(0.7).timeout
	_check(boss._momentum == 0, "万劫归一清空灾势")
	_check(sp.debuffs.has("zai_beng"), "万劫归一命中施加灾崩")
	# 二阶段三灾归一
	boss._turn_guard_left = 0.0
	boss._on_phase_two()
	_check(boss.calamity_state() == "fusion", "二阶段进入三灾归一")
	var fusion_m: float = boss.damage_taken_multiplier("physical")
	_check(fusion_m >= 1.19, "归一期间受伤至少 +20%", "x%.2f" % fusion_m)
	boss._fusion_left = 0.01
	boss._tick_calamity(0.02)
	_check(boss.calamity_state() != "fusion", "归一结束恢复单灾位")
	# 八式全路径
	for sid in ["form_calamity_step", "form_calamity_slash",
			"form_calamity_fire_seal", "form_calamity_fire_field",
			"form_calamity_thunder_strike", "form_calamity_thunder_pool",
			"form_calamity_turn", "form_calamity_final"]:
		boss._calamity = String(MoveDB.resolve_boss(sid).get("calamity_tag", "wind"))
		if boss._calamity == "final" or boss._calamity == "turn":
			boss._calamity = "fire"
		boss.state = 0
		boss.state_timer = 0.0
		boss._current_skill = sid
		boss._fire_skill()
		if sid == "form_calamity_step":
			boss._tick_step(0.2)
		await get_tree().create_timer(0.75, true, false, true).timeout
	_check(true, "BOSS 八式 cast 全路径已跑通")
	# AI 模拟
	boss.state = 0
	boss._decide_wait = 0.0
	boss.set_physics_process(true)
	await get_tree().create_timer(8.0).timeout
	_check(boss._recent.size() >= 3, "BOSS 自主模拟出招 >= 3", str(boss._recent))
	boss.set_physics_process(false)
	# 雷池锁灾：只锁池内、整池只锁一次
	boss._zones.clear()
	sp.global_position = Vector2.ZERO
	sp.debuffs.clear()
	boss.global_position = Vector2.ZERO
	boss._zones.append({
		"pos": Vector2(500.0, 0.0), "radius": 150.0, "left": 4.0, "tick": 0.0,
		"interval": 1.0, "dmg": 0.0, "kind": "elemental", "elem": "thunder", "lock": 3.0,
	})
	boss._tick_zones(0.01)
	_check(not sp.debuffs.has("suo_zai"), "雷池外不锁灾")
	var z: Dictionary = boss._zones[0]
	z["tick"] = 0.0
	sp.global_position = Vector2(500.0, 0.0)
	boss._tick_zones(0.01)
	_check(sp.debuffs.has("suo_zai"), "雷池内首跳锁灾")
	sp.debuffs.erase("suo_zai")
	z["tick"] = 0.0
	boss._tick_zones(0.01)
	_check(not sp.debuffs.has("suo_zai"), "同一雷池不重复锁灾")
	boss._zones.clear()
	# 二阶段归一门槛 1 层
	boss.phase = 2
	boss._fusion_left = 0.0
	boss._broken_left = 0.0
	boss._calamity = "wind"
	boss._momentum = 1
	boss._cools["form_calamity_final"] = 0.0
	boss._decide_wait = 0.0
	boss.state = 0
	boss._current_skill = ""
	sp.calamity_element = "fire"
	boss.target = sp
	boss._choose()
	_check(boss._current_skill == "form_calamity_final", "二阶段灾势 1 层可放万劫归一",
		boss._current_skill)
	boss.state = 0
	boss._current_skill = ""
	boss.set_physics_process(false)
	boss.queue_free()
	sp.queue_free()
	await get_tree().process_frame



func _test_ai_pool() -> void:
	var sp := StubPlayer.new()
	sp.add_to_group("player")
	sp.global_position = Vector2(220.0, 0.0)
	add_child(sp)
	var boss = (load("res://scenes/boss/domain_boss_03_c.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.target = sp
	seed(20261029)
	var saw: Dictionary = {}
	var neutral := {"wind": "fire", "fire": "thunder", "thunder": "wind"}
	for el in ["wind", "fire", "thunder"]:
		sp.calamity_element = String(neutral[el])
		for d in [80.0, 220.0, 380.0]:
			sp.global_position = Vector2(float(d), 0.0)
			for i in range(30):
				boss.state = 0
				boss._current_skill = ""
				boss._decide_wait = 0.0
				boss._cools.clear()
				boss._recent.clear()
				boss._momentum = 0
				boss._fusion_left = 0.0
				boss._broken_left = 0.0
				boss._turn_guard_left = 0.0
				boss._calamity = String(el)
				boss._choose()
				if boss._current_skill != "":
					saw[boss._current_skill] = true
	for sid in ["form_calamity_step", "form_calamity_slash",
			"form_calamity_fire_seal", "form_calamity_fire_field",
			"form_calamity_thunder_strike", "form_calamity_thunder_pool"]:
		_check(saw.has(sid), "AI 池会选 " + String(sid))
	# 被玩家克 → 轮转；灾势 2 层 → 归一
	boss._calamity = "wind"
	sp.calamity_element = "thunder"
	boss._cools.clear()
	boss._momentum = 0
	boss._fusion_left = 0.0
	boss._broken_left = 0.0
	boss._decide_wait = 0.0
	boss.state = 0
	boss._current_skill = ""
	sp.global_position = Vector2(200.0, 0.0)
	boss._choose()
	_check(boss._current_skill == "form_calamity_turn", "AI 被克时轮转")
	boss._calamity = "wind"
	sp.calamity_element = "fire"
	boss._cools.clear()
	boss._momentum = 2
	boss._decide_wait = 0.0
	boss.state = 0
	boss._current_skill = ""
	boss.phase = 1
	boss._choose()
	_check(boss._current_skill == "form_calamity_final", "AI 灾势 2 层归一")
	boss.queue_free()
	sp.queue_free()
	await get_tree().process_frame


func _test_player() -> void:
	for old_boss in get_tree().get_nodes_in_group("boss"):
		old_boss.remove_from_group("boss")
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector2.ZERO
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	var ids := ["skill_calamity_step", "skill_calamity_slash", "skill_calamity_fire_seal",
		"skill_calamity_fire_field", "skill_calamity_thunder_strike",
		"skill_calamity_thunder_pool", "skill_calamity_turn", "skill_calamity_final"]
	for sid in ids:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	var passive_id := "skill_calamity_body"
	CharacterData.passive_skill_loadout = []
	p._refresh_calamity_unlock()
	_check(bool(p._calamity_unlocked), "学会三灾主动后招式结算解锁")
	_check(not bool(p._calamity_passive_on), "未装备灾身被动时玩家灾轮不开启")
	p._calamity_set_element("fire", true)
	_check(p.calamity_state() == "", "无被动不获得玩家灾位")
	if not CharacterData.learned_skills.has(passive_id):
		CharacterData.learned_skills.append(passive_id)
	CharacterData.passive_skill_loadout = [passive_id]
	p._refresh_calamity_unlock()
	_check(bool(p._calamity_passive_on), "装备三灾·灾身后被动开启")
	_check(p._calamity_wheel != null and is_instance_valid(p._calamity_wheel), "玩家三灾轮 HUD 已创建")
	_check(is_equal_approx(SkillDB.CALAMITY_BOON_PCT, 12.0), "灾身加成提升至 12%")
	_check(is_equal_approx(SkillDB.CALAMITY_BREAK_TAKEN_MULT, 1.30), "破灾易伤提升至 30%")
	var boss = (load("res://scenes/boss/domain_boss_03_c.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.global_position = Vector2(200.0, 0.0)
	boss.target = p
	boss._calamity = "thunder"
	p._calamity_set_element("fire", true)
	_check(p.calamity_state() == "fire", "玩家灾位切到火")
	_check(p.calamity_momentum == 1, "首次切灾位 +1 灾势")
	_check(p.has_buff("sanzai_guard") == false, "未转轮时没有灾替")
	# 通用重复跳不得再结算雷池（专属 handler 自己排 4 跳）
	var hp_before_repeat: float = float(boss.current_hp)
	p._skill_tick_repeats("skill_calamity_thunder_pool",
		SkillDB.get_skill_form("skill_calamity_thunder_pool"), Vector2.RIGHT)
	await get_tree().create_timer(1.2).timeout
	_check(is_equal_approx(boss.current_hp, hp_before_repeat), "雷池不再被通用循环重复结算",
		"hp=%.1f" % boss.current_hp)
	# 火克雷 → 破灾
	var before: float = boss.current_hp
	var hit: bool = p._calamity_damage_circle(boss.global_position, 100.0,
		CharacterData.spell_attack(), "fire")
	p._calamity_notify_hit(boss, "fire")
	_check(hit and boss.is_calamity_broken(), "玩家火克雷破灾")
	_check(p.calamity_momentum >= 2, "破灾 +1 灾势")
	# 雷池锁灾
	p._calamity_set_element("thunder", true)
	p._cast_calamity_thunder_pool(SkillDB.get_skill_form("skill_calamity_thunder_pool"), Vector2.RIGHT)
	await get_tree().create_timer(0.12).timeout
	_check(boss.has_debuff("suo_zai"), "雷池锁 BOSS 灾轮")
	# 玩家被克 / 灾替
	p.calamity_element = "fire"
	boss._calamity = "wind"
	var m1: float = p.calamity_incoming_multiplier("wind")
	_check(is_equal_approx(m1, 1.15), "BOSS 风克玩家火 → 受伤 +15%")
	p.apply_calamity_break("wind")
	_check(p.has_debuff("suo_zai"), "被破灾后锁灾")
	p.clear_debuff("suo_zai")
	# 轮转起手的 1.5 秒灾替：免破、+1 灾势，并且 HUD 显示「替」
	p.apply_buff("sanzai_guard", 8.0)
	p.calamity_element = "fire"
	p._refresh_calamity_hud()
	_check(p._calamity_wheel.marker == "替", "灾替 HUD 标记", p._calamity_wheel.marker)
	var before_guard_m: int = p.calamity_momentum
	var m3: float = p.calamity_incoming_multiplier("wind")
	_check(is_equal_approx(m3, 1.0), "轮转灾替免破")
	p.apply_calamity_break("wind")
	_check(not p.has_buff("sanzai_guard"), "轮转灾替消耗")
	_check(p.calamity_momentum == mini(before_guard_m + 1, 3), "轮转灾替 +1 灾势")
	# 真实入口
	p.skill_cooldowns.clear()
	p.mana = 999.0
	p.stamina = 9
	var ok: bool = p.try_use_skill("skill_calamity_fire_seal")
	_check(ok, "焚天印可通过 try_use_skill")
	await get_tree().create_timer(0.6).timeout
	# 八式都要能从真实入口放出来（不是只测私有 cast 函数）
	for sid in ids:
		p.skill_cooldowns.clear()
		p.mana = 999.0
		p.stamina = 99
		p.calamity_momentum = 1
		var cast_ok: bool = p.try_use_skill(String(sid))
		_check(cast_ok, "玩家真实入口可放 " + String(sid))
		await get_tree().create_timer(0.36).timeout
	# 终极清空灾势
	p.calamity_element = "fire"
	p.calamity_momentum = 3
	p._cast_calamity_final(SkillDB.get_skill_form("skill_calamity_final"), Vector2.RIGHT)
	_check(p.calamity_momentum == 0, "玩家万劫归一清空灾势")


## 普通风 / 火 / 雷功法也要能破灾：不依赖晏无咎本族功法与玩家灾轮解锁
func _test_ordinary_break() -> void:
	for old_boss in get_tree().get_nodes_in_group("boss"):
		old_boss.remove_from_group("boss")
	var saved_loadout: Array = CharacterData.active_skill_loadout.duplicate()
	var saved_passive: Array = CharacterData.passive_skill_loadout.duplicate()
	CharacterData.active_skill_loadout = []
	CharacterData.passive_skill_loadout = []
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector2.ZERO
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	p._refresh_calamity_unlock()
	_check(not bool(p._calamity_unlocked) and not bool(p._calamity_passive_on),
		"没有本族功法 / 被动时玩家灾轮不显示")
	var boss = (load("res://scenes/boss/domain_boss_03_c.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.global_position = Vector2(220.0, 0.0)
	boss.target = p
	boss._calamity = "thunder"
	boss._broken_left = 0.0
	boss._break_cd = 0.0
	boss._fusion_left = 0.0
	boss._current_skill = ""
	p.notify_calamity_element_hit(boss, "metal", "skill_sword_chop")
	_check(not boss.is_calamity_broken(), "金 / 木 / 水 / 土功法不破灾")
	p.notify_calamity_element_hit(boss, "", "skill_sun_slash")
	_check(boss.is_calamity_broken(), "普通火属性功法破雷灾（元素回退）")
	boss._broken_left = 0.0
	boss._break_cd = 0.0
	boss._calamity = "wind"
	p._deal_direct_damage(boss, 1.0, "elemental", "thunder", "skill_thunder_lock")
	_check(boss.is_calamity_broken(), "普通雷属性功法经直伤入口破风灾")
	boss._broken_left = 0.0
	boss._break_cd = 0.0
	boss._calamity = "fire"
	p.notify_calamity_element_hit(boss, "wind", "skill_qi_wave")
	_check(boss.is_calamity_broken(), "普通风属性功法破火灾")
	boss._broken_left = 0.0
	boss._break_cd = 0.0
	boss._calamity = "thunder"
	var before_momentum: int = boss.calamity_momentum()
	p.notify_calamity_element_hit(boss, "thunder", "skill_thunder_lock")
	_check(boss.calamity_momentum() == mini(before_momentum + 1, 3), "普通同属性功法喂 BOSS 灾势")
	boss._broken_left = 0.0
	boss._break_cd = 0.0
	boss._calamity = "thunder"
	p.notify_calamity_element_hit(boss, "fire", "skill_calamity_fire_seal")
	_check(not boss.is_calamity_broken(), "本族功法交给原有路径，不在通用入口重复破灾")
	CharacterData.active_skill_loadout = saved_loadout
	CharacterData.passive_skill_loadout = saved_passive
	boss.queue_free()
	p.queue_free()


func _test_resolve() -> void:
	CharacterData.current_realm = "结丹"
	CharacterData.realm_stage = 2
	CharacterData.realm_exp = 0
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03_c",
	}
	var res := BattleResolver.resolve_victory()
	_check(String(res.get("message", "")).contains("修为 +500"),
		"位面 03 第三位首杀给 500 修为", String(res.get("message", "")))
	_check(bool((CharacterData.boss_progress.get("boss_03_c", {}) as Dictionary).get("killed", false)),
		"位面 03 记录晏无咎击杀")
	GameState.battle_context = {}
