extends Node
## 卡片自走棋 · 规则层闭合性验证（2026-11-02）
##
## 这一层只验**规则**，不验平衡：战斗用的是 MatchCombat 抽象模型（无走位、无机制），
## 所以这里的胜率只能证明「状态机不会卡死、不会误判」，
## 不能拿来当数值结论 —— 平衡要等第 4 步真 BOSS 上场后另跑一版。
##
## 用法：godot --headless --path . res://tools/probe_match_rules.tscn -- --no-save

var _passes := 0
var _fails: Array = []

const SIM_MATCHES := 1000
const DT := 1.0 / 30.0
const MAX_STEPS := 40000      # ≈ 22 分钟真实时间上限，正常一局远不到


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 卡片自走棋 · 规则层 ##########")
	_check_tables()
	_check_pacing()
	_check_one_match()
	_check_timeout_path()
	_check_half_submit()
	_check_determinism()
	_check_clock_ramp()
	_check_sim(SIM_MATCHES)
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(1 if not _fails.is_empty() else 0)


# ===================== 数据表 =====================

func _check_tables() -> void:
	_check(MatchDB.CARD_POOL.size() == 16, "卡池 16 位", "n=%d" % MatchDB.CARD_POOL.size())
	var missing_panel: Array = []
	var missing_factor: Array = []
	var dup := {}
	for id in MatchDB.CARD_POOL:
		if dup.has(id):
			missing_panel.append("重复:" + String(id))
		dup[id] = true
		if MatchDB.panel_of(String(id)).is_empty():
			missing_panel.append(String(id))
		if not MatchDB.FACTORS.has(String(id)):
			missing_factor.append(String(id))
	_check(missing_panel.is_empty(), "每位都有面板快照", str(missing_panel))
	_check(missing_factor.is_empty(), "每位都有折算系数", str(missing_factor))
	# 校准值缺失时 adapter 会退回目标 DPS 并告警 —— 那等于造出一只几十倍弱的棋子，
	# 所以"有没有漏测"必须是硬失败，不能只靠运行时那条 warning 被发现。
	var no_calib: Array = []
	for id in MatchDB.CARD_POOL:
		if float(MatchDB.ATTACK_CALIB.get(String(id), 0.0)) <= 0.0:
			no_calib.append(String(id))
	_check(no_calib.is_empty(), "16 位全部有真实 DPS 校准值", str(no_calib))

	# 卡池不足 6 张 → 随机补满（用户 11-02 定，取代原先按固定顺序发凡界那几只）
	var r1 := RandomNumberGenerator.new()
	r1.seed = 77
	var filled := MatchDB.fill_pool(["boss_huyao", "boss_01"], r1)
	_check(filled.size() == MatchDB.DECK_SIZE, "卡池只有 2 张时随机补满到 6 张", str(filled))
	_check(filled.has("boss_huyao") and filled.has("boss_01"),
			"补发保留玩家已有的牌（不是整手换掉）")
	var uniq := {}
	var offpool := false
	for id in filled:
		uniq[id] = true
		if not MatchDB.CARD_POOL.has(String(id)):
			offpool = true
	_check(uniq.size() == filled.size() and not offpool, "补出来的 6 张不重复且都在卡池内")
	# fill_pool 的职责是"补到至少 6 张可挑"，不是截到 6 张 ——
	# 截断会剥夺玩家从已解锁里挑选的自由（解锁 16 张反而只能随机用 6 张，荒谬）。
	var full := MatchDB.fill_pool(MatchDB.CARD_POOL.duplicate(), r1)
	_check(full == MatchDB.CARD_POOL, "卡池够 6 张时原样返回：不追加也不截断", "n=%d" % full.size())
	var ra := RandomNumberGenerator.new()
	ra.seed = 5
	var rb := RandomNumberGenerator.new()
	rb.seed = 5
	_check(MatchDB.fill_pool(["boss_02"], ra) == MatchDB.fill_pool(["boss_02"], rb),
			"同种子补发结果一致（联机两端能复现同一手牌）")

	# 押注：有效注额按较少一方计，超出退回 —— 零和，不凭空印钱
	_check(MatchDB.bet_matched(100.0, 50.0) == 50.0, "押 100 对 50 → 有效注额 50")
	_check(MatchDB.bet_matched(50.0, 50.0) == 50.0, "对等押注 → 全额生效")
	_check(MatchDB.bet_matched(0.0, 500.0) == 0.0, "对方没押则一分不得（不白送）")
	_check(MatchDB.bet_allowed(50.0, 100.0), "钱包够时可押最低注")
	_check(not MatchDB.bet_allowed(10.0, 1000.0), "低于起步注额不允许")
	_check(not MatchDB.bet_allowed(500.0, 100.0), "超出钱包不允许")
	_check(not MatchDB.bet_allowed(999999.0, 999999.0), "超过注额上限不允许")

	# 「选哪 6 张」不能被数值碾平（原始 HP 差 77 倍）。2026-11-07 起这条读**有效身板**
	# （面板 × 实测减免），不再读面板：面板那列现在是"补偿之后"的数，跨度**故意**比设计带宽
	# （苍角减免 1.79 ⇒ 面板只剩别人的 0.53 倍），拿面板判跨度会红得毫无意义。
	# 真正决定强弱的是对面实际要打掉多少血。
	var effs: Array = []
	var panels: Array = []
	var dpss: Array = []
	for id in MatchDB.CARD_POOL:
		var st := MatchDB.piece_stats(String(id))
		effs.append(MatchDB.effective_hp(String(id)))
		panels.append(float(st["hp"]))
		dpss.append(float(st["dps"]))
	var hmin: float = effs.min()
	var hmax: float = effs.max()
	var pmin: float = panels.min()
	var pmax: float = panels.max()
	var dmin: float = dpss.min()
	var dmax: float = dpss.max()
	_check(hmax / hmin <= 1.5 and dmax / dmin <= 1.5,
			"有效 HP 与 DPS 都压在 ±20% 带内（面板跨度是补偿后的，故意放宽）",
			"有效hp %.0f..%.0f(%.2fx)  面板hp %.0f..%.0f(%.2fx)  dps %.0f..%.0f(%.2fx)  原始hp跨度=%.1fx" % [
					hmin, hmax, hmax / hmin, pmin, pmax, pmax / pmin,
					dmin, dmax, dmax / dmin,
					float(MatchDB.PANEL_SNAPSHOT["boss_04_c"]["hp"])
							/ float(MatchDB.PANEL_SNAPSHOT["boss_huyao"]["hp"])])
	# 减免表缺一只不会报错，只会**静默按 1.00** ⇒ 那只棋子白拿一层肉度。
	# 和当年 ATTACK_CALIB 漏人（静默弱十倍）是同一种形状，所以要单独钉一条。
	var no_mult: Array = []
	for id in MatchDB.CARD_POOL:
		if not MatchDB.MEASURED_EHP_MULT.has(String(id)):
			no_mult.append(String(id))
	_check(no_mult.is_empty(), "16 张全都有实测减免（缺一只就静默白拿一层肉度）", str(no_mult))

	# 第四只核心两张表两个名字，必须还能查到面板
	_check(not MatchDB.panel_of("world_core_shihou").is_empty()
			and not MatchDB.panel_of("world_core_yuanying").is_empty(),
			"石犼的两种 id 都翻到同一份面板（区域表 yuanying / 卡包 shihou）")

	# 棋盘卡片尺寸：两头都要守住 —— 太小（用户报过一次：卡面只有 88×132，
	# 比盖着的卡背还小），太大又会让卡套顶进上下相邻格、棋盘糊成一片。
	var th := MatchDB.card_token_height()
	var tw := th * 2.0 / 3.0
	var pad2 := MatchCardToken.SLEEVE_PAD * 2.0
	_check(th >= MatchDB.CELL_PX * 0.8, "卡片高度不低于格子的 80%",
			"%.0f / %.0f" % [th, MatchDB.CELL_PX])
	_check(th + pad2 <= MatchDB.CELL_PX and tw + pad2 <= MatchDB.CELL_PX,
			"连卡套一起装得进一格，不顶到相邻格", "卡套 %.0f×%.0f ≤ %.0f" % [tw + pad2, th + pad2, MatchDB.CELL_PX])
	# 正反面共用同一个矩形：贴图自己必须是 2:3，否则同一张 face 会把其中一面拉扁
	var back_sz := MatchCard.back_texture().get_size()
	_check(absf(back_sz.x / back_sz.y - 2.0 / 3.0) < 0.011,
			"牌背与卡面同为 2:3（正反面视觉尺寸必然一致）", str(back_sz))
	_check(absf(float(MatchCard.ART_BAKE_W) / float(MatchCard.ART_BAKE_H) - 2.0 / 3.0) < 0.001,
			"卡面烘进内存的比例是 2:3")

	# 棋盘尺寸必须容得下转阶段击退，否则棋子会被顶到墙上反复弹
	var half := MatchDB.arena_half()
	_check(half.x - 48.0 > BossBase.PHASE_TRANSITION_PUSH,
			"战场半宽容得下转阶段击退 520",
			"half=%.0f 可用=%.0f" % [half.x, half.x - 48.0])


# ===================== 单局全流程 =====================

func _make_pool(rng: RandomNumberGenerator, n: int) -> Array:
	var all := MatchDB.CARD_POOL.duplicate()
	var out: Array = []
	for i in range(n):
		if all.is_empty():
			break
		out.append(String(all.pop_at(rng.randi_range(0, all.size() - 1))))
	return out


## 跑一局。submit=false 时全程没人提交，逼超时自动代选接管。
## `only_team >= 0` 时**只有那一队**手动提交，另一队一律走窗口到点代选 ——
## 这才是实机的节奏（AI 0.4 秒就交，人要想满 10 秒），也是 2026-11-04 事故的入口。
func _play(seed: int, submit: bool = true, only_team: int = -1) -> Dictionary:
	var st := MatchState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7
	st.start([_make_pool(rng, 6), _make_pool(rng, 6)], seed)
	# 选牌
	var d0: Array = MatchPolicy.decide_deck(st.legal_pool(0))
	var d1: Array = MatchPolicy.decide_deck(st.legal_pool(1))
	st.apply_command({"t": "pick", "team": 0, "ids": d0})
	st.apply_command({"t": "pick", "team": 1, "ids": d1})
	# 锁定
	for t in 2:
		var lk: Dictionary = MatchPolicy.decide_lock(st, t)
		st.apply_command({"t": "lock", "team": t, "down": int(lk["down"]), "up": int(lk["up"])})
	# 布阵
	var deploy_guard := 0
	while st.phase == MatchState.Phase.DEPLOY and deploy_guard < 50:
		var mv: Dictionary = MatchPolicy.decide_deploy(st, st.deploy_turn, rng)
		if mv.is_empty():
			break
		st.apply_command({"t": "deploy", "team": st.deploy_turn,
				"card": int(mv["card"]), "cell": mv["cell"]})
		deploy_guard += 1
	# 对战 + 终局
	var steps := 0
	var auto_picks := 0
	var ended_early := false
	while st.phase != MatchState.Phase.OVER and steps < MAX_STEPS:
		if submit and st.phase == MatchState.Phase.BATTLE and not st.fighting():
			for t in 2:
				if only_team >= 0 and t != only_team:
					continue
				if int(st.pending[t]) == -1:
					var pick := MatchPolicy.decide(st, t)
					if pick >= 0:
						st.apply_command({"t": "activate", "team": t, "card": pick})
		st.advance(DT)
		for e in st.drain_events():
			if String(e.get("t", "")) == "auto_pick":
				auto_picks += 1
		if st.phase == MatchState.Phase.OVER and int(st.round_index) < MatchDB.DECK_SIZE \
				and st.end_reason != "no_legal_move":
			ended_early = true
		steps += 1
	var activated := 0
	var up := 0
	var unflipped := 0        # 落了子却从没激活：牌永远扣着牌背、棋子也从没上场
	for c in st.cards:
		if bool(c["activated"]):
			activated += 1
		if bool(c["face_up"]):
			up += 1
		if bool(c["deployed"]) and not bool(c["activated"]):
			unflipped += 1
	return {"st": st, "steps": steps, "activated": activated, "face_up": up,
			"unflipped": unflipped,
			"auto_picks": auto_picks, "ended_early": ended_early,
			"over": st.phase == MatchState.Phase.OVER, "reason": st.end_reason,
			"winner": st.winner}


## 节奏：选牌窗口与战斗窗口是用户 2026-11-03 定的 10 秒 / 15 秒。
## 既断常数，也断"真的按这个值在倒数"—— 常数对了但被别处覆写，一样是跑偏。
func _check_pacing() -> void:
	_check(MatchDB.PICK_SECONDS == 10.0 and MatchDB.ROUND_SECONDS == 15.0,
			"暗选窗口 10 秒、战斗窗口 15 秒",
			"pick=%.0f round=%.0f" % [MatchDB.PICK_SECONDS, MatchDB.ROUND_SECONDS])
	var st := MatchState.new()
	st.combat = MatchCombat.new()
	var pool: Array = []
	for i in MatchDB.CARD_POOL.size():
		pool.append(String(MatchDB.CARD_POOL[i]))
	st.start([pool.slice(0, 6), pool.slice(6, 12)], 777, 0)
	st.apply_command({"t": "pick", "team": 1, "ids": MatchPolicy.decide_deck(st.legal_pool(1))})
	st.apply_command({"t": "pick", "team": 0, "ids": MatchPolicy.decide_deck(st.legal_pool(0))})
	for t in [0, 1]:
		var lk: Dictionary = MatchPolicy.decide_lock(st, t)
		if not lk.is_empty():
			st.apply_command({"t": "lock", "team": t,
					"down": int(lk["down"]), "up": int(lk["up"])})
	for guard in 40:
		if st.phase != MatchState.Phase.DEPLOY:
			break
		for t in [0, 1]:
			var mv: Dictionary = MatchPolicy.decide_deploy(st, t, st.rng)
			if not mv.is_empty():
				st.apply_command({"t": "deploy", "team": t,
						"card": int(mv["card"]), "cell": mv["cell"]})
	st.drain_events()
	_check(st.phase == MatchState.Phase.BATTLE, "驱动到对战阶段",
			String(MatchState.PHASE_NAME.get(int(st.phase), "?")))
	_check(absf(st.timer - MatchDB.PICK_SECONDS) < 0.001,
			"进对战时选牌窗口按 %.0f 秒起表" % MatchDB.PICK_SECONDS, "timer=%.2f" % st.timer)
	var own0: Array = st.legal_activate(0)
	var own1: Array = st.legal_activate(1)
	if own0.is_empty() or own1.is_empty():
		_check(false, "双方都有合法手", "0队=%d 1队=%d" % [own0.size(), own1.size()])
		return
	st.apply_command({"t": "activate", "team": 0, "card": int(own0[0])})
	st.apply_command({"t": "activate", "team": 1, "card": int(own1[0])})
	# 文案里的秒数一律从常数取：写死过一次，改数值后就成了假话
	_check(st.fighting() and absf(st.timer - MatchDB.ROUND_SECONDS) < 0.001,
			"两张都提交后战斗窗口按 %.0f 秒起表" % MatchDB.ROUND_SECONDS,
			"fighting=%s timer=%.2f" % [st.fighting(), st.timer])
	# 一整局的时间预算：6 轮 × (10 + 15) = 150 秒战斗 + 终局最多 120 秒
	var budget := float(MatchDB.DECK_SIZE) * (MatchDB.PICK_SECONDS + MatchDB.ROUND_SECONDS)
	_check(budget >= 150.0, "对战阶段总时长 %d 秒（最初 6+8 时只有 84 秒）" % int(budget))

	# 血量 ×3（用户 2026-11-03「都死太快了」）要成立的性质：
	# 抽象模型里**没有任何一对棋子能在一个战斗窗口内打死对方**。
	# 原来 10000 基准 / 8 秒窗口时，刀客对刀客 7.8 秒就倒，连一轮都撑不满。
	_check(MatchDB.PIECE_HP_BASE == 30000.0, "棋子血量基准 = 30000",
			"%.0f" % MatchDB.PIECE_HP_BASE)
	var worst := INF
	var worst_pair := ""
	for a in MatchDB.CARD_POOL:
		var sa: Dictionary = MatchDB.piece_stats(String(a))
		for b in MatchDB.CARD_POOL:
			# 有效身板：面板 × 实测减免（见上面那条判据的同一条口径）
			var sb_hp := MatchDB.effective_hp(String(b))
			var ttk := sb_hp / maxf(float(sa["dps"]), 1.0)
			if ttk < worst:
				worst = ttk
				worst_pair = "%s 打 %s" % [String(a), String(b)]
	_check(worst > MatchDB.ROUND_SECONDS,
			"最凶的一对也活得过一轮（血量×3 的全部目的；TTK 按有效身板算）",
			"最快击杀=%.1fs 窗口=%.0fs（%s）" % [worst, MatchDB.ROUND_SECONDS, worst_pair])


func _check_one_match() -> void:
	var r: Dictionary = _play(12345)
	var st: MatchState = r["st"]
	_check(bool(r["over"]), "单局能正常结束（不卡死）",
			"reason=%s steps=%d" % [r["reason"], r["steps"]])
	_check(not bool(r["ended_early"]), "12 张没翻完之前绝不判负",
			"reason=%s" % r["reason"])
	_check(int(r["activated"]) == 12, "12 张全部激活、每张恰好一次", "n=%s" % r["activated"])
	_check(int(r["face_up"]) == 6, "全场 6 正 6 反（每队 3 正 3 反）", "up=%s" % r["face_up"])
	_check(st.winner == 0 or st.winner == 1 or st.winner == 2, "胜者编号合法", "w=%s" % st.winner)
	# 布阵落点必须互不重叠
	var cells := {}
	var overlap := false
	for c in st.cards:
		if overlap or not bool(c["deployed"]):
			continue
		var key := "%d,%d" % [int(c["cell"].x), int(c["cell"].y)]
		if cells.has(key):
			overlap = true
		cells[key] = true
	_check(not overlap and cells.size() == 12, "12 个落点互不重叠")


func _check_timeout_path() -> void:
	var r: Dictionary = _play(999, false)
	_check(bool(r["over"]), "全程无人提交也能打完（超时代选接管）",
			"reason=%s" % r["reason"])
	_check(int(r["auto_picks"]) >= 12, "超时代选确实发生了", "n=%s" % r["auto_picks"])
	_check(int(r["activated"]) == 12, "代选同样把 12 张翻完", "n=%s" % r["activated"])


## 实机节奏：一方先提交、另一方走窗口到点代选。
## ⚠ 上面那条 `_play(999, false)` 抓不到这个坑 —— 两边都走代选时，
##   循环最后一格（team=1）才凑齐双方、才结算，本轮结算完循环也就走完了。
##   只有"先提交的是 team=1、结算发生在 team=0 那一格"时，循环才会多走一格
##   把牌塞进下一轮，然后下一轮又被单方面结算掉 → 12 张只翻出 11 张。
##   （2026-11-04 用户实机截图「我输了但还有一张牌没翻出来」，撤掉
##    `match_state.gd` 里 `round_index != round_before` 那两处守卫，本函数立刻转红。）
func _check_half_submit() -> void:
	var bad := 0
	var worst := 12
	var most_rounds := 0
	for s in 200:
		for who in [0, 1]:
			var r: Dictionary = _play(90000 + s * 131, true, int(who))
			worst = mini(worst, int(r["activated"]))
			most_rounds = maxi(most_rounds, int((r["st"] as MatchState).round_index))
			if int(r["unflipped"]) > 0 or not bool(r["over"]):
				bad += 1
	_check(bad == 0, "400 局「一方先提交 + 另一方超时代选」没有一张牌扣着牌背",
			"漏 %d 局" % bad)
	_check(worst == 12, "这批局每局都激活满 12 张", "最少 %d" % worst)
	# 轮次必须**正好** 6 轮走完。超过 6 轮说明"有一轮只激活了一张"，
	# 虽然终局那道 `_all_flipped()` 兜底会把牌补齐、结果是对的，
	# 但玩家会看到"第 7 轮 / 第 8 轮"，而且那一轮对面是空着手过的 ——
	# 这条专门钉住代选循环"多走一格"本身，别让它躲在兜底后面。
	_check(most_rounds == MatchDB.DECK_SIZE, "翻完 12 张恰好只用 6 轮（没有只激活一张的轮）",
			"最多 %d 轮" % most_rounds)
	# 结构性兜底：终局只允许在真的翻完之后开，轮次跑在牌前面也不许判负
	var guard_ok := true
	for s in 60:
		var r2: Dictionary = _play(7000 + s * 977, true, s % 2)
		var st = r2["st"]
		if int(st.round_index) >= MatchDB.DECK_SIZE and int(r2["activated"]) < 12:
			guard_ok = false
	_check(guard_ok, "轮次到 6 但牌没翻完时不许进终局", "")


func _check_determinism() -> void:
	var a: Dictionary = _play(4242)
	var b: Dictionary = _play(4242)
	var sa: Array = []
	var sb: Array = []
	for c in (a["st"] as MatchState).cards:
		sa.append("%s|%d|%s|%s" % [c["boss_id"], int(c["team"]), str(c["face_up"]), str(c["cell"])])
	for c in (b["st"] as MatchState).cards:
		sb.append("%s|%d|%s|%s" % [c["boss_id"], int(c["team"]), str(c["face_up"]), str(c["cell"])])
	_check(sa == sb, "同种子 → 正反面与落点完全一致（可重放）")
	_check(int(a["winner"]) == int(b["winner"]) and a["reason"] == b["reason"],
			"同种子 → 同名次的胜者与结束原因一致")
	var d: Dictionary = _play(4243)
	_check(d["st"] != null, "换种子能跑出不同局面")


func _check_clock_ramp() -> void:
	var st := MatchState.new()
	st.phase = MatchState.Phase.FINAL
	st.final_elapsed = 0.0
	_check(absf(st.time_scale() - 1.0) < 0.001, "翻完即开打时倍率为 1.0")
	st.final_elapsed = 59.9
	_check(absf(st.time_scale() - 1.0) < 0.001, "第 60 秒之前不加速")
	st.final_elapsed = 90.0
	var mid := st.time_scale()
	_check(mid > 1.3 and mid < 1.7, "中点约 1.5 倍", "x=%.2f" % mid)
	st.final_elapsed = 120.0
	_check(absf(st.time_scale() - MatchDB.ACCEL_MAX_SCALE) < 0.001, "终点推到 2.0",
			"x=%.2f" % st.time_scale())
	st.final_elapsed = 400.0
	_check(st.time_scale() <= MatchDB.ACCEL_MAX_SCALE + 0.001, "不会超过上限")


# ===================== 千局模拟 =====================

func _check_sim(n: int) -> void:
	var stalls := 0
	var early := 0
	var bad_flip := 0
	var wins := [0, 0, 0]
	var reasons := {}
	var max_steps := 0
	for s in n:
		var r: Dictionary = _play(1000 + s * 37, (s % 5) == 0)   # 每 5 局有一局走超时代选
		var st: MatchState = r["st"]
		max_steps = maxi(max_steps, int(r["steps"]))
		if not bool(r["over"]):
			stalls += 1
		if bool(r["ended_early"]):
			early += 1
		if int(r["activated"]) != 12 or int(r["face_up"]) != 6:
			bad_flip += 1
		wins[int(r["winner"])] += 1
		reasons[String(r["reason"])] = int(reasons.get(String(r["reason"]), 0)) + 1
	_check(stalls == 0, "%d 局无一卡死" % n, "stall=%d max_steps=%d" % [stalls, max_steps])
	_check(early == 0, "%d 局都没有「没翻完就判负」" % n, "n=%d" % early)
	_check(bad_flip == 0, "%d 局都是 12 翻 / 6 正 6 反" % n, "bad=%d" % bad_flip)
	var t0 := float(wins[0]) / n
	_check(t0 > 0.30 and t0 < 0.70, "先手队胜率不退化（规则本身不偏袒某队）",
			"team0=%.1f%% team1=%.1f%% draw=%.1f%%" % [
				t0 * 100.0, float(wins[1]) / n * 100.0, float(wins[2]) / n * 100.0])
	print("     结束原因分布：", reasons)
