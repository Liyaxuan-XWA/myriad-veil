extends Node
## 未选中页签的「可按」起伏截图（窗口化）：在同一次打开面板里，按两个相位各裁一刀
## godot --path . --resolution 1280x720 res://tools/shot_tab_idle.tscn -- --no-save

func _ready() -> void:
	var panel = (load("res://scripts/ui/panels/domain_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	var world_btn: Button = panel.get("_tab_world")
	UIKit.set_tab_selected(world_btn, false)
	for i in 30:
		await get_tree().process_frame
	_run_shot("tab_idle_a", world_btn)
	await get_tree().create_timer(1.3).timeout
	_run_shot("tab_idle_b", world_btn)
	get_tree().quit(0)

func _run_shot(tag: String, b: Button) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var r := b.get_global_rect()
	# 多裁一圈，看「抬起来」的那几像素
	var crop := img.get_region(Rect2i(int(r.position.x) - 10, int(r.position.y) - 10,
		int(r.size.x) + 20, int(r.size.y) + 20))
	var big := Image.create(crop.get_width() * 3, crop.get_height() * 3, false, crop.get_format())
	for y in crop.get_height():
		for x in crop.get_width():
			var col := crop.get_pixel(x, y)
			for dy in 3:
				for dx in 3:
					big.set_pixel(x * 3 + dx, y * 3 + dy, col)
	big.save_png("output/%s.png" % tag)
	print("SHOT output/%s.png  scale=%.4f" % [tag, b.scale.x])
