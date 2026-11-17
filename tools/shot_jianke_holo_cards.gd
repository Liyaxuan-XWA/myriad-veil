extends Node
## 剑客华彩卡（人物 + 飞剑一起扣出）实机观感截图
## 用法：godot --path . --windowed --resolution 1600x900 tools/shot_jianke_holo_cards.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _still(view: AchievementView) -> void:
	for h in view.find_children("*", "HoloCardView", true, false):
		(h as HoloCardView).set_view_speed_immediate(Vector2.ZERO)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CharacterData.tower_progress[3] = {
		"unlocked": true, "first_kill": true,
		"clear_count": CodexDB.HOLO_CLEAR_REQUIRED,
	}
	CharacterData.tower_no_hit_double[3] = true
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	view.open_boss("boss_01_c")
	await get_tree().create_timer(1.0, true, false, true).timeout
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_boss_01_c_spread.png")
	view.open_card(0)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_boss_01_c_scene.png")
	view.open_card(2)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_boss_01_c_plain.png")
	get_tree().paused = false
	get_tree().quit(0)
