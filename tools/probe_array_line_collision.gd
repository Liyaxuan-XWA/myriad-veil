extends Node
## 阵线真实物理阻挡自检（2026-10-29）：
##   同一条玩家阵线：mask 含玩家线层的 mover 被挡住，mask 不含的 mover 穿过去。
## 用法：godot --headless --path . res://tools/probe_array_line_collision.tscn

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _make_mover(mask: int, x: float) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	body.collision_layer = 0
	body.collision_mask = mask
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	body.add_child(shape)
	body.global_position = Vector2(x, -90.0)
	add_child(body)
	return body


func _ready() -> void:
	print("\n########## 阵线物理阻挡自检 ##########")
	var flag_a := Node2D.new()
	var flag_b := Node2D.new()
	add_child(flag_a)
	add_child(flag_b)
	flag_a.global_position = Vector2(-160.0, 0.0)
	flag_b.global_position = Vector2(160.0, 0.0)
	var barrier := ArrayLineBarrier.new()
	barrier.top_level = true
	barrier.setup(ArrayFlag.LINE_LAYER_PLAYER)
	add_child(barrier)
	barrier.sync([[flag_a, flag_b]])

	# 左侧：mask 含玩家线层 → 应被挡在 y<0
	var blocked := _make_mover(ArrayFlag.LINE_LAYER_PLAYER, -60.0)
	# 右侧：mask 不含玩家线层 → 应穿到 y>0
	var free := _make_mover(ArrayFlag.LINE_LAYER_BOSS, 60.0)
	await get_tree().physics_frame
	for i in 90:
		blocked.velocity = Vector2(0.0, 160.0)
		free.velocity = Vector2(0.0, 160.0)
		blocked.move_and_slide()
		free.move_and_slide()
		await get_tree().physics_frame

	_check(blocked.global_position.y < -2.0, "阵线挡住了应被挡的 mover",
		"y=%.1f" % blocked.global_position.y)
	_check(free.global_position.y > 20.0, "阵线不挡同一侧/施法者层",
		"y=%.1f" % free.global_position.y)
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
