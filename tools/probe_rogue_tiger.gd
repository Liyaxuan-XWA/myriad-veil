extends Node
## 试炼之路 · 虎妖（蛮力 / 砂暴）自检（2026-11-08）
## 覆盖：虎妖开局四式、卡池按流派过滤（剑修 / 刀修卡不得混入）、
##       撼地 / 崩山 / 飞砂 / 远砂 / 骤雨 / 妖丹·烈 六张招式覆盖、
##       碎甲破防与迷眼减速的施加、压强对破防目标的加伤、蛮劲只加物理、收局还原。
## 用法：godot --headless --path . res://tools/probe_rogue_tiger.tscn -- --no-save

const MINION_SCENE := "res://scenes/world/world_enemy.tscn"

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
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


## 不动、不还手的木桩（量破防 / 迷眼用）
func _make_dummy(pos: Vector2) -> WorldEnemy:
	var packed := load(MINION_SCENE) as PackedScene
	var e := packed.instantiate() as WorldEnemy
	var cfg := {
		"pos": pos,
		"max_hp": 100000.0,
		"attack_power": 1.0,
		"move_speed": 120.0,
		"visual_id": "rogue_rat",
		"aggro_range": 1.0,
		"leash_range": 1.0,
		"melee_range": 1.0,
		"melee_angle": 1.0,
		"melee_coeff": 0.0,
		"body_radius": 20.0,
		"attack_name": "不动",
		"skills": [],
		"cast_coeff": 0.0,
	}
	e.position = pos
	e.configure(cfg, WorldEnemy.KIND_BEAST, "木桩")
	add_child(e)
	return e


func _run() -> void:
	print("\n########## 试炼之路 · 虎妖 ##########")
	await get_tree().process_frame

	# ===== 1. 虎妖开局 =====
	RogueRun.start_run("beast")
	await get_tree().process_frame
	_check(RogueRun.active and RogueRun.family == "beast", "开局：本局流派=虎妖", RogueRun.family)
	var loadout: Array = CharacterData.active_skill_loadout
	_check(loadout.size() == 4, "4 个主动槽", str(loadout))
	var all_tiger := true
	for sid in loadout:
		if not String(sid).begins_with("skill_tiger_"):
			all_tiger = false
	_check(all_tiger, "开局四式全是虎妖功法", str(loadout))
	_check(CharacterData.passive_skill_loadout.is_empty(), "虎妖没有被动功法（空槽）")
	_check(CharacterData.learned_skills.has("skill_tiger_rock")
		and CharacterData.learned_skills.size() == 5, "五式全习得（碎岩飞砂暂不装配）",
		str(CharacterData.learned_skills))
	_check(not (CharacterData.active_skill_loadout as Array).has("skill_tiger_rock"),
		"碎岩飞砂不在出战槽（4 槽放不下五式）")

	# ===== 2. 卡池按本局流派过滤 =====
	var leak := 0
	var tiger_seen := 0
	for i in 60:
		for raw in RogueRun.roll_choices(3, i % 2 == 0):
			var bid := String((raw as Dictionary).get("id", ""))
			if bid.begins_with("s_") or bid.begins_with("b_"):
				leak += 1
			elif bid.begins_with("t_"):
				tiger_seen += 1
	_check(leak == 0, "剑修 / 刀修卡不会混进虎妖局", "泄漏 %d 张" % leak)
	_check(tiger_seen > 0, "虎妖卡能正常抽到", "出现 %d 次" % tiger_seen)

	# 兽潮流已改用「虎煞」层数（不召虎影）—— 池子里不该再留任何召唤物相关文案
	var ghost_cards := 0
	var hunt_cards := 0
	for raw in RogueDB.BEAST_BUFFS:
		var bid := String((raw as Dictionary).get("id", ""))
		if String((raw as Dictionary).get("desc", "")).contains("虎影"):
			ghost_cards += 1
		if bid.begins_with("t_cy_"):
			hunt_cards += 1
	_check(ghost_cards == 0, "池子里没有「虎影」废卡（兽潮流改用虎煞层数）", str(ghost_cards))
	# ⚠ 别锁死张数：上一轮加了「猎杀本能」后这里还写着 5，白红了一轮。
	# 真正要锁的是「兽潮流的每张都在虎妖池里」，加卡不用回来改数字。
	var hunt_in_pool := 0
	for raw in (RogueDB.POOLS.get("beast", []) as Array):
		if String((raw as Dictionary).get("id", "")).begins_with("t_cy_"):
			hunt_in_pool += 1
	_check(hunt_cards >= 6 and hunt_in_pool == hunt_cards, "兽潮流卡全部在虎妖池里",
		"%d / %d" % [hunt_in_pool, hunt_cards])

	# ===== 3. 招式覆盖（纯数据，不需要场景）=====
	var smash := MoveDB.resolve_player("form_smash")
	_check(is_equal_approx(float(smash.get("range", 0.0)), 120.0), "踏地范围基值 120")
	RogueRun.add_buff("t_bl_range")
	RogueRun.add_buff("t_bl_range")
	smash = MoveDB.resolve_player("form_smash")
	_check(absf(float(smash.get("range", 0.0)) - 180.0) < 0.01,
		"撼地 ×2：踏地范围 180（120×1.5）", "%.1f" % float(smash.get("range", 0.0)))

	var base_stomp_dmg := CharacterData.calc_skill_damage("skill_tiger_stomp", true, false)
	RogueRun.add_buff("t_bl_heavy")
	RogueRun.add_buff("t_bl_heavy")
	var boosted_stomp_dmg := CharacterData.calc_skill_damage("skill_tiger_stomp", true, false)
	# ⚠ 不要拿总伤害除：calc_skill_damage 里还有一层固定加值，系数翻 1.4 倍时
	#   总伤害只涨 ×1.36（14.3 → 19.4）。断言的正确口径是**系数本身**。
	_check(absf(float(MoveDB.resolve_player("form_smash").get("phys_coeff", 0.0)) - 1.96) < 0.001,
		"崩山 ×2：踏地系数 1.4 → 1.96",
		"%.2f" % float(MoveDB.resolve_player("form_smash").get("phys_coeff", 0.0)))
	_check(boosted_stomp_dmg > base_stomp_dmg, "崩山真的抬了实战伤害",
		"%.1f → %.1f" % [base_stomp_dmg, boosted_stomp_dmg])

	var volley := MoveDB.resolve_player("form_arrow_volley")
	_check(int(volley.get("count", 0)) == 5, "砂石乱舞弹数基值 5")
	RogueRun.add_buff("t_sb_count")
	RogueRun.add_buff("t_sb_count")
	volley = MoveDB.resolve_player("form_arrow_volley")
	_check(int(volley.get("count", 0)) == 7, "飞砂 ×2：弹数 5 → 7（加算）",
		str(int(volley.get("count", 0))))

	var arrow := MoveDB.resolve_player("form_arrow")
	_check(is_equal_approx(float(arrow.get("range", 0.0)), 620.0), "碎岩飞砂射程基值 620")
	RogueRun.add_buff("t_sb_range")
	arrow = MoveDB.resolve_player("form_arrow")
	_check(absf(float(arrow.get("range", 0.0)) - 713.0) < 0.01,
		"远砂：单发射程 620 → 713", "%.1f" % float(arrow.get("range", 0.0)))

	_check(is_equal_approx(float(volley.get("cooldown", 0.0)), 10.0), "砂石乱舞冷却基值 10",
		"%.2f" % float(volley.get("cooldown", 0.0)))
	RogueRun.add_buff("t_sb_cd")
	volley = MoveDB.resolve_player("form_arrow_volley")
	_check(absf(float(volley.get("cooldown", 0.0)) - 8.8) < 0.01,
		"骤雨：乱舞冷却 10 → 8.8", "%.2f" % float(volley.get("cooldown", 0.0)))

	var orb := MoveDB.resolve_player("form_element_orb")
	_check(is_equal_approx(float(orb.get("spell_coeff", 0.0)), 1.75), "妖丹法强系数基值 1.75")
	RogueRun.add_buff("t_sb_orb")
	RogueRun.add_buff("t_sb_orb")
	orb = MoveDB.resolve_player("form_element_orb")
	_check(absf(float(orb.get("spell_coeff", 0.0)) - 2.45) < 0.01,
		"妖丹·烈 ×2：1.75 → 2.45", "%.2f" % float(orb.get("spell_coeff", 0.0)))

	# ===== 4. 进战斗场景取玩家 =====
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.get("player")
	var rogue: Node = arena.get("_rogue")
	_check(player != null and rogue != null, "战斗场景与 RogueArena 已创建")
	if player == null or rogue == null:
		return
	# 冻结刷怪机并清场：后面自己摆木桩
	rogue.set_process(false)
	rogue.set_physics_process(false)
	player.set("invincible_timer", 9999.0)
	for raw in (rogue.get("_alive") as Array).duplicate():
		if is_instance_valid(raw):
			(raw as Node).queue_free()
	await get_tree().process_frame

	# ===== 5. 碎甲：踏地 / 虎爪 挂破防，乱舞不挂 =====
	RogueRun.add_buff("t_bl_break")
	var d1 := _make_dummy(Vector2(360.0, 60.0))
	await get_tree().process_frame
	player.call("_rogue_apply_hit_debuff", d1, "skill_tiger_sandstorm")
	_check(not d1.call("has_debuff", "armor_break"), "砂石乱舞不挂破防（只有重击挂）")
	player.call("_rogue_apply_hit_debuff", d1, "skill_tiger_stomp")
	_check(d1.call("has_debuff", "armor_break"), "猛虎踏地挂上破防")
	player.call("_rogue_apply_hit_debuff", d1, "skill_tiger_claw")
	_check(d1.call("has_debuff", "armor_break"), "虎爪裂空也挂破防")
	var taken_mult := float(d1.call("debuff_damage_taken_mult"))
	_check(absf(taken_mult - 1.15) < 0.001, "破防：受伤 ×1.15", "%.3f" % taken_mult)

	# ===== 6. 压强：对破防目标加伤（2 叠 = ×1.3）=====
	player.set("_rogue_scale_left", 0.0)
	player.set("_rogue_step_ready", false)
	var broken_dmg := float(player.call("_rogue_modify_damage", 100.0, d1, "physical_melee", ""))
	var d2 := _make_dummy(Vector2(360.0, -60.0))
	await get_tree().process_frame
	var plain_dmg := float(player.call("_rogue_modify_damage", 100.0, d2, "physical_melee", ""))
	_check(absf(broken_dmg / maxf(plain_dmg, 0.001) - 1.0) < 0.01, "未拿压强时对破防无额外加伤",
		"%.1f vs %.1f" % [broken_dmg, plain_dmg])
	RogueRun.add_buff("t_bl_broken")
	RogueRun.add_buff("t_bl_broken")
	var broken_dmg2 := float(player.call("_rogue_modify_damage", 100.0, d1, "physical_melee", ""))
	_check(absf(broken_dmg2 / maxf(plain_dmg, 0.001) - 1.3) < 0.01,
		"压强 ×2：对破防目标 ×1.3", "%.1f → %.1f" % [plain_dmg, broken_dmg2])
	var plain_dmg2 := float(player.call("_rogue_modify_damage", 100.0, d2, "physical_melee", ""))
	_check(absf(plain_dmg2 / maxf(plain_dmg, 0.001) - 1.0) < 0.01, "压强对未破防目标不生效",
		"%.1f" % plain_dmg2)

	# ===== 7. 迷眼：乱舞挂减速，取最强不叠乘 =====
	RogueRun.add_buff("t_sb_slow")
	player.call("_rogue_apply_hit_debuff", d2, "skill_tiger_sandstorm")
	_check(d2.call("has_debuff", "blinding_sand"), "砂石乱舞挂上迷眼")
	var move_mult := float(d2.call("debuff_move_mult"))
	_check(absf(move_mult - 0.75) < 0.001, "迷眼：移速 ×0.75", "%.2f" % move_mult)
	_check(not d1.call("has_debuff", "blinding_sand"), "踏地不会挂迷眼（只有乱舞挂）")

	# ===== 8. 蛮劲：只加物理 =====
	RogueRun.add_buff("t_bl_phys")
	RogueRun.add_buff("t_bl_phys")
	RogueRun.add_buff("t_bl_phys")
	var phys_out := float(player.call("_rogue_modify_damage", 100.0, d2, "physical_melee", ""))
	var spell_out := float(player.call("_rogue_modify_damage", 100.0, d2, "elemental", ""))
	_check(absf(phys_out / maxf(plain_dmg2, 0.001) - 1.3) < 0.01, "蛮劲 ×3：物理 ×1.3",
		"%.1f → %.1f" % [plain_dmg2, phys_out])
	_check(absf(spell_out - 100.0) < 0.01, "蛮劲不加法术", "%.1f" % spell_out)

	# ===== 9. 真打一下：踏地命中同时挂破防并吃到压强 =====
	player.set("_rogue_scale_left", 0.0)
	player.set("_rogue_step_ready", false)
	var d3 := _make_dummy(Vector2(80.0, 0.0))
	await get_tree().process_frame
	var pos3: Vector2 = d3.global_position
	player.global_position = pos3 - Vector2(60.0, 0.0)
	var hp3 := float(d3.get("current_hp"))
	var form := MoveDB.resolve_player("form_smash")
	var dmg3 := CharacterData.calc_skill_damage("skill_tiger_stomp", true, false)
	player.call("_damage_bosses_in_shape", Vector2.RIGHT, float(form.get("range", 120.0)),
		deg_to_rad(180.0), dmg3, "physical", "earth", true, "skill_tiger_stomp")
	var loss3 := hp3 - float(d3.get("current_hp"))
	_check(loss3 > 0.0, "踏地真的打到了木桩", "%.1f" % loss3)
	_check(d3.call("has_debuff", "armor_break"), "踏地命中自动挂破防（走真实结算）")

	# ===== 10. 收局还原 =====
	d1.queue_free()
	d2.queue_free()
	d3.queue_free()
	RogueRun.restore()
	RogueRun.family = "sword"
	_check(not RogueRun.active, "收局：active=false")
	_check(CharacterData.active_skill_loadout.is_empty()
		or not String(CharacterData.active_skill_loadout[0]).begins_with("skill_tiger_"),
		"收局：虎妖功法已从存档数据里退出", str(CharacterData.active_skill_loadout))
	_check(absf(float(MoveDB.resolve_player("form_smash").get("range", 0.0)) - 120.0) < 0.01,
		"收局：踏地范围回到 120")
