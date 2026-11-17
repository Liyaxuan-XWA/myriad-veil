extends SceneTree
## 临时自检：把练气区跑起来，抓几帧存成 PNG，看美术接进去到底长什么样。
## 只为确认「贴图导入了、着色器编译过、实体不是黑方块、标签不压在模型身上」，
## 观感还是要用户实机看。
## 用法（会开一个窗口，跑完自己退）：
##     godot --path . --script tools/capture_region.gd
##
## ⚠ 改完参数不能立刻抓：get_texture() 拿到的是**上一帧**已经渲染好的画面，
##    「改 → 马上截图」会拍到上一发的状态，整批结果错位一格。所以每发先设、
##    空跑 SETTLE 帧、再截。
## ⚠ 玩家站着不动也会慢慢漂，一漂整幅画面就跟着挪，几发之间没法比 —— 传送完把
##    玩家和相机一起冻住。
## ⚠ 站位不写死坐标，按 kind 去 Content 下找真实节点：药材/灵气团的坐标归
##    SecretWorldDB 管，灵气团还是随机落点，写死迟早对不上。

const MOVE_SHOT := 60
## 传送后等相机稳定几帧再开拍
const WARMUP := 8
## 设完状态到截图之间要空的帧数（见上面的 ⚠）
const SETTLE := 3

## find = 去 Content 下找一个该 kind 的 WorldResource，站到它跟前
## at   = 直接给世界坐标（五类药材散在地图五处，按 kind 只会找到第一类）
##        坐标 = SecretWorldDB 的偏移 + 区域中心 (3000, 2000)
const SHOTS := [
	{"tag": "herb", "find": "herb", "zoom": 1.0},
	{"tag": "herb_near", "find": "herb", "zoom": 1.6},
	{"tag": "herb_lanying", "at": Vector2(1280.0, 3120.0), "zoom": 1.4},
	{"tag": "herb_liyuan", "at": Vector2(2680.0, 680.0), "zoom": 1.4},
	{"tag": "herb_faling", "at": Vector2(3180.0, 3220.0), "zoom": 1.4},
	{"tag": "herb_hugu", "at": Vector2(4480.0, 920.0), "zoom": 1.4},
	{"tag": "qi", "find": "qi", "zoom": 1.0},
	{"tag": "portal", "find": "portal", "zoom": 1.0},
	{"tag": "portal_near", "find": "portal", "zoom": 1.6},
]

var _scene: Node
var _frames := 0
var _target := Vector2.ZERO


func _initialize() -> void:
	var s := load("res://scenes/world/secret_world.tscn") as PackedScene
	_scene = s.instantiate()
	root.add_child(_scene)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == MOVE_SHOT:
		_freeze_player()
		return false
	var rel := _frames - (MOVE_SHOT + WARMUP)
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


func _find_world_pos(kind: String) -> Vector2:
	var c := _scene.get_node_or_null("Content")
	if c == null:
		return Vector2.ZERO
	for ch in c.get_children():
		if ch.get("kind") != null and String(ch.get("kind")) == kind:
			return (ch as Node2D).global_position
	return Vector2.ZERO


func _begin_shot(slot: int) -> void:
	var spec: Dictionary = SHOTS[slot]
	_target = spec["at"] if spec.has("at") else _find_world_pos(String(spec["find"]))
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
	var path := "res://output/capture_props_%s.png" % String(spec["tag"])
	root.get_texture().get_image().save_png(path)
	print("saved ", path, "  cam=", (_scene.get_node("Player/Camera2D") as Camera2D).global_position)
