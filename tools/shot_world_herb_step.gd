extends Node
## 采草药完成指引 · 截图验收（2026-11-13）
## 出两张：
##   ① 采药前 —— 卡片「出门采第一株药」，人站在真的草药旁
##   ② 采药后 —— 卡片换成「打死一只灵兽或野修」（这一步已记完成）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_world_herb_step.tscn -- --no-save

const WORLD_SCENE := "res://scenes/world/secret_world.tscn"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/%s.png" % name)
	print("SHOT output/%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"done": {}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	GameState.battle_context = {}
	var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await _frames(10)
	get_tree().current_scene = w
	await _frames(4)
	var herb: WorldResource = null
	for raw in (w.get("_resources") as Dictionary).values():
		if raw is WorldResource and (raw as WorldResource).kind == WorldResource.KIND_HERB:
			herb = raw as WorldResource
			break
	if herb == null:
		print("没有草药")
		get_tree().quit(1)
		return
	var wp: Node2D = w.get("player")
	wp.set_physics_process(false)
	wp.global_position = herb.global_position + Vector2(0.0, 46.0)
	await _frames(6)
	print("step=", Tutorial.active_step.get("id", ""))
	await _shot("herb_step_before")
	w.call("_on_interact")
	await _frames(8)
	print("step_after=", Tutorial.active_step.get("id", ""), " done=", Tutorial.is_done("c8_gather"))
	await _shot("herb_step_after")
	get_tree().quit(0)
