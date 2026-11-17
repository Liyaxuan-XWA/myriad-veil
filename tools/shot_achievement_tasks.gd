extends Node
## 成就任务 · 卡面收集截图（2026-10-30）
## 用法：godot --path . --resolution 1600x900 res://tools/shot_achievement_tasks.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CharacterData.tower_progress.clear()
	CharacterData.tower_best_time.clear()
	CharacterData.tower_no_hit_double.clear()
	CharacterData.secret_world["core_kills"] = {}
	CharacterData.core_replay.clear()
	CharacterData.card_reward_claimed.clear()

	var entries := CodexDB.card_entries()
	if entries.size() > 0:
		var first := entries[0] as Dictionary
		var f1 := int(first.get("floor", 0))
		if f1 > 0:
			CharacterData.tower_progress[f1] = {
				"unlocked": true, "first_kill": true,
				"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
			}
			CharacterData.tower_no_hit_double[f1] = true
			CharacterData.tower_best_time[f1] = 9.0
	if entries.size() > 1:
		var second := entries[1] as Dictionary
		var f2 := int(second.get("floor", 0))
		if f2 > 0:
			CharacterData.tower_progress[f2] = {
				"unlocked": true, "first_kill": true, "clear_count": 1,
			}
	if entries.size() > 2:
		var third := entries[2] as Dictionary
		var f3 := int(third.get("floor", 0))
		if f3 > 0:
			CharacterData.tower_progress[f3] = {
				"unlocked": true, "first_kill": true,
				"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
			}
			CharacterData.tower_best_time[f3] = 9.0

	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	view._show_page(AchievementView.PAGE_TASKS)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/achievement_tasks.png")
	print("SHOT output/achievement_tasks.png  ", img.get_width(), "x", img.get_height())
	get_tree().quit()
