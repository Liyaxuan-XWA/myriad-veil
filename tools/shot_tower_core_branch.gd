extends Node
## 万界塔区域首领分支截图（2026-10-30：点分支先出右侧记录碑）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_tower_core_branch.tscn
## 输出：output/tower_core_branch.png

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CharacterData.secret_world["core_kills"] = {"world_lianqi": true}
	CharacterData.core_replay = {"world_lianqi": {"clear_count": 3}}
	var panel := TowerPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().create_timer(0.6, true, false, true).timeout
	for n in panel.find_children("*", "Button", true, false):
		var b := n as Button
		if b != null and b.tooltip_text.contains("分支节点"):
			b.pressed.emit()
			break
	await get_tree().create_timer(0.15, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/tower_core_branch.png")
	print("SHOT output/tower_core_branch.png  ", img.get_width(), "x", img.get_height())
	get_tree().quit()
