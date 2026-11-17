extends Node
## 大世界里放「一剑开天 / 万剑归宗」并连拍（窗口化）
## godot --path . --resolution 1280x720 res://tools/shot_world_skill_fx.tscn -- --no-save

const WORLD := "res://scenes/world/secret_world.tscn"

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/%s.png" % tag)
	print("SHOT output/%s.png" % tag)

func _ready() -> void:
	var w: Node = (load(WORLD) as PackedScene).instantiate()
	add_child(w)
	for i in 8:
		await get_tree().process_frame
	var p: Node2D = w.get("player")
	p.set_physics_process(false)
	p.set("sword_intent", p.call("_sword_intent_max"))
	# 把玩家摆到空地中央，镜头跟过去
	p.global_position = Vector2(5330.0, 3420.0)
	for i in 10:
		await get_tree().process_frame
	p.call("_cast_skill", "skill_sword_heaven")
	await get_tree().create_timer(0.20).timeout
	await _shot("world_heaven_charge")
	await get_tree().create_timer(0.35).timeout
	await _shot("world_heaven_land")
	await get_tree().create_timer(0.9).timeout
	p.set("sword_intent", p.call("_sword_intent_max"))
	p.call("_cast_skill", "skill_sword_myriad")
	await get_tree().create_timer(0.30).timeout
	await _shot("world_myriad")
	for i in 30:
		await get_tree().process_frame
	print("done")
	get_tree().quit(0)
