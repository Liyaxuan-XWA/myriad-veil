extends Node
## 试炼行囊 / 玉简 实机截图（窗口化）
## godot --path . --resolution 1280x720 res://tools/shot_rogue_gear.tscn -- --no-save
## 出图：output/rogue_deck_scroll.png（玉简页：面板不变形 + 右侧滚动条）

func _ready() -> void:
	RogueRun.start_run("sword")
	for raw in RogueDB.GENERIC_BUFFS:
		if RogueRun.buffs.size() >= 22:
			break
		RogueRun.add_buff(String((raw as Dictionary).get("id", "")))
	var panel = (load("res://scripts/ui/panels/rogue_gear_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	for i in 6:
		await get_tree().process_frame
	panel.call("_switch_tab", 1)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_deck_scroll.png")
	print("SHOT output/rogue_deck_scroll.png")
	get_tree().quit(0)
