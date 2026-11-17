extends Node

func _ready() -> void:
	GameState.battle_context = {
		"source": "world_core",
		"region_id": "world_zhuji",
		"boss_id": "world_core_zhuji",
	}
	var arena = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().create_timer(0.8, true, false, true).timeout
	var card = arena.find_child("BossIntroCard", true, false)
	if card != null:
		card.call("_dismiss")
	await get_tree().create_timer(1.2, true, false, true).timeout
	var boss = arena.get_node_or_null("Boss")
	if boss != null:
		boss.call("_start_core_skill", SecretWorldDB.CORE_SKILLS_ZHUJI[0].duplicate(true))
	await get_tree().create_timer(0.80, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/cangjiao_skill_gore.png")
	print("SHOT output/cangjiao_skill_gore.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
