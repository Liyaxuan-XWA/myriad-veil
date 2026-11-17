extends Node2D
## 时停验收（2026-11-03 用户 B 案）
##
## 用户要的不是"看着像停了"，而是**真的时间暂停**：棋子的动作（移动 / 出手 /
## 招式状态）、已经排好落地时刻的技能、以及棋子身上的 buff / debuff 全部冻住，
## 窗口结束必须原样恢复。
##
## 两层闸门各自都要查到（少一层就是半个时停）：
## ① `get_tree().paused` 冻"过程"：物理积分、Tween、粒子、动画，以及全部按 delta
##    计时的东西（`state_timer` / 冷却 / `_tick_debuffs`）。冻的范围 = 整棵对局场景，
##    只有 HUD 与 MatchDriver 两支写 ALWAYS 继续活着，所以倒计时和按钮照常用。
## ② `BossBase.world_frozen` 冻"后果"：`create_timer()` 的 `process_always` 默认
##    true，树停了它照样触发回调（赫连霄的雷 / 火麟的陨 / 石犼的爪都靠它排落地
##    时刻，2f 就是实测到回调照跑）—— 所以延迟伤害、补挂 debuff、飘字幕必须在
##    BOSS 基类里再拦一道。
##
## ⚠ 本探针的根节点**不写** PROCESS_MODE_ALWAYS：给场景根写 ALWAYS 再让棋子退回
##   PAUSABLE 是第一版的写法，实测冻不住（窗口里点燃照跳、延迟伤害照落地）；
##   而探针根本身就是"对局场景的祖先"，一写 ALWAYS 就把整棵对局树带进同一条歧路，
##   量出来全是假绿。要查"显式 ALWAYS 的分支在暂停里照跑"这条底层规则，
##   用 tools/diag_pause_topology.tscn（它同时也说明那条歧路不该依赖）。
##   探针自己靠 `get_tree().physics_frame` 推进：树暂停时这个信号照样每帧发，
##   await 它不要求本节点正在处理。
##
## 每条关键断言都配一次反向对照：同一段时间在不冻的场面里必须**真的会变**，
## 否则探针会因为"什么都没发生"而假绿。
##
## 用法：godot --headless --path . res://tools/probe_match_freeze.tscn -- --no-save

var _passes := 0
var _fails: Array = []
## 2f 那发延迟伤害的返回值。⚠ 必须是成员变量：GDScript 的 lambda 按**值**捕获局部
## 变量，在 lambda 里给局部变量赋值，外面永远读不到（第一版就栽在这，整节假绿）。
var _landed: Variant = null
var _landed_ran := false


func _check(ok: bool, name: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("  ok  ", name, "  ", detail)
	else:
		_fails.append(name + " | " + detail)
		print("  !   ", name, "  ", detail)


func _ready() -> void:
	await _check_table()
	await _check_live()
	await _check_whole_match()
	print("\n########## 时停：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(0 if _fails.is_empty() else 1)


# ===================== 一、取值表 =====================

func _mk_state() -> MatchState:
	var st := MatchState.new()
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		pool.append(String(id))
	st.start([pool.slice(0, 8), pool.slice(8, 16)], 90210, 0)
	return st


func _check_table() -> void:
	print("\n### 1. time_stopped() 取值表")
	var st := _mk_state()
	_check(st.phase == MatchState.Phase.PICK and st.time_stopped(),
			"PICK 停", String(MatchState.PHASE_NAME.get(int(st.phase), "?")))
	for t in [0, 1]:
		st.apply_command({"t": "pick", "team": t,
				"ids": MatchPolicy.decide_deck(st.legal_pool(t))})
	_check(st.phase == MatchState.Phase.LOCK and st.time_stopped(),
			"LOCK 停", String(MatchState.PHASE_NAME.get(int(st.phase), "?")))
	for t in [0, 1]:
		var lk: Dictionary = MatchPolicy.decide_lock(st, t)
		if not lk.is_empty():
			st.apply_command({"t": "lock", "team": t,
					"down": int(lk["down"]), "up": int(lk["up"])})
	var saw_deploy := false
	for guard in 40:
		if st.phase != MatchState.Phase.DEPLOY:
			break
		if not saw_deploy:
			saw_deploy = true
			_check(st.time_stopped(), "DEPLOY 停", "phase=deploy")
		for t in [0, 1]:
			var mv: Dictionary = MatchPolicy.decide_deploy(st, t, st.rng)
			if not mv.is_empty():
				st.apply_command({"t": "deploy", "team": t,
						"card": int(mv["card"]), "cell": mv["cell"]})
	# 战斗阶段的两个子态（开打 / 暗选窗口）
	st.set("phase", MatchState.Phase.BATTLE)
	st.set("_fighting", true)
	_check(not st.time_stopped(), "开打时不停（时间要真的在走）", "")
	st.set("_fighting", false)
	_check(st.time_stopped(), "战斗窗口的暗选段停", "")
	st.pending[0] = 3
	_check(st.time_stopped(), "己方已提交、还在等对面的那几秒也停",
			"（拿 _awaiting_player 当判据会在这种空档先松开）")
	st.set("phase", MatchState.Phase.FINAL)
	_check(not st.time_stopped(), "FINAL 加速段不停", "")
	st.set("phase", MatchState.Phase.OVER)
	_check(not st.time_stopped(), "OVER 不停：死亡淡出与结算动画得播完", "")


# ===================== 二、真场景 =====================

## 场上所有真棋子（棋子挂在 host 里一层）
func _units(pieces: Node) -> Array:
	var out: Array = []
	for host in pieces.get_children():
		if not is_instance_valid(host):
			continue
		for raw in host.get_children():
			if is_instance_valid(raw) and raw is BossBase:
				out.append(raw)
	return out


## 按实例 id 记读数，不按下标 —— 窗口里上一轮激活的牌会合法进场，
## 按下标比会把"进场"误判成"动了"。
## 五项读数：位置 / 血量 / 招式状态 / 招表进度 / 索敌。
## state_timer 由 `_tick_state(delta)` 每帧递减 —— 脑子还在转就一定变，
## 只看位置会漏掉"原地续招"，只看血量会漏掉"走位不砍人"。
func _snap(units: Array) -> Dictionary:
	var out: Dictionary = {}
	for u in units:
		out[u.get_instance_id()] = [u.get("global_position"), float(u.get("current_hp")),
				int(u.get("state")), float(u.get("state_timer")),
				int(u.get("target").get_instance_id()) if u.get("target") != null else -1]
	return out


## a 里每一只都必须还在、且五项读数一字不差；b 里多出来的是新进场，不算变化。
func _diff(a: Dictionary, b: Dictionary) -> String:
	for k in a.keys():
		if not b.has(k):
			return "id=%s 不见了" % str(k)
		var va: Array = a[k]
		var vb: Array = b[k]
		var pa: Vector2 = va[0]
		var pb: Vector2 = vb[0]
		if pa.distance_to(pb) > 0.5 or absf(float(va[1]) - float(vb[1])) > 0.01 \
				or int(va[2]) != int(vb[2]) \
				or absf(float(va[3]) - float(vb[3])) > 0.001 or int(va[4]) != int(vb[4]):
			return "id=%s 位移 %.1f 血量 %+0.1f 状态 %s→%s 招表 %+0.2f 目标 %s→%s" % [
					str(k), pa.distance_to(pb), float(vb[1]) - float(va[1]),
					str(va[2]), str(vb[2]), float(va[3]) - float(vb[3]),
					str(va[4]), str(vb[4])]
	return ""


## 招名 / 状态字幕是 `_show_skill_text` 现场 new 的 Label，挂在棋子节点的子层。
func _label_count(pieces: Node) -> int:
	var n := 0
	for host in pieces.get_children():
		if not is_instance_valid(host):
			continue
		for raw in host.get_children():
			if not is_instance_valid(raw):
				continue
			for ch in (raw as Node).get_children():
				if ch is Label:
					n += 1
	return n


var _arena: Node
var _pieces: Node


func _run_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check_live() -> void:
	print("\n### 2. 对局场景里的时停")
	_arena = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	_arena.set("player_stage_timeout", 0.35)      # 先快点跑完选牌 / 锁定 / 布阵
	add_child(_arena)
	_pieces = _arena.get_node("Pieces")

	var st = null
	for guard in 6000:
		await get_tree().physics_frame
		st = _arena.get("_state")
		if st == null:
			continue
		if int(st.phase) == MatchState.Phase.BATTLE and st.fighting() \
				and _units(_pieces).size() >= 2:
			break
	var us0 := _units(_pieces)
	_check(st != null and int(st.phase) == MatchState.Phase.BATTLE and st.fighting()
			and us0.size() >= 2,
			"跑到第一轮开打且场上有棋子",
			"phase=%s 棋子=%d" % [String(MatchState.PHASE_NAME.get(int(st.phase), "?")),
					us0.size()])
	if us0.size() < 2 or st == null:
		return

	# ---- 2a. 开打段：两层闸门都开着，而且**必须真的在逐帧处理**（反向对照的基线）
	#        基线用点燃剩余时间，不用位移：两只刚进场互相走向对方的棋子也可能
	#        整段站在原地蓄招，位移为 0 不能证明"探针没在看"。点燃只有
	#        `_physics_process` 在跑才会跳，是最干净的"脑子还在转"读数。
	_check(not get_tree().paused and not BossBase.world_frozen,
			"开打时两层闸门都开着",
			"paused=%s frozen=%s" % [str(get_tree().paused), str(BossBase.world_frozen)])
	var base := _snap(us0)
	var burned := bool(us0[0].apply_debuff("burn", 600.0))
	await _run_frames(45)
	var live := _diff(base, _snap(_units(_pieces)))
	var burn_live := float(us0[0].get("debuffs").get("burn", 0.0))
	_check(burned and burn_live < 600.0,
			"开打 0.75 秒里点燃确实在跳（棋子逐帧在处理，探针看得见动静）",
			"剩余 %.2f 另外读数变化：%s" % [burn_live, live if live != "" else "无"])

	# ---- 2b. 场景侧的代选超时抬高：不然量到一半就被"玩家超时自动提交"解冻
	_arena.set("player_stage_timeout", 90.0)

	# ---- 2c. 本轮打到点 → 进暗选窗口 → 闸门必须落下
	st.set("timer", 0.02)
	for guard in 600:
		await get_tree().physics_frame
		if not st.fighting():
			break
	_check(not st.fighting(), "本轮打到点、进入选牌窗口", "timer=%.2f" % float(st.timer))
	await _run_frames(3)
	_check(get_tree().paused, "窗口里整棵树被 pause", str(get_tree().paused))
	_check(BossBase.world_frozen, "窗口里 BossBase.world_frozen 也拨上",
			str(BossBase.world_frozen))
	_check(int(_arena.get("process_mode")) == Node.PROCESS_MODE_INHERIT,
			"对局场景根保持 INHERIT（写 ALWAYS 会盖掉棋子的暂停，实测过）",
			str(_arena.get("process_mode")))
	var drv: Node = _arena.get_node_or_null("Driver")
	_check(drv != null and int(drv.get("process_mode")) == Node.PROCESS_MODE_ALWAYS,
			"帧驱动搬到叶子节点 Driver（ALWAYS 传染不到棋子）", "")
	_check(int(_arena.get_node("HUD").get("process_mode")) == Node.PROCESS_MODE_ALWAYS,
			"HUD 那支写 ALWAYS（按钮与倒计时窗口里照常用）", "")
	var u1 := _units(_pieces)
	# ⚠ 用 `can_process()` 而不是 `is_physics_processing()`：后者读的是"这个节点有没有
	#   开启物理处理"的开关（棋子一直开着，暂停时也返回 true）；前者才是
	#   "在不在树里 + 树暂停时该不该跑"的真实判定。
	_check(not bool(u1[0].call("can_process")), "窗口里棋子不再被处理",
			"can_process=%s" % str(u1[0].call("can_process")))
	var drv2: Node = _arena.get_node("Driver")
	_check(bool(drv2.call("can_process")), "同一段时间里 Driver 仍被处理（驱动没断）",
			"can_process=%s" % str(drv2.call("can_process")))

	# ---- 2d. 冻住：位置 / 血量 / 招式状态 / 招表进度 / 索敌，一项都不许动
	var frozen := _snap(u1)
	var burn0 := float(u1[0].get("debuffs").get("burn", 0.0))
	await _run_frames(90)          # 1.5 秒真实时间：够跳 3 次点燃、够走完一整段招式
	var drifted := _diff(frozen, _snap(_units(_pieces)))
	_check(drifted == "", "窗口 1.5 秒内棋子不动、不出手、不掉血、不换目标", drifted)
	_check(BossBase.world_frozen, "1.5 秒过去闸门还在（窗口没被提前解掉）", "")
	var u1b := _units(_pieces)
	var burn1 := float(u1b[0].get("debuffs").get("burn", 0.0))
	_check(burn1 > 0.0 and absf(burn1 - burn0) < 0.01, "点燃剩余时间不减少",
			"%.3f→%.3f" % [burn0, burn1])

	# ---- 2e. 窗口本身照旧倒数：时停冻的是场面，不是整局
	var t0 := float(st.timer)
	await _run_frames(30)
	_check(float(st.timer) < t0 - 0.3, "窗口倒计时照旧在走（HUD 那 10 秒真的在数）",
			"%.2f→%.2f" % [t0, float(st.timer)])
	_check(BossBase.world_frozen, "倒计时走了但闸门没松（冻的是场面不是窗口）", "")

	# ---- 2f. 那个洞：create_timer(process_always=true) 在暂停里照样触发，
	#        招式把落地时刻排在这种计时器上，所以要拦的是它**造成的后果**。
	_landed = null
	_landed_ran = false
	var timer := get_tree().create_timer(0.05, true, false, true)
	timer.timeout.connect(func() -> void:
		var now := _units(_pieces)
		if now.size() < 2:
			return
		_landed_ran = true
		_landed = now[0].deal_damage_to(now[1], 500.0, "elemental"))
	await _run_frames(40)
	_check(_landed_ran, "延迟回调确实触发了（证明 pause 拦不住它，得拦后果）",
			"返回值=%s" % str(_landed))
	_check(_landed == false, "时停里延迟伤害不落地", str(_landed))
	var after_cb := _diff(frozen, _snap(_units(_pieces)))
	_check(after_cb == "", "回调跑完后棋子仍然一动不动", after_cb)
	_check(not bool(u1b[0].apply_debuff("stun", 5.0)), "时停里挂不上新 debuff",
			str(u1b[0].get("debuffs").get("stun", "没有")))
	var lb0 := _label_count(_pieces)
	u1b[0].show_skill_line("测试招名", 1.0)
	await _run_frames(3)
	_check(_label_count(_pieces) == lb0, "时停里不冒新字幕（否则字会挂在半空淡不掉）",
			"%d→%d" % [lb0, _label_count(_pieces)])

	# ---- 2g. 弹体：窗口里新出现的那发也必须悬住
	var proj: Node = u1b[0].call("_spawn_projectile", "elemental")
	if proj != null and is_instance_valid(proj):
		var pp: Vector2 = proj.get("global_position")
		await _run_frames(20)
		var pj := pp.distance_to(Vector2(proj.get("global_position")))
		_check(pj < 0.5, "窗口里新出现的弹体悬住不动", "位移 %.1f" % pj)
		if is_instance_valid(proj):
			proj.queue_free()
	else:
		_check(false, "能造出一发弹体做悬停对照", "spawn 返回空")

	# ---- 2h. 解冻：窗口到点自动出牌、重新开打，棋子立刻恢复行动
	st.set("timer", 0.05)
	for guard in 900:
		await get_tree().physics_frame
		if st.fighting():
			break
	_check(st.fighting(), "窗口到点后两边自动出牌、重新开打",
			"fighting=%s phase=%s" % [str(st.fighting()),
					String(MatchState.PHASE_NAME.get(int(st.phase), "?"))])
	_check(not get_tree().paused and not BossBase.world_frozen,
			"重新开打后两层闸门都复位",
			"paused=%s frozen=%s" % [str(get_tree().paused), str(BossBase.world_frozen)])
	var us2 := _units(_pieces)
	var thaw := _snap(us2)
	# 用"新 debuff 挂得上 + 开始跳"来判定时间真的重新流走：
	# apply_debuff 返回的是"是不是新挂上的"，同一只已经带点燃，再挂点燃只会刷新时长、
	# 返回 false —— 第一版把这个当成"挂不上"，是自己读错了返回值。
	var resumed := bool(us2[0].apply_debuff("wounded", 30.0))
	await _run_frames(45)
	var wounded_left := float(us2[0].get("debuffs").get("wounded", 0.0))
	_check(resumed and wounded_left > 0.0 and wounded_left < 30.0,
			"解冻后棋子重新开始逐帧处理（debuff 挂得上并且开始跳）",
			"新挂=%s 剩余 %.2f；读数变化：%s" % [str(resumed), wounded_left,
					_diff(thaw, _snap(_units(_pieces)))])

	# ---- 2i. 离场不留 paused
	st.set("phase", MatchState.Phase.PICK)
	await _run_frames(3)
	_check(get_tree().paused, "离场前先确认是冻着的", str(get_tree().paused))
	_arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not get_tree().paused, "场景离场后树不再暂停（主城不能被塞一个暂停）",
			str(get_tree().paused))
	_check(not BossBase.world_frozen, "场景离场后全局闸门复位", str(BossBase.world_frozen))


# ===================== 三、整局跑通 =====================

## 时停开关一局里要反复拨二十几次，每一次都必须既冻得上又松得开。
## 这里把整局加速跑完（窗口与战斗段都把 timer 拨到快到期），只查三件事：
## ① 真打到 OVER（不会被某次冻结卡死在原地）；
## ② 结算面板出来了（OVER 特意不冻，否则淡出与面板动画都停在半路）；
## ③ 闸门与 paused 在结束时都是开的、离场后也不留暂停。
func _check_whole_match() -> void:
	print("\n### 3. 整局跑通（时停反复拨二十几次不能卡死）")
	var arena = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 0.3)
	add_child(arena)
	var flips := 0
	var was := false
	var frames := 0
	var st = null
	for guard in 40000:
		frames += 1
		await get_tree().physics_frame
		st = arena.get("_state")
		if st == null:
			continue
		var fz := bool(arena.get("_frozen"))
		if fz != was:
			was = fz
			flips += 1
		if int(st.phase) == MatchState.Phase.BATTLE or int(st.phase) == MatchState.Phase.FINAL:
			st.set("timer", minf(float(st.timer), 0.03))
		if int(st.phase) == MatchState.Phase.OVER:
			break
	_check(int(st.phase) == MatchState.Phase.OVER,
			"整局打到结束（没有哪一次冻结把局卡住）",
			"%d 帧 / 拨了 %d 次 / phase=%s reason=%s" % [frames, flips,
					String(MatchState.PHASE_NAME.get(int(st.phase), "?")),
					str(st.get("end_reason"))])
	# 一局里翻牌轮数不一定跑满 12（一边被清空就提前结束），所以门槛按"实际打了几轮"算：
	# 每轮至少一次「解冻开打 → 冻住选牌」= 两次翻转。
	var rounds := int(st.get("round_index"))
	_check(flips >= rounds * 2 - 2,
			"结束前闸门确实反复开合过（不是一次性状态）",
			"打了 %d 轮 / 拨了 %d 次" % [rounds, flips])
	await _run_frames(6)
	_check(not get_tree().paused and not BossBase.world_frozen,
			"结算态下两层闸门都是开的（死亡淡出与结算动画在播）",
			"paused=%s frozen=%s" % [str(get_tree().paused), str(BossBase.world_frozen)])
	var res: Control = arena.get("_result")
	_check(res != null and res.visible, "结算面板真的显示出来了",
			"面板=%s" % ("无" if res == null else str(res.visible)))
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not get_tree().paused, "整局结束后离场也不留暂停", str(get_tree().paused))
	_check(not BossBase.world_frozen, "整局结束后全局闸门复位", str(BossBase.world_frozen))
