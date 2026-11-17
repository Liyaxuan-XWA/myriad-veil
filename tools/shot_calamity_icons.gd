extends Node
## 功法库「晏无咎功法」展开截图：核对火灾·燎原 / 万劫归一图标
## 用法：godot --path . --windowed --resolution 1600x900 tools/shot_calamity_icons.tscn -- --no-save

const CALAMITY_IDS: Array = [
	"skill_calamity_step", "skill_calamity_slash",
	"skill_calamity_fire_seal", "skill_calamity_fire_field",
	"skill_calamity_thunder_strike", "skill_calamity_thunder_pool",
	"skill_calamity_turn", "skill_calamity_final", "skill_calamity_body",
]


func _ready() -> void:
	get_tree().create_timer(40.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT CALAMITY ICONS TIMEOUT")
		get_tree().quit(2))
	for sid in CALAMITY_IDS:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	panel._expanded["boss_03_c"] = true
	panel._refresh_content()
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := panel.content.get_parent() as ScrollContainer
	var anchor: Control = null
	for n in panel.find_children("*", "TextureRect", true, false):
		var tr := n as TextureRect
		var tex := tr.texture
		if tex != null and String(tex.resource_path).contains("skill_calamity_final"):
			anchor = tr
			break
	if anchor != null and scroll != null:
		scroll.ensure_control_visible(anchor)
	for i in 6:
		await get_tree().process_frame
	if scroll != null:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/calamity_icons.png")
	print("SHOT output/calamity_icons.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
