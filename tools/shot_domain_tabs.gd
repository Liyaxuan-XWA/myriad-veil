extends Node
## 万界秘境页签动效截图（窗口化）：连拍 8 帧，看呼吸/光扫的实际幅度

func _ready() -> void:
	var panel = (load("res://scripts/ui/panels/domain_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	for i in 6:
		await get_tree().process_frame
	for k in 8:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/domain_tabs_%d.png" % k)
		print("SHOT output/domain_tabs_%d.png" % k)
		await get_tree().create_timer(0.42).timeout
	get_tree().quit(0)
