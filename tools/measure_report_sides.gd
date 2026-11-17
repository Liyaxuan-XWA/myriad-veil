extends Node
## 战报读数核对：真打一局到分胜负，把每只的 打出 / 承受 两个数都打出来
##
## 用户实机截图里"我方六只全是 0"，两种解释要分清：
##   A 真的没打到（开局就被观澜那档秒了，前摇都没走完）
##   B 打到了但没记账（归属那条链在我方这一侧断了）
## 区别在承受侧：B 的话我方承受也会是 0；A 的话我方承受会是十几万。
##
## 用法：godot --headless --path . res://tools/measure_report_sides.tscn -- --no-save

func _ready() -> void:
	print("\n########## 战报读数核对 ##########")
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = 2
	GameState.match_context = {"level": 3}
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
	if fight == null or fight.disabled:
		print("  ⚠ 开不了战")
		get_tree().quit(1)
		return
	fight.pressed.emit()

	var f := 0
	while f < 6000 and st.phase != MatchState.Phase.OVER:
		await get_tree().process_frame
		f += 1
	print("  打到第 %d 帧，phase=%s 结束方式=%s 赢家=%s"
			% [f, MatchState.PHASE_NAME[st.phase], st.end_reason, str(st.winner)])

	var sides: Array = arena.call("_report_sides")
	for s_i in sides.size():
		var s: Dictionary = sides[s_i]
		print("\n── %s ──" % String(s.get("title", "")))
		for u in s.get("units", []):
			var d: Dictionary = u
			print("  %-12s 打出=%10.1f  承受=%10.1f  spawned=%s alive=%s  行=%d 组=%d" % [
				String(d.get("name", "")),
				float(d.get("total", 0.0)), float(d.get("taken_total", 0.0)),
				str(bool(d.get("spawned", false))), str(bool(d.get("alive", false))),
				(d.get("rows", []) as Array).size(), (d.get("taken", []) as Array).size()])
	var rep: Dictionary = arena.get("_report")
	for card in rep.keys():
		var e: Dictionary = rep[card]
		print("  快照 card=%d team=%d rows=%d taken=%d" % [
			int(card), int(e.get("team", -1)),
			(e.get("rows", {}) as Dictionary).size(), (e.get("taken", {}) as Dictionary).size()])
	get_tree().quit(0)
