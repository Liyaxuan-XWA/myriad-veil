extends Node
## 折痕佩新图标：锻造挂签实机截图（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_zhehen_icon.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"
const EID := "eq_zhehen_pei"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.inventory.clear()
	var item := CharacterData.make_equipment_instance(ItemDB.get_equipment_template(EID))
	CharacterData.inventory.append(item)
	var realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await _frames(2)
	get_tree().current_scene = realm
	await _frames(4)
	var panel := ForgePanel.new()
	panel.set("_tutorial_seen", true)
	get_tree().root.add_child(panel)
	await _frames(6)
	panel.call("open")
	await _frames(8)
	panel.call("_refresh_content")
	await _frames(6)

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/zhehen_icon_panel.png")
	var grid: GridContainer = panel.get("_bag_grid")
	var tag: Control = null
	for c in grid.get_children():
		var it = c.get("item")
		if it is Dictionary and String((it as Dictionary).get("id", "")) == EID:
			tag = c as Control
			break
	if tag == null:
		print("TAG missing")
		get_tree().quit(1)
		return
	var r := tag.get_global_rect()
	var pad := 6
	img.get_region(Rect2i(int(r.position.x) - pad, int(r.position.y) - pad,
		int(r.size.x) + pad * 2, int(r.size.y) + pad * 2)).save_png(
		"output/zhehen_icon_tag.png")
	print("SHOT output/zhehen_icon_panel.png / zhehen_icon_tag.png  tag=", r)

	panel.call("close")
	await _frames(3)
	get_tree().quit(0)
