extends Node
## 全元素与抗性接口自检：八元素注册、法术元素覆盖、风/雷/暗抗性结算。

class DummyTarget extends Node:
	var resist := {"fire": 0.0, "wind": 100.0, "thunder": 0.0}
	var phys_resist := 0.0
	var magic_resist := 0.0
	## 暗「蚀」的穿抗乘区：探针里直接摆数值，验证打折发生在 DamageCalc 结算层、不在属性层
	var shred := 0.0
	func attribute(attr_id: String) -> float:
		if attr_id == "physical_resist":
			return phys_resist
		if attr_id == "magic_resist":
			return magic_resist
		if attr_id.begins_with("resist_"):
			return float(resist.get(attr_id.trim_prefix("resist_"), 0.0))
		return 0.0
	func element_resist(element: String) -> float:
		return float(resist.get(element, 0.0))
	func debuff_resist_shred() -> float:
		return shred

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
	print("\n########## 全元素 · 抗性接口探针 ##########")
	_check(AttributeDB.ELEMENTS.size() == 8, "八元素已注册（11-05 加暗）",
		str(AttributeDB.ELEMENTS))
	_check(AttributeDB.attr_name("resist_wind") == "风抗", "风抗显示名")
	_check(AttributeDB.attr_name("resist_thunder") == "雷抗", "雷抗显示名")
	_check(AttributeDB.attr_name("resist_dark") == "暗抗", "暗抗显示名")
	_check(CharacterData.BASE_ATTRIBUTE_DEFAULTS.has("resist_wind")
		and CharacterData.BASE_ATTRIBUTE_DEFAULTS.has("resist_thunder")
		and CharacterData.BASE_ATTRIBUTE_DEFAULTS.has("resist_dark"),
		"玩家基础抗性含风/雷/暗")

	var target := DummyTarget.new()
	add_child(target)
	var wind_hit := DamageCalc.incoming(100.0, target, "elemental", "wind")
	var thunder_hit := DamageCalc.incoming(100.0, target, "elemental", "thunder")
	var phys_hit := DamageCalc.incoming(100.0, target, "physical", "wind")
	_check(is_equal_approx(float(wind_hit.get("amount", 0.0)), 50.0),
		"风抗 100 → 法术风伤减半", "%.1f" % float(wind_hit.get("amount", 0.0)))
	_check(is_equal_approx(float(thunder_hit.get("amount", 0.0)), 100.0),
		"雷抗 0 → 法术雷伤不减", "%.1f" % float(thunder_hit.get("amount", 0.0)))
	_check(is_equal_approx(float(phys_hit.get("amount", 0.0)), 100.0),
		"物理伤害不吃元素抗性", "%.1f" % float(phys_hit.get("amount", 0.0)))
	_check(is_equal_approx(DamageCalc.element_reduction(target, "wind"), 0.5),
		"单元素减免接口", "%.2f" % DamageCalc.element_reduction(target, "wind"))

	var missing: Array[String] = []
	var neutral: Array[String] = []
	var bad_thunder: Array[String] = []
	for raw in SkillDB.SKILLS:
		var skill: Dictionary = raw
		var sid := String(skill.get("skill_id", ""))
		if SkillDB.get_spell_coeff(sid) <= 0.0:
			continue
		var elem := SkillDB.get_damage_element(sid)
		if elem == "":
			missing.append(sid)
		elif elem == "none":
			neutral.append(sid)
		elif not AttributeDB.is_element(elem):
			missing.append(sid + ":" + elem)
		if (bool(skill.get("thunder", false))
				or String(skill.get("calamity_tag", "")) == "thunder") \
				and elem != "thunder":
			bad_thunder.append(sid + ":" + elem)
	_check(missing.is_empty(), "全部法术功法都有元素", str(missing))
	_check(bad_thunder.is_empty(), "雷系功法统一 thunder", str(bad_thunder))
	_check(neutral.size() <= 5, "无属性仅限混伤/动态招式", str(neutral))

	# ===== 暗 · 蚀（2026-11-05 用户定：暗 = 通用属性，配一条专属机制）=====
	var de := DebuffDB.get_debuff("dark_erosion")
	_check(not de.is_empty(), "蚀已登记进 DebuffDB")
	_check(is_equal_approx(float(de.get("resist_shred", 0.0)),
			AttributeDB.DARK_EROSION_RESIST_SHRED),
			"蚀的穿抗数值单一来源（表 = AttributeDB）",
			"%.2f" % float(de.get("resist_shred", 0.0)))
	_check(is_equal_approx(float(de.get("heal_mult", 1.0)),
			AttributeDB.DARK_EROSION_HEAL_MULT),
			"蚀的减疗乘区 = 0.10（减疗 90%）",
			"%.2f" % float(de.get("heal_mult", 1.0)))
	# 蚀是「按目标堆的减免按比例吃掉」，不是又一档无条件增伤：
	# 抗 0 完全无感、抗越高收益越大 —— 这条曲线就是暗的定位（破硬）。
	var dt := DummyTarget.new()
	add_child(dt)
	for row in [[0.0, 100.0, 100.0], [40.0, 71.43, 80.65], [100.0, 50.0, 62.5],
			[200.0, 33.33, 45.45]]:
		dt.phys_resist = row[0]
		dt.shred = 0.0
		var plain := float(DamageCalc.incoming(100.0, dt, "physical", "").get("amount", 0.0))
		dt.shred = AttributeDB.DARK_EROSION_RESIST_SHRED
		var eroded := float(DamageCalc.incoming(100.0, dt, "physical", "").get("amount", 0.0))
		_check(absf(plain - row[1]) < 0.2 and absf(eroded - row[2]) < 0.2,
				"物抗 %.0f 无蚀 %.1f%% / 蚀后 %.1f%%（多挨 %.1f%%）" % [
				row[0], plain, eroded, (eroded / maxf(plain, 0.01) - 1.0) * 100.0],
				"%.2f / %.2f" % [plain, eroded])
	# 面板不许撒谎：蚀只打折结算，attribute() 必须仍是真实抗性
	dt.shred = 0.0
	var shown := float(dt.attribute("physical_resist"))
	dt.shred = AttributeDB.DARK_EROSION_RESIST_SHRED
	_check(is_equal_approx(float(dt.attribute("physical_resist")), shown),
			"蚀不改 attribute()：面板显示的仍是真实抗性", "%.0f" % shown)
	# 法术段：法抗与元素抗两层叠乘的防护，被蚀一起打穿
	dt.phys_resist = 0.0
	dt.magic_resist = 100.0
	dt.resist["dark"] = 100.0
	dt.shred = 0.0
	var spell_plain := float(DamageCalc.incoming(100.0, dt, "elemental", "dark").get("amount", 0.0))
	dt.shred = AttributeDB.DARK_EROSION_RESIST_SHRED
	var spell_eroded := float(DamageCalc.incoming(100.0, dt, "elemental", "dark").get("amount", 0.0))
	_check(spell_plain < 26.0 and spell_eroded > spell_plain * 1.5,
			"法术段：法抗与暗抗两层都吃蚀",
			"%.1f -> %.1f" % [spell_plain, spell_eroded])
	# 持续按暗抗缩短：这是 resist_dark 目前唯一的用处
	_check(is_equal_approx(AttributeDB.dark_erosion_time(0.0),
			AttributeDB.DARK_EROSION_TIME),
			"暗抗 0 到 蚀满 6 秒", "%.1f" % AttributeDB.dark_erosion_time(0.0))
	_check(is_equal_approx(AttributeDB.dark_erosion_time(100.0), 3.0),
			"暗抗 100 到 蚀只剩 3 秒（暗抗从此有明确价值）",
			"%.1f" % AttributeDB.dark_erosion_time(100.0))
	_check(AttributeDB.DARK_EROSION_REFRESH_CD > AttributeDB.DARK_EROSION_TIME,
			"刷新 CD 必须长于持续，否则覆盖率拉满 = 常驻",
			"%.0f > %.0f" % [AttributeDB.DARK_EROSION_REFRESH_CD,
					AttributeDB.DARK_EROSION_TIME])
	dt.free()

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
