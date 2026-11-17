class_name MatchState
extends RefCounted
## 卡片召唤自走棋 · 规则状态机（纯逻辑：不碰节点、不读输入、不渲染）
##
## 全部推进都走 `apply_command(cmd)`，命令是**普通字典**：
## 这是给以后 SDK 联机留的唯一接缝 —— 服务器只要把同一串命令按序广播，
## 各端就能算出完全一致的局面；本地玩家输入和 AI 决策也都只是往这个口子里塞命令。
## 任何"当前帧读输入""直接改字段"的写法都会让这条接缝失效，禁止。

enum Phase { PICK, LOCK, DEPLOY, BATTLE, FINAL, OVER }

var phase: int = Phase.PICK
var rng := RandomNumberGenerator.new()
var cards: Array = []              ## 12 张卡，字段见 _make_card
var round_index := 0               ## BATTLE 第几轮，0..5
var pending: Array = [-1, -1]      ## 每队本轮已提交的卡下标，-1 = 还没选
var timer := 0.0                   ## 当前窗口剩余秒数
var final_elapsed := 0.0           ## FINAL 阶段已经打了多少秒
var deploy_turn := 0               ## 布阵阶段该谁放
var first_team := 0                ## 先手队（上一局败者）
var winner := -1                   ## -1 = 未分；0/1 = 队伍；2 = 平
var end_reason := ""
var events: Array = []             ## 本帧产生的事件，渲染层消费后清空
var combat := MatchCombat.new()
## 每队的可用卡池（选牌阶段的合法手）。联机时这是"该队能看到哪些牌"的权威来源。
var pools: Array = [[], []]
## 快速模式开关（票 003 / ADR-0003）。**默认 false ⇒ 下面三个分叉点一个都不走**。
## 它不是"另一种玩法"的新状态机：阶段枚举、事件字典、终局判定全都共用，
## 只是开局日程不同 —— 对方一次摆完、玩家跳过锁定、摆完等「开战」。
var quick := false
var _quick_ai := 1                  ## 快速模式里被预摆的那一队
var _quick_ready := false           ## quick_open 已经跑过了

const PHASE_NAME := {
	Phase.PICK: "pick", Phase.LOCK: "lock", Phase.DEPLOY: "deploy",
	Phase.BATTLE: "battle", Phase.FINAL: "final", Phase.OVER: "over",
}
const WIN_DRAW := 2


# ===================== 开局 =====================

## pools[team] = 该队可用卡池（已解锁 boss_id 数组，或补发后的完整 6 张）
func start(pools_: Array, seed: int, opening_team: int = 0) -> void:
	rng.seed = seed
	first_team = opening_team
	phase = Phase.PICK
	cards.clear()
	round_index = 0
	deploy_turn = first_team
	winner = -1
	end_reason = ""
	final_elapsed = 0.0
	_fighting = false
	events = []
	_picked = [[], []]
	_locked = [false, false]
	pools = [[], []]
	for t in pools_.size():
		pools[t] = (pools_[t] as Array).duplicate()
	_clear_pending()
	_emit({"t": "phase", "phase": "pick"})


## 该队选牌阶段的合法手：卡池里还没被自己选走的。
func legal_pool(team: int) -> Array:
	if team < 0 or team >= pools.size():
		return []
	return pools[team]


func _make_card(boss_id: String, team: int) -> Dictionary:
	var st := MatchDB.piece_stats(boss_id)
	return {
		"boss_id": boss_id, "team": team,
		"face_up": false,        # 锁定阶段决定
		"deployed": false, "cell": Vector2i(-1, -1),
		"activated": false, "spawned": false, "alive": false,
		"hp": float(st["hp"]), "hp_max": float(st["hp"]), "dps": float(st["dps"]),
		"pos": Vector2.ZERO,
	}


# ===================== 合法手（控制器与超时自动代选共用）=====================

func team_cards(team: int) -> Array:
	var out: Array = []
	for i in cards.size():
		if int(cards[i]["team"]) == team:
			out.append(i)
	return out


## 已落子、还没激活的卡 —— 对战阶段的候选。
func _unactivated(team: int) -> Array:
	var out: Array = []
	for i in team_cards(team):
		if bool(cards[i]["deployed"]) and not bool(cards[i]["activated"]):
			out.append(i)
	return out


## 还没落子的卡 —— 布阵阶段的候选。
## ⚠ 别和上面那个合并成一个函数加参数：两个条件恰好相反
##   （一个要 deployed、一个要 not deployed），混用会让布阵合法手恒为空，
##   整局卡在 DEPLOY 出不来 —— 千局模拟第一次跑就抓到这个。
func _not_deployed(team: int) -> Array:
	var out: Array = []
	for i in team_cards(team):
		if not bool(cards[i]["deployed"]):
			out.append(i)
	return out


## 本轮该队能选哪些卡。奇偶决定选己方还是对方：
## 偶数轮（1/3/5）选**己方**、奇数轮（2/4/6）选**对方**。
## 两边候选集天然不相交，所以永远不可能"双方同时选中同一张牌"。
func legal_activate(team: int) -> Array:
	if phase != Phase.BATTLE:
		return []
	var own := (round_index % 2) == 0
	return _unactivated(team if own else 1 - team)


func legal_deploy(team: int) -> Array:
	if phase != Phase.DEPLOY or team != deploy_turn:
		return []
	return _not_deployed(team)


## 空格列表。**static**：`MatchPolicy.random_free_cell` 和快速布局都要用它，
## 而那边手上没有状态实例 —— 不 static 就会逼出第二份"挑空格"的代码。
static func free_cells(occupied: Array) -> Array:
	var out: Array = []
	for y in MatchDB.BOARD_ROWS:
		for x in MatchDB.BOARD_COLS:
			var c := Vector2i(x, y)
			if not occupied.has(c):
				out.append(c)
	return out


func occupied_cells() -> Array:
	var out: Array = []
	for c in cards:
		if bool(c["deployed"]):
			out.append(c["cell"])
	return out


func is_own_round() -> bool:
	return (round_index % 2) == 0


# ===================== 命令入口 =====================

## 唯一推进口。cmd.t ∈ pick / lock / deploy / activate
func apply_command(cmd: Dictionary) -> bool:
	match String(cmd.get("t", "")):
		"pick":
			return _cmd_pick(int(cmd.get("team", -1)), cmd.get("ids", []))
		"lock":
			return _cmd_lock(int(cmd.get("team", -1)), int(cmd.get("down", -1)),
					int(cmd.get("up", -1)))
		"deploy":
			return _cmd_deploy(int(cmd.get("team", -1)), int(cmd.get("card", -1)),
					cmd.get("cell", Vector2i(-1, -1)))
		"activate":
			return _cmd_activate(int(cmd.get("team", -1)), int(cmd.get("card", -1)))
	return false


var _picked: Array = [[], []]
var _locked: Array = [false, false]


func _cmd_pick(team: int, ids: Array) -> bool:
	if phase != Phase.PICK or team < 0 or team >= MatchDB.TEAM_COUNT:
		return false
	if ids.size() != MatchDB.DECK_SIZE or _picked[team].size() > 0:
		return false
	# 必须是**该队卡池里**的牌：只查 CARD_POOL 的话，一个越权命令就能选出对手才有的卡
	var pool := legal_pool(team)
	for id in ids:
		if not pool.has(String(id)):
			return false
	_picked[team] = ids.duplicate()
	if quick and team != _quick_ai:
		_quick_after_player_pick(team)          # 分叉点①：跳过 LOCK
		return true
	if _picked[0].size() == MatchDB.DECK_SIZE and _picked[1].size() == MatchDB.DECK_SIZE:
		_build_cards()
		phase = Phase.LOCK
		_emit({"t": "phase", "phase": "lock"})
	return true


func _build_cards() -> void:
	cards.clear()
	for team in MatchDB.TEAM_COUNT:
		for id in _picked[team]:
			cards.append(_make_card(String(id), team))


# ===================== 快速模式（票 003）=====================
##
## 三个分叉点全部封在这下面，普通模式的路径一行没改：
##   ① _cmd_pick 末尾：玩家交完牌直接进布阵，不进 LOCK
##   ② _cmd_deploy 末尾：不翻转 deploy_turn（对方已经摆完了，没人和你交替）、
##      摆满 12 张也不自动开打
##   ③ quick_start_battle()：「开战」一次激活 12 只，直接进终局

## 开局把对方 6 张当场建好、定好正反面、摆好。
## ⚠ 格子与朝向**必须**来自 `MatchQuickSetup.layout_for(level)` —— 那是长卷拓印
##   画的同一份数据。这里自己算一遍就会漂，而玩家是照着卷来针对的。
## 事件按普通模式同款 `deploy` 发，渲染层因此一行都不用改。
func quick_open(ai_team: int, ai_ids: Array, ai_layout: Array) -> void:
	quick = true
	_quick_ai = ai_team
	_picked[ai_team] = ai_ids.duplicate()
	for x in ai_layout:
		var d: Dictionary = x
		var c := _make_card(String(d["boss_id"]), ai_team)
		c["face_up"] = bool(d["face_up"])
		c["deployed"] = true
		c["cell"] = d["cell"]
		c["pos"] = MatchDB.cell_to_pos(d["cell"])
		var idx := cards.size()
		cards.append(c)
		_emit({"t": "deploy", "team": ai_team, "card": idx, "cell": d["cell"],
				"reveal": bool(d["face_up"])})
	_quick_ready = true


## 分叉点①：快速模式下玩家提交卡组后**不进 LOCK**，直接进布阵。
## 玩家 6 张全正面（2026-11-05 用户拍定：快速模式跳过锁定那一步，所以没有反面）。
func _quick_after_player_pick(team: int) -> void:
	for id in _picked[team]:
		var c := _make_card(String(id), team)
		c["face_up"] = true
		cards.append(c)
	phase = Phase.DEPLOY
	deploy_turn = team
	timer = 0.0
	_emit({"t": "phase", "phase": "deploy", "first": team})


## 快速模式：12 张都摆好了，正等玩家点「开战」。
func quick_awaiting_start() -> bool:
	return quick and phase == Phase.DEPLOY and deployed_count() >= MatchDB.DECK_SIZE * MatchDB.TEAM_COUNT


## 分叉点③：「开战」把六轮逐张翻牌压成一次 —— 12 只同时激活，直接进终局。
## ⚠ 激活口径必须和普通模式 `_resolve_round()` 逐字相同（activated/spawned/alive
##   三个字段 + 同款 spawn 事件），否则渲染层、血条染色、终局判定会悄悄分叉成两套。
##   这里改的只是"分几轮"，不是"怎么上场"。
func quick_start_battle() -> void:
	if not quick or phase != Phase.DEPLOY:
		return
	if not quick_awaiting_start():
		return
	for i in cards.size():
		var c: Dictionary = cards[i]
		if not bool(c["deployed"]):
			continue
		c["activated"] = true
		c["spawned"] = true
		c["alive"] = true
		_emit({"t": "spawn", "team": int(c["team"]), "card": i,
				"boss_id": String(c["boss_id"]), "cell": c["cell"]})
	_clear_pending()
	round_index = MatchDB.DECK_SIZE
	_begin_final()



func _cmd_lock(team: int, down: int, up: int) -> bool:
	if phase != Phase.LOCK or team < 0 or team >= MatchDB.TEAM_COUNT:
		return false
	if _locked[team] or down == up:
		return false
	var mine := team_cards(team)
	if not mine.has(down) or not mine.has(up):
		return false
	# 分配口径交给 MatchPolicy.face_flags —— 快速布局算的是同一个函数，
	# 长卷拓印才敢画"真实落位"（ADR-0004）。
	var dps: Array = []
	for i in mine:
		dps.append(float(cards[i]["dps"]))
	var flags := MatchPolicy.face_flags(dps, rng, mine.find(down), mine.find(up))
	for k in mine.size():
		cards[mine[k]]["face_up"] = bool(flags[k])
	_locked[team] = true
	if _locked[0] and _locked[1]:
		phase = Phase.DEPLOY
		deploy_turn = first_team
		timer = 0.0
		_emit({"t": "phase", "phase": "deploy", "first": first_team})
	return true


func _cmd_deploy(team: int, card: int, cell: Vector2i) -> bool:
	if phase != Phase.DEPLOY or team != deploy_turn:
		return false
	if not legal_deploy(team).has(card) or not MatchDB.in_board(cell):
		return false
	if occupied_cells().has(cell):
		return false
	var c: Dictionary = cards[card]
	c["deployed"] = true
	c["cell"] = cell
	c["pos"] = MatchDB.cell_to_pos(cell)
	_emit({"t": "deploy", "team": team, "card": card, "cell": cell,
			# 只有正面朝上的落子才把身份告诉对手
			"reveal": bool(c["face_up"])})
	if quick:
		# 分叉点②：对方开局就摆完了，没有人和玩家交替 ⇒ 轮次不翻转；
		# 摆满 12 张也**不自动开打**，等玩家点「开战」（票 004）。
		return true
	deploy_turn = 1 - deploy_turn
	if deployed_count() >= MatchDB.DECK_SIZE * MatchDB.TEAM_COUNT:
		_begin_battle()
	return true


func deployed_count() -> int:
	var n := 0
	for c in cards:
		if bool(c["deployed"]):
			n += 1
	return n


func _begin_battle() -> void:
	phase = Phase.BATTLE
	round_index = 0
	_clear_pending()
	timer = MatchDB.PICK_SECONDS
	_emit({"t": "phase", "phase": "battle"})
	_emit({"t": "round", "round": round_index, "own": is_own_round()})


func _cmd_activate(team: int, card: int) -> bool:
	if phase != Phase.BATTLE or team < 0 or team >= MatchDB.TEAM_COUNT:
		return false
	if pending[team] != -1 or not legal_activate(team).has(card):
		return false
	pending[team] = card
	if pending[0] != -1 and pending[1] != -1:
		_resolve_round_and_fight()
	return true


## 同时结算：两张卡一起进场，谁也不知道对方选了什么的悬念在这一刻才解开
func _resolve_round() -> void:
	for team in MatchDB.TEAM_COUNT:
		var idx: int = pending[team]
		if idx < 0:
			continue
		var c: Dictionary = cards[idx]
		c["activated"] = true
		c["spawned"] = true
		c["alive"] = true
		_emit({"t": "spawn", "team": int(c["team"]), "card": idx,
				"boss_id": String(c["boss_id"]), "cell": c["cell"]})
	_clear_pending()
	round_index += 1
	if round_index >= MatchDB.DECK_SIZE and _all_flipped():
		_begin_final()
	else:
		timer = MatchDB.PICK_SECONDS
		_emit({"t": "round", "round": round_index, "own": is_own_round()})


## 12 张是不是都翻完了（落了子但还没激活的还剩几张）。
## ⚠ 终局的门槛不能只看 `round_index`：轮次记的是"结算了几轮"，
##   一旦有哪轮只凑出一张合法手（代选循环曾经多走一格），轮次会跑在牌前面，
##   于是"没翻完就判负"——用户实机看到的「输了但还有一张牌没翻出来」就是这个。
##   现在两处进终局都要过这一关，轮次不够就再开窗口，直到真的翻完。
func _all_flipped() -> bool:
	return _unactivated(0).is_empty() and _unactivated(1).is_empty()


func _begin_final() -> void:
	phase = Phase.FINAL
	final_elapsed = 0.0
	timer = final_limit()
	_emit({"t": "phase", "phase": "final"})


# ===================== 推进 =====================

## delta 用**真实秒数**（选牌窗口是时停的，不能跟着 time_scale 跑）
func advance(delta: float) -> void:
	if phase == Phase.OVER:
		return
	match phase:
		Phase.DEPLOY:
			# 布阵是明着轮流放，没有隐藏信息，交给 UI 点选，不计时
			return
		Phase.BATTLE:
			_tick_battle(delta)
		Phase.FINAL:
			_tick_final(delta)
		_:
			return


## 选牌窗口内棋子时停；两边都提交之后才走那 8 秒
var _fighting := false


## 当前是不是在「8 秒战斗窗口」里（false = 在时停的选牌窗口）。渲染层用它决定
## 要不要播棋子动作、以及 HUD 显示倒计时还是显示「等待双方选择」。
func fighting() -> bool:
	return _fighting


## 这一段是不是**时停**的（渲染层据此把整棵战斗树 pause 掉，2026-11-03 用户 B 案）。
## 判据只看规则层状态，不含任何场景知识 —— 联机时对面也是同一个函数。
## · pick / lock / deploy：等人操作的这段时间，场面必须完全静止，
##   否则「先看清楚再决定」会变成「边掉血边选」。
## · battle 且还没开打：两边都在暗选，同样是停的。注意要覆盖**整段**窗口，
##   包括己方已提交、还在等对面那零点几秒 —— 用 `_awaiting_player()` 当判据的话，
##   玩家一点「确认」场面就先动起来，看着像时停没生效。
## · battle 开打后 / final / over：时间在走。over 特意不冻，
##   否则最后一只棋子的死亡淡出与结算动画一起被 pause，玩家看不到「谁倒下」。
func time_stopped() -> bool:
	if phase == Phase.BATTLE:
		return not _fighting
	return phase == Phase.PICK or phase == Phase.LOCK or phase == Phase.DEPLOY


func _tick_battle(delta: float) -> void:
	# ⚠ 镜像要放在最前面，两个分支都要走到：窗口里场面是**真停的**（MatchArena 把
	#   树 pause 了，见 time_stopped()），但「上一轮打完倒下几只」必须在进窗口的
	#   当帧就读回规则层 —— 原来只有 `_fighting` 分支调 combat.step()，于是窗口期间
	#   cards 里的 hp/alive 停在开打前，HUD 的存活数和玩家眼睛对不上，
	#   读成"一到选牌就时间暂停"（2026-11-03 实测 Engine.time_scale 全程 1.000，
	#   引擎根本没停，停的是这一层镜像）。
	combat.sync(cards)
	if _fighting:
		combat.step(cards, delta * time_scale())
		timer -= delta
		if timer <= 0.0:
			_fighting = false
			if round_index >= MatchDB.DECK_SIZE and _all_flipped():
				_begin_final()
			else:
				timer = MatchDB.PICK_SECONDS
				_emit({"t": "round", "round": round_index, "own": is_own_round()})
		return
	# 时停的选牌窗口
	timer -= delta
	if pending[0] != -1 and pending[1] != -1:
		return
	if timer > 0.0:
		return
	# 窗口到点还没选的，按预设策略代选 —— 与 AI 用同一个 decide()，
	# 所以「超时」和「让 AI 替你打」是同一件事，不存在两套逻辑。
	#
	# ⚠ 必须先把 round_index 记下来，并且**一旦发现这一轮已经结算完就立刻停手**：
	#   `_cmd_activate` 凑齐双方时会在内部当场结算（round_index += 1、pending 清空）。
	#   原来这个 for 循环不知道这件事，于是"替后提交的那一方选完 → 本轮结算 →
	#   循环继续走下一格 → 把牌塞进**新一轮**并留下 pending"，
	#   接着下面那条"只有一方有合法手"的分支把**新一轮**也单方面结算掉了。
	#   后果：六轮里有一轮只激活一张，12 张只翻出 11 张，
	#   剩那张永远扣着牌背、棋子也从没上场（2026-11-04 用户实机截图「我输了但还有一张牌没翻出来」）。
	#   触发条件很日常：一方先提交（AI 0.4 秒就交，人要想满 10 秒），另一方走超时代选。
	var round_before := round_index
	for team in MatchDB.TEAM_COUNT:
		if round_index != round_before or phase != Phase.BATTLE:
			break                 # 本轮已经结算过了，别再往新一轮里塞牌
		if int(pending[team]) == -1:
			var pick := MatchPolicy.decide(self, team)
			if pick >= 0:
				_cmd_activate(team, pick)
				_emit({"t": "auto_pick", "team": team, "card": pick})
	# ⚠ 不能用「pending 还是 -1」当"没人能动"的证据：上面那两次提交一旦凑齐双方，
	#   _cmd_activate 内部就结算并清空了 pending，照那个判据会把刚开局的一局误判成死局。
	if phase != Phase.BATTLE or round_index != round_before:
		return
	if int(pending[0]) != -1 or int(pending[1]) != -1:
		# 只有一方有合法手：让它单独进场推进，不能干等另一方（它已经没有牌可出了）
		_resolve_round_and_fight()
	elif legal_activate(0).is_empty() and legal_activate(1).is_empty():
		_end(WIN_DRAW, "no_legal_move")


func _resolve_round_and_fight() -> void:
	_resolve_round()
	if phase == Phase.BATTLE:
		_fighting = true
		timer = MatchDB.ROUND_SECONDS


func _tick_final(delta: float) -> void:
	combat.step(cards, delta * time_scale())
	final_elapsed += delta
	timer -= delta
	var a := MatchCombat.team_alive(cards, 0)
	var b := MatchCombat.team_alive(cards, 1)
	if not a and not b:
		_end(WIN_DRAW, "mutual_annihilation")
		return
	if not a:
		_end(1, "clear_field")
		return
	if not b:
		_end(0, "clear_field")
		return
	if timer <= 0.0:
		# 超时比剩余血量百分比之和，不比绝对值：面板上限不同就不公平
		var fa := MatchCombat.hp_fraction_sum(cards, 0)
		var fb := MatchCombat.hp_fraction_sum(cards, 1)
		if absf(fa - fb) < 0.001:
			_end(WIN_DRAW, "timeout_equal")
		elif fa > fb:
			_end(0, "timeout_hp")
		else:
			_end(1, "timeout_hp")


## 终局上限秒数：快速模式单独放宽（票 004）。普通模式取表里那个 120s，没动。
func final_limit() -> float:
	return MatchDB.QUICK_FINAL_LIMIT_SECONDS if quick else MatchDB.FINAL_LIMIT_SECONDS


## 加速起点：和 final_limit 成对取，保证两种模式都是"窗口后半段线性推到 2.0×"。
## 快速模式如果仍按 60s 起推，第 120 秒到第 240 秒会全程 2.0× 恒速 —— 加速从
## "收尾手段"变成"常态"，那就不是同一份预算了。
func accel_start() -> float:
	return MatchDB.QUICK_ACCEL_START_SECONDS if quick else MatchDB.ACCEL_START_SECONDS


## 对局时间流速：加速起点起线性推到窗口末尾的 2.0。
## 渲染层拿这个值去调 GameState.set_time_flow_base()。
func time_scale() -> float:
	if phase != Phase.FINAL:
		return 1.0
	var start := accel_start()
	if final_elapsed < start:
		return 1.0
	var span := final_limit() - start
	var k := clampf((final_elapsed - start) / maxf(span, 0.001), 0.0, 1.0)
	return 1.0 + k * (MatchDB.ACCEL_MAX_SCALE - 1.0)


func _end(team: int, reason: String) -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	winner = team
	end_reason = reason
	_emit({"t": "end", "winner": team, "reason": reason})


func _clear_pending() -> void:
	pending = [-1, -1]


func _emit(e: Dictionary) -> void:
	events.append(e)


func drain_events() -> Array:
	var out := events
	events = []
	return out


## Fisher–Yates。⚠ 不能用 Array.shuffle()：它走引擎全局随机数，
## 不吃本局种子，两个客户端拿到同样的命令串也会洗出不同的正反面。
## 实现挪到了 MatchPolicy.fisher_yates —— 快速布局要用同一个洗牌，
## 留两份就会在"改一处忘改另一处"时把长卷和开局洗成两副牌。
func _shuffle(arr: Array) -> void:
	MatchPolicy.fisher_yates(arr, rng)
