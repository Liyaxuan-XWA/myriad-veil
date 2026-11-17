extends Node
## 观澜 · 照影界真实箱庭截图（含地面 / 倒影 / 水光）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_guanying_arena.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 0
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	var boss: Node2D = arena.boss
	var player: Node2D = arena.player
	if player != null:
		player.invincible_timer = 999.0
		player.global_position = boss.global_position + Vector2(-90.0, 60.0)
	await get_tree().create_timer(0.6).timeout
	await _shot("guanying_arena_idle.png")

	boss.call("_play_form_anim", "form_mirror_slash", 1.0)
	await get_tree().create_timer(0.52).timeout
	await _shot("guanying_arena_slash.png")
	await get_tree().create_timer(0.6).timeout

	boss.call("_cast_bloom", MoveDB.resolve_boss("form_mirror_bloom"))
	await get_tree().create_timer(0.2).timeout
	boss.call("_cast_bloom", MoveDB.resolve_boss("form_mirror_bloom"))
	await get_tree().create_timer(0.5).timeout
	await _shot("guanying_arena_images.png")
	# 二阶段：镜像必须同步转红
	boss.current_hp = boss.max_hp * 0.49
	boss.take_damage(1.0, player, "physical", "")
	await get_tree().create_timer(1.2).timeout
	boss.call("_cast_bloom", MoveDB.resolve_boss("form_mirror_bloom"))
	await get_tree().create_timer(0.5).timeout
	await _shot("guanying_arena_phase2.png")
	# 玩家侧镜像：同源贴图，按玩家站位生成；确认尺寸与脚底对齐
	boss.set_physics_process(false)
	boss.set_process(false)
	for raw in boss._images:
		if is_instance_valid(raw):
			raw.queue_free()
	boss._images.clear()
	player._mirror_clear_images()
	player._mirror_spawn(player.global_position + Vector2(55.0, 18.0))
	player._mirror_spawn(player.global_position + Vector2(-55.0, 18.0))
	await get_tree().create_timer(0.4).timeout
	await _shot("guanying_player_images.png")
	get_tree().quit(0)
