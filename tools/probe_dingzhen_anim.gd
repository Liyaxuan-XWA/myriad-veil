extends Node
## 定阵先生八式攻击动作自检（2026-10-28）：
##   ArtDB form → rig 动画名映射必须齐全，真实场景里出招要能带动手臂。
## 用法：godot --headless --path . res://tools/probe_dingzhen_anim.tscn

const FORMS := [
	["form_array_plant", "plant", 0.60],
	["form_array_line", "line", 0.75],
	["form_array_pull", "pull", 0.65],
	["form_array_seal", "seal", 1.10],
	["form_array_sweep", "sweep", 0.62],
	["form_array_step", "step", 0.55],
	["form_array_pile", "pile", 1.10],
	["form_array_burst", "burst", 1.20],
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
	print("\n########## 定阵先生攻击动作探针 ##########")
	var boss: Node = (load("res://scenes/boss/domain_boss_02_b.tscn") as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)

	var rig := boss.skin.render_node as BossRig
	_check(rig != null, "真实场景用骨骼 rig")

	for row in FORMS:
		var form := String(row[0])
		var anim := String(row[1])
		var windup := float(row[2])
		var mapped := ArtDB.boss_move_anim("boss_dingzhen", form)
		_check(mapped == anim, "映射 " + form, mapped)
		_check(rig != null and rig.has_animation(anim), "rig 动画存在 " + anim)
		if rig == null:
			continue

		boss.skin.cancel_one_shot()
		rig.reset_pose()
		await get_tree().process_frame
		var arm: Node2D = rig._nodes.get("arm", null)
		var body: Node2D = rig._nodes.get("body", null)
		var arm0 := arm.rotation if arm != null else 0.0
		var body0 := body.rotation if body != null else 0.0

		boss._play_form_anim(form, windup + 0.15)
		_check(rig._one_shot == anim, "出招启动 " + anim, rig._one_shot)
		_check(rig._player.current_animation == anim, "动画播放器切到 " + anim,
			rig._player.current_animation)
		await get_tree().create_timer(minf(0.42, windup * 0.5)).timeout
		var arm_delta := absf(arm.rotation - arm0) if arm != null else 0.0
		var body_delta := absf(body.rotation - body0) if body != null else 0.0
		print("  ", anim, " arm ", arm_delta, " body ", body_delta)
		_check(arm_delta > 0.05, "手臂有攻击动作 " + anim, str(arm_delta))
		_check(body_delta > 0.005, "躯干参与发力 " + anim, str(body_delta))

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
