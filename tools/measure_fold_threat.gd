extends Node
## 叠纸「折痕到底有没有参与进攻」诊断（2026-11-05 用户报：叠痕总是乱放，打不到人）
##
## 它不判 PASS/FAIL，只量一个决定性的数：**玩家折过来的对位点离 BOSS 有多远**
## （`|mirror(玩家) − BOSS|`）。按纸的扇形半径 178、双屏/押痕的圆 150 ——
## 这个数大于它们，镜像那一面就永远落空，机制参与度就是 0，不管痕画得多好看。
##
## 三种玩家行为各跑一段，分开看：
##   0 自然绕圈（普通玩家的走位）
##   1 主动站进贴合带（愿意吃机制的玩家）
##   2 躲开痕的法向（现有"空手可破"的那只手）
## 用法：godot --headless --path . res://tools/measure_fold_threat.tscn -- --no-save

const TICK := 0.1
## 逐拍状态打印只在开发本次口径时打开（跑完一轮看趋势用，不进回归）
const TRACE := false
const SIM_TIME := 40.0
const PRESS_FAN := 178.0
const PRESS_ANGLE := 104.0
const FORMS: Array[String] = [
	"form_fold_press", "form_fold_trace", "form_fold_stride", "form_fold_pressmark",
	"form_fold_shroud", "form_fold_tear", "form_fold_twin", "form_fold_triple",
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(20261105)
	print("\n########## 叠纸 · 折痕参与度诊断 ##########")
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	if player == null or boss == null:
		print("没有 player/boss，跑不了")
		get_tree().quit(2)
		return
	print("  场地半幅 %s · 贴合带 P1=%.0f P2=%.0f · 按纸扇形 %.0f" % [
		str(boss.arena_half_extents), FoldLaw.REACH_P1, FoldLaw.REACH_P2, PRESS_FAN])
	## ⚠ 无头进场时玩家的属性还没往运行时刷，`max_hp` 是 0 —— 于是押痕那 100 点
	##   伤害直接把假人打死（hp 从 0 掉到 −100，读数看着像"掉血100"）。
	##   假人一死 `_focus()` 就是空，整只 BOSS 一句招都不出，三段统计全 0
	##   —— 这不是 BOSS 弱，是夹具把目标弄没了（2026-11-05 踩过）。
	player._apply_attributes_to_runtime(true)
	_arm_dummy(player)
	await _probe_pressmark(player, boss)
	for mode in 3:
		await _run_mode(player, boss, mode)
	get_tree().quit(0)


## 假人三件同时成立才量得到东西：活着（否则 BOSS 没有目标）、
## 血打不完（否则几刀之后整段模拟停摆）、没有免伤窗口（否则"命中"永远是 0）。
func _arm_dummy(player: Node2D) -> void:
	player.is_dead = false
	player.max_hp = 1.0e9
	player.hp = 1.0e9
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0


## 定点受控：把玩家摆在离 BOSS 200/400/600/800 处，直接放一次押痕，
## 把 bisect 之后的每个中间量打出来 —— 镜像落点到底断在哪一步。
func _probe_pressmark(player: Node2D, boss: Node2D) -> void:
	print("\n  ── 押痕定点受控 ──")
	var field = boss._field
	if field == null or not is_instance_valid(field):
		return
	var b := MoveDB.resolve_boss("form_fold_pressmark")
	for d in [200.0, 400.0, 600.0, 800.0]:
		boss.global_position = Vector2.ZERO
		player.global_position = Vector2(d, 0.0)
		boss.target = player
		field._down_left = 0.0
		field._preview_left = 0.0
		field.set_phase(1)
		field.rebuild_near(player.global_position)
		boss._hit_once.clear()
		boss._fold_landings = 0
		boss._direct_landings = 0
		_arm_dummy(player)
		boss._cast_pressmark(b)
		var sp: Dictionary = field.nearest(player.global_position)
		var img: Vector2 = boss._fold_image_of(player)
		var crease_len := 0.0
		var perp := 0.0
		var alongv := 0.0
		if not sp.is_empty():
			var a: Vector2 = sp.get("a", Vector2.ZERO)
			var bb: Vector2 = sp.get("b", Vector2.ZERO)
			crease_len = a.distance_to(bb)
			perp = FoldLaw._perp_len(a, bb, player.global_position)
			alongv = FoldLaw.along(a, bb, player.global_position)
		print("     d=%.0f  痕长%.0f 垂距%.0f 沿距%.0f(线段%.0f) fold_dist%.0f → 对位%s 离BOSS %.0f · 镜像落点%d 本体%d · 掉血%.0f" % [
			d, crease_len, perp, alongv, crease_len, float(field.fold_dist(player.global_position)),
			"INF" if img == Vector2.INF else str(img),
			0.0 if img == Vector2.INF else img.distance_to(boss.global_position),
			int(boss._fold_landings), int(boss._direct_landings),
			player.max_hp - player.hp])


func _run_mode(player: Node2D, boss: Node2D, mode: int) -> void:
	boss.current_hp = boss.max_hp
	boss.phase = 1
	boss.state = BossBase.BossState.IDLE
	boss._cools.clear()
	boss._recent.clear()
	boss._hits.clear()
	boss._triple_plan.clear()
	boss._direct_landings = 0
	boss._fold_landings = 0
	boss._fold_windows = 0
	boss._gate_blocked = 0
	var field = boss._field
	if field == null or not is_instance_valid(field):
		return
	field.set_phase(1)
	field._down_left = 0.0
	field._preview_left = 0.0
	field.rebuild_near(player.global_position)
	_arm_dummy(player)
	player.global_position = boss.global_position + Vector2(0.0, 260.0)

	var dists: Array = []          # 每次采样：|mirror(P) - B|
	var d_list: Array = []         # 每次采样：BOSS↔玩家距离（先确认假人真的走在设定的环上）
	var fd_list: Array = []        # 玩家到痕的贴合距离
	var same_side := 0             # 与 BOSS 同侧（镜像根本不可能）的采样数
	var samples := 0
	var sampled := 0
	var down_ticks := 0
	var prev_ticks := 0
	var aimed_ticks := 0
	var usable := 0                # 镜像面此刻真能盖到人（对位点在扇形里）的采样数
	var att := {}
	var landed := {}
	var dmg_sum := 0.0
	var pending: Array = []
	var last := ""
	var pm_seen := 0
	var pm_preview := 0
	var pm_rows: Array = []
	var t := 0.0
	var strafe := 1.0
	while t < SIM_TIME:
		## 按物理帧步进，不用计时器：无头下 create_timer 受真实帧率影响，
		## 同一段模拟能跑出 26% 和 0% 两种结果，量出来的东西不能信
		for i in int(round(TICK * 60.0)):
			await get_tree().physics_frame
		t += TICK
		if not is_instance_valid(player) or not is_instance_valid(boss):
			break
		if player.is_dead:
			player.hp = player.max_hp
		player.stamina = player.max_stamina
		player.mana = player.max_mana
		_walk(player, boss, field, mode, t, strafe)
		if int(t * 10.0) % 27 == 0:
			strafe = -strafe
		# —— 几何采样（不看招式，纯量痕摆得对不对）——
		var d := boss.global_position.distance_to(player.global_position)
		var img: Vector2 = boss._fold_image_of(player)
		var sp: Dictionary = field.nearest(player.global_position)
		var fd := float(field.fold_dist(player.global_position))
		fd_list.append(fd)
		d_list.append(d)
		samples += 1
		if not sp.is_empty() and FoldLaw.side(sp.get("a", Vector2.ZERO),
				sp.get("b", Vector2.ZERO), boss.global_position) \
				== FoldLaw.side(sp.get("a", Vector2.ZERO), sp.get("b", Vector2.ZERO),
					player.global_position):
			same_side += 1
		sampled += 1
		if field._down_left > 0.0:
			down_ticks += 1
		elif field.is_previewing():
			prev_ticks += 1
		if field._aim_ready:
			aimed_ticks += 1
		if img != Vector2.INF:
			var off := img.distance_to(boss.global_position)
			dists.append(off)
			# 起手时 BOSS 会转向玩家，所以扇形轴向就是 B→P
			if _in_fan(img, boss.global_position,
					(player.global_position - boss.global_position).normalized(),
					PRESS_FAN, cos(deg_to_rad(PRESS_ANGLE * 0.5))):
				usable += 1
		# —— 出手统计 ——
		var cur := String(boss._current_skill)
		if TRACE and mode == 1 and int(t * 10.0) % 5 == 0 and t < 8.0:
			var dd2 := boss.global_position.distance_to(player.global_position)
			print("    t=%.1f state=%s tgt=%s d=%.0f locked=%s preview=%s aim=%s ask=%.1f down=%.1f covers=%s feas=%s pm_cd=%.1f press_cd=%.1f refold=%.1f" % [
				t, str(boss.state), str(boss.target != null and is_instance_valid(boss.target)),
				dd2, str(boss.is_skill_locked()), str(field.is_previewing()),
				str(field._aim_ready), float(boss._refold_ask), float(field._down_left),
				str(boss._fold_covers_press(player)),
				str(FoldLaw.aim_feasible(dd2, FoldLaw.reach_for(int(boss.phase)))),
				float(boss._cools.get("form_fold_pressmark", 0.0)),
				float(boss._cools.get("form_fold_press", 0.0)), float(field._refold_left)])
			print("        B%s v%s | P%s v=%s hp=%.0f | focus=%s decide=%.2f cur=%s gate=%d hitonce=%d" % [
				str(boss.global_position), str(boss.velocity),
				str(player.global_position), str(player.velocity), float(player.hp),
				str(boss._focus()), float(boss._decide_wait), String(boss._current_skill),
				int(boss._gate_blocked), int((boss._hit_once as Dictionary).size())])
			print("        target=%s(%s) pdead=%s tdead=%s focus_node=%s" % [
				str(boss.target), str((boss.target as Node).name) if boss.target != null else "-",
				str(player.get("is_dead")), str(BossBase.is_unit_dead(boss.target)),
				str(boss.focus_node())])
		if cur != "" and cur != last:
			att[cur] = int(att.get(cur, 0)) + 1
			pending.append({"form": cur, "hp0": player.hp, "t0": t})
			if cur == "form_fold_pressmark":
				pm_seen += 1
				pm_preview += 1 if field.is_previewing() else 0
				var dd := boss.global_position.distance_to(player.global_position)
				pm_rows.append("       押痕#%d t=%.1fs d=%.0f 可行=%s 预告中=%s 痕长=%.0f 玩家离痕=%.0f" % [
					pm_seen, t, dd, str(FoldLaw.aim_feasible(dd, FoldLaw.reach_for(int(boss.phase)))),
					str(field.is_previewing()),
					0.0 if field.nearest(player.global_position).is_empty()
						else (field.nearest(player.global_position) as Dictionary).get("a", Vector2.ZERO).distance_to(
							(field.nearest(player.global_position) as Dictionary).get("b", Vector2.ZERO)),
					float(field.fold_dist(player.global_position))])
		last = cur
		for i in range(pending.size() - 1, -1, -1):
			var e: Dictionary = pending[i]
			var w := float(MoveDB.resolve_boss(String(e["form"])).get("windup", 0.7))
			if t < float(e["t0"]) + w + 0.25:
				continue
			pending.remove_at(i)
			var dropped := maxf(0.0, float(e["hp0"]) - float(player.hp))
			if dropped > 0.5:
				var fm := String(e["form"])
				landed[fm] = int(landed.get(fm, 0)) + 1
				dmg_sum += dropped
			player.hp = player.max_hp
	print("\n  ── 模式 %d ──" % mode)
	print("     BOSS↔玩家 距离：%s" % _stats(d_list))
	print("     镜像面此刻能盖到人：%d/%d 次采样（%.0f%%）· 与 BOSS 同侧 %.0f%%" % [
		usable, samples, 100.0 * usable / maxf(1.0, samples),
		100.0 * same_side / maxf(1.0, samples)])
	print("     对位点离 BOSS：%s" % _stats(dists))
	print("     玩家离痕：%s" % _stats(fd_list))
	print("     场地状态：碎痕中 %d/%d 拍 · 预告中 %d · 已锁意图待折 %d" % [
		down_ticks, sampled, prev_ticks, aimed_ticks])
	var parts := ""
	for f in FORMS:
		if int(att.get(f, 0)) > 0:
			parts += "%s 出%d/中%d " % [String(f).replace("form_fold_", ""),
				int(att.get(f, 0)), int(landed.get(f, 0))]
	print("     出手/命中：%s" % parts)
	for r in pm_rows:
		print(String(r))
	print("     押痕共 %d 次，其中落在压痕预告里 %d 次" % [pm_seen, pm_preview])
	print("     镜像落点结算 %d 次 · 本体 %d 次 · 闸口拦下 %d 次" % [
		int(boss._fold_landings), int(boss._direct_landings), int(boss._gate_blocked)])
	## 假人血是 1e9（打不完），所以伤害只能自己累计；换算按实机元婴面板 988 血
	print("     40 秒累计伤害 ≈ %.0f（实机 988 血的话 = %.1f 管）" % [dmg_sum, dmg_sum / 988.0])


## 与 BOSS 判定同口径的扇形测试（探针自己复算一次，才能不看招式就量出"此刻能不能打到"）
func _in_fan(at: Vector2, origin: Vector2, dir: Vector2, reach: float,
		cos_half: float) -> bool:
	var to := at - origin
	var dd := to.length()
	if dd > reach + FoldLaw.HIT_MARGIN:
		return false
	if dd > 1.0 and dir.dot(to / dd) < cos_half:
		return false
	return true


func _walk(player: Node2D, boss: Node2D, field, mode: int, t: float, strafe: float) -> void:
	var to_b: Vector2 = boss.global_position - player.global_position
	var d := maxf(to_b.length(), 1.0)
	var radial := to_b.normalized()
	var tang := to_b.orthogonal().normalized() * strafe
	var want := Vector2.ZERO
	match mode:
		0:
			## 自然绕圈：保持 300~400 的距离转。
			## ⚠ 符号别写反：radial 是「指向 BOSS」，太近要**退**（−radial），太远才迎上去。
			##   写反之后假人一路贴到 d=48，量到的全是贴脸情形，机制参与度看着像 0（2026-11-05）。
			want = radial * (-0.9 if d < 300.0 else (0.9 if d > 400.0 else 0.0))
			want += tang * 0.8
		1:
			# 主动站进贴合带，并站到与 BOSS 分处痕的两侧
			want = radial * (-0.9 if d < 320.0 else (0.9 if d > 420.0 else 0.0))
			want += tang * 0.5
			var sp: Dictionary = field.nearest(player.global_position)
			if not sp.is_empty():
				var cd := FoldLaw.crease_dir(sp.get("a", Vector2.ZERO),
					sp.get("b", Vector2.ZERO))
				var nrm := Vector2(-cd.y, cd.x)
				var bs := FoldLaw.side(sp.get("a", Vector2.ZERO),
					sp.get("b", Vector2.ZERO), boss.global_position)
				var ms := FoldLaw.side(sp.get("a", Vector2.ZERO),
					sp.get("b", Vector2.ZERO), player.global_position)
				if bs != 0.0 and ms == bs:
					want -= nrm * bs * 260.0
				elif float(field.fold_dist(player.global_position)) > 200.0:
					want += nrm * (-ms if ms != 0.0 else 1.0) * 260.0
		2:
			# 躲开痕的法向，直到离痕 > 贴合带 + 90（现有"空手可破"那只手）
			var sp2: Dictionary = field.nearest(player.global_position)
			var n := Vector2.UP
			if not sp2.is_empty():
				n = FoldLaw.crease_dir(sp2.get("a", Vector2.ZERO),
					sp2.get("b", Vector2.ZERO)).orthogonal().normalized()
			var cur_fd := float(field.fold_dist(player.global_position))
			var sgn := 1.0 if n.dot(player.global_position
					- 0.5 * (sp2.get("a", Vector2.ZERO) as Vector2
						+ sp2.get("b", Vector2.ZERO))) >= 0.0 else -1.0
			want = n * sgn * (260.0 if cur_fd < FoldLaw.reach_for(int(boss.phase)) + 90.0 else 0.0)
			want += tang * 0.25
	## ⚠ 必须合成真的移动按键，不能直接改 global_position：
	## 那样 player.velocity 恒为 0，而 BOSS 的预判提前量吃的就是玩家速度 ——
	## 造出来的玩家看着在绕圈，实际是个从不跑步的假人，任何跟移动有关的机制都量不到。
	var dir := Vector2.ZERO
	if want.length_squared() > 0.0001:
		dir = want.normalized()
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	if dir.x > 0.25:
		Input.action_press("move_right")
	elif dir.x < -0.25:
		Input.action_press("move_left")
	if dir.y > 0.25:
		Input.action_press("move_down")
	elif dir.y < -0.25:
		Input.action_press("move_up")


func _stats(vals: Array) -> String:
	if vals.is_empty():
		return "无样本"
	var a := vals.duplicate()
	a.sort()
	var sum := 0.0
	for v in a:
		sum += float(v)
	return "中位 %.0f · 均值 %.0f · P10 %.0f · P90 %.0f · n=%d" % [
		float(a[int(a.size() * 0.5)]), sum / a.size(),
		float(a[int(a.size() * 0.1)]), float(a[mini(a.size() - 1, int(a.size() * 0.9))]),
		a.size()]
