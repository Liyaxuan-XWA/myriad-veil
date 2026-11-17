extends Node
## 位移技能方向自检（2026-10-30）：
## 有移动输入时按输入方向；没有输入时默认朝最近 BOSS。非位移技能不受输入影响。
## 用法：godot --headless --path . tools/probe_skill_cast_dir.tscn -- --no-save

const MOVE_FORMS := [
	"form_blade_dash", "form_sword_pierce", "form_yinyang_triple",
	"form_array_step", "form_qi_step", "form_thunder_step",
	"form_sun_step", "form_calamity_step",
]

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 位移技能方向探针 ##########")
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector2.ZERO
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	var boss := Node2D.new()
	boss.add_to_group("boss")
	boss.global_position = Vector2(-200.0, 0.0)
	add_child(boss)
	await get_tree().process_frame

	for fid in MOVE_FORMS:
		var form: Dictionary = MoveDB.resolve_player(String(fid))
		_check(not form.is_empty(), "形态存在 " + String(fid))
		Input.action_press("move_right")
		var moved: Vector2 = p._skill_cast_dir(form)
		Input.action_release("move_right")
		_check(moved.is_equal_approx(Vector2.RIGHT),
			"有输入按输入方向：" + String(fid), str(moved))
		var idle: Vector2 = p._skill_cast_dir(form)
		_check(idle.is_equal_approx(Vector2.LEFT),
			"无输入朝 BOSS：" + String(fid), str(idle))

	var non_move: Dictionary = MoveDB.resolve_player("form_smash")
	Input.action_press("move_right")
	var still_boss: Vector2 = p._skill_cast_dir(non_move)
	Input.action_release("move_right")
	_check(still_boss.is_equal_approx(Vector2.LEFT),
		"非位移技能仍朝 BOSS（不被输入带偏）", str(still_boss))

	boss.queue_free()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
