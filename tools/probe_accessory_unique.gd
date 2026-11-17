extends Node
## 饰品唯一性自检（2026-10-31 用户定：不能佩戴相同的饰品）
## 覆盖：三层拦截（equip / equip_from_inventory / equip_dup_slot）、同槽换装、
## 同一对象换槽、旧档去重迁移、法宝旧规则未回归。
## 用法：godot --headless --path . tools/probe_accessory_unique.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _acc(id: String) -> Dictionary:
	return CharacterData.make_equipment_instance(ItemDB.get_equipment_template(id))


func _clear_worn() -> void:
	for slot in CharacterData.WORN_SLOT_ORDER:
		CharacterData._set_slot(String(slot), {})


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 饰品唯一性探针 ##########")
	var backup_inv: Array = CharacterData.inventory.duplicate(true)
	var backup_eq: Dictionary = CharacterData.equipment_slots.duplicate(true)
	var backup_tr: Dictionary = CharacterData.treasure_slots.duplicate(true)
	CharacterData.inventory = []
	_clear_worn()

	var a1 := _acc("eq_huyaxianglian")
	var a2 := _acc("eq_huyaxianglian")
	var b1 := _acc("eq_qihai_yuzhui")
	var c1 := _acc("eq_liangyi_yujue")

	# 1) 三种不同饰品可以占满三槽
	CharacterData.equip("accessory_1", a1)
	CharacterData.equip("accessory_2", b1)
	CharacterData.equip("accessory_3", c1)
	_check(CharacterData.is_held_by_slot(a1) and CharacterData.is_held_by_slot(b1)
		and CharacterData.is_held_by_slot(c1), "不同饰品可同时戴三件")

	# 2) equip() 最后防线：同款第二件不能进第二槽
	CharacterData.equip("accessory_2", a2)
	_check(not CharacterData.is_held_by_slot(a2), "equip() 拦截同款饰品")
	_check(is_same(CharacterData.get_equipped("accessory_2"), b1), "拦截后原槽不变")

	# 3) 强化等级不同也算同一种
	var a3 := _acc("eq_huyaxianglian")
	a3["enhancement_level"] = 3
	CharacterData.equip("accessory_2", a3)
	_check(not CharacterData.is_held_by_slot(a3), "强化等级不同仍算同款")

	# 4) equip_from_inventory 在移出背包前拦截，物品不丢
	_clear_worn()
	CharacterData.inventory = []
	CharacterData.equip("accessory_1", a1)
	CharacterData.add_item(a2)
	# add_item 会复制一份，背包里的不是 a2 本体；按新引用判定
	var bag_a2: Dictionary = CharacterData.inventory[CharacterData.inventory.size() - 1]
	var idx := CharacterData.inventory.size() - 1
	var old := CharacterData.equip_from_inventory(idx, "accessory_2")
	_check(old.is_empty() and not CharacterData.is_held_by_slot(bag_a2), "背包穿戴被拦截")
	_check(CharacterData.inventory.size() == 1, "拦截后同款仍留在背包")
	_check(is_same(CharacterData.get_equipped("accessory_1"), a1), "拦截后已戴饰品未变")

	# 5) 换装到同一槽不算重复：同槽替换为同款另一件
	old = CharacterData.equip_from_inventory(0, "accessory_1")
	_check(CharacterData.is_held_by_slot(bag_a2) and is_same(CharacterData.get_equipped("accessory_1"), bag_a2),
		"同槽换同款允许")
	_check(is_same(old, a1) and CharacterData.inventory.size() == 1
		and String(CharacterData.inventory[0].get("id", "")) == "eq_huyaxianglian",
		"被换下的同款回到背包")

	# 6) equip_dup_slot 的 except_slot / 同一对象换槽
	var dup_probe := _acc("eq_huyaxianglian")
	_check(CharacterData.equip_dup_slot(dup_probe) == "accessory_1", "查到同款占用槽")
	_check(CharacterData.equip_dup_slot(dup_probe, "accessory_1") == "", "忽略目标槽后无冲突")
	_clear_worn()
	CharacterData.inventory = []
	CharacterData.equip("accessory_1", a2)
	CharacterData.equip("accessory_2", a2)
	_check(CharacterData.is_held_by_slot(a2) and CharacterData.get_equipped("accessory_1").is_empty(),
		"同一件对象换槽不算重复")

	# 7) 旧档去重迁移：保留靠前槽，其余回背包
	_clear_worn()
	CharacterData.inventory = []
	CharacterData._set_slot("accessory_1", a1)
	CharacterData._set_slot("accessory_2", a2)
	CharacterData._set_slot("accessory_3", b1)
	var moved := CharacterData.migrate_duplicate_accessories()
	_check(moved == 1, "旧档去重挪回 1 件", str(moved))
	_check(is_same(CharacterData.get_equipped("accessory_1"), a1), "去重保留靠前槽")
	_check(CharacterData.get_equipped("accessory_2").is_empty(), "去重清空重复槽")
	_check(is_same(CharacterData.get_equipped("accessory_3"), b1), "不同款不受影响")
	_check(CharacterData.inventory.size() == 1
		and String(CharacterData.inventory[0].get("id", "")) == "eq_huyaxianglian",
		"重复件回到背包")

	# 8) 装备分背包满时也强制去重（允许临时超出上限，不吞装备）
	_clear_worn()
	CharacterData.inventory = []
	for i in CharacterData.BAG_CAP_EQUIPMENT:
		CharacterData.inventory.append({"id": "probe_fill_%d" % i, "name": "占位装备",
			"type": "equipment", "equipment_type": "weapon", "count": 1})
	CharacterData._set_slot("accessory_1", a1)
	CharacterData._set_slot("accessory_2", a2)
	moved = CharacterData.migrate_duplicate_accessories()
	_check(moved == 1 and not CharacterData.is_held_by_slot(a2), "装备包满时仍强制去重")
	_check(CharacterData.bag_count_for(CharacterData.ITEM_EQUIPMENT)
		== CharacterData.BAG_CAP_EQUIPMENT + 1
		and String(CharacterData.inventory[-1].get("id", "")) == "eq_huyaxianglian",
		"超出分背包上限一格但不吞装备",
		"装备包 %d 格" % CharacterData.bag_count_for(CharacterData.ITEM_EQUIPMENT))

	# 9) 读档入口也会去重（旧档直接带着两件同款饰品）
	var backup_snap := SaveManager.capture()
	var snap := SaveManager.capture()
	var save_a := _acc("eq_huyaxianglian")
	var save_b := _acc("eq_huyaxianglian")
	var save_c := _acc("eq_qihai_yuzhui")
	var eq_data: Dictionary = snap.get("equipment_data", {})
	for s in CharacterData.SLOT_ORDER:
		eq_data[String(s)] = null
	eq_data["accessory_1"] = save_a
	eq_data["accessory_2"] = save_b
	eq_data["accessory_3"] = save_c
	snap["equipment_data"] = eq_data
	snap["inventory_data"] = []
	SaveManager.apply(snap)
	_check(CharacterData.get_equipped("accessory_2").is_empty()
		and CharacterData.inventory.size() == 1, "读档时自动去重")
	SaveManager.apply(backup_snap)

	# 10) 法宝旧规则未回归
	CharacterData.inventory = []
	_clear_worn()
	var t1 := CharacterData.make_treasure_instance(ItemDB.get_treasure_template("tr_daoke_ling"))
	var t2 := CharacterData.make_treasure_instance(ItemDB.get_treasure_template("tr_daoke_ling"))
	CharacterData.equip("treasure_1", t1)
	CharacterData.equip("treasure_2", t2)
	_check(CharacterData.is_held_by_slot(t1) and not CharacterData.is_held_by_slot(t2),
		"同款法宝仍然不能占两个槽")

	# 11) 角色面板点击「穿戴」：给出同款提示，物品不丢
	_clear_worn()
	CharacterData.inventory = []
	CharacterData.equip("accessory_1", a1)
	CharacterData.add_item(a2)
	CharacterPanel._on_equip_from_bag(0)
	_check(String(CharacterPanel._detail.text).contains("不能重复佩戴"),
		"角色面板提示同款不能重复", String(CharacterPanel._detail.text))
	_check(CharacterData.inventory.size() == 1 and CharacterData.get_equipped("accessory_2").is_empty(),
		"角色面板拦截后物品仍在背包")

	# 恢复现场
	CharacterData.inventory = backup_inv
	CharacterData.equipment_slots = backup_eq
	CharacterData.treasure_slots = backup_tr
	CharacterPanel._refresh_bag()
	CharacterPanel._refresh_equipment()
	CharacterPanel._refresh_stats()

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
