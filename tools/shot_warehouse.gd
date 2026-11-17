extends Node
## 仓库 / 分背包界面截图（2026-11-02）
## 用法：godot --path . --resolution 1600x1000 tools/shot_warehouse.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _pill(id: String, c: int) -> Dictionary:
	var def := ItemDB.get_consumable(id)
	return {"id": id, "name": String(def.get("pill_name", id)), "type": "pill",
		"count": c, "icon": String(def.get("icon", ""))}


func _mat(id: String, c: int) -> Dictionary:
	var def := ItemDB.get_material(id)
	return {"id": id, "name": String(def.get("name", id)), "type": "material",
		"count": c, "icon": String(def.get("icon", ""))}


func _equip(id: String) -> Dictionary:
	return CharacterData.make_equipment_instance(ItemDB.get_equipment_template(id))


func _treasure(id: String) -> Dictionary:
	return CharacterData.make_treasure_instance(ItemDB.get_treasure_template(id))


func _ready() -> void:
	var backup_inv: Array = CharacterData.inventory.duplicate(true)
	var backup_wh: Array = CharacterData.warehouse.duplicate(true)
	var backup_eq: Dictionary = CharacterData.equipment_slots.duplicate(true)

	CharacterData.inventory = [
		_pill("pill_julidan", 6),
		_pill("pill_huichundan", 2),
		_mat("mat_ruishoupi", 14),
		_mat("mat_falinghua", 3),
		_mat("mat_pojing_zhuji", 1),
		_equip("eq_fanpinwandao"),
		_equip("eq_qingfengjian"),
		_equip("eq_tengjia"),
		_treasure("tr_daoke_ling"),
		_treasure("tr_jianke_ling"),
	]
	CharacterData.warehouse = [
		_mat("mat_ruishoupi", 88),
		_mat("mat_falinghua", 20),
		_equip("eq_qingfengxie"),
	]

	var whp := WarehousePanel.new()
	add_child(whp)
	await get_tree().process_frame
	whp.open()
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _shot("warehouse_pill.png")

	whp._on_tab_pressed(CharacterData.ITEM_MATERIAL, null)
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _shot("warehouse_material.png")

	# 真按一次「存入」：挑一行当前页签里看得见的材料，反馈与格子变化才同屏可见
	var store_idx := -1
	for i in CharacterData.inventory.size():
		if String(CharacterData.inventory[i].get("id", "")) == "mat_falinghua":
			store_idx = i
	whp._on_store_pressed(store_idx)
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _shot("warehouse_after_store.png")

	whp._on_tab_pressed(CharacterData.ITEM_TREASURE, null)
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _shot("warehouse_treasure.png")
	whp.close()
	await get_tree().create_timer(0.2, true, false, true).timeout

	# 背包「装备」包满：点卸下要被拒绝，装备留在身上不消失
	CharacterData.inventory = []
	for i in range(CharacterData.BAG_CAP_EQUIPMENT):
		CharacterData.inventory.append(_equip("eq_tengjia"))
	CharacterData.inventory.append(_mat("mat_ruishoupi", 40))
	CharacterData.equip("weapon", CharacterData.make_equipment_instance(
		ItemDB.get_equipment_template("eq_qingfengjian")))
	CharacterPanel._on_filter_pressed(CharacterData.ITEM_EQUIPMENT, null)
	CharacterPanel.open_panel()
	await get_tree().create_timer(0.5, true, false, true).timeout
	CharacterPanel._on_unequip_slot("weapon")
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _shot("bag_full_unequip.png")

	CharacterPanel._on_filter_pressed(CharacterData.ITEM_TREASURE, null)
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _shot("bag_treasure_tab.png")
	CharacterPanel.close_panel()

	CharacterData.inventory = backup_inv
	CharacterData.warehouse = backup_wh
	CharacterData.equipment_slots = backup_eq
	get_tree().quit(0)
