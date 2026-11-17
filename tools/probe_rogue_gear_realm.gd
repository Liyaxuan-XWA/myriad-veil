extends Node
## 试炼之路 · 局内 BOSS 装备 + 修为突破自检（2026-11-08）
##
## 用户定：击败 BOSS 随机获得该 BOSS 装备之一 → 局内行囊 → Tab 自己选着戴；
## 击杀小怪 / BOSS 给修为 → 满即自动突破（有明显提示）。
## 铁律：以上全部只在 RogueRun 局内容器里，**绝不写** CharacterData 的
## equipment_slots / inventory / codex / realm_*，出局 restore() 整组清空。
##
## 用法：godot --headless --path . res://tools/probe_rogue_gear_realm.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	print("\n########## 试炼局内装备 / 修为 ##########")
	# ===== 局外档快照（验「不影响局外」的基准）=====
	var inv0 := CharacterData.inventory.size()
	var eq0: Dictionary = CharacterData.equipment_slots.duplicate(true)
	var codex0 := CharacterData.codex_unlocked.size()
	var realm0 := String(CharacterData.current_realm)
	var stage0 := int(CharacterData.realm_stage)
	var exp0 := int(CharacterData.realm_exp)

	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	if rogue == null or player == null:
		_check(false, "试炼战斗场景创建成功")
		RogueRun.restore()
		return
	rogue.set_process(false)
	for raw in (rogue.get("_alive") as Array):
		if is_instance_valid(raw):
			(raw as Node).free()
	(rogue.get("_alive") as Array).clear()

	# ===== 开局局内状态 =====
	_check(RogueRun.gear_bag.is_empty(), "开局行囊为空")
	_check(RogueRun.gear_slots.size() == CharacterData.SLOT_ORDER.size(),
		"局内槽位与局外 SLOT_ORDER 一致", str(RogueRun.gear_slots.size()))
	_check(RogueRun.realm_title() == "练气前期" and RogueRun.realm_exp == 0,
		"局内从练气前期 / 0 修为起步", RogueRun.realm_title())
	_check(RogueRun.stage_exp_required() == RogueDB.TRIAL_STAGE_EXP_BASE,
		"局内阈值走独立常量", str(RogueRun.stage_exp_required()))

	# ===== BOSS 装备抽取：必须是该 BOSS 池里的装备之一 =====
	var huyao_ids: Array = []
	for raw in ItemDB.get_drops_for_boss("boss_huyao"):
		var e: Dictionary = raw
		if String(e.get("kind", "equipment")) == "equipment":
			huyao_ids.append(String(e.get("item_id", "")))
	_check(huyao_ids.size() >= 2, "虎妖登记了多件装备（能随机「之一」）", str(huyao_ids))
	var pool_ok := true
	for i in 24:
		var g := RogueDB.roll_boss_gear("boss_huyao")
		if g.is_empty() or not huyao_ids.has(String(g.get("id", ""))):
			pool_ok = false
	_check(pool_ok, "24 次抽取都落在虎妖装备池内（不串别的 BOSS）")
	var other := RogueDB.roll_boss_gear("boss_01")
	_check(not other.is_empty() and String(other.get("id", "")) == "eq_fanpinwandao",
		"刀客只掉自己的弯刀", String(other.get("id", "")))

	# ===== 真实入口：击败 BOSS → 遗物**落地**，按 F 才进行囊 =====
	_check(bool(rogue.call("_drop_boss_gear")), "击败 BOSS 后遗物落地")
	_check(RogueRun.gear_bag.is_empty(), "还没捡时行囊不增加", str(RogueRun.gear_bag.size()))
	var drops: Array = rogue.get("_boss_drop_nodes")
	_check(drops.size() == 1 and is_instance_valid(drops[0]),
		"场上生成了一件可拾取遗物", str(drops.size()))
	var drop: Area2D = drops[0]
	var drop_item: Dictionary = drop.get("item")
	_check(String(drop_item.get("type", "")) == "rogue_gear_drop",
		"地面那份是显示副本（type 改成试炼专属值）", String(drop_item.get("type", "")))
	# 走到遗物上「按 F」：走 combat_arena 的真实拾取入口，不直接调 handler
	# （⚠ 上一轮漏登记 _drops_on_ground 就会「看得见捡不到」，只有真实入口能抓到）
	# ⚠ 把遗物挪到玩家脚下，而不是瞬移玩家：CharacterBody2D 被瞬移进 Area2D 时
	#   物理服务器不一定立刻重算 overlap（实测 ovl=0 → 探针假红）。
	drop.global_position = player.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(bool(drop.call("has_player_inside")), "玩家站在遗物上（拾取范围已命中）")
	arena.call("_try_pickup_nearest")
	await get_tree().process_frame
	# 拾取成功后 0.45s 会安排三选一（面板会暂停树）；探针不跑那一步，先把阶段挪开
	rogue.set("_phase", RogueArena.Phase.FIGHT)
	_check(RogueRun.gear_bag.size() == 1, "按 F 后装备进局内行囊",
		str(RogueRun.gear_bag.size()))
	if RogueRun.gear_bag.size() == 1:
		var picked: Dictionary = RogueRun.gear_bag[0]
		_check(String(picked.get("type", "")) == CharacterData.ITEM_EQUIPMENT,
			"入包时 type 已还原成装备", String(picked.get("type", "")))
	_check((rogue.get("_boss_drop_nodes") as Array).is_empty(),
		"拾取后待捡列表清空")
	_check(CharacterData.inventory.size() == inv0, "没进主模式背包",
		"%d → %d" % [inv0, CharacterData.inventory.size()])
	_check(CharacterData.codex_unlocked.size() == codex0, "没写图鉴",
		"%d → %d" % [codex0, CharacterData.codex_unlocked.size()])
	var eq_inside: Dictionary = CharacterData.equipment_slots.duplicate(true)
	for slot in eq_inside.keys():
		_check(eq_inside.get(slot) == null, "局外装备槽没被写入：%s" % String(slot))

	# ===== 穿戴 / 卸下：属性真的生效，且走独立 source =====
	# 用一件已知带绝对词条的装备，避免随机到纯百分比词条不好验 attribute()
	var tpl := ItemDB.get_equipment_template("eq_qingfengjian")
	var known := CharacterData.make_equipment_instance(tpl)
	RogueRun.add_gear(known)
	var known_attrs := ItemDB.item_attributes(known)
	var attr_key := ""
	for k in known_attrs.keys():
		if not String(k).ends_with("_pct"):
			attr_key = String(k)
			break
	var attr_before := float(CharacterData.attribute(attr_key))
	RogueRun.equip_from_bag(1)
	_check(RogueRun.gear_bag.size() == 1, "穿戴后行囊少一件", str(RogueRun.gear_bag.size()))
	var worn_slot := ""
	for slot in RogueRun.gear_slots.keys():
		if RogueRun.gear_slots.get(slot) is Dictionary:
			worn_slot = String(slot)
			break
	_check(worn_slot == "weapon", "清风剑落到武器槽", worn_slot)
	var attr_after := float(CharacterData.attribute(attr_key))
	_check(attr_after > attr_before, "局内装备属性真的生效",
		"%s %.1f → %.1f" % [attr_key, attr_before, attr_after])
	_check(CharacterData.attribute_mods.has("rogue_gear"),
		"装备加成走独立 source rogue_gear（不会被 rebuild 抹掉）")
	RogueRun.unequip_gear("weapon")
	_check(RogueRun.gear_bag.size() == 2, "卸下后装备回到行囊", str(RogueRun.gear_bag.size()))
	_check(is_equal_approx(float(CharacterData.attribute(attr_key)), attr_before),
		"卸下后属性回落")

	# ===== 修为：击杀小怪 / BOSS 各一档，满自动突破 =====
	var exp_min := RogueDB.exp_for_minion(1, false)
	var exp_elite := RogueDB.exp_for_minion(1, true)
	var exp_boss := RogueDB.exp_for_boss(1)
	_check(exp_elite > exp_min and exp_boss > exp_elite,
		"小怪 < 精英 < BOSS 三档修为",
		"%.0f / %.0f / %.0f" % [exp_min, exp_elite, exp_boss])
	var dummy := Node2D.new()
	dummy.name = "Rogue_rogue_rat"
	add_child(dummy)
	var exp_before := RogueRun.realm_exp
	rogue.call("_grant_kill_exp", dummy, false)
	_check(RogueRun.realm_exp > exp_before, "击杀小怪确实给了修为",
		"%d → %d" % [exp_before, RogueRun.realm_exp])
	dummy.free()

	# 直接补到阈值，验自动突破 + 明显提示（HUD 高亮计时器）
	var need := RogueRun.stage_exp_required()
	RogueRun.realm_exp = 0
	var info := RogueRun.add_exp(float(need))
	_check(bool(info.get("broke", false)), "修为满自动突破（无需按钮）")
	_check(RogueRun.realm_title() == "练气中期", "境界推进到练气中期", RogueRun.realm_title())
	_check(RogueRun.breakthroughs == 1, "累计突破次数 +1")
	_check(CharacterData.attribute_mods.has("rogue_realm"),
		"境界加成走独立 source rogue_realm")
	var realm_mods: Dictionary = CharacterData.attribute_mods.get("rogue_realm", {})
	var has_pct := false
	for k in realm_mods.keys():
		if float((realm_mods[k] as Dictionary).get("base_pct", 0.0)) > 0.0:
			has_pct = true
	_check(has_pct, "突破后境界倍率写进属性修正（全属性提升）")
	_check(int(CharacterData.realm_exp) == 0 and int(CharacterData.realm_stage) == 0,
		"局外 realm_exp / realm_stage 一个字都没动")
	_check(String(CharacterData.current_realm) == "练气",
		"局外 current_realm 仍是练气（没被局内突破改写）")
	# 明显提示之一：HUD 境界行高亮计时器被点亮
	rogue.call("_announce_breakthrough", info)
	_check(float(rogue.get("_realm_flash")) > 0.0, "突破触发 HUD 高亮提示",
		str(rogue.get("_realm_flash")))

	# ===== 局外接口仍锁（之前那道隔离没被这次改动破坏）=====
	_check(bool(CharacterData.rogue_lock), "局外换装/突破锁仍在")
	_check((CharacterData.equip_from_inventory(0) as Dictionary).is_empty(),
		"局外换装接口仍拒绝")
	CharacterData.break_stage()
	_check(int(CharacterData.realm_stage) == 0, "局外突破接口仍拒绝")

	# ===== Tab 打开的是局内行囊，不是局外角色面板 =====
	CharacterPanel.call("_open_rogue_gear")
	await get_tree().process_frame
	var gear_panel: Node = CharacterPanel.get("_rogue_gear_panel")
	_check(gear_panel != null and is_instance_valid(gear_panel)
		and gear_panel is RogueGearPanel, "Tab 打开的是 RogueGearPanel（局内数据）")
	_check(CharacterPanel.get("_visible") == false,
		"局外角色面板没有被打开")
	if gear_panel != null and is_instance_valid(gear_panel):
		gear_panel.call("close")
		await get_tree().process_frame

	# ===== 出局：全部清空还原 =====
	RogueRun.restore()
	_check(not RogueRun.active, "收局 active=false")
	_check(RogueRun.gear_bag.is_empty() and RogueRun.gear_slots.is_empty(),
		"局内行囊与槽位清空（带不出局外）")
	_check(RogueRun.realm_title() == "练气前期" and RogueRun.breakthroughs == 0,
		"局内境界与突破次数归零")
	_check(not CharacterData.attribute_mods.has("rogue_gear")
		and not CharacterData.attribute_mods.has("rogue_realm"),
		"两个独立属性 source 已清除")
	_check(not bool(CharacterData.rogue_lock), "rogue_lock 已撤")
	_check(String(CharacterData.current_realm) == realm0
		and int(CharacterData.realm_stage) == stage0
		and int(CharacterData.realm_exp) == exp0,
		"局外境界/修为完整还原",
		"%s / %d / %d" % [CharacterData.current_realm, CharacterData.realm_stage, CharacterData.realm_exp])
	var eq_restored := true
	for slot in eq0.keys():
		var a = eq0.get(slot)
		var b = CharacterData.equipment_slots.get(slot)
		if (a is Dictionary) != (b is Dictionary):
			eq_restored = false
	_check(eq_restored, "局外装备槽完整还原（没被局内穿戴影响）")
	_check(CharacterData.inventory.size() == inv0
		and CharacterData.codex_unlocked.size() == codex0,
		"背包与图鉴最终零变化")

	arena.free()
