extends Node
## 被动槽自检（2026-10-30）：只能带 1 门、满槽拒绝第二门、卸下可换、旧档只留第一门
## 用法：godot --headless --path . tools/probe_passive_slot.tscn -- --no-save

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 被动槽探针 ##########")
	CharacterData.learned_skills = [
		"skill_yinyang_harmony", "skill_sun_wheel", "skill_qi_ring_heal",
	]
	CharacterData.passive_skill_loadout = []

	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame

	_check(SkillPanel.MAX_PASSIVE == 1 and CharacterData.MAX_PASSIVE_SKILLS == 1,
		"被动槽上限 = 1")
	var row_text := ""
	for n in panel.find_children("*", "Label", true, false):
		var t := String((n as Label).text)
		if t.contains("被动功法"):
			row_text = t
	_check(row_text.contains("0 / 1"), "功法库显示 0 / 1", row_text)

	panel._on_equip("skill_yinyang_harmony", false)
	_check(CharacterData.passive_skill_loadout == ["skill_yinyang_harmony"],
		"装配第一门被动", str(CharacterData.passive_skill_loadout))
	panel._on_equip("skill_sun_wheel", false)
	_check(CharacterData.passive_skill_loadout == ["skill_yinyang_harmony"],
		"满槽时拒绝第二门", str(CharacterData.passive_skill_loadout))
	panel._on_unequip("skill_yinyang_harmony", false)
	panel._on_equip("skill_sun_wheel", false)
	_check(CharacterData.passive_skill_loadout == ["skill_sun_wheel"],
		"卸下后可换另一门", str(CharacterData.passive_skill_loadout))

	CharacterData.passive_skill_loadout = ["skill_sun_wheel", "skill_yinyang_harmony"]
	CharacterData.trim_passive_loadout()
	_check(CharacterData.passive_skill_loadout == ["skill_sun_wheel"],
		"旧档多带只留第一门", str(CharacterData.passive_skill_loadout))

	panel.close()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
