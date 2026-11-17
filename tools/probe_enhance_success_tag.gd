extends Node
## 强化词条次数探针（2026-11-01 建，2026-11-02 改为按词条次数计）：
##   普通成功 +1；大成功一次加两条词条，按实际升的强化级数 +2
##   （+9 时大成功被上限夹成 +1，就只记 1）；进阶敲击不计。
## 兵器架挂签左上角绿色「成N」与右上 +N、右下失败数并存。

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
	print("\n########## 强化词条次数探针 ##########")
	var tpl: Dictionary = {}
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		if String((raw as Dictionary).get("equipment_type", "")) == "weapon":
			tpl = raw
			break
	_check(not tpl.is_empty(), "取得武器模板")
	if tpl.is_empty():
		get_tree().quit(1)
		return

	# 1) 计数规则：每次成功按实际升的强化级数累加；失败不动；观测一次大成功 +2
	var backup_inv: Array = CharacterData.inventory.duplicate(true)
	CharacterData.inventory = []
	CharacterData.grant_material(CharacterData.ENHANCE_MATERIAL, 600)
	var rule_ok := true
	var normal_ok := true
	var fail_ok := true
	var great_ok := false
	var tried := 0
	while not great_ok and tried < 25:
		tried += 1
		var test_item := CharacterData.make_equipment_instance(tpl)
		for i in 80:
			if int(test_item.get("enhancement_level", 0)) >= ItemDB.MAX_ENHANCE:
				break
			var before := int(test_item.get("enhance_success_count", 0))
			var res := CharacterData.enhance_item(test_item)
			if not bool(res.get("ok", false)):
				break
			var result := String(res.get("result", ""))
			var after := int(test_item.get("enhance_success_count", 0))
			var delta := int(res.get("enhance_after", 0)) - int(res.get("enhance_before", 0))
			if result == ItemDB.ENHANCE_RESULT_GREAT:
				if after - before != delta:
					rule_ok = false
				if delta == 2 and after - before == 2:
					great_ok = true
					break
			elif result == ItemDB.ENHANCE_RESULT_SUCCESS:
				if after - before != 1 or delta != 1:
					normal_ok = false
			elif result in [ItemDB.ENHANCE_RESULT_FAIL, ItemDB.ENHANCE_RESULT_BROKEN]:
				if after != before:
					fail_ok = false
			if result == ItemDB.ENHANCE_RESULT_BROKEN:
				break
	_check(rule_ok, "成功按实际升的强化级数累加")
	_check(normal_ok, "普通成功记 1 次")
	_check(fail_ok, "失败不增加词条次数")
	_check(great_ok, "大成功记 2 次", "尝试 %d 件装备" % tried)

	# 2) 挂签显示：左上「成N」、右上「+N」、右下失败数
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var item := CharacterData.make_equipment_instance(tpl)
	item["enhance_success_count"] = 12
	item["enhancement_level"] = 3
	item["enhance_fail_count"] = mini(ItemDB.ENHANCE_FAIL_LIMIT, 2)
	var tag := ForgeTagSlot.new()
	tag.setup(item, panel, "bag", 0)
	add_child(tag)
	await get_tree().process_frame
	var success_lbl: Label = null
	var enh_lbl: Label = null
	var fail_lbl: Label = null
	for n in tag.find_children("*", "Label", true, false):
		var l := n as Label
		if l.text == "成12":
			success_lbl = l
		elif l.text == "+%d" % int(item.get("enhancement_level", 0)):
			enh_lbl = l
		elif l.text == "2":
			fail_lbl = l
	_check(success_lbl != null, "左上显示累计词条次数")
	if success_lbl != null:
		_check(success_lbl.anchor_left == 0.0 and success_lbl.anchor_top == 0.0,
			"词条次数在左上角")
		_check(success_lbl.get_theme_color("font_color") == Color(0.16, 0.44, 0.19),
			"词条次数为绿色")
	_check(enh_lbl != null and enh_lbl.anchor_left == 1.0, "强化等级仍在右上角")
	_check(fail_lbl != null and fail_lbl.anchor_left == 1.0 and fail_lbl.anchor_top == 1.0,
		"失败次数仍在右下角")
	_check(tag.tooltip_text.contains("累计强化词条 12 次（大成功计 2 次）"),
		"tooltip 写明大成功计 2 次")

	CharacterData.inventory = backup_inv
	panel.queue_free()
	tag.queue_free()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
