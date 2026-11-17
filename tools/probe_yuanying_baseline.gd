extends Node
## 元婴区数值基线：用现有装备模板把六个槽拉到「元婴初期 · 道器 +N」，
## 只打印面板，不改存档。用来反推幽冥灵墟的小怪 / 野修数值。
## 用法：godot --headless --path . tools/probe_yuanying_baseline.tscn -- --no-save

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


func _build(stage: int, enh: int) -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = stage
	for slot in CharacterData.SLOT_ORDER:
		CharacterData.equipment_slots[slot] = null
	var slots := ["weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3"]
	for i in GEAR.size():
		CharacterData.equipment_slots[slots[i]] = _mk(String(GEAR[i]), "道器", enh)


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


func _ready() -> void:
	await get_tree().process_frame
	for enh in [4, 6, 8, 10]:
		_build(0, enh)
		_report("元婴初期 · 道器 +%d" % enh)
	_build(1, 6)
	_report("元婴中期 · 道器 +6")
	get_tree().quit(0)
