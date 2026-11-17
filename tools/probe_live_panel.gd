extends Node
## 只读：载入最近存档，打印元婴后期实际面板（--no-save，不写盘）

func _ready() -> void:
	var ok := SaveManager.load_latest_auto()
	print("LOAD ", ok, "  ", CharacterData.current_realm, " ", CharacterData.realm_stage)
	print("HP %.1f / %.1f  STA %.1f  MANA %.1f" % [
		CharacterData.max_hp(), CharacterData.max_hp(),
		CharacterData.max_stamina(), CharacterData.max_mana()])
	print("物攻 %.1f  法攻 %.1f  攻速 %.1f%%  间隔 %.3f" % [
		CharacterData.physical_attack(), CharacterData.spell_attack(),
		CharacterData.attribute(AttributeDB.ATTR_ATTACK_SPEED),
		CharacterData.attack_interval()])
	print("法技增伤 x%.3f" % CharacterData.spell_skill_damage_mult())
	var one := CharacterData.calc_physical_damage(false, false, false)
	var fin := CharacterData.calc_physical_damage(true, false, false)
	var combo := one * 2.0 + fin
	var cycle := CharacterData.attack_interval() * 2.0 + CharacterData.attack_interval() * 1.42
	print("普攻三段 %.1f / %.2fs = %.1f DPS；单段 %.1f / 终结 %.1f" % [
		combo, cycle, combo / cycle, one, fin])
	print("物抗 %.1f (%.1f%%)  法抗 %.1f (%.1f%%)" % [
		CharacterData.attribute(AttributeDB.ATTR_PHYSICAL_RESIST),
		AttributeDB.resist_reduction(CharacterData.attribute(AttributeDB.ATTR_PHYSICAL_RESIST)) * 100.0,
		CharacterData.attribute(AttributeDB.ATTR_MAGIC_RESIST),
		AttributeDB.resist_reduction(CharacterData.attribute(AttributeDB.ATTR_MAGIC_RESIST)) * 100.0])
	print("火抗 %.1f (%.1f%%)  水抗 %.1f  雷抗 %.1f" % [
		CharacterData.attribute("resist_fire"),
		AttributeDB.resist_reduction(CharacterData.attribute("resist_fire")) * 100.0,
		CharacterData.attribute("resist_water"), CharacterData.attribute("resist_thunder")])
	for slot in CharacterData.SLOT_ORDER:
		var it = CharacterData.get_equipped(slot)
		if it is Dictionary and not (it as Dictionary).is_empty():
			print("  ", slot, " ", it.get("equipment_name", it.get("treasure_name", it.get("id", ""))),
				" +", it.get("enhancement_level", 0))
	for sid in ["skill_mirror_slash", "skill_mirror_thrust", "skill_mirror_shatter",
			"skill_mirror_ring", "skill_mirror_myriad"]:
		var form := SkillDB.get_skill_form(sid)
		if form.is_empty():
			continue
		var coeff := SkillDB.get_spell_coeff(sid) + SkillDB.get_phys_coeff(sid)
		var sample := CharacterData.calc_skill_damage(sid, false, false)
		print("  ", sid, " 系数%.2f 单次≈%.0f" % [coeff, sample])
	get_tree().quit(0)
