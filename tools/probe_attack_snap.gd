extends Node2D
## 平A「近距离自动吸附」自检（2026-11-10 用户：平a会有攻击不到人的情况）
## 2026-11-11 改版：按**落空原因**分治，断言口径跟着换。
##
## ⚠ 真实入口：用 `Input.action_press("attack")` 走完整链路
##   _handle_action_input → _start_attack → _parry_followup_dash / _melee_snap_to_target
##   → 落地再校验 → _perform_attack_hit。
##   🚫 不要改成直调 `_start_attack()`：那会绕过输入分发，吸附的起手条件漏测也全绿。
##
## 八类锁：
##   ① 距离不够 → 补位命中，且落点是「刚好进判定」而不是固定贴脸
##   ② 本来就能命中 → 位置和朝向都不许多改
##   ③ 缺口 > MELEE_SNAP_MAX_STEP → 不吸（玩家自己该走的位，不许变成自动冲锋）
##   ④ 换锋符 → 不贴身
##   ⑤ 距离够、角度不够（前刺半角只有 35°，劈/撩是 89.5°）→ **只转向、零位移**
##      —— 这条就是用户报的「明明砍得到还是吸到 BOSS 面前」
##   ⑥ 滑步这 0.12s 里目标走位 → 落点锁死，不许被拖着走
##   ⑦ 目标只漂移一点 → 落地再校验补上还差的缺口，这一刀仍要命中
##   ⑧ 弹反追击不吃缺口上限（追远是弹反奖励本身）
##
## 用法：godot --headless --path . tools/probe_attack_snap.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _p: Node2D
var _target: Node2D
var _dummy: Node2D
var _hp0 := 0.0
## ⚠ 必须是**成员变量**：Godot 的 lambda 按值捕获局部变量，
##   在闭包里 `local = true` 改不到外层，题目生效与否会永远读成 false。
var _mid_fired := false


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 目标当前血量（木桩没有 current_hp，返回 0，不参与掉血断言）
func _hp(t: Node2D) -> float:
	var v: Variant = t.get("current_hp")
	return float(v) if v != null else 0.0


## 这一刀打没打上：木桩读 hit_count，真实 BOSS 读掉血
func _landed() -> bool:
	if _target.has_method("reset_training_stats"):
		return int(_target.get("hit_count")) >= 1
	return _hp(_target) < _hp0


## 把玩家摆到目标左侧 x 像素处，清掉上一刀的状态
func _place(x: float, combo: int = 0) -> void:
	await _place_at(_target.global_position + Vector2(-x, 0.0), combo)


func _place_at(at: Vector2, combo: int = 0) -> void:
	_p.set("attack_combo", combo)
	_p.set("is_attacking", false)
	_p.global_position = at
	_p.set("attack_dir", Vector2.RIGHT)
	_p.set("velocity", Vector2.ZERO)
	_p.set("_melee_snapped", false)
	_p.set("_melee_turned", false)
	_p.call("remove_buff", "parry_followup")
	_p.set("parry_followup_can_dash", false)
	_mid_fired = false
	if _target.has_method("reset_training_stats"):
		_target.call("reset_training_stats")
	_hp0 = _hp(_target)
	await get_tree().process_frame


## 注入一次真实平A按键，等这一刀完全收尾。
## on_mid：位移进行到第 3 个物理帧时回调一次（用来模拟目标在前摇里走位）。
func _swing(on_mid: Callable = Callable()) -> void:
	var combo0 := int(_p.get("attack_combo"))
	Input.action_press("attack")
	# ⚠ 必须等输入分发**真的吃到**这一下（combo 自增 = _start_attack 跑过）再松开。
	#   只 await 一帧就 release，headless 下 _handle_action_input 可能还没跑，
	#   结果 is_attacking 还是 false、while 循环一次不进，上一刀的位移 tween
	#   就会跨用例继续拖着玩家跑（实测远距 case 被拉走 253px）。
	var guard := 0
	while int(_p.get("attack_combo")) == combo0 and guard < 60:
		await get_tree().physics_frame
		guard += 1
	Input.action_release("attack")
	guard = 0
	while bool(_p.get("is_attacking")) and guard < 240:
		if guard == 3 and on_mid.is_valid():
			on_mid.call()
		await get_tree().physics_frame
		guard += 1
	# 再让 tween / 出伤计时器把最后一帧走完
	for i in 8:
		await get_tree().process_frame


## 落点到最「深」的那个受击球表面的有符号距离（负 = 钻进球里了）
func _surface() -> float:
	var best := 1.0e9
	for sp in _target.call("hit_spheres"):
		var sv: Vector3 = sp
		if sv.z <= 0.0:
			continue
		var sc: Vector2 = _target.global_position + Vector2(sv.x, sv.y)
		best = minf(best, _p.global_position.distance_to(sc) - sv.z)
	return best


func _ready() -> void:
	print("\n########## 平A 近距离吸附探针 ##########")
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	_p.global_position = Vector2.ZERO
	_p.set("invincible_timer", 999.0)
	_p.set("stamina", 99.0)
	_dummy = (load("res://scenes/combat/training_dummy.tscn") as PackedScene).instantiate()
	add_child(_dummy)
	_dummy.global_position = Vector2(400.0, 0.0)
	_target = _dummy
	await get_tree().process_frame
	await get_tree().process_frame
	# ⚠ 登场演出会整段吞输入（_handle_action_input 里 is_teleporting 直接 return），
	#   等 deferred 的 _begin_teleport_arrival 跑完再收掉，否则按了也没反应。
	_p.set("is_teleporting", false)
	await get_tree().process_frame
	await _run_dummy_cases()
	await _run_boss_cases()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run_dummy_cases() -> void:
	# ===== ① 距离不够 ⇒ 补位命中，且落点是「刚好进判定」不是固定贴脸 =====
	# 木桩到最近受击球球心约 133px，而普攻 reach 74 + 球半径 30 = 104 → 原本必空。
	await _place(130.0)
	var pos0: Vector2 = _p.global_position
	await _swing()
	_check(bool(_p.get("_melee_snapped")), "① 近距离原本会落空时触发了吸附")
	_check(_landed(), "① 吸附后这一刀命中了木桩",
			"hits=%d" % int(_target.get("hit_count")))
	var step0 := _p.global_position.distance_to(pos0)
	_check(step0 > 10.0, "① 玩家确实补了一小步", "位移 %.0fpx" % step0)
	# 上限 60 再加落地再校验可能追加的几像素，超过就是「自动冲锋」而不是「补一步」
	_check(step0 <= 66.0, "① 补位量没有越过一次滑步的上限",
			"位移 %.1fpx / 上限 60" % step0)
	_check(_surface() >= -4.0, "① 落点没有钻进受击球（不会被碰撞体弹开）",
			"离球面 %.1f" % _surface())
	# 落点精确锁：新口径 = 命中上界(reach + 该球自身半径) − 余量 20，而不是旧那套固定
	# 贴脸站位 clamp(min(hit_r+18, body_r+24), reach×0.35, reach×0.72)。
	# 这条既是用户要的「只补到能打到 boss 的距离」，也是「落点公式退回旧值」的变异锁。
	var sh0: Dictionary = _p.call("_melee_shape", 1)
	var land_d := 1.0e9
	var want := 0.0
	for sp in _target.call("hit_spheres"):
		var sv: Vector3 = sp
		if sv.z <= 0.0:
			continue
		var c: Vector2 = _target.global_position + Vector2(sv.x, sv.y)
		if _p.global_position.distance_to(c) < land_d:
			land_d = _p.global_position.distance_to(c)
			want = float(sh0["reach"]) + sv.z - 20.0
	_check(absf(land_d - want) <= 2.0,
			"① 落点 = 命中上界 − 余量 20（像素级锁死，退回旧固定站位会偏出 2px）",
			"离球心 %.1fpx / 应为 %.1fpx" % [land_d, want])

	# ===== ② 本来就能命中 ⇒ 位置和朝向都不许多改 =====
	await _place(70.0)
	var near_pos: Vector2 = _p.global_position
	var near_dir: Vector2 = _p.get("attack_dir")
	await _swing()
	_check(not bool(_p.get("_melee_snapped")), "② 本来就能命中的一刀不吸附")
	_check(not bool(_p.get("_melee_turned")), "② 本来就能命中的一刀也不擅自转向")
	_check(_p.global_position.distance_to(near_pos) < 1.0, "② 站位没有被改动",
			"位移 %.1fpx" % _p.global_position.distance_to(near_pos))
	_check(near_dir.distance_to(_p.get("attack_dir")) < 0.02, "② 朝向没有被改动",
			"Δ=%.3f" % near_dir.distance_to(_p.get("attack_dir")))
	_check(_landed(), "② 这一刀照常命中", "hits=%d" % int(_target.get("hit_count")))

	# ===== ③ 缺口 > 60px ⇒ 不吸（那是玩家自己该走的位）=====
	await _place(300.0)
	var far_pos: Vector2 = _p.global_position
	await _swing()
	_check(not bool(_p.get("_melee_snapped")), "③ 缺口约 196px（> 上限 60）不触发吸附")
	_check(_p.global_position.distance_to(far_pos) < 1.0, "③ 远距平A 站位不变",
			"位移 %.1fpx" % _p.global_position.distance_to(far_pos))
	_check(int(_target.get("hit_count")) == 0, "③ 远距这一刀仍然打空（没偷偷改射程）",
			"hits=%d" % int(_target.get("hit_count")))

	# ===== ④ 换锋符：这一刀是远程剑气，不该贴身 =====
	await _place(130.0)
	_p.set("_blade_form_left", 1.0)
	_p.set("_blade_form_range", 240.0)
	await _swing()
	_check(not bool(_p.get("_melee_snapped")), "④ 换锋窗口内普攻不贴身吸附")
	_p.set("_blade_form_left", 0.0)

	# ===== ⑥ 滑步 0.12s 里目标走位 ⇒ 落点锁死，不许被拖着走 =====
	# 旧写法每帧重读目标位置，目标 320px 的招式位移会把玩家一路带走；
	# 现在落点锁死在起手值，剩下的 404px 缺口由再校验判成「超过上限」而拒绝。
	await _place(130.0)
	var lock_start: Vector2 = _p.global_position
	var t0: Vector2 = _target.global_position
	await _swing(func() -> void:
		_mid_fired = true
		_target.global_position = t0 + Vector2(320.0, 0.0))
	_check(_mid_fired, "⑥ 滑步中途确实挪走了目标（题目生效）")
	_check(bool(_p.get("_melee_snapped")), "⑥ 起手判定为距离不够，触发了滑步")
	var dragged := _p.global_position.distance_to(lock_start)
	_check(dragged <= 66.0,
			"⑥ 落点锁死在起手值：没跟着目标的招式位移被拖走",
			"玩家走 %.0fpx，而目标自己走了 320px" % dragged)
	_target.global_position = t0

	# ===== ⑦ 落地再校验：目标只漂移一点时补上还差的缺口，这一刀仍要命中 =====
	await _place(125.0)
	await _swing(func() -> void:
		_mid_fired = true
		_target.global_position = _target.global_position + Vector2(44.0, 0.0))
	_check(_mid_fired, "⑦ 滑步中途目标确实漂移了 44px（题目生效）")
	_check(_landed(), "⑦ 落地再校验补上漂移造成的缺口，这一刀仍然命中",
			"hits=%d" % int(_target.get("hit_count")))
	_target.global_position = t0


func _run_boss_cases() -> void:
	_dummy.global_position = Vector2(4000.0, 0.0)   # 把木桩挪出索敌范围，别抢目标
	var boss = (load("res://scenes/boss/domain_boss_01.tscn") as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	boss.global_position = Vector2(400.0, 0.0)
	boss.set_physics_process(false)
	await get_tree().process_frame
	_target = boss

	# ===== ⑤ 距离够、角度不够 ⇒ 只转向、零位移（用户报的那一条）=====
	# 起手 attack_combo=1 → 出伤读 _melee_shape(2) = 前刺，半角只有 35°（劈/撩是 89.5°）。
	# 摆位：沿扇形轴外侧偏 70° 放人，离锚球 80%×命中上界 ⇒ 距离绰绰有余、角度必定出锥。
	# ⚠ 这里只借 _melee_shape 读几何来**造题**，断言的是行为（不动 + 命中），不是求解器返回值。
	var shape: Dictionary = _p.call("_melee_shape", 2)
	var axis := Vector2.RIGHT.rotated(deg_to_rad(float(shape["mid_deg"])))
	var off_axis := axis.rotated(deg_to_rad(70.0))
	var reach := float(shape["reach"])
	var placed := false
	for sp in boss.call("hit_spheres"):
		var sv: Vector3 = sp
		if sv.z <= 0.0:
			continue
		var c: Vector2 = boss.global_position + Vector2(sv.x, sv.y)
		var cand: Vector2 = c - off_axis * ((reach + sv.z) * 0.8)
		# 两道前置：① 按几何这一刀确实打不到；② 离身体中心 ≥ 软锁定半径 70，
		#    否则 _auto_aim_to_boss 会先把 attack_dir 掰走，这道题就没出成
		if bool(_p.call("_would_hit_boss", boss, shape, cand)):
			continue
		if cand.distance_to(boss.global_position) < 70.0:
			continue
		await _place_at(cand, 1)
		placed = true
		break
	if not placed:
		_check(false, "⑤ 造不出「距离够但角度不够」的站位", "逐球试完都能命中，题目失效")
	else:
		var turn_pos: Vector2 = _p.global_position
		await _swing()
		_check(bool(_p.get("_melee_turned")), "⑤ 角度落空被判成「只转向」")
		_check(not bool(_p.get("_melee_snapped")), "⑤ 角度落空时没有位移")
		var moved := _p.global_position.distance_to(turn_pos)
		_check(moved < 1.0, "⑤ 角度落空这一刀玩家位移为 0（不再扑到脸上）",
				"位移 %.2fpx" % moved)
		_check(_landed(), "⑤ 只转向之后这一刀命中了",
				"hp %.0f → %.0f" % [_hp0, _hp(boss)])

	# ===== ⑧ 弹反追击不吃缺口上限：距离很远也要追（一次性资格，追远是奖励本身）=====
	await _place(280.0)
	_p.set("parry_followup_can_dash", true)
	_p.call("apply_buff", "parry_followup", 5.0)
	var chase_start: Vector2 = _p.global_position
	await _swing()
	var chased := _p.global_position.distance_to(chase_start)
	_check(chased > 120.0,
			"⑧ 弹反追击照样吃掉 200px 以上的缺口（不受平A 的 60px 上限约束）",
			"追击位移 %.0fpx" % chased)
	_check(_landed(), "⑧ 追击后这一刀命中",
			"hp %.0f → %.0f" % [_hp0, _hp(boss)])
	_p.set("parry_followup_can_dash", false)
	boss.queue_free()
