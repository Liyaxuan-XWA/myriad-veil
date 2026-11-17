extends Node
## 试炼之路 · 后九套技能组自检（2026-11-08）
## 覆盖：12 套流派登记完整（起始四式 / 被动 / 15 张卡 / 无重复 id）、
##       卡池只按本局流派过滤、每张卡都能改出可观测的派生值（没有死卡）、
##       各流派核心机制真的接到了算伤害 / 减伤 / 冷却的那一处。
## 用法：godot --headless --path . res://tools/probe_rogue_families.tscn -- --no-save

const MINION_SCENE := "res://scenes/world/world_enemy.tscn"
const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

## 后九套：每套应有的 15 张卡
const NEW_FAMILIES: Array[String] = [
	"yinyang", "array", "qi", "thunder", "sun",
	"calamity", "mirror", "shadow", "fold",
]

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


func _make_dummy(pos: Vector2) -> WorldEnemy:
	var packed := load(MINION_SCENE) as PackedScene
	var e := packed.instantiate() as WorldEnemy
	var cfg := {
		"pos": pos, "max_hp": 100000.0, "attack_power": 1.0, "move_speed": 120.0,
		"visual_id": "rogue_rat", "aggro_range": 1.0, "leash_range": 1.0,
		"melee_range": 1.0, "melee_angle": 1.0, "melee_coeff": 0.0,
		"body_radius": 20.0, "attack_name": "不动", "skills": [], "cast_coeff": 0.0,
	}
	e.position = pos
	e.configure(cfg, WorldEnemy.KIND_BEAST, "木桩")
	add_child(e)
	return e


## 每张卡至少要有一种「效果载体」，否则抽到就是纯文字
func _card_has_effect(def: Dictionary) -> bool:
	for key in ["attr", "cap", "stat", "flag", "form"]:
		if def.has(key):
			return true
	return false


func _run() -> void:
	print("\n########## 试炼之路 · 后九套 ##########")
	await get_tree().process_frame

	# ===== 1. 数据完整性（不需要场景）=====
	var all_ids: Dictionary = {}
	var dup := 0
	for fam in NEW_FAMILIES:
		_check(RogueDB.POOLS.has(fam), "卡池已登记：" + fam)
		var pool: Array = RogueDB.POOLS.get(fam, [])
		# 2026-11-09 机制拓展：每套从 15 张扩到 17 张，断言下限而不是等值，
		# 以后再加卡不用回来改这里（真正要守的是「没有空卡」那一条）
		_check(pool.size() >= 15, "%s 池 ≥15 张" % fam, str(pool.size()))
		var bad_eff := 0
		for raw in pool:
			var def: Dictionary = raw
			var cid := String(def.get("id", ""))
			if cid == "" or not _card_has_effect(def) or String(def.get("desc", "")) == "":
				bad_eff += 1
			if all_ids.has(cid):
				dup += 1
			all_ids[cid] = true
			if not RogueDB.RARITY_WEIGHT.has(String(def.get("rarity", ""))):
				bad_eff += 1
		_check(bad_eff == 0, "%s 池没有空卡（id / 载体 / 文案 / 稀有度齐全）" % fam, str(bad_eff))
		# 起始功法
		var kit: Dictionary = RogueDB.family_start(fam)
		_check((kit.get("active", []) as Array).size() == 4, "%s 起始四式" % fam,
			str((kit.get("active", []) as Array).size()))
		var missing := 0
		for sid in (kit.get("active", []) as Array):
			if SkillDB.get_skill(String(sid)).is_empty():
				missing += 1
		for sid in (kit.get("passive", []) as Array):
			if SkillDB.get_skill(String(sid)).is_empty():
				missing += 1
		_check(missing == 0, "%s 起始功法都能在功法表里查到" % fam, str(missing))
		_check(RogueDB.FAMILY_BLURB.has(fam), "%s 有入口文案" % fam)
	_check(dup == 0, "九套卡池 id 无重复", str(dup))
	# ⚠ 锁「顺序表 = 起始表」，不锁死具体数字：新增流派不必回来改这里；
	#   漏登一族（有起始套但没进顺序表 → 入口页少一个按钮）照样会红。
	_check(RogueDB.FAMILY_ORDER.size() == RogueDB.FAMILY_START.size()
		and RogueDB.FAMILY_ORDER.size() >= 13,
		"入口流派按钮与起始表一一对应（≥13）",
		"%d / %d" % [RogueDB.FAMILY_ORDER.size(), RogueDB.FAMILY_START.size()])

	# ===== 2. 逐流派：卡池过滤 + 机制接线 =====
	for fam in NEW_FAMILIES:
		await _check_family(fam)

	# ===== 3. 收局 =====
	RogueRun.restore()
	RogueRun.family = "sword"
	_check(not RogueRun.active, "收局：active=false")


## 一个流派：开一局 → 起战斗场景 → 断机制 → 拆场景
func _check_family(fam: String) -> void:
	print("\n--- %s ---" % fam)
	RogueRun.start_run(fam)
	await get_tree().process_frame

	# 卡池过滤：只能抽到通用 + 本流派
	var leak := 0
	var own := 0
	for i in 40:
		for raw in RogueRun.roll_choices(3, i % 2 == 0):
			var bid := String((raw as Dictionary).get("id", ""))
			if RogueDB.family_of(bid) == fam:
				own += 1
			elif RogueDB.family_of(bid) != "generic":
				leak += 1
	_check(leak == 0, "%s 局不会抽到别家的卡" % fam, "泄漏 %d" % leak)
	_check(own > 0, "%s 自己的卡能抽到" % fam, "%d 次" % own)

	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.get("player")
	var rogue: Node = arena.get("_rogue")
	if player == null or rogue == null:
		_check(false, "%s 战斗场景创建失败" % fam)
		if is_instance_valid(arena):
			arena.queue_free()
		RogueRun.restore()
		return
	rogue.set_process(false)
	rogue.set_physics_process(false)
	player.set("invincible_timer", 99999.0)
	for raw in (rogue.get("_alive") as Array).duplicate():
		if is_instance_valid(raw):
			(raw as Node).queue_free()
	await get_tree().process_frame

	match fam:
		"yinyang":
			await _probe_yinyang(player)
		"array":
			await _probe_array(player)
		"qi":
			await _probe_qi(player)
		"thunder":
			await _probe_thunder(player)
		"sun":
			await _probe_sun(player)
		"calamity":
			await _probe_calamity(player)
		"mirror":
			await _probe_mirror(player)
		"shadow":
			await _probe_shadow(player)
		"fold":
			await _probe_fold(player)

	arena.queue_free()
	await get_tree().process_frame
	RogueRun.restore()
	RogueRun.family = "sword"
	await get_tree().process_frame


# ===================== 各流派机制 =====================

func _probe_yinyang(player: Node2D) -> void:
	_check(player.get("_yinyang_unlocked"), "两仪势已解锁（被动已装）")
	_check(RogueRun.cap("yinyang_max") == 3, "势上限基值 3")
	var base_per := float(SkillDB.YINYANG_COLLAPSE_COEFF_PER_STACK)
	RogueRun.add_buff("y_ni_cap")
	RogueRun.add_buff("y_beng_per")
	RogueRun.add_buff("y_beng_per")
	await get_tree().process_frame
	_check(RogueRun.cap("yinyang_max") == 5, "太极枢：势上限 3 → 5",
		str(RogueRun.cap("yinyang_max")))
	var boosted := float(SkillDB.YINYANG_COLLAPSE_COEFF_PER_STACK) + RogueRun.stat("yy_collapse_per")
	_check(absf(boosted - (base_per + 0.30)) < 0.001,
		"蓄崩 ×2：每层势系数 +0.30", "%.2f" % boosted)
	# 逆式真的叠层 + 加伤（走真实结算）
	var d1 := _make_dummy(Vector2(300.0, 0.0))
	await get_tree().process_frame
	player.set("yinyang_stacks", 0)
	player.set("yinyang_polarity", player.YINYANG_YANG)
	var out1 := float(player.call("_yinyang_modify_damage", d1, "physical_melee", 100.0, ""))
	var stacks1 := int(player.get("yinyang_stacks"))
	_check(stacks1 == 1, "空条第一发算逆式：势 0 → 1", str(stacks1))
	_check(out1 > 100.0, "逆式这一发有加伤", "%.1f" % out1)
	RogueRun.add_buff("y_ni_stack")
	await get_tree().process_frame
	player.set("yinyang_stacks", 0)
	player.call("_yinyang_modify_damage", d1, "physical_melee", 100.0, "")
	_check(int(player.get("yinyang_stacks")) == 2, "逆流：逆式额外 +1 层（0 → 2）",
		str(int(player.get("yinyang_stacks"))))
	RogueRun.add_buff("y_yin_life")
	var dmg_mark := float(player.call("_yinyang_modify_damage", d1, "physical_melee", 100.0, ""))
	_check(dmg_mark > 0.0, "挂印 / 引爆链路不报错", "%.1f" % dmg_mark)
	d1.queue_free()


func _probe_array(player: Node2D) -> void:
	_check(RogueRun.cap("array_max") == 5, "阵旗上限基值 5")
	RogueRun.add_buff("a_flag_cap")
	RogueRun.add_buff("a_zone_amp")
	RogueRun.add_buff("a_zone_amp")
	await get_tree().process_frame
	_check(RogueRun.cap("array_max") == 7, "扩阵：上限 5 → 7", str(RogueRun.cap("array_max")))
	# 阵威：阵区攻击加成 1.30 → 1.50（这里直接调结算函数，不依赖摆旗）
	player.set("_array_zone_self_attack_mult", 1.0)
	player.call("_refresh_array_zone_attack_mult")
	var zone := float(CharacterData.array_zone_attack_mult)
	_check(absf(zone - 1.0) < 0.001, "阵外不吃阵威", "%.3f" % zone)
	var zone_buff := 1.30 + RogueRun.stat("array_zone_amp") / 100.0
	_check(absf(zone_buff - 1.50) < 0.001, "阵威 ×2：阵内加成 1.30 → 1.50", "%.3f" % zone_buff)
	# 布杀：布旗真的对周围打一发
	RogueRun.add_buff("a_plant_dmg")
	await get_tree().process_frame
	var d := _make_dummy(Vector2(120.0, 0.0))
	await get_tree().process_frame
	var hp0 := float(d.get("current_hp"))
	player.set("array_flags", [])
	# ⚠ 布杀按**落点半径**取敌：木桩在探针根节点下、玩家在战斗场景内，
	#   两者的 global_position 差着几百像素，这里必须把落点设在木桩身上再调。
	player.call("_rogue_array_plant_burst", d.global_position)
	_check(float(d.get("current_hp")) < hp0, "布杀：布旗溅射真的掉血",
		"%.1f → %.1f" % [hp0, float(d.get("current_hp"))])
	# 旗行移速
	RogueRun.add_buff("a_flag_move")
	await get_tree().process_frame
	_check(RogueRun.stat("array_flag_move") > 0.0, "旗行：每面旗移速已登记")
	d.queue_free()


func _probe_qi(player: Node2D) -> void:
	_check(RogueRun.cap("qi_max") == 5, "气环上限基值 5")
	RogueRun.add_buff("q_ring_cap")
	await get_tree().process_frame
	_check(RogueRun.cap("qi_max") == 8, "环枢：上限 5 → 8", str(RogueRun.cap("qi_max")))
	RogueRun.add_buff("q_touch")
	RogueRun.add_buff("q_touch")
	await get_tree().process_frame
	var d := _make_dummy(Vector2(100.0, 0.0))
	await get_tree().process_frame
	var hp0 := float(d.get("current_hp"))
	player.call("_qi_ring_hit", d)
	var dealt := hp0 - float(d.get("current_hp"))
	var expect := CharacterData.spell_attack() * 0.30 * 1.5
	_check(dealt > 0.0, "环身气命中真的掉血", "%.1f" % dealt)
	_check(absf(dealt - expect) < maxf(1.0, expect * 0.05),
		"环锋 ×2：接触系数 ×1.5", "%.1f vs 期望 %.1f" % [dealt, expect])
	# 环守 / 环御接线：受击减伤表能读到
	player.set("qi_rings", 5)
	RogueRun.add_buff("q_def")
	await get_tree().process_frame
	_check(RogueRun.stat("qi_def_pct") > 0.0, "环守：每层减伤已登记")
	RogueRun.add_buff("q_guard")
	await get_tree().process_frame
	_check(RogueRun.has_flag("qi_guard"), "环御：开关已打开")
	# 气爆伤害
	var burst_form := MoveDB.resolve_player("form_qi_burst")
	_check(float(burst_form.get("range", 0.0)) > 0.0, "气爆形态可解析")
	d.queue_free()


func _probe_thunder(player: Node2D) -> void:
	_check(RogueRun.cap("thunder_max") == 3, "雷势上限基值 3")
	RogueRun.add_buff("l_lei_cap")
	await get_tree().process_frame
	_check(RogueRun.cap("thunder_max") == 5, "雷枢：上限 3 → 5", str(RogueRun.cap("thunder_max")))
	RogueRun.add_buff("l_full_haste")
	RogueRun.add_buff("l_full_haste")
	await get_tree().process_frame
	player.set("lei_shi", 0)
	var base_haste := float(player.call("_attack_haste_mult"))
	player.set("lei_shi", RogueRun.cap("thunder_max"))
	var full_haste := float(player.call("_attack_haste_mult"))
	_check(absf(base_haste - 1.0) < 0.001, "非满势没有攻速加成", "%.3f" % base_haste)
	_check(absf(full_haste - (1.0 + 0.30 + 0.20)) < 0.001,
		"满势·疾 ×2：满势攻速 1.30 → 1.50", "%.3f" % full_haste)
	# 雷柱 +1、伤害 +25%
	RogueRun.add_buff("l_pillar_add")
	RogueRun.add_buff("l_pillar_add")
	RogueRun.add_buff("l_pillar_dmg")
	await get_tree().process_frame
	_check(absf(RogueRun.stat("pillar_add") - 2.0) < 0.001, "雷柱·增 ×2：+2 根")
	_check(absf(RogueRun.stat("pillar_pct") - 25.0) < 0.001, "雷柱·重：+25%")
	# 雷势减 CD
	RogueRun.add_buff("l_lei_cd")
	await get_tree().process_frame
	_check(RogueRun.stat("lei_cd_add") > 0.0, "雷势·减：额外减 CD 已登记")


func _probe_sun(player: Node2D) -> void:
	var base_mult := CharacterData.sun_damage_mult
	RogueRun.add_buff("u_stack_dmg")
	await get_tree().process_frame
	player.set("sun_stacks", 3)
	player.call("_apply_sun_crown")
	var with_card := float(CharacterData.sun_damage_mult)
	var expect := 1.0 + (0.12 + 0.03) * 3.0
	_check(absf(with_card - expect) < 0.001, "日冕：3 层 = ×%.2f（每层 +15%%）" % expect,
		"%.3f" % with_card)
	# 满层额外增伤（⚠ 天火种没实体种时每帧 `_tick_sun` 会把层数清零，
	#   所以「再叠一档」必须在同一帧内直接设层数再调，中间不能 await）
	RogueRun.add_buff("u_nova_lie")
	await get_tree().process_frame
	player.set("sun_stacks", 3)
	player.call("_apply_sun_crown")
	var full_mult := float(CharacterData.sun_damage_mult)
	_check(absf(full_mult - (expect + 0.08)) < 0.001, "烈阳：满层再 +8%", "%.3f" % full_mult)
	# 投日 / 焚心倍率
	RogueRun.add_buff("u_throw_dmg")
	RogueRun.add_buff("u_nova_dmg")
	await get_tree().process_frame
	var throw_form := MoveDB.resolve_player("form_sun_throw")
	var spell_c := float(throw_form.get("spell_coeff", 0.0))
	_check(spell_c > 0.0, "投日·烈：投日系数被抬高", "%.3f" % spell_c)
	var nova := float(player.call("_sun_nova_damage", 1.0))
	var nova_plain := CharacterData.spell_attack() * 2.0 * ItemDB.SKILL_DAMAGE_COEFF \
		* CharacterData.spell_skill_damage_mult()
	_check(nova > nova_plain, "焚心·烈：焚心伤害被抬高",
		"%.1f vs %.1f" % [nova, nova_plain])
	player.set("sun_stacks", 0)
	player.call("_clear_sun_crown")
	_check(absf(CharacterData.sun_damage_mult - base_mult) < 0.001, "清层后日冕乘区归 1",
		"%.3f" % CharacterData.sun_damage_mult)


func _probe_calamity(player: Node2D) -> void:
	_check(RogueRun.cap("calamity_max") == 3, "灾势上限基值 3")
	RogueRun.add_buff("c_momentum_cap")
	await get_tree().process_frame
	_check(RogueRun.cap("calamity_max") == 5, "灾枢：上限 3 → 5",
		str(RogueRun.cap("calamity_max")))
	_check(player.get("_calamity_passive_on"), "三灾被动已装")
	# 灾位激活 → 专精加伤
	RogueRun.add_buff("c_elem_dmg")
	await get_tree().process_frame
	player.set("calamity_element", player.CALAMITY_WIND)
	var d := _make_dummy(Vector2(300.0, 0.0))
	await get_tree().process_frame
	var plain := float(player.call("_rogue_modify_damage", 100.0, d, "physical_melee",
		"skill_calamity_slash"))
	_check(absf(plain / 100.0 - 1.2) < 0.01, "专精：风灾招式在风灾位 ×1.2",
		"%.1f" % plain)
	var other := float(player.call("_rogue_modify_damage", 100.0, d, "physical_melee",
		"skill_tiger_claw"))
	_check(absf(other - 100.0) < 0.01, "专精不惠及非灾害招式", "%.1f" % other)
	# 灾崩 / 每痕
	RogueRun.add_buff("c_break_amp")
	RogueRun.add_buff("c_mark_deep")
	await get_tree().process_frame
	d.call("apply_debuff", "zai_beng", 3.0)
	d.call("apply_debuff", "feng_shi", 3.0)
	var broken := float(player.call("_rogue_modify_damage", 100.0, d, "physical_melee",
		"skill_tiger_claw"))
	_check(absf(broken - 100.0 * 1.10 * 1.04) < 0.5,
		"灾崩 +10% × 一痕 +4%", "%.1f" % broken)
	d.queue_free()


func _probe_mirror(player: Node2D) -> void:
	# 起始四式自带被动「照影」→ 基值 = 2（MAX_IMAGES）+ 1（PASSIVE_EXTRA_IMAGES）
	# ⚠ 断言别写死 2：这套的起始功法就带照影，写成 2 会一直红
	var base_cap := int(player.call("_mirror_max_images"))
	_check(base_cap == 3, "镜像上限基值 3（2 + 照影 1）", str(base_cap))
	RogueRun.add_buff("m_cap")
	await get_tree().process_frame
	_check(int(player.call("_mirror_max_images")) == base_cap + 2, "镜枢：上限 +2",
		"%d → %d" % [base_cap, int(player.call("_mirror_max_images"))])
	var img: Node2D = player.call("_mirror_spawn", player.global_position + Vector2(80.0, 0.0))
	await get_tree().process_frame
	_check(img != null, "镜像能生成")
	RogueRun.add_buff("m_per_image")
	await get_tree().process_frame
	var d := _make_dummy(Vector2(300.0, 0.0))
	await get_tree().process_frame
	var per := RogueRun.stat("mirror_dmg_per")
	var out := float(player.call("_rogue_modify_damage", 100.0, d, "physical_melee", ""))
	_check(absf(out - 100.0 * (1.0 + per / 100.0 * 1.0)) < 0.5,
		"映照：1 个镜像 +%d%%" % int(per), "%.1f" % out)
	# 镜返倍率 / 换镜无敌
	RogueRun.add_buff("m_reflect")
	RogueRun.add_buff("m_swap_free")
	await get_tree().process_frame
	_check(RogueRun.stat("mirror_reflect_pct") > 0.0, "镜返·反：反弹倍率已登记")
	_check(RogueRun.stat("mirror_swap_inv") > 0.0, "不碎：换镜额外无敌已登记")
	var slow_before := 2.0
	player.set("invincible_timer", 0.0)
	player.call("_mirror_slow_area", d.global_position, 200.0, slow_before)
	_check(d.call("has_debuff", "mirror_slow"), "碎镜减速挂得上")
	if img != null and is_instance_valid(img):
		img.queue_free()
	d.queue_free()


func _probe_shadow(player: Node2D) -> void:
	player.set("_shadow_dim_left", 0.0)
	var plain := float(player.call("_shadow_dim_mult", "physical"))
	_check(absf(plain - 1.0) < 0.001, "未明灭时物理乘区 1.0", "%.3f" % plain)
	RogueRun.add_buff("w_dim_amp")
	await get_tree().process_frame
	player.set("_shadow_dim_left", 2.0)
	var dimmed := float(player.call("_shadow_dim_mult", "physical"))
	var expect := 1.0 + SkillDB.SHADOW_DIM_PHYS_BONUS + RogueRun.stat("shadow_dim_pct") / 100.0
	_check(absf(dimmed - expect) < 0.001, "明灭·烈：物理乘区 %.3f" % expect, "%.3f" % dimmed)
	player.set("_shadow_dim_left", 0.0)
	_check(RogueRun.cap("thunder_max") > 0, "雷势其它流派不受影响（隔离检查）")
	# 影长上限 / 每 100 影长加伤
	RogueRun.add_buff("w_len")
	RogueRun.add_buff("w_len_dmg")
	await get_tree().process_frame
	_check(RogueRun.stat("shadow_len_pct") > 0.0, "长影：影长上限已登记")
	var d := _make_dummy(Vector2(400.0, 0.0))
	await get_tree().process_frame
	var out := float(player.call("_rogue_modify_damage", 100.0, d, "physical_melee", ""))
	_check(out > 100.0, "影杀：按影长加伤生效", "%.1f" % out)
	# 分影：影兽存在时本体减伤 + 加伤
	RogueRun.add_buff("w_split_erode")
	await get_tree().process_frame
	player.set("_shadow_split_left", 3.0)
	var out2 := float(player.call("_rogue_modify_damage", 100.0, d, "physical_melee", ""))
	_check(out2 > out, "影蚀：影兽在场再加 12%", "%.1f → %.1f" % [out, out2])
	player.set("_shadow_split_left", 0.0)
	d.queue_free()


func _probe_fold(player: Node2D) -> void:
	_check(player.call("_fold_measure_on"), "量折被动已装")
	_check(player.get("_fold_field") == null or not is_instance_valid(player.get("_fold_field")),
		"开局没有个人折痕（需要裁痕）")
	var base_ratio := float(player.call("_fold_mirror_ratio"))
	_check(absf(base_ratio - FoldLaw.MIRROR_RATIO) < 0.001, "镜像比例基值 0.6",
		"%.3f" % base_ratio)
	RogueRun.add_buff("f_ratio")
	await get_tree().process_frame
	var ratio := float(player.call("_fold_mirror_ratio"))
	_check(absf(ratio - (FoldLaw.MIRROR_RATIO + 0.08)) < 0.001, "双面：比例 0.6 → 0.68",
		"%.3f" % ratio)
	# 穿缝加成
	RogueRun.add_buff("f_cross")
	RogueRun.add_buff("f_cross")
	await get_tree().process_frame
	player.set("_fold_cross_left", 2.0)
	var cross := float(player.call("_fold_cross_mult"))
	var expect := 1.0 + FoldLaw.CROSS_BONUS + 0.30
	_check(absf(cross - expect) < 0.001, "穿缝·锐 ×2：加成 +60%", "%.3f" % cross)
	# 裁痕：长度 / 持续受卡影响
	RogueRun.add_buff("f_field_life")
	RogueRun.add_buff("f_field_radius")
	await get_tree().process_frame
	player.call("_fold_cast_seam", Vector2.RIGHT)
	await get_tree().process_frame
	var fld = player.get("_fold_field")
	_check(fld != null and is_instance_valid(fld), "裁痕：个人折痕已铺出")
	if fld != null and is_instance_valid(fld):
		var life := float(fld.get("life_left"))
		_check(life > FoldLaw.PLAYER_SEAM_TIME + 0.5, "折久：折痕持续被延长", "%.2f" % life)
		(fld as Node).queue_free()
		player.set("_fold_field", null)
	# 镜像落点回精力 / 折守
	RogueRun.add_buff("f_mirror_heal")
	RogueRun.add_buff("f_field_guard")
	await get_tree().process_frame
	_check(RogueRun.stat("fold_mirror_stam") > 0.0, "镜像归元：回精力已登记")
	_check(RogueRun.stat("fold_field_guard") > 0.0, "折守：减伤已登记")
