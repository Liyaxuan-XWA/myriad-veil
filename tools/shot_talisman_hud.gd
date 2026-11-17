extends Node
## 符箓 HUD / 轮盘实景截图
## 用法：godot --path . --resolution 1280x720 res://tools/shot_talisman_hud.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	CharacterData.add_item({
		"id": "tal_huoqiu_lianqi", "name": "火球符·练气", "type": "talisman",
		"count": 5, "icon": "res://assets/ui/icon/tal_element_fire.png",
	})
	CharacterData.active_skill_loadout = [
		"talisman:tal_huoqiu_lianqi", "", "", "",
	]
	GameState.battle_context = {"source": BattleResolver.SOURCE_ARENA}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	await _shot("talisman_skill_bar.png")
	BattleWheel._open_wheel()
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("talisman_wheel_pills.png")
	get_tree().quit()
