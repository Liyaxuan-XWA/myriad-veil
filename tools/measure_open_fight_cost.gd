extends Node
## 「开战」那一帧到底多贵 —— 预载前 / 预载后的同进程对照
##
## 同一条产品代码、同一个场景、同一副卡组，跑两遍：
##   A 摆完立刻点「开战」（预载刚点火，资源还在工作线程上）
##   B 等到预载队列排空再点（棋子该读的东西都已经在内存里）
## 差别就是这次优化买到的东西。帧周期用 process_frame 之间的真实间隔量，
## 不是 `_process` 的 delta（后者会被引擎的 time_scale 与卡顿补偿影响）。
##
## 用法：godot --path . --windowed --resolution 1280x720 res://tools/measure_open_fight_cost.tscn -- --no-save

const SAMPLE_FRAMES := 14


func _ready() -> void:
	print("\n########## 开战那一帧：预载前 / 预载后 ##########")
	await _case("A 没有预热（点下去时资源还在路上）", false)
	await _case("B 预热完成（落子时就已线程预载）", true)
	get_tree().quit(0)


func _case(label: String, wait_warm: bool) -> void:
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

	if wait_warm:
		var w := 0
		while SkinWarm.is_busy() and w < 600:
			await get_tree().process_frame
			w += 1
		print("  预热等待 %d 帧（这一段的解码在**工作线程**，主线程照常出帧）" % w)

	var btns: Dictionary = arena.get("_buttons")
	var fight: Button = btns.get("fight")
	print("\n── %s ──" % label)
	if fight == null or fight.disabled:
		print("  ⚠ 「开战」点不了，跳过")
		arena.queue_free()
		await get_tree().process_frame
		return
	var prev := Time.get_ticks_usec()
	fight.pressed.emit()
	var periods: Array = []
	var counts: Array = []
	for i in SAMPLE_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		periods.append(float(now - prev) / 1000.0)
		prev = now
		counts.append((arena.get("_pieces") as Node).get_child_count())
	var worst := 0.0
	var total := 0.0
	for p in periods:
		worst = maxf(worst, float(p))
		total += float(p)
	var peak_before := 0
	for c in counts:
		peak_before = maxi(peak_before, int(c))
	print("  帧周期(ms) = %s" % str(_round(periods)))
	print("  最坏一帧 = %.1f ms（预算 16.7）  前 4 帧合计 = %.1f ms" % [worst, _sum4(periods)])
	print("  落场进度 = %s" % str(counts))
	print("  纹理显存 = %.1f MB" % (float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0))
	arena.queue_free()
	for i in 3:
		await get_tree().process_frame


func _round(list: Array) -> Array:
	var out: Array = []
	for v in list:
		out.append(roundf(float(v) * 10.0) / 10.0)
	return out


func _sum4(list: Array) -> float:
	var t := 0.0
	for i in mini(4, list.size()):
		t += float(list[i])
	return t
