extends Node
## 镇墟石犼卡包截图：四张展开 + 华彩有背景 / 普通 / 纯华彩 / 纸本水墨。
## 用法：godot --path . --windowed --resolution 1600x1000 tools/shot_shihou_cards.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _finish_paper_reveal(view: AchievementView) -> void:
	for n in view.find_children("*", "CardFace", true, false):
		var face := n as CardFace
		if face != null and face.is_paper():
			face.set_paper_reveal_immediate(1.0)


func _still(view: AchievementView) -> void:
	for h in view.find_children("*", "HoloCardView", true, false):
		(h as HoloCardView).set_view_speed_immediate(Vector2.ZERO)


func _ready() -> void:
	get_tree().create_timer(30.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT TIMEOUT")
		get_tree().quit(2))
	for f in range(1, 8):
		CharacterData.tower_progress[f] = {"unlocked": true, "first_kill": true, "clear_count": 12}
	CharacterData.tower_progress[8] = {"unlocked": true, "first_kill": true, "clear_count": 1}
	CharacterData.tower_progress[9] = {"unlocked": true, "first_kill": true, "clear_count": 1}
	CharacterData.tower_no_hit_double[1] = true
	CharacterData.secret_world["core_kills"] = {
		"world_lianqi": true, "world_zhuji": true, "world_jiedan": true,
		"world_yuanying": true,
	}
	for rid in ["world_lianqi", "world_zhuji", "world_jiedan", "world_yuanying"]:
		CharacterData.core_replay[rid] = {
			"clear_count": 12, "no_hit_double": true, "best_time": 9.5,
		}
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	await get_tree().create_timer(0.6, true, false, true).timeout
	_finish_paper_reveal(view)
	await _shot("shihou_cards_grid.png")
	view.open_boss("world_core_shihou")
	await get_tree().create_timer(1.0, true, false, true).timeout
	_finish_paper_reveal(view)
	_still(view)
	await _shot("shihou_cards_spread.png")

	for i in range(4):
		view.open_card(i)
		await get_tree().create_timer(0.6, true, false, true).timeout
		_finish_paper_reveal(view)
		_still(view)
		await get_tree().create_timer(0.2, true, false, true).timeout
		var names := ["scene", "portrait", "plain", "ink"]
		await _shot("shihou_card_%s.png" % names[i])
		view.back()
		await get_tree().create_timer(0.3, true, false, true).timeout
	print("SHOT shihou cards done")
	get_tree().quit(0)
