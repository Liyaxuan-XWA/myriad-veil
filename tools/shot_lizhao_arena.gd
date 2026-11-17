extends Node
## 离照 · 真实战斗箱庭截图（焚天祭坛 + 天火种 + 招式）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_lizhao_arena.tscn

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
	await get_tree().create_timer(3.8, true, false, true).timeout
	await _shot("lizhao_arena_idle.png")

	# 天火种落在两人之间
	boss._seed_respawn_left = 0.0
	boss._tick_seed(0.0)
	var seed: SunSeed = boss._seed
	if seed != null:
		seed.global_position = Vector2(0.0, 120.0)
		seed._claim_lock = 0.0
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("lizhao_arena_seed.png")

	# BOSS 持种：日冕读数 + 减伤光
	if seed != null and is_instance_valid(seed):
		seed.steal_by(boss)
		seed.set_claim_lock(0.0)
		seed.stacks = 2
		boss._tick_seed(0.0)
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _shot("lizhao_arena_seed_boss.png")

	boss._begin("form_sun_slash")
	await get_tree().create_timer(0.36, true, false, true).timeout
	await _shot("lizhao_arena_slash_windup.png")
	boss._fire_skill()
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _shot("lizhao_arena_slash_strike.png")

	# 日蚀预警
	if seed != null and is_instance_valid(seed):
		seed.drop(player.global_position)
		seed._claim_lock = 0.0
	boss._current_skill = "form_sun_eclipse"
	boss._fire_skill()
	await get_tree().create_timer(0.22, true, false, true).timeout
	await _shot("lizhao_arena_eclipse_warn.png")
	await get_tree().create_timer(0.45, true, false, true).timeout
	await _shot("lizhao_arena_eclipse_burst.png")
	await get_tree().create_timer(0.8, true, false, true).timeout

	# 玩家投日：火种沿抛物线飞行，抓 4 帧看轨迹（不瞬移）
	boss._seed_respawn_left = 0.0
	boss._tick_seed(0.0)
	await get_tree().create_timer(0.2, true, false, true).timeout
	var fly_seed: SunSeed = boss._seed
	if fly_seed != null and is_instance_valid(fly_seed):
		fly_seed.steal_by(player)
		fly_seed.set_claim_lock(0.0)
		player._sun_handle_cast("skill_sun_throw", Vector2.UP)
		await get_tree().create_timer(0.04, true, false, true).timeout
		await _shot("lizhao_seed_flight_a.png")
		await get_tree().create_timer(0.045, true, false, true).timeout
		await _shot("lizhao_seed_flight_b.png")
		await get_tree().create_timer(0.045, true, false, true).timeout
		await _shot("lizhao_seed_flight_c.png")
		await get_tree().create_timer(0.15, true, false, true).timeout
		await _shot("lizhao_seed_flight_land.png")
	get_tree().quit()
