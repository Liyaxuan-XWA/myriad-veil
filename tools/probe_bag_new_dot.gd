extends Node
## 背包「首次获得」红点（2026-11-12 用户定）
## 用法：godot --headless --path . res://tools/probe_bag_new_dot.tscn -- --no-save
##
## 口径：第一次获得才亮（同 id 一辈子一次）；**点开详情才清**；看过之后再获得不再亮。
## ⚠ 走真实控件：从 _bag_grid 里捞那一格、按它的 pressed（BagSlot → CharacterPanel._on_item_selected）。

const ITEM := "mat_xuecao"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _give(n: int = 1) -> void:
	var def := ItemDB.get_material(ITEM)
	CharacterData.add_item({
		"id": ITEM, "name": String(def.get("name", ITEM)), "type": "material",
		"count": n, "icon": String(def.get("icon", "")), "desc": "",
	})


func _slot_of(item_id: String) -> Control:
	var grid: Control = CharacterPanel.get("_bag_grid")
	if grid == null:
		return null
	for c in grid.get_children():
		var it = c.get("item")
		if it is Dictionary and String((it as Dictionary).get("id", "")) == item_id:
			return c as Control
	return null


func _ready() -> void:
	print("\n########## 背包 · 首次获得红点 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# ===== 1. 数据层：只亮一次、看过就不亮 =====
	CharacterData.bag_new_ids.erase(ITEM)
	CharacterData.bag_seen_ids.erase(ITEM)
	_check(not CharacterData.is_bag_new(ITEM), "初始：不是新东西")
	_give()
	_check(CharacterData.is_bag_new(ITEM), "第一次获得：记成「新的」")
	_give()
	_check(CharacterData.is_bag_new(ITEM), "重复获得：仍是同一颗（不会叠出第二颗）")

	# ===== 2. 背包格：右上角真的有红点 =====
	CharacterPanel.open_panel()
	await _frames(3)
	CharacterPanel.call("_on_filter_pressed", CharacterData.ITEM_MATERIAL, null)
	await _frames(3)
	var slot := _slot_of(ITEM)
	_check(slot != null, "背包里找到这格")
	_check(slot != null and slot.get_node_or_null("NewDot") != null, "格子右上角有红点")
	# 点开详情 → 红点清掉、格子重画
	if slot != null:
		(slot as Button).pressed.emit()
	await _frames(3)
	_check(not CharacterData.is_bag_new(ITEM), "点开详情：红点状态清掉")
	var slot2 := _slot_of(ITEM)
	_check(slot2 != null and slot2.get_node_or_null("NewDot") == null, "格子重画后红点消失")

	# ===== 3. 看过之后再获得：不再亮（一辈子一次） =====
	_give()
	_check(not CharacterData.is_bag_new(ITEM), "看过的东西再次获得：不再亮红点")
	CharacterPanel.close_panel()
	await _frames(2)
	print("")
