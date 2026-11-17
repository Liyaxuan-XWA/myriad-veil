extends Node
## 快速模式第三档相机（票 005）
##
## 三档不是"三个缩放数"，是三套**屏幕预算**：
##   常规档 有卡要点 ⇒ 让出完整上下带 + 右侧手牌列
##   看盘档 无事可做 ⇒ 带子收窄、手牌收掉
##   快速档 整个终局都无事可做 ⇒ 带子再压、阶段提示搬到操作带、倒计时让位到右侧
## 期望值全部独立算出（1280×720 手算 + 几何封顶 vs.y/1560），不拿实现反推。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_camera.tscn -- --no-save

const VS := Vector2(1280.0, 720.0)
const BOARD := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX

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
	print("\n########## 快速模式第三档相机 · 票 005 ##########")
	_check_three_sizes()
	_check_within_geometry_ceiling()
	_check_mode_table()
	await _watch_band()
	await _quick_band_layout()
	await _normal_two_bands_unchanged()
	await _check_bands_on_screen()
	_check_tiers_hold_on_small_screens()
	_finish()


## ⑧ 三档缩放的**排序**必须在每一档视口下都成立 —— 这是"用尺度本身指示该看盘还是该点卡"
## 这个设计的唯一证法：如果小屏上快速档不再比看盘档大，引导就失效了，
## 而 1280×720 的绿灯完全看不出来（①② 只在那一个尺寸上量过绝对值）。
## 用纯函数 `_camera_fit` 传显式 vs，所以不需要 HUD、也不需要 await。
func _check_tiers_hold_on_small_screens() -> void:
	var a := _mk_arena()
	var sizes: Array = [Vector2(1920, 1080), Vector2(1280, 720), Vector2(1024, 600),
			Vector2(800, 480), Vector2(740, 360)]
	var bad: Array = []
	for vs in sizes:
		var v: Vector2 = vs
		var n := _fit_at(a, v, BOARD, MatchArena.TOP_BAND, MatchArena.BOTTOM_BAND,
				MatchArena.BOARD_OVERHANG, true)
		var w := _fit_at(a, v, BOARD, MatchArena.FOCUS_TOP_BAND, MatchArena.FOCUS_BOTTOM_BAND,
				MatchArena.FOCUS_OVERHANG, false)
		var q := _fit_at(a, v, BOARD, MatchArena.QUICK_TOP_BAND, MatchArena.QUICK_BOTTOM_BAND,
				MatchArena.QUICK_OVERHANG, false)
		var nw := float(n["board_w"])
		var ww := float(w["board_w"])
		var qw := float(q["board_w"])
		print("    %dx%d 三档棋盘 %.0f / %.0f / %.0f px" % [
			int(v.x), int(v.y), nw, ww, qw])
		if not (qw > ww and ww > nw):
			bad.append("%d×%d 档位不再递增 %.0f/%.0f/%.0f" % [int(v.x), int(v.y), nw, ww, qw])
		for f in [n, w, q]:
			var d: Dictionary = f
			if float(d["board_w"]) > v.x + 0.001:
				bad.append("%d×%d 宽 %.0f 出屏" % [int(v.x), int(v.y), float(d["board_w"])])
			if float(d["z"]) > v.y / BOARD.y + 0.0001:
				bad.append("%d×%d z=%.4f 越过高度封顶" % [int(v.x), int(v.y), float(d["z"])])
		# 可读性下限：再小卡牌脸就糊成一团，三档的共同底线
		if qw < 200.0:
			bad.append("%d×%d 快速档只有 %.0fpx，低于 200px 可读底线" % [
				int(v.x), int(v.y), qw])
	_check(bad.is_empty(), "⑧ 五档视口下三档仍递增、不出屏、不低于可读底线", str(bad))
	_free(a)


func _fit(arena: Node, top: float, bottom: float, ov: float, side: bool) -> Dictionary:
	return arena.call("_camera_fit", VS, BOARD, top, bottom, ov, side)


## ⑥ 用的是真对局实例的实际视口，不是写死的 1280×720。
func _fit_at(arena: Node, vs: Vector2, board_px: Vector2, top: float, bottom: float,
		ov: float, side: bool) -> Dictionary:
	return arena.call("_camera_fit", vs, board_px, top, bottom, ov, side)


## ① 三档棋盘像素：480 / 568 / 616（1280×720）。
func _check_three_sizes() -> void:
	var a := _mk_arena()
	var n := _fit(a, MatchArena.TOP_BAND, MatchArena.BOTTOM_BAND, MatchArena.BOARD_OVERHANG, true)
	var w := _fit(a, MatchArena.FOCUS_TOP_BAND, MatchArena.FOCUS_BOTTOM_BAND, MatchArena.FOCUS_OVERHANG, false)
	var q := _fit(a, MatchArena.QUICK_TOP_BAND, MatchArena.QUICK_BOTTOM_BAND, MatchArena.QUICK_OVERHANG, false)
	var got := [float(n["board_w"]), float(w["board_w"]), float(q["board_w"])]
	var want := [480.0, 568.0, 616.0]
	var bad: Array = []
	for i in 3:
		if absf(got[i] - want[i]) > 8.0:
			bad.append("第%d档=%.0f 应为 %.0f" % [i + 1, got[i], want[i]])
	_check(bad.is_empty(), "① 三档棋盘 480 / 568 / 616 px", str(bad))
	# 必须严格一档比一档大，否则第三档白加
	_check(got[2] > got[1] and got[1] > got[0], "① 三档严格递增", str(got))
	_free(a)


## ② 三档都不越几何封顶，宽度都不出屏。
func _check_within_geometry_ceiling() -> void:
	var a := _mk_arena()
	var ceiling := VS.y / BOARD.y
	var bad: Array = []
	for spec in [[MatchArena.TOP_BAND, MatchArena.BOTTOM_BAND, MatchArena.BOARD_OVERHANG, true],
			[MatchArena.FOCUS_TOP_BAND, MatchArena.FOCUS_BOTTOM_BAND, MatchArena.FOCUS_OVERHANG, false],
			[MatchArena.QUICK_TOP_BAND, MatchArena.QUICK_BOTTOM_BAND, MatchArena.QUICK_OVERHANG, false]]:
		var f := _fit(a, float(spec[0]), float(spec[1]), float(spec[2]), bool(spec[3]))
		var z := float(f["z"])
		if z > ceiling + 0.0001:
			bad.append("z=%.4f 越过封顶 %.4f" % [z, ceiling])
		if float(f["board_w"]) > VS.x + 0.001:
			bad.append("宽 %.0f 出屏" % float(f["board_w"]))
	_check(bad.is_empty(), "② 三档都不越高度封顶、宽度不出屏", str(bad))
	_free(a)


## ③ 档位判定表。快速档只在"快速模式 + 终局"出现，别的一律不许抢。
func _check_mode_table() -> void:
	var a := _mk_arena()
	var st := MatchState.new()
	a.set("_state", st)
	var cases: Array = [
		# [quick, phase, round_index, finished, 期望档位]
		[false, MatchState.Phase.PICK, 0, false, MatchArena.CAM_NORMAL],
		[false, MatchState.Phase.LOCK, 0, false, MatchArena.CAM_NORMAL],
		[false, MatchState.Phase.DEPLOY, 0, false, MatchArena.CAM_NORMAL],
		# 2026-11-10：普通模式 BATTLE 六轮**一律**放大，不再按奇偶 480↔568 来回跳
		[false, MatchState.Phase.BATTLE, 0, false, MatchArena.CAM_WATCH],
		[false, MatchState.Phase.BATTLE, 1, false, MatchArena.CAM_WATCH],
		[false, MatchState.Phase.BATTLE, 2, false, MatchArena.CAM_WATCH],
		[false, MatchState.Phase.BATTLE, 5, false, MatchArena.CAM_WATCH],
		[false, MatchState.Phase.FINAL, 6, false, MatchArena.CAM_NORMAL],
		[false, MatchState.Phase.OVER, 6, true, MatchArena.CAM_NORMAL],
		[true, MatchState.Phase.PICK, 0, false, MatchArena.CAM_NORMAL],
		[true, MatchState.Phase.DEPLOY, 0, false, MatchArena.CAM_NORMAL],
		# 反向守卫：快速模式的 BATTLE 仍看轮次（它的己方轮还留着手牌列）
		[true, MatchState.Phase.BATTLE, 0, false, MatchArena.CAM_NORMAL],
		[true, MatchState.Phase.BATTLE, 1, false, MatchArena.CAM_WATCH],
		[true, MatchState.Phase.FINAL, 6, false, MatchArena.CAM_QUICK],
		[true, MatchState.Phase.OVER, 6, true, MatchArena.CAM_NORMAL],
	]
	var bad: Array = []
	for c in cases:
		st.quick = bool(c[0])
		a.set("_quick", bool(c[0]))
		st.phase = int(c[1])
		st.round_index = int(c[2])
		a.set("_finished", bool(c[3]))
		var got: int = int(a.call("_camera_mode"))
		if got != int(c[4]):
			bad.append("quick=%s phase=%s round=%d ⇒ %d 应为 %d" % [
				str(c[0]), String(MatchState.PHASE_NAME[int(c[1])]), int(c[2]), got, int(c[4])])
	_check(bad.is_empty(), "③ 全组合的档位判定全对（普通 BATTLE 恒定 / 快速仍看轮次）", str(bad))
	_free(a)


## ④ 看盘档与快速档都必须收掉手牌列；常规档必须留著。
func _watch_band() -> void:
	var a := _mk_arena()
	var hs := ScrollContainer.new()
	a.set("_hand_scroll", hs)
	var st := MatchState.new()
	a.set("_state", st)
	var bad: Array = []
	for spec in [[MatchArena.CAM_NORMAL, true], [MatchArena.CAM_WATCH, false],
			[MatchArena.CAM_QUICK, false]]:
		a.set("_cam_mode", int(spec[0]))
		a.call("_apply_hand_visibility")
		if bool(hs.visible) != bool(spec[1]):
			bad.append("档%d visible=%s 应为 %s" % [int(spec[0]), str(hs.visible), str(spec[1])])
		var want_filter: int = int(Control.MOUSE_FILTER_PASS) if bool(spec[1]) \
				else int(Control.MOUSE_FILTER_IGNORE)
		if int(hs.mouse_filter) != want_filter:
			bad.append("档%d filter=%d 应为 %d" % [int(spec[0]), int(hs.mouse_filter), want_filter])
	_check(bad.is_empty(), "④ 三档的手牌列可见性与点击拦截都对", str(bad))
	hs.free()
	_free(a)


## ⑤ 快速档的几何契约：顶带压到 52px ⇒ 阶段提示必须搬到操作带，
## 倒计时必须让位到右侧且不压「设置」。
## ⚠ 不能把 phase 硬改成 FINAL：那样 12 张都没 spawned，`_tick_final` 第一帧
##   就发现"两边全灭"，当场 mutual_annihilation 结束 —— 要真驱动到终局。
func _quick_band_layout() -> void:
	var a := await _mk_quick_final()
	var st = a.get("_state")
	_check(st.phase == MatchState.Phase.FINAL, "⑤ 前置：真打到了快速终局", str(st.phase))
	var vs: Vector2 = get_tree().root.get_visible_rect().size
	var timer: Control = a.get("_timer_label")
	var prompt: Control = a.get("_prompt")
	var tr := timer.get_global_rect()
	_check(tr.position.x > vs.x * 0.45, "⑤ 快速档倒计时已搬到右半", "x=%.0f" % tr.position.x)
	_check(tr.end.x <= vs.x - 100.0, "⑤ 倒计时不压右上角「设置」", "右缘=%.0f" % tr.end.x)
	_check(tr.end.y <= MatchArena.QUICK_TOP_BAND + MatchArena.QUICK_OVERHANG + 2.0,
			"⑤ 倒计时整条都在棋盘上沿之上", "底边=%.0f 棋盘顶=%.0f" % [
				tr.end.y, MatchArena.QUICK_TOP_BAND + MatchArena.QUICK_OVERHANG])
	_check(prompt.get_parent() == a.get("_bottom_box"),
			"⑤ 阶段提示从顶带搬到了操作带", str(prompt.get_parent().name))
	_check(String(prompt.text).contains("快速模式"),
			"⑤ 快速终局读数写「快速模式」", String(prompt.text))
	_check(not String(prompt.text).contains("第 "),
			"⑤ 快速终局不出现「第 N 轮」（没有轮次）", String(prompt.text))
	await _teardown(a)


## ⑥ 反向判据：普通模式的"档位 → 缩放"映射没变。
## ⚠ 不能拿 1280×720 的绝对像素当期望值 —— 无头模式跑的是项目默认窗口尺寸。
##   绝对像素由 ①② 用显式 VS 守住，这里守的是**映射关系**，
##   所以用真对局实例（HUD 齐的），并且全程不 await —— 一 await 轮次就自己走掉了。
func _normal_two_bands_unchanged() -> void:
	var a := await _mk_normal()
	var vs: Vector2 = a.get_viewport().get_visible_rect().size
	var board_px := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX
	var normal := _fit_at(a, vs, board_px, MatchArena.TOP_BAND, MatchArena.BOTTOM_BAND,
			MatchArena.BOARD_OVERHANG, true)
	var watch := _fit_at(a, vs, board_px, MatchArena.FOCUS_TOP_BAND, MatchArena.FOCUS_BOTTOM_BAND,
			MatchArena.FOCUS_OVERHANG, false)
	var st = a.get("_state")
	var cam: Camera2D = a.get("_cam")
	var bad: Array = []
	# 2026-11-10：BATTLE 六轮都拿 watch 的 z（含己方轮 round=0），
	#   这里多铺几个轮次就是为了防止有人改回 `round_index % 2` 判据。
	for spec in [[MatchState.Phase.BATTLE, 0, MatchArena.CAM_WATCH, float(watch["z"])],
			[MatchState.Phase.BATTLE, 1, MatchArena.CAM_WATCH, float(watch["z"])],
			[MatchState.Phase.BATTLE, 4, MatchArena.CAM_WATCH, float(watch["z"])],
			[MatchState.Phase.BATTLE, 5, MatchArena.CAM_WATCH, float(watch["z"])],
			[MatchState.Phase.FINAL, 6, MatchArena.CAM_NORMAL, float(normal["z"])],
			[MatchState.Phase.PICK, 0, MatchArena.CAM_NORMAL, float(normal["z"])]]:
		st.phase = int(spec[0])
		st.round_index = int(spec[1])
		a.set("_cam_mode", int(a.call("_camera_mode")))
		a.call("_resolve_camera", vs)
		a.call("_apply_camera_now")
		if int(a.get("_cam_mode")) != int(spec[2]):
			bad.append("%s round=%d ⇒ 档=%d 应为 %d" % [
				String(MatchState.PHASE_NAME[int(spec[0])]), int(spec[1]),
				int(a.get("_cam_mode")), int(spec[2])])
		if absf(float(cam.zoom.x) - float(spec[3])) > 0.0001:
			bad.append("%s round=%d ⇒ z=%.4f 应为 %.4f" % [
				String(MatchState.PHASE_NAME[int(spec[0])]), int(spec[1]),
				float(cam.zoom.x), float(spec[3])])
	_check(bad.is_empty(), "⑥ 普通模式「阶段→档位→缩放」映射（BATTLE 恒定放大）", str(bad))
	# 非快速档：提示必须还住在顶带、倒计时必须回正中
	var prompt: Control = a.get("_prompt")
	_check(prompt.get_parent() == a.get("_top_box"),
			"⑥ 普通模式阶段提示仍在顶带", str(prompt.get_parent().name))
	var tr: Rect2 = (a.get("_timer_label") as Control).get_global_rect()
	_check(absf(tr.position.x + tr.size.x * 0.5 - vs.x * 0.5) < 8.0,
			"⑥ 普通模式倒计时仍在屏幕正中", "中心=%.0f / %.0f" % [
				tr.position.x + tr.size.x * 0.5, vs.x * 0.5])
	await _teardown(a)


## 裸实例：①〜④⑥ 调的都是纯函数，不需要 HUD 和真对局。
## 故意不入树 —— 一入树 `_ready` 就把整套 HUD 和一局比赛建起来了，慢且没必要。
## ⑦ 三档下两条 HUD 带都必须真的在屏内。
## 这条是**点名判据**：底带用 BOTTOM_WIDE 锚点（anchor top=1），
## offset_top 必须是负偏移；写成 vs.y - h 会把整条带推到屏幕外 636px，
## 而它的症状是"确认/锁牌/跳过全部点不到" —— probe_match_clicks 一次红 12 项，
## 谁都看不出是带子跑了。所以这里直接量全局矩形并喊出来。
func _check_bands_on_screen() -> void:
	var a := await _mk_normal()
	var vs: Vector2 = get_tree().root.get_visible_rect().size
	var top: Control = a.get("_top_band")
	var bot: Control = a.get("_bottom_band")
	var bar: Control = a.get("_action_bar")
	var bad: Array = []
	# ⚠ 先把帧驱动停掉：`tick()` 每帧跑 `_fit_camera()`，它会用**真实状态**重算档位，
	 #   把这里强设的档位覆盖回去（现象是"操作栏还亮着"，其实是档位被改回了常规）。
	var drv: Node = a.get_node_or_null("Driver")
	if drv != null:
		drv.set_process(false)
	for mode in [MatchArena.CAM_NORMAL, MatchArena.CAM_WATCH, MatchArena.CAM_QUICK]:
		a.set("_cam_mode", mode)
		a.call("_apply_band_layout")
		# ⚠ 必须等一帧：offset_top 改了，但 Control 的 size 要到下一次布局才重算，
		#   同帧量到的还是上一档的 62px（本项目"面板延后两三帧"同一条纪律）。
		await get_tree().process_frame
		await get_tree().process_frame
		var bt: Rect2 = bot.get_global_rect()
		var tp: Rect2 = top.get_global_rect()
		if bt.position.y < 0.0 or bt.end.y > vs.y + 1.0:
			bad.append("档%d 底带 y=%.0f~%.0f 出屏（视口高=%.0f）" % [mode, bt.position.y, bt.end.y, vs.y])
		if tp.position.y < -1.0 or tp.end.y > vs.y:
			bad.append("档%d 顶带 y=%.0f~%.0f 出屏" % [mode, tp.position.y, tp.end.y])
		# 快速档操作栏是**故意**收掉的（等待期没有操作可做），
		# 所以那里验"确实不可见"，其余两档验"按钮真的在屏内点得到"。
		if mode == MatchArena.CAM_QUICK:
			if bar.visible:
				bad.append("档%d 等待期操作栏还亮着" % mode)
		else:
			var br: Rect2 = bar.get_global_rect()
			if br.end.y > vs.y + 1.0 or br.position.y < 0.0:
				bad.append("档%d 按钮条 y=%.0f~%.0f 不在屏内 ⇒ 点不到" % [mode, br.position.y, br.end.y])
	_check(bad.is_empty(), "⑦ 三档的两条带与按钮条都真的在屏内", str(bad))
	if not bad.is_empty():
		# 红了就把底带内容的每一项打出来：PanelContainer 撑到子节点最小高度，
		# 不量就只会在这里瞎猜"是不是那颗按钮占的"。
		a.set("_cam_mode", MatchArena.CAM_QUICK)
		a.call("_apply_band_layout")
		var box: VBoxContainer = a.get("_bottom_box")
		print("    底带最小高=%.1f 实际=%.1f" % [
			(a.get("_bottom_band") as Control).get_combined_minimum_size().y,
			(a.get("_bottom_band") as Control).size.y])
		for ch in box.get_children():
			var cc := ch as Control
			print("    子节点 %-14s 可见=%s 最小=%.0fx%.0f 实际=%.0fx%.0f" % [
				String(cc.name), str(cc.visible), cc.get_combined_minimum_size().x,
				cc.get_combined_minimum_size().y, cc.size.x, cc.size.y])
		print("    底带 separation=%d" % box.get_theme_constant("separation"))
	await _teardown(a)


func _mk_arena() -> Node:
	return MatchArena.new()


func _free(a: Node) -> void:
	a.free()


## 真开一局**普通模式**（HUD 齐的），只等它把棋盘和两条带建起来，不推进玩法。
func _mk_normal() -> Node:
	CharacterData.match_quick_mode = false
	CharacterData.match_level_cleared = 4
	GameState.match_context = {"level": 5}
	var a: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	a.set("player_stage_timeout", 60.0)
	add_child(a)
	for i in 24:
		await get_tree().process_frame
	return a


## 真开一局快速模式并驱动到终局：交牌 → 摆满 6 张 → 开战。
## 只有"真到了 FINAL"才测得出快速档的 HUD 搬家，硬改 phase 会被终局判定当场判掉。
func _mk_quick_final() -> Node:
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = 4
	GameState.match_context = {"level": 5}
	var a: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	a.set("player_stage_timeout", 60.0)
	add_child(a)
	for i in 24:
		await get_tree().process_frame
	var st = a.get("_state")
	var ids: Array = []
	for i in MatchDB.DECK_SIZE:
		ids.append(String((st.legal_pool(0) as Array)[i]))
	st.apply_command({"t": "pick", "team": 0, "ids": ids})
	for n in MatchDB.DECK_SIZE:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		st.apply_command({"t": "deploy", "team": 0, "card": int(legal[0]), "cell": cells[0]})
	st.quick_start_battle()
	a.call("_refresh_stage")
	# 让 tick 把 spawn 事件排干、HUD 重算几帧，档位才会真的落到相机与两条带上
	for i in 12:
		await get_tree().process_frame
	return a


func _teardown(a: Node) -> void:
	a.queue_free()
	await get_tree().process_frame
	GameState.match_context = {}
	CharacterData.match_quick_mode = false


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
