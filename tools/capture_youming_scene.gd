extends Node
## 幽冥灵墟实景截图（走场景入口，autoload 才会挂上）。
## 用法：godot --path . tools/capture_youming_scene.tscn

const WARMUP := 8
## 区域切换判定每 0.35s 一次；停留太短会截到上一张的区域标题
const SETTLE := 24
const SHOTS := [
	{"tag": "portal", "at": Vector2(-4980.0, 3050.0), "zoom": 1.0},
	{"tag": "gate", "at": Vector2(-3000.0, 1980.0), "zoom": 1.0},
	{"tag": "west_wall", "at": Vector2(-5450.0, 2000.0), "zoom": 1.0},
	{"tag": "west_wall_b", "at": Vector2(-5450.0, 1755.0), "zoom": 1.0},
	{"tag": "south_wall", "at": Vector2(-3000.0, 3450.0), "zoom": 1.2},
	{"tag": "south_wall_b", "at": Vector2(-3367.0, 3450.0), "zoom": 1.2},
	{"tag": "seam_north", "at": Vector2(-3000.0, 0.0), "zoom": 1.6},
	{"tag": "seam_north_b", "at": Vector2(-1500.0, 0.0), "zoom": 1.6},
	{"tag": "seam_north_wide", "at": Vector2(-3000.0, 150.0), "zoom": 0.75},
	{"tag": "seam_east", "at": Vector2(-40.0, 2000.0), "zoom": 1.6},
	{"tag": "seam_east_b", "at": Vector2(-40.0, 800.0), "zoom": 1.6},
	{"tag": "seam_east_wide", "at": Vector2(-140.0, 2000.0), "zoom": 0.75},
	{"tag": "beasts", "at": Vector2(-3800.0, 2450.0), "zoom": 1.15},
	{"tag": "beasts_b", "at": Vector2(-5450.0, 2100.0), "zoom": 1.15},
]

var _world: Node
var _frames := 0
var _target := Vector2.ZERO


func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	_world = s.instantiate()
	add_child(_world)


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
	print("set ", spec["tag"], "  at=", _target)


func _finish_shot(slot: int) -> void:
	var spec: Dictionary = SHOTS[slot]
	var path := "res://output/capture_youming_%s.png" % String(spec["tag"])
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
