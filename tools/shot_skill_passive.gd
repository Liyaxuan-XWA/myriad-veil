extends Node
## 功法库「负阴抱阳」展开截图（排版回归用）
## 用法：godot --path . --windowed --resolution 1600x900 tools/shot_skill_passive.tscn -- --no-save

func _ready() -> void:
	get_tree().create_timer(40.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT SKILL PASSIVE TIMEOUT")
		get_tree().quit(2))
	for sid in ["skill_yinyang_harmony", "skill_qi_ring_heal"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var gid := ""
	for g in SkillDB.get_library_groups():
		for raw in (g as Dictionary).get("skills", []):
			if String((raw as Dictionary).get("skill_id", "")) == "skill_yinyang_harmony":
				gid = String((g as Dictionary).get("group_id", ""))
	panel._expanded[gid] = true
	panel._expanded_skills["skill_yinyang_harmony"] = true
	panel._refresh_content()
	await get_tree().process_frame
	await get_tree().process_frame
	var detail := panel.find_child("SkillDetail_skill_yinyang_harmony", true, false) as Control
	var scroll := panel.content.get_parent() as ScrollContainer
	if detail != null and scroll != null:
		scroll.ensure_control_visible(detail)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/skill_passive_detail.png")
	print("SHOT output/skill_passive_detail.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
