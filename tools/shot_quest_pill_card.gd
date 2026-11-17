extends Node
## 任务卡「使用一次丹药」的排版截图（**必须窗口化跑**）。
##
## 用法：godot --path . --resolution 1280x720 res://tools/shot_quest_pill_card.tscn -- --no-save
## 出图：output/quest_pill_card.png
##
## 为什么要拍：detail 从 26 字加到 64 字，说明卡会不会绕成五六行、把「收起」和进度条挤开，
## 光数字数判断不了（同一天在指引卡上已经栽过一次：66 字三行、58 字仍三行、45 字才两行）。

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 前 9 条做完 → 当前正好是第 10 条 q_use_pill（卡头显示 9/12）
	var done := {
		"q_kill_huyao": true, "q_enhance": true, "q_tower": true,
		"q_equip_skill": true, "q_break_realm": true, "q_boss_material": true,
		"q_rogue": true, "q_match": true, "q_brew_pill": true,
	}
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.quest_data = {"done": done}

	var realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = realm
	for i in 6:
		await get_tree().process_frame
	# 主城读档会把 quest_data 覆盖回来 → 在它之后重摆，并压住轮询别把现场滚走
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.quest_data = {"done": done}
	Quest.set("_poll_left", 99999.0)
	Quest.changed.emit()
	for i in 12:
		await get_tree().process_frame

	print("当前任务 = ", Quest.current_id())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://output/quest_pill_card.png")
	print("SHOT output/quest_pill_card.png")

	# 第 13 条（11-12 新增）：前 12 条做完 → 当前正好是练气区核心首领这条
	var done13 := {}
	for raw in QuestDB.QUESTS:
		var qid := String((raw as Dictionary).get("id", ""))
		if qid != "q_lianqi_core":
			done13[qid] = true
	CharacterData.quest_data = {"done": done13}
	Quest.changed.emit()
	for i in 8:
		await get_tree().process_frame
	print("当前任务 = ", Quest.current_id())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://output/quest_lianqi_core.png")
	print("SHOT output/quest_lianqi_core.png")
	get_tree().quit(0)
