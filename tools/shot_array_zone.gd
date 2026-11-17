extends Node

class DummyBoss extends Node2D:
	func take_damage(_amount: float, _source: Node = null, _kind: String = "physical",
			_element: String = "", _from_projectile: bool = false) -> void:
		pass

	func apply_debuff(_id: String, _duration: float) -> bool:
		return true

	func has_debuff(_id: String) -> bool:
		return false

	func remove_debuff(_id: String) -> void:
		pass

	func set_zone_attack_mult(_source: String, _mult: float) -> void:
		pass


func _ready() -> void:
	for sid in ["skill_array_plant"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	var bg := Sprite2D.new()
	bg.texture = load("res://assets/scenes/dingzhen_arena_ground.png")
	bg.centered = true
	bg.scale = Vector2(1.12, 1.12)
	bg.z_index = -20
	add_child(bg)

	var boss := DummyBoss.new()
	boss.add_to_group("boss")
	add_child(boss)
	var boss_spr := Sprite2D.new()
	boss_spr.texture = load("res://assets/characters/boss/boss_dingzhen.png")
	boss_spr.centered = true
	boss_spr.scale = Vector2(0.34, 0.34)
	boss_spr.position = Vector2(0.0, -42.0)
	boss.add_child(boss_spr)
	boss.global_position = Vector2(0.0, -20.0)

	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.global_position = Vector2(0.0, 100.0)
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	p.auto_parry_timer = 0.0
	p._refresh_array_unlock()
	p._clear_array_flags()

	for i in 5:
		var ang := -PI * 0.5 + TAU * float(i) / 5.0
		p._plant_array_flag(Vector2(cos(ang), sin(ang)) * 240.0, ArrayFlag.Kind.ATTACK)
	p._tick_array_flags(0.016)

	var cam := Camera2D.new()
	cam.global_position = Vector2(0.0, 0.0)
	cam.zoom = Vector2(1.0, 1.0)
	add_child(cam)
	cam.make_current()
	await get_tree().create_timer(0.45, true, false, true).timeout

	p.mana = p.max_mana
	p._tick_array_flags(1.01)
	await get_tree().create_timer(0.10, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/array_zone.png")
	print("SHOT output/array_zone.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()
