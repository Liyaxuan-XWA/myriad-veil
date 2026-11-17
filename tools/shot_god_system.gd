extends Node
## 铸神 / 补天 / 祭坛 · 截图验收（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_god_system.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"
const WORLD_SCENE := "res://scenes/world/secret_world.tscn"


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
	CharacterData.secret_world["god_altars"] = {}

	# ===== ① 大世界祭坛 =====
	GameState.battle_context = {}
	var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await _frames(10)
	var altar: WorldResource = null
	for raw in (w.get("_resources") as Dictionary).values():
		if raw is WorldResource and (raw as WorldResource).kind == WorldResource.KIND_GOD_ALTAR \
				and (raw as WorldResource).node_id == "lq_god_altar":
			altar = raw as WorldResource
	if altar != null:
		var wp: Node2D = w.get("player")
		wp.set_physics_process(false)
		wp.global_position = altar.global_position + Vector2(0, 90)
		await _frames(6)
		await _shot("god_altar_world")
	else:
		print("没有找到祭坛")
	w.queue_free()
	await _frames(3)

	# ===== ② 锻造台：铸神就绪 / 铸神完成 =====
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
	var item := _tpl("eq_huyaxianglian")
	item["equipment_grade"] = "仙器"
	item["enhancement_level"] = 10
	panel._anvil_item = item
	panel.call("_refresh_content")
	await _frames(6)
	await _shot("forge_divine_ready")
	var btn := panel.get("_divine_btn") as Button
	btn.pressed.emit()
	# 铸神数据在落锤那一拍（约 0.74s）才结算，等演出走完再截图
	await get_tree().create_timer(1.05).timeout
	await _shot("forge_divine_done")

	# ===== ③ 材料图标在背包 =====
	panel.call("close")
	await _frames(3)
	CharacterPanel.open_panel()
	await _frames(4)
	CharacterPanel.call("_on_filter_pressed", CharacterData.ITEM_MATERIAL, null)
	await _frames(4)
	await _shot("god_materials_bag")
	get_tree().quit(0)
