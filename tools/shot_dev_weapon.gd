extends Node
## 开发者武器「房主神器」 · 截图验收（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_dev_weapon.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/%s.png" % name)
	print("SHOT output/%s.png" % name)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"legacy": true}
	var realm = (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(realm)
	await _frames(2)
	get_tree().current_scene = realm
	await _frames(4)

	# ① F2 面板：滚到底看「房主神器」
	var panel := DebugItemPanel.new()
	get_tree().root.add_child(panel)
	await _frames(4)
	panel.visible = true
	await _frames(3)
	for c in panel.find_children("*", "ScrollContainer", true, false):
		var sc := c as ScrollContainer
		sc.scroll_vertical = 100000
	await _frames(3)
	await _shot("dev_weapon_f2")

	# ② 获取 → 背包详情
	panel.call("_grant_equipment", ItemDB.get_equipment_template("eq_fangzhu_shenqi"), false)
	panel.visible = false
	CharacterPanel.open_panel()
	await _frames(6)
	CharacterPanel.call("_on_filter_pressed", CharacterData.ITEM_EQUIPMENT, null)
	await _frames(4)
	var slot: Control = null
	for c in (CharacterPanel.get("_bag_grid") as Node).get_children():
		var it = c.get("item")
		if it is Dictionary and String((it as Dictionary).get("id", "")) == "eq_fangzhu_shenqi":
			slot = c as Control
			break
	if slot != null:
		(slot as Button).pressed.emit()
	await _frames(4)
	await _shot("dev_weapon_bag")
	get_tree().quit(0)
