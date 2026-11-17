extends Node
## 大世界死亡掉落提示 · 截图
## 用法：godot --path . --resolution 1280x720 res://tools/shot_world_death_warn.tscn -- --no-save

const WORLD_SCENE := "res://scenes/world/secret_world.tscn"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"legacy": true}
	GameState.battle_context = {}
	var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await _frames(10)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/world_death_warn.png")
	print("SHOT output/world_death_warn.png")
	get_tree().quit(0)
