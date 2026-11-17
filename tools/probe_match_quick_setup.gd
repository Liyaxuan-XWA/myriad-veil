extends Node
## 快速布局纯函数（票 002）
##
## 守的是 ADR-0004 那条硬约束：长卷拓印画的落位和对局开局真正摆的落位
## 必须是**同一个函数**算出来的，漂一次就等于骗玩家。
## 期望值全部来自独立真相源（deck_for / MatchDB 面板 / 手算的 3+3），
## 不拿 layout_for 自己的输出去验它自己。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_setup.tscn -- --no-save

const SAMPLES := 200

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
	print("\n########## 快速布局纯函数 · 票 002 ##########")
	_check_deterministic()
	_check_deck_is_the_level_deck()
	_check_three_up_three_down()
	_check_strongest_up_weakest_down()
	_check_layouts_differ_across_levels()
	_check_shares_the_lock_rule()
	_finish()


## ① 同一关两次调用逐字段相同，且 6 个格子互不相同、都在盘内。
func _check_deterministic() -> void:
	var a: Array = MatchQuickSetup.layout_for(7)
	var b: Array = MatchQuickSetup.layout_for(7)
	var same := a.size() == b.size()
	for i in range(mini(a.size(), b.size())):
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		if String(x["boss_id"]) != String(y["boss_id"]) \
				or Vector2(x["cell"]) != Vector2(y["cell"]) \
				or bool(x["face_up"]) != bool(y["face_up"]):
			same = false
	_check(same and a.size() == MatchDB.DECK_SIZE, "① 同一关两次调用逐字段相同", str(a.size()))

	var seen := {}
	var offboard: Array = []
	for x in a:
		var c: Vector2i = (x as Dictionary)["cell"]
		if seen.has(c):
			offboard.append("重复%s" % str(c))
		seen[c] = true
		if not MatchDB.in_board(c):
			offboard.append("出界%s" % str(c))
	_check(offboard.is_empty(), "① 6 个格子互不相同且都在盘内", str(offboard))


## ② 卡组必须就是 deck_for(level)，不许 layout_for 自己再抽一次牌。
## 否则长卷预告的是一副、进关打的是另一副，"完全预告"直接作废。
func _check_deck_is_the_level_deck() -> void:
	var bad: Array = []
	for lv in [1, 2, 3, 17, 40, 120]:
		var want := {}
		for id in MatchLevelDeck.deck_for(lv):
			want[String(id)] = true
		var got := {}
		for x in MatchQuickSetup.layout_for(lv):
			got[String((x as Dictionary)["boss_id"])] = true
		if want.keys().size() != got.keys().size():
			bad.append("%d 张数不符" % lv)
			continue
		for k in want:
			if not got.has(k):
				bad.append("%d 缺 %s" % [lv, k])
	_check(bad.is_empty(), "② 每一关的卡组 == deck_for(关卡号)", str(bad))


## ③ 每关恰好 3 正 3 反。这是普通模式 LOCK 的结果分布（1 指定反 + 1 指定正 +
## 其余 4 张洗牌 2/2），快速模式既然说"三正三反"，就必须关关如此。
## 抽 200 关而不是 3 关：面板相同的两只进同一副牌时 down==up，
## 那种边界只在高关卡号才撞得出来。
func _check_three_up_three_down() -> void:
	var bad: Array = []
	for lv in range(1, SAMPLES + 1):
		var ups := 0
		for x in MatchQuickSetup.layout_for(lv):
			if bool((x as Dictionary)["face_up"]):
				ups += 1
		if ups != 3:
			bad.append("%d关=%d正" % [lv, ups])
	_check(bad.is_empty(), "③ 前 %d 关每关恰好 3 正 3 反" % SAMPLES,
			"%s 例（共 %d）" % [str(bad.slice(0, 4)), bad.size()])


## ④ 最强那张锁正面、最弱那张锁反面 —— 和 MatchPolicy.decide_lock 同一条判据。
## 期望值从 MatchDB 面板独立算出，不拿 layout_for 的结果反推。
func _check_strongest_up_weakest_down() -> void:
	var bad: Array = []
	for lv in [1, 2, 5, 11, 23, 40, 77, 120]:
		var layout: Array = MatchQuickSetup.layout_for(lv)
		var best_d := -INF
		var worst_d := INF
		var best_id := ""
		var worst_id := ""
		for x in layout:
			var bid := String((x as Dictionary)["boss_id"])
			var d := float(MatchDB.piece_stats(bid)["dps"])
			if d > best_d:
				best_d = d
				best_id = bid
			if d < worst_d:
				worst_d = d
				worst_id = bid
		for x in layout:
			var bid2 := String((x as Dictionary)["boss_id"])
			var up := bool((x as Dictionary)["face_up"])
			if bid2 == best_id and not up:
				bad.append("%d关 最强 %s 没锁正" % [lv, bid2])
			if bid2 == worst_id and up:
				bad.append("%d关 最弱 %s 没锁反" % [lv, bid2])
	_check(bad.is_empty(), "④ 最强锁正面、最弱锁反面（与 decide_lock 同判据）", str(bad))


## ⑤ 不同关卡的布局确实不同。固定摆位要是把 200 关都摆成同一副，
## "可背板"就变成"只有一块板"。
func _check_layouts_differ_across_levels() -> void:
	var seen := {}
	for lv in range(1, SAMPLES + 1):
		var parts: Array[String] = []
		for x in MatchQuickSetup.layout_for(lv):
			parts.append("%s@%s" % [String((x as Dictionary)["boss_id"]),
					str((x as Dictionary)["cell"])])
		parts.sort()
		seen["|".join(parts)] = true
	# 卡组本身第 416 关起才会重复（ADR-0002 实测），前 200 关应当几乎关关不同
	_check(seen.size() >= SAMPLES - 10, "⑤ 前 %d 关布局互不相同" % SAMPLES,
			"去重后 %d 副" % seen.size())


## ⑥ 同源守卫：`_cmd_lock` 走的状态机路径，和 `layout_for` 走的 face_flags 路径，
## 同一副牌 + 同一个种子必须给出**逐张相同**的正反面。
## 这条存在的理由：两处以后有人只改一边（比如把 LOCK_OWN_DOWN 调成 2），
## ①〜⑤ 全都还是绿的，只有这里会红。
func _check_shares_the_lock_rule() -> void:
	var seed_v := 12345
	var deck: Array = MatchLevelDeck.deck_for(5)
	var mine_ids: Array = []
	for id in MatchDB.CARD_POOL:
		if mine_ids.size() < MatchDB.DECK_SIZE:
			mine_ids.append(String(id))
	var st := MatchState.new()
	st.start([mine_ids, deck], seed_v, 0)
	st.apply_command({"t": "pick", "team": 0, "ids": mine_ids})
	st.apply_command({"t": "pick", "team": 1, "ids": deck})
	_check(st.phase == MatchState.Phase.LOCK, "⑥ 前置：状态机进到 LOCK", str(st.phase))

	var mine := st.team_cards(1)
	var dps: Array = []
	for i in mine:
		dps.append(float((st.cards[i] as Dictionary)["dps"]))
	var chosen: Dictionary = MatchPolicy.decide_lock(st, 1)
	# face_flags 用一条**独立但同种子**的 rng：start() 之后到 lock 之前没有任何
	# 地方消耗过 st.rng，所以两边起点一致。
	var r2 := RandomNumberGenerator.new()
	r2.seed = seed_v
	var expected := MatchPolicy.face_flags(dps, r2, mine.find(int(chosen["down"])),
			mine.find(int(chosen["up"])))
	st.apply_command({"t": "lock", "team": 1,
			"down": int(chosen["down"]), "up": int(chosen["up"])})
	var actual: Array = []
	for i in mine:
		actual.append(bool((st.cards[i] as Dictionary)["face_up"]))
	_check(actual == expected, "⑥ 状态机 LOCK 与 face_flags 逐张同结果",
			"%s vs %s" % [str(actual), str(expected)])


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
