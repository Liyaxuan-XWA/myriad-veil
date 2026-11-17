extends Node
## 万界塔区域首领分支自检（2026-10-30）：
##   核心已击杀 → 塔面板出现分支节点；分支节点 → 战斗箱庭加载 WorldEnemy 核心；
##   重战胜利 → 掉装备 + 锻造晶石；每胜一次血量 +10%（2 倍封顶）；
##   双倍血取胜解锁华彩卡，双倍血无伤解锁纯华彩卡；首次无伤 +50 晶石。
## 用法：godot --headless --path . res://tools/probe_tower_core_branch.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _has_branch_button(root: Node) -> bool:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b != null and b.tooltip_text.contains("重战"):
			return true
	return false


func _branch_tooltip(root: Node) -> String:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b != null and b.tooltip_text.contains("分支节点"):
			return b.tooltip_text
	return ""


func _drop_ids(arena: Node) -> Array:
	var out: Array = []
	for raw in arena._drops_on_ground:
		if raw is Node:
			var item = raw.get("item")
			if item is Dictionary:
				out.append(String((item as Dictionary).get("id", "")))
	return out


func _make_arena() -> Node:
	BattleResolver.skip_next_intro = true
	var arena = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	return arena


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 万界塔区域首领分支探针 ##########")
	CharacterData.secret_world["core_kills"] = {"world_lianqi": true}
	CharacterData.core_replay = {}

	# 1. 数据映射
	_check(WorldDB.get_domain_id_for_realm("练气") == "domain_01", "练气 → 凡界")
	_check(SecretWorldDB.get_core_boss("world_lianqi").get("name", "") == "青岚古猿",
		"核心配置可读")
	_check(CharacterData.is_core_killed("world_lianqi"), "核心击杀状态可读")
	_check(is_equal_approx(CharacterData.core_hp_multiplier("world_lianqi"), 1.0),
		"首次重战基础血量")
	CharacterData.core_replay["world_lianqi"] = {"clear_count": 10}
	_check(is_equal_approx(CharacterData.core_hp_multiplier("world_lianqi"), 2.0),
		"胜 10 次后下一次 2 倍血")
	CharacterData.core_replay = {}

	# 2. 塔面板出现分支节点 + 未击杀时隐藏
	var panel := TowerPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_has_branch_button(panel), "塔面板出现区域首领分支节点")
	panel.close()
	await get_tree().process_frame

	CharacterData.secret_world["core_kills"] = {}
	var panel2 := TowerPanel.new()
	add_child(panel2)
	await get_tree().process_frame
	await get_tree().process_frame
	panel2.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _has_branch_button(panel2), "未击杀时不出现分支节点")
	panel2.close()
	await get_tree().process_frame
	CharacterData.secret_world["core_kills"] = {"world_lianqi": true}

	# 3. 首次重战：核心首领 + 重战标题 + 装备 + 晶石 + 首次无伤 50
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_WORLD_CORE,
		"region_id": "world_lianqi",
		"boss_id": "world_core_lianqi",
	}
	var crystals_before: int = CharacterData.count_material("mat_duanzaojingshi")
	var arena = _make_arena()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var boss = arena.boss
	_check(boss is WorldEnemy, "战斗箱庭加载 WorldEnemy")
	_check(boss != null and boss.enemy_kind == WorldEnemy.KIND_CORE, "核心首领类型")
	_check(boss != null and is_equal_approx(float(boss.max_hp), 2200.0),
		"首次重战气血 2200", str(boss.max_hp) if boss != null else "null")
	_check(boss != null and bool(boss.standalone), "重战模式标记")
	_check(String(arena.get_node("HUD/BattleTitleLabel").text).contains("重战"),
		"战斗标题写明重战", arena.get_node("HUD/BattleTitleLabel").text)
	if boss != null:
		boss.set_physics_process(false)
		boss.set_process(false)
	await get_tree().process_frame
	boss.call("_die")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bool(arena._cleared), "重战胜利进入结算")
	var ids := _drop_ids(arena)
	_check(ids.has("eq_tengjia"), "掉落为核心装备藤甲", str(ids))
	var crystal_drops := 0
	for iid in ids:
		if String(iid) == "mat_duanzaojingshi":
			crystal_drops += 1
	_check(crystal_drops == 9, "首次重战掉落 9 块晶石", "n=%d" % crystal_drops)
	_check(CharacterData.get_core_clear_count("world_lianqi") == 1, "重战次数记 1")
	var crystals_after: int = CharacterData.count_material("mat_duanzaojingshi")
	_check(crystals_after - crystals_before == CharacterData.TOWER_NO_HIT_BONUS_CRYSTALS,
		"首次无伤 +50 晶石", "delta=%d" % (crystals_after - crystals_before))
	_check(CharacterData.core_no_hit_rewarded("world_lianqi"), "无伤奖励已标记")
	var core_card := CodexDB.card_entry("world_core_lianqi")
	_check(not bool(core_card.get("double_cleared", true)),
		"1 胜时华彩卡仍锁", str(core_card.get("double_cleared")))
	_check(not bool(core_card.get("perfect_cleared", true)),
		"1 胜时纯华彩卡仍锁", str(core_card.get("perfect_cleared")))
	arena.queue_free()
	await get_tree().process_frame

	# 4. 双倍血重战：血量 4400 + 第 11 次标题 + 双倍卡 / 纯华彩卡解锁
	CharacterData.core_replay["world_lianqi"]["clear_count"] = 10
	var arena2 = _make_arena()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var boss2 = arena2.boss
	_check(boss2 != null and is_equal_approx(float(boss2.max_hp), 4400.0),
		"第 11 次重战双倍血 4400", str(boss2.max_hp) if boss2 != null else "null")
	_check(String(arena2.get_node("HUD/BattleTitleLabel").text).contains("第 11 次"),
		"战斗标题写第 11 次", arena2.get_node("HUD/BattleTitleLabel").text)
	if boss2 != null:
		boss2.set_physics_process(false)
		boss2.set_process(false)
	arena2._elapsed = 9.0
	await get_tree().process_frame
	boss2.call("_die")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(CharacterData.get_core_clear_count("world_lianqi") == 11, "重战次数记到 11")
	var ids2 := _drop_ids(arena2)
	var crystal_drops2 := 0
	for iid in ids2:
		if String(iid) == "mat_duanzaojingshi":
			crystal_drops2 += 1
	_check(crystal_drops2 == 3, "重复重战掉落 3 块晶石", "n=%d" % crystal_drops2)
	var crystals_after2: int = CharacterData.count_material("mat_duanzaojingshi")
	_check(crystals_after2 == crystals_after, "无伤奖励每区只发一次",
		"before=%d after=%d" % [crystals_after, crystals_after2])
	var card2 := CodexDB.card_entry("world_core_lianqi")
	_check(bool(card2.get("double_cleared", false)), "双倍血取胜解锁华彩卡")
	_check(bool(card2.get("perfect_cleared", false)), "双倍血无伤解锁纯华彩卡")
	_check(bool(card2.get("ink_cleared", false)), "双倍血 9 秒通关解锁水墨")
	_check(int(card2.get("card_collected", 0)) == 4, "首领四张卡都亮",
		str(card2.get("card_collected")))

	# 5. 分支节点显示重战次数
	var panel3 := TowerPanel.new()
	add_child(panel3)
	await get_tree().process_frame
	await get_tree().process_frame
	panel3.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var tip := _branch_tooltip(panel3)
	_check(tip.contains("已重战 ×11") and tip.contains("封顶"), "分支节点显示次数与血量",
		tip.replace("\n", " | "))
	panel3.close()
	arena2.queue_free()
	await get_tree().process_frame

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
