extends Node
## 快速模式终局的实测：12 只全活开打，240 秒窗口内到底能不能清场。
##
## ⚠ 只能用 **live** 棋子测。`MatchCombat` 那个抽象模型的文件头明写
##   "不模拟走位、射程、前摇、元素克制、二阶段、任何机制……不能用来判断平衡"。
##   它的 TTK 是纯 dps÷hp，会系统性**低估**真实用时（真 BOSS 有前摇和打空的时候），
##   拿它估超时率等于给自己发假安心证明。
##
## 用法：godot --headless --path . res://tools/measure_quick_final.tscn -- --no-save
##   可加 --levels=1,4,9,17,25,40 指定关卡号

const DEFAULT_LEVELS := [1, 4, 9, 17, 25, 40]

var levels: Array = []
var results: Array = []


func _ready() -> void:
	_read_args()
	print("\n########## 快速终局实测：%d 关 ##########" % levels.size())
	for lv in levels:
		var r := await _one(int(lv))
		results.append(r)
		print("  第 %2d 关  %-18s 用时=%6.1fs 存活 我%d/敌%d  血量%%和 我%.2f/敌%.2f" % [
			int(lv), String(r["reason"]), float(r["secs"]), int(r["ally"]), int(r["enemy"]),
			float(r["fa"]), float(r["fb"])])
	_summarize()
	get_tree().quit(0)


func _read_args() -> void:
	levels = []
	for raw in OS.get_cmdline_user_args():
		var s := String(raw)
		if s.begins_with("levels="):
			for part in s.trim_prefix("levels=").split(","):
				if String(part).is_valid_int():
					levels.append(int(part))
	if levels.is_empty():
		levels = DEFAULT_LEVELS.duplicate()


func _one(lv: int) -> Dictionary:
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = lv - 1
	GameState.match_context = {"level": lv}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	# 60 秒：别让"到点代选"在摆子途中插一手，摆位由本工具自己驱动
	arena.set("player_stage_timeout", 60.0)
	add_child(arena)
	await _frames(24)
	var st = arena.get("_state")
	var ids: Array = []
	for i in MatchDB.DECK_SIZE:
		ids.append(String((st.legal_pool(0) as Array)[i]))
	st.apply_command({"t": "pick", "team": 0, "ids": ids})
	for n in MatchDB.DECK_SIZE:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		if legal.is_empty() or cells.is_empty():
			break
		st.apply_command({"t": "deploy", "team": 0, "card": int(legal[0]), "cell": cells[0]})
	st.quick_start_battle()

	var t0 := Time.get_ticks_msec() / 1000.0
	var waited := 0.0
	while st.phase != MatchState.Phase.OVER and waited < 300.0:
		await get_tree().process_frame
		waited = (Time.get_ticks_msec() / 1000.0) - t0
	var secs := float(st.final_elapsed)
	var out := {
		"level": lv, "reason": String(st.end_reason), "secs": secs,
		"wall": waited,
		"ally": int(MatchCombat.team_alive(st.cards, 0)),
		"enemy": int(MatchCombat.team_alive(st.cards, 1)),
		"fa": MatchCombat.hp_fraction_sum(st.cards, 0),
		"fb": MatchCombat.hp_fraction_sum(st.cards, 1),
		"winner": int(st.winner),
	}
	arena.queue_free()
	await _frames(4)
	# 每场之间把全局状态清干净，否则上一局留下的时停/流速会带进下一场
	GameState.reset_time_flow()
	return out


func _summarize() -> void:
	var cleared := 0
	var timed := 0
	var other := 0
	var secs: Array = []
	for r in results:
		var reason := String(r["reason"])
		if reason == "clear_field" or reason == "mutual_annihilation":
			cleared += 1
		elif reason.begins_with("timeout"):
			timed += 1
		else:
			other += 1
		secs.append(float(r["secs"]))
	secs.sort()
	var n := secs.size()
	var med := 0.0
	if n > 0:
		med = float(secs[int(n / 2)])
	var pct := 0.0
	if n > 0:
		pct = 100.0 * float(timed) / float(n)
	print("\n  样本=%d  清场=%d  超时=%d（%.0f%%）  其他=%d" % [n, cleared, timed, pct, other])
	print("  终局用时中位=%.1fs  最短=%.1fs  最长=%.1fs（窗口上限=%.0fs）" % [
		med, float(secs[0]) if n > 0 else 0.0, float(secs[n - 1]) if n > 0 else 0.0,
		MatchDB.QUICK_FINAL_LIMIT_SECONDS])
	print("  判定：超时率 %.0f%% %s 20%%" % [pct, "＞" if pct > 20.0 else "≤"])
	print("QUICK_TIMEOUT_RATE=%.0f%% samples=%d median=%.1fs" % [pct, n, med])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
