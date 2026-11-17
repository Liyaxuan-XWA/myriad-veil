extends Node
## 诊断（2026-11-04 用户带截图问「我输了但还有一张牌没翻出来」）：
## 逐帧盯规则层的 activated 位，把"每一轮到底激活了哪几张"打出来，
## 找出那张**落了子却从没被激活**的牌是在哪一轮被跳过的。
## 用法：godot --headless --path . res://tools/diag_match_unflip.tscn -- --no-save

const RUNS := 20


func _ready() -> void:
	var bad := 0
	for r in RUNS:
		if await _run_one(r):
			bad += 1
	print("\n########## %d 局里 %d 局有牌落了子却从没激活 ##########" % [RUNS, bad])
	get_tree().quit(0)


func _run_one(idx: int) -> bool:
	var arena := (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 0.05)
	add_child(arena)
	var st = arena.get("_state")
	var prev_act: Array = []          # 上一帧的 activated 快照
	var prev_round := -1
	var trace: Array = []
	var guard := 0
	while guard < 8000:
		guard += 1
		await get_tree().process_frame
		if st == null:
			break
		var ph := int(st.phase)
		if ph == MatchState.Phase.BATTLE or ph == MatchState.Phase.FINAL:
			st.timer = 0.0
		if ph == MatchState.Phase.OVER:
			break
		var cur: Array = []
		for c in st.cards:
			cur.append(bool(c["activated"]))
		if int(st.round_index) != prev_round:
			var newly: Array = []
			for i in cur.size():
				if cur[i] and (prev_act.size() != cur.size() or not prev_act[i]):
					newly.append("#%d(队%d)" % [i, int(st.cards[i]["team"])])
			if prev_round >= 0:
				trace.append("轮 %d→%d 本轮激活 %d 张：%s" % [prev_round, int(st.round_index),
						newly.size(), " ".join(PackedStringArray(newly))])
			prev_round = int(st.round_index)
		prev_act = cur
	var miss_rules := 0
	for i in st.cards.size():
		var c: Dictionary = st.cards[i]
		if bool(c["deployed"]) and not bool(c["activated"]):
			miss_rules += 1
			trace.append("★ #%d 队%d 落了子却从没激活（正=%s）" % [i, int(c["team"]), str(c["face_up"])])
	print("[局 %d] 结束=%s 轮=%d 激活=%d/12 漏=%d" % [idx, String(st.end_reason),
			int(st.round_index), prev_act.count(true), miss_rules])
	if miss_rules > 0:
		for t in trace:
			print("   ", t)
	arena.queue_free()
	await get_tree().process_frame
	return miss_rules > 0
