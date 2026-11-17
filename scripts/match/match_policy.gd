class_name MatchPolicy
extends RefCounted
## 对局决策函数 —— AI 思考与「选牌窗口超时自动代选」**共用这一份**。
##
## 这是 2026-11-02 访谈里定的架构约束：超时不是"随便选一个"，而是
## "你没在时限内调用这个函数，系统替你调用了"。所以只可能有一套逻辑，
## 写两套迟早漂成「AI 比玩家聪明」或者「超时选出的牌 AI 永远不会选」。
##
## 全部只读 `MatchState` + 用 `state.rng`（吃本局种子），
## 因此同样的初始局面必然算出同样的决策 —— 以后接服务器时这是能重放的前提。

# ===================== 选牌阶段 =====================

## 从卡池里挑 6 张。卡池不足 6 张的补发已经由 `MatchDB.fill_pool` 在开局前做完
## （用户 11-02 定：随机补满，不是按固定顺序发凡界那几只），
## 所以这里只负责"从合法池里选"，不再关心凑数。
static func decide_deck(pool: Array) -> Array:
	var out: Array = []
	for id in pool:
		if out.size() >= MatchDB.DECK_SIZE:
			break
		out.append(String(id))
	return out


# ===================== 锁定阶段 =====================

## 1 张锁反面、1 张锁正面。
## 口径：最强的那张锁正面（反正对手迟早要知道），最弱的锁反面（留到最后开盲盒）。
static func decide_lock(st: MatchState, team: int) -> Dictionary:
	var mine := st.team_cards(team)
	if mine.is_empty():
		return {}
	return {"down": _argmin_dps(st, mine), "up": _argmax_dps(st, mine)}


# ===================== 布阵阶段 =====================

## 随机挑一张合法卡 + 一个空格。布阵是明着轮流放，没有隐藏信息，
## 模拟里不需要为此发明策略；真 AI 要变聪明就在这一处换掉即可。
## ⚠ 抽取顺序是"先卡后格"，不能调：本局种子驱动的播种已经把这个顺序
##   写进了所有校准数据（probe_match_balance / calibrate_match_duel），
##   交换两次 randi_range 的先后 = 重掷所有关卡的布局。
static func decide_deploy(st: MatchState, team: int, rng: RandomNumberGenerator) -> Dictionary:
	var legal := st.legal_deploy(team)
	if legal.is_empty():
		return {}
	var card: int = legal[rng.randi_range(0, legal.size() - 1)]
	var cell := random_free_cell(st.occupied_cells(), rng)
	if cell == Vector2i(-1, -1):
		return {}
	return {"card": card, "cell": cell}


## 从"还没被占的格子"里随机挑一个。decide_deploy 与快速布局共用（票 002）。
static func random_free_cell(occupied: Array, rng: RandomNumberGenerator) -> Vector2i:
	var cells := MatchState.free_cells(occupied)
	if cells.is_empty():
		return Vector2i(-1, -1)
	return cells[rng.randi_range(0, cells.size() - 1)]


# ===================== 正反面分配（票 002 抽出来共享）=====================

## 一队牌的正反面分配。`down_pos` / `up_pos` 是**队内下标**，给 -1 就按
## `decide_lock` 的口径自动取：最强锁正面（反正对手迟早要知道）、最弱锁反面（留到最后开盲盒）。
## 其余几张洗牌后，前 `LOCK_OWN_DOWN` 张反、其余正。
##
## ⚠ `MatchState._cmd_lock` 和 `MatchQuickSetup.layout_for` 必须共用它 ——
##   长卷拓印画的就是这个结果，两处各写一遍一定会漂，而漂一次就是骗玩家。
static func face_flags(dps: Array, rng: RandomNumberGenerator,
		down_pos: int = -1, up_pos: int = -1) -> Array:
	var n := dps.size()
	var out: Array = []
	for i in n:
		out.append(true)
	if n == 0:
		return out
	var up_i := up_pos
	var down_i := down_pos
	if up_i < 0:
		up_i = _argmax_arr(dps)
	if down_i < 0:
		down_i = _argmin_arr(dps)
	# 面板完全相同的两只（同种 BOSS 进同一副牌）会让最强==最弱，
	# 此时把反面挪到下一张，不能让一张牌同时正又反。
	if down_i == up_i and n > 1:
		down_i = (up_i + 1) % n
	out[up_i] = true
	out[down_i] = false
	var rest: Array = []
	for i in n:
		if i != up_i and i != down_i:
			rest.append(i)
	fisher_yates(rest, rng)
	var flip_from := MatchDB.LOCK_OWN_DOWN + MatchDB.LOCK_OWN_UP
	for k in rest.size():
		out[rest[k]] = k >= flip_from
	return out


## Fisher–Yates。**只吃传进来的 rng**：`Array.shuffle()` 走引擎全局随机，
## 两个客户端拿到同一串命令会洗出不同正反面（见文件头"联机接缝"）。
static func fisher_yates(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _argmax_arr(dps: Array) -> int:
	var best := 0
	var bv := -INF
	for i in dps.size():
		var v := float(dps[i])
		if v > bv:
			bv = v
			best = i
	return best


static func _argmin_arr(dps: Array) -> int:
	var best := 0
	var bv := INF
	for i in dps.size():
		var v := float(dps[i])
		if v < bv:
			bv = v
			best = i
	return best


# ===================== 对战阶段 =====================

## 本轮该激活哪张卡。返回 -1 表示没有合法手。
static func decide(st: MatchState, team: int) -> int:
	var legal := st.legal_activate(team)
	if legal.is_empty():
		return -1
	if st.is_own_round():
		# 己方回合：把最能打的先放出去。12 张反正全都要翻，
		# 「藏着」没有长期收益，早出场早压伤害。
		return _argmax_dps(st, legal)
	# 敌方回合：优先开**已知**（正面朝上）里最弱的那张 —— 逼对手把弱牌提前进场，
	# 同时不去赌暗牌。全是暗牌时才随机开一张。
	var known: Array = []
	for i in legal:
		if bool(st.cards[i]["face_up"]):
			known.append(i)
	if not known.is_empty():
		return _argmin_dps(st, known)
	return legal[st.rng.randi_range(0, legal.size() - 1)]


static func _argmax_dps(st: MatchState, idxs: Array) -> int:
	var best := -1
	var bv := -INF
	for i in idxs:
		var v := float(st.cards[i]["dps"])
		if v > bv:
			bv = v
			best = i
	return best


static func _argmin_dps(st: MatchState, idxs: Array) -> int:
	var best := -1
	var bv := INF
	for i in idxs:
		var v := float(st.cards[i]["dps"])
		if v < bv:
			bv = v
			best = i
	return best
