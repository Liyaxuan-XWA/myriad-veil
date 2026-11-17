extends Node
## 锻打铭牌强化词条行 · 截图验收（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_forge_affix.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _tpl(eid: String) -> Dictionary:
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		if String((raw as Dictionary).get("equipment_id", "")) == eid:
			return CharacterData.make_equipment_instance(raw as Dictionary)
	return {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"legacy": true}
	var realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await _frames(2)
	get_tree().current_scene = realm
	await _frames(4)
	var panel := ForgePanel.new()
	get_tree().root.add_child(panel)
	await _frames(6)
	panel.call("open")
	await _frames(8)
	var item := _tpl("eq_qingfengjian")
	item["enhancement_level"] = 2
	panel._anvil_item = item
	panel.call("_refresh_content")
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/forge_affix_full.png")
	var plaque: Control = panel.get("_plaque")
	var r := plaque.get_global_rect()
	var crop := img.get_region(Rect2i(int(r.position.x) - 8, int(r.position.y) - 8,
		int(r.size.x) + 16, int(r.size.y) + 16))
	var big := Image.create(crop.get_width() * 2, crop.get_height() * 2, false, crop.get_format())
	for y in crop.get_height():
		for x in crop.get_width():
			var col := crop.get_pixel(x, y)
			for dy in 2:
				for dx in 2:
					big.set_pixel(x * 2 + dx, y * 2 + dy, col)
	big.save_png("output/forge_affix_plaque.png")
	print("SHOT output/forge_affix_full.png / forge_affix_plaque.png  plaque=", r)

	# 抗性甲：物抗 / 五行抗全部显示区间（2026-11-13）
	var cang := _tpl("eq_cangjiao_jia")
	cang["enhancement_level"] = 2
	panel._anvil_item = cang
	panel.call("_refresh_content")
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("output/forge_affix_resist_full.png")
	var r2 := plaque.get_global_rect()
	img2.get_region(Rect2i(int(r2.position.x) - 8, int(r2.position.y) - 8,
		int(r2.size.x) + 16, int(r2.size.y) + 16)).save_png("output/forge_affix_resist.png")
	print("SHOT output/forge_affix_resist_full.png / forge_affix_resist.png")

	# 法强 / 灵力：法强区间对齐力量
	var qihai := _tpl("eq_qihai_yuzhui")
	qihai["enhancement_level"] = 2
	panel._anvil_item = qihai
	panel.call("_refresh_content")
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img3 := get_viewport().get_texture().get_image()
	img3.save_png("output/forge_affix_spell_full.png")
	var r3 := plaque.get_global_rect()
	img3.get_region(Rect2i(int(r3.position.x) - 8, int(r3.position.y) - 8,
		int(r3.size.x) + 16, int(r3.size.y) + 16)).save_png("output/forge_affix_spell.png")
	print("SHOT output/forge_affix_spell_full.png / forge_affix_spell.png")

	get_tree().quit(0)
