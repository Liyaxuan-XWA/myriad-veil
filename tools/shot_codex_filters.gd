extends Node
## 图鉴二级分类截图：装备武器 / 材料 / BOSS 大陆核心。

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _index_of(cid: String) -> int:
	for i in CodexDB.categories().size():
		if String((CodexDB.categories()[i] as Dictionary).get("id", "")) == cid:
			return i
	return 0


func _ready() -> void:
	var panel := CodexPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	var view: CodexView = panel._view

	view._show_category(_index_of(CodexDB.CAT_EQUIPMENT))
	await get_tree().process_frame
	view._show_sub(CodexDB.SUB_WEAPON)
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("codex_equipment_weapons.png")

	view._show_category(_index_of(CodexDB.CAT_MATERIAL))
	await get_tree().process_frame
	view._show_sub(CodexDB.SUB_REALM_LIANQI)
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("codex_materials_lianqi.png")

	view._show_category(_index_of(CodexDB.CAT_BOSS))
	await get_tree().process_frame
	view._show_sub(CodexDB.SUB_WORLD)
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("codex_boss_world.png")

	get_tree().paused = false
	get_tree().quit(0)
