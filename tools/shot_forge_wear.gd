extends Node
## 磨损刻度分色 · 截图（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_forge_wear.tscn -- --no-save

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
	var item := _tpl("eq_huyaxianglian")
	# 当前仙器（红名），但旧进阶格保留各自失败时品阶：凡品 / 灵器 / 宝器
	item["equipment_grade"] = "仙器"
	item["enhance_fail_count"] = 6
	item["enhance_ascend_fail_count"] = 3
	item["enhance_wear_seq"] = [
		{"k": "n"}, {"k": "a", "g": "凡品"},
		{"k": "n"}, {"k": "a", "g": "灵器"},
		{"k": "n"}, {"k": "a", "g": "宝器"}]
	panel._anvil_item = item
	panel.call("_refresh_content")
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/forge_wear_full.png")
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
	big.save_png("output/forge_wear_plaque.png")
	print("SHOT output/forge_wear_full.png / forge_wear_plaque.png")
	get_tree().quit(0)
