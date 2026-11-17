extends Node
## 晏无咎 · 真实战斗箱庭截图（劫灰战场 + 三灾轮 + 招式）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_wujiu_arena.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	for sid in ["skill_calamity_step", "skill_calamity_slash",
			"skill_calamity_fire_seal", "skill_calamity_fire_field",
			"skill_calamity_thunder_strike", "skill_calamity_thunder_pool",
			"skill_calamity_turn", "skill_calamity_final"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	player.set_physics_process(false)
	boss.set_physics_process(false)
	boss.state = 0
	boss.state_timer = 0.0
	boss._current_skill = ""
	if boss.skin != null:
		boss.skin.cancel_one_shot()
	boss.anim.modulate = Color.WHITE
	player.global_position = Vector2(0.0, 210.0)
	boss.global_position = Vector2(0.0, 20.0)
	boss.target = player
	await get_tree().create_timer(4.0, true, false, true).timeout
	await _shot("wujiu_arena_idle.png")

	boss._begin("form_calamity_slash")
	await get_tree().create_timer(0.30, true, false, true).timeout
	await _shot("wujiu_arena_slash_windup.png")
	boss.state = 0
	boss._current_skill = ""
	if boss.skin != null:
		boss.skin.cancel_one_shot()

	boss._begin("form_calamity_turn")
	await get_tree().create_timer(0.40, true, false, true).timeout
	await _shot("wujiu_arena_turn_windup.png")
	boss._fire_skill()
	await get_tree().create_timer(0.14, true, false, true).timeout
	await _shot("wujiu_arena_turn_strike.png")
	await get_tree().create_timer(0.8, true, false, true).timeout

	boss._fusion_left = 8.0
	boss._momentum = 3
	boss._refresh_hud()
	player.calamity_element = "thunder"
	player.calamity_momentum = 2
	player._refresh_calamity_hud()
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("wujiu_arena_fusion.png")
	boss._fusion_left = 0.0
	boss._calamity = "fire"
	boss._refresh_hud()

	boss._begin("form_calamity_fire_field")
	await get_tree().create_timer(0.5, true, false, true).timeout
	boss._fire_skill()
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _shot("wujiu_arena_fire_field.png")
	await get_tree().create_timer(1.0, true, false, true).timeout
	get_tree().quit()
