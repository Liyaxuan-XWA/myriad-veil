extends Node
## 苍澜大陆四区边界/接缝实景截图（2026-11-01 边界纹理盘点）。
## 用法：godot --path . tools/capture_world_edges.tscn
##
## 覆盖：四条区间接缝、八个外圈线段、四个角。HUD 隐藏，只留世界与角色作比例尺。
## 与 capture_youming_scene 一样：传送后冻玩家、等相机稳定再截。

const WARMUP := 10
const SETTLE := 20
const SHOTS := [
	# 四条接缝
	{"tag": "seam_lianqi_youming_a", "at": Vector2(-40.0, 600.0), "zoom": 1.0},
	{"tag": "seam_lianqi_youming_b", "at": Vector2(-40.0, 2300.0), "zoom": 1.6},
	{"tag": "seam_lianqi_youming_c", "at": Vector2(-40.0, 3550.0), "zoom": 1.0},
	{"tag": "seam_lianqi_zhuji_a", "at": Vector2(1200.0, 0.0), "zoom": 1.0},
	{"tag": "seam_lianqi_zhuji_gap", "at": Vector2(3000.0, 0.0), "zoom": 1.0},
	{"tag": "seam_lianqi_zhuji_b", "at": Vector2(5000.0, 0.0), "zoom": 1.0},
	{"tag": "seam_zhuji_jiedan_a", "at": Vector2(0.0, -1200.0), "zoom": 1.0},
	{"tag": "seam_zhuji_jiedan_b", "at": Vector2(0.0, -3200.0), "zoom": 1.0},
	{"tag": "seam_jiedan_youming_a", "at": Vector2(-1500.0, 0.0), "zoom": 1.0},
	{"tag": "seam_jiedan_youming_wide", "at": Vector2(-3000.0, 0.0), "zoom": 0.7},
	{"tag": "seam_jiedan_youming_b", "at": Vector2(-4800.0, 0.0), "zoom": 1.0},
	# 四角（四区交汇 / 地图角）
	{"tag": "corner_center", "at": Vector2(300.0, 300.0), "zoom": 0.7},
	{"tag": "corner_center_zoom", "at": Vector2(140.0, 140.0), "zoom": 1.6},
	{"tag": "corner_nw", "at": Vector2(-5600.0, -3600.0), "zoom": 0.7},
	{"tag": "corner_ne", "at": Vector2(5600.0, -3600.0), "zoom": 0.7},
	{"tag": "corner_se", "at": Vector2(5600.0, 3600.0), "zoom": 0.7},
	{"tag": "corner_sw", "at": Vector2(-5600.0, 3600.0), "zoom": 0.7},
	# 外圈林带
	{"tag": "band_lianqi_south", "at": Vector2(1800.0, 3380.0), "zoom": 1.2},
	{"tag": "band_lianqi_east", "at": Vector2(5400.0, 1800.0), "zoom": 1.2},
	{"tag": "band_zhuji_north", "at": Vector2(1600.0, -3380.0), "zoom": 1.2},
	{"tag": "band_zhuji_east", "at": Vector2(5400.0, -1800.0), "zoom": 1.2},
	{"tag": "band_jiedan_north", "at": Vector2(-4600.0, -3380.0), "zoom": 1.2},
	{"tag": "band_jiedan_west", "at": Vector2(-5400.0, -1800.0), "zoom": 1.2},
	{"tag": "band_youming_south", "at": Vector2(-1800.0, 3380.0), "zoom": 1.2},
	{"tag": "band_youming_west", "at": Vector2(-5400.0, 1800.0), "zoom": 1.2},
]

var _world: Node
var _frames := 0
var _target := Vector2.ZERO


func _ready() -> void:
	VirtualPad.enabled = false
	SettingsUI.set_entry_visible(false)
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	_world = s.instantiate()
	add_child(_world)
	var hud := _world.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 50:
		_freeze_player()
		return
	var rel := _frames - (50 + WARMUP)
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
	var hud := _world.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	print("set ", spec["tag"], "  at=", _target)


func _finish_shot(slot: int) -> void:
	var spec: Dictionary = SHOTS[slot]
	var path := "res://output/edges_%s.png" % String(spec["tag"])
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
