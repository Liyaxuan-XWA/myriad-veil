extends Node
## 试炼之路 · 模式隔离自检（2026-11-08 用户报「局内还能开背包换装 / 突破」）
## 覆盖：进局上锁、修为归零、面板打不开、换装 / 卸装被拒、小阶段与大境界突破被拒、
##       战斗轮盘关闭、出局后真实数据（境界 / 修为 / 装备槽 / 锁）原样还原。
## 用法：godot --headless --path . res://tools/probe_rogue_isolation.tscn -- --no-save

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
	await get_tree().process_frame
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# 造一份「真实档」：练气前期、修为早就涨满了（用户截图里就是 87040 / 1000）
	CharacterData.current_realm = "练气"
	CharacterData.realm_stage = 0
	CharacterData.realm_exp = 87040
	var stage_before := CharacterData.realm_stage
	var realm_before := String(CharacterData.current_realm)
	var exp_before := CharacterData.realm_exp
	var slots_before := CharacterData.equipment_slots.duplicate(true)

	# ===== 进局 =====
	RogueRun.start_run("sword")
	_check(bool(CharacterData.rogue_lock), "进局上互斥锁", "rogue_lock=%s" % str(CharacterData.rogue_lock))
	_check(CharacterData.realm_exp == 0, "局内修为归零（面板不再显示真实档的 87040/1000）",
		str(CharacterData.realm_exp))
	_check(String(CharacterData.current_realm) == "练气", "局内境界为练气",
		String(CharacterData.current_realm))

	# ===== 面板入口 =====
	CharacterPanel.open_panel()
	_check(not CharacterPanel.is_open(), "试炼中 Tab / HUD 背包打不开",
		"is_open=%s" % str(CharacterPanel.is_open()))
	CharacterPanel.toggle_panel()
	_check(not CharacterPanel.is_open(), "试炼中 toggle_panel 同样拒绝",
		"is_open=%s" % str(CharacterPanel.is_open()))

	# ===== 换装（数据层保险）=====
	CharacterData.equip_block_reason = ""
	CharacterData.equip_from_inventory(0)
	_check(String(CharacterData.equip_block_reason).contains("试炼"),
		"试炼中换装被拒", CharacterData.equip_block_reason)
	_check(not CharacterData.unequip_to_inventory("weapon"), "试炼中卸装被拒", "")
	_check(not CharacterData.unequip_treasure_to_inventory("treasure_1"), "试炼中卸法宝被拒", "")

	# ===== 突破 =====
	CharacterData.break_stage()
	_check(CharacterData.realm_stage == stage_before, "试炼中小阶段突破被拒",
		"stage=%d" % CharacterData.realm_stage)
	CharacterData.break_realm("筑基")
	_check(String(CharacterData.current_realm) == realm_before, "试炼中大境界突破被拒",
		String(CharacterData.current_realm))
	_check(not CharacterData.perform_huashen_breakthrough(), "试炼中化神坛突破被拒", "")

	# ===== 战斗轮盘 =====
	_check(not BattleWheel._can_open(), "试炼中战斗轮盘关闭（不消耗主模式丹药符箓）", "")

	# ===== 出局还原 =====
	RogueRun.restore()
	_check(not bool(CharacterData.rogue_lock), "出局撤锁", "rogue_lock=%s" % str(CharacterData.rogue_lock))
	_check(CharacterData.realm_exp == exp_before, "出局修为原样还原",
		"%d（应为 %d）" % [CharacterData.realm_exp, exp_before])
	_check(CharacterData.realm_stage == stage_before, "出局小阶段还原",
		str(CharacterData.realm_stage))
	_check(String(CharacterData.current_realm) == realm_before, "出局境界还原",
		String(CharacterData.current_realm))
	# 整槽内容比较（不是「两件装备是否同一件」的判定，这里要的就是内容相等）
	_check(CharacterData.equipment_slots == slots_before, "出局装备槽还原", "")

	# ===== 出局后一切恢复可用 =====
	_check(not CharacterData.rogue_lock, "出局后换装不再被拦（锁已撤）",
		"rogue_lock=%s" % str(CharacterData.rogue_lock))
	CharacterPanel.close_panel()
