extends Node
## 快速模式「开战」与宽时间窗（票 004）
##
## 两件事要守住：
##   ① 12 只同时激活的**激活口径**必须和普通模式逐轮激活完全相同（同款字段 + 同款 spawn 事件），
##      否则渲染层、血条、终局判定会悄悄分叉成两套。
##   ② 时间窗只该在 quick 那一侧变宽。普通模式的 120s / 60s 起推是校准过的，动不得。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_battle.tscn -- --no-save

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
	print("\n########## 快速模式开战与宽时间窗 · 票 004 ##########")
	_check_start_activates_all_twelve()
	_check_accel_curve_quick()
	_check_accel_curve_normal_unchanged()
	_check_final_judgement_shared()
	await _check_arena_fight_button()
	await _check_arena_skip()
	_finish()


## 造一个"12 张全摆好、正等开战"的快速局面。
func _ready_to_fight(level: int) -> MatchState:
	var st := MatchState.new()
	var deck: Array = MatchLevelDeck.deck_for(level)
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		if pool.size() < MatchDB.DECK_SIZE:
			pool.append(String(id))
	st.start([pool, deck], 999, 0)
	st.quick_open(1, deck, MatchQuickSetup.layout_for(level))
	st.apply_command({"t": "pick", "team": 0, "ids": pool})
	for n in MatchDB.DECK_SIZE:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		st.apply_command({"t": "deploy", "team": 0, "card": int(legal[0]), "cell": cells[0]})
	return st


## ① 开战一次把 12 只全激活，字段与事件和普通模式的 _resolve_round 同款。
func _check_start_activates_all_twelve() -> void:
	var st := _ready_to_fight(6)
	st.drain_events()
	st.quick_start_battle()
	_check(st.phase == MatchState.Phase.FINAL, "① 开战后直接进终局（不经过六轮）", str(st.phase))
	var n_act := 0
	var n_spawn := 0
	for c in st.cards:
		if bool(c["activated"]) and bool(c["spawned"]) and bool(c["alive"]):
			n_act += 1
	var evs: Array = st.drain_events()
	for e in evs:
		if String((e as Dictionary)["t"]) == "spawn":
			n_spawn += 1
	_check(n_act == 12, "① 12 张全部 activated+spawned+alive", "%d 张" % n_act)
	_check(n_spawn == 12, "① 逐张发 12 个 spawn 事件（渲染层不用改）", "%d 个" % n_spawn)
	_check(st.deployed_count() == 12, "① 落子数没被开战改动", str(st.deployed_count()))


## ② 快速模式加速曲线：120s 起推、240s 到 2.0×，中点 1.5×。
func _check_accel_curve_quick() -> void:
	var st := _ready_to_fight(6)
	st.phase = MatchState.Phase.FINAL
	var pts := {60.0: 1.0, 120.0: 1.0, 180.0: 1.5, 240.0: 2.0}
	var bad: Array = []
	for t in pts:
		st.final_elapsed = float(t)
		var got := st.time_scale()
		if absf(got - float(pts[t])) > 0.001:
			bad.append("%.0fs=%.3f 应为 %.2f" % [float(t), got, float(pts[t])])
	_check(bad.is_empty(), "② 快速模式 120s 起推、180s=1.5×、240s=2.0×", str(bad))
	_check(absf(st.final_limit() - 240.0) < 0.001, "② 快速终局上限 = 240s", str(st.final_limit()))


## ③ 普通模式的曲线与上限**一个数字都没变**（这是反向判据的数值版）。
func _check_accel_curve_normal_unchanged() -> void:
	var st := MatchState.new()
	st.phase = MatchState.Phase.FINAL
	var pts := {30.0: 1.0, 60.0: 1.0, 90.0: 1.5, 120.0: 2.0}
	var bad: Array = []
	for t in pts:
		st.final_elapsed = float(t)
		var got := st.time_scale()
		if absf(got - float(pts[t])) > 0.001:
			bad.append("%.0fs=%.3f 应为 %.2f" % [float(t), got, float(pts[t])])
	_check(bad.is_empty(), "③ 普通模式 60s 起推、120s=2.0× 没变", str(bad))
	_check(absf(st.final_limit() - MatchDB.FINAL_LIMIT_SECONDS) < 0.001,
			"③ 普通终局上限仍是表里那个 120s", str(st.final_limit()))


## ④ 终局判定共用同一个 _tick_final：清场 ⇒ clear_field，超时 ⇒ 比血量百分比。
## 快速模式**不许**自带第二套胜负函数。
func _check_final_judgement_shared() -> void:
	var a := _ready_to_fight(4)
	a.quick_start_battle()
	for c in a.cards:
		if int(c["team"]) == 1:
			c["alive"] = false
			c["hp"] = 0.0
		else:
			c["alive"] = true
			c["hp"] = 1000.0
	a._tick_final(0.016)
	_check(a.phase == MatchState.Phase.OVER and String(a.end_reason) == "clear_field",
			"④ 清场判定走同一个函数", "%s/%s" % [str(a.phase), a.end_reason])
	_check(int(a.winner) == 0, "④ 清场后赢家是对方全灭的那一队", str(a.winner))

	var b := _ready_to_fight(4)
	b.quick_start_battle()
	# ⚠ 造超时要把 timer 一起清零：_begin_final 按 final_limit() 上了表，
	#   只改 final_elapsed 的话 timer 还剩 240，永远走不到超时那一支。
	b.final_elapsed = 241.0
	b.timer = 0.0
	for c in b.cards:
		c["alive"] = true
		c["hp_max"] = 1000.0
		c["hp"] = 900.0 if int(c["team"]) == 0 else 100.0
	b._tick_final(0.016)
	_check(b.phase == MatchState.Phase.OVER and String(b.end_reason) == "timeout_hp",
			"④ 超时走同一条血量百分比判定", "%s/%s" % [str(b.phase), b.end_reason])
	_check(int(b.winner) == 0, "④ 剩余血量比例高的一方胜出", str(b.winner))


## ⑤ 底栏那颗「开战」：没摆完禁用并显示还差几张，摆完才可点。
func _check_arena_fight_button() -> void:
	var arena: Node = await _mk_quick_arena()
	var fight: Button = arena.get("_buttons").get("fight")
	_check(fight != null, "⑤ 快速模式有「开战」这颗钮", "")
	if fight == null:
		return
	_check(not fight.visible, "⑤ 选牌阶段不出现「开战」（还没到布阵）",
			"vis=%s" % str(fight.visible))

	# 交牌 + 摆满 6 张
	var st = arena.get("_state")
	_pick_all(st)
	arena.call("_refresh_stage")
	await get_tree().process_frame
	_check(fight.visible and fight.disabled, "⑤ 进布阵但一张没摆 ⇒ 可见且禁用",
			"vis=%s dis=%s" % [str(fight.visible), str(fight.disabled)])
	_check(String(fight.text).contains("还差 6 张"), "⑤ 禁用态写明还差几张（从计数现算）",
			String(fight.text))
	for n in MatchDB.DECK_SIZE:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		st.apply_command({"t": "deploy", "team": 0, "card": int(legal[0]), "cell": cells[0]})
	arena.call("_refresh_stage")
	await get_tree().process_frame
	_check(fight.visible and not fight.disabled, "⑤ 摆满 6 张 ⇒ 可点",
			"vis=%s dis=%s" % [str(fight.visible), str(fight.disabled)])
	fight.pressed.emit()
	await get_tree().process_frame
	_check(st.phase == MatchState.Phase.FINAL, "⑤ 点「开战」真的进了终局", str(st.phase))
	await _teardown(arena)


## ⑥ 「跳过（按策略代打）」在快速模式必须**一次摆完 6 张**并给一句回执。
## 点一次只落一子是普通模式的语义（那里要交替回合）；快速模式没得交替，
## 六下点击每下只是手里少一张，就是用户报过最多那类「点了没反应」。
func _check_arena_skip() -> void:
	var arena := await _mk_quick_arena()
	var st = arena.get("_state")
	_pick_all(st)
	arena.call("_refresh_stage")
	await get_tree().process_frame

	var skip: Button = arena.get("_buttons").get("skip")
	var fight: Button = arena.get("_buttons").get("fight")
	_check(skip != null and skip.visible, "⑥ 布阵阶段「跳过」可见", "")
	if skip == null:
		await _teardown(arena)
		return
	_check(fight.disabled, "⑥ 按跳过之前「开战」还锁着", str(fight.disabled))
	skip.pressed.emit()
	await get_tree().process_frame
	_check(int(st.deployed_count()) == 12, "⑥ 按一下 ⇒ 6 张一次摆完",
			"%d 子" % int(st.deployed_count()))
	var notice := String(arena.get("_notice").text)
	_check(notice.contains("摆好 6 张"), "⑥ 回执写明摆了几张", notice)
	_check(fight.visible and not fight.disabled, "⑥ 跳完「开战」立刻变可点",
			"vis=%s dis=%s" % [str(fight.visible), str(fight.disabled)])
	# 再按第二下不许把已经摆好的吞掉，也不许静默
	skip.pressed.emit()
	await get_tree().process_frame
	_check(int(st.deployed_count()) == 12, "⑥ 重复点不吞已摆的 6 张",
			str(int(st.deployed_count())))
	_check(String(arena.get("_notice").text).contains("都在盘上"),
			"⑥ 没得摆时回执改口，不静默", String(arena.get("_notice").text))
	_check(st.phase == MatchState.Phase.DEPLOY, "⑥ 跳过不越权开战",
			String(MatchState.PHASE_NAME[st.phase]))
	await _teardown(arena)


## 开一局真·快速对局并停在「刚交完牌、一张还没摆」的布阵态。
func _mk_quick_arena() -> Node:
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = 4
	GameState.match_context = {"level": 5}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 20:
		await get_tree().process_frame
	return arena


func _pick_all(st) -> void:
	var pool: Array = st.legal_pool(0)
	var ids: Array = []
	for i in MatchDB.DECK_SIZE:
		ids.append(String(pool[i]))
	st.apply_command({"t": "pick", "team": 0, "ids": ids})


func _teardown(arena: Node) -> void:
	arena.queue_free()
	await get_tree().process_frame
	CharacterData.match_quick_mode = false
	GameState.match_context = {}


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
