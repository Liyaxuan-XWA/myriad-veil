extends Node
## 锻打铭牌 · 强化词条与单次增强区间（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_forge_affix_line.tscn -- --no-save
##
## 用户原话：「在锻打铭牌里显示当前武器强化会随机增强的词条和该词条的增强范围。」
## 判据：
##   · 词条池 = 装备上所有 AttributeDB.can_enhance 的属性（强化就是从这个池子里随机挑）；
##   · 区间现算自 AttributeDB.ENHANCE_RANGE（不是写死文案）；
##   · 真实锻造台：清风剑显示「力量 +1~+2 · 精力恢复速度 +0.5%~+1.0%」；
##   · 最长的一条（三词条鞋）自动换行后仍不越出铜牌；法宝 / 不可强化 / 空砧整行收起。

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


func _tpl(eid: String) -> Dictionary:
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		if String((raw as Dictionary).get("equipment_id", "")) == eid:
			return CharacterData.make_equipment_instance(raw as Dictionary)
	return {}


func _ready() -> void:
	print("\n########## 锻打铭牌 · 强化词条区间 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	# ===== 1. 数据层：池子 + 区间现算 =====
	var qf := _tpl("eq_qingfengjian")
	_check(not qf.is_empty(), "取到清风剑实例")
	if qf.is_empty():
		return
	var pool: Array[String] = []
	for k in (qf.get("attributes", {}) as Dictionary).keys():
		if AttributeDB.can_enhance(String(k)):
			pool.append(String(k))
	_check(pool.size() == 2, "清风剑的可强化词条池 = 2（力量 / 精力恢复速度）", str(pool))
	var lines := ItemDB.enhance_range_lines(qf)
	_check(lines == ["力量 +1~+2", "精力恢复速度 +0.5%~+1.0%"],
		"区间文案 = 力量 +1~+2 / 精力恢复速度 +0.5%~+1.0%", str(lines))
	var line := ItemDB.enhance_affix_line(qf)
	_check(line == "强化随机词条：力量 +1~+2 · 精力恢复速度 +0.5%~+1.0%",
		"整行文案", line)
	# 每个数值都必须来自 ENHANCE_RANGE（改区间只改那一处，UI 自动跟上）
	var rng_str := {}
	for k in pool:
		var r := AttributeDB.enhance_range(k)
		rng_str[k] = [float(r.get("min", 0.0)), float(r.get("max", 0.0))]
	_check(is_equal_approx(float(rng_str[AttributeDB.ATTR_STRENGTH][1]), 2.0)
			and is_equal_approx(float(rng_str[AttributeDB.ATTR_STAMINA_REGEN_PCT][0]), 0.5),
		"探针独立读到区间 力量 1~2 / 精力恢复 0.5~1.0", str(rng_str))

	# ===== 1b. 2026-11-13：所有可强化词条都必须是区间，不再有固定值 =====
	var fixed_entries: Array[String] = []
	for id in AttributeDB.ENHANCE_RANGE.keys():
		var r := AttributeDB.enhance_range(String(id))
		if float(r.get("max", 0.0)) <= float(r.get("min", 0.0)) + 0.0001:
			fixed_entries.append(String(id))
	_check(fixed_entries.is_empty(), "ENHANCE_RANGE 里没有固定值词条", str(fixed_entries))
	var sp_rng := AttributeDB.enhance_range(AttributeDB.ATTR_SPELL_POWER)
	var asp_rng := AttributeDB.enhance_range(AttributeDB.ATTR_ATTACK_SPEED)
	var pres_rng := AttributeDB.enhance_range(AttributeDB.ATTR_PHYSICAL_RESIST)
	var mres_rng := AttributeDB.enhance_range(AttributeDB.ATTR_MAGIC_RESIST)
	_check(is_equal_approx(float(sp_rng.get("min", 0.0)), 1.0)
			and is_equal_approx(float(sp_rng.get("max", 0.0)), 2.0),
		"法强对齐力量：+1~+2", str(sp_rng))
	_check(is_equal_approx(float(asp_rng.get("min", 0.0)), 0.5)
			and is_equal_approx(float(asp_rng.get("max", 0.0)), 1.5),
		"攻速：+0.5%~+1.5%（均值仍 1）", str(asp_rng))
	_check(is_equal_approx(float(pres_rng.get("min", 0.0)), 0.5)
			and is_equal_approx(float(pres_rng.get("max", 0.0)), 1.5)
			and is_equal_approx(float(mres_rng.get("min", 0.0)), 0.5)
			and is_equal_approx(float(mres_rng.get("max", 0.0)), 1.5),
		"物抗 / 法抗：+0.5~+1.5（均值仍 1）", "%s / %s" % [pres_rng, mres_rng])
	var bad_lines: Array[String] = []
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		var it := CharacterData.make_equipment_instance(raw as Dictionary)
		if it.is_empty() or String(it.get("equipment_type", "")) == "treasure":
			continue
		for l in ItemDB.enhance_range_lines(it):
			if String(l).contains("固定") or not String(l).contains("~"):
				bad_lines.append(String(l))
	_check(bad_lines.is_empty(), "所有装备的铭牌词条都是区间", str(bad_lines))
	var cang := _tpl("eq_cangjiao_jia")
	var cang_lines := ItemDB.enhance_range_lines(cang)
	_check("物抗 +0.5~+1.5" in cang_lines and "木抗 +0.5~+1.5" in cang_lines,
		"抗性区间文案统一一位小数", str(cang_lines))
	var qihai := _tpl("eq_qihai_yuzhui")
	var qihai_lines := ItemDB.enhance_range_lines(qihai)
	_check(qihai_lines == ["法强 +1~+2", "灵力 +2~+4"],
		"法强 / 灵力区间文案", str(qihai_lines))
	var huqi := _tpl("eq_leiwen_huqi")
	var huqi_lines := ItemDB.enhance_range_lines(huqi)
	_check("攻速 +0.5%~+1.5%" in huqi_lines and "物抗 +0.5~+1.5" in huqi_lines,
		"攻速百分比两端都带 % / 物抗一位小数", str(huqi_lines))

	# ===== 2. 真实锻造台：铭牌上真的挂出这一行 =====
	var panel := ForgePanel.new()
	add_child(panel)
	await _frames(3)
	panel.call("open")
	await _frames(6)
	panel._anvil_item = qf
	panel.call("_refresh_content")
	await _frames(4)
	var affix: Label = panel.get("_plaque_affix") as Label
	var plaque: Control = panel.get("_plaque") as Control
	_check(affix != null and plaque != null, "取到铭牌与词条行")
	if affix != null and plaque != null:
		_check(affix.visible, "清风剑上砧：词条行可见")
		_check(affix.text == line, "铭牌文案 = 数据层整行", affix.text)
		var vbox: Node = affix.get_parent()
		_check(vbox == plaque.get_child(0), "词条行挂在铭牌内容列里")
		var pr := plaque.get_global_rect()
		var ar := affix.get_global_rect()
		_check(absf(pr.size.x - 376.0) < 1.0, "铜牌仍是设计宽度 376（词条行不许把它撑宽）",
			str(pr.size.x))
		_check(ar.end.y <= pr.end.y - 2.0, "词条行不越出铜牌底边",
			"%s vs %s" % [ar, pr])
		_check(ar.size.x <= 332.0, "一行放得下内容宽 332（未被迫横向溢出）", str(ar.size.x))
		_check(affix.get_theme_color("font_color") != UIKit.C_DANGER,
			"是信息行，不用警示红", str(affix.get_theme_color("font_color")))

	# ===== 3. 最长一条（三词条鞋）：自动换行后仍在铜牌内 =====
	var widest := {}
	var widest_w := 0.0
	var f: Font = UIKit.readable_font()
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		var it := CharacterData.make_equipment_instance(raw as Dictionary)
		if it.is_empty() or String(it.get("equipment_type", "")) == "treasure":
			continue
		var l := ItemDB.enhance_affix_line(it)
		if l == "":
			continue
		var w := f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		if w > widest_w:
			widest_w = w
			widest = it
	if not widest.is_empty():
		panel._anvil_item = widest
		panel.call("_refresh_content")
		await _frames(4)
		var ar2 := affix.get_global_rect()
		var pr2 := plaque.get_global_rect()
		_check(widest_w > 332.0, "这条确实超过一行宽（换行路径被覆盖）", "%.0f" % widest_w)
		_check(ar2.end.y <= pr2.end.y - 2.0, "换行后仍不越出铜牌底边",
			"%.0f > %.0f? %s" % [ar2.end.y, pr2.end.y, affix.text])

	# ===== 4. 法宝 / 不可强化 / 空砧：整行收起 =====
	var tr := CharacterData.make_treasure_instance(ItemDB.get_treasure_template("tr_huyao_ling"))
	_check(not tr.is_empty(), "取到法宝实例")
	panel._anvil_item = tr
	panel.call("_refresh_content")
	await _frames(3)
	_check(not affix.visible, "法宝不带词条：整行收起")
	var wj := _tpl("eq_wentian_jian")
	_check(not wj.is_empty(), "取到问天剑实例")
	panel._anvil_item = wj
	panel.call("_refresh_content")
	await _frames(3)
	_check(not affix.visible, "传家之物不可强化：整行收起")
	panel._anvil_item = {}
	panel.call("_refresh_content")
	await _frames(3)
	_check(not affix.visible, "空砧：整行收起")
	panel.call("close")
	await _frames(2)
	print("")
