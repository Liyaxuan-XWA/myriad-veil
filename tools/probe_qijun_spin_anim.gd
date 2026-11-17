extends Node
## 太虚气君「御风·回旋」动作自检（2026-10-28）：
##   整身不再转 360°；旋转交给气环，身体只做侧倾/下沉回弹。
## 用法：godot --headless --path . res://tools/probe_qijun_spin_anim.tscn

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _find_track(a: Animation, path: String) -> int:
	for i in range(a.get_track_count()):
		if String(a.track_get_path(i)) == path:
			return i
	return -1


func _max_abs_key(a: Animation, track: int) -> float:
	var m := 0.0
	for k in range(a.track_get_key_count(track)):
		m = maxf(m, absf(float(a.track_get_key_value(track, k))))
	return m


func _ready() -> void:
	print("\n########## 太虚气君回旋动作探针 ##########")
	var boss: Node = (load("res://scenes/boss/domain_boss_02_c.tscn") as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)

	var rig := boss.skin.render_node as BossRig
	_check(rig != null, "真实场景用骨骼 rig")
	_check(ArtDB.boss_move_anim("boss_qijun", "form_qi_spin") == "spin",
		"回旋映射", ArtDB.boss_move_anim("boss_qijun", "form_qi_spin"))
	if rig == null:
		get_tree().quit(1)
		return
	_check(rig.has_animation("spin"), "spin 动画存在")

	var a: Animation = rig._player.get_animation("spin")
	var bi := _find_track(a, "body:rotation")
	var hi := _find_track(a, "halo:rotation")
	_check(bi >= 0, "身体旋转轨道存在")
	_check(hi >= 0, "气环旋转轨道存在")
	if bi >= 0:
		var bmax := _max_abs_key(a, bi)
		_check(bmax < 0.2, "身体不再整圈旋转（最大 <0.2 rad）", str(bmax))
	if hi >= 0:
		var hmax := 0.0
		for k in range(a.track_get_key_count(hi)):
			hmax = maxf(hmax, absf(float(a.track_get_key_value(hi, k))))
		_check(hmax >= TAU * 1.9, "气环急转两圈", str(hmax))

	boss.skin.cancel_one_shot()
	rig.reset_pose()
	await get_tree().process_frame
	var body: Node2D = rig._nodes.get("body", null)
	var halo: Node2D = rig._nodes.get("halo", null)
	var b0 := body.rotation if body != null else 0.0
	var h0 := halo.rotation if halo != null else 0.0
	var scale_max := 1.0
	var body_abs_max := 0.0
	boss._play_form_anim("form_qi_spin", 0.75)
	for i in range(5):
		await get_tree().create_timer(0.1).timeout
		if body != null:
			body_abs_max = maxf(body_abs_max, absf(body.rotation - b0))
		if halo != null:
			scale_max = maxf(scale_max, halo.scale.x)
	print("body_max=", body_abs_max, " halo_rot=", halo.rotation if halo != null else 0.0,
		" halo_scale_max=", scale_max)
	_check(body_abs_max < 0.2, "实测身体只有轻微侧倾", str(body_abs_max))
	_check(halo != null and absf(halo.rotation - h0) > 3.0, "实测气环在转",
		str(halo.rotation - h0) if halo != null else "null")
	_check(scale_max > 1.1, "气环放大", str(scale_max))
	await get_tree().create_timer(0.45).timeout
	_check(absf(body.rotation - b0) < 0.02, "收招回正", str(body.rotation - b0))

	# ---- 玩家气锁 / 回旋对真实 BOSS 的受控接口 ----
	boss.state = BossBase.BossState.IDLE
	boss._cc_slow_left = 0.0
	boss._cc_slow_mult = 1.0
	boss._cc_silence_left = 0.0
	boss._knock_vel = Vector2.ZERO
	var base_speed: float = boss._move_speed()
	boss.apply_slow(0.5, 2.0)
	_check(is_equal_approx(boss._move_speed(), base_speed * 0.5), "气锁减速 50% 真落到走位速度",
		"%.1f → %.1f" % [base_speed, boss._move_speed()])
	boss.apply_skill_lock(2.0)
	_check(boss.is_skill_locked(), "封技 2 秒生效")
	var state_before: int = boss.state
	boss._begin("form_qi_gather")
	_check(boss.state == state_before, "封技期间不能起手", "state=%d" % boss.state)
	boss.state = BossBase.BossState.WINDUP
	boss.apply_skill_lock(1.0)
	_check(boss.state != BossBase.BossState.WINDUP, "封技打断正在前摇的招")
	boss.take_knockback(Vector2(320.0, 0.0))
	_check(boss._knock_vel.x > 0.0, "回旋击退写进 BOSS 击退速度",
		str(boss._knock_vel))
	boss._cc_slow_left = 0.0
	boss._cc_slow_mult = 1.0
	boss._cc_silence_left = 0.0
	boss._knock_vel = Vector2.ZERO

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
