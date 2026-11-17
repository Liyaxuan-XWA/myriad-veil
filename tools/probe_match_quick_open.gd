extends Node
## 快速模式开局预摆（票 003）
##
## 守的是"对方已经摆好 + 玩家跳过锁定 + 布阵不交替"这三条日程差异，
## 以及最要紧的一条**反向判据**：关掉开关以后，普通模式的路径必须
## 一个字节都没被碰过。只验快速模式能跑通是守不住的 ——
## 普通模式被顺手改坏时它照样全绿。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_open.tscn -- --no-save

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
	print("\n########## 快速模式开局预摆 · 票 003 ##########")
	_check_ai_preplaced()
	_check_player_skips_lock()
	_check_player_all_face_up()
	_check_deploy_does_not_alternate()
	_check_waits_for_start_button()
	_check_normal_path_untouched()
	await _check_arena_end_to_end()
	_finish()


## 造一个已经 quick_open 好的状态：对方 6 张当场建好摆好，玩家还没选牌。
func _opened(level: int) -> MatchState:
	var st := MatchState.new()
	var deck: Array = MatchLevelDeck.deck_for(level)
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		if pool.size() < MatchDB.DECK_SIZE:
			pool.append(String(id))
	st.start([pool, deck], 999, 0)
	st.quick_open(1, deck, MatchQuickSetup.layout_for(level))
	return st


func _ids_of(st: MatchState, team: int) -> Array:
	var out: Array = []
	for i in st.team_cards(team):
		out.append(String((st.cards[i] as Dictionary)["boss_id"]))
	return out


func _cells_of(st: MatchState, team: int) -> Dictionary:
	var out := {}
	for i in st.team_cards(team):
		var c: Dictionary = st.cards[i]
		if bool(c["deployed"]):
			out[String(c["boss_id"])] = c["cell"]
	return out


## ① 开局即见对方 6 张已落位，且格子逐张等于 layout_for(关卡号)。
## 这条是 ADR-0004 同源约束在**对局侧**的落点：拓印画的那份必须就是这里摆的那份。
func _check_ai_preplaced() -> void:
	var lv := 7
	var st := _opened(lv)
	var layout: Array = MatchQuickSetup.layout_for(lv)
	var want := {}
	for x in layout:
		want[String((x as Dictionary)["boss_id"])] = (x as Dictionary)["cell"]
	var got := _cells_of(st, 1)
	var bad: Array = []
	if got.size() != MatchDB.DECK_SIZE:
		bad.append("对方只摆了 %d 张" % got.size())
	for k in want:
		if not got.has(k):
			bad.append("缺 %s" % k)
		elif Vector2i(got[k]) != Vector2i(want[k]):
			bad.append("%s 摆错格 %s≠%s" % [k, str(got[k]), str(want[k])])
	_check(bad.is_empty(), "① 对方 6 张开局即落位，格子 == layout_for", str(bad))
	_check(_ids_of(st, 1).size() == MatchDB.DECK_SIZE, "① 对方就是本关那 6 只",
			str(_ids_of(st, 1)))


## ② 玩家提交卡组后**直接进布阵**，中间不许出现 LOCK。
func _check_player_skips_lock() -> void:
	var st := _opened(9)
	_check(st.phase == MatchState.Phase.PICK, "② 前置：还在选牌", str(st.phase))
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		if pool.size() < MatchDB.DECK_SIZE:
			pool.append(String(id))
	st.apply_command({"t": "pick", "team": 0, "ids": pool})
	_check(st.phase == MatchState.Phase.DEPLOY, "② 玩家交完牌直接进布阵（没有 LOCK）",
			str(st.phase))
	_check(st.deploy_turn == 0, "② 布阵轮到玩家", str(st.deploy_turn))


## ③ 玩家 6 张全正面（快速模式跳过锁定 ⇒ 没有反面）。
## 对方仍必须恰好 3 正 3 反 —— 只改玩家那一侧。
func _check_player_all_face_up() -> void:
	var st := _opened(11)
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		if pool.size() < MatchDB.DECK_SIZE:
			pool.append(String(id))
	st.apply_command({"t": "pick", "team": 0, "ids": pool})
	var ups := 0
	for i in st.team_cards(0):
		if bool((st.cards[i] as Dictionary)["face_up"]):
			ups += 1
	_check(ups == MatchDB.DECK_SIZE, "③ 玩家 6 张全正面", "%d 正" % ups)
	var ai_ups := 0
	for i in st.team_cards(1):
		if bool((st.cards[i] as Dictionary)["face_up"]):
			ai_ups += 1
	_check(ai_ups == 3, "③ 对方仍是 3 正 3 反", "%d 正" % ai_ups)


## ④ 玩家连续落子时 `deploy_turn` 不翻转 —— 对方已经摆完了，没人和你交替。
## 这条要是漂了，表现就是"放一张之后突然要等对方放"，而对方根本不会再放。
func _check_deploy_does_not_alternate() -> void:
	var st := _opened(13)
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		if pool.size() < MatchDB.DECK_SIZE:
			pool.append(String(id))
	st.apply_command({"t": "pick", "team": 0, "ids": pool})
	var placed := 0
	for n in MatchDB.DECK_SIZE * 2:      # 故意多试几轮：交替的话第 2 张就放不下去
		var legal: Array = st.legal_deploy(0)
		if legal.is_empty():
			break
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		var ok := st.apply_command({"t": "deploy", "team": 0,
				"card": int(legal[0]), "cell": cells[0]})
		if ok:
			placed += 1
	_check(placed == MatchDB.DECK_SIZE, "④ 玩家能连摆满 6 张（没有交替）", "%d 张" % placed)
	_check(st.deploy_turn == 0, "④ 摆完 deploy_turn 仍归玩家", str(st.deploy_turn))


## ⑤ 12 张摆满**不自动开打**：快速模式要等玩家点「开战」。
func _check_waits_for_start_button() -> void:
	var st := _opened(15)
	var pool: Array = []
	for id in MatchDB.CARD_POOL:
		if pool.size() < MatchDB.DECK_SIZE:
			pool.append(String(id))
	st.apply_command({"t": "pick", "team": 0, "ids": pool})
	for n in MatchDB.DECK_SIZE:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		st.apply_command({"t": "deploy", "team": 0, "card": int(legal[0]), "cell": cells[0]})
	_check(st.deployed_count() == 12, "⑤ 前置：场上 12 张都摆好了",
			str(st.deployed_count()))
	_check(st.phase == MatchState.Phase.DEPLOY, "⑤ 摆满不自动开打（还在布阵等按钮）",
			str(st.phase))
	_check(st.quick_awaiting_start(), "⑤ quick_awaiting_start() 报真", str(st.phase))


## ⑥ **反向判据**（本票最重要的一条）。
## 只验快速模式能跑通是守不住的：普通模式被顺手改坏时它照样全绿。
## 这里把普通模式那条路完整走一遍，逐段核对阶段序列、交替节奏和"摆满自动开打"。
func _check_normal_path_untouched() -> void:
	var st := MatchState.new()
	var p0: Array = []
	var p1: Array = []
	var ids: Array = MatchDB.CARD_POOL
	for i in MatchDB.DECK_SIZE:
		p0.append(String(ids[i]))
		p1.append(String(ids[MatchDB.DECK_SIZE + i]))
	st.start([p0, p1], 4242, 0)
	var seq: Array[String] = [MatchState.PHASE_NAME[st.phase]]
	st.apply_command({"t": "pick", "team": 0, "ids": p0})
	seq.append(MatchState.PHASE_NAME[st.phase])
	st.apply_command({"t": "pick", "team": 1, "ids": p1})
	seq.append(MatchState.PHASE_NAME[st.phase])
	# 普通模式：两边都交完 ⇒ 必然进 LOCK（快速模式才会跳过）
	_check(st.phase == MatchState.Phase.LOCK, "⑥ 普通模式仍然要过 LOCK", str(st.phase))
	var l0: Dictionary = MatchPolicy.decide_lock(st, 0)
	var l1: Dictionary = MatchPolicy.decide_lock(st, 1)
	st.apply_command({"t": "lock", "team": 0, "down": int(l0["down"]), "up": int(l0["up"])})
	st.apply_command({"t": "lock", "team": 1, "down": int(l1["down"]), "up": int(l1["up"])})
	_check(st.phase == MatchState.Phase.DEPLOY, "⑥ 两边锁完 ⇒ 布阵", str(st.phase))
	_check(not st.quick, "⑥ 没调 quick_open ⇒ quick 标记仍是 false", str(st.quick))

	# 交替节奏：每落一子换一边，且 12 子落满自动开打
	var flipped := 0
	for n in MatchDB.DECK_SIZE * MatchDB.TEAM_COUNT:
		var t: int = st.deploy_turn
		var legal: Array = st.legal_deploy(t)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		if legal.is_empty() or cells.is_empty():
			break
		st.apply_command({"t": "deploy", "team": t, "card": int(legal[0]), "cell": cells[0]})
		if st.deploy_turn != t:
			flipped += 1
	_check(flipped == MatchDB.DECK_SIZE * MatchDB.TEAM_COUNT,
			"⑥ 普通模式布阵仍逐子交替", "%d/12 次翻转" % flipped)
	_check(st.phase == MatchState.Phase.BATTLE, "⑥ 普通模式摆满 12 张自动开打", str(st.phase))
	_check(seq[0] == "pick" and seq[1] == "pick" and seq[2] == "lock",
			"⑥ 阶段序列 pick→pick→lock 没被插队", str(seq))


## ⑦ 端到端：真开一局快速模式，验证渲染层确实收到了对方那 6 个子。
## 前面 ①〜⑥ 全是规则层，规则层绿了不代表场上看得见 ——
## quick_open 发的是普通 deploy 事件，这条就是守住"渲染层不用改也能长出来"。
func _check_arena_end_to_end() -> void:
	var lv := 5
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = lv - 1
	GameState.match_context = {"level": lv}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 20:
		await get_tree().process_frame
	var st = arena.get("_state")
	_check(bool(st.quick), "⑦ 真对局拿到了 quick 标记", str(st.quick))
	_check(st.phase == MatchState.Phase.PICK, "⑦ 开局停在选牌（对方已就位）", str(st.phase))

	var want := {}
	for x in MatchQuickSetup.layout_for(lv):
		want[String((x as Dictionary)["boss_id"])] = (x as Dictionary)["cell"]
	var bad: Array = []
	for i in st.team_cards(1):
		var c: Dictionary = st.cards[i]
		var bid := String(c["boss_id"])
		if not bool(c["deployed"]):
			bad.append("%s 没落位" % bid)
		elif Vector2i(c["cell"]) != Vector2i(want.get(bid, Vector2i(-9, -9))):
			bad.append("%s 格子不对" % bid)
	_check(bad.is_empty(), "⑦ 对方 6 张在真对局里已落位且 == layout_for", str(bad))

	# 渲染侧：Tokens 容器里应该有对方那 6 张牌
	var tokens: Node2D = arena.get("_tokens")
	var tok_cards := {}
	for t in tokens.get_children():
		if t is MatchCardToken:
			tok_cards[int(t.get("card_index"))] = true
	_check(tok_cards.size() >= MatchDB.DECK_SIZE,
			"⑦ 渲染层收到了对方的牌（deploy 事件同款，没改渲染代码）",
			"%d 张" % tok_cards.size())

	arena.queue_free()
	await get_tree().process_frame
	CharacterData.match_quick_mode = false
	GameState.match_context = {}


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
