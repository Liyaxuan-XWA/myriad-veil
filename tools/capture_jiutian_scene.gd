extends Node
## 九天之上（化神区）与化神坛实景截图。走场景入口，autoload 才会挂上。
## 用法：godot --path . --resolution 1280x720 res://tools/capture_jiutian_scene.tscn
##
## 这块地是「开过九天门才进得来」的占位空场，探针只能证明数据对，
## 铺地/墙/相机/落点/坛子中没中墙这些必须用眼睛看一次。

const WARMUP := 8
const SETTLE := 24
const SHOTS := [
	{"tag": "spawn", "at": Vector2(-6920.0, -550.0), "zoom": 1.0},
	{"tag": "altar", "at": Vector2(-9000.0, -2000.0), "zoom": 1.0},
	{"tag": "altar_wide", "at": Vector2(-9000.0, -2000.0), "zoom": 0.55},
	{"tag": "portal", "at": Vector2(-6700.0, -700.0), "zoom": 1.0},
	{"tag": "north_wall", "at": Vector2(-9000.0, -3650.0), "zoom": 1.0},
]

var _world: Node
var _frames := 0
var _prompt_seen := ""


func _ready() -> void:
	# 门开过 = 九天之上才会被铺进并集；截图要的是开门之后的样子
	CharacterData.huashen_gate_opened = true
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_HUASHEN
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	_world = s.instantiate()
	add_child(_world)


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 60:
		_report()
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


## 顺手把交互条上那一行打出来：站在坛前应该读到「F　登坛突破化神」
func _report() -> void:
	if _world == null:
		return
	print("region=", _world.get("region_id"),
		"  open_regions=", (_world.call("get_open_regions") as Array).size(),
		"  resources=", (_world.get("_resources") as Dictionary).size())
	var altar = _world.get("_resources").get("huashen_altar", null)
	print("altar=", "有" if altar != null else "无",
			"  prompt=", altar.prompt_text() if altar != null else "")
	var gate = _world.get("_resources").get("huashen_gate", null)
	print("gate=", "有" if gate != null else "无",
		"  prompt=", gate.prompt_text() if gate != null else "")


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
	var at: Vector2 = spec["at"]
	var p := _world.get_node("Player") as Node2D
	var cam := p.get_node("Camera2D") as Camera2D
	p.global_position = at
	cam.global_position = at
	cam.reset_smoothing()
	cam.zoom = Vector2(float(spec["zoom"]), float(spec["zoom"]))
	print("set ", spec["tag"], "  at=", at)


func _finish_shot(slot: int) -> void:
	var spec: Dictionary = SHOTS[slot]
	var path := "res://output/capture_jiutian_%s.png" % String(spec["tag"])
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
