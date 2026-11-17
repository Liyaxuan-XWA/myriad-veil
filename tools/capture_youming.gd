extends SceneTree
## 幽冥灵墟实景截图：西南门 / 中央山门 / 西墙 / 南墙 / 北接缝 / 东接缝 / 两兽
## 只为确认贴图导入、着色器编译、接缝接得上；观感仍以用户实机为准。
## 用法：godot --path . --script tools/capture_youming.gd
## ⚠ get_texture() 拿的是上一帧：设完状态空跑 SETTLE 帧再截。

const WARMUP := 8
const SETTLE := 3
const SHOTS := [
	{"tag": "portal", "at": Vector2(-4980.0, 3050.0), "zoom": 1.0},
	{"tag": "gate", "at": Vector2(-3000.0, 1980.0), "zoom": 1.0},
	{"tag": "west_wall", "at": Vector2(-5450.0, 2000.0), "zoom": 1.0},
	{"tag": "south_wall", "at": Vector2(-3000.0, 3450.0), "zoom": 1.2},
	{"tag": "seam_north", "at": Vector2(-3000.0, 0.0), "zoom": 1.6},
	{"tag": "seam_east", "at": Vector2(0.0, 2000.0), "zoom": 1.6},
	{"tag": "beasts", "at": Vector2(-3900.0, 2150.0), "zoom": 1.15},
]

var _scene: Node
var _frames := 0
var _target := Vector2.ZERO


func _initialize() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	_scene = s.instantiate()
	root.add_child(_scene)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 60:
		_freeze_player()
		return false
	var rel := _frames - (60 + WARMUP)
	if rel < 0:
		return false
	var slot := rel / (SETTLE + 1)
	if slot >= SHOTS.size():
		return true
	var k := rel % (SETTLE + 1)
	if k == 0:
		_begin_shot(slot)
	elif k == SETTLE:
		_finish_shot(slot)
	return false


func _freeze_player() -> void:
	var p := _scene.get_node_or_null("Player") as Node2D
	if p == null:
		return
	p.set_physics_process(false)
	var cam := p.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.reset_smoothing()


func _begin_shot(slot: int) -> void:
	var spec: Dictionary = SHOTS[slot]
	_target = spec["at"]
	var p := _scene.get_node("Player") as Node2D
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
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
