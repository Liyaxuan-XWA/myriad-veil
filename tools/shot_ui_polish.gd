extends Node
## UI 视觉秩序改版后的样板截图（2026-11-04）
## 三处样板：仓库面板 / 锻造台（含器谱）/ 战斗 HUD
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_ui_polish.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _mat(id: String, c: int) -> Dictionary:
	var def := ItemDB.get_material(id)
	return {"id": id, "name": String(def.get("name", id)), "type": "material",
		"count": c, "icon": String(def.get("icon", ""))}


func _pill(id: String, c: int) -> Dictionary:
	var def := ItemDB.get_consumable(id)
	return {"id": id, "name": String(def.get("pill_name", id)), "type": "pill",
		"count": c, "icon": String(def.get("icon", ""))}


func _ready() -> void:
	var backup_inv: Array = CharacterData.inventory.duplicate(true)
	var backup_wh: Array = CharacterData.warehouse.duplicate(true)

	# ---------- ① 仓库 ----------
	CharacterData.inventory = [
		_pill("pill_julidan", 6), _pill("pill_huichundan", 2),
		_mat("mat_ruishoupi", 14), _mat("mat_falinghua", 3),
	]
	CharacterData.warehouse = [_mat("mat_yuanshen", 9), _pill("pill_peiyuan", 4)]
	var wh = load("res://scripts/ui/panels/warehouse_panel.gd").new()
	add_child(wh)
	await get_tree().process_frame
	wh.open()
	for i in 14:
		await get_tree().process_frame
	await _shot("ui_polish_warehouse.png")
	wh.close()
	await get_tree().process_frame

	# ---------- ② 锻造台（砧上有装备 + 器谱展开）----------
	CharacterData.inventory = [
		CharacterData.make_equipment_instance(ItemDB.get_equipment_template("eq_zhenxu_jia")),
		_mat("mat_duanzaojingshi", 480),
	]
	var item: Dictionary = CharacterData.inventory[0]
	item["equipment_grade"] = "宝器"
	item["enhancement_level"] = 6
	item["enhance_fail_count"] = 3
	item["enhance_success_count"] = 17
	item["attributes_base"] = {
		AttributeDB.ATTR_HP_MAX: 60.0,
		AttributeDB.ATTR_PHYSICAL_RESIST: 7.0,
		"resist_earth": 6.0,
	}
	var panel := ForgePanel.new()
	panel._anvil_item = item
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	for i in 12:
		await get_tree().process_frame
	panel._show_anvil_manual()
	for i in 8:
		await get_tree().process_frame
	await _shot("ui_polish_forge_manual.png")
	panel.close()
	await get_tree().process_frame

	CharacterData.inventory = backup_inv
	CharacterData.warehouse = backup_wh

	# ---------- ③ 战斗 HUD ----------
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01",
		"boss_id": "boss_01_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 10:
		await get_tree().process_frame
	await _shot("ui_polish_hud.png")
	get_tree().quit(0)
