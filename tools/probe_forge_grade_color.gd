extends Node
## 锻造台品阶色探针（2026-11-01）：
## 铁砧上装备名 / 铭牌名必须按 equipment_grade 使用 UIKit.grade_color 同一套七色环。

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
	print("\n########## 锻造台品阶色探针 ##########")
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var base_item := {}
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		base_item = CharacterData.make_equipment_instance(raw as Dictionary)
		if not base_item.is_empty():
			break
	_check(not base_item.is_empty(), "取得一件测试装备")
	var seen := {}
	# 装备模板本身都是凡品，品阶由进阶改变；这里只改实例字段验证 UI 着色。
	for grade in ["凡品", "法器", "灵器", "宝器", "道器", "仙器"]:
		var item: Dictionary = base_item.duplicate(true)
		item["equipment_grade"] = grade
		panel._anvil_item = item
		panel._refresh_content()
		var expected := UIKit.grade_color(grade)
		var equip_color: Color = panel._equip_name.get_theme_color("font_color")
		var plaque_color: Color = panel._plaque_name.get_theme_color("font_color")
		_check(equip_color == expected and plaque_color == expected,
			"砧上与铭牌同品阶色 · " + grade,
			"%s / %s / 期望 %s" % [equip_color, plaque_color, expected])
		seen[grade] = true

	_check(seen.size() >= 3, "至少覆盖三种品阶", str(seen.keys()))
	panel._anvil_item = {}
	panel._refresh_content()
	_check(panel._plaque_name.text == "空砧", "空砧铭牌回到空态")
	panel.queue_free()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
