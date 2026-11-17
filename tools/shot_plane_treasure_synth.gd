extends Node
## 位面法宝合成界面截图（2026-10-29）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_plane_treasure_synth.tscn
## 输出：output/plane_treasure_synth.png

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CharacterData.inventory.clear()
	for mid in ["mat_liangyi_xuanshi", "mat_zhusha_zhending", "mat_taixu_qijing"]:
		CharacterData.grant_material(mid, 1)
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	panel._switch_mode(ForgePanel.MODE_MELT)
	var candidates: Array = panel._synth_candidates()
	# 故意倒序放：证明三个投入口不看顺序
	var pick_order: Array = [2, 0, 1]
	if candidates.size() >= 3:
		for slot in 3:
			panel._on_synth_pick(slot, candidates[pick_order[slot]])
	await get_tree().create_timer(0.4, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/plane_treasure_synth.png")
	print("SHOT output/plane_treasure_synth.png  ", img.get_width(), "x", img.get_height())
	get_tree().quit()
