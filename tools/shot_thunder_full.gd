extends Node
## 满雷势 · 平A协同雷击截图（赫连霄战场）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_thunder_full.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	CharacterData.learned_skills.append("skill_thunder_verdict")
	CharacterData.active_skill_loadout = ["skill_thunder_verdict"]
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	player.global_position = Vector2(-130.0, 130.0)
	player._refresh_thunder_unlock()
	player.lei_shi = 3
	player._refresh_thunder_hud()
	boss.global_position = Vector2(0.0, 0.0)
	player.attack_dir = (boss.global_position - player.global_position).normalized()
	boss.target = null
	boss.set_physics_process(false)
	boss.state = 0
	boss.state_timer = 0.0
	boss._current_skill = ""
	boss._gather_left = 0.0
	if boss.skin != null:
		boss.skin.cancel_one_shot()
	boss._clear_laws()
	boss.anim.modulate = Color.WHITE
	await get_tree().create_timer(3.8, true, false, true).timeout
	await _shot("thunder_full_idle.png")

	player._perform_attack_hit()
	await get_tree().create_timer(0.04, true, false, true).timeout
	await _shot("thunder_full_coop.png")
	get_tree().quit()
