extends Node
## 灵力恢复 ÷10 回归（2026-10-31）
## 覆盖：基础回复 / 小大突破增量 / 太虚云履词条 / 强化区间

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 灵力恢复 ÷10 探针 ##########")
	_check(is_equal_approx(float(CharacterData.BASE_ATTRIBUTE_DEFAULTS.get(
		AttributeDB.ATTR_MANA_REGEN, -1.0)), 0.3),
		"基础灵力恢复 = 0.3/秒")
	_check(is_equal_approx(CharacterData.REALM_MINOR_MANA_REGEN, 0.1),
		"小突破灵力回复 = +0.1")
	_check(is_equal_approx(CharacterData.REALM_MAJOR_MANA_REGEN, 0.3),
		"大突破灵力回复 = +0.3")
	var shoe := ItemDB.get_equipment_template("eq_taixu_yunlv")
	var attrs: Dictionary = shoe.get("attributes", {})
	_check(is_equal_approx(float(attrs.get(AttributeDB.ATTR_MANA_REGEN, -1.0)), 0.15),
		"太虚云履灵力恢复 = 0.15/秒")
	var enh: Dictionary = AttributeDB.ENHANCE_RANGE.get(AttributeDB.ATTR_MANA_REGEN, {})
	_check(is_equal_approx(float(enh.get("min", -1.0)), 0.05)
		and is_equal_approx(float(enh.get("max", -1.0)), 0.1),
		"灵力恢复强化区间 = 0.05~0.1", str(enh))
	# 灵力丹保持原值：它是有限消耗品，不属于「每秒恢复」
	var mana_pill := ItemDB.get_consumable("pill_julingdan")
	_check(is_equal_approx(float((mana_pill.get("battle_effect", {}) as Dictionary).get("ratio", -1.0)), 0.10),
		"练气回灵丹仍为 10%（本次只砍恢复属性）")

	# 旧档装备迁移：base 1.5 → 0.15，当前值同步 ÷10；再跑一次不再动
	var old_item := {
		"attributes": {AttributeDB.ATTR_MANA_REGEN: 2.75, "speed_pct": 1.0},
		"attributes_base": {AttributeDB.ATTR_MANA_REGEN: 1.5, "speed_pct": 1.0},
	}
	var fixed_once := CharacterData._fix_mana_regen_legacy_attrs(old_item)
	_check(fixed_once
		and is_equal_approx(float(old_item["attributes"][AttributeDB.ATTR_MANA_REGEN]), 0.275)
		and is_equal_approx(float(old_item["attributes_base"][AttributeDB.ATTR_MANA_REGEN]), 0.15),
		"旧档装备灵力恢复 ÷10", str(old_item["attributes"]))
	_check(not CharacterData._fix_mana_regen_legacy_attrs(old_item),
		"旧档迁移幂等（第二次不再除）")
	var new_item := {
		"attributes": {AttributeDB.ATTR_MANA_REGEN: 0.65},
		"attributes_base": {AttributeDB.ATTR_MANA_REGEN: 0.15},
	}
	_check(not CharacterData._fix_mana_regen_legacy_attrs(new_item)
		and is_equal_approx(float(new_item["attributes"][AttributeDB.ATTR_MANA_REGEN]), 0.65),
		"新装备强化值不被二次折算")
	_check(AttributeDB.format_value(AttributeDB.ATTR_MANA_REGEN, 0.15) == "0.15",
		"面板显示保留两位小数", AttributeDB.format_value(AttributeDB.ATTR_MANA_REGEN, 0.15))

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
