extends Node
## 镇墟石犼图鉴详情截图：顶部卡面 / 属性与招式 / 掉落。
## 用法：godot --path . --windowed --resolution 1600x1000 tools/shot_shihou_codex.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var panel := CodexPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	var view: CodexView = panel._view
	view._category_index = 0
	view._boss_detail_id = "world_core_shihou"
	view._render_list()
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _shot("shihou_codex_top.png")
	var scroll := view.find_child("BossInfoScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 620
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("shihou_codex_stats.png")
	if scroll != null:
		scroll.scroll_vertical = 100000
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _shot("shihou_codex_drops.png")
	print("SHOT shihou codex done")
	get_tree().quit(0)
