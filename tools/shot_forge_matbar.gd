extends Node
## 锻造顶栏材料动作（铸神 / 补天 / 蕴仙）· 截图（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_forge_matbar.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _tpl(eid: String) -> Dictionary:
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		if String((raw as Dictionary).get("equipment_id", "")) == eid:
			return CharacterData.make_equipment_instance(raw as Dictionary)
	return {}


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.current_realm = "化神"
	CharacterData.inventory.clear()
	CharacterData.grant_material("mat_zhushenjing", 1)
	CharacterData.grant_material("mat_butianshi", 2)
	CharacterData.grant_material("mat_yunxiansui", 3)
	CharacterData.grant_material("mat_duanzaojingshi", 128)
	var realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await _frames(2)
	get_tree().current_scene = realm
	await _frames(4)
	var panel := ForgePanel.new()
	panel.set("_tutorial_seen", true)
	get_tree().root.add_child(panel)
	await _frames(6)
	panel.call("open")
	await _frames(8)

	# 满 +10 仙器：铸神亮、蕴仙熄
	var maxed := _tpl("eq_huyaxianglian")
	maxed["equipment_grade"] = "仙器"
	maxed["enhancement_level"] = ItemDB.MAX_ENHANCE
	panel._anvil_item = maxed
	panel.call("_refresh_content")
	await _frames(5)
	await _shot("output/forge_matbar_full.png")
	var img := get_viewport().get_texture().get_image()
	img.get_region(Rect2i(600, 0, 680, 96)).save_png("output/forge_matbar_zoom.png")
	print("SHOT output/forge_matbar_zoom.png")

	# +9 带磨损：补天 / 蕴仙亮
	var worn := _tpl("eq_huyaxianglian")
	worn["equipment_grade"] = "仙器"
	worn["enhancement_level"] = 9
	worn["enhance_fail_count"] = 2
	worn["enhance_ascend_fail_count"] = 1
	worn["enhance_wear_seq"] = [{"k": "n"}, {"k": "a", "g": "道器"}, {"k": "n"}]
	panel._anvil_item = worn
	panel.call("_refresh_content")
	await _frames(5)
	await _shot("output/forge_matbar_wear.png")

	# 点「蕴仙」：材料从顶栏飞下 → 自动落锤
	var ybtn: Button = panel.get("_yunxian_btn")
	ybtn.pressed.emit()
	await get_tree().create_timer(0.38).timeout
	await _shot("output/forge_yunxian_fly.png")
	await get_tree().create_timer(0.62).timeout
	await _shot("output/forge_yunxian_impact.png")
	await get_tree().create_timer(0.60).timeout
	await _shot("output/forge_yunxian_after.png")

	# 神器旧痕：铭牌上恢复磨损刻度与数量
	panel.call("_hide_toast")
	var divine := _tpl("eq_fanpinwandao")
	divine["equipment_grade"] = "神器/先天至宝"
	divine["enhance_fail_count"] = 2
	divine["enhance_ascend_fail_count"] = 1
	divine["enhance_wear_seq"] = [{"k": "n"}, {"k": "a", "g": "道器"}, {"k": "n"}]
	panel._anvil_item = divine
	panel.call("_refresh_content")
	await _frames(5)
	await _shot("output/forge_divine_wear.png")
	var dimg := get_viewport().get_texture().get_image()
	var pr: Rect2 = (panel.get("_plaque") as Control).get_global_rect()
	dimg.get_region(Rect2i(int(pr.position.x) - 8, int(pr.position.y) - 8,
		int(pr.size.x) + 16, int(pr.size.y) + 16)).save_png("output/forge_divine_wear_plaque.png")
	print("SHOT output/forge_divine_wear_plaque.png")

	# 常规锻造闸门：仙器走普通锤被拒，回执指向顶栏「蕴仙」
	var gate := _tpl("eq_huyaxianglian")
	gate["equipment_grade"] = "仙器"
	gate["enhancement_level"] = 5
	panel._anvil_item = gate
	panel.call("_refresh_content")
	await _frames(4)
	panel.call("_commit_forge")
	await _frames(3)
	await _shot("output/forge_yunxian_gate.png")

	panel.call("close")
	await _frames(3)
	get_tree().quit(0)
