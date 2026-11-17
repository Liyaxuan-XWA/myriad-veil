extends Node
## 卡片自走棋 · 关卡卡组生成器（#54，2026-11-05）
##
## 接缝只有一个：`MatchLevelDeck.deck_for(level:int) -> Array[String]`。
## 所有断言都打在这个公共接口上，内部怎么加权、怎么去重都不该让探针红。
##
## 用法：godot --headless --path . res://tools/probe_match_level_deck.tscn -- --no-save

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
	print("\n########## 棋坛关卡 · 卡组生成器 ##########")
	_check_deck_shape()
	_check_determinism()
	_check_unique_across_levels()
	_check_strength_curve()
	_check_stats_ignore_level()
	_check_no_global_random()
	_check_exhaustion_contract()
	_check_bad_level()
	_finish()


## ⑧ 关卡号下界：#55 那边传的是 `match_level_cleared + 1`，
##    但默认 0 / 手滑传负数不能把游戏搞崩，也不能静默给一副"第 0 关"的牌。
func _check_bad_level() -> void:
	var bad: Array[String] = []
	for lv in [-5, -1, 0]:
		var deck := MatchLevelDeck.deck_for(lv)
		if deck.size() != MatchDB.DECK_SIZE:
			bad.append("level=%d 给了 %d 张" % [lv, deck.size()])
		elif not _all_in_pool(deck) or not _no_dup(deck):
			bad.append("level=%d 非法卡组 %s" % [lv, str(deck)])
	_check(bad.is_empty(), "⑧ 关卡号 0 / 负数不崩且产出合法 6 张", str(bad))
	_check(_key(MatchLevelDeck.deck_for(0)) == _key(MatchLevelDeck.deck_for(1)),
		"⑧ 关卡号下界统一按第 1 关处理（不另开一副幽灵牌）", "")


## ⑦ 组合用尽后的契约：不崩、不空放、不无限循环，并且**报警要真的响**。
##    实测可达组合远少于 C(16,6)=8008（加权饱和后强半区垄断），
##    第 416 关起就会撞满，所以这里跑到 520 关把回退分支真的走一遍。
func _check_exhaustion_contract() -> void:
	var t0 := Time.get_ticks_msec()
	var bad: Array[String] = []
	var dup_after_ceiling := 0
	var seen := {}
	for lv in range(1, 521):
		var deck := MatchLevelDeck.deck_for(lv)
		if deck.size() != MatchDB.DECK_SIZE or not _all_in_pool(deck) or not _no_dup(deck):
			bad.append("第 %d 关产出非法卡组 %s" % [lv, str(deck)])
			break
		var k := _key(deck)
		if seen.has(k):
			dup_after_ceiling += 1
		else:
			seen[k] = lv
	var ms := Time.get_ticks_msec() - t0
	_check(bad.is_empty(), "⑦ 跑到 520 关全部产出合法 6 张（回退分支不空放不崩）", str(bad))
	_check(dup_after_ceiling > 0, "⑦ 可达组合用尽后确实进入回退（不是死代码）",
		"%d 副与前面重复，实测去重守到约第 400 关" % dup_after_ceiling)
	_check(ms < 4000, "⑦ 生成 1..520 关耗时可接受（冷启动一次）", "%d ms" % ms)


## ④ 加权曲线：关卡号越高越偏强手，但早期不能已经顶格。
##    强度排名在探针里**独立算**（PANEL_SNAPSHOT 的 hp×atk 排序），
##    不去调生成器的内部表，否则就成了同义反复。
##    ⚠ 分段不能切太细：一副牌只有 6 张、一段只有 20 副时，
##      单副均名的抽样 σ≈0.34，逐段严格递增会被噪声自己打红（11-05 第一版就栽在这）。
##      所以趋势用 100 关的大窗口判，窗口内 σ≈0.15 才够分辨真实曲线。
func _check_strength_curve() -> void:
	var ranks := _rank_table()
	# 窗口贴着曲线走满的那段放（生成器里 BIAS_FULL_LEVEL=50），
	# 铺到 1-300 去量只会量到一条已经平掉的天花板。
	var windows := [[1, 12], [13, 37], [38, 100]]
	var means: Array[float] = []
	for w in windows:
		means.append(_avg_rank(ranks, int(w[0]), int(w[1])))
	print("      三段平均排名：1-12=%.2f  13-37=%.2f  38-100=%.2f" % [means[0], means[1], means[2]])

	_check(means[0] < means[1] and means[1] < means[2],
		"④ 平均名次随关卡三段严格递增", "%.2f / %.2f / %.2f" % [means[0], means[1], means[2]])
	_check(means[2] - means[0] >= 2.0, "④ 曲线幅度够玩家感觉到（末段比首段 ≥2 名）",
		"差 %.2f" % (means[2] - means[0]))
	_check(means[0] < 10.0, "④ 首段没有被加权顶格（早期仍能见到弱手）",
		"%.2f / 满格 16" % means[0])

	# 走满之后要真的以强手为主：60..120 关里，排名前 8（强半区）的出场占比
	var top := 0
	var total := 0
	for lv in range(60, 121):
		for id in MatchLevelDeck.deck_for(lv):
			total += 1
			if int(ranks[String(id)]) >= 9:
				top += 1
	var share := float(top) / float(maxi(total, 1))
	_check(share >= 0.60, "④ 高关卡确实以强手为主（强半区出场占比）",
		"%.0f%%（门槛 60%%）" % (share * 100.0))


func _avg_rank(ranks: Dictionary, from_lv: int, to_lv: int) -> float:
	var sum := 0.0
	var n := 0
	for lv in range(from_lv, to_lv + 1):
		for id in MatchLevelDeck.deck_for(lv):
			sum += float(ranks[String(id)])
			n += 1
	return sum / float(maxi(n, 1))


## ① 示踪弹：第 1 关能拿到一副合法的 6 张
func _check_deck_shape() -> void:
	var deck: Array = MatchLevelDeck.deck_for(1)
	_check(deck.size() == MatchDB.DECK_SIZE, "① 第 1 关给满 6 张", "%d 张" % deck.size())
	_check(_all_in_pool(deck), "① 6 张全部来自卡池 16 位", str(deck))
	_check(_no_dup(deck), "① 同一副里不出现重复卡", str(deck))


## ② 同一关在任何时候重算都得到同一副（关卡号是唯一输入，不吃引擎全局随机）
func _check_determinism() -> void:
	var first := _key(MatchLevelDeck.deck_for(7))
	var drift: Array[String] = []
	for i in 50:
		if _key(MatchLevelDeck.deck_for(7)) != first:
			drift.append("第 %d 次重算变了" % (i + 2))
			break
	_check(drift.is_empty(), "② 第 7 关连续重算 50 次逐字一致", str(drift))
	_check(_key(MatchLevelDeck.deck_for(7)) != _key(MatchLevelDeck.deck_for(8)),
		"② 相邻两关不是同一副", "7=%s 8=%s" % [first, _key(MatchLevelDeck.deck_for(8))])


## ③ 严格去重：1..300 关两两互不相同（ADR-0002 的硬要求）
func _check_unique_across_levels() -> void:
	const LEVELS := 300
	var seen := {}
	var dup: Array[String] = []
	for lv in range(1, LEVELS + 1):
		var k := _key(MatchLevelDeck.deck_for(lv))
		if seen.has(k):
			dup.append("第 %d 关与第 %d 关同为 %s" % [lv, int(seen[k]), k])
			if dup.size() >= 3:
				break
		else:
			seen[k] = lv
	_check(dup.is_empty(), "③ 前 300 关两两互不相同（实测 %d 副）" % seen.size(), str(dup))


static func _key(deck: Array) -> String:
	var ids: Array[String] = []
	for id in deck:
		ids.append(String(id))
	ids.sort()
	return "|".join(ids)


## ⑤ 数值不膨胀：生成 300 关不许动到任何棋子面板。
##    判据是「生成前后 16 位的 piece_stats 逐字相同」，不是去看代码有没有乘系数。
func _check_stats_ignore_level() -> void:
	var before := _all_stats()
	for lv in range(1, 301):
		MatchLevelDeck.deck_for(lv)
	var after := _all_stats()
	var diff: Array[String] = []
	for id in before.keys():
		if str(before[id]) != str(after[id]):
			diff.append("%s %.0f→%.0f" % [id, (before[id] as Dictionary).hp, (after[id] as Dictionary).hp])
	_check(diff.is_empty(), "⑤ 生成 300 关前后棋子面板逐字未变（关卡号不参与数值）", str(diff))

	# 同一只卡在第 1 关和第 999 关用的是同一张表，这里独立再算一次对账。
	# ⚠ 11-07 起 `piece_stats()` 的面板 = `基准 × 系数 ÷ 实测减免`（减免见 `MEASURED_EHP_MULT`），
	#   所以这条恒等式挪到**有效身板**上判 —— 铁律说的"面板与关卡号无关"没有被削弱，
	#   只是"面板"这个数现在是补偿后的结果，不再等于 基准×系数 本身。
	var s1 := MatchDB.piece_stats("boss_03_c")
	var s2 := MatchDB.piece_stats("boss_03_c")
	_check(str(s1) == str(s2)
			and absf(MatchDB.effective_hp("boss_03_c") - 30000.0 * 1.10) < 0.01,
			"⑤ 晏无咎有效身板 = 基准 × 系数，与关卡无关",
			"hp=%.1f 有效=%.1f" % [s1.hp, MatchDB.effective_hp("boss_03_c")])


## ⑥ 硬约定：不吃引擎全局随机（见 match_state.gd:473 的 Fisher–Yates 注释）。
##    `rng.randf()` 是合法的，裸 `randf()` 才违规——所以要看调用体前面有没有 `rng.`。
func _check_no_global_random() -> void:
	var src := ""
	var f := FileAccess.open("res://scripts/match/match_level_deck.gd", FileAccess.READ)
	_check(f != null, "⑥ 能读到生成器源码", "res://scripts/match/match_level_deck.gd")
	if f == null:
		return
	src = f.get_as_text()
	_check(src.contains("RandomNumberGenerator.new()"), "⑥ 随机走的是带种子的本地 rng", "")

	var hits: Array[String] = []
	for frag in ["randomize(", ".shuffle(", "randf(", "randi(", "randfn("]:
		var at := src.find(frag)
		while at >= 0:
			var before := src.substr(maxi(at - 4, 0), mini(4, at))
			if before != "rng.":
				hits.append("%s @%d" % [frag, at])
				break
			at = src.find(frag, at + 1)
	_check(hits.is_empty(), "⑥ 源码里没有全局随机调用", str(hits))


func _all_stats() -> Dictionary:
	var out := {}
	for id in MatchDB.CARD_POOL:
		out[String(id)] = MatchDB.piece_stats(String(id))
	return out


## 独立真相源：按 PANEL_SNAPSHOT 的 hp×atk 排 1..16 名（1 最弱）
func _rank_table() -> Dictionary:
	var scored: Array = []
	for id in MatchDB.CARD_POOL:
		var p: Dictionary = MatchDB.PANEL_SNAPSHOT[String(id)]
		scored.append([String(id), float(p.hp) * float(p.atk)])
	scored.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	var out := {}
	for i in scored.size():
		out[String(scored[i][0])] = i + 1
	return out


func _all_in_pool(deck: Array) -> bool:
	for id in deck:
		if not MatchDB.CARD_POOL.has(String(id)):
			return false
	return true


func _no_dup(deck: Array) -> bool:
	var seen := {}
	for id in deck:
		if seen.has(String(id)):
			return false
		seen[String(id)] = true
	return true


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
