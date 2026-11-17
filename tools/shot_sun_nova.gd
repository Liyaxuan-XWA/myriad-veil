extends Node
## 日冕焚心实景截图：满层引燃标记 + 1 秒后体内爆开
## 用法：godot --path . --resolution 1280x720 res://tools/shot_sun_nova.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	for sid in ["skill_sun_step", "skill_sun_slash", "skill_sun_throw", "skill_sun_pull",
			"skill_sun_wind", "skill_sun_eclipse", "skill_sun_wheel", "skill_sun_meteor"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03_b",
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
	player._refresh_sun_unlock()
	await get_tree().create_timer(3.8).timeout

	var seed: SunSeed = player._find_sun_seed()
	if seed == null:
		boss._seed_respawn_left = 0.0
		boss._tick_seed(0.0)
		seed = boss._seed
	if seed != null and is_instance_valid(seed):
		seed.steal_by(player)
		seed.global_position = player.global_position + Vector2(0.0, -46.0)
		seed.set_claim_lock(0.0)
		seed.stacks = 3
		seed._unstable_left = 999.0
		player._tick_sun(0.0)
		player._sun_handle_cast("skill_sun_slash", Vector2.UP)
		await get_tree().create_timer(0.32).timeout
		await _shot("sun_nova_mark.png")
		await get_tree().create_timer(0.85).timeout
		await _shot("sun_nova_burst.png")
	get_tree().quit()
