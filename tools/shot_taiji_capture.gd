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
	if boss == null or player == null:
		get_tree().quit(1)
		return
	boss.set("target", player)
	boss.call("_update_facing_to_target")
	boss.set_physics_process(false)
	boss.set_process(false)
	player.set("_taiji_guard_id", "tr_taiji_pan")
	player.set("_taiji_guard_left", 8.0)
	player.set("_taiji_guard_pct", 0.3)
	TreasureFx.attach_taiji_guard(player, player.call("_body_center"), 8.0)
	boss.call("_cast_fish", MoveDB.resolve_boss("form_yinyang_fish"))

	await get_tree().create_timer(0.45, true, false, true).timeout
	var captured := 0
	for raw in get_tree().get_nodes_in_group("enemy_projectile"):
		if bool(raw.get("_capture_active")):
			captured += 1
	print("CAPTURED ", captured)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/taiji_capture_orbit.png")
	# 等到至少一枚反打再抓第二帧，避免把「还在绕圈」当成「已经反打」
	var waited := 0.0
	while waited < 2.4:
		var reflected := false
		for raw in get_tree().get_nodes_in_group("enemy_projectile"):
			if bool(raw.get("is_deflected")):
				reflected = true
				break
		if reflected:
			break
		await get_tree().create_timer(0.10, true, false, true).timeout
		waited += 0.10
	await get_tree().create_timer(0.10, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/taiji_capture_reflect.png")
	print("SHOT taiji capture frames")
	get_tree().quit()
