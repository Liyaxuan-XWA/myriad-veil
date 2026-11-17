extends Node
## 特效工坊面板版式截图（2026-11-04）
## 面板本体是编辑器插件，这里用鸭子类型替身把它当普通 Control 跑起来看版式。
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_pixelfx_studio.tscn -- --no-save

class Stub:
	func get_library_path() -> String:
		return "E:/skill/game/pixelfx"

	func get_node_path() -> String:
		return "node"

	func get_output_dir() -> String:
		return "res://assets/fx/pixelfx"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var panel = preload("res://addons/pixelfx_studio/studio_panel.gd").new()
	panel.plugin = Stub.new()
	panel.name = "StudioPanel"
	add_child(panel)
	panel.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var bosses: Array = panel._groups
	var bi := -1
	for i in bosses.size():
		if String((bosses[i] as Dictionary).get("boss_name", "")).contains("剑客"):
			bi = i
			break
	if bi < 0 and not bosses.is_empty():
		bi = 0
	panel._boss_pick.selected = bi
	panel._on_boss_selected()
	await get_tree().process_frame
	var heads: Array[String] = []
	for i in mini(4, panel._rows.size()):
		heads.append(String((panel._rows[i] as Dictionary).get("skill_name", "?")))
	print("MODE0 rows=", panel._rows.size(), " boss=", bi, " 招式=", heads)
	if not panel._rows.is_empty():
		panel._on_pick(0)
		await get_tree().process_frame
		var cands: Array = panel._rows
		var baked_i := -1
		for i in cands.size():
			if not PixelFxLib.baked_variants(String((cands[i] as Dictionary).get("id", ""))).is_empty():
				baked_i = i
				break
		var top_name := "?"
		var top_matched := []
		if not cands.is_empty():
			top_name = String((cands[0] as Dictionary).get("name", "?"))
			top_matched = (cands[0] as Dictionary).get("_matched", [])
		print("CAND count=", cands.size(), " top=", top_name, " matched=", top_matched,
			" baked_i=", baked_i)
		if baked_i >= 0:
			panel._on_pick(baked_i)
	for i in 20:
		await get_tree().process_frame
	await _shot("pixelfx_studio_by_skill.png")
	panel._set_mode(1)
	await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	await _shot("pixelfx_studio_by_category.png")
	get_tree().quit(0)
