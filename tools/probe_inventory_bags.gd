extends Node
## 分背包 / 丢件 / 仓库探针（2026-11-02 用户三条要求）
##  1) 四类分背包各 100 格（丹药 / 材料 / 装备 / 法宝），互不占用，去掉「全部」页签
##  2) 满包时脱下装备、锻造台取下与退出界面都**绝不能吞装备**
##  3) 仓库改成独立存储：每类 500 格，只能存 / 取，使用仍然只认背包
## 用法：godot --headless --path . tools/probe_inventory_bags.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _clear_worn() -> void:
	for slot in CharacterData.WORN_SLOT_ORDER:
		CharacterData._set_slot(String(slot), {})


func _weapon_tpl() -> Dictionary:
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		var tpl: Dictionary = raw
		if String(tpl.get("equipment_type", "")) == "weapon":
			return tpl
	return {}


func _treasure_tpl() -> Dictionary:
	for raw in ItemDB.TREASURE_TEMPLATES:
		var tpl: Dictionary = raw
		if String(tpl.get("treasure_id", "")) != "":
			return tpl
	return {}


## 往背包里塞满 n 件同类装备（直接 append，保住引用同一性）
func _fill_equip_bag(n: int, tpl: Dictionary) -> void:
	for i in range(n):
		CharacterData.inventory.append(CharacterData.make_equipment_instance(tpl))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 分背包 / 丢件 / 仓库探针 ##########")
	var d := CharacterData
	var backup_inv: Array = d.inventory.duplicate(true)
	var backup_eq: Dictionary = d.equipment_slots.duplicate(true)
	var backup_tr: Dictionary = d.treasure_slots.duplicate(true)
	var backup_wh: Array = d.warehouse.duplicate(true)
	var backup_stock: Dictionary = d.talisman_stock.duplicate(true)

	var wtpl := _weapon_tpl()
	var ttpl := _treasure_tpl()
	_check(not wtpl.is_empty() and not ttpl.is_empty(), "取到装备 / 法宝模板")

	# ===== 1. 分背包容量模型 =====
	_check(d.BAG_CAP_PILL == 100 and d.BAG_CAP_MATERIAL == 100
		and d.BAG_CAP_EQUIPMENT == 100 and d.BAG_CAP_TREASURE == 100,
		"四类分背包各 100 格")
	_check(d.BAG_CATEGORIES.size() == 4 and not d.BAG_CATEGORIES.has("all")
		and not d.BAG_CATEGORIES.has(d.ITEM_TALISMAN), "页签只剩四类", str(d.BAG_CATEGORIES))
	var wp := d.make_equipment_instance(wtpl)
	var tr := d.make_treasure_instance(ttpl)
	var pill := {"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 1}
	var mat := {"id": "mat_ruishoupi", "name": "青岚兽皮", "type": "material", "count": 1}
	_check(d.bag_category_of(wp) == d.ITEM_EQUIPMENT, "普通装备算「装备」类")
	_check(d.bag_category_of(tr) == d.ITEM_TREASURE, "法宝单独算「法宝」类")
	_check(d.bag_category_of(pill) == d.ITEM_PILL and d.bag_category_of(mat) == d.ITEM_MATERIAL,
		"丹药 / 材料各自成类")

	# 装备塞满 100，法宝与丹药仍然放得下 —— 分背包互不占用
	d.inventory = []
	_fill_equip_bag(d.BAG_CAP_EQUIPMENT, wtpl)
	_check(d.bag_count_for(d.ITEM_EQUIPMENT) == 100, "装备包占满 100 格")
	_check(not d.bag_has_room(wp), "装备包满后新装备放不下")
	_check(not d.add_item(d.make_equipment_instance(wtpl)), "add_item 满包返回 false")
	_check(d.inventory.size() == 100, "被拒的装备没有偷偷进包")
	_check(d.bag_has_room(tr) and d.bag_has_room(pill), "法宝 / 丹药不受装备包满影响")

	# 可堆叠物品永远合堆，不会把格子撑爆
	d.inventory = [{"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 50}]
	_check(d.add_item({"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 60}),
		"同款丹药叠加")
	_check(d.bag_count_for(d.ITEM_PILL) == 1 and int(d.inventory[0].get("count", 0)) == 110,
		"叠加只占一格", str(d.inventory))

	# get_items_by_type 按分背包取，装备页签不再混法宝
	d.inventory = []
	_fill_equip_bag(3, wtpl)
	d.inventory.append(d.make_treasure_instance(ttpl))
	_check(d.get_items_by_type(d.ITEM_EQUIPMENT).size() == 3
		and d.get_items_by_type(d.ITEM_TREASURE).size() == 1,
		"装备 / 法宝列表互不混排")

	# ===== 2. 满包脱下装备：拒绝，但装备绝不消失 =====
	d.inventory = []
	_clear_worn()
	_fill_equip_bag(d.BAG_CAP_EQUIPMENT, wtpl)
	var worn := d.make_equipment_instance(wtpl)
	d.equip("weapon", worn)
	_check(d.is_held_by_slot(worn), "测试装备已穿在身上")
	_check(not d.unequip_to_inventory("weapon"), "满包卸装被拒绝")
	_check(not d.get_equipped("weapon").is_empty(), "拒绝后装备仍在身上（没消失）")
	_check(d.inventory.size() == 100, "拒绝后背包格数不变")

	d.inventory.pop_back()
	_check(d.unequip_to_inventory("weapon"), "腾出一格后可以卸下")
	_check(d.get_equipped("weapon").is_empty() and d.inventory.size() == 100,
		"卸下后装备回到背包")

	# 法宝是独立分背包：满了只拦法宝，装备 / 丹药照常
	d.inventory = []
	_clear_worn()
	for i in range(d.BAG_CAP_TREASURE):
		d.inventory.append(d.make_treasure_instance(ttpl))
	var worn_t := d.make_treasure_instance(ttpl)
	d.equip("treasure_1", worn_t)
	_check(d.bag_count_for(d.ITEM_TREASURE) == 100, "法宝包占满 100 格")
	_check(not d.unequip_to_inventory("treasure_1"), "满包时卸下法宝被拒绝")
	_check(not d.get_equipped("treasure_1").is_empty(), "被拒的法宝仍在身上")
	_check(d.bag_has_room(wp) and d.bag_has_room(pill), "法宝包满不影响装备 / 丹药包")

	# 穿戴换下旧装备：预检在移除之后，换下的旧装备必然有位可回
	d.inventory = []
	_clear_worn()
	_fill_equip_bag(d.BAG_CAP_EQUIPMENT, wtpl)
	var old_worn := d.make_equipment_instance(wtpl)
	d.equip("weapon", old_worn)
	var new_idx := d.inventory.size() - 1
	var new_item: Dictionary = d.inventory[new_idx]
	var swapped := d.equip_from_inventory(new_idx)
	_check(not d.is_held_by_slot(old_worn) and d.is_held_by_slot(new_item),
		"满包穿戴：新装备穿上")
	_check(swapped.is_empty() or is_same(swapped, old_worn), "换下的旧装备交回界面")
	_check(d.inventory.size() == 100
		and (swapped.is_empty() or d.inventory.has(swapped)),
		"满包穿戴没有吞掉旧装备", "背包 %d 件" % d.inventory.size())

	# ===== 3. 锻造台 =====
	d.inventory = []
	_clear_worn()
	_fill_equip_bag(d.BAG_CAP_EQUIPMENT, wtpl)
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var anvil_item := d.make_equipment_instance(wtpl)
	panel._anvil_item = anvil_item
	_check(not d.return_from_forge(anvil_item), "满包时锻造台取回被拒绝")
	_check(d.inventory.size() == 100, "被拒的装备没进背包（也还在砧上）")
	panel._on_take_from_anvil()
	_check(is_same(panel._anvil_item, anvil_item), "拒绝后装备仍留在砧上")

	# 退出界面：哪怕分背包已经满，也必须强制归还（用户报的「退出锻造界面装备消失」）
	var count_before_exit := d.inventory.size()
	panel.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(d.inventory.size() == count_before_exit + 1,
		"退出锻造界面后装备回到背包", "背包 %d 件" % d.inventory.size())
	_check(d.inventory.has(anvil_item), "归还的正是砧上那件（不是复制品）")

	# 面板内换装失败的回滚路径：满包时把砧上装备塞回去也要强制入包
	d.inventory = []
	_fill_equip_bag(d.BAG_CAP_EQUIPMENT, wtpl)
	var forced := d.make_equipment_instance(wtpl)
	d.return_item_or_force(forced)
	_check(d.inventory.size() == 101 and d.inventory.has(forced),
		"return_item_or_force 越上限也保证不丢")

	# ===== 4. 仓库：独立存储 =====
	d.warehouse = []
	d.inventory = []
	d.add_item({"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 3})
	d.add_item({"id": "mat_ruishoupi", "name": "青岚兽皮", "type": "material", "count": 2})
	var bag_pill_idx := 0
	var res := d.store_to_warehouse(bag_pill_idx)
	_check(bool(res.get("ok", false)), "丹药可存入仓库", str(res))
	_check(d.inventory.size() == 1 and d.warehouse.size() == 1, "存后两边各剩一格")
	_check(int(d.warehouse[0].get("count", 0)) == 3, "存入保留了张数", str(d.warehouse[0]))

	# 同款叠加，不同款各占一格
	d.add_item({"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 4})
	_check(d.store_to_warehouse(d.inventory.size() - 1).get("ok") == true, "第二堆丹药存入")
	_check(d.warehouse.size() == 1 and int(d.warehouse[0].get("count", 0)) == 7,
		"仓库同款合堆", str(d.warehouse))
	_check(d.store_to_warehouse(0).get("ok") == true, "材料存入")
	_check(d.warehouse_count_for(d.ITEM_MATERIAL) == 1
		and d.warehouse_count_for(d.ITEM_PILL) == 1, "仓库按分背包计数")

	# 装备不合堆
	d.inventory = []
	d.inventory.append(d.make_equipment_instance(wtpl))
	d.inventory.append(d.make_equipment_instance(wtpl))
	d.store_to_warehouse(1)
	d.store_to_warehouse(0)
	_check(d.warehouse_count_for(d.ITEM_EQUIPMENT) == 2, "仓库里两件装备占两格")

	# 取出：回到背包
	_check(bool(d.take_from_warehouse(0).get("ok", false)), "丹药可取出回背包")
	_check(d.warehouse_count_for(d.ITEM_PILL) == 0
		and d.bag_count_for(d.ITEM_PILL) == 1
		and d.warehouse_count_for(d.ITEM_EQUIPMENT) == 2,
		"取出后两边格数对得上", str(d.warehouse))

	# 背包放不下 → 取出被拒，物品仍留在仓库
	d.inventory = []
	_fill_equip_bag(d.BAG_CAP_EQUIPMENT, wtpl)
	d.warehouse.append(d.make_equipment_instance(wtpl))
	var wh_idx := d.warehouse.size() - 1
	var take_res := d.take_from_warehouse(wh_idx)
	_check(not bool(take_res.get("ok", false)), "满包时取出被拒绝", str(take_res))
	_check(d.warehouse.size() == wh_idx + 1, "被拒的物品仍完整留在仓库")
	_check(String(take_res.get("message", "")).contains("背包已满"), "拒绝文案说明背包已满")

	# 仓库每类 500 格
	_check(d.WAREHOUSE_CAP_PER_CATEGORY == 500, "仓库每类 500 格")
	d.warehouse = []
	d.inventory = []
	for i in range(500):
		d.warehouse.append({"id": "mat_%d" % i, "name": "材料%d" % i, "type": "material", "count": 1})
	d.add_item({"id": "mat_new", "name": "新材料", "type": "material", "count": 1})
	_check(not d.warehouse_has_room({"id": "mat_new", "type": "material", "count": 1}),
		"材料类占满 500 格后不再收")
	var full_res := d.store_to_warehouse(0)
	_check(not bool(full_res.get("ok", false)), "仓库满时存入被拒绝")
	_check(d.inventory.size() == 1, "被拒的物品留在背包")
	d.warehouse.append({"id": "mat_ruishoupi", "name": "青岚兽皮", "type": "material", "count": 1})
	d.inventory.append({"id": "mat_ruishoupi", "name": "青岚兽皮", "type": "material", "count": 1})
	_check(d.warehouse_has_room({"id": "mat_ruishoupi", "name": "青岚兽皮", "type": "material", "count": 1}),
		"能合堆就还算放得下")
	_check(d.store_to_warehouse(d.inventory.size() - 1).get("ok") == true, "满仓仍可合堆存入")

	# 符箓不进仓库（照旧只认符匣）
	d.warehouse = []
	d.inventory = [{"id": "tal_shui_yi", "name": "一元水符", "type": "talisman", "count": 1}]
	var tal_res := d.store_to_warehouse(0)
	_check(not bool(tal_res.get("ok", false)) and d.inventory.size() == 1,
		"符箓不进仓库，也不留在背包", str(tal_res))
	_check(d.warehouse.is_empty(), "被拦下的符箓没有落进仓库")
	d.inventory = []

	# 整类搬运
	d.inventory = []
	for i in range(5):
		d.add_item({"id": "mat_bag%d" % i, "name": "袋料%d" % i, "type": "material", "count": 1})
	d.add_item({"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 1})
	_check(d.store_category(d.ITEM_MATERIAL) == 5, "全部存入只搬这一类")
	_check(d.warehouse_count_for(d.ITEM_MATERIAL) == 5
		and d.bag_count_for(d.ITEM_PILL) == 1, "整类搬运不影响别类")
	_check(d.take_category(d.ITEM_MATERIAL) == 5, "全部取回")
	_check(d.bag_count_for(d.ITEM_MATERIAL) == 5 and d.warehouse_count_for(d.ITEM_MATERIAL) == 0,
		"取回后仓库该类清空")

	# 使用侧仍然只认背包：仓库里的破境材料不能直接突破
	d.inventory = []
	d.warehouse = [{"id": "mat_pojing_zhuji", "name": "筑基破境晶", "type": "material", "count": 1}]
	_check(d.count_material("mat_pojing_zhuji") == 0, "仓库材料不计入可用性")

	# ===== 5. 存档 =====
	d.inventory = [{"id": "mat_ruishoupi", "name": "青岚兽皮", "type": "material", "count": 2}]
	d.warehouse = [{"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 9}]
	var snap: Dictionary = SaveManager.capture()
	_check(snap.has("warehouse_data"), "存档写入 warehouse_data")
	d.warehouse = []
	d.inventory = []
	SaveManager.apply(snap)
	_check(d.warehouse.size() == 1 and int(d.warehouse[0].get("count", 0)) == 9,
		"读档恢复仓库", str(d.warehouse))
	_check(d.inventory.size() == 1, "读档恢复背包")

	# 空档判定：仓库里有东西也要算「动过手」（用合成快照，避免受当前会话进度干扰）
	var blank := {"inventory_data": [], "warehouse_data": [], "realm_data": {}}
	_check(SaveManager.is_blank_run(blank), "空背包空仓库仍算空档")
	blank["warehouse_data"] = [{"id": "mat_x", "name": "x", "type": "material", "count": 1}]
	_check(not SaveManager.is_blank_run(blank), "仓库里有东西不算空档")

	# ===== 6. 界面 =====
	d.inventory = []
	d.warehouse = []
	for i in range(3):
		d.add_item({"id": "mat_ui%d" % i, "name": "丙料%d" % i, "type": "material", "count": 1})
	d.add_item({"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 1})
	d.warehouse.append({"id": "mat_ui0", "name": "丙料0", "type": "material", "count": 4})

	var whp := WarehousePanel.new()
	add_child(whp)
	await get_tree().process_frame
	await get_tree().process_frame
	# 探针不走 open()（会暂停整棵树），直接调刷新，和数据层探针一套口径
	whp._refresh_content()
	var tabs := PackedStringArray()
	for n in whp.find_children("*", "Button", true, false):
		var t := String((n as Button).text)
		if t in ["丹药", "材料", "装备", "法宝", "全部", "符箓"]:
			tabs.append(t)
	_check(tabs.count("丹药") == 1 and tabs.count("材料") == 1 and tabs.count("装备") == 1
		and tabs.count("法宝") == 1 and tabs.count("全部") == 0 and tabs.count("符箓") == 0,
		"仓库页签四类、没有全部", " ".join(tabs))
	_check(whp._bag_count.text.contains("/ 100 格") and whp._wh_count.text.contains("/ 500 格"),
		"两栏各报自己的容量", "%s | %s" % [whp._bag_count.text, whp._wh_count.text])

	whp._on_tab_pressed(d.ITEM_MATERIAL, null)
	_check(whp._tab == d.ITEM_MATERIAL, "页签可切到材料")
	var bag_rows := whp._bag_list.get_child_count()
	var wh_rows := whp._wh_list.get_child_count()
	_check(bag_rows == 3 and wh_rows == 1, "两栏只列当前类", "背包 %d / 仓库 %d" % [bag_rows, wh_rows])

	# 点「存入」真的搬东西
	_check(bool(d.store_to_warehouse(0).get("ok", false)), "界面外的存入接口可用")
	whp._refresh_content()
	_check(whp._bag_list.get_child_count() == 2 and whp._wh_list.get_child_count() == 1,
		"存入后背包少一格、仓库合堆不增格")

	# 背包页签同样只剩四类
	var bag_tabs := PackedStringArray()
	for pair in CharacterPanel._filter_buttons:
		bag_tabs.append((pair[0] as Button).text)
	_check(bag_tabs.size() == 4 and not bag_tabs.has("全部") and bag_tabs.has("法宝"),
		"背包页签：去全部、加法宝", " ".join(bag_tabs))

	whp.queue_free()
	await get_tree().process_frame

	# ===== 收尾：还原 =====
	d.inventory = backup_inv
	d.equipment_slots = backup_eq
	d.treasure_slots = backup_tr
	d.warehouse = backup_wh
	d.talisman_stock = backup_stock
	CharacterPanel._refresh_bag()

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
