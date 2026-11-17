extends Node
## 「突破境界」任务卡两段文案实机截图（窗口化）
## godot --path . --resolution 1280x720 res://tools/shot_quest_break_text.tscn -- --no-save
## ⚠ 换场景是同步的：先把本节点挪到 GameState 底下再 change_scene。

func _ready() -> void:
	# ⚠ 换场景/换父节点必须延后一帧：_ready 期间 root 正在装子节点，remove_child 会被拒
	call_deferred("_go")


func _go() -> void:
	# 任务进度摆成「前 4 个做完」→ 当前任务 = 突破境界
	CharacterData.quest_data = {"done": {}}
	var quests: Array = QuestDB.QUESTS
	for i in mini(4, quests.size()):
		(CharacterData.quest_data["done"] as Dictionary)[String((quests[i] as Dictionary).get("id", ""))] = true
	var host := get_node_or_null("/root/GameState")
	if host == null:
		print("[!] 没有 GameState")
		get_tree().quit(1)
		return
	get_parent().remove_child(self)
	host.add_child(self)
	get_tree().change_scene_to_file("res://scenes/main/primordial_realm.tscn")
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/quest_break_text.png")
	# 裁任务卡那块放大 2 倍
	var crop := img.get_region(Rect2i(0, 200, 470, 300))
	var big := Image.create(crop.get_width() * 2, crop.get_height() * 2, false, crop.get_format())
	for y in crop.get_height():
		for x in crop.get_width():
			var col := crop.get_pixel(x, y)
			for dy in 2:
				for dx in 2:
					big.set_pixel(x * 2 + dx, y * 2 + dy, col)
	big.save_png("output/quest_break_text_zoom.png")
	print("SHOT output/quest_break_text.png / _zoom.png")
	get_tree().quit(0)
