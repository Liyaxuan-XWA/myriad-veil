extends Node
## 图鉴二级分类自检：装备按部件、法宝按类型、材料按境界、BOSS 按来源。

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ids(category: String) -> Array:
	var out: Array = []
	for raw in CodexDB.subcategories(category):
		out.append(String((raw as Dictionary).get("id", "")))
	return out


func _summarize(category: String) -> Dictionary:
	var total := CodexDB.category_entries(category, CodexDB.SUB_ALL).size()
	var parts: Array = []
	var sums := 0
	for sid in _ids(category):
		if sid == CodexDB.SUB_ALL:
			continue
		var n := CodexDB.category_entries(category, sid).size()
		sums += n
		parts.append([sid, n])
	return {"total": total, "parts": parts, "sum": sums}


func _ready() -> void:
	print("\n########## 图鉴二级分类探针 ##########")
	var eq := _summarize(CodexDB.CAT_EQUIPMENT)
	_check(_ids(CodexDB.CAT_EQUIPMENT) == [
		CodexDB.SUB_ALL, CodexDB.SUB_WEAPON, CodexDB.SUB_ARMOR,
		CodexDB.SUB_SHOES, CodexDB.SUB_ACCESSORY],
		"装备二级分类：全部 / 武器 / 护甲 / 鞋子 / 饰品", str(eq["parts"]))
	_check(eq["sum"] == eq["total"], "装备各部件无重叠且覆盖全部",
		"%d / %d" % [eq["sum"], eq["total"]])
	_check(CodexDB.category_entries(CodexDB.CAT_EQUIPMENT, CodexDB.SUB_WEAPON).size() == 10,
		"武器分类 10 把（含镜潭尺 / 长夜刃 / 纸错剑 / 问天剑）", str(CodexDB.category_entries(CodexDB.CAT_EQUIPMENT,
			CodexDB.SUB_WEAPON).size()))

	var treasure := _summarize(CodexDB.CAT_TREASURE)
	_check(treasure["sum"] == treasure["total"], "法宝类型无重叠且覆盖全部",
		"%d / %d" % [treasure["sum"], treasure["total"]])
	var material := _summarize(CodexDB.CAT_MATERIAL)
	_check(material["sum"] == material["total"], "材料境界无重叠且覆盖全部",
		"%d / %d" % [material["sum"], material["total"]])
	var boss_count := CodexDB.category_entries(CodexDB.CAT_BOSS, CodexDB.SUB_ALL).size()
	var floor_count := CodexDB.category_entries(CodexDB.CAT_BOSS, CodexDB.SUB_FLOOR).size()
	var world_count := CodexDB.category_entries(CodexDB.CAT_BOSS, CodexDB.SUB_WORLD).size()
	_check(floor_count + world_count == boss_count, "BOSS 位面/大陆分类覆盖全部",
		"%d + %d = %d" % [floor_count, world_count, boss_count])

	var view := CodexView.new()
	add_child(view)
	await get_tree().process_frame
	var eq_index := -1
	for i in CodexDB.categories().size():
		if String((CodexDB.categories()[i] as Dictionary).get("id", "")) == CodexDB.CAT_EQUIPMENT:
			eq_index = i
			break
	view._show_category(eq_index)
	await get_tree().process_frame
	_check(view._sub_bar != null and view._sub_bar.visible, "装备页显示二级分类条")
	_check(view._sub_buttons.size() == 5, "装备页五个分类按钮",
		str(view._sub_buttons.size()))
	view._show_sub(CodexDB.SUB_WEAPON)
	await get_tree().process_frame
	_check(view._sub_id == CodexDB.SUB_WEAPON, "切到武器分类")
	var expected := CodexDB.category_entries(CodexDB.CAT_EQUIPMENT,
		CodexDB.SUB_WEAPON).size()
	_check(view._list_box.get_child_count() >= expected, "武器分类列表已刷新",
		"cards=%d expected=%d" % [view._list_box.get_child_count(), expected])

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
