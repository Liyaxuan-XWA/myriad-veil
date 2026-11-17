extends Node2D
## 赫连霄 / 判词·天律 全链路自检（2026-10-29）
## 覆盖：数据 / 玩家八式 / 判词四条 / 雷势 / 守律顺天 / BOSS 侧立律与违律 / 抗辩 / 二阶段双律。

class StubPlayer extends Node2D:
	var is_dodging := false
	var is_teleporting := false
	var is_dead := false
	var knockback_velocity := Vector2.ZERO
	var debuffs: Dictionary = {}
	var buffs: Dictionary = {}
	var hits: Array = []
	var shunted := 0
	func take_damage(amount: float, _kind: String = "physical", _source: Node = null,
			_elem: String = "") -> void:
		hits.append(amount)
	func apply_debuff(id: String, duration: float, _quiet := false) -> bool:
		debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
		return true
	func clear_debuff(id: String) -> void:
		debuffs.erase(id)
	func apply_shuntian(sec: float) -> void:
		shunted += 1
		buffs["shuntian"] = sec
	func head_top_y() -> float:
		return -110.0

class DummyBoss extends Node2D:
	var state := 0
	var is_dead := false
	var velocity := Vector2.ZERO
	var hits: Array = []
	var debuffs: Dictionary = {}
	var staggers: Array = []
	var lei_kept := 0
	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			_elem: String = "", _proj: bool = false) -> void:
		hits.append(amount)
	func apply_debuff(id: String, duration: float) -> bool:
		debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
		return true
	func remove_debuff(id: String) -> void:
		debuffs.erase(id)
	func stagger_for(sec: float) -> void:
		staggers.append(sec)
	func on_player_law_kept() -> void:
		lei_kept += 1
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
	print("\n########## 赫连霄 · 判词天律 探针 ##########")
	await get_tree().process_frame
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	_test_data()
	await _test_player_side()
	await _test_boss_side()


func _test_data() -> void:
	var forms := ["form_thunder_verdict", "form_thunder_execute", "form_thunder_drum",
		"form_thunder_lock", "form_thunder_step", "form_thunder_gather",
		"form_thunder_nine", "form_thunder_prison"]
	for f in forms:
		_check(MoveDB.has_form(String(f)), "形态已登记 " + String(f))
		var b := MoveDB.resolve_boss(String(f))
		var p := MoveDB.resolve_player(String(f))
		_check(not b.is_empty(), "BOSS 侧可解析 " + String(f))
		_check(not p.is_empty(), "玩家侧可解析 " + String(f))
	var ids := ["skill_thunder_verdict", "skill_thunder_execute", "skill_thunder_drum",
		"skill_thunder_lock", "skill_thunder_step", "skill_thunder_gather",
		"skill_thunder_nine", "skill_thunder_prison"]
	for sid in ids:
		var sk := SkillDB.get_skill(String(sid))
		_check(not sk.is_empty(), "功法已登记 " + String(sid))
		_check(bool(sk.get("thunder", false)), "功法带 thunder 标记 " + String(sid))
		var lines := SkillDB.get_effect_lines(String(sid))
		_check(lines.size() >= 3, "功法效果行 >=3 " + String(sid), "n=%d" % lines.size())
	_check(WorldDB.get_domain_name("domain_03") == "赤霄界", "位面 03 定名赤霄界")
	_check(WorldDB.get_boss_name("boss_03") == "赫连霄", "boss_03 定名赫连霄")
	_check(WorldDB.get_boss_scene("boss_03").ends_with("domain_boss_03.tscn"), "BOSS 场景已登记")
	_check(not WorldDB.get_boss_moves("boss_03").is_empty(), "BOSS 招式组已登记")
	_check(WorldDB.get_floor(7).get("boss_id", "") == "boss_03", "塔第 7 层 = 赫连霄")
	var codex := CodexDB.boss_entry("boss_03")
	_check(not codex.is_empty(), "图鉴卡已登记")
	_check((codex.get("mechanic_points", []) as Array).size() >= 4, "图鉴机制要点 >=4")
	var states := CodexDB.boss_status_info("boss_03")
	_check(states.size() >= 6, "图鉴状态含判词四条 + 滞雷 + 眩晕", "n=%d" % states.size())
	_check(not ItemDB.get_drops_for_boss("boss_03").is_empty(), "掉落表已登记")
	_check(not ItemDB.get_equipment_template("eq_leiwen_huqi").is_empty(), "雷纹护臂已登记")
	_check(not ItemDB.get_equipment_template("eq_panguan_tiebi").is_empty(), "判官铁笔已登记")
	_check(not ItemDB.get_material("mat_chixiao_leijing").is_empty(), "赤霄雷晶已登记")
	_check(not ItemDB.get_material("soul_helianxiao").is_empty(), "赫连霄元魂已登记")
	_check(not ItemDB.get_treasure_template("tr_panguan_ling").is_empty(), "判官令已登记")
	_check(not ItemDB.get_synth_recipe_by_soul("soul_helianxiao").is_empty(), "判官令合成配方已登记")
	_check(SkillDB.get_group_rules("boss_03").get("title", "").contains("判词"), "功法库组规则卡已挂")
	_check(DebuffDB.get_debuff("thunder_stagnation").get("dodge_mult", 1.0) < 1.0, "滞雷有闪避距离乘区")
	_check(not BuffDB.get_buff("shuntian").is_empty(), "顺天 buff 已登记")
	_check(WorldDB.get_floor_reward_skills(7).size() == 9, "塔 7 层感悟池 = 9 门（八式 + 被动）",
		"n=%d" % WorldDB.get_floor_reward_skills(7).size())
	_check(CodexDB.boss_learn_info("boss_03").size() == 9, "图鉴可感悟功法 = 9 门",
		"n=%d" % CodexDB.boss_learn_info("boss_03").size())
	_check(ResourceLoader.exists(String(CodexDB.boss_entry("boss_03").get("portrait", ""))),
		"图鉴卡原画存在")
	_check(ResourceLoader.exists(String(ArtDB.get_visual("bg_chixiao_arena").get("texture", ""))),
		"赤霄界战场地面存在")
	_check(ResourceLoader.exists(String(ArtDB.get_visual("boss_heiliao").get("rig", ""))),
		"赫连霄 rig 存在")
	_check(ItemDB.get_drops_for_boss("boss_03").size() == 3, "掉落表 2 装备 + 1 材料")
	var boss_drop_ids := ItemDB.get_boss_equipment_ids("boss_03")
	_check("eq_leiwen_huqi" in boss_drop_ids and "eq_panguan_tiebi" in boss_drop_ids,
		"判官装备 2 件", str(boss_drop_ids))
	_check(not ItemDB.get_synth_recipe_for_equipment("eq_leiwen_huqi").is_empty(),
		"雷纹护臂可熔铸判官令")
	var groups := SkillDB.get_library_groups()
	var found_group := false
	for g in groups:
		if String((g as Dictionary).get("group_id", "")) == "boss_03":
			found_group = true
			_check(int((g as Dictionary).get("total", 0)) == 9, "功法库赫连霄组 9 门",
				"n=%d" % int((g as Dictionary).get("total", 0)))
	_check(found_group, "功法库出现赫连霄分组")
	var codex_bosses := CodexDB.boss_entries()
	var found_boss := false
	for e in codex_bosses:
		if String((e as Dictionary).get("id", "")) == "boss_03":
			found_boss = true
	_check(found_boss, "图鉴 BOSS 列表出现赫连霄")
	## 层数断言写成「≥10」而不是「==10」：每落地一只新 BOSS 就多加一层，
	## 写死数字会让这个探针在跟赫连霄毫无关系的改动上变红（执烛 / 叠纸 落地后就误报过一次）。
	var floors: Array = WorldDB.get_floors()
	_check(floors.size() >= 10, "万界塔已扩到含照影界首位（≥10 层）", "n=%d" % floors.size())
	var f7 := ""
	for f in floors:
		if int((f as Dictionary).get("floor", 0)) == 7:
			f7 = String((f as Dictionary).get("boss_id", ""))
	_check(f7 == "boss_03", "塔 7 层仍是赫连霄本人", "boss_id=%s" % f7)
	# 位面 03 首杀结算：500 修为 + 击杀记录
	CharacterData.current_realm = "结丹"
	CharacterData.realm_stage = 0
	CharacterData.realm_exp = 0
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03",
	}
	var res := BattleResolver.resolve_victory()
	_check(String(res.get("message", "")).contains("修为 +500"),
		"位面 03 首杀给 500 修为", String(res.get("message", "")))
	_check(bool((CharacterData.boss_progress.get("boss_03", {}) as Dictionary).get("killed", false)),
		"位面 03 记录击杀")
	GameState.battle_context = {}


func _test_player_side() -> void:
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector2.ZERO
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	var ids := ["skill_thunder_verdict", "skill_thunder_execute", "skill_thunder_drum",
		"skill_thunder_lock", "skill_thunder_step", "skill_thunder_gather",
		"skill_thunder_nine", "skill_thunder_prison"]
	for sid in ids:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	p._refresh_thunder_unlock()
	_check(bool(p._thunder_unlocked), "学会判官功法后雷势条解锁")
	_check(p._thunder_pips != null and is_instance_valid(p._thunder_pips), "雷势 HUD 已创建")
	_check(p._verdict_banner != null and is_instance_valid(p._verdict_banner), "判词横幅已创建")
	_check(p._thunder_pips != null and bool(p._thunder_pips.visible), "雷势条已显示")
	# 2026-10-30 用户定：只学会、不带在身上 = 没有涨雷势的手段 → 整条隐藏
	var held: Array = []
	for sid in CharacterData.active_skill_loadout.duplicate():
		if bool(SkillDB.get_skill(String(sid)).get("thunder", false)):
			held.append(sid)
			CharacterData.active_skill_loadout.erase(sid)
	p._refresh_thunder_unlock()
	p._refresh_thunder_hud()
	_check(not p._thunder_unlocked and not bool(p._thunder_pips.visible),
		"不带雷功法 → 雷势条隐藏")
	for sid in held:
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	p._refresh_thunder_unlock()
	p._refresh_thunder_hud()
	_check(p._thunder_unlocked and bool(p._thunder_pips.visible),
		"重新带上雷功法 → 雷势条恢复")
	p.apply_debuff("verdict_no_move", 3.0, true)
	p._tick_thunder_banner()
	_check(bool(p._verdict_banner.visible), "有判词时横幅显示")
	p.clear_debuff("verdict_no_move")
	p._tick_thunder_banner()
	_check(not bool(p._verdict_banner.visible), "无判词时横幅整条隐藏")

	var b := DummyBoss.new()
	b.add_to_group("boss")
	b.global_position = Vector2(200.0, 0.0)
	add_child(b)

	# 选律：目标最近闪避过 → 禁避
	p._boss_dash_recent = 1.0
	p._boss_attack_recent = 0.0
	p._boss_move_recent = 0.0
	_check(p._choose_player_law() == "verdict_no_dodge", "选律：闪避 → 禁避")
	p._boss_dash_recent = 0.0
	p._boss_attack_recent = 1.0
	_check(p._choose_player_law() == "verdict_no_attack", "选律：出手 → 禁攻")
	p._boss_attack_recent = 0.0
	p._boss_move_recent = 1.0
	_check(p._choose_player_law() == "verdict_no_move", "选律：移动 → 禁行")
	p._boss_move_recent = 0.0
	_check(p._choose_player_law() == "verdict_no_still", "选律：站定 → 禁立")

	# 判词落地
	b.debuffs.clear()
	p._pending_player_law = "verdict_no_move"
	p._thunder_handle_cast("skill_thunder_verdict", Vector2.RIGHT)
	_check(p._law_id == "verdict_no_move", "第一条判词落到目标身上", p._law_id)
	_check(p._law2_id != "" and p._law2_id != p._law_id, "第二条判词也落到目标身上",
		p._law2_id)
	_check(b.debuffs.has("verdict_no_move") and b.debuffs.has(p._law2_id),
		"目标同时挂两条判词 debuff", str(b.debuffs.keys()))
	_check(is_instance_valid(p._law_mark), "目标头顶判词印已创建")
	_check(p._law_mark_label2 != null and is_instance_valid(p._law_mark_label2),
		"第二条判词的头顶标签已创建")

	# 禁行：移动 110 → 违律 + 雷势
	b.hits.clear()
	p.lei_shi = 0
	p._law_cd = 0.0
	var start: Vector2 = b.global_position
	for i in range(12):
		b.global_position = start + Vector2(10.0 * float(i + 1), 0.0)
		p._tick_thunder_law(0.01)
	await get_tree().create_timer(0.32).timeout
	_check(p.lei_shi == 1, "禁行违律 +1 雷势", "lei=%d" % p.lei_shi)
	_check(b.hits.size() >= 1, "违律落雷造成伤害", "hits=%d" % b.hits.size())

	# 禁攻：目标进入 ATTACK 状态 → 违律
	p._apply_player_law(b, "verdict_no_attack")
	p.lei_shi = 0
	p._law_cd = 0.0
	b.state = 2
	p._tick_thunder_law(0.01)
	b.state = 3
	p._tick_thunder_law(0.01)
	_check(p.lei_shi >= 1, "禁攻：目标出手 → 违律", "lei=%d" % p.lei_shi)

	# 禁避：目标 0.2 秒位移 140 → 违律
	p._apply_player_law(b, "verdict_no_dodge")
	p.lei_shi = 0
	p._law_cd = 0.0
	b.global_position = Vector2(200.0, 0.0)
	p._tick_thunder_law(0.01)
	b.global_position = Vector2(400.0, 0.0)
	p._tick_thunder_law(0.11)
	p._tick_thunder_law(0.11)
	_check(p.lei_shi >= 1, "禁避：目标位移 → 违律", "lei=%d" % p.lei_shi)

	# 禁立：目标 1 秒不动 → 违律
	p._apply_player_law(b, "verdict_no_still")
	p.lei_shi = 0
	p._law_cd = 0.0
	for i in range(70):
		p._tick_thunder_law(0.02)
	_check(p.lei_shi >= 1, "禁立：目标站定 → 违律", "lei=%d" % p.lei_shi)

	# 守律：两条判词零违律走完 → 顺天 + 对手雷势 -1
	p._law_target = b
	p._law_id = "verdict_no_move"
	p._law2_id = "verdict_no_attack"
	p._law_left = 0.0
	p._law2_left = 0.0
	p._law_violations = 0
	p._law2_violations = 0
	b.lei_kept = 0
	p.remove_buff("shuntian")
	p._tick_buffs(0.01)
	p._expire_player_laws()
	_check(p.has_buff("shuntian"), "守律走完获得顺天")
	_check(b.lei_kept == 1, "守律削对手一层雷势", "kept=%d" % b.lei_kept)
	p.remove_buff("shuntian")
	p._tick_buffs(0.01)

	# 九霄：消耗全部雷势
	p.lei_shi = 3
	p._refresh_thunder_hud()
	b.hits.clear()
	var form9 := SkillDB.get_skill_form("skill_thunder_nine")
	p._cast_thunder_nine(form9)
	_check(p.lei_shi == 0, "九霄消耗全部雷势")
	await get_tree().create_timer(0.55).timeout
	_check(b.hits.size() >= 1, "九霄雷柱命中目标", "hits=%d" % b.hits.size())

	# 聚雷：完成 +1 雷势
	p.lei_shi = 0
	b.global_position = Vector2(200.0, 0.0)
	var formG := SkillDB.get_skill_form("skill_thunder_gather")
	p._cast_thunder_gather(formG, Vector2.RIGHT)
	for i in range(70):
		p._tick_thunder_channel(0.02)
	_check(p.lei_shi == 1, "聚雷完成 +1 雷势", "lei=%d" % p.lei_shi)

	# 定刑：带判词 +50%（只验证出伤与延迟）
	p._apply_player_law(b, "verdict_no_move")
	b.hits.clear()
	var formE := SkillDB.get_skill_form("skill_thunder_execute")
	p._cast_thunder_execute(formE)
	await get_tree().create_timer(0.55).timeout
	_check(b.hits.size() >= 1, "定刑延迟落雷命中", "hits=%d" % b.hits.size())

	# 雷牢：收拢命中 → 硬直
	b.global_position = Vector2(200.0, 0.0)
	b.staggers.clear()
	var formP := SkillDB.get_skill_form("skill_thunder_prison")
	p._cast_thunder_prison(formP)
	await get_tree().create_timer(1.35).timeout
	_check(b.staggers.size() >= 1, "雷牢收拢命中 → 硬直", str(b.staggers))

	# 顺天 + 滞雷
	p.apply_shuntian(6.0)
	_check(p.has_buff("shuntian"), "顺天 buff 已挂")
	_check(CharacterData.attribute_mods.has("shuntian"), "顺天属性修正已写入")
	p.apply_debuff("thunder_stagnation", 3.0, true)
	_check(p._dodge_distance_mult() < 1.0, "滞雷缩短闪避距离",
		"mult=%.2f" % p._dodge_distance_mult())
	p.debuffs.erase("verdict_no_move")
	p.remove_buff("shuntian")
	p._tick_buffs(0.01)
	_check(not CharacterData.attribute_mods.has("shuntian"), "顺天到期撤掉属性修正")

	# ===== try_use_skill 端到端（消耗 / 冷却 / 前摇 / 命中）=====
	p.mana = 999.0
	p.stamina = 5
	p.skill_cooldowns.clear()
	b.debuffs.clear()
	b.hits.clear()
	b.global_position = Vector2(200.0, 0.0)
	var ok_exec: bool = bool(p.try_use_skill("skill_thunder_execute"))
	_check(ok_exec, "try_use_skill 定刑成功")
	await get_tree().create_timer(0.75, true, false, true).timeout
	_check(b.hits.size() >= 1, "try_use_skill 定刑延迟命中", "hits=%d" % b.hits.size())

	p.skill_cooldowns.clear()
	p._pending_player_law = ""
	b.debuffs.clear()
	var ok_law: bool = bool(p.try_use_skill("skill_thunder_verdict"))
	_check(ok_law, "try_use_skill 判词成功")
	await get_tree().create_timer(0.55, true, false, true).timeout
	_check(b.debuffs.size() >= 1, "try_use_skill 判词落到目标", str(b.debuffs.keys()))

	p.skill_cooldowns.clear()
	p.lei_shi = 3
	var ok_full: bool = bool(p.try_use_skill("skill_thunder_gather"))
	_check(not ok_full, "雷势满时聚雷被门槛拦下")
	p.lei_shi = 0
	p.skill_cooldowns.clear()
	var ok_gather: bool = bool(p.try_use_skill("skill_thunder_gather"))
	_check(ok_gather, "雷势未满时聚雷可放")

	p.queue_free()
	await get_tree().process_frame


func _test_boss_side() -> void:
	var sp := StubPlayer.new()
	sp.add_to_group("player")
	sp.global_position = Vector2(120.0, 0.0)
	add_child(sp)
	var boss = (load("res://scenes/boss/domain_boss_03.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.global_position = Vector2.ZERO
	boss._update_threat_target(true)
	boss.target = sp
	_check(is_equal_approx(boss.max_hp, 13000.0), "BOSS 血量按结丹标准档反推", "hp=%.0f" % boss.max_hp)
	_check(is_equal_approx(boss.attack_power, 90.0), "BOSS 攻击力按结丹标准档反推", "atk=%.0f" % boss.attack_power)
	var gather_boss := MoveDB.resolve_boss("form_thunder_gather")
	var break_need: float = float(boss.max_hp) * float(gather_boss.get("channel_break_damage", 1.0))
	_check(break_need <= 350.0, "聚雷打断门槛可被标准档 1.4 秒普攻打破", "需 %.0f 伤害" % break_need)
	_check(boss._pips != null and is_instance_valid(boss._pips), "BOSS 雷势三印已创建")
	var skin = boss.get_node_or_null("Visual/Skin")
	var rig_node = skin.render_node if skin != null else null
	_check(rig_node is BossRig, "骨骼已由 rig.tres 构建")
	if rig_node is BossRig:
		var ap = rig_node.get_node_or_null("Anim")
		_check(ap != null, "骨骼 AnimationPlayer 已创建")
		if ap != null:
			var names := (ap as AnimationPlayer).get_animation_list()
			for need in ["idle", "walk", "verdict", "execute", "drum", "lock", "step", "gather", "nine", "prison"]:
				_check(need in names, "骨骼动画存在 " + String(need))

	# 立律：直接出手（跳过前摇）
	sp.debuffs.clear()
	boss._pending_laws = ["verdict_no_move", "verdict_no_attack"]
	boss._current_skill = DomainBoss03.F_VERDICT
	boss._verdict_cancelled = false
	boss._cast_verdict(MoveDB.resolve_boss(DomainBoss03.F_VERDICT))
	_check(sp.debuffs.has("verdict_no_move") and sp.debuffs.has("verdict_no_attack"),
		"BOSS 立双律到玩家身上", str(sp.debuffs.keys()))
	_check(boss._verdicts.size() == 2, "BOSS 内部记录两条律", "n=%d" % boss._verdicts.size())

	# 违律：玩家移动 110 → 雷势 +1
	boss._lei_shi = 0
	boss._move_accum = 0.0
	var start: Vector2 = sp.global_position
	for i in range(12):
		sp.global_position = start + Vector2(10.0 * float(i + 1), 0.0)
		boss._tick_watch(0.01)
		boss._tick_verdicts(0.01)
	await get_tree().create_timer(0.32).timeout
	_check(boss._lei_shi >= 1, "BOSS 侧违律 → 雷势 +1", "lei=%d" % boss._lei_shi)
	_check(sp.hits.size() >= 1, "BOSS 侧违律落雷命中玩家", "hits=%d" % sp.hits.size())

	# 抗辩：弹反宣判 → 撤销 + 雷势 -1
	boss._verdicts.clear()
	boss._lei_shi = 2
	boss._pending_laws = ["verdict_no_move"]
	boss._current_skill = DomainBoss03.F_VERDICT
	var before: int = int(boss._lei_shi)
	boss.on_parried(sp)
	_check(bool(boss._verdict_cancelled), "弹反宣判 → 判词撤销标记")
	_check(boss._lei_shi == before - 1, "抗辩成功 → 雷势 -1", "lei=%d" % boss._lei_shi)

	# 守律：判词走完不违规 → 顺天 + 雷势 -1
	boss._verdicts.clear()
	boss._verdict_cancelled = false
	sp.debuffs.clear()
	sp.shunted = 0
	boss._lei_shi = 2
	boss._pending_laws = ["verdict_no_still"]
	boss._current_skill = DomainBoss03.F_VERDICT
	boss._cast_verdict(MoveDB.resolve_boss(DomainBoss03.F_VERDICT))
	sp.global_position = Vector2(800.0, 0.0)
	for i in range(60):
		sp.global_position += Vector2(2.0, 0.0)
		boss._tick_watch(0.1)
		boss._tick_verdicts(0.1)
	_check(sp.shunted >= 1, "守律 → 玩家获得顺天", "shunted=%d" % sp.shunted)
	_check(boss._lei_shi == 1, "守律 → BOSS 雷势 -1", "lei=%d" % boss._lei_shi)

	# 二阶段：双律
	boss._phase_two = true
	sp.debuffs.clear()
	boss._verdicts.clear()
	boss._pending_laws = boss._choose_laws()
	_check(boss._pending_laws.size() == 2, "二阶段选律 → 双律", str(boss._pending_laws))
	boss._current_skill = DomainBoss03.F_VERDICT
	boss._cast_verdict(MoveDB.resolve_boss(DomainBoss03.F_VERDICT))
	_check(boss._verdicts.size() >= 1, "二阶段宣判仍能落律", "n=%d" % boss._verdicts.size())
	# 友军召唤（判官令）：判词要落在它的 target（敌方 BOSS），不是玩家
	boss.is_ally = true
	boss.target = sp
	sp.debuffs.clear()
	boss._verdicts.clear()
	boss._pending_laws = ["verdict_no_move"]
	boss._current_skill = DomainBoss03.F_VERDICT
	boss._cast_verdict(MoveDB.resolve_boss(DomainBoss03.F_VERDICT))
	_check(sp.debuffs.has("verdict_no_move"), "友军召唤：判词落在 target 上")
	boss.is_ally = false
	# ===== 自主模拟：让 BOSS 自己打 9 秒，确认选招 / 出招 / FX 全链路 =====
	boss.current_hp = boss.max_hp
	boss.state = 0
	boss.state_timer = 0.0
	boss._current_skill = ""
	boss._cools.clear()
	boss._recent.clear()
	boss._verdicts.clear()
	boss._lei_shi = 0
	boss._phase_two = false
	sp.global_position = Vector2(220.0, 0.0)
	boss.global_position = Vector2.ZERO
	boss.target = sp
	boss.set_physics_process(true)
	await get_tree().create_timer(9.0, true, false, true).timeout
	boss.set_physics_process(false)
	_check(boss._recent.size() >= 3, "BOSS 自主模拟出招 >= 3", str(boss._recent))
	boss.queue_free()
	sp.queue_free()
	await get_tree().process_frame
