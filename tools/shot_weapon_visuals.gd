extends Node2D
## 三把新武器局内贴图预览：待机 + 挥击中点，仅评审用。

const WEAPONS := [
	["朱弦阵尺", "weapon_zhuxian_chizhang"],
	["判官铁笔", "weapon_panguan_tiebi"],
	["劫锋", "weapon_jiefeng"],
]

var _orbits: Array = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085, 1.0)
	bg.size = Vector2(1280.0, 720.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for i in WEAPONS.size():
		var actor := Node2D.new()
		actor.position = Vector2(260.0 + 380.0 * float(i), 400.0)
		actor.scale = Vector2(1.85, 1.85)
		add_child(actor)
		var body := ColorRect.new()
		body.color = Color(0.22, 0.23, 0.26, 1.0)
		body.size = Vector2(26.0, 42.0)
		body.position = Vector2(-13.0, -38.0)
		actor.add_child(body)
		var orbit := WeaponOrbit.new()
		orbit.weapon_id = String(WEAPONS[i][1])
		actor.add_child(orbit)
		orbit.refresh()
		_orbits.append(orbit)
		var label := Label.new()
		label.text = String(WEAPONS[i][0])
		label.position = Vector2(260.0 + 380.0 * float(i) - 70.0, 610.0)
		label.size = Vector2(140.0, 28.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		add_child(label)
	await get_tree().process_frame
	for orbit in _orbits:
		orbit.sweep(Vector2.RIGHT, {}, false)
	await get_tree().create_timer(0.10, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/weapon_visuals_in_game.png")
	print("saved output/weapon_visuals_in_game.png")
	get_tree().quit()
