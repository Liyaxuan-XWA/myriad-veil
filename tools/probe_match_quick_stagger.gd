extends Node
## 开战入场摊帧 + 预载 + 终局计时对齐（票 004 追加 / 卡顿优化三件套）
##
## 实测根因（tools/measure_threaded_warm.gd）：点「开战」那一帧 645ms，
## 其中石犼的招式图集在主线程解码 455ms、刀客 190ms；同一进程里再建一只
## 一样的棋子只要 35–55ms ⇒ 钱花在「读资源解码」，不在「建节点」。
##
## 这一轮守三条：
##   ① 规则层**仍然**是 12 只同时激活（activated/spawned/alive 点下去就全给齐）。
##   ② 落场节点摊成每帧 2 只，而且**两边交替** —— 事件流是对方 6 只在前，
##      不交错就等于送对面半秒先手。
##   ③ 摊帧期间终局计时不许走，不然最后两只一上场就发现自己迟到 0.1 秒。
## 外加预载链路的证据：落子 ⇒ 场景排队 ⇒ 场景到手后把它声明的招式表也拉进来。
##
## 采样而不是死等某一帧：点下去之后 tick 与 process_frame 的先后差一帧，
## 逐帧采样既稳又能证明「没有哪一帧一次蹦出 12 只」。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_stagger.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _planned := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _plan(n: int) -> void:
	_planned += n


func _ready() -> void:
	print("\n########## 开战摊帧与预载 · 卡顿优化 ##########")
	await _check_stagger_and_timer()
	await _check_warm_chain()
	await _check_release_on_exit()
	# 哨兵：PLANNED **不含**这一条自身，否则永远差一条（判据计数踩过这个坑）
	_check(_passes + _fails.size() >= _planned, "⑤ 判据全部跑到（没有半途中止）",
			"%d/%d" % [_passes + _fails.size(), _planned])
	_finish()


## 场上真棋子数（每只一个 PieceHost，所以数 host 就是数棋子）
func _pieces(arena: Node) -> int:
	var pc: Node = arena.get("_pieces") as Node
	return pc.get_child_count() if pc != null else -1


func _arena_quick(level: int) -> Node:
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = level - 1
	GameState.match_context = {"level": level}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 20:
		await get_tree().process_frame
	return arena


## 交牌 + 把 6 张全摆上（走 state 命令，和 UI 点「跳过」等价）
func _deploy_all(arena: Node, st) -> void:
	var pool: Array = st.legal_pool(0)
	var ids: Array = []
	for i in MatchDB.DECK_SIZE:
		ids.append(String(pool[i]))
	st.apply_command({"t": "pick", "team": 0, "ids": ids})
	arena.call("_refresh_stage")
	await get_tree().process_frame
	for n in MatchDB.DECK_SIZE:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		st.apply_command({"t": "deploy", "team": 0, "card": int(legal[0]), "cell": cells[0]})
	arena.call("_refresh_stage")
	await get_tree().process_frame


func _press_fight(arena: Node) -> bool:
	var btns: Dictionary = arena.get("_buttons")
	var fight: Button = btns.get("fight")
	if fight == null or not fight.visible or fight.disabled:
		return false
	fight.pressed.emit()
	return true


## ① 规则层同时激活　② 摊帧 + 交替　③ 计时对齐
func _check_stagger_and_timer() -> void:
	_plan(9)
	var arena: Node = await _arena_quick(5)
	var st = arena.get("_state")
	await _deploy_all(arena, st)
	_check(_pieces(arena) == 0, "① 开战前场上 0 只（摆好的只是 token）", str(_pieces(arena)))
	_check(_press_fight(arena), "① 「开战」摆满 6 张后可点", "")

	# 逐帧采样到 12 只落齐为止。⚠ 不能只采 14 帧：headless 一帧只有零点几毫秒墙钟，
	# 预载还没排空、闸门还按着落场，采到的全是 0（第一版就是这么红的）。
	var counts: Array = []
	var elapsed_while_queued := -1.0
	var late := 0
	while late < 240:
		await get_tree().process_frame
		late += 1
		var c := _pieces(arena)
		# 闸门按住的那段全是 0，别把它记进 counts（否则"第一批落几只"量的全是等待）
		if c > 0 and counts.size() < 24:
			counts.append(c)
		if c < 12 and elapsed_while_queued < 0.0:
			elapsed_while_queued = float(st.final_elapsed)
		if c >= 12:
			break
	var jumps: Array = []
	var prev := 0
	for c in counts:
		if int(c) - prev > 6:
			jumps.append("%d→%d" % [prev, int(c)])
		prev = int(c)
	var first_landing := 0
	for c in counts:
		if int(c) > 0:
			first_landing = int(c)
			break
	_check(first_landing >= 1 and first_landing < 12,
			"② 第一批只落几只，不是一次 12 只", str(counts.slice(0, 12)))
	_check(jumps.is_empty(), "② 任何一帧落场都不超过半批（6 只）", str(jumps))
	_check(prev == 12, "② 摊帧收口：12 只全在场", "%d 只 / %d 帧" % [prev, late])

	var n_act := 0
	for c in st.cards:
		if bool(c["activated"]) and bool(c["spawned"]) and bool(c["alive"]):
			n_act += 1
	_check(n_act == 12, "① 规则层仍然 12 只同时激活（摊的只是节点）", "%d 张" % n_act)
	_check(elapsed_while_queued >= 0.0 and elapsed_while_queued <= 0.0001,
			"③ 还没落完 ⇒ 终局计时没开始走", "%.4f s" % elapsed_while_queued)

	# 交替落场：前两只必须一边一只（按 host 入树顺序读 meta）
	var teams: Array = []
	var pc: Node = arena.get("_pieces")
	for h in pc.get_children():
		teams.append(int(h.get_meta("team")))
	_check(teams.size() >= 2 and teams[0] != teams[1],
			"② 交错落场：前两只一边一只（不送对面先手）", str(teams.slice(0, 4)))
	await _settle_frames(3)
	_check(float(st.final_elapsed) > 0.0, "③ 落完之后终局计时恢复",
			"%.3f s" % float(st.final_elapsed))
	arena.queue_free()
	await get_tree().process_frame


## ④ 预载链路：落子 ⇒ 场景进队列 ⇒ 场景声明的美术条目也进队列并押住
func _check_warm_chain() -> void:
	_plan(6)
	var arena: Node = await _arena_quick(6)
	var st = arena.get("_state")
	await _deploy_all(arena, st)
	var deck: Array = []
	for c in st.cards:
		deck.append(String(c["boss_id"]))
	_check(deck.size() == 12, "④ 场面确有 12 张（对方 6 + 玩家 6）", str(deck.size()))

	var waited := 0
	while SkinWarm.is_busy() and waited < 400:
		await get_tree().process_frame
		waited += 1
	_check(not SkinWarm.is_busy(), "④ 预载队列排空", "%d 帧" % waited)

	var missing: Array = []
	for id in deck:
		var p := MatchAdapter.scene_path_for(String(id))
		if p == "" or not SkinWarm.is_ready(p):
			missing.append(String(id))
	_check(missing.is_empty(), "④ 落子过的 12 份场景都已在内存", str(missing))

	# 真效果：拿一只**真上场的棋子**身上的 visual_id 反查它的招式表 / rig 有没有被押住。
	# 只看「队列空了」不算证明 —— 可能是场景到了但招式表压根没排队。
	_check(_press_fight(arena), "④ 能点开「开战」", "")
	await _settle_frames(12)
	var probe := _first_boss_with_skin(arena)
	_check(probe != null, "④ 找得到一只带 SkinVisual 的棋子", "")
	if probe != null:
		var skin := probe.get_node_or_null("Visual/Skin")
		var vid := String(skin.get("visual_id"))
		var entry: Dictionary = ArtDB.get_visual(vid)
		var wanted: Array = []
		for key in ["sprite_frames", "rig"]:
			var p := String(entry.get(key, ""))
			if p != "":
				wanted.append(p)
		var not_ready: Array = []
		for p in wanted:
			if not SkinWarm.is_ready(String(p)):
				not_ready.append(String(p).get_file())
		# ⚠ 同时要求 wanted 非空：两条路径都缺时 not_ready 自然是空的，
		#   那就成了一条永远绿的判据（本项目栽过好几次的那种）。
		_check(not wanted.is_empty() and not_ready.is_empty(),
				"④ 场景声明的美术条目已被押住（%s）" % vid, str(wanted))
	else:
		_check(false, "④ 场景声明的美术条目已被押住", "没拿到棋子")
	arena.queue_free()
	await get_tree().process_frame


## ⑤ 离场必须放开引用：一张招式图集 100–200MB 显存，押着不放会把显存吃穿
func _check_release_on_exit() -> void:
	_plan(2)
	var arena: Node = await _arena_quick(7)
	var st = arena.get("_state")
	await _deploy_all(arena, st)
	var waited := 0
	while SkinWarm.is_busy() and waited < 400:
		await get_tree().process_frame
		waited += 1
	var id := String(st.cards[0]["boss_id"])
	var p := MatchAdapter.scene_path_for(id)
	_check(SkinWarm.is_ready(p), "⑤ 离场前场景是押着的", p)
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not SkinWarm.is_ready(p), "⑤ 离开对局 ⇒ 押住的资源放开（显存还给系统）", p)


func _first_boss_with_skin(arena: Node) -> Node:
	var pc: Node = arena.get("_pieces")
	for h in pc.get_children():
		if h.get_child_count() <= 0:
			continue
		var n: Node = h.get_child(0)
		if n.get_node_or_null("Visual/Skin") != null:
			return n
	return null


## 等若干帧，并且让预载继续 poll（对局没结束，tick 自己会 poll；这里只是给时间）
func _settle_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
