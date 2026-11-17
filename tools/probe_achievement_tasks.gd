extends Node
## 成就任务 · 卡面收集自检（2026-10-30）
## 用法：godot --headless --path . tools/probe_achievement_tasks.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _label_texts(root: Node) -> String:
	var parts := PackedStringArray()
	for n in root.find_children("*", "Label", true, false):
		parts.append((n as Label).text)
	return " ".join(parts)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 成就任务 · 卡面收集 ##########")
	get_tree().create_timer(15.0, true, false, true).timeout.connect(func() -> void:
		print("PROBE TIMEOUT")
		get_tree().quit(2))
	CharacterData.tower_progress.clear()
	CharacterData.tower_best_time.clear()
	CharacterData.tower_no_hit_double.clear()
	CharacterData.secret_world["core_kills"] = {}
	CharacterData.core_replay.clear()
	CharacterData.card_reward_claimed.clear()

	var entries := CodexDB.card_entries()
	_check(entries.size() >= 10, "卡面首领条目已登记", "n=%d" % entries.size())
	if entries.is_empty():
		get_tree().quit(1)
		return
	var first := entries[0] as Dictionary
	var first_id := String(first.get("id", ""))
	var floor_no := int(first.get("floor", 0))
	if floor_no > 0:
		CharacterData.tower_progress[floor_no] = {
			"unlocked": true, "first_kill": true,
			"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
		}
		CharacterData.tower_no_hit_double[floor_no] = true
		CharacterData.tower_best_time[floor_no] = 9.5
	else:
		var rid := String(first.get("world_region", ""))
		CharacterData.secret_world["core_kills"][rid] = true
		CharacterData.core_replay[rid] = {
			"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
			"no_hit_double": true,
			"best_time": 9.5,
		}

	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	view._show_page(AchievementView.PAGE_TASKS)
	await get_tree().process_frame

	var tasks := view.find_children("CardTask_*", "PanelContainer", true, false)
	_check(tasks.size() == entries.size(), "每位首领一条任务", "%d / %d" % [
		tasks.size(), entries.size()])
	var total_cards := 0
	for raw in entries:
		total_cards += (raw as Dictionary).get("card_variants", []).size()
	var expected := "已完成 1 / %d 位首领 · 4 / %d 张卡" % [entries.size(), total_cards]
	_check(view._summary.text.contains(expected), "任务页汇总进度", view._summary.text)

	var card := view.find_child("CardTask_%s" % first_id, true, false)
	_check(card != null, "已完成首领任务可定位", first_id)
	if card != null:
		for vid in ["portrait", "scene", "plain", "ink"]:
			var state := view.find_child("TaskState_%s_%s" % [first_id, vid], true, false)
			_check(state != null and (state as Label).text == "已获得",
				"%s 卡已获得" % vid, (state as Label).text if state != null else "missing")
		var scene_goal := view.find_child("TaskGoal_%s_scene" % first_id, true, false)
		var plain_goal := view.find_child("TaskGoal_%s_plain" % first_id, true, false)
		var ink_goal := view.find_child("TaskGoal_%s_ink" % first_id, true, false)
		_check(scene_goal != null and _label_texts(scene_goal).contains("第 11 次"),
			"华彩有背景写明第 11 次起")
		_check(plain_goal != null and _label_texts(plain_goal).contains("无伤"),
			"纯华彩写明无伤")
		_check(ink_goal != null and _label_texts(ink_goal).contains("10 秒"),
			"水墨卡写明 10 秒速通")
		var claim := view.find_child("TaskClaim_%s_scene" % first_id, true, false) as Button
		_check(claim != null and not claim.disabled, "华彩卡解锁后可领晶石")
		_check(view.find_child("TaskClaim_%s_portrait" % first_id, true, false) == null,
			"普通卡没有领奖按钮")
		if claim != null:
			var crystals_before := CharacterData.count_material(CharacterData.ENHANCE_MATERIAL)
			claim.pressed.emit()
			_check(CharacterData.count_material(CharacterData.ENHANCE_MATERIAL) \
				== crystals_before + CharacterData.CARD_UNLOCK_BONUS_CRYSTALS,
				"领一张非普通卡 +50 晶石")
			_check(CharacterData.is_card_reward_claimed(first_id, "scene"), "领奖状态已入账")
			_check(CharacterData.claim_card_reward(first_id, "scene") == 0,
				"同一张卡不能重复领")
			_check(claim.disabled and claim.text.contains("已领"), "按钮变为已领")

	if entries.size() > 1:
		var second_id := String((entries[1] as Dictionary).get("id", ""))
		var second_state := view.find_child("TaskState_%s_portrait" % second_id, true, false)
		_check(second_state != null and (second_state as Label).text == "未获得",
			"未解锁首领显示未获得", (second_state as Label).text if second_state != null else "missing")

	# 大陆核心：普通卡文案与区域位置
	var core_entry: Dictionary = {}
	for raw in entries:
		if String((raw as Dictionary).get("world_region", "")) != "":
			core_entry = raw as Dictionary
			break
	if not core_entry.is_empty():
		var core_id := String(core_entry.get("id", ""))
		var rid := String(core_entry.get("world_region", ""))
		CharacterData.secret_world["core_kills"][rid] = true
		CharacterData.core_replay[rid] = {
			"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
			"no_hit_double": true,
			"best_time": 9.5,
		}
		view.refresh()
		await get_tree().process_frame
		var core_card := view.find_child("CardTask_%s" % core_id, true, false)
		var core_goal := view.find_child("TaskGoal_%s_portrait" % core_id, true, false)
		_check(core_card != null and _label_texts(core_card).contains("区域核心重战"),
			"核心任务写明区域核心位置")
		_check(core_goal != null and _label_texts(core_goal).contains("大世界区域核心首领"),
			"核心普通卡写明击败核心")
		var core_state := view.find_child("TaskState_%s_scene" % core_id, true, false)
		_check(core_state != null and (core_state as Label).text == "已获得",
			"核心双倍气血卡已获得", (core_state as Label).text if core_state != null else "missing")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
