extends Node
## 化神终境截图（2026-11-01）：确认不再显示前 / 中 / 后期，按钮为「已至顶点」。
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_realm_huashen.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var backup_realm := CharacterData.current_realm
	var backup_stage := CharacterData.realm_stage
	var backup_exp := CharacterData.realm_exp
	var backup_limit := CharacterData.current_world_realm_limit
	var backup_original := CharacterData.original_world_max_realm
	CharacterData.current_realm = CharacterData.REALM_HUASHEN
	CharacterData.realm_stage = 0
	CharacterData.realm_exp = 50000
	CharacterData.current_world_realm_limit = CharacterData.REALM_HUASHEN
	var panel := RealmPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _shot("realm_huashen.png")
	CharacterData.realm_exp = CharacterData.HUASHEN_EXP_CAP
	panel._refresh_content()
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _shot("realm_huashen_cap.png")
	panel.close()
	CharacterData.current_realm = backup_realm
	CharacterData.realm_stage = backup_stage
	CharacterData.realm_exp = backup_exp
	CharacterData.current_world_realm_limit = backup_limit
	CharacterData.original_world_max_realm = backup_original
	get_tree().quit(0)
