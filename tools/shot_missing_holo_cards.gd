extends Node
## 离照 / 晏无咎三卡实机观感截图（2026-10-30）
## 用法：godot --path . --windowed --resolution 1600x900 tools/shot_missing_holo_cards.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _still(view: AchievementView) -> void:
	for h in view.find_children("*", "HoloCardView", true, false):
		(h as HoloCardView).set_view_speed_immediate(Vector2.ZERO)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for f in [8, 9]:
		CharacterData.tower_progress[f] = {
			"unlocked": true, "first_kill": true,
			"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
		}
		CharacterData.tower_no_hit_double[f] = true
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view

	for boss_id in ["boss_03_b", "boss_03_c"]:
		view.open_boss(String(boss_id))
		await get_tree().create_timer(1.0, true, false, true).timeout
		_still(view)
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _shot("achievement_pack_%s_spread.png" % String(boss_id))
		view.open_card(0)
		await get_tree().create_timer(0.6, true, false, true).timeout
		_still(view)
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _shot("achievement_pack_%s_scene.png" % String(boss_id))
		view.open_card(2)
		await get_tree().create_timer(0.6, true, false, true).timeout
		_still(view)
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _shot("achievement_pack_%s_plain.png" % String(boss_id))
		view.back()
		await get_tree().create_timer(0.3, true, false, true).timeout
		view.back()
		await get_tree().create_timer(0.3, true, false, true).timeout
	get_tree().paused = false
	get_tree().quit(0)
