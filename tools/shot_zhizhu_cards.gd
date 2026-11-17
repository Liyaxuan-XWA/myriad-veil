extends Node
## 执烛 · 入场卡 + 卡包四张截图（2026-11-02）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_zhizhu_cards.tscn -- --no-save

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
	# 入场卡
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.050, 0.075)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var card := BossIntroCard.new()
	add_child(card)
	card.open(CodexDB.boss_entry("boss_04_b"), {
		"title": "照影界 · 执烛",
		"source_line": "照影界 · 第二关",
	})
	await get_tree().create_timer(3.2).timeout
	await _shot("zhizhu_intro_card.png")
	card.queue_free()
	await get_tree().process_frame

	# 卡包四张（塔 11 层：通关 12 次 + 无伤双倍血 → 三档解锁齐）
	CharacterData.tower_progress[11] = {
		"unlocked": true, "first_kill": true, "clear_count": 12,
	}
	CharacterData.tower_best_time[11] = 12.0
	CharacterData.tower_no_hit_double[11] = true
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	view.open_boss("boss_04_b")
	await get_tree().create_timer(1.0).timeout
	_finish_paper_reveal(view)
	_still(view)
	await get_tree().create_timer(0.2).timeout
	await _shot("zhizhu_cards_spread.png")
	var names := ["zhizhu_card_scene.png", "zhizhu_card_portrait.png",
		"zhizhu_card_plain.png", "zhizhu_card_ink.png"]
	for i in 4:
		view.open_card(i)
		await get_tree().create_timer(0.7).timeout
		_finish_paper_reveal(view)
		_still(view)
		await get_tree().create_timer(0.2).timeout
		await _shot(names[i])
	get_tree().quit(0)
