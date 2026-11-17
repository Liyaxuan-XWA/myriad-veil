extends Node
## 赫连霄图鉴卡截图（真实 CodexPanel）
## 用法：godot --path . --windowed --resolution 1600x900 res://tools/shot_heiliao_codex.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	CharacterData.boss_progress["boss_03"] = {"killed": true, "first_kill": true}
	var panel := CodexPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	var view: CodexView = panel._view
	view._category_index = 0
	view._boss_detail_id = "boss_03"
	view._render_list()
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _shot("heiliao_codex_detail.png")
	var info_scroll := view.find_child("BossInfoScroll", true, false) as ScrollContainer
	if info_scroll == null:
		print("MISS BossInfoScroll")
	else:
		info_scroll.scroll_vertical = 460
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _shot("heiliao_codex_detail_mid.png")
		info_scroll.scroll_vertical = 100000
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _shot("heiliao_codex_detail_bottom.png")
	view._boss_detail_id = ""
	view._render_list()
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _shot("heiliao_codex_list.png")
	get_tree().paused = false
	get_tree().quit(0)
