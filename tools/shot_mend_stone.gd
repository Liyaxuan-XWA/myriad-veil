extends Node
## 补天石 / 铸神晶：红色品质 + 不可丢弃 · 截图（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_mend_stone.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"legacy": true}
	var realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await _frames(2)
	get_tree().current_scene = realm
	await _frames(4)
	CharacterData.inventory.clear()
	CharacterData.grant_material("mat_zhushenjing", 1)
	CharacterData.grant_material("mat_butianshi", 7)
	CharacterPanel.open_panel()
	await _frames(6)
	CharacterPanel.call("_on_filter_pressed", CharacterData.ITEM_MATERIAL, null)
	await _frames(4)
	for c in (CharacterPanel.get("_bag_grid") as Node).get_children():
		var it = c.get("item")
		if it is Dictionary and String((it as Dictionary).get("id", "")) == "mat_butianshi":
			(c as Button).pressed.emit()
			break
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/mend_stone_bag.png")
	print("SHOT output/mend_stone_bag.png")
	get_tree().quit(0)
