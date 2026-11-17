extends Node
## 万界塔右侧「本层掉落」：名称 / 数量 / 概率 / 元魂条件（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_tower_drops.tscn -- --no-save

const FLOOR := 1

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _rows_text(rows: Node) -> Array:
	var out: Array = []
	for row in rows.get_children():
		var name_lbl := row.get_child(0) as Label
		var pct_lbl := row.get_child(1) as Label
		out.append([name_lbl.text if name_lbl != null else "",
			pct_lbl.text if pct_lbl != null else ""])
	return out


func _ready() -> void:
	print("\n########## 万界塔 · 本层掉落 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	# ===== 1. 数据源 =====
	_check(ItemDB.tower_crystal_count(1) == 9 and ItemDB.tower_crystal_count(2) == 6
			and ItemDB.tower_crystal_count(3) == 3,
		"晶石档位 9 / 6 / 3", "%d/%d/%d" % [ItemDB.tower_crystal_count(1),
			ItemDB.tower_crystal_count(2), ItemDB.tower_crystal_count(3)])
	var d1: Array = ItemDB.get_tower_drops(FLOOR, 1)
	_check(d1.size() == 1 and String((d1[0] as Dictionary).get("item_id", ""))
			== CharacterData.ENHANCE_MATERIAL and int((d1[0] as Dictionary).get("count", 0)) == 9,
		"第 1 次通关：锻造晶石 ×9", str(d1))
	_check(is_equal_approx(ItemDB.get_drop_chance(d1[0] as Dictionary), 1.0),
		"锻造晶石 100%", str(ItemDB.get_drop_chance(d1[0] as Dictionary)))
	_check(is_equal_approx(ItemDB.TOWER_YUNXIAN_DROP_CHANCE, 0.05),
		"塔 BOSS 蕴仙髓 5%", str(ItemDB.TOWER_YUNXIAN_DROP_CHANCE))
	_check(is_equal_approx(ItemDB.TOWER_SOUL_DROP_CHANCE, 0.5),
		"双倍血量元魂 50%", str(ItemDB.TOWER_SOUL_DROP_CHANCE))
	var soul := ItemDB.soul_for_boss("boss_huyao")
	_check(String(soul.get("name", "")) == "虎妖元魂", "1 层元魂名称", String(soul.get("name", "")))
	_check(is_equal_approx(CharacterData.tower_hp_multiplier_at(10), 1.9)
			and is_equal_approx(CharacterData.tower_hp_multiplier_at(11), 2.0),
		"元魂按刚打完那场的倍率：第 10 次 1.9 / 第 11 次 2.0",
		"%.1f / %.1f" % [CharacterData.tower_hp_multiplier_at(10),
			CharacterData.tower_hp_multiplier_at(11)])
	var arena_src := FileAccess.get_file_as_string("res://scripts/combat/combat_arena.gd")
	_check(arena_src.contains("tower_hp_multiplier_at(clear_index)"),
		"塔掉落用该场开打时的倍率判定元魂")
	var boss_drops: Array = ItemDB.get_drops_for_boss("boss_huyao")
	_check(boss_drops.size() == 3, "虎妖本体掉落 3 条", str(boss_drops))
	if boss_drops.size() == 3:
		_check(is_equal_approx(ItemDB.get_drop_chance(boss_drops[0] as Dictionary), 0.5)
				and is_equal_approx(ItemDB.get_drop_chance(boss_drops[1] as Dictionary), 0.5)
				and is_equal_approx(ItemDB.get_drop_chance(boss_drops[2] as Dictionary), 0.2),
			"本体装备默认 50% / 材料 20%", "%s/%s/%s" % [
				ItemDB.get_drop_chance(boss_drops[0] as Dictionary),
				ItemDB.get_drop_chance(boss_drops[1] as Dictionary),
				ItemDB.get_drop_chance(boss_drops[2] as Dictionary)])

	# ===== 2. 面板：通关 1 次 → 下一战第 2 次 =====
	CharacterData.tower_progress[FLOOR] = {"unlocked": true, "first_kill": true,
		"clear_count": 1}
	var panel := TowerPanel.new()
	add_child(panel)
	await _frames(3)
	panel.call("open")
	await _frames(6)
	panel.call("_select_floor", FLOOR)
	await _frames(4)
	var box: Control = panel.get("_detail_drop_box")
	var rows: Node = panel.get("_detail_drop_rows")
	var hint: Label = panel.get("_detail_drop_hint")
	var note: Label = panel.get("_detail_drop_note")
	_check(box != null and box.visible, "本层掉落段可见")
	_check(hint != null and hint.text == "按第 2 次通关", "标题右侧写下次通关次数", hint.text)
	var r1 := _rows_text(rows)
	_check(r1.size() == 5, "普通场次 5 行掉落（本体 3 + 塔 2）", str(r1))
	if r1.size() >= 5:
		_check(r1[0][0] == "虎皮袍 ×1" and r1[0][1] == "50%",
			"本体装备 1：虎皮袍 50%", str(r1[0]))
		_check(r1[1][0] == "虎牙项链 ×1" and r1[1][1] == "50%",
			"本体装备 2：虎牙项链 50%", str(r1[1]))
		_check(r1[2][0] == "界门虎牙 ×1" and r1[2][1] == "20%",
			"本体材料：界门虎牙 20%", str(r1[2]))
		_check(r1[3][0] == "锻造晶石 ×6" and r1[3][1] == "100%",
			"晶石数量按第 2 次档位 + 100%", str(r1[3]))
		_check(r1[4][0] == "蕴仙髓 ×1" and r1[4][1] == "5%",
			"蕴仙髓 5%", str(r1[4]))
	_check(note != null and note.visible and note.text.contains("第 11 次起")
			and note.text.contains("虎妖元魂") and note.text.contains("50%"),
		"普通场次预告双倍血量元魂", note.text)

	# ===== 3. 通关 10 次 → 下一战第 11 次（双倍血量） =====
	CharacterData.tower_progress[FLOOR]["clear_count"] = 10
	panel.call("_refresh_detail")
	await _frames(3)
	_check(hint.text == "按第 11 次通关", "双倍场次标题次数", hint.text)
	var r2 := _rows_text(rows)
	_check(r2.size() == 6, "双倍场次多出元魂行（本体 3 + 塔 2 + 元魂）", str(r2))
	if r2.size() >= 6:
		_check(r2[3][0] == "锻造晶石 ×3" and r2[3][1] == "100%",
			"第 11 次晶石回到 3 块", str(r2[3]))
		_check(r2[5][0] == "虎妖元魂 ×1（双倍）" and r2[5][1] == "50%",
			"双倍场次元魂 50% 且行内标注", str(r2[5]))
	_check(not note.visible, "双倍场次不再重复预告注")

	# ===== 4. 区域核心分支：本层掉落段收起，避免和「重战掉落」重复 =====
	panel.set("_selected_core", SecretWorldDB.REGION_LIANQI)
	panel.call("_refresh_core_detail")
	await _frames(3)
	_check(not box.visible, "核心重战详情收起塔层掉落段")
	panel.call("close")
	await _frames(2)
