extends Node
## 自动锻造界面截图（2026-11-01）

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var base := {}
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		base = CharacterData.make_equipment_instance(raw as Dictionary)
		if not base.is_empty():
			break
	var panel := ForgePanel.new()
	panel._anvil_item = base
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().create_timer(0.4, true, false, true).timeout
	CharacterData.grant_material(CharacterData.ENHANCE_MATERIAL, 100)
	panel._hammer_held = true
	panel._refresh_content()
	await get_tree().process_frame
	panel._on_auto_pressed()
	await get_tree().create_timer(0.35, true, false, true).timeout
	await _shot("forge_auto.png")
	panel._on_auto_stop_pressed()
	await get_tree().create_timer(0.8, true, false, true).timeout
	await _shot("forge_auto_stopped.png")
	get_tree().quit(0)
