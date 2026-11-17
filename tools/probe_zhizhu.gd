extends Node
## 执烛 · 投影身外之影 全链路探针（2026-11-02）
## 覆盖：位面/塔 11 层 / 八式数据 / 影身几何 / 选招不许空放 / 每招实测出手与落空 /
##       弹反反噬 / 明灭 / 分影 / 二阶段夺灯反照 / 首战空手可破 / 无势条无叠爆 /
##       玩家侧完整继承 / 图鉴 / 掉落与位面材料 / 卡包与字印 / 素材落地。
## 用法：godot --headless --path . res://tools/probe_zhizhu.tscn -- --no-save

const BOSS_SCRIPT := preload("res://scripts/boss/domain_boss_04_b.gd")
const LAMP_SCRIPT := preload("res://scripts/combat/shadow_lamp.gd")
const SWEEPER_SCRIPT := preload("res://scripts/combat/shadow_sweeper.gd")

const FORMS: Array[String] = [
	"form_shadow_cut", "form_shadow_reach", "form_shadow_bind", "form_shadow_step",
	"form_shadow_dim", "form_shadow_beam", "form_shadow_split", "form_shadow_longnight",
]
const SKILLS: Array[String] = [
	"skill_shadow_cut", "skill_shadow_reach", "skill_shadow_bind", "skill_shadow_step",
	"skill_shadow_dim", "skill_shadow_beam", "skill_shadow_split", "skill_shadow_longnight",
	"skill_shadow_lamp",
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


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _ready() -> void:
	print("\n########## 执烛 · 投影身外之影全链路探针 ##########")
	await _run()
	await _check_soft_edges()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	# ===== 1. 位面 / 塔 11 层 / 场景登记 =====
	var dom := WorldDB.get_domain("domain_04")
	var dom_bosses: Array = dom.get("boss_ids", [])
	_check(dom_bosses.size() >= 2 and String(dom_bosses[1]) == "boss_04_b",
		"照影界第二位 = boss_04_b", str(dom_bosses))
	_check(WorldDB.get_boss_name("boss_04_b") == "执烛", "BOSS 名 = 执烛")
	_check(WorldDB.get_boss_scene("boss_04_b") == "res://scenes/boss/domain_boss_04_b.tscn",
		"BOSS 场景已登记")
	_check(ResourceLoader.exists(WorldDB.get_boss_scene("boss_04_b")), "BOSS 场景文件存在")
	_check(WorldDB.get_floors().size() >= 11, "万界塔至少 11 层",
		"n=%d" % WorldDB.get_floors().size())
	var f11 := WorldDB.get_floor(11)
	_check(String(f11.get("boss_id", "")) == "boss_04_b", "第 11 层 = 执烛",
		str(f11.get("boss_id", "")))
	_check(String(f11.get("projection_id", "")) == "proj_boss_04_b", "第 11 层投影 id 对")
	var learned := WorldDB.get_boss_skill_ids("boss_04_b")
	_check(learned.size() == 9, "第 11 层感悟池 = 9 门（八式 + 被动）", str(learned.size()))
	_check(WorldDB.get_floor_reward_skills(11).size() == 9, "感悟池可直接发功法")
	var moves: Array = WorldDB.get_boss_moves("boss_04_b")
	_check(moves.size() == 8, "BOSS_MOVES 登记八式", str(moves.size()))

	# ===== 2. 形态数据：双侧齐全 + 消耗准则 =====
	for fid in FORMS:
		var raw := MoveDB.get_form(String(fid))
		_check(not raw.is_empty(), "形态已登记 " + String(fid))
		var merged := MoveDB.resolve_boss(String(fid))
		_check(not merged.is_empty() and merged.has("attack_kind"),
			"BOSS 侧规则齐全 " + String(fid), String(merged.get("attack_kind", "")))
		var pl := MoveDB.resolve_player(String(fid))
		_check(not pl.is_empty(), "玩家侧规则齐全 " + String(fid))
		var kind := String(merged.get("attack_kind", ""))
		var parryable := bool(merged.get("parryable", false))
		_check(parryable == (kind != "elemental"),
			"可弹反 = 物理 / 不可弹反 = 法术：" + String(fid),
			"%s / parry=%s" % [kind, str(parryable)])
	_check(is_equal_approx(float(MoveDB.resolve_boss("form_shadow_reach").get("damage_coeff", 0.0)), 1.15),
		"投晷系数 1.15")
	_check(is_equal_approx(float(MoveDB.resolve_boss("form_shadow_longnight").get("damage_mult_p2", 0.0)), 1.5),
		"二阶段伤害 ×1.5（2026-10-31 口径）")

	# ===== 3. 功法条目：8 主动 + 1 被动，元素与消耗口径 =====
	for sid in SKILLS:
		var sk := SkillDB.get_skill(String(sid))
		_check(not sk.is_empty(), "功法已登记 " + String(sid))
		_check(String(sk.get("source_boss_id", "")) == "boss_04_b", "归属执烛 " + String(sid))
		_check(bool(sk.get("shadow", false)), "打上投影标记 " + String(sid))
		_check(String(sk.get("tower_projection_id", "")) == "proj_boss_04_b",
			"塔投影绑定 " + String(sid))
	_check(String(SkillDB.get_skill("skill_shadow_lamp").get("skill_type", ""))
			== SkillDB.TYPE_PASSIVE, "执灯是被动的唯一一门")
	# ===== 3a. 元素：投影一路挂「暗」，不再和观澜（镜）撞同一个抗性维度 =====
	# MoveDB 的 damage_element 是 BOSS / 玩家**共用**的一行，所以改元素等于两边一起改：
	# 执烛自己的招式也认暗抗。这里同时钉住镜身仍是水，防止哪天顺手把整界都刷成暗。
	for fid in FORMS:
		_check(String(MoveDB.resolve_boss(String(fid)).get("damage_element", "")) == "dark",
				"形态元素 = 暗 " + String(fid))
	for mf in ["form_mirror_slash", "form_mirror_thrust", "form_mirror_bloom",
			"form_mirror_shatter", "form_mirror_swap", "form_mirror_return",
			"form_mirror_ring", "form_mirror_myriad"]:
		var melem := String(MoveDB.resolve_boss(mf).get("damage_element", ""))
		if melem != "":
			_check(melem == "water", "观澜（镜）仍是水 " + mf, melem)
	var rules := SkillDB.get_group_rules("boss_04_b")
	_check(not rules.is_empty() and String(rules.get("title", "")).contains("投影"),
		"功法库有投影机制组说明", String(rules.get("title", "")))
	_check(SkillDB.get_shadow_rules().size() >= 8, "机制说明至少 8 行",
		str(SkillDB.get_shadow_rules().size()))
	for raw in SkillDB.get_shadow_rules():
		var line := String(raw)
		_check(not ("势条" in line and not ("没有势条" in line)),
			"说明里没有势条读数", line.substr(0, 24))

	# ===== 3b. 硬禁令：没有势条 / 没有叠层兑现 =====
	_check(not SkillDB.get_skill("skill_shadow_reach").has("qi_ring") \
			and not SkillDB.get_skill("skill_shadow_reach").has("intent_gain"),
		"影技不吃任何资源条，也不产势")
	_check(not FileAccess.get_file_as_string("res://scripts/boss/domain_boss_04_b.gd")
			.contains("stacks"), "执烛脚本里没有任何攒层字段（无势条实现）")
	_check(ShadowLaw.SHADOW_MIN > 0.0 and ShadowLaw.SHADOW_MAX > ShadowLaw.SHADOW_MIN,
		"影长是几何量而不是层数", "%.0f~%.0f" % [ShadowLaw.SHADOW_MIN, ShadowLaw.SHADOW_MAX])

	# ===== 4. 影身几何：命中与落空各一条 =====
	_check(is_equal_approx(ShadowLaw.shadow_len(0.0), ShadowLaw.SHADOW_MIN),
		"灯正下方影长 = 最短", "%.0f" % ShadowLaw.shadow_len(0.0))
	_check(ShadowLaw.shadow_len(400.0) > ShadowLaw.shadow_len(150.0),
		"离灯越远影越长",
		"%.0f vs %.0f" % [ShadowLaw.shadow_len(150.0), ShadowLaw.shadow_len(400.0)])
	_check(is_equal_approx(ShadowLaw.shadow_len(4000.0), ShadowLaw.SHADOW_MAX),
		"影长封顶（不会被拉满全场）", "%.0f" % ShadowLaw.shadow_len(4000.0))
	var origin := Vector2(0.0, 0.0)
	var down := Vector2(0.0, 1.0)
	_check(ShadowLaw.corridor_contains(origin, down, 300.0, Vector2(0.0, 240.0)),
		"影身中段命中判定成立")
	_check(not ShadowLaw.corridor_contains(origin, down, 300.0, Vector2(0.0, -120.0)),
		"灯侧（身后）不在判定里 —— 站到灯与它之间能拆招")
	_check(not ShadowLaw.corridor_contains(origin, down, 300.0, Vector2(0.0, 460.0)),
		"超出影尖打不到")
	_check(not ShadowLaw.corridor_contains(origin, down, 300.0, Vector2(140.0, 150.0)),
		"走廊外侧打不到（宽度就是画出来的那条带子）")
	_check(ShadowLaw.can_reach(Vector2(0.0, 0.0), Vector2(0.0, -200.0), down, Vector2(0.0, 250.0)),
		"离灯 200 时能够到 250 处的玩家")
	_check(not ShadowLaw.can_reach(Vector2(0.0, 0.0), Vector2(0.0, -30.0), down, Vector2(0.0, 250.0)),
		"被逼到灯下就够不到（拆射程是真的）")

	# ===== 5. 真实箱庭 =====
	for sid in SKILLS:
		if not CharacterData.learned_skills.has(String(sid)):
			CharacterData.learned_skills.append(String(sid))
	CharacterData.active_skill_loadout = [
		"skill_shadow_reach", "skill_shadow_cut", "skill_shadow_beam", "skill_shadow_bind"]
	CharacterData.passive_skill_loadout = ["skill_shadow_lamp"]
	_wear_baseline(1, 6)
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04_b",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	_check(player != null and is_instance_valid(player), "真实 Player 已生成")
	_check(boss != null and is_instance_valid(boss), "真实 BOSS 已生成")
	if player == null or boss == null:
		return
	_check(boss.boss_id == "boss_04_b", "箱庭加载的是执烛", boss.boss_id)
	_check(boss.get_script() == BOSS_SCRIPT, "BOSS 使用 domain_boss_04_b")
	_check(is_equal_approx(boss.max_hp, 56000.0) and is_equal_approx(boss.attack_power, 205.0),
		"BOSS 数值 = 56000 / 205（目标 TTK 68~78s）",
		"hp=%.0f atk=%.0f" % [boss.max_hp, boss.attack_power])
	_check(is_equal_approx(boss.physical_resist, 20.0) and is_equal_approx(boss.magic_resist, 0.0),
		"物抗 20 / 法抗 0（与观澜的法术门禁反向）")
	_check(boss._lamp != null and is_instance_valid(boss._lamp), "界灯已生成")
	_check(LAMP_SCRIPT.new() is Node2D, "界灯是独立可复用节点")
	_check(boss._shadow != null and is_instance_valid(boss._shadow), "本体影身已生成")
	player._apply_attributes_to_runtime(true)
	print("  玩家面板：HP %.0f · 物攻 %.0f · 法强 %.0f · 法技 ×%.3f" % [
		player.max_hp, CharacterData.physical_attack(), CharacterData.spell_attack(),
		1.0 + CharacterData.attribute(AttributeDB.ATTR_SPELL_SKILL_DAMAGE_PCT) / 100.0])
	_check(player.max_hp >= 440.0 and CharacterData.physical_attack() >= 175.0
			and CharacterData.spell_attack() >= 145.0,
		"元婴初期 · 道器 +6 baseline 已穿上（后期数值由 probe_zhizhu_live_play 实测）",
		"HP %.0f 物攻 %.0f 法强 %.0f" % [player.max_hp,
			CharacterData.physical_attack(), CharacterData.spell_attack()])
	print("  战场半宽高 %s · 灯在 %s · BOSS 在 %s" % [
		str(boss.arena_half_extents), str(boss._light_pos()), str(boss.global_position)])

	# ===== 6. AI 不许空放：够不到就不放远程，改抢位置 =====
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.state = BossBase.BossState.IDLE
	boss._cools.clear()
	boss._decide_wait = 0.0
	var lamp_pos: Vector2 = boss._light_pos()
	# 玩家站到「灯 — BOSS」连线的灯那一侧：影身甩到反方向，远程招必然打空
	player.global_position = lamp_pos + (boss.global_position - lamp_pos).normalized() * 40.0
	boss.target = player
	boss._set_facing((player.global_position - boss.global_position).normalized())
	player.invincible_timer = 999.0
	var picks := {}
	for i in 40:
		boss.state = BossBase.BossState.IDLE
		boss._decide_wait = 0.0
		boss._recent.clear()
		boss._cools.clear()
		boss._choose()
		picks[String(boss._current_skill)] = true
	_check(not picks.has("form_shadow_reach") or boss._lamp_owned,
		"影身盖不住玩家时绝不选投晷（不许空放）", str(picks.keys()))
	_check(picks.has("form_shadow_step") or picks.has("form_shadow_dim") \
			or picks.has("form_shadow_beam"),
		"够不到时用踏灯 / 明灭 / 照骨应对，而不是原地罚站", str(picks.keys()))
	# 玩家挪到影尖方向：投晷应当重新变得可用
	player.global_position = boss.global_position \
			+ (boss.global_position - lamp_pos).normalized() * 210.0
	boss._set_facing((player.global_position - boss.global_position).normalized())
	boss.state = BossBase.BossState.IDLE
	boss._decide_wait = 0.0
	boss._recent.clear()
	boss._cools.clear()
	boss._cools["form_shadow_bind"] = 99.0
	boss._cools["form_shadow_dim"] = 99.0
	boss._cools["form_shadow_split"] = 99.0
	var reach_seen := false
	for i in 30:
		boss.state = BossBase.BossState.IDLE
		boss._decide_wait = 0.0
		boss._recent.clear()
		boss._cools = {"form_shadow_bind": 99.0, "form_shadow_dim": 99.0,
			"form_shadow_split": 99.0}
		boss._choose()
		if String(boss._current_skill) == "form_shadow_reach":
			reach_seen = true
	_check(reach_seen, "影身能够到人时投晷重新可选")

	# ===== 7. 八式逐招实测：站在影身上必须掉血，站在灯侧不掉 =====
	boss.set_physics_process(true)
	boss.set_process(true)
	await _wait(0.2)
	boss.set_physics_process(false)
	boss.set_process(false)
	var bform := {}
	for fid in FORMS:
		bform[String(fid)] = MoveDB.resolve_boss(String(fid))
	for fid in FORMS:
		if String(fid) in ["form_shadow_dim", "form_shadow_longnight"]:
			continue
		if String(fid) == "form_shadow_step":
			await _step_moves(boss, player)
			continue
		if String(fid) == "form_shadow_split":
			await _split_chases(boss, player)
			continue
		await _hit_pair(boss, player, String(fid), bform[String(fid)])
	# 明灭：不造成伤害，但要压暗灯、缩短影长
	await _check_dim(boss, player)
	# 长夜：二阶段招，一阶段不许出现
	boss.phase = 1
	boss.state = BossBase.BossState.IDLE
	boss._cools.clear()
	boss._decide_wait = 0.0
	boss._recent.clear()
	boss._choose()
	_check(String(boss._current_skill) != "form_shadow_longnight",
		"一阶段不会选出长夜 · 一灯", String(boss._current_skill))

	# ===== 8. 弹反影身招 → 影子反噬本体 =====
	boss._current_skill = "form_shadow_reach"
	boss._phase_two = false
	var hp_before_parry: float = boss.current_hp
	boss.on_parried(player)
	await _wait(0.1)
	_check(boss.current_hp < hp_before_parry, "弹反成功让影子折回来砍它自己",
		"%.0f -> %.0f" % [hp_before_parry, boss.current_hp])

	# ===== 9. 首战空手可破：不学任何执烛功法也能打 =====
	player.invincible_timer = 999.0
	var bare_hp: float = boss.current_hp
	boss.take_damage(500.0, player, "physical", "")
	_check(boss.current_hp < bare_hp, "空手物理打本体有效",
		"%.0f -> %.0f" % [bare_hp, boss.current_hp])
	var bare_hp2: float = boss.current_hp
	boss.take_damage(500.0, player, "elemental", "fire")
	_check(boss.current_hp < bare_hp2, "任意属性术法打本体有效（不锁颜色）",
		"%.0f -> %.0f" % [bare_hp2, boss.current_hp])
	_check(boss.debuffs.is_empty() or not boss.debuffs.has("shadow_bind"),
		"本体不吃自己的影缚")

	# ===== 10. 二阶段：夺灯反照 =====
	boss.set_physics_process(true)
	boss.set_process(true)
	boss.current_hp = boss.max_hp * 0.4
	boss.take_damage(1.0, player, "physical", "")
	await _wait(1.4)
	_check(boss.phase == 2, "自然进入二阶段", "phase=%d" % boss.phase)
	_check(boss._lamp_owned, "二阶段：灯被执烛提走")
	_check(boss._lamp == null or not is_instance_valid(boss._lamp), "界灯节点已退场")
	var chan: Dictionary = boss._anchor_at(player.global_position)
	_check(not chan.is_empty(), "二阶段能算出玩家的影带")
	var bd: Vector2 = chan.get("dir", Vector2.ZERO)
	var expect: Vector2 = (player.global_position - boss.global_position).normalized()
	_check(bd.distance_to(expect) < 0.05, "影带朝背离执烛的方向铺（后退才会撞进自己影子）",
		"%.2f vs %.2f" % [bd.x, expect.x])
	player.global_position = boss.global_position + Vector2(0.0, 260.0)
	boss._set_facing((player.global_position - boss.global_position).normalized())
	boss.state = BossBase.BossState.IDLE
	boss._decide_wait = 0.0
	boss._recent.clear()
	boss._cools.clear()
	var p2_picks := {}
	for i in 40:
		boss.state = BossBase.BossState.IDLE
		boss._decide_wait = 0.0
		boss._recent.clear()
		boss._cools.clear()
		boss._choose()
		p2_picks[String(boss._current_skill)] = true
	_check(p2_picks.has("form_shadow_longnight"), "二阶段会出长夜 · 一灯", str(p2_picks.keys()))
	var hp_before_ln: float = player.hp
	player.invincible_timer = 0.0
	player.hp = player.max_hp
	boss._current_skill = "form_shadow_longnight"
	boss._anchor = boss._anchor_at(player.global_position)
	boss._cast_longnight(MoveDB.resolve_boss("form_shadow_longnight"))
	await _wait(0.1)
	_check(player.hp < player.max_hp, "长夜落在玩家影带上（贴脸/侧移才躲得掉）",
		"hp %.0f" % player.hp)
	player.invincible_timer = 999.0
	player.hp = player.max_hp

	# ===== 11. 玩家侧完整继承 =====
	await _player_side(player, boss)

	# ===== 12. 暗 · 蚀：端到端（走真实 take_damage，不是手搓 ctx）=====
	await _dark_erosion(player, boss)

	# ===== 13. 图鉴 / 掉落 / 位面材料 / 卡包 / 字印 =====
	_content_check()
	GameState.battle_context = {}


## 暗是**通用属性**，所以这条链不许依赖任何影系配置：
## 只要一击的 element 是 dark，受击方自己就该挂上蚀 —— 来源是 BOSS 还是玩家都一样。
func _dark_erosion(player: Node2D, boss: Node2D) -> void:
	var eid := AttributeDB.DARK_EROSION_ID
	boss.set_physics_process(false)
	boss.set_process(false)
	player.set_physics_process(false)

	# 1) 只有暗命中才挂
	_clear_hit_windows(player)
	player.take_damage(60.0, "physical", null, "water")
	_check(not player.debuffs.has(eid), "水属性命中不挂蚀（规则只认暗）")
	_clear_hit_windows(player)
	player.take_damage(60.0, "physical", null, AttributeDB.DARK)
	_check(player.debuffs.has(eid), "暗属性命中自动挂蚀（不占 form.debuff_on_hit）",
			"%.1fs" % float(player.debuffs.get(eid, 0.0)))
	_check(is_equal_approx(player.debuff_resist_shred(),
			AttributeDB.DARK_EROSION_RESIST_SHRED),
			"蚀期间穿抗乘区 = 0.40", "%.2f" % player.debuff_resist_shred())
	_check(is_equal_approx(player.debuff_heal_mult(),
			AttributeDB.DARK_EROSION_HEAL_MULT),
			"蚀期间治疗乘区 = 0.10（减疗 90%）", "%.2f" % player.debuff_heal_mult())

	# 2) 刷新锁：蚀期间再中暗招不续杯（否则减疗 90% 会被常驻磨死治疗流）
	var t0: float = float(player.debuffs[eid])
	_clear_hit_windows(player)
	player.debuffs[eid] = t0
	player.dark_erosion_lock = AttributeDB.DARK_EROSION_REFRESH_CD
	player.take_damage(60.0, "physical", null, AttributeDB.DARK)
	_check(is_equal_approx(float(player.debuffs[eid]), t0),
			"蚀期间第二次暗击不续杯（9 秒刷新锁）", "%.2f -> %.2f" % [
			t0, float(player.debuffs[eid])])

	# 3) 减疗真的作用在回血入口上（丹药 / 水愈符 / 法宝 / 气环·回息 / 吐纳 / 续命灯全走 restore_health）
	player.debuffs[eid] = 5.0
	player.hp = player.max_hp * 0.5
	var healed: float = player.restore_health(100.0)
	_check(is_equal_approx(healed, 100.0 * AttributeDB.DARK_EROSION_HEAL_MULT),
			"蚀期间回血只剩 10%", "%.1f" % healed)
	player.debuffs.clear()
	player.hp = player.max_hp * 0.5
	var healed_clean: float = player.restore_health(100.0)
	_check(is_equal_approx(healed_clean, 100.0),
			"蚀结束后回血恢复满额（不是永久削弱）", "%.1f" % healed_clean)

	# 4) BOSS 侧同一条规则：暗击把蚀挂到执烛身上，它的回血同样被压
	boss.debuffs.clear()
	boss.dark_erosion_lock = 0.0
	boss.current_hp = boss.max_hp * 0.5
	boss.take_damage(60.0, null, "physical", AttributeDB.DARK)
	_check(boss.debuffs.has(eid), "暗击在 BOSS 侧同样挂蚀（规则对称）")
	var bh: float = boss.apply_heal(1000.0)
	_check(is_equal_approx(bh, 1000.0 * AttributeDB.DARK_EROSION_HEAL_MULT),
			"蚀期间 BOSS 回血也只剩 10%（apply_heal 是唯一入口）", "%.1f" % bh)

	# 5) 真放一招影技（走完整结算链，不是手搓 take_damage）：影系自己就该把蚀挂上去
	player._lantern_pos = player.global_position + Vector2(-240.0, 0.0)
	player._shadow_snap_left = 0.0
	boss.global_position = player.global_position + Vector2(300.0, 0.0)
	boss.debuffs.clear()
	boss.dark_erosion_lock = 0.0
	player._shadow_cast_reach(Vector2.RIGHT)
	await _wait(0.1)
	_check(boss.debuffs.has(eid),
			"投晷真的把蚀挂上了 BOSS（影系八式的元素就是暗，不用另配 debuff_on_hit）",
			str(boss.debuffs.keys()))

	# 6) 面板不许撒谎：蚀只存在于结算层，抗性读数一个字都没改
	var shown := float(CharacterData.attribute(AttributeDB.ATTR_PHYSICAL_RESIST))
	boss.debuffs.clear()
	player.debuffs.clear()
	player.dark_erosion_lock = 0.0
	player.hp = player.max_hp
	player.invincible_timer = 999.0
	player.set_physics_process(true)
	_check(is_equal_approx(float(CharacterData.attribute(AttributeDB.ATTR_PHYSICAL_RESIST)), shown),
			"蚀不改 attribute()：角色面板显示的仍是真实抗性", "物抗 %.0f" % shown)


## 清掉「这一击到底落不落地」的全部窗口：无敌帧 / 自动弹刀守势 / 闪避 / 镜返 /
## 纳势格挡 / 防重复挂 debuff 的 0.1 秒窗。
## ⚠ 这些窗口不是探针障碍，是**正确行为**：被弹反、闪避或无敌帧吞掉的暗击，
##   伤害没落地，元素交互也就不该落地 —— 不能出现「躲开了却中减疗 90%」。
##   探针连打两下会同时踩中 0.3 秒无敌帧和 0.1 秒防重复窗，所以每击前单独清。
func _clear_hit_windows(player: Node2D) -> void:
	player.debuffs.clear()
	player.dark_erosion_lock = 0.0
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0
	player.auto_parry_timer = 0.0
	player.is_parrying = false
	player.is_dodging = false
	player._counter_charging = false
	player._mirror_return_left = 0.0
	player.hp = player.max_hp

func _hit_pair(boss: Node2D, player: Node2D, fid: String, form: Dictionary) -> void:
	var lamp: Vector2 = boss._light_pos()
	var away: Vector2 = (boss.global_position - lamp).normalized()
	if away.length_squared() < 0.01:
		away = Vector2.DOWN
	var len_now: float = boss._shadow_length_at(boss.global_position)
	# A) 玩家站在这招真实判定会盖到的位置
	player.global_position = boss.global_position + away * _probe_stand(fid, len_now)
	boss.target = player
	boss._set_facing((player.global_position - boss.global_position).normalized())
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0
	player.is_parrying = false
	player.hp = player.max_hp
	await _fire(boss, player, fid, form)
	var hit: bool = player.hp < player.max_hp
	# B) 玩家挪到灯那一侧（影子的反方向）：同一招必须打不到
	player.global_position = lamp + away * 30.0 + Vector2(6.0, 0.0)
	boss._set_facing((player.global_position - boss.global_position).normalized())
	player.hp = player.max_hp
	await _fire(boss, player, fid, form)
	var miss: bool = player.hp >= player.max_hp
	_check(hit, "站到判定里会被 %s 打中" % String(form.get("form_name", fid)))
	_check(miss, "站到灯侧躲开 %s（走位可解，不是必中）" % String(form.get("form_name", fid)),
		"hp %.0f/%.0f" % [player.hp, player.max_hp])
	player.invincible_timer = 999.0
	player.hp = player.max_hp


## 每招「站得住」的距离：扇形吃 range，直线吃影长，落印吃影身中段
func _probe_stand(fid: String, length: float) -> float:
	match fid:
		"form_shadow_cut":
			return 110.0
		"form_shadow_reach":
			return minf(length * 0.8, length - 20.0)
		"form_shadow_bind":
			return length * 0.62
		"form_shadow_beam":
			return 260.0
		"form_shadow_split":
			return 240.0
	return 200.0


## 分影是脱手追人的：站定必被扫到；在 0.45s 预兆里持续横移才扫得空
func _split_chases(boss: Node2D, player: Node2D) -> void:
	var lamp: Vector2 = boss._light_pos()
	var away: Vector2 = (boss.global_position - lamp).normalized()
	player.global_position = boss.global_position + away * 240.0
	boss.target = player
	boss._set_facing(away)
	player.invincible_timer = 0.0
	player.hp = player.max_hp
	boss._split_left = 0.0
	boss._cast_split(MoveDB.resolve_boss("form_shadow_split"))
	_check(boss._split_left > 0.0, "分影进入脱手期")
	_check(is_equal_approx(boss.damage_taken_multiplier("physical"),
			ShadowLaw.SPLIT_TAKEN_MULT), "分影期间本体受伤加重（输出窗）",
		"%.2f" % boss.damage_taken_multiplier("physical"))
	await _wait(ShadowLaw.SPLIT_SWEEP_GAP + 0.7)
	_check(player.hp < player.max_hp, "站定会被脱手影身扫到", "hp %.0f" % player.hp)
	var hp_after: float = player.hp
	player.hp = player.max_hp
	## 预兆期内横移 260：影带是死的，人跑了就该扫空
	var dodged := 0
	for i in 6:
		player.global_position += Vector2(0.0, 120.0)
		await _wait(0.1)
		if player.hp >= player.max_hp:
			dodged += 1
		player.hp = player.max_hp
	_check(dodged >= 3, "横移能在预兆期躲开脱手影身（不是自动锁）", "%d/6 段扫空" % dodged)
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	boss._split_left = 0.0
	if boss._sweeper != null and is_instance_valid(boss._sweeper):
		boss._sweeper.call("detach_and_free")
	boss._sweeper = null


## 位移招不判命中（布点 / 位移不作攻击门禁），但必须真的位移
func _step_moves(boss: Node2D, player: Node2D) -> void:
	var lamp: Vector2 = boss._light_pos()
	var away: Vector2 = (boss.global_position - lamp).normalized()
	var room: float = maxf(180.0, boss.arena_half_extents.y * 0.6)
	player.global_position = boss.global_position + away * room
	boss.target = player
	boss._set_facing(away)
	var before: Vector2 = boss.global_position
	boss._cast_step(MoveDB.resolve_boss("form_shadow_step"))
	await _wait(0.1)
	var moved: float = boss.global_position.distance_to(before)
	_check(moved > 24.0, "踏灯真的产生位移（不是只播动画）",
		"%.0fpx（战场半高 %.0f）" % [moved, boss.arena_half_extents.y])
	var covers: bool = boss._channel_covers(boss._channel(), player.global_position)
	_check(covers, "踏灯的落点按影长解算：换位后影身能够到人")


func _fire(boss: Node2D, player: Node2D, fid: String, form: Dictionary) -> void:
	match fid:
		"form_shadow_cut":
			boss._cast_cut(form)
		"form_shadow_reach":
			boss._cast_reach(form)
		"form_shadow_bind":
			boss._cast_bind(form)
			## 延迟招：BOSS 的帧循环此刻是关着的，直接驱动它的结算钩子
			boss._bind_left = 0.0
			boss._resolve_bind()
		"form_shadow_beam":
			boss._cast_beam(form)
		"form_shadow_split":
			boss._cast_split(form)
			await _wait(ShadowLaw.SPLIT_SWEEP_GAP + 0.7)
		_:
			boss._cast_cut(form)
	await _wait(0.12)


func _check_dim(boss: Node2D, player: Node2D) -> void:
	boss._split_left = 0.0
	var len_before: float = boss._shadow_length_at(boss.global_position)
	boss._current_skill = "form_shadow_dim"
	boss._cast_dim(MoveDB.resolve_boss("form_shadow_dim"))
	await _wait(0.5)
	_check(boss._dim_left > 0.0, "明灭真的进入暗场", "%.1fs" % boss._dim_left)
	_check(boss._shadow_length_at(boss.global_position) < len_before * 0.6,
		"暗场期间影长明显缩短", "%.0f -> %.0f" % [
			len_before, boss._shadow_length_at(boss.global_position)])
	_check(is_equal_approx(boss._dmg_scale(), ShadowLaw.DIM_SELF_ATTACK_MULT),
		"暗场期间本体招式伤害上涨", "%.2f" % boss._dmg_scale())
	_check(is_equal_approx(boss.damage_taken_multiplier("physical"),
			ShadowLaw.DIM_PHYS_VULN), "暗场期间本体受物理伤害加重（输出窗是真的）",
		"%.2f" % boss.damage_taken_multiplier("physical"))
	boss._dim_left = 0.0


func _player_side(player: Node2D, boss: Node2D) -> void:
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.current_hp = boss.max_hp
	player.invincible_timer = 999.0
	player._shadow_reset()
	await _wait(0.2)
	player._lantern_pos = player.global_position + Vector2(0.0, -240.0)
	var length: float = player._shadow_len()
	_check(length > 300.0, "玩家灯笼拖在身后 → 影长随距离变长", "%.0f" % length)
	player._lantern_pos = player.global_position
	_check(player._shadow_len() <= ShadowLaw.SHADOW_MIN + 1.0,
		"站定影长塌回脚边（射程不是无限的）", "%.0f" % player._shadow_len())
	_check(player._shadow_equipped(), "带影系功法时机制读数开启")
	_check(player._shadow_lamp_passive_on(), "被动「执灯」识别正确")
	_check(is_equal_approx(player._shadow_dim_mult("physical"), 1.0) \
			and is_equal_approx(player._shadow_dim_mult("elemental"), 1.0),
		"未开明灭时没有隐藏增伤")
	# 射程随影长：把 BOSS 放影长内 / 外各打一次
	var dir := Vector2.RIGHT
	player.global_position = Vector2(0.0, 0.0)
	boss.global_position = Vector2(300.0, 0.0)
	player._lantern_pos = Vector2(-240.0, 0.0)
	var fitted: Dictionary = player._shadow_fit_form("skill_shadow_reach",
		SkillDB.get_skill_form("skill_shadow_reach"))
	_check(is_equal_approx(float(fitted.get("range", 0.0)), player._shadow_len()),
		"影技射程 = 当前影长（判定与特效同一份）", "%.0f" % float(fitted.get("range", 0.0)))
	boss.current_hp = boss.max_hp
	var hp_b: float = boss.current_hp
	player._shadow_cast_reach(dir)
	await _wait(0.1)
	_check(boss.current_hp < hp_b, "投晷在影长内命中 BOSS",
		"%.0f -> %.0f" % [hp_b, boss.current_hp])
	boss.global_position = Vector2(900.0, 0.0)
	hp_b = boss.current_hp
	player._shadow_cast_reach(dir)
	await _wait(0.1)
	_check(is_equal_approx(boss.current_hp, hp_b), "超出影长就打不到（射程真的受几何约束）")
	# 明灭：影长归零 + 物理增伤
	player._shadow_cast_dim()
	_check(player._shadow_len() < ShadowLaw.SHADOW_MIN, "明灭把影长收到脚边",
		"%.0f" % player._shadow_len())
	_check(player._shadow_dim_mult("physical") > 1.2, "明灭期间物理功法增伤",
		"×%.2f" % player._shadow_dim_mult("physical"))
	_check(is_equal_approx(player._shadow_dim_mult("elemental"), 1.0),
		"明灭只加物理，不加术法")
	player._shadow_dim_left = 0.0
	# 缚影：钉住 BOSS
	boss.global_position = Vector2(260.0, 0.0)
	boss.debuffs.clear()
	boss.velocity = Vector2.ZERO
	boss.set_physics_process(false)
	player._lantern_pos = Vector2(-240.0, 0.0)
	player._shadow_cast_bind(dir)
	await _wait(SkillDB.SHADOW_BIND_DELAY + 0.35)
	_check(float(boss.debuffs.get("shadow_bind", 0.0)) > 0.0, "缚影真的钉住敌人",
		str(boss.debuffs.keys()))
	_check(is_equal_approx(boss.debuff_move_mult(), 0.0), "影缚期间移速归零（但没吞行动）")
	_check(not boss.is_stunned(), "影缚不是眩晕：仍可出手")
	# 分影：撕影尖那一截 —— 影兽代打 + 自己影长打折，但投晷不再被封
	boss.debuffs.clear()
	player._shadow_cast_split(dir)
	_check(player._shadow_split_left > 0.0, "分影进入代打期")
	_check(not player._shadow_cast_blocked("skill_shadow_reach"),
		"分影期间投晷照打：撕走的是影尖那一截，不是整条影子")
	_check(player._shadow_cast_blocked("skill_shadow_bind"),
		"缚影仍要等影尖回来：代价没消失，只是不再封全组 DPS 最高的那招")
	_check(not player._shadow_cast_blocked("skill_shadow_beam"),
		"照骨是本体光束，不受分影影响")
	# 代价对照：影长 ×SHADOW_SPLIT_LEN_MULT
	# ⚠ 必须当场重摆灯笼：前面那些 await 里玩家一直在跑 _shadow_update_lantern，
	#   站着的 0.35 秒足够把拖尾追平，不重摆就变成拿「已经塌到 40」去比 40×0.72。
	player._shadow_split_left = 0.0
	player._lantern_pos = player.global_position + Vector2(-240.0, 0.0)
	var len_whole: float = player._shadow_len_now()
	player._shadow_split_left = 2.0
	_check(is_equal_approx(player._shadow_len_now(),
			len_whole * SkillDB.SHADOW_SPLIT_LEN_MULT),
		"分影期间影长打折 = 被撕掉的那一截", "%.0f -> %.0f" % [
		len_whole, player._shadow_len_now()])
	player._shadow_split_left = 0.0
	var sweeper_seen := false
	for c in player.get_parent().get_children():
		if c.get_script() == SWEEPER_SCRIPT:
			sweeper_seen = true
	_check(sweeper_seen, "玩家侧脱手影身已创建")
	var hp_split: float = boss.current_hp
	boss.global_position = player.global_position + Vector2(150.0, 0.0)
	await _wait(ShadowLaw.SPLIT_SWEEP_GAP + 0.8)
	_check(boss.current_hp < hp_split, "玩家的分影在扫敌人（不打自己人）",
		"%.0f -> %.0f" % [hp_split, boss.current_hp])
	player._shadow_reset()
	_check(player._shadow_split_left <= 0.0, "退出战斗清掉分影状态")
	# ===== A：影长快照 + 惯性（2026-11-05 执灯组增强）=====
	# 按下那一帧定格：前摇里灯笼追平，也不能让打出去的射程比看见的短
	player._shadow_reset()
	await _wait(0.1)
	player.set_physics_process(false)
	player.velocity = Vector2(220.0, 0.0)
	player._lantern_pos = player.global_position + Vector2(-250.0, 0.0)
	player._lantern_speed_avg = 220.0
	player._shadow_snap_left = 0.0
	var len_press: float = player._shadow_len_now()
	player._shadow_precast("skill_shadow_reach", Vector2.RIGHT)
	player._lantern_pos = player.global_position
	player._lantern_speed_avg = 0.0
	_check(player._shadow_snap_left > 0.0, "按下影技时影长上了快照")
	_check(is_equal_approx(player._shadow_len(), len_press),
			"快照期间射程不跟着灯笼追平缩水（不再看着够、打出去空）", "%.0f" % len_press)
	_check(player._shadow_len_now() < len_press * 0.3,
			"对照：这一帧的实时影长确实已经塌了", "%.0f" % player._shadow_len_now())
	var fitted_snap: Dictionary = player._shadow_fit_form("skill_shadow_reach",
		SkillDB.get_skill_form("skill_shadow_reach"))
	_check(is_equal_approx(float(fitted_snap.get("range", 0.0)), len_press),
			"特效覆盖的射程读同一份快照（判定与画面不再分叉）")
	player._shadow_snap_left = 0.0
	# 惯性：拖尾吃速度均值，平A 那 0.35 秒定身不该把射程抽回脚边
	player._lantern_pos = player.global_position
	player._lantern_speed_avg = 0.0
	for i in 100:
		player._shadow_update_lantern(1.0 / 60.0)
	var len_run: float = player._shadow_len_now()
	player.velocity = Vector2.ZERO
	for i in 21:
		player._shadow_update_lantern(1.0 / 60.0)
	var len_held: float = player._shadow_len_now()
	_check(len_run > 400.0, "跑满 1.6 秒影长顶到高位", "%.0f" % len_run)
	_check(len_held > len_run * 0.55,
			"平A 定身 0.35 秒后影长还剩六成以上（旧口径按瞬时速度只剩两成）",
			"%.0f -> %.0f" % [len_run, len_held])
	for i in 120:
		player._shadow_update_lantern(1.0 / 60.0)
	_check(player._shadow_len_now() <= ShadowLaw.SHADOW_MIN + 1.0,
			"真站着不动 2 秒照样塌回脚边：射程仍然要跑位换",
			"%.0f" % player._shadow_len_now())
	player.set_physics_process(true)

	# 长夜：影长上限抬升
	player._lantern_pos = player.global_position + Vector2(0.0, -250.0)
	var base_len: float = player._shadow_len()
	player._shadow_cast_longnight(Vector2.UP)
	await _wait(0.05)
	_check(player._shadow_len() > base_len, "长夜把影长顶到新上限",
		"%.0f -> %.0f" % [base_len, player._shadow_len()])
	_check(player._shadow_long_left > 0.0, "长夜有持续时间")
	# ===== E：长夜升格为这组的射程窗口 =====
	var ln_form: Dictionary = MoveDB.resolve_player("form_shadow_longnight")
	_check(is_equal_approx(float(ln_form.get("cooldown", 0.0)), 20.0),
			"长夜 CD 32 → 20 秒", "cd=%.1f" % float(ln_form.get("cooldown", 0.0)))
	_check(is_equal_approx(float(ln_form.get("mana_cost", 0.0)), 24.0),
			"长夜灵力 34 → 24", "mana=%.0f" % float(ln_form.get("mana_cost", 0.0)))
	_check(is_equal_approx(SkillDB.SHADOW_LONGNIGHT_SECONDS, 10.0),
			"长夜持续 8 → 10 秒", "t=%.1f" % SkillDB.SHADOW_LONGNIGHT_SECONDS)
	# 上面那次长夜还挂在表上（10 秒没走完），先清零才叫「非长夜」
	player._shadow_long_left = 0.0
	_check(is_equal_approx(player._shadow_width_mult(), 1.0),
			"非长夜时走廊不加宽")
	player._shadow_long_left = 5.0
	_check(is_equal_approx(player._shadow_width_mult(),
			SkillDB.SHADOW_LONGNIGHT_WIDTH_MULT),
			"长夜期间影技走廊 ×%.2f" % SkillDB.SHADOW_LONGNIGHT_WIDTH_MULT)
	# 削影双段：影长不够 150 时，长夜里仍然补影尖那一刀
	# ⚠ 物理冻结 + 灯笼状态归零：上面那次长夜把灯笼甩到 620 外，它按 430px/s 追回来，
	#   影长就变成「这段 await 里过了几帧」的函数 —— 判据会偶发飘红（踩过）。
	player.set_physics_process(false)
	player._shadow_long_left = 0.0
	player._shadow_snap_left = 0.0
	player._lantern_pos = player.global_position
	player._lantern_lag_want = 0.0
	player._lantern_speed_avg = 0.0
	boss.global_position = player.global_position + Vector2(150.0, 0.0)
	boss.current_hp = boss.max_hp
	_check(player._shadow_len() < SkillDB.SHADOW_CUT_TIP_EXTRA,
			"前置条件成立：这一帧影长确实不够双段", "%.0f" % player._shadow_len())
	var hp_single: float = boss.current_hp
	player._shadow_after_cast("skill_shadow_cut", {}, Vector2.RIGHT)
	_check(is_equal_approx(boss.current_hp, hp_single),
			"影长不足又没开长夜：削影只有单段")
	player._shadow_long_left = 5.0
	player._shadow_after_cast("skill_shadow_cut", {}, Vector2.RIGHT)
	_check(boss.current_hp < hp_single,
			"长夜期间削影必定双段", "%.0f -> %.0f" % [hp_single, boss.current_hp])
	player._shadow_long_left = 0.0
	player.set_physics_process(true)

	# 被动：完美闪避拉满影长
	player._shadow_long_left = 0.0
	player._shadow_passive_cd = 0.0
	player._lantern_pos = player.global_position
	player._shadow_passive_on_perfect_dodge()
	_check(player._shadow_passive_left > 0.0 and player._shadow_len() > 500.0,
		"被动「执灯」完美闪避后影长拉满", "%.0f" % player._shadow_len())
	player._shadow_reset()


func _content_check() -> void:
	var codex: Dictionary = CodexDB.BOSS_CODEX.get("boss_04_b", {})
	_check(not codex.is_empty(), "BOSS 图鉴已登记")
	# 蚀是**元素规则**、不在任何 form 的 debuff_on_hit 里，所以它只能靠 status_extra 进图鉴。
	# 漏登记的话玩家会在 HUD 看到一个从没解释过的状态名 —— 这条守卫就是防这个。
	var statuses := CodexDB.boss_status_info("boss_04_b")
	var erosion_seen := false
	for row in statuses:
		if String((row as Dictionary).get("id", "")) == AttributeDB.DARK_EROSION_ID:
			erosion_seen = true
			_check(String((row as Dictionary).get("effect", "")).contains("治疗"),
					"图鉴里蚀说清了减疗那半条（不只是穿抗）",
					String((row as Dictionary).get("effect", "")))
	_check(erosion_seen, "蚀已进图鉴负面清单", str(statuses.size()) + " 条")
	_check(String(codex.get("mechanic_title", "")) == "投影 · 身外之影", "图鉴机制标题")
	_check(String(codex.get("subtitle", "")).contains("第二关"), "图鉴显示照影界第二关",
		String(codex.get("subtitle", "")))
	# 2026-11-02 文案改版：正文只留三句话，细节挪到要点行 —— 玩家两张都会读，
	# 所以判据要看「整块机制文案」而不是只盯正文那一段
	var mech := String(codex.get("mechanic", ""))
	for x in (codex.get("mechanic_points", []) as Array):
		mech += "\n" + String(x)
	_check(mech.contains("界灯") and mech.contains("影身"), "图鉴讲清唯一光源与影身")
	_check("首战可破" in mech or "不需要任何执烛功法" in mech, "图鉴写明首战空手可破")
	_check(not mech.contains("势条") or mech.contains("没有势条"), "图鉴没引入新势条")
	_check(codex.get("mechanic_points") is Array \
			and (codex.get("mechanic_points") as Array).size() >= 8,
		"机制要点分条列清", str((codex.get("mechanic_points") as Array).size()))
	_check(String(codex.get("status_note", "")).contains("影缚"), "影缚 / 影没在状态说明里")
	_check(CodexDB.INK_NOTES.has("boss_04_b"), "卡包水墨条目已登记")
	_check(CodexDB.HOLO_CARDS.has("boss_04_b"), "卡包华彩四张已登记")
	var sources := ""
	for k in ["mat_zhaoying_zhulei", "soul_zhizhu", "tr_zhizhu_ling",
			"eq_changye_ren", "eq_zhului_zhui"]:
		var s := CodexDB.source_for(String(k))
		_check(s != "" and not s.contains("待补充"), "获取方式已登记 " + String(k), s)
		sources += s
	# 物品与掉落
	_check(not ItemDB.get_material("mat_zhaoying_zhulei").is_empty(), "位面材料「照影烛泪」已登记")
	var drops: Array = ItemDB.get_drops_for_boss("boss_04_b")
	_check(drops.size() == 3, "执烛掉落三件（武器 / 饰品 / 位面材料）", str(drops.size()))
	var mat_chance := 0.0
	for d in drops:
		if String((d as Dictionary).get("item_id", "")) == "mat_zhaoying_zhulei":
			mat_chance = float((d as Dictionary).get("chance", 0.0))
	_check(is_equal_approx(mat_chance, 0.2), "位面材料 20% 掉率（与观澜同口径）")
	_check(not ItemDB.get_treasure_template("tr_zhizhu_ling").is_empty(), "执烛令已登记")
	_check(String(ItemDB.get_treasure_template("tr_zhizhu_ling").get("summon_boss_id", ""))
			== "boss_04_b", "执烛令召唤的是执烛")
	_check(not ItemDB.get_synth_recipe_by_soul("soul_zhizhu").is_empty(), "执烛令配方已接合成台")
	var wep := ItemDB.get_equipment_template("eq_changye_ren")
	var acc := ItemDB.get_equipment_template("eq_zhului_zhui")
	_check(String(wep.get("equipment_type", "")) == "weapon" \
			and wep.get("attributes", {}).has(AttributeDB.ATTR_STRENGTH),
		"长夜刃是元婴物理向武器（补观澜只给法系的缺口）")
	_check(acc.get("attributes", {}).has("resist_thunder"),
		"烛泪坠补雷抗（全套装备此前没有雷抗来源）")
	# 战场映射与字印
	var board: Dictionary = preload("res://scripts/ui/facility/domain_boss_board.gd").SIGILS
	_check(String(board.get("boss_04_b", {}).get("glyph", "")) == "烛", "选关字印 = 烛",
		str(board.get("boss_04_b", {})))
	var arena_src := FileAccess.get_file_as_string("res://scripts/combat/combat_arena.gd")
	_check(arena_src.contains("\"boss_04_b\""), "执烛战场映射已接进 CombatArena")
	# 素材落地（洋红键色生成 / 替代素材都要有文件）
	for p in ["res://assets/characters/boss/boss_zhizhu.png",
			"res://assets/characters/boss/zhizhu_rig/rig.tres",
			"res://assets/characters/boss/zhizhu_rig/body.png",
			"res://assets/characters/boss/zhizhu_rig/lantern.png",
			"res://assets/scenes/zhaoying_lamp_arena_ground.png",
			"res://assets/effects/skills/lamp_seal.png",
			"res://assets/ui/codex/card_boss_zhizhu.png",
			"res://assets/ui/codex/holo/boss_04_b_art.png",
			"res://assets/ui/codex/holo/boss_04_b_bg.png",
			"res://assets/ui/codex/holo/boss_04_b_lines.png"]:
		_check(ResourceLoader.exists(String(p)) or FileAccess.file_exists(String(p)),
			"素材已落地 " + String(p).get_file())
	for sid in SKILLS:
		var ip := "res://assets/ui/icon/%s.png" % String(sid)
		_check(FileAccess.file_exists(ip), "功法图标已落地 " + String(sid))
	for ip in ["res://assets/ui/icon/mat_zhaoying_zhulei.png",
			"res://assets/ui/icon/soul_zhizhu.png",
			"res://assets/ui/icon/tr_zhizhu_ling.png",
			"res://assets/ui/icon/equip_changye_ren.png",
			"res://assets/ui/icon/equip_zhului_zhui.png"]:
		_check(FileAccess.file_exists(String(ip)), "物品图标已落地 " + String(ip).get_file())
	var vis := ArtDB.get_visual("boss_zhizhu")
	_check(not vis.is_empty() and String(vis.get("rig", "")) != "", "ArtDB 已登记 boss_zhizhu")
	var bg := ArtDB.get_visual("bg_zhaoying_lamp_arena")
	_check(not bg.is_empty(), "执烛战场地面已登记")
	for fid in FORMS:
		var sid2 := SkillDB.get_skill_id_by_form(String(fid))
		_check(not ArtDB.get_skill_fx(sid2).is_empty(), "特效族已登记 " + sid2)
		_check(String(ArtDB.get_skill_fx(sid2).get("family", "")) == "shadow",
			"影族统一 family " + sid2)
	var anim_map: Dictionary = preload("res://scripts/data/art_db.gd").BOSS_MOVE_ANIMS.get("boss_zhizhu", {})
	_check(anim_map.size() == 8, "rig 动作表登记八式", str(anim_map.size()))
	# 影族特效必须真的能画出来（不能是通用 slash 兜底）
	var fx_src := FileAccess.get_file_as_string("res://scripts/visual/skill_fx.gd")
	_check(fx_src.contains("func _build_shadow()"), "skill_fx 里有影族绘制分支")
	_check(fx_src.contains("\"shadow\":\n\t\t\t_build_shadow()") \
			or fx_src.contains("_build_shadow()"), "motif=shadow 接到 _build_shadow")


func _wear_baseline(stage: int, enh: int) -> void:
	const ENH_AVG := {
		"strength": 1.5, "spell_power": 1.0, "hp_max": 3.0,
		"physical_resist": 1.0, "magic_resist": 1.0, "mana_max": 3.0,
		"mana_regen": 0.75, "speed_pct": 0.3, "attack_speed": 1.0,
		"spell_skill_damage_pct": 0.75, "stamina_regen_pct": 0.75,
	}
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = stage
	for slot in CharacterData.SLOT_ORDER:
		CharacterData.equipment_slots[slot] = null
	var gear := ["eq_qingfengjian", "eq_jinwen_zhanpao", "eq_zhuri_lv",
		"eq_liangyi_yujue", "eq_qihai_yuzhui", "eq_leiwen_huqi"]
	var slots := ["weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3"]
	for i in gear.size():
		var tpl := ItemDB.get_equipment_template(String(gear[i]))
		var it := CharacterData.make_equipment_instance(tpl)
		var asc := maxi(0, ItemDB.grade_index("道器") - ItemDB.grade_index(String(it.get("equipment_grade", ""))))
		var attrs: Dictionary = {}
		var base = it.get("attributes_base", {})
		for k in base.keys():
			attrs[String(k)] = float(base[k])
		for j in asc:
			for k in attrs.keys():
				attrs[k] = float(attrs[k]) * 1.5
		for k in attrs.keys():
			if ENH_AVG.has(k):
				attrs[k] = float(attrs[k]) + float(ENH_AVG[k]) * float(enh)
		it["attributes"] = attrs
		it["equipment_grade"] = "道器"
		it["enhancement_level"] = enh
		CharacterData.equipment_slots[String(slots[i])] = it


## 影族特效的"柔边"判据（2026-11-04 用户报「还是硬边色块」）
## 三条都是撤掉修复就会红的：
## ① 光带贴图纵向 10%→90% 的过渡宽度（原来用的 4×4 纯白图 = 0，一条垂直一刀）；
## ② 芯宽（FWHM）占全高的比例 —— `_soft_bar` 把 thickness 定义成"看得见的芯"，
##    折算系数写错的话芯会细到 1.3px，看着像"特效没做"；
## ③ 播一式之后，整棵子树里**不许**还有用纯白图拉的 Sprite2D。
func _check_soft_edges() -> void:
	var tex: Texture2D = SkillFx.lightbar_texture()
	_check(tex != null, "影族柔光条贴图已生成")
	if tex == null:
		return
	var img: Image = tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var col: Array = []
	for y in img.get_height():
		col.append(img.get_pixel(img.get_width() / 2, y).a)
	var peak := 0.0
	for v in col:
		peak = maxf(peak, float(v))
	var lo := -1
	var hi := -1
	var core := 0
	for y in img.get_height():
		var v := float(col[y])
		if lo < 0 and v >= peak * 0.10:
			lo = y
		if v >= peak * 0.50:
			core += 1
		if v >= peak * 0.90:
			hi = y
	var feather := float(absi(hi - lo))
	_check(feather >= 12.0,
			"光带边缘是羽化的（10→90 过渡 ≥12 原生 px），不是硬边一刀",
			"过渡=%.1fpx 芯=%d/%d=%.0f%%" % [feather, core, img.get_height(),
					core * 100.0 / img.get_height()])
	_check(core * 100.0 / img.get_height() > 18.0 and core * 100.0 / img.get_height() < 32.0,
			"芯宽（FWHM）占全高 18~32%% —— _soft_bar 的 thickness 折算与贴图一致",
			"实测 %.1f%%" % (core * 100.0 / img.get_height()))
	# ⚠ 遍历要拿 `play_at_strike` **返回的那个 SkillFx 节点**往下走：
	#   它挂在 caster 的父节点上，而 Sprite 全在 SkillFx 自己的子树里。
	#   前两版分别栽在"遍历 caster"和"遍历容器"上，都数到 0 个 → 假绿。
	var host := Node2D.new()
	add_child(host)
	var caster := Node2D.new()
	host.add_child(caster)
	var made: Array = []
	for id in ["skill_shadow_beam", "skill_shadow_reach", "skill_shadow_step",
			"skill_shadow_longnight"]:
		var fx := SkillFx.play_at_strike(caster, id, {"range": 300.0, "width": 62.0,
				"hit_shape": MoveDB.SHAPE_LINE}, Vector2.RIGHT)
		if fx != null:
			made.append(fx)
	await get_tree().process_frame
	await get_tree().process_frame
	var white: Texture2D = SkillFx.white_texture()
	var hard := 0
	var sprites := 0
	for fxn in made:
		if not is_instance_valid(fxn):
			continue
		for n in (fxn as Node).get_children(true):
			var sp := n as Sprite2D
			if sp == null:
				continue
			sprites += 1
			if sp.texture != null and sp.texture == white:
				hard += 1
	# 下限：先证明"确实画出了东西"，上面那条 0 才有意义
	_check(sprites >= 12, "影族四式确实播出了精灵（判据不是空跑）", "%d 个 Sprite2D" % sprites)
	_check(hard == 0, "影族四式播完，子树里没有任何用纯白图拉的硬边方块",
			"找到 %d 个" % hard)
	host.free()
