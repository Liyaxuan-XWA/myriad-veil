extends Node

const SHOTS := [
	{"tag": "iso_east", "at": Vector2(5400.0, 1800.0), "zoom": 1.2},
	{"tag": "iso_south", "at": Vector2(1800.0, 3380.0), "zoom": 1.2},
	{"tag": "iso_seam", "at": Vector2(5000.0, 0.0), "zoom": 1.0},
]
const MODES := ["all", "terrain_seam", "terrain_band", "terrain"]

var _world: Node
var _frames := 0
var _slot := 0
var _mode := 0

func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	_world = s.instantiate()
	add_child(_world)
	var hud := _world.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false

func _process(_d: float) -> void:
	_frames += 1
	if _frames == 30:
		var p := _world.get_node("Player") as Node2D
		p.set_physics_process(false)
		var cam := p.get_node("Camera2D") as Camera2D
		cam.reset_smoothing()
		return
	var rel := _frames - 41
	if rel < 0:
		return
	var per := 12
	var idx := rel / per
	if idx >= SHOTS.size() * MODES.size():
		get_tree().quit(0)
		return
	if rel % per == 0:
		_slot = idx / MODES.size()
		_mode = idx % MODES.size()
		_apply(SHOTS[_slot], MODES[_mode])
	elif rel % per == per - 1:
		var path := "res://output/iso_%s_%s.png" % [SHOTS[_slot]["tag"], MODES[_mode]]
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)

func _apply(spec: Dictionary, mode: String) -> void:
	var p := _world.get_node("Player") as Node2D
	var cam := p.get_node("Camera2D") as Camera2D
	p.global_position = spec["at"]
	cam.global_position = spec["at"]
	cam.reset_smoothing()
	cam.zoom = Vector2(float(spec["zoom"]), float(spec["zoom"]))
	var g := _world.get_node("Ground")
	for c in g.get_children():
		var n := String(c.name)
		var is_band := n.begins_with("Band_")
		var is_seam := n.begins_with("Seam")
		var is_terrain := n.begins_with("TerrainGround")
		var vis := true
		match mode:
			"terrain_seam":
				vis = is_terrain or is_seam
			"terrain_band":
				vis = is_terrain or is_band
			"terrain":
				vis = is_terrain
		c.visible = vis
