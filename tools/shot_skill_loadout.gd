extends Node
## 功法库「当前搭配」截图：带图标的 4 键槽（含空槽） + 槽位选择器
## 用法：godot --path . --windowed --resolution 1600x900 tools/shot_skill_loadout.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	get_tree().create_timer(40.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT LOADOUT TIMEOUT")
		get_tree().quit(2))
	for sid in ["skill_blade_slash", "skill_blade_scar", "skill_blade_peak",
			"skill_sword_stab", "skill_sword_myriad", "skill_tiger_stomp",
			"skill_yinyang_harmony", "skill_qi_ring_heal"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = [
		"skill_blade_slash", "", "skill_sword_myriad", "skill_tiger_stomp",
	]
	CharacterData.passive_skill_loadout = ["skill_yinyang_harmony"]
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	await _shot("skill_loadout_slots.png")
	panel._request_slot(1)
	for i in 6:
		await get_tree().process_frame
	await _shot("skill_loadout_slot_picker.png")
	panel._request_key_for("skill_blade_scar")
	for i in 6:
		await get_tree().process_frame
	await _shot("skill_loadout_key_picker.png")
	panel._request_passive()
	for i in 6:
		await get_tree().process_frame
	await _shot("skill_loadout_passive_picker.png")
	get_tree().quit()
