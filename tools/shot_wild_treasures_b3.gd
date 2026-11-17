extends Node2D
## 野修法宝第三组局内观感截图（2026-11-01）
## 用法：godot --path . --windowed --resolution 1600x900 res://tools/shot_wild_treasures_b3.tscn

const OUT_DIR := "output"

var _p: Node2D
var _near: Node2D


func _ready() -> void:
	get_tree().create_timer(50.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT WILD TREASURES B3 TIMEOUT")
		get_tree().quit(2))
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.12)
	bg.position = Vector2.ZERO
	bg.size = Vector2(1600, 900)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_near = _spawn_enemy(Vector2(600, 520), "近处野修")
	_spawn_enemy(Vector2(980, 520), "远处野修")
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	await get_tree().process_frame
	await get_tree().process_frame
	_p.global_position = Vector2(420, 520)
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.max_hp = 1000.0
	_p.hp = 1000.0
	_p.max_mana = 999.0
	_p.mana = 999.0
	await _shot_blood_seal()
	await _shot_swap()
	await _shot_thorns()
	await _shot_gust()
	await _shot_forge()
	get_tree().quit()


func _spawn_enemy(pos: Vector2, name: String) -> Node2D:
	var e = (load("res://scenes/world/world_enemy.tscn") as PackedScene).instantiate()
	var cfg := {
		"pos": pos,
		"max_hp": 1000.0,
		"attack_power": 20.0,
		"visual_id": "player_liqingyun",
		"move_speed": 120.0,
		"aggro_range": 600.0,
		"leash_range": 1000.0,
		"skills": [],
		"treasure_mana_max": 100.0,
		"treasure_trigger_hp_ratio": 0.55,
	}
	e.configure(cfg, "cultivator", name)
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	e.set_process(false)
	return e


func _reset_treasure() -> void:
	_p._summon_cooldowns.clear()
	_p.mana = 999.0
	_p._stake_left = 0.0
	_p._stake_id = ""
	_p.debuffs.clear()
	_p._stop_thorns_treasure()


func _shot_blood_seal() -> void:
	_reset_treasure()
	var tpl := ItemDB.get_treasure_template("tr_xuesi_yin")
	_p._start_blood_seal_treasure(CharacterData.make_treasure_instance(tpl), tpl)
	await get_tree().create_timer(0.16).timeout
	await _save("wild_treasures_b3_blood_seal.png")


func _shot_swap() -> void:
	_reset_treasure()
	_p.global_position = Vector2(420, 520)
	_near.global_position = Vector2(600, 520)
	var tpl := ItemDB.get_treasure_template("tr_huanwei_jue")
	_p._start_swap_treasure(CharacterData.make_treasure_instance(tpl), tpl)
	await get_tree().create_timer(0.10).timeout
	await _save("wild_treasures_b3_swap.png")


func _shot_thorns() -> void:
	_reset_treasure()
	_p.global_position = Vector2(420, 520)
	var tpl := ItemDB.get_treasure_template("tr_jijia_pei")
	_p._start_thorns_treasure(CharacterData.make_treasure_instance(tpl), tpl)
	await get_tree().create_timer(0.35).timeout
	await _save("wild_treasures_b3_thorns.png")


func _shot_gust() -> void:
	_reset_treasure()
	_p.global_position = Vector2(420, 520)
	_near.global_position = Vector2(600, 520)
	var tpl := ItemDB.get_treasure_template("tr_huifeng_dai")
	_p._start_gust_treasure(CharacterData.make_treasure_instance(tpl), tpl)
	await get_tree().create_timer(0.16).timeout
	await _save("wild_treasures_b3_gust.png")


func _shot_forge() -> void:
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var item := CharacterData.make_treasure_instance(
		ItemDB.get_treasure_template("tr_xuesi_yin"))
	panel._anvil_item = item
	panel._refresh_forge()
	for i in 5:
		await get_tree().process_frame
	await _save("wild_treasures_b3_forge.png")


func _save(file: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s" % [OUT_DIR, file])
	print("SHOT %s/%s %dx%d" % [OUT_DIR, file, img.get_width(), img.get_height()])
