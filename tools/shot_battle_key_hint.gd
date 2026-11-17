extends Node
## 战斗左上角操作键竖排截图（窗口化）
## godot --path . --resolution 1280x720 res://tools/shot_battle_key_hint.tscn -- --no-save

const ARENA := "res://scenes/combat/combat_arena.tscn"

func _ready() -> void:
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN, "domain_id": "domain_01", "boss_id": "boss_01",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load(ARENA) as PackedScene).instantiate()
	add_child(arena)
	for i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/battle_key_hint.png")
	print("SHOT output/battle_key_hint.png")
	get_tree().quit(0)
