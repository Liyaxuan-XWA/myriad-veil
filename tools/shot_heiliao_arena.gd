extends Node
## 赫连霄 · 真实战斗箱庭截图（赤霄界战场 + 雷印贴花 + 招式）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_heiliao_arena.tscn

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
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	player.set_physics_process(false)
	boss.set_physics_process(false)
	# 冻结前可能已经自动起手：强制回待机，避免截到半招
	boss.state = 0
	boss.state_timer = 0.0
	boss._current_skill = ""
	boss._gather_left = 0.0
	if boss.skin != null:
		boss.skin.cancel_one_shot()
	boss._clear_laws()
	boss.anim.modulate = Color.WHITE
	player.global_position = Vector2(0.0, 210.0)
	boss.global_position = Vector2(0.0, 20.0)
	boss.target = player
	# 等开场大字幕淡出（HINT 3s + fade 0.6s）
	await get_tree().create_timer(3.8, true, false, true).timeout
	await _shot("heiliao_arena_idle.png")

	boss._begin("form_thunder_verdict")
	await get_tree().create_timer(0.35, true, false, true).timeout
	await _shot("heiliao_arena_verdict_windup.png")
	boss._fire_skill()
	await get_tree().create_timer(0.18, true, false, true).timeout
	await _shot("heiliao_arena_verdict_strike.png")

	boss._lei_shi = 3
	boss._refresh_pips()
	boss._current_skill = "form_thunder_nine"
	boss._fire_skill()
	await get_tree().create_timer(0.55, true, false, true).timeout
	await _shot("heiliao_arena_nine.png")
	await get_tree().create_timer(0.9, true, false, true).timeout
	get_tree().quit()
