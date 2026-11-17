extends Node
## 诊断：开局前几轮到底谁激活了谁。
## 每轮把「双方各提交了哪张卡、那张卡属于哪一队、这一轮进场了哪几只」打出来。
## 用法：godot --headless --path . res://tools/diag_match_rounds.tscn -- --no-save

var _log: Array = []


func _ready() -> void:
	var st := MatchState.new()
	st.combat = MatchCombat.new()
	var pool: Array = []
	for i in MatchDB.CARD_POOL.size():
		pool.append(String(MatchDB.CARD_POOL[i]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261103
	st.start([pool.slice(0, 6), pool.slice(6, 12)], rng.randi(), 0)
	st.apply_command({"t": "pick", "team": 1, "ids": MatchPolicy.decide_deck(st.legal_pool(1))})
	st.apply_command({"t": "pick", "team": 0, "ids": MatchPolicy.decide_deck(st.legal_pool(0))})
	# 锁定要照规则层的口径来：卡下标是全局 0..11，队 1 的是 6..11，不能手写 2/3
	for t in [0, 1]:
		var lk: Dictionary = MatchPolicy.decide_lock(st, t)
		if not lk.is_empty():
			st.apply_command({"t": "lock", "team": t, "down": int(lk["down"]), "up": int(lk["up"])})
	# 布阵：双方交替把 12 张全放下去
	for guard in 200:
		if st.phase != MatchState.Phase.DEPLOY:
			break
		for t in [0, 1]:
			var legal: Array = st.legal_deploy(t)
			if legal.is_empty():
				continue
			var mv: Dictionary = MatchPolicy.decide_deploy(st, t, st.rng)
			if mv.is_empty():
				continue
			st.apply_command({"t": "deploy", "team": t, "card": int(mv["card"]), "cell": mv["cell"]})
	print("DIAG 布阵后 phase=", String(MatchState.PHASE_NAME.get(int(st.phase), "?")),
			" round=", st.round_index)

	# 对战：完全照对局场景的提交节奏 —— 每轮双方各提交一次
	for r in 12:
		if st.phase != MatchState.Phase.BATTLE:
			break
		var own := st.is_own_round()
		var row := "round %d (%s): " % [st.round_index, "己方" if own else "对方"]
		var submits: Array = []
		for t in [0, 1]:
			var legal: Array = st.legal_activate(t)
			var pick := -1
			for c in legal:
				pick = int(c)
				break
			submits.append(pick)
			row += " 队%d候选%d张选%d" % [t, legal.size(), pick]
		# 谁先交、谁后交都试一遍，看结算是否只进两只
		st.apply_command({"t": "activate", "team": 0, "card": submits[0]})
		var mid := _spawn_line(st)
		st.apply_command({"t": "activate", "team": 1, "card": submits[1]})
		var owners: Array = []
		for e in st.drain_events():
			if String(e.get("t", "")) == "spawn":
				owners.append("%d队#%d" % [int(e["team"]), int(e["card"])])
		print(row, " → 进场 ", owners, "  (第一次提交后已进场:", mid, ")")
		# 打完这一轮
		var guard := 0
		while st.phase == MatchState.Phase.BATTLE and st.fighting() and guard < 400:
			guard += 1
			st.advance(0.5)
	print("DIAG 结束 phase=", String(MatchState.PHASE_NAME.get(int(st.phase), "?")),
			" winner=", st.winner, " reason=", st.end_reason)
	get_tree().quit(0)


## 只提交了一方时，规则层有没有提前把牌放出来
func _spawn_line(st) -> String:
	var out: Array = []
	for e in st.events:
		if String(e.get("t", "")) == "spawn":
			out.append(int(e["card"]))
	return str(out)
