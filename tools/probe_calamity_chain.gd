extends Node
## 灾劫连锁探针（2026-10-31）：
## 覆盖：风蚀数据、三种反应的新形态（火龙卷 DoT / 一次火爆 / 风雷吸附）、
## 燎原 / 雷池跳伤也能引爆、装备被动后仍生效、轮转 / 归一的未装备分支、
## 普通功法不引爆、头顶三痕读数。
## 用法：godot --headless --path . tools/probe_calamity_chain.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _p: Node2D
var _boss: Node
var _boss2: Node

const IDS: Array[String] = [
	"skill_calamity_step", "skill_calamity_slash",
	"skill_calamity_fire_seal", "skill_calamity_fire_field",
	"skill_calamity_thunder_strike", "skill_calamity_thunder_pool",
	"skill_calamity_turn", "skill_calamity_final",
]


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _reset_boss(node: Node) -> void:
	node.current_hp = node.max_hp
	node.state = 0
	node.state_timer = 0.0
	node._current_skill = ""
	node._broken_left = 0.0
	node._break_cd = 0.0
	node._fusion_left = 0.0
	node._momentum = 0
	node._calamity = "wind"
	node.debuffs.clear()


func _clear_debuffs(node: Node) -> void:
	node.debuffs.clear()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 灾劫连锁探针 ##########")
	var saved_learned: Array = CharacterData.learned_skills.duplicate()
	var saved_active: Array = CharacterData.active_skill_loadout.duplicate()
	var saved_passive: Array = CharacterData.passive_skill_loadout.duplicate()
	for sid in IDS:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	if not CharacterData.learned_skills.has("skill_calamity_body"):
		CharacterData.learned_skills.append("skill_calamity_body")
	CharacterData.active_skill_loadout = IDS.duplicate()
	CharacterData.passive_skill_loadout = []

	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	_p.global_position = Vector2.ZERO
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.is_teleporting = false
	_p.invincible_timer = 0.0
	_p._refresh_calamity_unlock()
	_boss = (load("res://scenes/boss/domain_boss_03_c.tscn") as PackedScene).instantiate()
	add_child(_boss)
	_boss.set_physics_process(false)
	_boss.set_process(false)
	_boss.global_position = Vector2(100.0, 0.0)
	_boss.target = _p
	_boss2 = (load("res://scenes/boss/domain_boss_03_c.tscn") as PackedScene).instantiate()
	add_child(_boss2)
	_boss2.set_physics_process(false)
	_boss2.set_process(false)
	_boss2.global_position = Vector2(300.0, 0.0)
	_boss2.target = _p
	await get_tree().process_frame

	# 1) 数据
	_check(String(DebuffDB.get_debuff("feng_shi").get("name", "")) == "风蚀",
		"风蚀 debuff 已登记")
	_check(is_equal_approx(float(DebuffDB.get_debuff("feng_shi").get("move_mult", 1.0)), 0.85),
		"风蚀移速 -15%")
	_check(not SkillDB.calamity_reaction_for("wind").is_empty()
		and String(SkillDB.calamity_reaction_for("wind").get("name", "")) == "风助火势",
		"风 → 风助火势")
	_check(String(SkillDB.calamity_reaction_for("fire").get("name", "")) == "雷火交击",
		"火 → 雷火交击")
	_check(String(SkillDB.calamity_reaction_for("thunder").get("name", "")) == "风雷引",
		"雷 → 风雷引")
	var tornado_data := SkillDB.calamity_reaction_for("wind")
	_check(String(tornado_data.get("kind", "")) == "fire_tornado"
		and int(tornado_data.get("ticks", 0)) == 6
		and is_equal_approx(float(tornado_data.get("interval", 0.0)), 0.5)
		and is_equal_approx(float(tornado_data.get("radius", 0.0)), 120.0),
		"风助火势 = 3 秒火龙卷 / 每 0.5 秒一跳 / 半径 120")
	var burst_data := SkillDB.calamity_reaction_for("fire")
	_check(String(burst_data.get("kind", "")) == "burst"
		and is_equal_approx(float(burst_data.get("ratio", 0.0)), 1.2),
		"雷火交击 = 一次爆发")
	var vortex_data := SkillDB.calamity_reaction_for("thunder")
	_check(String(vortex_data.get("kind", "")) == "vortex"
		and is_equal_approx(float(vortex_data.get("radius", 0.0)), 260.0)
		and is_equal_approx(float(vortex_data.get("pull", 0.0)), 150.0),
		"风雷引 = 风雷涡吸附 / 半径 260")
	var rules_text := "\n".join(SkillDB.get_calamity_rules())
	_check(rules_text.contains("灾劫连锁") and rules_text.contains("火龙卷")
		and rules_text.contains("风雷涡") and rules_text.contains("装备或未装备"),
		"规则卡写明三套持续 / 爆发形态")
	_check(not bool(_p._calamity_passive_on) and bool(_p._calamity_unlocked),
		"未带被动但八式结算已解锁")

	# 2) 风技挂风蚀 + 三痕读数
	_reset_boss(_boss)
	_clear_debuffs(_boss)
	_p._cast_calamity_slash(SkillDB.get_skill_form("skill_calamity_slash"), Vector2.RIGHT)
	_check(_boss.has_debuff("feng_shi"), "断空斩附加风蚀")
	_check(_boss.has_meta("calamity_mark_fx")
		and is_instance_valid(_boss.get_meta("calamity_mark_fx")), "目标头顶出现三痕读数")

	# 3) 风助火势：风引爆劫火，在目标处留火龙卷，持续跳火伤
	_reset_boss(_boss)
	_reset_boss(_boss2)
	_clear_debuffs(_boss)
	_clear_debuffs(_boss2)
	_boss2.global_position = Vector2(-150.0, 0.0)
	_boss2.apply_debuff("jie_huo", 4.0)
	var hp0: float = float(_boss2.current_hp)
	_p._cast_calamity_slash(SkillDB.get_skill_form("skill_calamity_slash"), Vector2.LEFT)
	_check(_boss2.has_debuff("jie_huo"), "火龙卷持续续劫火")
	_check(_boss2.has_debuff("feng_shi"), "引爆后留下风蚀")
	_check(float(_boss2.current_hp) < hp0, "风助火势立刻造成一跳火伤")
	var hp_after_tick: float = float(_boss2.current_hp)
	await get_tree().create_timer(0.65).timeout
	_check(float(_boss2.current_hp) < hp_after_tick, "火龙卷持续跳伤")
	# 火龙卷的后续跳伤不参与再次引爆
	_boss2.apply_debuff("gan_dian", 3.0)
	await get_tree().create_timer(0.55).timeout
	_check(_boss2.has_debuff("gan_dian"), "火龙卷跳伤不二次引爆")
	_boss2.global_position = Vector2(300.0, 0.0)
	_reset_boss(_boss2)
	_clear_debuffs(_boss2)

	# 4) 雷火交击：火引爆感电，一次性爆发
	_reset_boss(_boss)
	_clear_debuffs(_boss)
	_boss.apply_debuff("gan_dian", 3.0)
	hp0 = float(_boss.current_hp)
	_p._cast_calamity_fire_seal(SkillDB.get_skill_form("skill_calamity_fire_seal"), Vector2.RIGHT)
	await get_tree().create_timer(0.45).timeout
	_check(not _boss.has_debuff("gan_dian"), "雷火交击消耗感电")
	_check(_boss.has_debuff("jie_huo"), "火印自身留下劫火")
	_check(float(_boss.current_hp) < hp0, "雷火交击造成伤害")
	var hp_after_burst: float = float(_boss.current_hp)
	await get_tree().create_timer(0.80).timeout
	_check(is_equal_approx(float(_boss.current_hp), hp_after_burst),
		"雷火交击是一次性爆发，没有后续跳伤")

	# 5) 风雷引：雷引爆风蚀，留下风雷涡持续吸附，不造成伤害
	_reset_boss(_boss)
	_reset_boss(_boss2)
	_clear_debuffs(_boss)
	_clear_debuffs(_boss2)
	_boss2.set("_knock_vel", Vector2.ZERO)
	_boss.apply_debuff("feng_shi", 4.0)
	_boss2.apply_debuff("feng_shi", 4.0)
	var hp2_0: float = float(_boss2.current_hp)
	_p._cast_calamity_thunder_strike(
		SkillDB.get_skill_form("skill_calamity_thunder_strike"), Vector2.RIGHT)
	await get_tree().create_timer(0.85).timeout
	_check(not _boss.has_debuff("feng_shi"), "风雷引消耗风蚀")
	_check(_boss.has_debuff("gan_dian"), "雷技自身留下感电")
	_check(_boss2.has_debuff("feng_shi"), "风雷涡不连锁，第二目标保留风蚀")
	_check(not _boss2.has_debuff("gan_dian"), "风雷涡不挂感电")
	var kv2: Vector2 = _boss2.get("_knock_vel")
	_check(kv2.x < -1.0, "风雷涡把第二目标往中心吸", str(kv2))
	_check(is_equal_approx(float(_boss2.current_hp), hp2_0), "风雷涡不造成伤害")

	# 6) 轮转的未装备分支：风环 + 风蚀，不发无效灾替
	_reset_boss(_boss)
	_clear_debuffs(_boss)
	_boss.apply_debuff("jie_huo", 4.0)
	_p.remove_buff("sanzai_guard")
	_p._cast_calamity_turn(SkillDB.get_skill_form("skill_calamity_turn"), Vector2.RIGHT)
	_check(_boss.has_debuff("feng_shi"), "未装备时轮转改为风环并挂风蚀")
	var hp_turn: float = float(_boss.current_hp)
	await get_tree().create_timer(0.65).timeout
	_check(float(_boss.current_hp) < hp_turn, "轮转引爆出的火龙卷持续跳伤")
	_check(not _p.has_buff("sanzai_guard"), "未装备时轮转不再挂无效灾替")
	_check(_p.calamity_state() == "", "未装备时轮转不改玩家灾位")

	# 7) 归一的未装备分支：火属性引爆感电 + 灾崩
	_reset_boss(_boss)
	_clear_debuffs(_boss)
	_boss.apply_debuff("gan_dian", 3.0)
	_p._cast_calamity_final(SkillDB.get_skill_form("skill_calamity_final"), Vector2.RIGHT)
	await get_tree().create_timer(0.7).timeout
	_check(not _boss.has_debuff("gan_dian"), "万劫归一引爆感电")
	_check(_boss.has_debuff("zai_beng"), "万劫归一命中挂灾崩")

	# 8) 燎原 / 雷池的跳伤也能引爆（以前 allow_reaction=false，两道场永远不出反应）
	_reset_boss(_boss2)
	_clear_debuffs(_boss2)
	_boss2.global_position = Vector2(1500.0, 0.0)
	_boss2.apply_debuff("gan_dian", 3.0)
	var hp_field: float = float(_boss2.current_hp)
	_p._calamity_ticks(_boss2.global_position, 100.0, 10.0, "fire", "jie_huo", 3.0, 1, 0.0)
	_check(not _boss2.has_debuff("gan_dian"), "火场跳伤引爆感电")
	_check(_boss2.has_debuff("jie_huo"), "火场跳伤留下劫火")
	_check(float(_boss2.current_hp) < hp_field, "火场跳伤引爆造成伤害")
	_reset_boss(_boss2)
	_clear_debuffs(_boss2)
	_boss2.apply_debuff("feng_shi", 3.0)
	_p._calamity_ticks(_boss2.global_position, 100.0, 10.0, "thunder", "gan_dian", 3.0, 1, 0.0)
	_check(not _boss2.has_debuff("feng_shi"), "雷池跳伤引爆风蚀")
	_check(_boss2.has_debuff("gan_dian"), "雷池跳伤留下感电")

	# 9) 普通功法不走灾劫连锁
	_reset_boss(_boss)
	_clear_debuffs(_boss)
	_boss.apply_debuff("gan_dian", 3.0)
	_p._damage_bosses_in_shape(Vector2.RIGHT, 200.0, deg_to_rad(70.0), 10.0,
		"elemental", "fire", false, "skill_sword_chop")
	_check(_boss.has_debuff("gan_dian"), "普通火功法不引爆感电")

	# 10) 装备被动后灾劫连锁仍然生效
	if not CharacterData.learned_skills.has("skill_calamity_body"):
		CharacterData.learned_skills.append("skill_calamity_body")
	CharacterData.passive_skill_loadout = ["skill_calamity_body"]
	_p._refresh_calamity_unlock()
	_check(bool(_p._calamity_passive_on), "装备被动后灾身开启")
	_reset_boss(_boss)
	_clear_debuffs(_boss)
	_boss.apply_debuff("jie_huo", 4.0)
	var hp_passive: float = float(_boss.current_hp)
	_p._cast_calamity_slash(SkillDB.get_skill_form("skill_calamity_slash"), Vector2.RIGHT)
	_check(float(_boss.current_hp) < hp_passive, "带被动时风技也触发火龙卷")
	_check(_boss.has_debuff("feng_shi"), "带被动时风技仍可挂风蚀")
	_check(_boss.has_meta("calamity_mark_fx"), "带被动时仍显示三痕读数")
	var hp_passive_tick: float = float(_boss.current_hp)
	await get_tree().create_timer(0.65).timeout
	_check(float(_boss.current_hp) < hp_passive_tick, "带被动时火龙卷持续跳伤")
	_boss.global_position = Vector2(1200.0, 1200.0)
	_boss.apply_debuff("jie_huo", 4.0)
	_check(bool(_p._try_calamity_reaction(_boss, "wind", 100.0)), "带被动时反应入口开放")

	# 10b) 带被动、场上没有可破灾的对手：势点仍按玩家灾势显示，切灾位照常 +1
	_boss.state = 6
	_boss2.state = 6
	_p.calamity_element = ""
	_p.calamity_momentum = 0
	_p._calamity_set_element("wind", true)
	_check(bool(_p._calamity_wheel.visible), "无灾位对手时灾位环仍显示")
	_check(int(_p._calamity_wheel.get("momentum")) == 1, "无灾位对手时势点照常显示")
	_check(_p.calamity_momentum == 1, "无灾位对手时首次切灾位 +1 灾势")
	_p._calamity_set_element("fire", true)
	_check(_p.calamity_momentum == 2 and int(_p._calamity_wheel.get("momentum")) == 2,
		"换灾位 +1，势点读数同步")
	_p._calamity_set_element("fire", true)
	_check(_p.calamity_momentum == 2, "同灾位不重复涨势")
	_boss.state = 0
	_boss2.state = 0
	_p._refresh_calamity_hud()
	_check(int(_p._calamity_wheel.get("momentum")) == 2, "有灾位对手时继续显示玩家灾势")

	# 10c) 闪避掉的命中：不掉血、不挂劫火、不扣灾势/不上锁灾
	_p.hp = _p.max_hp
	_p.invincible_timer = 0.0
	_p.is_dodging = true
	_p.dodge_timer = 0.1
	_p.calamity_element = "thunder"
	_boss._calamity = "fire"
	_boss._broken_left = 0.0
	_boss._break_cd = 0.0
	var hp_dodge: float = _p.hp
	var m_dodge: int = _p.calamity_momentum
	var hit_dodge: bool = _boss._damage_unit(_p, 5.0, "elemental", "fire")
	_check(not hit_dodge, "闪避掉的命中不算命中")
	_check(is_equal_approx(_p.hp, hp_dodge), "闪避不掉血")
	_check(not _p.has_debuff("jie_huo"), "闪避不吃劫火")
	_check(_p.calamity_momentum == m_dodge, "闪避不扣灾势")
	_check(not _p.has_debuff("suo_zai"), "闪避不锁灾")
	_p.is_dodging = false
	_p._hit_negated_timer = 0.0
	var hp_hit: float = _p.hp
	var hit_land: bool = _boss._damage_unit(_p, 5.0, "elemental", "fire")
	_check(hit_land, "正常命中算命中")
	_check(_p.hp < hp_hit, "正常命中掉血")
	_check(_p.has_debuff("jie_huo"), "正常命中吃劫火")
	_check(_p.has_debuff("suo_zai"), "正常命中破灾锁灾")
	_p.clear_debuff("jie_huo")
	_p.clear_debuff("suo_zai")
	_p.hp = _p.max_hp

	# 11) 演武场木桩：可挂痕 / 引爆 / 显示读数
	CharacterData.passive_skill_loadout = []
	_p._refresh_calamity_unlock()
	_boss.global_position = Vector2(1200.0, 1200.0)
	_boss2.global_position = Vector2(1300.0, 1200.0)
	var dummy = (load("res://scenes/combat/training_dummy.tscn") as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = Vector2(100.0, 0.0)
	dummy.apply_debuff("jie_huo", 4.0)
	_p._cast_calamity_slash(SkillDB.get_skill_form("skill_calamity_slash"), Vector2.RIGHT)
	_check(dummy.has_debuff("feng_shi"), "木桩可触发灾劫连锁")
	_check(float(dummy.total_damage) > 0.0, "木桩记录灾劫伤害")
	_check(dummy.has_meta("calamity_mark_fx"), "木桩显示灾痕读数")
	_check(String(dummy.call("calamity_state")) == "fire", "训练木桩提供火灾位")
	_check(bool(dummy.call("on_calamity_broken", _p)), "训练木桩可被破灾")
	# 演武场戴上被动：势点按玩家灾势显示（木桩提供可破灾目标）
	CharacterData.passive_skill_loadout = ["skill_calamity_body"]
	_p._refresh_calamity_unlock()
	_boss.state = 6
	_boss2.state = 6
	_p._refresh_calamity_hud()
	_check(_p._calamity_wheel.visible and int(_p._calamity_wheel.get("momentum")) >= 0,
		"演武场木桩旁三枚势点可见")
	dummy.queue_free()

	# 恢复现场
	CharacterData.learned_skills = saved_learned
	CharacterData.active_skill_loadout = saved_active
	CharacterData.passive_skill_loadout = saved_passive
	_p.queue_free()
	_boss.queue_free()
	_boss2.queue_free()
	# 等反应特效 / 持续场 / 飘字的 tween 收尾，避免无头退出时产生泄漏告警
	await get_tree().create_timer(3.2).timeout

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
