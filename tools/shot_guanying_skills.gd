extends Node
## 观澜 · 功法库图标 / 组规则截图
## 用法：godot --path . --resolution 1280x720 res://tools/shot_guanying_skills.tscn -- --no-save

func _ready() -> void:
	for sid in ["skill_mirror_slash", "skill_mirror_thrust", "skill_mirror_bloom",
			"skill_mirror_shatter", "skill_mirror_swap", "skill_mirror_return",
			"skill_mirror_ring", "skill_mirror_myriad", "skill_mirror_echo"]:
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
			if String((raw as Dictionary).get("skill_id", "")) == "skill_mirror_slash":
				panel._expanded[String((g as Dictionary).get("group_id", ""))] = true
	panel._refresh_content()
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := panel.content.get_parent() as ScrollContainer
	var anchor: Control = null
	for n in panel.find_children("*", "Label", true, false):
		if String((n as Label).text).contains("镜水斩"):
			anchor = n as Control
			break
	if anchor != null and scroll != null:
		scroll.ensure_control_visible(anchor)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/guanying_skill_library.png")
	print("SHOT output/guanying_skill_library.png")
	get_tree().quit(0)
