extends Node
## 铸神 / 补天 演出截图：材料飞上装备 + 自动落锤 + 装备光色（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_forge_special.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/%s.png" % name)
	print("SHOT output/%s.png" % name)


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
	CharacterData.inventory.clear()
	CharacterData.grant_material("mat_zhushenjing", 1)
	CharacterData.grant_material("mat_butianshi", 2)
	CharacterData.grant_material("mat_duanzaojingshi", 50)
	var panel := ForgePanel.new()
	get_tree().root.add_child(panel)
	await _frames(6)
	panel.call("open")
	await _frames(8)

	# 铸神：材料飞入 → 落锤 → 金光
	var item := _tpl("eq_huyaxianglian")
	item["equipment_grade"] = "仙器"
	item["enhancement_level"] = ItemDB.MAX_ENHANCE
	panel._anvil_item = item
	panel.call("_refresh_content")
	await _frames(4)
	(panel.get("_divine_btn") as Button).pressed.emit()
	await get_tree().create_timer(0.26).timeout
	await _shot("forge_divine_fly")
	await get_tree().create_timer(0.70).timeout
	await _shot("forge_divine_glow")

	# 补天：材料飞入 → 落锤 → 绿光
	var wear := _tpl("eq_huyaxianglian")
	wear["equipment_grade"] = "灵器"
	wear["enhance_fail_count"] = 6
	wear["enhance_ascend_fail_count"] = 2
	panel._anvil_item = wear
	panel.call("_refresh_content")
	await _frames(4)
	(panel.get("_mend_btn") as Button).pressed.emit()
	await get_tree().create_timer(0.26).timeout
	await _shot("forge_mend_fly")
	await get_tree().create_timer(0.70).timeout
	await _shot("forge_mend_glow")
	get_tree().quit(0)
