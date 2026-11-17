extends Node
## 丹炉 UI smoke（2026-11-01）：药谱抽屉要能显示元婴五味材料与五张丹方。

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
	print("\n########## 丹炉元婴药谱 UI smoke ##########")
	var backup: Array = CharacterData.inventory.duplicate(true)
	CharacterData.inventory = []
	for mid in ["mat_yy_xuecao", "mat_yy_lanyingcao", "mat_yy_liyuanguo",
			"mat_yy_falinghua", "mat_yy_huguteng"]:
		CharacterData.add_item({"id": mid, "type": "material", "count": 2,
			"name": ItemDB.get_material_name(mid)})
	var panel := AlchemyPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().create_timer(0.4, true, false, true).timeout
	panel._toggle_drawer()
	await get_tree().process_frame
	var text := ""
	for n in panel.find_children("*", "Label", true, false):
		text += String((n as Label).text) + "\n"
	for pill_name in ["元婴回春丹", "元婴聚灵丹", "元婴巨力丹", "元婴灵法丹", "元婴金刚丹"]:
		_check(text.contains(String(pill_name)), "药谱出现 " + String(pill_name))
	for mid in ["幽冥血参", "幽冥蓝萤草", "幽冥力元果", "幽冥法灵花", "幽冥护骨藤"]:
		_check(text.contains(String(mid)), "药谱出现药材 " + String(mid))
	panel.close()
	CharacterData.inventory = backup
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
