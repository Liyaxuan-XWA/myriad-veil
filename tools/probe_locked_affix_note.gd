extends Node
## 固定词条「不可强化」标注探针（2026-11-04 用户要求：长夜刃的「精力 +1」要写明）
## 用法：godot --headless --path . tools/probe_locked_affix_note.tscn -- --no-save

const NOTE := "（固定属性，不可强化）"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 改版前的旧口径，用来证明「除了标注，其它一个字都没变」
func _legacy_text(attrs: Dictionary) -> String:
	if attrs.is_empty():
		return ""
	var parts := PackedStringArray()
	for id in AttributeDB.all_ids():
		if not attrs.has(id):
			continue
		var v := float(attrs[id])
		if is_zero_approx(v):
			continue
		parts.append("%s %s" % [AttributeDB.attr_name(String(id)),
			AttributeDB.format_value(String(id), v)])
	return "　".join(parts)


func _tpl(eid: String) -> Dictionary:
	return ItemDB.get_equipment_template(eid)


func _ready() -> void:
	CharacterData.current_realm = "化神"
	CharacterData.grant_material_guaranteed("mat_duanzaojingshi", 5000)

	var changye := CharacterData.make_equipment_instance(_tpl("eq_changye_ren"))
	var t1 := ItemDB.item_attributes_text(changye)
	var t2 := ItemDB.item_attributes_with_gain_text(changye)
	_check(t1.contains("精力 1" + NOTE), "装备详情：精力词条带标注", t1)
	_check(t2.contains("精力 +1.0" + NOTE), "锻造台铭牌：精力词条带标注", t2)
	_check(t1.count(NOTE) == 1 and t2.count(NOTE) == 1, "只标注一次不多刷", "%s / %s" % [t1, t2])
	_check(t1.contains("力量 26"), "正常词条照常显示", t1)

	# 分隔符与顺序不能被改动
	_check(t2.split("、").size() == 3, "铭牌仍用顿号分三条", t2)
	_check(t1.split("　").size() == 3, "详情仍用全角空格分三条", t1)

	# 全库影响面：只有长夜刃被标注
	var flagged: Array[String] = []
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		var tpl: Dictionary = raw
		if String(tpl.get("equipment_type", "")) == "treasure":
			continue
		if ItemDB.item_attributes_text(tpl).contains(NOTE):
			flagged.append(String(tpl.get("equipment_id", "")))
	_check(flagged.size() == 1 and flagged[0] == "eq_changye_ren",
		"全库只有长夜刃出现该标注", str(flagged))

	# 与旧口径逐条等价（把标注去掉后必须一字不差）
	var same := true
	var diff := ""
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		var tpl: Dictionary = raw
		if String(tpl.get("equipment_type", "")) == "treasure":
			continue
		var now := ItemDB.item_attributes_text(tpl).replace(NOTE, "")
		var old := _legacy_text(ItemDB.item_attributes(tpl))
		if now != old:
			same = false
			diff = "%s\n      新[%s]\n      旧[%s]" % [String(tpl.get("equipment_id", "")), now, old]
			break
	_check(same, "除标注外与旧口径完全一致", diff)

	# 强化一锤后，增量括号仍然写在数值后面
	CharacterData.current_realm = "化神"
	var hammered := false
	var after := ""
	for i in 40:
		var res: Dictionary = CharacterData.enhance_item(changye)
		if not bool(res.get("ok", false)):
			break
		if not (res["attr_gains"] as Array).is_empty():
			hammered = true
			after = ItemDB.item_attributes_with_gain_text(changye)
			break
	_check(hammered and after.contains("（+") and after.contains(NOTE),
		"有增量标注时两者共存", after)

	# 精力这条永远不该被强化抽中
	var picked_stamina := false
	for i in 400:
		var it := CharacterData.make_equipment_instance(_tpl("eq_changye_ren"))
		var res: Dictionary = CharacterData.enhance_item(it)
		if not bool(res.get("ok", false)):
			continue
		for g in (res["attr_gains"] as Array):
			if String(g.get("attr_id", "")) == AttributeDB.ATTR_STAMINA_MAX:
				picked_stamina = true
	_check(not picked_stamina, "精力不参与强化抽选", str(picked_stamina))

	# 图鉴详情走同一个口径
	var entry := {
		"category": CodexDB.CAT_EQUIPMENT,
		"grade": "凡品",
		"equip_type": "weapon",
		"template": _tpl("eq_changye_ren"),
	}
	var codex_line := ""
	for ln in CodexDB.detail_lines(entry):
		if String(ln).begins_with("属性："):
			codex_line = String(ln)
	_check(codex_line.contains(NOTE), "图鉴详情同一条口径", codex_line)

	# 法宝没有词条，不能被带出标注
	var treasure_tpl: Dictionary = ItemDB.TREASURE_TEMPLATES[0]
	var tt: Dictionary = CharacterData.make_treasure_instance(treasure_tpl)
	var ttext := ItemDB.item_attributes_text(tt)
	_check(ttext == "" and not ttext.contains(NOTE), "法宝无词条不受影响", ttext)

	print("RESULT passes=", _passes, " fails=", _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)
