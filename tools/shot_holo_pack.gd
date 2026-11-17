extends Node
## 成就 · 卡包收藏册截图：收藏册 / 三卡展开 / 拖动换位 / 封面跟随 / 单卡三版 /
## 只有普通卡的首领 / 未获得的 BOSS 不占格 / 任务页。
## 用法：godot --path . --windowed --resolution 1600x900 tools/shot_holo_pack.tscn -- --no-save


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _still(view: AchievementView) -> void:
	for h in view.find_children("*", "HoloCardView", true, false):
		(h as HoloCardView).set_view_speed_immediate(Vector2.ZERO)


func _finish_paper_reveal(view: AchievementView) -> void:
	for n in view.find_children("*", "CardFace", true, false):
		var face := n as CardFace
		if face != null and face.is_paper():
			face.set_paper_reveal_immediate(1.0)


func _ready() -> void:
	for f in range(1, 8):
		CharacterData.tower_progress[f] = {"unlocked": true, "first_kill": true, "clear_count": 12}
	CharacterData.tower_progress[8] = {"unlocked": true, "first_kill": true, "clear_count": 1}
	CharacterData.tower_progress[9] = {"unlocked": true, "first_kill": true, "clear_count": 1}
	CharacterData.tower_no_hit_double[1] = true
	CharacterData.secret_world["core_kills"] = {
		"world_lianqi": true, "world_zhuji": true, "world_jiedan": true,
	}
	CodexDB.set_card_order("boss_huyao", ["scene", "portrait", "plain", "ink"])
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view

	# 收藏册（纸本封面若在落墨中，先补满，避免验收图拍到半张纸）
	await get_tree().create_timer(0.5, true, false, true).timeout
	_finish_paper_reveal(view)
	await _shot("achievement_pack_grid.png")
	await get_tree().create_timer(0.9, true, false, true).timeout
	await _shot("achievement_pack_grid_anim.png")
	if view._scroll != null:
		view._scroll.scroll_vertical = 620
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _shot("achievement_pack_grid_rows.png")
	if view._scroll != null:
		view._scroll.scroll_vertical = 0

	# 展开：中途 + 落定
	view.open_boss("boss_huyao")
	await get_tree().create_timer(0.18, true, false, true).timeout
	await _shot("achievement_pack_spread_mid.png")
	await get_tree().create_timer(0.9, true, false, true).timeout
	_finish_paper_reveal(view)
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_spread.png")

	# 单卡三版：封面（华彩有背景）/ 普通 / 纯华彩
	view.open_card(0)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_card_scene.png")
	view.open_card(1)
	await get_tree().create_timer(0.5, true, false, true).timeout
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_card_portrait.png")
	view.open_card(2)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_card_plain.png")

	# 纸本水墨：展示完全落墨后的静态卡面
	view.open_card(3)
	await get_tree().create_timer(0.5, true, false, true).timeout
	var ink_face := view.find_child("CardSingle", true, false) as CardFace
	if ink_face != null:
		ink_face.set_paper_reveal_immediate(1.0)
		ink_face.set_paper_interactive(false)
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_card_ink.png")

	# 拖动换位：把封面拖到第二位，第一位换成普通卡
	view._mode = AchievementView.MODE_SPREAD
	view._render()
	await get_tree().create_timer(0.7, true, false, true).timeout
	_still(view)
	var stage := view.find_child("SpreadStage", true, false) as Control
	var slots := view.find_children("CardSlot*", "Control", true, false)
	if stage != null and slots.size() == 4:
		var targets := view._fan_targets(4, view._spread_card)
		var start: Vector2 = (slots[0] as Control).position \
			+ view._spread_card * 0.5
		var drop: Vector2 = targets[1].get("pos", Vector2.ZERO) \
			+ view._spread_card * 0.5
		view._drag_press(start)
		await get_tree().process_frame
		view._drag_move(drop)
		await get_tree().process_frame
		view._drag_release(drop)
		await get_tree().create_timer(0.6, true, false, true).timeout
		_still(view)
		await _shot("achievement_pack_reordered.png")
		view.back()
		await get_tree().create_timer(0.4, true, false, true).timeout
		await _shot("achievement_pack_reordered_grid.png")
		CodexDB.set_card_order("boss_huyao", ["scene", "portrait", "plain", "ink"])
		view.refresh()
		await get_tree().create_timer(0.3, true, false, true).timeout

	# 只有普通卡的首领（大陆核心）
	view.open_boss("world_core_lianqi")
	await get_tree().create_timer(0.9, true, false, true).timeout
	await _shot("achievement_pack_core_card.png")
	view.back()
	await get_tree().create_timer(0.3, true, false, true).timeout

	# 核心首领三卡：双倍血 12 胜 + 双倍血无伤 → 华彩 / 纯华彩都亮
	CharacterData.core_replay["world_lianqi"] = {
		"clear_count": 12, "no_hit_double": true, "no_hit_rewarded": true,
	}
	view.refresh()
	await get_tree().create_timer(0.4, true, false, true).timeout
	view.open_boss("world_core_lianqi")
	await get_tree().create_timer(1.0, true, false, true).timeout
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_core_holo_spread.png")
	view.open_card(0)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_core_holo_scene.png")
	view.open_card(2)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_still(view)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("achievement_pack_core_holo_plain.png")
	view.back()
	await get_tree().create_timer(0.3, true, false, true).timeout
	view.back()
	await get_tree().create_timer(0.3, true, false, true).timeout
	CharacterData.core_replay = {}

	# 未获得的 BOSS / 卡不占格
	CharacterData.tower_progress[3] = {"unlocked": true, "first_kill": false, "clear_count": 0}
	var kills: Dictionary = CharacterData.secret_world.get("core_kills", {})
	kills.erase("world_lianqi")
	view.refresh()
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _shot("achievement_pack_hidden.png")

	# 成就任务页
	view._show_page(AchievementView.PAGE_TASKS)
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("achievement_pack_tasks.png")
	get_tree().paused = false
	get_tree().quit(0)
