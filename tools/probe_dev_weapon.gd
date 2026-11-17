extends Node
## 开发者武器「房主神器」（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_dev_weapon.tscn -- --no-save
##
## 口径：力量 +9999999 / 最高品阶 / 不配美术（icon 空）/ 只在编辑器 F2 调试面板获取。
## 判据：
##   · 模板与实例字段；
##   · 装备图鉴里**没有**它（dev_only）；
##   · 试炼 BOSS 兜底掉落池**没有**它（dev_only）；
##   · 任何 DROP_TEMPLATES 都不指向它；
##   · F2 面板真的列出它，点「获取」真的进背包。

const ID := "eq_fangzhu_shenqi"

var _passes := 0
var _fails: Array = []
var _saved_inv: Array = []
var _saved_new: Dictionary = {}
var _saved_seen: Dictionary = {}


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


func _ready() -> void:
	print("\n########## 开发者武器 · 房主神器 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved_inv = CharacterData.inventory.duplicate(true)
	_saved_new = CharacterData.bag_new_ids.duplicate(true)
	_saved_seen = CharacterData.bag_seen_ids.duplicate(true)
	var tpl := ItemDB.get_equipment_template(ID)
	_check(not tpl.is_empty(), "模板存在", ID)
	if tpl.is_empty():
		return
	_check(String(tpl.get("equipment_name", "")) == "房主神器", "名字 = 房主神器",
		String(tpl.get("equipment_name", "")))
	_check(String(tpl.get("equipment_grade", "")) == "神器/先天至宝", "品质 = 最高品阶",
		String(tpl.get("equipment_grade", "")))
	_check(String(tpl.get("equipment_type", "")) == "weapon", "类型 = 武器")
	_check(bool(tpl.get("dev_only", false)), "带 dev_only 标记")
	_check(String(tpl.get("icon", "")) == "", "不配美术（icon 为空 → 首字占位）")
	var attrs = tpl.get("attributes", {})
	_check(attrs is Dictionary
			and is_equal_approx(float((attrs as Dictionary).get(AttributeDB.ATTR_STRENGTH, 0.0)), 9999999.0),
		"力量 +9999999", str((attrs as Dictionary).get(AttributeDB.ATTR_STRENGTH, 0.0)))
	_check(ItemDB.is_max_grade(String(tpl.get("equipment_grade", ""))), "is_max_grade = true")

	var item := CharacterData.make_equipment_instance(tpl)
	_check(int(item.get("enhancement_limit", 0)) == ItemDB.MAX_ENHANCE, "实例强化上限按通用口径")
	_check(float((item.get("attributes", {}) as Dictionary).get(AttributeDB.ATTR_STRENGTH, 0.0)) == 9999999.0,
		"实例力量 = 9999999")
	_check(String(item.get("equipment_grade", "")) == "神器/先天至宝", "实例品阶 = 最高")

	# ===== 图鉴里没有它 =====
	var in_codex := false
	for e in CodexDB.category_entries(CodexDB.CAT_EQUIPMENT):
		if String((e as Dictionary).get("id", "")) == ID:
			in_codex = true
	_check(not in_codex, "装备图鉴不收录开发者武器")

	# ===== 试炼 BOSS 兜底掉落池没有它 =====
	seed(20261113)
	var leaked := false
	for i in 400:
		var drop := RogueDB.roll_boss_gear("__probe_no_such_boss__")
		if String(drop.get("id", "")) == ID:
			leaked = true
			break
	_check(not leaked, "试炼兜底掉落 400 次都不出开发者武器")

	# ===== 任何 BOSS 掉表都不指向它 =====
	var in_drops := false
	for boss_id in ItemDB.DROP_TEMPLATES.keys():
		for raw in (ItemDB.DROP_TEMPLATES[boss_id] as Array):
			if String((raw as Dictionary).get("item_id", "")) == ID:
				in_drops = true
	_check(not in_drops, "DROP_TEMPLATES 里没有任何条目指向它")

	# ===== F2 面板列出它，点「获取」进背包 =====
	var panel := DebugItemPanel.new()
	add_child(panel)
	await _frames(3)
	var listed := false
	for c in panel.find_children("*", "Label", true, false):
		if String((c as Label).text).begins_with("房主神器"):
			listed = true
			break
	_check(listed, "F2 调试面板列出「房主神器」")
	panel.call("_grant_equipment", tpl, false)
	await _frames(2)
	var got := {}
	for raw in CharacterData.inventory:
		if String((raw as Dictionary).get("id", "")) == ID:
			got = raw
			break
	_check(not got.is_empty(), "点「获取」后进入背包")
	if not got.is_empty():
		_check(float((got.get("attributes", {}) as Dictionary).get(AttributeDB.ATTR_STRENGTH, 0.0)) == 9999999.0
				and String(got.get("equipment_grade", "")) == "神器/先天至宝",
			"进包实例带着力量 9999999 与最高品阶")
	panel.queue_free()
	await _frames(2)

	# 还原背包
	CharacterData.inventory.clear()
	CharacterData.inventory.append_array(_saved_inv)
	CharacterData.bag_new_ids = _saved_new
	CharacterData.bag_seen_ids = _saved_seen
	print("")
