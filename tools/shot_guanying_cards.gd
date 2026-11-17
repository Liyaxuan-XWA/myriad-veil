extends Node
## 观澜 · 卡包四张卡截图（华彩有背景 / 普通 / 纯华彩 / 纸本水墨）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_guanying_cards.tscn -- --no-save

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
	CharacterData.tower_progress[10] = {
		"unlocked": true, "first_kill": true, "clear_count": 12,
	}
	CharacterData.tower_best_time[10] = 9.0
	CharacterData.tower_no_hit_double[10] = true
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	view.open_boss("boss_04")
	await get_tree().create_timer(1.0).timeout
	_finish_paper_reveal(view)
	_still(view)
	await get_tree().create_timer(0.2).timeout
	await _shot("guanying_cards_spread.png")
	for i in 4:
		view.open_card(i)
		await get_tree().create_timer(0.7).timeout
		_finish_paper_reveal(view)
		_still(view)
		await get_tree().create_timer(0.2).timeout
		await _shot(["guanying_card_scene.png", "guanying_card_portrait.png",
			"guanying_card_plain.png", "guanying_card_ink.png"][i])
	get_tree().quit(0)
