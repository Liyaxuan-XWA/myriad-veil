extends Node
## 蕴仙髓：化神仙器淬炼消耗 + 背包图标 · 截图（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_yunxian.tscn -- --no-save

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
	CharacterData.current_realm = "化神"
	CharacterData.inventory.clear()
	CharacterData.grant_material("mat_yunxiansui", 1)
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
	item["equipment_grade"] = "仙器"
	item["enhancement_level"] = 5
	panel._anvil_item = item
	panel.call("_refresh_content")
	await _frames(5)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/forge_yunxian_full.png")
	var plaque: Control = panel.get("_plaque")
	var r := plaque.get_global_rect()
	img.get_region(Rect2i(int(r.position.x) - 8, int(r.position.y) - 8,
		int(r.size.x) + 16, int(r.size.y) + 16)).save_png("output/forge_yunxian_plaque.png")
	print("SHOT output/forge_yunxian_full.png / forge_yunxian_plaque.png")

	panel.call("close")
	await _frames(3)
	CharacterPanel.open_panel()
	await _frames(4)
	CharacterPanel.call("_on_filter_pressed", CharacterData.ITEM_MATERIAL, null)
	await _frames(4)
	for c in (CharacterPanel.get("_bag_grid") as Node).get_children():
		var it = c.get("item")
		if it is Dictionary and String((it as Dictionary).get("id", "")) == "mat_yunxiansui":
			(c as Button).pressed.emit()
			break
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/yunxian_bag.png")
	print("SHOT output/yunxian_bag.png")
	get_tree().quit(0)
