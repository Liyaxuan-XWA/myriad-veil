extends Node2D
## 符箓局内特效截图：符卡飞行 + 七系落点
## 用法：godot --path . --resolution 1280x720 res://tools/shot_talisman_fx.tscn -- --no-save

const IDS := [
	["tal_jinfeng_lianqi", "jinfeng"],
	["tal_huoqiu_lianqi", "huoqiu"],
	["tal_yinlei_lianqi", "yinlei"],
	["tal_muling_lianqi", "muling"],
	["tal_shuihui_lianqi", "shuihui"],
	["tal_fengji_lianqi", "fengji"],
	["tal_tushi_lianqi", "tushi"],
]

class DummyBoss extends Node2D:
	func take_damage(_amount: float, _source: Node = null, _kind: String = "elemental",
			_elem: String = "", _proj: bool = false) -> void:
		pass
	func apply_debuff(_id: String, _duration: float) -> bool:
		return true
	func hit_spheres() -> Array:
		return [Vector3(0.0, -20.0, 40.0)]
	func is_dead() -> bool:
		return false


func _ready() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -20
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.04, 0.055, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)

	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector2(640.0, 380.0)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	await get_tree().process_frame
	await get_tree().process_frame

	var dummy := DummyBoss.new()
	dummy.add_to_group("boss")
	dummy.global_position = Vector2(930.0, 360.0)
	add_child(dummy)

	# 火球符：先单拍一张飞行中的符卡
	_give("tal_huoqiu_lianqi")
	p.mana = 100.0
	p.use_talisman("tal_huoqiu_lianqi")
	await get_tree().create_timer(0.13).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/talisman_fx_fly.png")
	print("SHOT output/talisman_fx_fly.png")
	await get_tree().create_timer(0.16).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/talisman_fx_hover.png")
	print("SHOT output/talisman_fx_hover.png")
	await get_tree().create_timer(0.30).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/talisman_fx_projectile.png")
	print("SHOT output/talisman_fx_projectile.png")
	await get_tree().create_timer(1.0).timeout

	for pair in IDS:
		var item_id: String = pair[0]
		var tag: String = pair[1]
		_give(item_id)
		p.hp = p.max_hp
		p.mana = 100.0
		p.use_talisman(item_id)
		await get_tree().create_timer(0.95).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/talisman_fx_%s.png" % tag)
		print("SHOT output/talisman_fx_%s.png" % tag)
		await get_tree().create_timer(1.2).timeout
	get_tree().quit()


func _give(item_id: String) -> void:
	var def := ItemDB.get_consumable(item_id)
	for i in 3:
		CharacterData.add_item({
			"id": item_id, "name": String(def.get("talisman_name", item_id)),
			"type": "talisman", "count": 1, "icon": String(def.get("icon", "")),
		})
