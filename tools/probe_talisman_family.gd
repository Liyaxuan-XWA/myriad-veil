extends Node
## 试炼之路 · 符箓四符连携自检（2026-11-10 重做；2026-11-11 连携改为可选强化）
## 覆盖：
##   ① 数据表：10 张基础符 / 20 个变体 / 每个 op 都有实现 / 变体与卡池一一对应；
##   ② 卡池：符方与改符卡的过滤规则（没这张符时不出它的改法、选过变体后不再出另一条）；
##   ③ 开局：结符四选四 → 四个槽真的是 `talisman:<base>`、品阶 0；
##   ④ 符方 / 符囊 / 换符 / 变体互斥（走 RogueRun 的公开接口）；
##   ⑤ 施放与连携走**真实入口** player.use_run_talisman：
##      未选「连携」卡时四符独立（0 连携、8 张深度卡不进池）；
##      选到后：耗灵、进冷却、连携不耗灵不进冷却、不二次连携、连携回灵 2 点；
##   ⑥ 机制卡：无墨免灵但冷却变长、双符一次连两张；
##   ⑦ 品质倍率只乘一次；结符页能建出七张卡、未满四张不给确认。
## 用法：godot --headless --path . res://tools/probe_talisman_family.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const MINION_SCENE := "res://scenes/world/world_enemy.tscn"

var _passes := 0
var _fails: Array = []
## ⚠ lambda 里的局部变量是**按值捕获**，写在 lambda 里出不来 → 收结果必须用成员变量
var _page_picks: Array = []
## 木桩序号：只为了给每只一个能读的名字（见 _make_dummy）
var _dummy_seq := 0
## 本探针建过的所有木桩，供 _park_dummies() 整批挪走
var _dummies: Array = []


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


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


## 等到这一击**真的结算完**（血量掉下来）再读数。
## ⚠ 符是弹体，`_wait_ms(80)` 在机器忙的时候会在弹体命中前就读了血量 ——
##   同一份代码偶发读到 0 伤害（本轮红过两次，一次基线、一次连携段）。
##   读数类判据一律等事件，不要猜时长。
func _wait_hit(target: Node, from_hp: float, limit_ms: int = 900) -> void:
	var t0 := Time.get_ticks_msec()
	while _hp(target) >= from_hp and Time.get_ticks_msec() - t0 < limit_ms:
		await get_tree().process_frame
	# 掉血之后再多走两帧：同一张符可能分段结算，读早了比值会偏小
	await get_tree().process_frame
	await get_tree().process_frame


func _make_dummy(pos: Vector2) -> WorldEnemy:
	var packed := load(MINION_SCENE) as PackedScene
	var e := packed.instantiate() as WorldEnemy
	_dummy_seq += 1
	# ⚠ 必须自己命名：Godot 给的自动名（@CharacterBody2D@1211）看不出「这一符打到了
	#   第几只」，而现场里同时挂着好几只木桩 —— 读到 0 伤害时分不出是没放出去还是打错人。
	e.name = "Dummy%d" % _dummy_seq
	var cfg := {
		"pos": pos, "max_hp": 1000000.0, "attack_power": 1.0, "move_speed": 0.0,
		"visual_id": "rogue_rat", "aggro_range": 1.0, "leash_range": 1.0,
		"melee_range": 1.0, "melee_angle": 1.0, "melee_coeff": 0.0,
		"body_radius": 20.0, "attack_name": "不动", "skills": [], "cast_coeff": 0.0,
	}
	e.position = pos
	e.configure(cfg, WorldEnemy.KIND_BEAST, "木桩")
	if not e.is_in_group("boss"):
		e.add_to_group("boss")
	add_child(e)
	e.global_position = pos
	_dummies.append(e)
	return e


## 把场上所有木桩挪出射程。
## ⚠ `_run_tal_target()` 取**最近**目标：§5 前半段在玩家身边留了好几只木桩，
##   新建的那只不一定就是被锁的那只 —— 伤害落到旧木桩上，读数就是 0（实测偶发红一次）。
##   每次换基线现场前必须整批挪走，只挪「上一只」不够。
func _park_dummies() -> void:
	for d in _dummies:
		if is_instance_valid(d):
			d.global_position = Vector2(4000.0, 0.0)


func _clear_cd(player: Node) -> void:
	var ready: Dictionary = player.get("_run_tal_ready")
	ready.clear()


## ⚠ BossBase 系列（含 WorldEnemy）血量字段是 `current_hp`，不是 `hp`
func _hp(node: Node) -> float:
	return float(node.get("current_hp"))


func _run() -> void:
	print("\n########## 试炼之路 · 符箓（四符连携）##########")
	await get_tree().process_frame

	# ===== 9. 美术资源齐全（2026-11-10 补图后立的规矩）=====
	# 新增一张符最容易漏的就是图：卡面 / 小图标 / 中文元素名三样缺一样，
	# 界面上不会报错，只会退成空白框或英文名 —— 只能靠这条守住。
	var miss_card: Array = []
	var miss_icon: Array = []
	var miss_elem: Array = []
	var miss_elem_card: Array = []
	var wrong_base: Array = []
	# ⚠ all_bases() 返回的是**字典数组**（每项带 id/name/ops），不是 id 数组
	for raw in TalismanDB.all_bases():
		var bid := String((raw as Dictionary).get("id", ""))
		var st: Dictionary = ArtDB.talisman_style(bid)
		var card := String(st.get("card", ""))
		if card == "" or not ResourceLoader.exists(card):
			miss_card.append(bid)
		# ⚠ 查的是 icon 字段本身，不是 talisman_icon()：后者在 icon 为空时会退回
		#   640×960 的大卡面，缩到 48px 一糊 —— 那样断言照样绿，等于没守住。
		var ic := String(st.get("icon", ""))
		if ic == "" or not ResourceLoader.exists(ic):
			miss_icon.append(bid)
		var el := TalismanDB.element_of(bid)
		if not AttributeDB.ELEMENT_NAMES.has(el):
			miss_elem.append("%s(%s)" % [bid, el])
	# ⚠ 符灵 / 地面符阵只有 element、没有 base_id，走的是 ArtDB.element_card()。
	#   这张「元素 → 代表符」表登记错了不会报错，只会静默退回占位框 —— 必须验映射本身。
	for el_key in ArtDB.ELEMENT_COLORS:
		var e := String(el_key)
		if ArtDB.element_card(e) == "":
			miss_elem_card.append(e)
		var mapped := String(ArtDB.ELEMENT_BASE.get(e, ""))
		if mapped == "" or TalismanDB.element_of(mapped) != e:
			wrong_base.append("%s->%s" % [e, mapped])
	_check(miss_card.is_empty(), "10 张符都有卡面", ", ".join(miss_card))
	_check(miss_icon.is_empty(), "10 张符都有技能栏图标", ", ".join(miss_icon))
	_check(miss_elem.is_empty(), "每张符的元素都有中文名", ", ".join(miss_elem))
	_check(miss_elem_card.is_empty(), "按元素能取到卡面（符灵 / 符阵用）", ", ".join(miss_elem_card))
	_check(wrong_base.is_empty(), "元素→代表符映射与符表一致", ", ".join(wrong_base))


	# ===== 1. 数据表 =====
	var bases: Array = TalismanDB.all_bases()
	_check(bases.size() == 10, "符表 = 10 张基础符", str(bases.size()))
	var ids: Dictionary = {}
	var variants_total := 0
	var variant_ok := true
	for raw in bases:
		var d: Dictionary = raw
		var id := String(d.get("id", ""))
		ids[id] = true
		if String(d.get("desc", "")) == "" or (d.get("ops", []) as Array).is_empty():
			variant_ok = false
		if float(d.get("cd", 0.0)) <= 0.0:
			variant_ok = false
		var vs: Array = d.get("variants", [])
		variants_total += vs.size()
		if vs.size() != 2:
			variant_ok = false
		for raw_v in vs:
			var vd := TalismanDB.variant_def(String(raw_v))
			if vd.is_empty() or String(vd.get("base", "")) != id:
				variant_ok = false
	_check(ids.size() == 10, "基础符 id 不重复", str(ids.size()))
	_check(variant_ok, "每张基础符都有 desc / ops / 冷却 / 两个变体（且变体 base 对齐）")
	_check(variants_total == 20, "变体总数 = 20", str(variants_total))

	# 每个 op 都有实现：扫 player.gd 里 _run_tal_op 的 match 分支
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var op_start := src.find("func _run_tal_op(op: Dictionary")
	var op_end := src.find("func _run_tal_op_damage(")
	var op_body := src.substr(op_start, op_end - op_start) if op_start >= 0 and op_end > op_start else ""
	var missing: Array = []
	var kinds: Dictionary = {}
	for raw in bases:
		for raw_op in ((raw as Dictionary).get("ops", []) as Array):
			kinds[String((raw_op as Dictionary).get("op", ""))] = true
	for raw_v in TalismanDB.all_variants():
		for raw_op in ((raw_v as Dictionary).get("ops", []) as Array):
			kinds[String((raw_op as Dictionary).get("op", ""))] = true
	for raw_kind in kinds.keys():
		var kind := String(raw_kind)
		if not op_body.contains("\"%s\":" % kind):
			missing.append(kind)
	_check(missing.is_empty(), "每个 op 在 player._run_tal_op 里都有实现", ", ".join(missing))

	# 变体 / 符方与卡池一一对应
	var variant_cards: Dictionary = {}
	var recipe_cards: Dictionary = {}
	for raw in RogueDB.TALISMAN_BUFFS:
		var c: Dictionary = raw
		var vid := String(c.get("variant", ""))
		if vid != "":
			variant_cards[vid] = true
		var rid := String(c.get("recipe", ""))
		if rid != "":
			recipe_cards[rid] = true
	var no_card: Array = []
	for raw_v in TalismanDB.all_variants():
		var vid := String((raw_v as Dictionary).get("id", ""))
		if not variant_cards.has(vid):
			no_card.append(vid)
	_check(no_card.is_empty(), "20 个变体都有对应的「改符」卡", ", ".join(no_card))
	var no_recipe: Array = []
	for raw in bases:
		var bid := String((raw as Dictionary).get("id", ""))
		if not recipe_cards.has(bid):
			no_recipe.append(bid)
	_check(no_recipe.is_empty(), "10 张符都有「符方」卡", ", ".join(no_recipe))

	# ===== 2. 卡池过滤 =====
	_check(RogueDB.TALISMAN_BUFFS.size() == 48,
		"符箓池 = 1 连携解锁 + 8 深度 + 9 经济 + 10 符方 + 20 改符",
		str(RogueDB.TALISMAN_BUFFS.size()))
	# 绝笔（11-12 新增）：免冷却，但必须带代价 —— 这一池的规矩是带取舍，不发纯收益卡
	var no_cd_card: Dictionary = RogueDB.get_buff("t_no_cd")
	_check(not no_cd_card.is_empty(), "「绝笔」卡在符箓池里", str(no_cd_card.get("name", "")))
	_check(String(no_cd_card.get("flag", "")) == "tal_no_cd", "绝笔走 tal_no_cd flag")
	_check(int(no_cd_card.get("max", 0)) == 1, "绝笔只能拿 1 张（免冷却不该能叠）")
	_check(String(no_cd_card.get("desc", "")).contains("伤害"),
		"绝笔的 desc 写明了代价", String(no_cd_card.get("desc", "")))
	RogueRun.reset_talisman_state()
	var var_def := RogueDB.get_buff("t_var_bingning_seal")
	_check(not RogueRun._buff_available(var_def), "没拥有凝霜符时，不出它的改法")
	RogueRun.tal_tier["tal_bingning"] = 0
	_check(RogueRun._buff_available(var_def), "拥有凝霜符后，改法才进池")
	RogueRun.talisman_set_variant("tal_bingning", "talv_bingning_seal")
	_check(not RogueRun._buff_available(var_def), "选过冰封后不再出冰封")
	var other_var := RogueDB.get_buff("t_var_bingning_armor")
	_check(not RogueRun._buff_available(other_var), "选过冰封后也不再出霜甲（互斥）")
	var recipe := RogueDB.get_buff("t_recipe_jin")
	_check(RogueRun._buff_available(recipe), "没拥有的符，符方在池里")
	RogueRun.tal_tier["tal_jinfeng"] = 3
	_check(not RogueRun._buff_available(recipe), "满档后符方不再进池")

	# ===== 3. 开局：结符四选四 =====
	RogueRun.start_run("talisman", ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"])
	await get_tree().process_frame
	_check(RogueRun.tal_main.size() == 4, "结符：四张主符", str(RogueRun.tal_main))
	_check(RogueRun.tal_main[0] == "tal_jinfeng", "结符按玩家点选顺序装槽")
	_check(RogueRun.talisman_tier("tal_jinfeng") == 0, "新符品阶 = 练气（0）")
	var slots: Array = CharacterData.active_skill_loadout
	_check(slots.size() == 4 and CharacterData.is_talisman_slot(String(slots[0])),
		"四个功法槽装的是符箓槽值", str(slots))
	_check(CharacterData.talisman_slot_item_id(String(slots[0])) == "tal_jinfeng",
		"槽值 = talisman:<base_id>", String(slots[0]))
	# ⚠ 2026-11-10 用户报「选了符箓流派但按 Q/E/R/T 放不出符」：
	#   HUD 直接读 active_skill_loadout（上面两条），按键分发却读 equipped_active_skills()。
	#   后者对试炼的裸 base_id 查 ItemDB 查不到就 append("")，四个键全被静默吞掉。
	#   只验槽值本身抓不到 —— 必须验分发真正读的那份。
	var equipped: Array = CharacterData.equipped_active_skills()
	_check(equipped.size() == 4 and String(equipped[0]) == String(slots[0])
			and String(equipped[3]) == String(slots[3]),
		"按键分发读的 equipped_active_skills 四格没被清空（Q/E/R/T 点得到符）",
		str(equipped))

	# ===== 4. 符方 / 符囊 / 换符 / 变体 =====
	RogueRun.add_buff("t_recipe_ice")
	_check(RogueRun.talisman_owned("tal_bingning"), "符方获得未拥有的符")
	_check(RogueRun.tal_bag.has("tal_bingning"), "新符进符囊（不占主槽）", str(RogueRun.tal_bag))
	RogueRun.add_buff("t_recipe_ice")
	_check(RogueRun.talisman_tier("tal_bingning") == 1, "重复符方 → 品阶 +1",
		str(RogueRun.talisman_tier("tal_bingning")))
	_check(RogueRun.talisman_swap(0, 0), "换符：主槽 0 <-> 符囊 0")
	_check(RogueRun.tal_main[0] == "tal_bingning", "换符后主槽变成凝霜符", str(RogueRun.tal_main))
	# ⚠ 2026-11-12 用户报「每层结束的换符环节，切换了但没生效」的回归锁。
	#   旧断言只验 tal_main 变了 —— 数据确实变了，但 Q/E/R/T 读的是
	#   active_skill_loadout / equipped_active_skills，那份原来只在开局 _apply_bare_state()
	#   写过一次。于是换符页显示对调成功、按下去打的还是开局那四张。
	#   **改一份不叫改完**：必须验到按键真正读的那一份。
	_check(String(CharacterData.active_skill_loadout[0])
			== CharacterData.talisman_slot_value("tal_bingning"),
			"换符后 Q/E/R/T 槽值跟着变（不是只改了 tal_main）",
			str(CharacterData.active_skill_loadout))
	var eq_swapped: Array = CharacterData.equipped_active_skills()
	_check(String(eq_swapped[0]) == String(CharacterData.active_skill_loadout[0]),
			"换符后按键分发读的那份也同步了", str(eq_swapped))
	RogueRun.talisman_swap(0, 0)
	_check(RogueRun.talisman_set_variant("tal_bingning", "talv_bingning_seal"), "选变体：冰封")
	_check(not RogueRun.talisman_set_variant("tal_bingning", "talv_bingning_armor"),
		"同一张符不能换第二条变体（互斥）")

	# ===== 5. 真实施放与连携 =====
	RogueRun.restore()
	RogueRun.start_run("talisman", ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"])
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.get("player")
	var rogue: Node = arena.get("_rogue")
	if player == null or rogue == null:
		_check(false, "战斗场景创建失败")
		RogueRun.restore()
		return
	rogue.set_process(false)
	rogue.set_physics_process(false)
	player.set("invincible_timer", 99999.0)
	# ⚠ 木桩要贴着**玩家**摆：探针自身在原点，直接给 (120,0) 会落在符的范围外
	var dummy := _make_dummy(player.global_position + Vector2(120.0, 0.0))
	await _wait_ms(80)

	# 5.0 **玩家真正的入口**：Q → _handle_action_input → _poll_skill_keys
	#     → equipped_active_skills() → use_talisman_slot() → use_run_talisman()。
	# ⚠ 下面 5.1 起都是 player.call("use_run_talisman")，绕过了整段输入分发；
	#   「槽值被 equipped_active_skills 清空」这个静默 bug 就是这么漏掉的。
	# ⚠ 不能用 tap_key()：它同帧按下+松开，轮询输入读不到边沿，必须按住几帧。
	_clear_cd(player)
	player.set("mana", 100.0)
	player.set("max_mana", 100.0)
	# ⚠ 刚建场景时玩家还在「传送登场」演出里，_handle_action_input 会整段 return
	#   （设计上锁操作）。探针要测的是按键分发，不是登场动画 → 直接收掉这个状态。
	player.set("is_teleporting", false)
	var q_down := InputEventKey.new()
	q_down.physical_keycode = KEY_Q
	q_down.keycode = KEY_Q
	q_down.pressed = true
	Input.parse_input_event(q_down)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var q_up := InputEventKey.new()
	q_up.physical_keycode = KEY_Q
	q_up.keycode = KEY_Q
	q_up.pressed = false
	Input.parse_input_event(q_up)
	await _wait_ms(80)
	_check(float(player.call("run_talisman_cd_left", "tal_jinfeng")) > 0.0,
		"按 Q 真的放出第一张符（走完整输入分发，不是直调私有函数）",
		"CD=%.2f" % float(player.call("run_talisman_cd_left", "tal_jinfeng")))

	# 5.1 单符（符囊清空，避免连携干扰伤害对比）
	RogueRun.tal_main = ["tal_jinfeng"]
	RogueRun.tal_bag = []
	_clear_cd(player)
	player.set("mana", 100.0)
	player.set("max_mana", 100.0)
	var hp0 := _hp(dummy)
	var ok := bool(player.call("use_run_talisman", "tal_jinfeng"))
	await _wait_ms(80)
	var dmg0 := hp0 - _hp(dummy)
	_check(ok and dmg0 > 0.0, "施符走真实入口并造成伤害", "伤害 %.1f" % dmg0)
	_check(float(player.call("run_talisman_cd_left", "tal_jinfeng")) > 0.0,
		"施符后进入冷却")
	# ⚠ 容差 0.6：读数期间灵力仍在自然回复（每帧 0.3/s），卡 0.01 会随机红
	_check(absf(float(player.get("mana")) - (100.0 - TalismanDB.mana_cost("tal_jinfeng"))) < 0.6,
		"施符扣灵力", str(player.get("mana")))
	_check(String(player.call("run_talisman_block", "talisman:tal_jinfeng")) != "",
		"冷却中灰化并给出原因")

	# 5.2 品质倍率：3 档伤害更高（同符、同目标、无连携）
	RogueRun.tal_tier["tal_jinfeng"] = 3
	_clear_cd(player)
	player.set("mana", 100.0)
	hp0 = _hp(dummy)
	player.call("use_run_talisman", "tal_jinfeng")
	await _wait_ms(80)
	var dmg3 := hp0 - _hp(dummy)
	# ⚠ 只断言「比 0 档高」抓不到「乘两遍」（乘两遍只会更高）——
	#   必须钉住倍率本身：3 档 = 2.2×，容差给 2% + 0.5（结算取整）
	var want := dmg0 * TalismanDB.QUALITY_MULT[3]
	_check(dmg0 > 0.0 and absf(dmg3 - want) <= maxf(0.5, want * 0.02),
		"品质 3 档 = 0 档 ×2.2（倍率只乘一次）", "%.2f vs 期望 %.2f" % [dmg3, want])
	RogueRun.tal_tier["tal_jinfeng"] = 0

	# 5.2b 连携是可选强化（2026-11-11 用户定）：没选「连携」卡之前——
	#   施放不触发连携；8 张连携深度卡全不进池（防废卡）；解锁卡本身可进池
	RogueRun.tal_main = ["tal_jinfeng", "tal_huoqiu"]
	RogueRun.tal_bag = []
	_clear_cd(player)
	player.set("mana", 100.0)
	var chains_locked0 := int(player.get("_run_tal_chain_count"))
	player.call("use_run_talisman", "tal_jinfeng")
	await _wait_ms(80)
	_check(int(player.get("_run_tal_chain_count")) - chains_locked0 == 0,
		"未选「连携」时施放不触发连携（四符各自独立）")
	var gated: Array = []
	for raw in RogueDB.TALISMAN_BUFFS:
		var d: Dictionary = raw
		if String(d.get("need_flag", "")) == "tal_chain_on" and RogueRun._buff_available(d):
			gated.append(String(d.get("id", "")))
	_check(gated.is_empty(), "未解锁连携时 8 张深度卡全不进池", ", ".join(gated))
	var unlock := RogueDB.get_buff("t_chain_unlock")
	_check(not unlock.is_empty() and String(unlock.get("rarity", "")) == RogueDB.RARITY_RARE
			and RogueRun._buff_available(unlock), "「连携」解锁卡存在、稀有档、可进池")
	_check(not RogueRun.has_flag("tal_chain_on"), "开局不带连携机制")

	# 5.3 连携（选到「连携」卡后）：四张符 → 一次手动 = 两次施放；
	#   连携不耗灵、不进 CD、不再连锁
	RogueRun.add_buff("t_chain_unlock")
	_check(RogueRun.has_flag("tal_chain_on"), "选到「连携」后机制解锁")
	var gated2: Array = []
	for raw in RogueDB.TALISMAN_BUFFS:
		var d2: Dictionary = raw
		if String(d2.get("need_flag", "")) == "tal_chain_on" and not RogueRun._buff_available(d2):
			gated2.append(String(d2.get("id", "")))
	_check(gated2.is_empty(), "解锁后 8 张深度卡全部可进池", ", ".join(gated2))
	RogueRun.tal_main = ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"]
	RogueRun.tal_bag = []
	_clear_cd(player)
	player.set("mana", 100.0)
	var casts0 := int(player.get("_run_tal_cast_count"))
	var chains0 := int(player.get("_run_tal_chain_count"))
	player.call("use_run_talisman", "tal_jinfeng")
	await _wait_ms(80)
	var casts := int(player.get("_run_tal_cast_count")) - casts0
	var chains := int(player.get("_run_tal_chain_count")) - chains0
	_check(chains == 1, "连携正好打出 1 张", str(chains))
	_check(casts == 2, "一次手动 = 手动 1 + 连携 1（不再连锁）", str(casts))
	var chained := String(player.get("_run_tal_last_chain_id"))
	_check(chained != "" and chained != "tal_jinfeng", "连携目标不是本张", chained)
	_check(float(player.call("run_talisman_cd_left", chained)) <= 0.0,
		"连携符不进冷却", chained)
	# 灵力：手动 -5 + 连携回 2 = 97（容差 0.6 同样是自然回复）
	_check(absf(float(player.get("mana")) - 97.0) < 0.6,
		"连携不耗灵，且连携回灵 2 点", str(player.get("mana")))

	# 5.3b 连携不会抽到「本张」—— 上一条只打一次，靠运气才抓得住，这里压成两选一跑 10 轮
	#   （池里只有 金锋 + 火球：抽错就一定是本张）
	RogueRun.tal_main = ["tal_jinfeng", "tal_huoqiu"]
	RogueRun.tal_bag = []
	var self_hits := 0
	for i in 10:
		_clear_cd(player)
		player.set("mana", 100.0)
		player.call("use_run_talisman", "tal_jinfeng")
		await _wait_ms(30)
		if String(player.get("_run_tal_last_chain_id")) == "tal_jinfeng":
			self_hits += 1
	_check(self_hits == 0, "连携永远不抽本张（10 轮两选一）", str(self_hits))

	# 5.4 双符：一次连 2 张
	RogueRun.tal_main = ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"]
	RogueRun.add_buff("t_chain_double")
	_clear_cd(player)
	player.set("mana", 100.0)
	chains0 = int(player.get("_run_tal_chain_count"))
	player.call("use_run_talisman", "tal_huoqiu")
	await _wait_ms(80)
	_check(int(player.get("_run_tal_chain_count")) - chains0 == 2, "双符：一次连携 2 张",
		str(int(player.get("_run_tal_chain_count")) - chains0))
	RogueRun.buffs.erase("t_chain_double")
	RogueRun.rebuild()

	# 5.5 无墨：不耗灵、冷却变长
	RogueRun.add_buff("t_free")
	_clear_cd(player)
	player.set("mana", 0.0)
	var before_cd := float(player.call("_run_tal_mana_cost", "tal_muling"))
	_check(before_cd == 0.0, "无墨：灵力消耗变 0", str(before_cd))
	var ok_free := bool(player.call("use_run_talisman", "tal_muling"))
	var cd_free := float(player.call("run_talisman_cd_left", "tal_muling"))
	_check(ok_free and cd_free > TalismanDB.cooldown("tal_muling") * 1.1,
		"无墨：0 灵力也能放，且冷却变长", "cd=%.2f" % cd_free)
	RogueRun.buffs.erase("t_free")
	RogueRun.rebuild()

	# 5.6 绝笔（11-12 新增）：冷却归零 + 伤害打八折，两条都要验。
	#     ⚠ 放在 §5 最末尾并自带现场：前面那串测试共用灵力 / 冷却 / 木桩血量 / 品阶，
	#     插在中间会把「施符扣灵力」「品质倍率」全挤坏（第一版就是这么红的）。
	#     ⚠ 必须先拿基线伤害再开 flag —— 只验「没有冷却」会漏掉代价那一半，
	#     而代价写在 desc 里却不生效，是玩家最迟才会发现的那种错。
	RogueRun.tal_main = ["tal_jinfeng"]
	RogueRun.tal_bag = []
	RogueRun.tal_tier["tal_jinfeng"] = 0
	RogueRun.tal_variant.erase("tal_jinfeng")
	RogueRun.buffs.clear()
	_clear_cd(player)
	player.set("mana", 100.0)
	# ⚠ 每次换基线现场前把**全部**旧木桩挪出射程（见 _park_dummies 的说明）
	var dmg_base := 0.0
	var base_ok := false
	var base_try := 0
	var base_lock := "null"
	for attempt in range(3):
		# 同 5.6b：基线读到 0 时先怀疑现场，不要拿 0 去除出个 0.000 比值
		base_try += 1
		_park_dummies()
		var dummy2 := _make_dummy(player.global_position + Vector2(120.0, 0.0))
		await _wait_ms(80)
		var base_a := _hp(dummy2)
		var base_tg = player.call("_run_tal_target")
		base_lock = str(base_tg.get("name")) if base_tg != null else "null"
		base_ok = bool(player.call("use_run_talisman", "tal_jinfeng"))
		await _wait_hit(dummy2, base_a)
		dmg_base = base_a - _hp(dummy2)
		if dmg_base > 0.0:
			break
	# ⚠ 读数里带上「施放有没有被拒」「重试几次」「实际锁到谁」：读到 0 时分不出是
	#   **没放出去**、**打到了别的木桩**、还是**弹体还在飞就读了血量**。
	_check(dmg_base > 0.0, "绝笔基线：先打出一张正常符",
		"伤害 %.1f / 施放 %s / 试 %d 次 / 锁定 %s" % [
			dmg_base, str(base_ok), base_try, base_lock])

	RogueRun.add_buff("t_no_cd")
	_check(RogueRun.has_flag("tal_no_cd"), "拿到「绝笔」后 flag 生效")
	_clear_cd(player)
	player.set("mana", 100.0)
	_park_dummies()
	var dummy3 := _make_dummy(player.global_position + Vector2(120.0, 0.0))
	await _wait_ms(80)
	var b0 := _hp(dummy3)
	var ok_a := bool(player.call("use_run_talisman", "tal_jinfeng"))
	await _wait_hit(dummy3, b0)
	var b1 := _hp(dummy3)
	var cd_mid := float(player.call("run_talisman_cd_left", "tal_jinfeng"))
	var ok_b := bool(player.call("use_run_talisman", "tal_jinfeng"))
	await _wait_hit(dummy3, b1)
	var dmg_no_cd := b1 - _hp(dummy3)
	_check(cd_mid <= 0.0, "绝笔下施符后冷却读数为 0", "cd=%.2f" % cd_mid)
	_check(ok_a and ok_b and (b0 - b1) > 0.0,
		"绝笔下同一张符可以立刻连放两次（不靠 _clear_cd 作弊）")
	# 玩家可见面：格子的灰罩走 run_talisman_block，不是直接读 _run_tal_ready。
	# 只在施放口免冷却、灰化口没改，玩家看到的是「能放但一直是灰的」。
	_check(String(player.call("run_talisman_block",
			CharacterData.talisman_slot_value("tal_jinfeng"))) == "",
		"绝笔刚放完也不灰化：技能栏不画「符还没画好」")
	var ratio := dmg_no_cd / maxf(0.001, dmg_base)
	_check(ratio > 0.68 and ratio < 0.92,
		"绝笔的代价真的生效：伤害 ≈ ×0.80（留 ±10% 给 ±5% 随机浮动）",
		"%.3f（基线 %.1f → 绝笔 %.1f）" % [ratio, dmg_base, dmg_no_cd])

	# 5.6b 连携那一张也必须吃代价。
	#      ⚠ 这里原来是一条源码字串匹配（`contains("if ...tal_no_cd...")`），
	#      变异测试证明它只挡得住我预先想到的那一种写法 —— 把判据改成
	#      `if not via_chain and has_flag(...)` 就完全绿。改成行为验：
	#      直接走 via_chain=true 这个入口，比较开卡前后的伤害比值。
	#      ⚠ buffs.clear() 之后必须 rebuild()，否则上一段留下的 tal_no_cd 仍在 flags 里，
	#        两趟都打八折 → 比值恒等于 1，测不出任何东西（同理木桩要挪走，见上面）。
	var chain_no := 0.0
	var chain_yes := 0.0
	var chain_diag := ""
	for pass_i in range(2):
		# ⚠ 整趟重来（最多 3 次）直到**这一趟真的打出了伤害**：施放被 `is_action_blocked`
		#   挡一次、或弹体没落在这只木桩上，都会读到 0 —— 读 0 不是「绝笔有问题」，
		#   是现场没立住。题目没成立就不配判比值（上一版只等血量掉下来，仍然偶发红一次）。
		var dealt := 0.0
		var cast_ok := false
		var tries := 0
		var lock_name := "null"
		for attempt in range(3):
			tries += 1
			RogueRun.buffs.clear()
			if pass_i == 1:
				RogueRun.add_buff("t_no_cd")
			RogueRun.rebuild()
			_clear_cd(player)
			player.set("mana", 100.0)
			_park_dummies()
			var d := _make_dummy(player.global_position + Vector2(120.0, 0.0))
			await _wait_ms(60)
			var h0 := _hp(d)
			var tg = player.call("_run_tal_target")
			lock_name = str(tg.get("name")) if tg != null else "null"
			cast_ok = bool(player.call("_run_tal_cast", "tal_jinfeng", 1.0, true))
			await _wait_hit(d, h0)
			dealt = h0 - _hp(d)
			d.global_position = Vector2(4000.0, 0.0)
			if dealt > 0.0:
				break
		if pass_i == 0:
			chain_no = dealt
			chain_diag = "施放 %s / 试 %d 次 / 锁定 %s" % [str(cast_ok), tries, lock_name]
		else:
			chain_yes = dealt
	_check(chain_no > 0.0, "连携入口能打出伤害（题目成立）",
			"%.1f %s" % [chain_no, chain_diag])
	var cratio := chain_yes / maxf(0.001, chain_no)
	_check(cratio > 0.68 and cratio < 0.92,
		"绝笔的代价对**连携那一张**同样生效（否则连携就是纯收益漏洞）",
		"%.3f（%.1f → %.1f）" % [cratio, chain_no, chain_yes])

	# 5.6c 边打边选卡：冷却正在转的时候拿到绝笔，必须立刻可用。
	#      ⚠ 判据要落在**读数侧**（run_talisman_cd_left）。只在 _run_tal_arm 里跳过
	#      武装的话，选卡之前已经武装好的时间戳还会继续挡人 —— 玩家体感就是
	#      「选了卡没反应」。上面每轮都先 _clear_cd，正好把这条掩盖掉了。
	RogueRun.buffs.clear()
	RogueRun.rebuild()
	_clear_cd(player)
	player.set("mana", 100.0)
	# ⚠ 自带一只靶子：上面 5.6b 收尾时把木桩全挪走了，这里若不留靶子，
	#   「施完进冷却」就变成在验一次空放，题目本身不成立。
	_park_dummies()
	_make_dummy(player.global_position + Vector2(120.0, 0.0))
	await _wait_ms(60)
	bool(player.call("use_run_talisman", "tal_jinfeng"))
	await _wait_ms(80)
	var cd_before := float(player.call("run_talisman_cd_left", "tal_jinfeng"))
	_check(cd_before > 0.0, "没拿绝笔时施完确实进冷却（题目成立）", "%.2f" % cd_before)
	RogueRun.add_buff("t_no_cd")
	var cd_after := float(player.call("run_talisman_cd_left", "tal_jinfeng"))
	_check(cd_after <= 0.0,
		"冷却转着的时候选到绝笔 → 立刻可用（不用等旧冷却跑完）", "%.2f" % cd_after)
	RogueRun.buffs.clear()
	RogueRun.rebuild()

	# 5.7 换符之后 HUD 技能栏必须跟着改 —— 「没生效」有两半：数据层（§4 已锁）和
	#     显示层。_build_skill_bar 把槽值缓存进 _skill_slots[i]["sid"]，_update_skill_bar
	#     每帧读的是这份缓存；不重建的话图标、名字、tooltip、冷却遮罩全停在换符之前。
	#     ⚠ 判据要走 rogue_arena 的真实收尾 `_on_talisman_swap_closed`，探针自己调
	#       `_build_skill_bar` 不算数 —— 那样「关掉页面到底会不会触发重建」这一环没被覆盖，
	#       把生产代码里那行删掉探针照样全绿（第一版就是这么假绿的）。
	RogueRun.buffs.clear()
	RogueRun.rebuild()
	RogueRun.tal_main = ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"]
	RogueRun.tal_bag = ["tal_bingning"]
	RogueRun.sync_talisman_loadout()
	arena.call("_build_skill_bar")
	await get_tree().process_frame
	_check(RogueRun.talisman_swap(1, 0), "换符：火球符 <-> 符囊里的凝霜符")
	var stale: Array = arena.get("_skill_slots")
	_check(String(stale[1].get("sid")) != String(CharacterData.active_skill_loadout[1]),
		"页面没关时缓存仍是旧槽值（题目成立：这一层确实要靠收尾重建才刷新）",
		str(stale[1].get("sid")))
	rogue.call("_on_talisman_swap_closed")
	await get_tree().process_frame
	var cached: Array = arena.get("_skill_slots")
	_check(cached.size() == 4, "重建后技能栏仍是四格", str(cached.size()))
	_check(String(cached[1].get("sid")) == String(CharacterData.active_skill_loadout[1]),
		"关掉换符页后缓存的槽值跟着变（图标/名字/冷却才会换）",
		"%s vs %s" % [cached[1].get("sid"), CharacterData.active_skill_loadout[1]])
	_check(String(cached[1].get("sid")) == CharacterData.talisman_slot_value("tal_bingning"),
		"缓存里确实是凝霜符，不是换符前的火球", str(cached[1].get("sid")))
	# 再走一次收尾，数 HUD 下的技能栏容器（queue_free 要等一帧才真正摘掉）
	# ⚠ 节点泄漏：本函数原先只在开战时跑一次，现在每换一次符就跑一次，旧 row 不摘
	#   就等于每换一次往 HUD 塞一个空 HBoxContainer。
	rogue.call("_on_talisman_swap_closed")
	await get_tree().process_frame
	var hud: Node = arena.get_node_or_null("HUD")
	var rows := 0
	if hud != null:
		for c in hud.get_children():
			# ⚠ 认 meta 不认 name：泄漏时多出来的 row 会因为撞名被 Godot 顶成
			#   @Control@…，按名字数**恰好数不到泄漏的那几只**（变异④ 就是这么全绿的）。
			if c.has_meta("skill_bar_row"):
				rows += 1
	_check(rows == 1, "重建两次后 HUD 只剩一条技能栏（不随换符累积空容器）", str(rows))
	RogueRun.tal_main = ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"]
	RogueRun.tal_bag = []
	RogueRun.sync_talisman_loadout()
	_clear_cd(player)

	# ===== 6. 符阵与符灵 =====
	RogueRun.tal_tier["tal_yinlei"] = 0
	RogueRun.talisman_set_variant("tal_yinlei", "talv_yinlei_prison")
	_clear_cd(player)
	player.set("mana", 100.0)
	var zones_before := _count_zones()
	player.call("use_run_talisman", "tal_yinlei")
	await _wait_ms(120)
	_check(_count_zones() > zones_before, "雷狱符真的铺出地面区", str(_count_zones()))
	RogueRun.talisman_set_variant("tal_muling", "talv_muling_spirit")
	_clear_cd(player)
	player.set("mana", 100.0)
	var spirits_before := _count_spirits()
	player.call("use_run_talisman", "tal_muling")
	await _wait_ms(120)
	_check(_count_spirits() > spirits_before, "符灵·青藤真的召出符灵", str(_count_spirits()))

	# ===== 7. 结符页 =====
	var page = load("res://scripts/ui/talisman_loadout_page.gd").new()
	add_child(page)
	await get_tree().process_frame
	var card_count := 0
	for raw in page.get("_cards").keys():
		card_count += 1
	_check(card_count == 7, "结符页列出七张元素符", str(card_count))
	var confirm: Button = page.get("_confirm")
	_check(confirm != null and confirm.disabled, "没选满四张时不能开始")
	for raw in TalismanDB.start_pool().slice(0, 4):
		page.call("_on_card_picked", String(raw))
	_check(not confirm.disabled, "选满四张后可以开始", str(page.get("_picked")))
	_page_picks = []
	page.confirmed.connect(func(picks: Array) -> void: _page_picks = picks)
	page.call("_on_confirm")
	_check(_page_picks.size() == 4, "确认后把四张选择交给上层", str(_page_picks))
	page.queue_free()

	# ===== 8. 入口接线：塔面板点「踏入试炼」先弹结符页，不直接开跑 =====
	# ⚠ 只验到「弹页」为止：再往下 _on_talisman_picks 会 change_scene，探针会被一起销毁。
	dummy.queue_free()
	arena.queue_free()
	RogueRun.restore()
	await get_tree().process_frame
	CharacterData.domain_progress[RogueDB.TRIAL_UNLOCK_DOMAIN] = {
		"unlocked": true, "cleared_bosses": [RogueDB.TRIAL_UNLOCK_BOSS]}
	var panel := (load("res://scripts/ui/panels/tower_panel.gd") as GDScript).new() as SystemPanel
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.set("_rogue_family", "talisman")
	panel.call("_on_enter_rogue")
	await get_tree().process_frame
	var page_found := false
	for c in panel.get_children():
		var sc = c.get_script()
		if sc != null and String(sc.resource_path).ends_with("talisman_loadout_page.gd"):
			page_found = true
	_check(page_found and not RogueRun.active,
		"塔面板「踏入试炼」先开结符页，不直接开跑",
		"page=%s active=%s" % [str(page_found), str(RogueRun.active)])
	panel.queue_free()
	await get_tree().process_frame

	# ===== 9. 换符页必须是屏幕层（2026-11-10 用户报「面板固定在地上」）=====
	# ⚠ 只验「面板能建出来」抓不到这个：工具截图阶段树里没有 Camera2D，
	#   裸 Control 挂 root 看起来也居中；实机同层有战斗世界 + 相机，就会跟着地面跑。
	var swap = load("res://scripts/ui/talisman_swap_page.gd").new()
	add_child(swap)
	await get_tree().process_frame
	_check(swap is CanvasLayer, "换符页自带 CanvasLayer（不跟相机 / 地面跑）",
			swap.get_class())
	if swap is CanvasLayer:
		_check(int(swap.get("layer")) >= 100,
			"换符页在高 layer（盖得住战斗 HUD）", str(swap.get("layer")))
		_check(int(swap.get("process_mode")) == int(Node.PROCESS_MODE_ALWAYS),
			"暂停树后换符页仍能收输入（ALWAYS）", str(swap.get("process_mode")))
		# 只验 process_mode 常量还不够：真的把树暂停一次，确认 can_process 仍为 true
		# （原来缺这一条时「继续」按钮会整块收不到 GUI 事件，面板卡死）。
		var was_paused := get_tree().paused
		get_tree().paused = true
		var alive := bool(swap.can_process())
		get_tree().paused = was_paused
		_check(alive, "暂停后换符页 can_process 仍为真（继续键点得动）", str(alive))
	var dim: Node = swap.get_node_or_null("Dim")
	_check(dim != null and dim is ColorRect, "换符页有全屏压暗遮罩", str(dim))
	if dim != null:
		var dr := (dim as Control).get_global_rect()
		var vsp := get_viewport().get_visible_rect().size
		_check(dr.size.x >= vsp.x - 1.0 and dr.size.y >= vsp.y - 1.0,
			"遮罩铺满视口（不会从四周露出红色地面）",
			"%.0f×%.0f / 视口 %.0f×%.0f" % [dr.size.x, dr.size.y, vsp.x, vsp.y])
	swap.queue_free()
	await get_tree().process_frame

	# ===== 10. 换符页的**点击路径**端到端（用户报的「切换了没生效」就发生在这里）=====
	# ⚠ §4 验的是 `RogueRun.talisman_swap()` 本身，§5.7 验的是页面关掉的收尾；
	#   中间那一环「玩家点两张卡 → 页面到底有没有去调 swap」一直没锁。
	#   这一节把 点符囊 → 点主槽 → 对调 走一遍，读数读到按键分发真正吃的那份槽值为止。
	RogueRun.start_run("talisman", ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"])
	RogueRun.add_buff("t_recipe_ice")
	_check(RogueRun.tal_bag.size() == 1 and RogueRun.tal_bag[0] == "tal_bingning",
		"现场：符囊里有一张凝霜符", str(RogueRun.tal_bag))
	var swap2 = load("res://scripts/ui/talisman_swap_page.gd").new()
	add_child(swap2)
	await get_tree().process_frame
	swap2.call("_on_bag_pressed", 0)
	swap2.call("_on_main_pressed", 1)
	await get_tree().process_frame
	_check(RogueRun.tal_main[1] == "tal_bingning",
		"页面上点两张卡 → 主槽真的对调了", str(RogueRun.tal_main))
	_check(String(CharacterData.active_skill_loadout[1])
			== CharacterData.talisman_slot_value("tal_bingning"),
		"页面点击这一路走完，Q/E/R/T 槽值也是新的（不是只改了 tal_main）",
		str(CharacterData.active_skill_loadout))
	# 没选符囊就点主槽：必须只给提示，不许把主槽清空
	var main_snapshot: Array = RogueRun.tal_main.duplicate()
	swap2.call("_on_main_pressed", 0)
	await get_tree().process_frame
	_check(RogueRun.tal_main == main_snapshot,
		"未选符囊时点主槽不动任何槽（只出提示）", str(RogueRun.tal_main))
	swap2.call("close")
	await get_tree().process_frame
	RogueRun.restore()


func _count_zones() -> int:
	return get_tree().get_nodes_in_group("talisman_zone").size()


func _count_spirits() -> int:
	return get_tree().get_nodes_in_group("talisman_spirit").size()
