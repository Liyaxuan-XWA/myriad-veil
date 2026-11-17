extends Node
## 位面法宝材料全链路自检（2026-11-07）：
##   「12 只 BOSS 真实掉落 → 落地拾取 → 入永久背包 → 四套配方各自合成入包」
## ⚠ 故意从真实入口 ItemDB.roll_boss_drops 采样，而不是只查 DROP_TEMPLATES 表登记：
##   项目踩过坑 —— 分档表里登记了，运行时却读的是写死的基准表（野修法宝池）。
## ⚠ 会清背包，必须带 -- --no-save，防止主城自动存档覆盖真实玩家档。
## 用法：godot --headless --path . res://tools/probe_plane_treasure_pipeline.tscn -- --no-save

const SAMPLES := 400

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _material_entry(boss_id: String) -> Dictionary:
	for raw in ItemDB.get_drops_for_boss(boss_id):
		var d: Dictionary = raw
		if String(d.get("kind", "")) == "material":
			return d
	return {}


func _has_item(item_id: String) -> bool:
	for raw in CharacterData.inventory:
		var it: Dictionary = raw
		if String(it.get("id", "")) == item_id:
			return true
	return false


func _item_index(item_id: String) -> int:
	for i in CharacterData.inventory.size():
		var it: Dictionary = CharacterData.inventory[i]
		if String(it.get("id", "")) == item_id:
			return i
	return -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 位面材料掉落 → 合成全链路探针 ##########")
	_check(ItemDB.PLANE_TREASURE_RECIPES.size() == 4, "四个位面各有一条配方",
		"n=%d" % ItemDB.PLANE_TREASURE_RECIPES.size())
	await _check_drop_pipeline()
	await _check_synth_pipeline()
	await _check_close_during_melt()
	await _check_cross_domain_reject()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


## 一、12 只 BOSS：从真实掉落入口采样，确认各自材料能掉出来、能捡进永久背包
func _check_drop_pipeline() -> void:
	for raw_dom in WorldDB.DOMAINS:
		var dom: Dictionary = raw_dom
		var did := String(dom.get("domain_id", ""))
		var recipe := ItemDB.get_plane_treasure_recipe(did)
		_check(not recipe.is_empty(), did + " 配方已登记")
		var need: Array = recipe.get("material_ids", [])
		var boss_ids: Array = dom.get("boss_ids", [])
		_check(boss_ids.size() == 3 and need.size() == 3,
			did + " 三只 BOSS / 三件材料", "boss=%d mat=%d" % [boss_ids.size(), need.size()])
		var dropped: Array = []
		for raw_bid in boss_ids:
			var bid := String(raw_bid)
			var entry := _material_entry(bid)
			_check(not entry.is_empty(), bid + " 掉落表登记了材料条目")
			if entry.is_empty():
				continue
			var mid := String(entry.get("item_id", ""))
			dropped.append(mid)
			_check(need.has(mid), bid + " 掉落材料属于本位面配方", mid)
			_check(not ItemDB.get_material(mid).is_empty(),
				bid + " 材料在 MATERIALS 有定义", mid)

			# 真实入口采样：不能只看表里有 id
			var hits := 0
			var equip_hits := 0
			var bad_structure := 0
			for i in SAMPLES:
				var drops: Array = ItemDB.roll_boss_drops(bid)
				for raw_d in drops:
					var d: Dictionary = raw_d
					var item: Dictionary = d.get("item", {})
					if item.is_empty() or String(item.get("id", "")) == "":
						bad_structure += 1
						continue
					if String(d.get("material_id", "")) == mid:
						hits += 1
						# 结算文案读顶层 count，拾取读 item.count：两者必须一致
						if int(d.get("count", 1)) != int(item.get("count", 1)):
							bad_structure += 1
					else:
						equip_hits += 1
			var ratio := float(hits) / float(SAMPLES)
			_check(hits > 0 and ratio > 0.10 and ratio < 0.32,
				bid + " 真实掉出 " + mid, "%d/%d = %.1f%%" % [hits, SAMPLES, ratio * 100.0])
			_check(equip_hits > 0, bid + " 装备掉落未被材料挤掉", "n=%d" % equip_hits)
			_check(bad_structure == 0, bid + " 掉落结构合法（结算数量 = 实得数量）",
				"bad=%d" % bad_structure)

			# 掉落物按 F 拾取后走 CharacterData.add_item，必须进永久背包
			CharacterData.inventory.clear()
			var got := false
			for i in 200:
				var drops2: Array = ItemDB.roll_boss_drops(bid)
				for raw_d in drops2:
					var d2: Dictionary = raw_d
					if String(d2.get("material_id", "")) == mid:
						got = CharacterData.add_item(d2.get("item", {}))
						break
				if got:
					break
			_check(got and CharacterData.count_material(mid) >= 1,
				bid + " 材料拾取后进永久背包", "count=%d" % CharacterData.count_material(mid))
		var sorted_drop := dropped.duplicate()
		sorted_drop.sort()
		var sorted_need := need.duplicate()
		sorted_need.sort()
		_check(sorted_drop == sorted_need, did + " 三只 BOSS 恰好凑齐配方三件",
			str(sorted_drop))


## 二、四条配方各自走锻造台真实合成：乱序投入 → 扣料 → 产物入包 → 可装备
func _check_synth_pipeline() -> void:
	for raw_r in ItemDB.PLANE_TREASURE_RECIPES:
		var recipe: Dictionary = raw_r
		var did := String(recipe.get("domain_id", ""))
		var rid := String(recipe.get("result_id", ""))
		var need: Array = recipe.get("material_ids", [])
		CharacterData.inventory.clear()
		for raw_mid in need:
			# 与 roll_boss_drops 的 material 分支同源，保证给的是真掉落物结构
			var drop := ItemDB.make_material_drop(String(raw_mid))
			CharacterData.add_item(drop.get("item", {}))
		var all_in := true
		for raw_mid in need:
			if CharacterData.count_material(String(raw_mid)) < 1:
				all_in = false
		_check(all_in, did + " 三件材料已在背包")

		var tpl := ItemDB.get_treasure_template(rid)
		_check(not tpl.is_empty(), did + " 产物模板已登记 " + rid)
		var panel := ForgePanel.new()
		add_child(panel)
		await get_tree().process_frame
		await get_tree().process_frame
		var candidates: Array = panel._synth_candidates()
		_check(candidates.size() == 3, did + " 锻造台列出三件候选",
			"n=%d" % candidates.size())
		if candidates.size() >= 3:
			# 乱序投入：证明按集合匹配而非按槽位
			panel._on_synth_pick(0, candidates[2])
			panel._on_synth_pick(1, candidates[0])
			panel._on_synth_pick(2, candidates[1])
		_check(not panel._matched_plane_recipe().is_empty(), did + " 乱序投入识别配方")
		_check(panel._synth_block_reason() == "", did + " 无合成拦截",
			panel._synth_block_reason())
		await panel._try_synthesize()
		var consumed := true
		for raw_mid in need:
			if CharacterData.count_material(String(raw_mid)) != 0:
				consumed = false
		_check(consumed, did + " 合成后三件材料清零")
		_check(_has_item(rid), did + " 产物 " + rid + " 已入包")

		var idx := _item_index(rid)
		if idx >= 0:
			var equipped := CharacterData.equip_treasure_from_inventory(idx, "treasure_1")
			_check(bool(equipped.get("ok", false)), did + " 产物可装备到法宝槽")
			var stats := ItemDB.treasure_active_stats(
				CharacterData.get_equipped("treasure_1"), tpl)
			_check(not stats.is_empty(), did + " 产物主动数值可读",
				String(stats.get("kind", "")))
			CharacterData.unequip_treasure_to_inventory("treasure_1")
		else:
			_check(false, did + " 产物可装备到法宝槽", "产物未入包")
		remove_child(panel)
		panel.free()


## 三、合成动画期间关闭面板：材料已扣，产物绝不能凭空消失
func _check_close_during_melt() -> void:
	var recipe := ItemDB.get_plane_treasure_recipe("domain_01")
	var rid := String(recipe.get("result_id", ""))
	CharacterData.inventory.clear()
	for raw_mid in recipe.get("material_ids", []):
		var drop := ItemDB.make_material_drop(String(raw_mid))
		CharacterData.add_item(drop.get("item", {}))
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var candidates: Array = panel._synth_candidates()
	if candidates.size() >= 3:
		for slot in 3:
			panel._on_synth_pick(slot, candidates[slot])
	# 故意不 await：协程停在 _run_synthesis 的 1.15 秒炉火动画上
	panel._try_synthesize()
	remove_child(panel)
	await get_tree().create_timer(1.4, true).timeout
	_check(_has_item(rid), "合成动画期间关闭面板，产物仍入包（不吞材料）")
	panel.free()


## 四、跨位面混投必须被拦，且不能白扣材料
func _check_cross_domain_reject() -> void:
	CharacterData.inventory.clear()
	var picks: Array = []
	for raw_r in ItemDB.PLANE_TREASURE_RECIPES:
		var recipe: Dictionary = raw_r
		var ids: Array = recipe.get("material_ids", [])
		if not ids.is_empty():
			picks.append(String(ids[0]))
	if picks.size() < 3:
		_check(false, "跨位面混投样本可用")
		return
	for i in 3:
		var drop := ItemDB.make_material_drop(String(picks[i]))
		CharacterData.add_item(drop.get("item", {}))
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var candidates: Array = panel._synth_candidates()
	if candidates.size() >= 3:
		for slot in 3:
			panel._on_synth_pick(slot, candidates[slot])
	_check(panel._matched_plane_recipe().is_empty(), "跨位面混投不识别为配方")
	await panel._try_synthesize()
	var kept := true
	for i in 3:
		if CharacterData.count_material(String(picks[i])) != 1:
			kept = false
	_check(kept, "跨位面混投被拦时材料不损失")
	remove_child(panel)
	panel.free()
