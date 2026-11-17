extends Node
## 背包丢弃规则探针（2026-11-01）：
## 丹药 / 普通材料可丢，突破材料不可丢；丢弃按钮与批量选中同步；丹药丢空时清轮盘格。

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _buttons_text() -> String:
	var parts := PackedStringArray()
	for n in CharacterPanel._detail_actions.find_children("*", "Button", true, false):
		parts.append((n as Button).text)
	return " ".join(parts)


func _select(item: Dictionary) -> void:
	var idx := CharacterData.inventory.find(item)
	CharacterPanel._on_item_selected(item, idx)


func _ready() -> void:
	print("\n########## 背包丢弃规则探针 ##########")
	var backup: Array = CharacterData.inventory.duplicate(true)
	CharacterData.inventory = []
	var pill := {"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 2}
	var herb := {"id": "mat_ruishoupi", "name": "青岚兽皮", "type": "material", "count": 1}
	var crystal := {"id": "mat_pojing_zhuji", "name": "筑基破境晶", "type": "material", "count": 1}
	CharacterData.inventory = [pill, herb, crystal]
	CharacterPanel._refresh_bag()

	_select(pill)
	_check(_buttons_text().contains("丢弃"), "丹药有丢弃按钮", _buttons_text())
	_select(herb)
	_check(_buttons_text().contains("丢弃"), "普通材料有丢弃按钮", _buttons_text())
	_select(crystal)
	_check(_buttons_text().contains("不可丢弃") and not _buttons_text().contains(" 丢弃"),
		"突破材料没有可点击丢弃按钮", _buttons_text())

	# 批量选中：丹药/材料可选，突破材料不可选
	CharacterPanel._discard_sel.clear()
	CharacterPanel._toggle_discard_pick(pill)
	CharacterPanel._toggle_discard_pick(crystal)
	_check(CharacterPanel._discard_sel.size() == 1
		and is_same(CharacterPanel._discard_sel[0], pill), "突破材料不能被批量选中")

	# 真的丢弃丹药；突破材料即使调用删除也被守卫拦下
	CharacterPanel._do_single_discard(pill)
	_check(CharacterData.count_item("pill_julidan") == 0, "丹药可真正丢弃")
	CharacterPanel._do_single_discard(crystal)
	_check(CharacterData.count_item("mat_pojing_zhuji") == 1, "突破材料删除被守卫拦下")

	CharacterData.inventory = backup
	CharacterPanel._refresh_bag()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
