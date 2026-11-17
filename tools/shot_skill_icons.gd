extends Node
## 早期三组新技能图标在功法库里的实景截图（虎妖组）
## 用法：godot --path . --windowed --resolution 1600x900 tools/shot_skill_icons.tscn -- --no-save

func _ready() -> void:
	get_tree().create_timer(40.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT SKILL ICONS TIMEOUT")
		get_tree().quit(2))
	for sid in ["skill_tiger_claw", "skill_tiger_rock", "skill_tiger_sandstorm",
			"skill_tiger_stomp", "skill_tiger_orb"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	for g in SkillDB.get_library_groups():
		for raw in (g as Dictionary).get("skills", []):
			if String((raw as Dictionary).get("skill_id", "")) == "skill_tiger_claw":
				panel._expanded[String((g as Dictionary).get("group_id", ""))] = true
	panel._refresh_content()
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := panel.content.get_parent() as ScrollContainer
	var anchor: Control = null
	for n in panel.find_children("*", "Label", true, false):
		if String((n as Label).text).contains("虎爪裂空"):
			anchor = n as Control
			break
	if anchor != null and scroll != null:
		scroll.ensure_control_visible(anchor)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/skill_icons_tiger_group.png")
	print("SHOT output/skill_icons_tiger_group.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
