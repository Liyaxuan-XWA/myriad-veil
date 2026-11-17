extends Node
## 眩晕头顶星 · 真实箱庭截图（赫连霄战场）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_stun_fx.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
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
	player.set_physics_process(false)
	boss.set_physics_process(false)
	boss.state = 0
	boss.state_timer = 0.0
	boss._current_skill = ""
	boss._gather_left = 0.0
	if boss.skin != null:
		boss.skin.cancel_one_shot()
	boss._clear_laws()
	boss.anim.modulate = Color.WHITE
	player.global_position = Vector2(0.0, 210.0)
	player.anim.scale = Vector2(absf(player.anim.scale.x), player.anim.scale.y)
	boss.global_position = Vector2(0.0, 20.0)
	boss.target = player
	await get_tree().create_timer(3.8, true, false, true).timeout
	await _shot("stun_fx_idle.png")

	boss.stun_for(4.0)
	player.apply_debuff("stun", 4.0, true)
	await get_tree().create_timer(0.45, true, false, true).timeout
	await _shot("stun_fx_both.png")

	get_tree().quit()
