extends Node

func _ready() -> void:
	var panel := CodexPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	var view: CodexView = panel._view
	view._category_index = 0
	view._boss_detail_id = "world_core_zhuji"
	view._render_list()
	await get_tree().create_timer(0.4, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/cangjiao_codex_top.png")
	var scroll := view.find_child("BossInfoScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 620
	await get_tree().create_timer(0.2, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/cangjiao_codex_stats.png")
	if scroll != null:
		scroll.scroll_vertical = 100000
	await get_tree().create_timer(0.25, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/cangjiao_codex_drops.png")
	print("SHOT cangjiao codex top/drops")
	get_tree().paused = false
	get_tree().quit(0)
