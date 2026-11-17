extends Node
## 长夜刃「固定属性，不可强化」标注截图（2026-11-04）
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_locked_affix_note.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var backup_inv: Array = CharacterData.inventory.duplicate(true)
	CharacterData.current_realm = "化神"
	CharacterData.grant_material_guaranteed("mat_duanzaojingshi", 500)
	var base: Dictionary = CharacterData.make_equipment_instance(ItemDB.get_equipment_template("eq_changye_ren"))
	# 先敲几锤，让「增量括号」和「固定属性标注」同时出现在铭牌上
	for i in 12:
		var res: Dictionary = CharacterData.enhance_item(base)
		if not bool(res.get("ok", false)):
			break
	base["equipment_grade"] = "宝器"
	CharacterData.inventory = [base.duplicate(true)]
	CharacterData.grant_material_guaranteed("mat_duanzaojingshi", 500)
	var panel := ForgePanel.new()
	panel._anvil_item = base
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().create_timer(0.35, true, false, true).timeout
	panel._refresh_content()
	await get_tree().create_timer(0.2, true, false, true).timeout
	panel._show_anvil_manual()
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _shot("locked_affix_note_manual.png")
	panel.close()
	await get_tree().process_frame
	CharacterData.inventory = backup_inv
	get_tree().quit(0)
