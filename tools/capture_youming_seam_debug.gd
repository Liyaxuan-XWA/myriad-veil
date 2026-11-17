extends Node
## 一次性诊断：在实景里画出世界 x=0 / 接缝板左右边缘 / y=0，确认贴图落点。
## 用法：godot --path . tools/capture_youming_seam_debug.tscn

const WARMUP := 8
const SETTLE := 3
const SHOTS := [
	{"tag": "debug_east", "at": Vector2(0.0, 2000.0), "zoom": 1.6},
	{"tag": "debug_north", "at": Vector2(-3000.0, 0.0), "zoom": 1.6},
]

var _world: Node
var _frames := 0
var _target := Vector2.ZERO


func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	_world = s.instantiate()
	add_child(_world)
	_add_guide_lines()


func _add_lines(points: PackedVector2Array, color: Color, width: float) -> void:
	var ln := Line2D.new()
	ln.points = points
	ln.default_color = color
	ln.width = width
	ln.z_index = 4000
	ln.z_as_relative = false
	(_world as Node2D).add_child(ln)


func _add_guide_lines() -> void:
	# 东接缝：板 x=-210..210，世界界 x=0
	_add_lines(PackedVector2Array([Vector2(-210, 0), Vector2(-210, 4000)]), Color(1, 0, 0), 3.0)
	_add_lines(PackedVector2Array([Vector2(0, 0), Vector2(0, 4000)]), Color(1, 1, 0), 3.0)
	_add_lines(PackedVector2Array([Vector2(210, 0), Vector2(210, 4000)]), Color(0, 1, 1), 3.0)
	# 北接缝：板 y=-140..280，世界界 y=0
	_add_lines(PackedVector2Array([Vector2(-6000, -140), Vector2(0, -140)]), Color(1, 0, 1), 3.0)
	_add_lines(PackedVector2Array([Vector2(-6000, 0), Vector2(0, 0)]), Color(1, 1, 0), 3.0)
	_add_lines(PackedVector2Array([Vector2(-6000, 280), Vector2(0, 280)]), Color(0, 1, 1), 3.0)


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 60:
		_freeze_player()
		return
	var rel := _frames - (60 + WARMUP)
	if rel < 0:
		return
	var slot := rel / (SETTLE + 1)
	if slot >= SHOTS.size():
		get_tree().quit(0)
		return
	var k := rel % (SETTLE + 1)
	if k == 0:
		_begin_shot(slot)
	elif k == SETTLE:
		_finish_shot(slot)


func _freeze_player() -> void:
	var p := _world.get_node_or_null("Player") as Node2D
	if p == null:
		return
	p.set_physics_process(false)
	var cam := p.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.reset_smoothing()


func _begin_shot(slot: int) -> void:
	var spec: Dictionary = SHOTS[slot]
	_target = spec["at"]
	var p := _world.get_node("Player") as Node2D
	var cam := p.get_node("Camera2D") as Camera2D
	p.global_position = _target
	cam.global_position = _target
	cam.reset_smoothing()
	var z := float(spec["zoom"])
	cam.zoom = Vector2(z, z)
	print("set ", spec["tag"], " at=", _target, " cam=", cam.global_position,
		" zoom=", cam.zoom, " center=", cam.get_screen_center_position())


func _finish_shot(slot: int) -> void:
	var spec: Dictionary = SHOTS[slot]
	var path := "res://output/debug_youming_%s.png" % String(spec["tag"])
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
