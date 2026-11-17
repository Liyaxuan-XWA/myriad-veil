extends Node
## 位面法宝合成自检（2026-10-29）：
##   三件材料**任意顺序**投入 → 自动识别位面法宝 → 太极盘入包，材料消耗；
##   回归：元魂 + 破损装备（同样不看槽位顺序）仍能合成召唤法宝。
## 用法：godot --headless --path . res://tools/probe_plane_treasure_synth.tscn

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _find_kind(entries: Array, kind: String) -> Dictionary:
	for raw in entries:
		var d: Dictionary = raw
		if String(d.get("kind", "")) == kind:
			return d
	return {}


func _has_button_text(node: Node, text: String) -> bool:
	if node == null:
		return false
	if node is Button and String((node as Button).text) == text:
		return true
	for c in node.get_children():
		if _has_button_text(c, text):
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 位面法宝合成探针 ##########")
	var recipe := ItemDB.get_plane_treasure_recipe("domain_02")
	_check(not recipe.is_empty(), "冲和界位面法宝配方存在")
	_check(String(recipe.get("result_id", "")) == "tr_taiji_pan", "产物 = 太极盘")
	var ids: Array = recipe.get("material_ids", [])
	_check(ids.size() == 3, "配方需要三件材料", str(ids))
	var tpl := ItemDB.get_treasure_template("tr_taiji_pan")
	_check(not tpl.is_empty() and String(tpl.get("active_type", "")) == "taiji_guard",
		"太极盘主动效果已登记")

	CharacterData.inventory.clear()
	for mid in ids:
		CharacterData.grant_material(String(mid), 1)
	_check(CharacterData.count_material(String(ids[0])) == 1, "测试材料已入包")

	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var candidates: Array = panel._synth_candidates()
	_check(candidates.size() == 3, "未切模式也能列出三件位面材料", "n=%d" % candidates.size())
	# 反向顺序放入三个槽：2 → 0 → 1，证明不看顺序
	var pick_order: Array = [2, 0, 1]
	if candidates.size() >= 3:
		for slot in 3:
			panel._on_synth_pick(slot, candidates[pick_order[slot]])
	_check(candidates.size() >= 3 and not panel._matched_plane_recipe().is_empty(),
		"三件材料自动识别为位面配方")
	_check(panel._synth_block_reason() == "", "乱序放入也可以合成",
		panel._synth_block_reason())
	_check(panel._melt_button.text == "合成法宝", "按钮切到合成法宝", panel._melt_button.text)
	panel._show_candidates(0)
	_check(_has_button_text(panel._candidate_layer, "取出"), "已投入的格子可以取出材料")
	panel._close_candidates()

	await panel._try_synthesize()
	_check(CharacterData.count_material(String(ids[0])) == 0
		and CharacterData.count_material(String(ids[1])) == 0
		and CharacterData.count_material(String(ids[2])) == 0,
		"三件材料各消耗 1")
	var has_treasure := false
	for it in CharacterData.inventory:
		if String((it as Dictionary).get("id", "")) == "tr_taiji_pan":
			has_treasure = true
			break
	_check(has_treasure, "太极盘已入包")
	var treasure_idx := -1
	for i in CharacterData.inventory.size():
		if String((CharacterData.inventory[i] as Dictionary).get("id", "")) == "tr_taiji_pan":
			treasure_idx = i
			break
	var equipped := {}
	if treasure_idx >= 0:
		equipped = CharacterData.equip_treasure_from_inventory(treasure_idx, "treasure_1")
	_check(bool(equipped.get("ok", false)), "太极盘可以装备到法宝槽")
	var active := ItemDB.treasure_active_stats(CharacterData.get_equipped("treasure_1"))
	_check(String(active.get("kind", "")) == "taiji_guard", "太极护体主动可读",
		String(active.get("kind", "")))
	CharacterData.unequip_treasure_to_inventory("treasure_1")
	_check(panel._synth_slot_data[0].is_empty() and panel._synth_slot_data[1].is_empty()
		and panel._synth_slot_data[2].is_empty(), "合成后投入口清空")

	# 回归：原有「元魂 + 破损装备 → 召唤法宝」仍可合成，且顺序颠倒也认
	CharacterData.grant_material("soul_huyao", 1)
	var equip_ids := ItemDB.get_boss_equipment_ids("boss_huyao")
	var broken_tpl := ItemDB.get_equipment_template(String(equip_ids[0])) if not equip_ids.is_empty() else {}
	_check(not broken_tpl.is_empty(), "虎妖装备模板可读")
	if not broken_tpl.is_empty():
		var broken := CharacterData.make_equipment_instance(broken_tpl)
		broken["is_broken"] = true
		CharacterData.add_item(broken)
	var all_rows: Array = panel._synth_candidates()
	var soul := _find_kind(all_rows, "soul")
	var equip := _find_kind(all_rows, "equip")
	_check(not soul.is_empty() and not equip.is_empty(), "召唤配方候选可用",
		"souls=%d equips=%d" % [int(not soul.is_empty()), int(not equip.is_empty())])
	if not soul.is_empty() and not equip.is_empty():
		# 元魂放第 3 口、装备放第 1 口
		panel._on_synth_pick(2, soul)
		panel._on_synth_pick(0, equip)
		_check(panel._synth_block_reason() == "", "召唤配方不分顺序成立",
			panel._synth_block_reason())
		_check(panel._melt_button.text == "熔铸", "召唤配方按钮仍为熔铸", panel._melt_button.text)
		await panel._try_synthesize()
		var has_summon := false
		for it in CharacterData.inventory:
			if String((it as Dictionary).get("id", "")) == "tr_huyao_ling":
				has_summon = true
				break
		_check(has_summon, "召唤法宝仍可合成")
		_check(panel._synth_slot_data[0].is_empty() and panel._synth_slot_data[1].is_empty()
			and panel._synth_slot_data[2].is_empty(), "召唤合成后投入口清空")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
