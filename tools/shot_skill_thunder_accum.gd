extends Node
## 功法库被动「雷积·震魂」详情截图（文案排版回归用）
## 用法：godot --path . --windowed --resolution 1600x900 tools/shot_skill_thunder_accum.tscn -- --no-save

func _ready() -> void:
	get_tree().create_timer(40.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT THUNDER ACCUM TIMEOUT")
		get_tree().quit(2))
	if not CharacterData.learned_skills.has("skill_thunder_accum"):
		CharacterData.learned_skills.append("skill_thunder_accum")
	CharacterData.passive_skill_loadout = ["skill_thunder_accum"]
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
			if String((raw as Dictionary).get("skill_id", "")) == "skill_thunder_accum":
				gid = String((g as Dictionary).get("group_id", ""))
	panel._expanded[gid] = true
	panel._expanded_skills["skill_thunder_accum"] = true
	panel._refresh_content()
	await get_tree().process_frame
	await get_tree().process_frame
	var detail := panel.find_child("SkillDetail_skill_thunder_accum", true, false) as Control
	var scroll := panel.content.get_parent() as ScrollContainer
	if detail != null and scroll != null:
		scroll.ensure_control_visible(detail)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/skill_thunder_accum_detail.png")
	print("SHOT output/skill_thunder_accum_detail.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
