extends Node
## 技能栏灰化对比截图（2026-11-09）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_skill_gray.tscn -- --no-save

const LOADOUT := ["skill_tiger_orb", "skill_tiger_claw", "skill_yinyang_flip", "skill_thunder_gather"]


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	for sid in LOADOUT:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = LOADOUT.duplicate()
	GameState.battle_context = {"source": BattleResolver.SOURCE_ARENA}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await _wait_frames(6)
	await get_tree().create_timer(1.0).timeout

	var player = arena.get("player")
	player.set("mana", float(player.get("max_mana")))
	player.set("stamina", int(player.get("max_stamina")))
	await _wait_frames(3)
	await _shot("skill_bar_normal.png")

	player.call("spend_mana", float(player.get("mana")))
	while int(player.get("stamina")) > 0:
		player.call("_spend_stamina")
	await _wait_frames(3)
	await _shot("skill_bar_gray.png")
	get_tree().quit()
