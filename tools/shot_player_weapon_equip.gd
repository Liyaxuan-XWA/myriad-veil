extends Node2D
## 真实玩家装备三把后加武器的局内截图（含旧存档只存 id 的情况）。

const ITEMS := [
	["eq_zhuxian_chizhang", "朱弦阵尺"],
	["eq_panguan_tiebi", "判官铁笔"],
	["eq_jiefeng", "劫锋"],
]


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085, 1.0)
	bg.size = Vector2(1280.0, 720.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var player: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector2(640.0, 390.0)
	player.set_physics_process(false)
	await get_tree().process_frame

	var label := Label.new()
	label.position = Vector2(490.0, 610.0)
	label.size = Vector2(300.0, 32.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	add_child(label)
	for i in ITEMS.size():
		var eid := String(ITEMS[i][0])
		# 模拟旧存档：只保留 id，不写 weapon_visual
		CharacterData.equipment_slots["weapon"] = {"id": eid}
		player.refresh_training_loadout()
		player.weapon.facing_dir = Vector2.RIGHT
		player.weapon.sweep(Vector2.RIGHT, {}, false)
		label.text = String(ITEMS[i][1])
		await get_tree().create_timer(0.10, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"output/player_weapon_%s.png" % eid)
		print("SHOT ", eid, " → ", player.weapon.weapon_id)
	get_tree().quit(0)
