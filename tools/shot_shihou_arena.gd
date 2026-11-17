extends Node
## 镇墟石犼核心重战箱庭截图：确认幽冥战场背景、六碣与 44,000 血条。
## 用法：godot --path . --windowed --resolution 1600x1000 tools/shot_shihou_arena.tscn -- --no-save

func _ready() -> void:
	GameState.battle_context = {
		"source": "world_core",
		"region_id": "world_yuanying",
		"boss_id": "world_core_shihou",
	}
	var arena = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().create_timer(0.8, true, false, true).timeout
	var card = arena.find_child("BossIntroCard", true, false)
	if card != null:
		card.call("_dismiss")
	await get_tree().create_timer(1.2, true, false, true).timeout
	# 截图时停 AI、清掉出招前摇的染色，避免把石犼拍成棕色
	var boss = arena.find_child("Boss", true, false)
	if boss != null:
		boss.set_physics_process(false)
		boss.set_process(false)
		var anim = boss.get("anim")
		if anim != null and anim is CanvasItem:
			(anim as CanvasItem).modulate = Color.WHITE
		var skin = boss.get("skin")
		if skin != null and skin is CanvasItem:
			(skin as CanvasItem).modulate = Color.WHITE
	await get_tree().create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/shihou_arena.png")
	print("SHOT output/shihou_arena.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
