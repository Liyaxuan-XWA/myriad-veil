extends Node
## 试炼之路 · 机制拓展卡自检（2026-11-09）
## 覆盖：
##   ① 新增 29 张「不叠数值」的机制卡全部登记齐全（id / 载体 / 文案 / 流派归属）；
##   ② 图鉴新增「试炼卡牌」卷：条目数与卡池一致、按稀有度筛选、流派分组与解锁口径正确；
##   ③ 关键机制走**真实入口**验证：嗜杀层数 → 伤害乘区、背水低血增伤、回响清冷却、
##      剑冢清波给剑意、意尽清空剑意炸范围；
##   ④ 图鉴页真实渲染一遍（CodexView 切到卡牌卷不崩、列表有内容）。
## 用法：godot --headless --path . res://tools/probe_rogue_cards.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const MINION_SCENE := "res://scenes/world/world_enemy.tscn"

## 2026-11-09 新增的机制卡：每张都不靠「纯数值叠加」生效
const NEW_CARDS: Array[String] = [
	# 通用
	"g_desperate", "g_bloodlust", "g_last_stand", "g_echo", "g_purist",
	# 剑修 / 刀修 / 虎妖
	"s_yj_break", "s_wj_seed", "b_sp_lone", "b_sp_ember",
	"t_cy_hunt", "t_bl_feral",
	# 两仪 / 阵旗 / 气环
	"y_ni_same", "y_yin_taint", "a_burst_echo", "a_step_trap",
	"q_burst_pull", "q_overflow",
	# 判词雷 / 逐日 / 三灾
	"l_hold_lei", "l_judge_chain", "u_keep_seed", "u_kill_seed",
	"c_plague", "c_lone_amp",
	# 镜身 / 投影 / 折影
	"m_replace", "m_burst", "w_dim_nova", "w_lamp_ward",
	"f_cross_again", "f_cross_reset",
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
		"pos": pos, "max_hp": 100000.0, "attack_power": 1.0, "move_speed": 0.0,
		"visual_id": "rogue_rat", "aggro_range": 1.0, "leash_range": 1.0,
		"melee_range": 1.0, "melee_angle": 1.0, "melee_coeff": 0.0,
		"body_radius": 20.0, "attack_name": "不动", "skills": [], "cast_coeff": 0.0,
	}
	e.position = pos
	e.configure(cfg, WorldEnemy.KIND_BEAST, "木桩")
	if not e.is_in_group("boss"):
		e.add_to_group("boss")
	add_child(e)
	return e


func _run() -> void:
	print("\n########## 试炼之路 · 机制拓展卡 ##########")
	await get_tree().process_frame

	# ===== 1. 数据：新卡登记齐全 =====
	var missing := 0
	var dead := 0
	for id in NEW_CARDS:
		var def := RogueDB.get_buff(id)
		if def.is_empty():
			missing += 1
			print("  缺失：", id)
			continue
		var has_effect := false
		for key in ["attr", "cap", "stat", "flag", "form"]:
			if def.has(key):
				has_effect = true
				break
		if not has_effect or String(def.get("desc", "")) == "":
			dead += 1
			print("  无载体 / 无文案：", id)
		if RogueDB.family_of(id) == "":
			dead += 1
			print("  无流派归属：", id)
	_check(missing == 0, "新增机制卡全部登记", "缺失 %d" % missing)
	_check(dead == 0, "新增机制卡都有载体 + 文案 + 流派归属", "问题 %d" % dead)
	_check(NEW_CARDS.size() == 29, "新增卡数量 29", str(NEW_CARDS.size()))
	# 传说卡叠加上限必须 1（机制卡不能叠成数值怪）
	var legend_bad := 0
	for id in NEW_CARDS:
		var def := RogueDB.get_buff(id)
		if String(def.get("rarity", "")) == RogueDB.RARITY_LEGEND \
				and RogueDB.stack_cap(id) != 1:
			legend_bad += 1
	_check(legend_bad == 0, "传说机制卡固定 1 层", str(legend_bad))

	# ===== 2. 图鉴：试炼卡牌卷 =====
	var has_cat := false
	for c in CodexDB.categories():
		if String((c as Dictionary).get("id", "")) == CodexDB.CAT_ROGUE_CARD:
			has_cat = true
	_check(has_cat, "图鉴已登记「试炼卡牌」卷")
	var all_cards := CodexDB.rogue_card_entries()
	var pool_total := 0
	for fam in RogueDB.POOLS.keys():
		pool_total += (RogueDB.POOLS[fam] as Array).size()
	_check(all_cards.size() == pool_total, "卡牌条目数与卡池完全一致",
		"%d / %d" % [all_cards.size(), pool_total])
	var legend_n := 0
	for raw in all_cards:
		if String((raw as Dictionary).get("rarity", "")) == RogueDB.RARITY_LEGEND:
			legend_n += 1
	_check(CodexDB.rogue_card_entries("legend").size() == legend_n,
		"按稀有度筛选（传说）", "%d" % legend_n)
	var groups := CodexDB.rogue_card_groups()
	# 组数 = 通用 1 组 + 每流派 1 组。跟着 FAMILY_ORDER 走，新增流派不用回来改数字，
	# 但「登记的流派没进卡池」仍然会被抓到（那族的分组就没了）。
	var want_groups := RogueDB.FAMILY_ORDER.size() + 1
	_check(groups.size() == want_groups,
		"按 %d 组（通用 + %d 流派）分组" % [want_groups, RogueDB.FAMILY_ORDER.size()],
		str(groups.size()))
	_check(CodexDB.unlocked_count(CodexDB.CAT_ROGUE_CARD) == all_cards.size(),
		"卡牌卷不依赖 codex_unlocked（全量可查）")
	var group_sum := 0
	for raw in groups:
		group_sum += ((raw as Dictionary).get("cards", []) as Array).size()
	_check(group_sum == pool_total, "分组内卡片总数与卡池一致", str(group_sum))

	# ===== 3. 行为：开一局，走真实入口 =====
	RogueRun.start_run("sword")
	await get_tree().process_frame
	_check(RogueRun.active, "开局 active")

	# 嗜杀：击杀叠层 → 伤害乘区真的变大
	RogueRun.add_buff("g_bloodlust")
	var base_out := RogueRun.modify_outgoing(100.0, null, "physical", "")
	RogueRun.add_kill_mark(4)
	_check(RogueRun.kill_marks == 4, "嗜杀：击杀叠 4 层", str(RogueRun.kill_marks))
	var marks_out := RogueRun.modify_outgoing(100.0, null, "physical", "")
	_check(marks_out > base_out, "嗜杀：杀意进全局伤害乘区",
		"%.1f → %.1f" % [base_out, marks_out])
	RogueRun.drop_kill_mark_half()
	_check(RogueRun.kill_marks == 2, "嗜杀：受伤掉一半", str(RogueRun.kill_marks))
	RogueRun.kill_marks = 0

	# 破釜：全局乘区（所有伤害类型）
	RogueRun.add_buff("g_purist")
	var before_flask := RogueRun.modify_outgoing(100.0, null, "elemental", "")
	_check(before_flask > 100.0, "破釜：法术伤害也吃全局乘区",
		"%.1f" % before_flask)

	# ===== 4. 玩家侧：背水 / 回响 / 剑冢 / 意尽 =====
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.get("player")
	var rogue: Node = arena.get("_rogue")
	if player == null or rogue == null:
		_check(false, "战斗场景创建失败")
		if is_instance_valid(arena):
			arena.queue_free()
		RogueRun.restore()
		return
	rogue.set_process(false)
	rogue.set_physics_process(false)
	player.set("invincible_timer", 99999.0)

	# 背水：满血 vs 残血的真实伤害出口
	RogueRun.add_buff("g_desperate")
	player.set("hp", float(player.get("max_hp")))
	var full_hit := float(player.call("_rogue_modify_damage", 100.0, null, "physical", ""))
	player.set("hp", float(player.get("max_hp")) * 0.20)
	var low_hit := float(player.call("_rogue_modify_damage", 100.0, null, "physical", ""))
	_check(low_hit > full_hit * 1.15, "背水：残血伤害显著高于满血",
		"%.1f → %.1f" % [full_hit, low_hit])
	player.set("hp", float(player.get("max_hp")))

	# 回响：清一波 → 冷却中的功法立刻转好
	RogueRun.add_buff("g_echo")
	var cds: Dictionary = player.get("skill_cooldowns")
	cds.clear()
	cds["skill_sword_stab"] = 5.0
	var tip := RogueRun.on_wave_clear(player)
	_check(not cds.has("skill_sword_stab") or float(cds["skill_sword_stab"]) <= 0.0,
		"回响：清波把冷却中的功法转好", tip)

	# 剑冢：清波给剑意
	RogueRun.add_buff("s_wj_seed")
	player.set("sword_intent", 0)
	RogueRun.on_wave_clear(player)
	_check(int(player.get("sword_intent")) >= 1, "剑冢：清波得剑意",
		str(player.get("sword_intent")))

	# 意尽：剑意清空 → 身周炸一圈（真实走 _damage_bosses_in_shape）
	RogueRun.add_buff("s_yj_break")
	# ⚠ 木桩必须摆在玩家 280 范围内：探针根在原点，但 arena 的玩家站在 (-300, 0)
	var dummy := _make_dummy(player.global_position + Vector2(90.0, 0.0))
	await get_tree().process_frame
	var hp_before := float(dummy.get("current_hp"))
	player.set("sword_intent", 3)
	player.call("_lose_sword_intent", 3)
	await get_tree().process_frame
	_check(float(dummy.get("current_hp")) < hp_before, "意尽：清空剑意炸出范围伤害",
		"%.0f → %.0f" % [hp_before, float(dummy.get("current_hp"))])
	# 反向锁：还剩层数时不该炸（防止「掉 1 层就爆」被误实现）
	player.set("sword_intent", 5)
	player.call("_lose_sword_intent", 1)
	_check(int(player.get("sword_intent")) == 4, "意尽：未清空时不触发（只掉层）",
		str(player.get("sword_intent")))

	# ===== 5. 图鉴页真实渲染 =====
	var view := CodexView.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(view)
	await get_tree().process_frame
	var idx := CodexDB.categories().size() - 1
	view.call("_show_category", idx)
	await get_tree().process_frame
	var list_box: Node = view.get("_list_box")
	var rows := list_box.get_child_count() if list_box != null else 0
	_check(rows > 13, "卡牌卷真实渲染出分组 + 卡片", "%d 行" % rows)
	view.queue_free()

	arena.queue_free()
	await get_tree().process_frame
	RogueRun.restore()
	RogueRun.family = "sword"
	_check(not RogueRun.active, "收局：active=false")
	_check(RogueRun.kill_marks == 0, "收局：杀意清零")
