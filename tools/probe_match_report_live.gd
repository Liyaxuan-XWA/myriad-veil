extends Node
## 战报端到端（票 003/004）：真开一局，验"账"对得上、页打得开
##
## 最有分量的一条是**自洽**：
##   双方逐招行的总和 == 对面实际掉了多少血（用规则层 card 的 hp_max - hp 独立算一遍）。
## 两头来源不同（台账在受击方的 take_damage 里记，血量在战斗镜像里写），
## 所以这条真能抓到"漏了某条伤害路径"——比如持续伤害不走 take_damage 那一坑。
##
## 用法：godot --headless --path . res://tools/probe_match_report_live.tscn -- --no-save

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
	print("\n########## 战报端到端 · 票 003/004 ##########")
	await _check_live_match()

	_check(_passes + _fails.size() >= _planned, "④ 判据全部跑到（没有半途中止）",
			"%d/%d" % [_passes + _fails.size(), _planned])
	_finish()


func _check_live_match() -> void:
	_plan(22)
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = 5
	GameState.match_context = {"level": 6}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 20:
		await get_tree().process_frame
	var st = arena.get("_state")
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
	var btns: Dictionary = arena.get("_buttons")
	var fight: Button = btns.get("fight")
	_check(fight != null and not fight.disabled, "① 12 张摆好后能点「开战」", "")
	fight.pressed.emit()
	print("[心跳] 已点开战")

	# 打一段：先等 12 只落场，再等"确实打掉血了"才继续。
	# ⚠ 不能只等固定帧数：headless 一帧的墙钟随机型浮动，帧数够而血没动时
	#   自洽判据会变成 0==0 的假绿。
	for i in 400:
		await get_tree().process_frame
		if (arena.get("_spawn_queue").is_empty()
				and (arena.get("_pieces") as Node).get_child_count() >= 12):
			break
	var waited := 0
	var strict := [-1.0, -1.0]      # [台账总和, 掉血总和]，取"已有掉血但还没人死"的那一帧
	# 逐只的承受账与掉血，同样只在无死亡窗口里取（过量伤害会把等号打歪）
	var strict_taken := {}
	var strict_lost := {}
	while waited < 420:
		await get_tree().process_frame
		waited += 1
		var led := _ledger_sum(arena.call("_report_sides") as Array)
		var lost := _hp_lost(st)
		var any_dead := false
		for i in st.cards.size():
			var c0: Dictionary = st.cards[i]
			if bool(c0["spawned"]) and not bool(c0["alive"]):
				any_dead = true
		# 严格比对只能在"还没人死"的窗口里做：一旦有人死，最后一击的**过量伤害**
		# 会计进台账但不再掉血（3000 的一刀砍在 500 血上 ⇒ 台账 +3000、血只掉 500）。
		# ⚠ 也不能一有招式名就收手：规则层的 hp 是**延迟镜像**的，
		#   第一帧台账已有 896 而 card 的 hp 还是满的（探针第一版就是这么红的）。
		if led > 0.0 and lost > 0.0 and not any_dead and strict[0] < 0.0:
			strict = [led, lost]
			strict_taken = _taken_map(arena.call("_report_sides") as Array)
			strict_lost = _lost_map(st)
		if strict[0] >= 0.0 and (any_dead or waited >= 90):
			break
		if any_dead:
			break
	print("[心跳] 交手 ", waited, " 帧 掉血=", snap1(_hp_lost(st)),
			" 严格样本=", str([snap1(strict[0]), snap1(strict[1])]),
			" 行名=", str(_all_names(arena)))
	_check(_hp_lost(st) > 0.0, "① 确实打起来了（不然自洽判据是 0==0 的假绿）",
			"掉血=%.1f" % _hp_lost(st))
	# 这条才是"按技能"三个字的凭据：真开一局里必须出现**招式名**的行，
	# 而不是全都糊在「普通攻击」/「其余」两行上。
	_check(_has_named(arena.call("_report_sides")), "① 表里出现了招式名行（不是只有平A与其余）",
			str(_all_names(arena)))
	# ② 自洽（严格）：没人死的那一帧，台账必须与掉血对上 —— 允许镜像延迟的少量超出，
	#    但绝不能少记（少记 = 有伤害路径没接上，比如跳伤不走 take_damage 那一坑）。
	_check(strict[0] >= 0.0 and strict[0] + 1.0 >= strict[1]
			and strict[0] <= strict[1] * 1.15 + 50.0,
			"② 无死亡时 台账 ≈ 实际掉血（不漏路径、也不虚记）",
			"台账=%.1f 掉血=%.1f" % [strict[0], strict[1]])
	# 承伤侧的两条独立判据：
	# ① **逐只**对上自己的血条（输出侧只能对总量，这条能抓到"记错人"）
	# ② 全局 打出总额 == 承受总额（同一笔钱在两侧各记一次，少抄一侧就红）
	var per_unit: Array = []
	for k in strict_lost.keys():
		if absf(float(strict_taken.get(k, 0.0)) - float(strict_lost[k])) > 1.0:
			per_unit.append("%s 承受=%.1f 掉血=%.1f" % [k, float(strict_taken.get(k, 0.0)), float(strict_lost[k])])
	_check(not strict_lost.is_empty() and per_unit.is_empty(),
			"③ 逐只：承受账 == 它自己掉的血（承伤没记错人）", str(per_unit))
	var taken_all := 0.0
	for k in strict_taken.keys():
		taken_all += float(strict_taken[k])
	_check(strict[0] >= 0.0 and absf(taken_all - strict[0]) <= 1.0,
			"③ 承受总额 == 打出总额", "承受=%.1f 打出=%.1f" % [taken_all, strict[0]])
	# ② 自洽（终局）：允许超出（过量伤害），但**绝不能少**——少记就是漏了某条路径
	for side_i in 2:
		var out_sum := 0.0
		for u in (arena.call("_report_sides") as Array)[side_i].get("units", []):
			for r in (u as Dictionary).get("rows", []):
				out_sum += float((r as Array)[1])
		var lost_i := 0.0
		for i in st.team_cards(1 - side_i):
			var c: Dictionary = st.cards[i]
			if not bool(c["spawned"]):
				continue
			lost_i += maxf(0.0, float(c["hp_max"]) - float(c["hp"]))
		_check(out_sum + 1.0 >= lost_i, "② 终局台账不少于实际掉血（侧%d）" % side_i,
				"台账=%.1f 掉血=%.1f" % [out_sum, lost_i])

	var report: Dictionary = arena.get("_report")
	_check(report.size() == 12, "① 十二只棋子都立了户", str(report.size()))

	# 用**喂给战报页的那一份**对账：`_report_sides()` 会把还在场的棋子现抄一次，
	# 死掉的走 child_exiting_tree 的快照。直接翻 `_report` 字典读到的是出生的空壳 ——
	# 第一版就是这么红的（队1 台账 0 / 掉血 3191）。
	var sides: Array = arena.call("_report_sides")
	_check(sides.size() == 2, "② 战报是两栏（我方 / 对方）", str(sides.size()))
	var titles: Array = []
	var unit_counts: Array = []
	var row_total := 0
	for s in sides:
		titles.append(String((s as Dictionary).get("title", "")))
		var units: Array = (s as Dictionary).get("units", [])
		unit_counts.append(units.size())
		for u in units:
			row_total += ((u as Dictionary).get("rows", []) as Array).size()
	_check(titles == ["我方", "对方"], "① 两栏标题是给玩家看的中文", str(titles))
	_check(unit_counts == [6, 6], "① 每栏各 6 只（含没上场的，不是只列活的）", str(unit_counts))
	_check(row_total >= 2, "③ 表里至少两只棋子有逐招内容（两栏都不是空壳）", "%d 行" % row_total)

	# 排序：每栏第一只必须是该栏总输出最高的
	var unsorted: Array = []
	for s in sides:
		var prev := 1e18
		for u in (s as Dictionary).get("units", []):
			var t := float((u as Dictionary).get("total", 0.0))
			if t > prev + 0.001:
				unsorted.append(String((u as Dictionary).get("name", "")))
			prev = t
	_check(unsorted.is_empty(), "③ 每栏按总输出降序", str(unsorted))

	# —— 真打到分胜负再对一次总账。
	# 这一条才是"整本账丢了"的克星：收账时机错在死亡之前时，
	# 无死亡窗口里两侧都能对上，只有打完、有人死过之后才露馅
	# （实测三张非核心卡的 child_exiting_tree 压根没触发，那一侧全是 0）。
	var f := 0
	while f < 4000 and st.phase != MatchState.Phase.OVER:
		await get_tree().process_frame
		f += 1
	var sides_end: Array = arena.call("_report_sides")
	var out0 := _side_sum(sides_end, 0, "total")
	var out1 := _side_sum(sides_end, 1, "total")
	var tk0 := _side_sum(sides_end, 0, "taken_total")
	var tk1 := _side_sum(sides_end, 1, "taken_total")
	_check(out0 > 0.0 and absf(out0 - tk1) <= maxf(2.0, out0 * 0.001),
			"④ 打完：我方打出 == 对方承受", "打出=%.1f 对面承受=%.1f" % [out0, tk1])
	_check(out1 > 0.0 and absf(out1 - tk0) <= maxf(2.0, out1 * 0.001),
			"④ 打完：对方打出 == 我方承受", "打出=%.1f 我方承受=%.1f" % [out1, tk0])
	# 死过的棋子也必须还留着账（挨打的那一侧不许整只归零）
	var blanked: Array = []
	for s in sides_end:
		for u in (s as Dictionary).get("units", []):
			var d: Dictionary = u
			if bool(d.get("spawned", false)) and float(d.get("taken_total", 0.0)) <= 0.0 \
					and float(d.get("total", 0.0)) <= 0.0:
				blanked.append(String(d.get("name", "")))
	_check(blanked.is_empty(), "④ 没有哪只上场的棋子整本账是空的", str(blanked))
	_check(st.phase == MatchState.Phase.OVER, "④ 这一局真打到了分胜负",
			"%s / %d 帧" % [String(MatchState.PHASE_NAME[st.phase]), f])

	# —— UI：结算页那颗「战报」真的能开、能关
	var settle_btn: Button = null
	await get_tree().process_frame
	var res: Control = arena.get("_result")
	for ch in res.find_children("*", "Button", true, false):
		if String((ch as Button).text) == "战报":
			settle_btn = ch as Button
	_check(settle_btn != null, "④ 结算页上有「战报」这颗钮", "")
	if settle_btn != null:
		settle_btn.pressed.emit()
		await get_tree().process_frame
		var view: Node = arena.get("_report_view")
		_check(view != null and is_instance_valid(view), "④ 点它真的开出一页", "")
		if view != null:
			# 展开第一只，验逐招行是真的挂上去了（不是只有标题）
			var heads: Array = (view as Node).find_children("*", "Button", true, false)
			var expanded := false
			for h in heads:
				if String((h as Button).text).contains("　") and not (h as Button).disabled:
					(h as Button).pressed.emit()
					await get_tree().process_frame
					expanded = (h as Control).get_child_count() >= 1 \
							or (h.get_parent() as Control).get_child_count() >= 2
					break
			_check(expanded, "④ 点名一只会展开逐招行", "")
			# 截图只在窗口化下有意义（headless 没有渲染）。
			# 布局合不合你定的口径（三级文字、不堆方框、读数用图形）要你眼过一遍。
			if DisplayServer.get_name() != "headless":
				await get_tree().process_frame
				var img := (get_tree().root as Viewport).get_texture().get_image()
				img.save_png("output/match_report_view.png")
				print("[截图] output/match_report_view.png")
			(view as Node).call("close_and_free")
			await get_tree().process_frame
			_check(not is_instance_valid(view) or not (view as Node).is_inside_tree(),
					"④ 关闭之后不残留在树上", "")
	arena.queue_free()
	for i in 3:
		await get_tree().process_frame
	CharacterData.match_quick_mode = false
	GameState.match_context = {}


## 场上已经打掉多少血（两边合计）——用来判断"真打起来了"
func _hp_lost(st) -> float:
	var t := 0.0
	for i in st.cards.size():
		var c: Dictionary = st.cards[i]
		if not bool(c["spawned"]):
			continue
		t += maxf(0.0, float(c["hp_max"]) - float(c["hp"]))
	return t


## 两边台账总和（用喂给 UI 的那份数据算，保证判据量的就是玩家看到的那一屏）
func _ledger_sum(sides: Array) -> float:
	var t := 0.0
	for s in sides:
		for u in (s as Dictionary).get("units", []):
			for r in (u as Dictionary).get("rows", []):
				t += float((r as Array)[1])
	return t


## 某一侧的总额（key = "total" 打出 / "taken_total" 承受）
func _side_sum(sides: Array, side_i: int, key: String) -> float:
	var t := 0.0
	for u in (sides[side_i] as Dictionary).get("units", []):
		t += float((u as Dictionary).get(key, 0.0))
	return t


## 逐只的承受总额（按 card 下标取键，避免双方重名时串到一起 —— 棋局允许两边带同一只）
## 承受是两层（来源棋子 → {招式: 金额}），这里按组求和。
func _taken_map(sides: Array) -> Dictionary:
	var out := {}
	for s in sides:
		for u in (s as Dictionary).get("units", []):
			var d: Dictionary = u
			var t := 0.0
			for g in d.get("taken", []):
				t += float((g as Dictionary).get("total", 0.0))
			out[int(d["card"])] = t
	return out


## 逐只掉了多少血（同一批 card 下标）
func _lost_map(st) -> Dictionary:
	var out := {}
	for i in st.cards.size():
		var c: Dictionary = st.cards[i]
		if not bool(c["spawned"]):
			continue
		var lost := maxf(0.0, float(c["hp_max"]) - float(c["hp"]))
		if lost > 0.0:
			out[i] = lost
	return out


## 是否出现了"招式名行"（不是平A、不是其余）
func _has_named(sides: Array) -> bool:
	for n in _names_of(sides):
		if n != BossBase.REPORT_ROW_BASIC and n != BossBase.REPORT_ROW_REST:
			return true
	return false


func _names_of(sides: Array) -> Array:
	var out: Array = []
	for s in sides:
		for u in (s as Dictionary).get("units", []):
			for r in (u as Dictionary).get("rows", []):
				out.append(String((r as Array)[0]))
	return out


func _all_names(arena: Node) -> Array:
	return _names_of(arena.call("_report_sides") as Array)


func snap1(v: float) -> float:
	return roundf(v * 10.0) / 10.0


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
