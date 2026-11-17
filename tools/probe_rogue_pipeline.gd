extends Node
## 试炼之路（肉鸽爬塔）链路自检（2026-11-08）
## 覆盖：开局快照与裸装、卡池与叠层、上限变量化、招式覆盖、波次推进、三选一、
##       BOSS 关与层数推进、复活、结算与角色数据还原、晶石入包。
## 用法：godot --headless --path . res://tools/probe_rogue_pipeline.tscn -- --no-save

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


func _find_panel(cls_name: String) -> Node:
	for c in get_tree().root.get_children():
		if c.get_script() == null:
			continue
		var path := String((c.get_script() as Script).resource_path)
		if path.ends_with(cls_name + ".gd"):
			return c
	return null


func _run() -> void:
	print("\n########## 试炼之路 · 链路 ##########")
	await get_tree().process_frame

	# ===== 1. 模拟一个有进度的玩家，进局应整组快照 =====
	CharacterData.base_attributes["strength"] = 77.0
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 2
	CharacterData.learned_skills = ["skill_fake_progress"]
	CharacterData.active_skill_loadout = ["skill_fake_progress"]
	CharacterData.equipment_slots["weapon"] = {"id": "eq_fake", "name": "假剑"}
	CharacterData.attribute_mods["potion"] = {"strength": {"flat": 5.0}}
	var crystal_before := _count_item(RogueDB.CRYSTAL_ID)
	var autosave_was := SaveManager.auto_save_enabled

	RogueRun.start_run()
	await get_tree().process_frame
	_check(RogueRun.active, "开局：active")
	_check(RogueRun.floor_no == 1 and RogueRun.stage_no == 1 and RogueRun.wave_no == 1, "开局：层/关/波=1")
	_check(RogueRun.stages_cleared == 0 and RogueRun.floors_cleared == 0, "开局：晶石计分清零")
	_check(is_equal_approx(CharacterData.attribute("strength"), 10.0), "裸装：力量=10",
		"实际 %.1f" % CharacterData.attribute("strength"))
	_check(is_equal_approx(CharacterData.max_hp(), 100.0), "裸装：气血=100",
		"实际 %.1f" % CharacterData.max_hp())
	_check(CharacterData.current_realm == "练气" and CharacterData.realm_stage == 0, "裸装：练气前期")
	_check(CharacterData.equipment_slots["weapon"] == null, "裸装：武器槽空")
	var has_all_start := true
	for sid in RogueDB.START_LEARNED:
		if not CharacterData.learned_skills.has(sid):
			has_all_start = false
	_check(has_all_start, "起始功法齐全", str(CharacterData.learned_skills))
	_check(CharacterData.active_skill_loadout.size() == 4, "4 个主动槽已装配")
	_check(not SaveManager.auto_save_enabled, "局内关掉自动存档")

	# ===== 2. 卡池 / 叠层 / 上限变量化 =====
	_check(RogueRun.cap("sword_intent_max") == 5, "剑意上限基值 5")
	RogueRun.add_buff("s_wj_cap")
	_check(RogueRun.cap("sword_intent_max") == 7, "纳锋：剑意上限 7")
	_check(int(MoveDB.resolve_player("form_sword_heaven").get("intent_full_at", 0)) == 7,
		"展示口径 intent_full_at 同步 7")
	RogueRun.add_buff("s_yj_dmg")
	var heaven := MoveDB.resolve_player("form_sword_heaven")
	_check(absf(float(heaven.get("phys_coeff", 0.0)) - 5.6) < 0.01, "开天·重：系数 ×1.4",
		"实际 %.2f" % float(heaven.get("phys_coeff", 0.0)))
	RogueRun.add_buff("g_str")
	_check(is_equal_approx(CharacterData.attribute("strength"), 13.0), "淬体：力量 +3")
	RogueRun.add_buff("g_str")
	RogueRun.add_buff("g_str")
	RogueRun.add_buff("g_str")
	_check(RogueRun.buff_stacks("g_str") == 3, "叠层封顶 3（第 4 次不入）")
	RogueRun.add_buff("s_yj_free")
	_check(RogueRun.has_flag("heaven_free"), "天成：免叠层开关")
	var picks := RogueRun.roll_choices(3, true)
	_check(picks.size() == 3, "三选一抽 3 张", str(picks.size()))
	var has_rare := false
	for raw in picks:
		if String((raw as Dictionary).get("rarity", "")) != RogueDB.RARITY_COMMON:
			has_rare = true
	_check(has_rare, "BOSS 关后保底稀有")
	var ids := {}
	for raw in picks:
		ids[String((raw as Dictionary).get("id", ""))] = true
	_check(ids.size() == picks.size(), "三张不重复")

	# ===== 2.5 小怪美术登记（缺登记 = 灰方块，用户定「占位必须能跑」）=====
	var unregistered: Array = []
	for mid in RogueDB.MINIONS.keys():
		var mdef: Dictionary = RogueDB.MINIONS[mid]
		var vid := String(mdef.get("visual_id", ""))
		if not ArtDB.VISUALS.has(vid):
			unregistered.append(String(mid))
	_check(unregistered.is_empty(), "四只小怪都已登记 ArtDB.VISUALS", str(unregistered))

	# ===== 3. 进战斗场景：第 1 层小关 1 第 1 波 =====
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var rogue = arena.get("_rogue")
	_check(rogue != null, "RogueArena 已创建")
	if rogue == null:
		return
	var alive: Array = rogue.get("_alive")
	# ⚠ 怪数按层渐进（WAVE_COUNTS），别写死 2/3：数值平衡后第 1 层是 1/2/2
	_check(alive.size() == RogueDB.wave_size(1, 1), "第 1 波怪数 = WAVE_COUNTS[1][1]",
		"%d / %d" % [alive.size(), RogueDB.wave_size(1, 1)])
	var player: Node2D = arena.get("player")
	var boss: Node2D = arena.get("boss")
	_check(player != null and boss != null, "玩家 / BOSS 已就位")
	_check(not bool(boss.get("visible")), "小怪阶段 BOSS 休眠")
	_check(is_equal_approx(float(boss.get("max_hp")), RogueDB.boss_hp("boss_huyao", 1)),
		"BOSS 血量按层数曲线", "实际 %.0f" % float(boss.get("max_hp")))

	# 剑意上限真的能在运行时抬高
	player.set("sword_intent", 6)
	_check(int(player.call("_sword_intent_max")) == 7, "运行时取到 7 层上限")

	# ===== 4. 清第 1 波 → 喘息 → 第 2 波 =====
	for e in alive:
		e.take_damage(999999.0, player, "physical_melee")
	await get_tree().create_timer(0.25).timeout
	_check(RogueRun.wave_no == 2, "第 1 波清空 → 波次 2", str(RogueRun.wave_no))
	await get_tree().create_timer(RogueDB.WAVE_BREAK + 0.4).timeout
	alive = rogue.get("_alive")
	_check(alive.size() == RogueDB.wave_size(1, 2), "第 2 波怪数 = WAVE_COUNTS[1][2]",
		"%d / %d" % [alive.size(), RogueDB.wave_size(1, 2)])

	# ===== 5. 清第 2 波 → 喘息 → 第 3 波 → 清空 → 三选一 =====
	for e in alive:
		e.take_damage(999999.0, player, "physical_melee")
	await get_tree().create_timer(0.25).timeout
	_check(RogueRun.wave_no == 3, "第 2 波清空 → 波次 3", str(RogueRun.wave_no))
	await get_tree().create_timer(RogueDB.WAVE_BREAK + 0.4).timeout
	alive = rogue.get("_alive")
	_check(alive.size() > 0, "第 3 波已刷出", str(alive.size()))
	for e in alive:
		if is_instance_valid(e):
			e.take_damage(999999.0, player, "physical_melee")
	await get_tree().create_timer(0.35).timeout
	var pick: Node = _find_panel("rogue_pick_panel")
	_check(pick != null, "小关结束弹出三选一")
	_check(get_tree().paused, "选卡时战斗暂停")
	if pick != null:
		var choices: Array = pick.get("choices")
		_check(choices.size() == 3, "面板 3 张玉简", str(choices.size()))
		var pick_id := String((choices[0] as Dictionary).get("id", ""))
		var before_stacks := RogueRun.buff_stacks(pick_id)
		pick.emit_signal("picked", pick_id)
		pick.call("close")
		await get_tree().create_timer(1.8).timeout
		_check(RogueRun.buff_stacks(pick_id) == before_stacks + 1, "选中的增益已入册", pick_id)
		_check(RogueRun.stage_no == 2, "进入小关 2", str(RogueRun.stage_no))
		_check(not get_tree().paused, "选完恢复战斗")

	# ===== 6. 跳到 BOSS 关 =====
	for e in rogue.get("_alive"):
		if is_instance_valid(e):
			e.take_damage(999999.0, player, "physical_melee")
	await get_tree().create_timer(0.2).timeout
	RogueRun.stage_no = RogueDB.STAGES_PER_FLOOR
	RogueRun.wave_no = 1
	rogue.set("_phase", 0)  # IDLE，避免 _process 与手动切关打架
	rogue.call("_start_stage")
	await get_tree().process_frame
	# ⚠ 每层 BOSS 关都会重新实例化 BOSS（spawn_rogue_boss_now），
	#   探针开头缓存的 boss 引用此时已被 free —— 必须重取，否则读已释放实例报错。
	#   顺带断言「确实换了一只」，这正是「卡在 BOSS 关进不了下一层」的修复点。
	var fresh_boss: Node2D = arena.get("boss")
	_check(fresh_boss != null and is_instance_valid(fresh_boss) and fresh_boss != boss,
		"BOSS 关重新实例化了本层 BOSS")
	boss = fresh_boss
	_check(bool(boss.get("visible")), "BOSS 关亮出 BOSS")
	_check(rogue.get("_phase") == 4, "阶段 = BOSS")

	# ===== 7. 击杀 BOSS → 遗物落地 → 捡起 → 必出稀有 → 下一层 =====
	var floor_before := RogueRun.floor_no
	boss.take_damage(9999999.0, player, "physical_melee")
	await get_tree().create_timer(0.2).timeout
	_check(RogueRun.boss_kills == 1, "击败 BOSS 计数 +1")
	# ⚠ 2026-11-09 起 BOSS 装备先**落地**，玩家捡走（或 10 秒兜底）之后才弹三选一。
	#   探针走真实入口：走到遗物上按 F（combat_arena._try_pickup_nearest）。
	var drops: Array = rogue.get("_boss_drop_nodes")
	_check(drops.size() == 1, "BOSS 遗物落地可拾取", str(drops.size()))
	if drops.size() > 0:
		var drop: Node2D = drops[0]
		# ⚠ 别反过来传送玩家：CharacterBody2D 被瞬移进 Area2D 时，物理服务器这一帧
		#   不一定重算 overlap（探针里实测 ovl=0）。把遗物挪到玩家脚下等价且稳定。
		drop.global_position = player.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(bool(drop.call("has_player_inside")), "玩家站在遗物上（拾取范围已命中）")
		arena.call("_try_pickup_nearest")
		await get_tree().process_frame
	await get_tree().create_timer(0.7).timeout

	# ===== 7.1 遗物到手提示（2026-11-11 用户要「获得装备时给个点开背包穿戴的提示」）=====
	# 真实入口：上面走的是 combat_arena._try_pickup_nearest → pickup_handler
	# → rogue_arena._on_boss_gear_picked，提示必须在这条链路上自己亮起来。
	var hint: PanelContainer = rogue.get("_gear_hint") as PanelContainer
	_check(hint != null, "遗物到手提示卡已随 HUD 创建")
	if hint != null:
		var title_lb: Label = rogue.get("_gear_hint_title") as Label
		var body_lb: Label = rogue.get("_gear_hint_body") as Label
		_check(hint.visible, "捡到遗物后提示卡亮相")
		var got_name := ""
		if not RogueRun.gear_bag.is_empty():
			got_name = String((RogueRun.gear_bag[0] as Dictionary).get("name", ""))
		_check(got_name != "" and title_lb.text.contains(got_name),
			"标题写清拿到了哪件装备", title_lb.text)
		_check(body_lb.text.contains("Tab") and body_lb.text.contains("穿戴"),
			"正文写明「按 Tab 打开行囊穿戴」", body_lb.text)
		# ⚠ 与任务面板同坑：CanvasLayer 子级不按最小尺寸铺开，不给尺寸就是 0×0
		_check(hint.size.x >= 400.0 and hint.size.x <= 440.0, "提示卡宽度恒定（不变形）",
			str(hint.size))
		_check(hint.size.y > 0.0 and hint.size.y <= 96.0, "提示卡高度贴合内容",
			str(hint.size))
		_check(hint.mouse_filter == Control.MOUSE_FILTER_STOP, "提示卡整条可点")
		# 别压在技能栏上：底边必须留出下方操作区的空间
		_check(hint.get_global_rect().end.y < 540.0, "提示卡在技能栏上方（不挡操作）",
			str(hint.get_global_rect()))

	var pick2 := _find_panel("rogue_pick_panel")
	_check(pick2 != null, "BOSS 后弹出三选一（保底稀有）")
	if pick2 != null:
		var rare_ok := false
		for raw in (pick2.get("choices") as Array):
			if String((raw as Dictionary).get("rarity", "")) != RogueDB.RARITY_COMMON:
				rare_ok = true
		_check(rare_ok, "三张里至少一张稀有")
		var cid := String(((pick2.get("choices") as Array)[0] as Dictionary).get("id", ""))
		pick2.emit_signal("picked", cid)
		pick2.call("close")
		await get_tree().create_timer(1.8).timeout
	_check(RogueRun.floor_no == floor_before + 1, "进入第 2 层", str(RogueRun.floor_no))

	# ===== 7.2 点提示卡 → 直接打开试炼行囊 =====
	# 走真实鼠标分发（push_input），别用 pressed.emit()：那样按钮被遮住、mouse_filter
	# 写错、坐标算错全都测不出来，玩家点不动探针照样全绿。
	if hint != null and hint.visible:
		_check(_find_panel("rogue_gear_panel") == null, "点击前没有行囊面板")
		_click(hint.get_global_rect().get_center())
		await get_tree().process_frame
		await get_tree().process_frame
		var gear_panel := _find_panel("rogue_gear_panel")
		_check(gear_panel != null, "点提示卡真的打开了试炼行囊")
		_check(not hint.visible, "行囊打开后提示卡收起")
		if gear_panel != null:
			gear_panel.call("close")
		for i in 3:
			await get_tree().process_frame
		_check(not get_tree().paused, "关掉行囊后恢复战斗")

	# ===== 8. 复活一次 =====
	await get_tree().process_frame
	var revive_before := RogueRun.revive_left()
	player.call("take_damage", 999999.0, "physical_melee", null, "")
	await get_tree().create_timer(0.3).timeout
	_check(RogueRun.revive_left() == revive_before - 1, "第一次死亡消耗复活", str(RogueRun.revive_left()))
	_check(not bool(player.get("is_dead")), "复活后不是死亡状态")
	_check(is_equal_approx(float(player.get("hp")), float(player.get("max_hp"))), "复活后满血")

	# ===== 9. 第二次死亡 → 结算 + 还原 =====
	var reached := RogueRun.floor_no
	# 复活给了 3 秒无敌，这一下必须先把无敌清掉，否则打不动（这正是 §三 记录的「免伤 return」坑）
	player.set("invincible_timer", 0.0)
	player.call("take_damage", 999999.0, "physical_melee", null, "")
	await get_tree().create_timer(0.5).timeout
	_check(not RogueRun.active, "结算后 active=false")
	_check(is_equal_approx(float(CharacterData.base_attributes.get("strength", 0.0)), 77.0),
		"还原：力量回到 77", str(CharacterData.base_attributes.get("strength")))
	_check(CharacterData.current_realm == "元婴" and CharacterData.realm_stage == 2, "还原：境界元婴后期")
	_check(CharacterData.learned_skills == ["skill_fake_progress"], "还原：功法表")
	var wpn_raw = CharacterData.equipment_slots.get("weapon", null)
	var wpn_id := ""
	if wpn_raw is Dictionary:
		wpn_id = String((wpn_raw as Dictionary).get("id", ""))
	_check(wpn_id == "eq_fake", "还原：武器槽", wpn_id)
	_check(CharacterData.attribute_mods.has("potion"), "还原：临时修正（丹药）")
	_check(not CharacterData.attribute_mods.has("rogue"), "还原：肉鸽属性修正已清")
	# ⚠ 探针带 --no-save 跑时 auto_save_enabled 本来就是 false，所以比对「进局前的值」
	_check(SaveManager.auto_save_enabled == autosave_was, "结算后自动存档闸门回到原值",
		"now=%s was=%s" % [str(SaveManager.auto_save_enabled), str(autosave_was)])
	_check(CharacterData.rogue_best_floor >= reached, "记录历史最高层",
		"best=%d reached=%d" % [CharacterData.rogue_best_floor, reached])
	var gained := _count_item(RogueDB.CRYSTAL_ID) - crystal_before
	# 计分断言独立于晶石断言：撤掉 advance_stage 埋点时计数=0 → 这里先红，不会假绿
	_check(RogueRun.stages_cleared == 2 and RogueRun.floors_cleared == 1,
		"计分：通关 2 关（小关1+BOSS关）过 1 层",
		"stages=%d floors=%d" % [RogueRun.stages_cleared, RogueRun.floors_cleared])
	# 期望 = 2×1 + 1×2 = 4；同时硬编码 4 兜住「公式没改」的回归（旧公式 2 层 ×4 = 8）
	var expect_crystals := RogueRun.stages_cleared * RogueDB.CRYSTALS_PER_STAGE \
		+ RogueRun.floors_cleared * RogueDB.CRYSTALS_PER_FLOOR_BONUS
	_check(gained == expect_crystals and gained == 4, "晶石 = 关数×1 + 层数×2 = 4",
		"实际 %d / 期望 %d" % [gained, expect_crystals])

	var settle := _find_panel("rogue_settle_panel")
	_check(settle != null, "结算面板已弹出")
	if settle != null:
		settle.call("close")
	await get_tree().process_frame

	# ===== 10. 边界：进入就退出 = 0 关 0 层 = 0 晶石（2026-11-11 用户定的白嫖封死） =====
	# 纯逻辑双开双收：start_run 捕快照 → finish_run 还原，不碰 arena；best/runs 自增无害
	var crystal_before2 := _count_item(RogueDB.CRYSTAL_ID)
	RogueRun.start_run()
	RogueRun.finish_run(false)
	var gained2 := _count_item(RogueDB.CRYSTAL_ID) - crystal_before2
	_check(not RogueRun.active, "边界：纯逻辑局已收")
	_check(gained2 == 0, "边界：进入就退出 = 0 晶石", "实际 %d" % gained2)


func _count_item(item_id: String) -> int:
	var total := 0
	for it in CharacterData.inventory:
		var d: Dictionary = it
		if String(d.get("id", "")) == item_id:
			total += int(d.get("count", 1))
	return total


## 真实点击：push_input 走完整 GUI 分发。
## ⚠ headless 下默认 `push_input(ev)` 会过一遍「窗口 → viewport」的拉伸变换，
##   坐标明明落在控件矩形里也会点空（probe_quest_panel 踩过，hover 恒 null）。
func _click(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	get_viewport().push_input(m, true)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = pos
	d.global_position = pos
	get_viewport().push_input(d, true)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = pos
	u.global_position = pos
	get_viewport().push_input(u, true)
