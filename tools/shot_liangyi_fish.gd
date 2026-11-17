extends Node

func _ready() -> void:
	GameState.battle_context = {
		"source": "domain",
		"domain_id": "domain_02",
		"boss_id": "boss_02",
	}
	var arena = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().create_timer(0.8, true, false, true).timeout
	var card = arena.find_child("BossIntroCard", true, false)
	if card != null:
		card.call("_dismiss")
	await get_tree().create_timer(1.2, true, false, true).timeout
	var boss = arena.get_node_or_null("Boss")
	var player = get_tree().get_first_node_in_group("player")
	if boss != null:
		boss.set("target", player)
		boss.call("_update_facing_to_target")
		boss.call("_cast_fish", MoveDB.resolve_boss("form_yinyang_fish"))
	await get_tree().create_timer(0.38, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/liangyi_fish.png")
	print("SHOT output/liangyi_fish.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
