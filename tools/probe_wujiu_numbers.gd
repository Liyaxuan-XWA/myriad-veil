extends Node
## 晏无咎数值复核：结丹后期玩家面板反推（2026-10-29）
## 用法：godot --headless --path . res://tools/probe_wujiu_numbers.tscn
## 只打印、不改存档；用来复核 20,500 血 / 108 攻在宝器 +4 / +6 下的 TTK 与单发占比。

const ENH_AVG := {
	"strength": 1.5, "spell_power": 1.0, "hp_max": 3.0,
	"physical_resist": 1.0, "magic_resist": 1.0, "mana_max": 3.0,
	"mana_regen": 0.75, "speed_pct": 0.3, "attack_speed": 1.0,
	"spell_skill_damage_pct": 0.75, "stamina_regen_pct": 0.75,
}

const GEAR := ["eq_qingfengjian", "eq_jinwen_zhanpao", "eq_zhuri_lv",
	"eq_liangyi_yujue", "eq_qihai_yuzhui", "eq_leiwen_huqi"]


func _mk(id: String, grade: String, enh: int) -> Dictionary:
	var tpl := ItemDB.get_equipment_template(id)
	var it := CharacterData.make_equipment_instance(tpl)
	var asc := maxi(0, ItemDB.grade_index(grade) - ItemDB.grade_index(String(it.get("equipment_grade", ""))))
	var attrs: Dictionary = {}
	var base = it.get("attributes_base", {})
	for k in base.keys():
		attrs[String(k)] = float(base[k])
	for i in asc:
		for k in attrs.keys():
			attrs[k] = float(attrs[k]) * 1.5
	for k in attrs.keys():
		if ENH_AVG.has(k):
			attrs[k] = float(attrs[k]) + float(ENH_AVG[k]) * float(enh)
	it["attributes"] = attrs
	it["equipment_grade"] = grade
	it["enhancement_level"] = enh
	return it


func _build(realm: String, stage: int, grade: String, enh: int) -> void:
	CharacterData.current_realm = realm
	CharacterData.realm_stage = stage
	for slot in CharacterData.SLOT_ORDER:
		CharacterData.equipment_slots[slot] = null
	var slots := ["weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3"]
	for i in GEAR.size():
		CharacterData.equipment_slots[slots[i]] = _mk(String(GEAR[i]), grade, enh)


func _report(tag: String) -> void:
	var hp := CharacterData.max_hp()
	var phys := CharacterData.physical_attack()
	var spell := CharacterData.spell_attack()
	var one := CharacterData.calc_physical_damage(false, false, false)
	var fin := CharacterData.calc_physical_damage(true, false, false)
	var combo := one * 2.0 + fin
	var t := CharacterData.attack_interval()
	var cycle := t * 2.0 + t * 1.42
	var avg := combo / 3.0
	print("\n===== %s =====" % tag)
	print("气血 %.0f  物攻 %.1f  法攻 %.1f  物抗 %.1f（%.1f%%）  法抗 %.1f（%.1f%%）  间隔 %.3fs" % [
		hp, phys, spell,
		CharacterData.attribute(AttributeDB.ATTR_PHYSICAL_RESIST),
		AttributeDB.resist_reduction(CharacterData.attribute(AttributeDB.ATTR_PHYSICAL_RESIST)) * 100.0,
		CharacterData.attribute(AttributeDB.ATTR_MAGIC_RESIST),
		AttributeDB.resist_reduction(CharacterData.attribute(AttributeDB.ATTR_MAGIC_RESIST)) * 100.0,
		t])
	print("三段一轮 %.1f / %.2fs；满速 %.1f DPS；2.5 刀/秒 %.1f；2.0 刀/秒 %.1f" % [
		combo, cycle, combo / cycle, avg * 2.5, avg * 2.0])
	var dps25 := avg * 2.5
	for uptime in [0.6, 0.7, 0.75]:
		print("  有效 %.0f%% → 19,500 血约 %.0f 秒；20,500 血约 %.0f 秒" % [
			float(uptime) * 100.0, 19500.0 / (dps25 * float(uptime)),
			20500.0 / (dps25 * float(uptime))])
	print("BOSS 108 攻单下（过抗）：")
	var final_coeff := float(MoveDB.resolve_boss("form_calamity_final").get("damage_coeff", 1.90))
	for pair in [["风步 0.80 物", 0.80, "physical", ""],
			["断空斩 0.95 物", 0.95, "physical", ""],
			["焚天印 1.05 火", 1.05, "elemental", "fire"],
			["燎原 0.65 火", 0.65, "elemental", "fire"],
			["引雷诀 1.15 雷", 1.15, "elemental", "thunder"],
			["雷池 0.55 雷", 0.55, "elemental", "thunder"],
			["轮转 0.60 混", 0.60, "elemental", "fire"],
			["万劫归一 %.2f 混" % final_coeff, final_coeff, "elemental", "fire"]]:
		var raw: float = 108.0 * float(pair[1])
		var p2: float = raw * 1.25
		var kind := String(pair[2])
		var elem := String(pair[3])
		var taken: float = float(DamageCalc.incoming(raw, CharacterData, kind, elem).get("amount", raw))
		var taken2: float = float(DamageCalc.incoming(p2, CharacterData, kind, elem).get("amount", p2))
		print("  %s：%.1f（%.1f%%） / P2 %.1f（%.1f%%）" % [
			String(pair[0]), taken, taken / hp * 100.0, taken2, taken2 / hp * 100.0])


func _ready() -> void:
	await get_tree().process_frame
	_build("结丹", 2, "宝器", 4)
	_report("结丹后期 · 宝器 +4")
	_build("结丹", 2, "宝器", 6)
	_report("结丹后期 · 宝器 +6")
	get_tree().quit(0)
