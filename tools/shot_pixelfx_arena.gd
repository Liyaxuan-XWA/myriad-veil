extends Node
## 像素特效叠在真实战场上的显示尺寸对比（2026-11-04）
## 战斗一暂停就只剩像素特效，避免把 BOSS 自己的演出误读成像素特效。
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_pixelfx_arena.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _mark(at: Vector2, color: Color) -> void:
	var s := Sprite2D.new()
	s.texture = SkillFx.white_texture()
	s.scale = Vector2(2.5, 2.5)
	s.modulate = color
	s.z_index = 300
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(s)
	s.global_position = at


func _ready() -> void:
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01",
		"boss_id": "boss_01_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 6:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	if player == null or boss == null:
		print("NO ANCHOR")
		get_tree().quit(1)
		return
	var feet: Vector2 = boss.call("feet_position")
	var nova := PixelFxFx.spawn(arena, feet, "ice/frost-nova")
	var slash := PixelFxFx.spawn(arena, player.global_position + Vector2(60, 0),
		"melee/sword-slash", {"dir": Vector2.RIGHT, "flip_by_dir": true})
	nova.process_mode = Node.PROCESS_MODE_ALWAYS
	slash.process_mode = Node.PROCESS_MODE_ALWAYS
	_mark(feet, Color(1, 1, 0, 0.95))
	_mark(player.global_position + Vector2(60, 0), Color(0.3, 1, 0.4, 0.95))
	get_tree().paused = true
	for i in 14:
		await get_tree().process_frame
	var vp := get_viewport()
	var spr := nova.get_node("Sheet") as Sprite2D
	var fsize: Vector2 = (spr.texture as AtlasTexture).region.size
	var tl := nova.global_position + spr.offset
	print("DIAG frame_box_screen=", Rect2(vp.get_canvas_transform() * tl, fsize),
		" feet_screen=", vp.get_canvas_transform() * feet)
	await _shot("pixelfx_arena_charge.png")
	for i in 30:
		await get_tree().process_frame
	await _shot("pixelfx_arena_ring.png")
	get_tree().paused = false
	get_tree().quit(0)
