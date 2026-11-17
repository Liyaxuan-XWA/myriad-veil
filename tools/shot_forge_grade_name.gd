extends Node
## 锻造台品阶名截图（2026-11-01）：砧上装备名与铭牌名随品阶变色。
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_forge_grade_name.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var backup_inv: Array = CharacterData.inventory.duplicate(true)
	var base := {}
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		base = CharacterData.make_equipment_instance(raw as Dictionary)
		if not base.is_empty():
			break
	if base.is_empty():
		get_tree().quit(1)
		return
	for grade in ["宝器", "道器", "仙器"]:
		var item: Dictionary = base.duplicate(true)
		item["equipment_grade"] = grade
		item["enhancement_level"] = 4
		item["enhance_fail_count"] = 3
		item["enhance_success_count"] = 17
		CharacterData.inventory = [item.duplicate(true)]
		var panel := ForgePanel.new()
		panel._anvil_item = item
		add_child(panel)
		await get_tree().process_frame
		panel.open()
		await get_tree().create_timer(0.35, true, false, true).timeout
		panel._refresh_content()
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _shot("forge_grade_name_%s.png" % grade)
		panel.close()
		await get_tree().process_frame
	CharacterData.inventory = backup_inv
	get_tree().quit(0)
