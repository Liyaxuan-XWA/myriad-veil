extends Node
## 布阵**拖拽上场**回归（2026-11-04 用户：定阵时可以拖动卡牌上场，拖动时半透明跟随鼠标）
##
## 这条链路只能窗口化验：无头模式 Viewport 不给 GUI 派发合成鼠标事件，
## 拖拽、悬停、按下-移动-松开全部打空（见 [[panel-probe-timing]]）。
## 用法：godot --path . --resolution 1280x720 res://tools/probe_match_drag.tscn -- --no-save

const ARENA_SCENE := "res://scenes/match/match_arena.tscn"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _motion(at: Vector2, mask: int) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.button_mask = mask
	get_viewport().push_input(m)


func _press(at: Vector2) -> void:
	_motion(at, MOUSE_BUTTON_MASK_LEFT)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = at
	d.global_position = at
	get_viewport().push_input(d)


func _release(at: Vector2) -> void:
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	get_viewport().push_input(u)


## 一次完整拖拽：按下 → 分几步移动（每步过一帧，`_begin_drag` 是在 motion 回调里建的）
## → 在终点松开。返回终点，方便调用方接着检查。
func _drag(a: Vector2, b: Vector2, steps: int = 6) -> Vector2:
	_press(a)
	for s in steps:
		_motion(a.lerp(b, float(s + 1) / float(steps)), MOUSE_BUTTON_MASK_LEFT)
		await get_tree().process_frame
	_release(b)
	await get_tree().process_frame
	await get_tree().process_frame
	return b


func _click(at: Vector2) -> void:
	_motion(at, 0)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = at
	d.global_position = at
	get_viewport().push_input(d)
	await get_tree().process_frame
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	get_viewport().push_input(u)
	await get_tree().process_frame
	await get_tree().process_frame


func _hand_btn(arena: Node, i: int) -> Control:
	var hand: Node = arena.get("_hand")
	var n := 0
	for ch in hand.get_children():
		# ⚠ 必须跳过 queue_free 过的旧按钮：`_refresh_stage()` 重建手牌时旧按钮是
		#   **帧尾才真释放**，不过帧就数会把它们算进去 → 下标错位、拿到即将消失的按钮，
		#   再 `.get_global_rect()` 就炸在协程里，探针既不报错也不往下走（直接挂死）。
		if ch is Button and not (ch as Node).is_queued_for_deletion():
			if n == i:
				return ch as Control
			n += 1
	return null


## 按 cards 下标找手牌按钮：布阵手牌是按 legal_deploy 顺序铺的
func _hand_btn_of(arena: Node, st, card: int) -> Control:
	var idx := 0
	for li in st.legal_deploy(0):
		if int(li) == card:
			return _hand_btn(arena, idx)
		idx += 1
	return null


func _phase(arena: Node) -> String:
	var st = arena.get("_state")
	if st == null:
		return "?"
	return String(MatchState.PHASE_NAME.get(int(st.phase), "?"))


func _notice(arena: Node) -> String:
	var l: Label = arena.get("_notice")
	return "" if l == null else l.text


func _wait_phase(arena: Node, want: String, secs: float = 8.0) -> bool:
	var limit := int(secs * 60.0)
	for k in limit:
		if _phase(arena) == want:
			return true
		await get_tree().process_frame
	return _phase(arena) == want


## 等回到玩家布阵的手（最多 10 秒）
## ⚠ 轮到玩家是**规则层**当场翻转的，手牌要等对局层把 deploy 事件排掉才重铺，
##   所以判到 turn==0 之后还要再等两三帧，否则拿到的是上一手留下的空手牌。
func _wait_turn(st) -> void:
	for k in 600:
		if int(st.phase) != MatchState.Phase.DEPLOY or int(st.deploy_turn) == 0:
			break
		await get_tree().process_frame
	for k in 4:
		await get_tree().process_frame


## 棋盘格子 → 屏幕坐标
func _cell_screen(arena: Node, cell: Vector2i) -> Vector2:
	var world: Vector2 = MatchDB.cell_to_pos(cell)
	return (arena as CanvasItem).get_canvas_transform() * world


func _ready() -> void:
	print("\n########## 卡片自走棋 · 布阵拖拽上场 ##########")
	var vs := get_viewport().get_visible_rect().size
	_check(vs.x > 100.0 and vs.y > 100.0, "窗口化运行（无头下 GUI 收不到合成鼠标）", str(vs))

	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	# 超时给足：本探针要自己拖自己点，不能被"到点代选"抢先布阵
	arena.set("player_stage_timeout", 90.0)
	add_child(arena)
	for k in 3:
		await get_tree().process_frame
	var st = arena.get("_state")

	# ---- 走到布阵阶段（点 6 张 → 确认 → 锁两张）----
	for i in MatchDB.DECK_SIZE:
		await _click(_hand_btn(arena, i).get_global_rect().get_center())
	await _click((arena.get("_buttons") as Dictionary).get("confirm")
			.get_global_rect().get_center())
	_check(await _wait_phase(arena, "lock"), "进入锁定阶段", _phase(arena))
	var btns: Dictionary = arena.get("_buttons")
	await _click(_hand_btn(arena, 0).get_global_rect().get_center())
	await _click((btns.get("lock_down") as Control).get_global_rect().get_center())
	await _click(_hand_btn(arena, 1).get_global_rect().get_center())
	await _click((btns.get("lock_up") as Control).get_global_rect().get_center())
	_check(await _wait_phase(arena, "deploy"), "进入布阵阶段", _phase(arena))
	await _wait_turn(st)
	_check(int(st.phase) == MatchState.Phase.DEPLOY and int(st.deploy_turn) == 0,
			"轮到玩家布阵", "phase=%s turn=%d" % [_phase(arena), int(st.deploy_turn)])

	# ---- 1. 结构：每张布阵手牌都接了拖拽通道 ----
	var hand: Node = arena.get("_hand")
	var nb := 0
	var wired := 0
	for ch in hand.get_children():
		if not (ch is Button):
			continue
		nb += 1
		# 一条给视差转发、一条给拖拽
		if (ch as Button).get_signal_connection_list("gui_input").size() >= 2:
			wired += 1
	_check(nb >= 1 and wired == nb, "每张布阵手牌都接了拖拽（gui_input 两条连接）",
			"%d/%d 张" % [wired, nb])

	# ---- 2. 短按不算拖：仍走原来的点选 ----
	var b0 := _hand_btn(arena, 0)
	var p0: Vector2 = b0.get_global_rect().get_center()
	await _drag(p0, p0 + Vector2(6.0, 4.0), 2)
	_check(not bool(arena.get("_drag_active")),
			"移动不到阈值（%.0fpx）→ 不进入拖拽" % MatchArena.DRAG_START_PX,
			"active=%s" % str(arena.get("_drag_active")))
	_check(arena.get("_drag_ghost") == null, "短按不会凭空造出一张跟手的牌")
	_check(int(arena.get("_sel_card")) >= 0, "短按仍然选中这张（点选路径没被拖拽吃掉）",
			"sel=%d" % int(arena.get("_sel_card")))

	# ---- 3. 真拖：半透明牌出现并跟着鼠标 ----
	var legal: Array = st.legal_deploy(0)
	var card := int(legal[0])
	var src := _hand_btn_of(arena, st, card)
	_check(src != null, "能找到那张要拖的手牌按钮", "card=%d" % card)
	if src == null:
		_finish()
		return
	var from: Vector2 = src.get_global_rect().get_center()
	var free: Array = MatchState.free_cells(st.occupied_cells())
	var target := Vector2i(free[0] as Vector2i)
	var to := _cell_screen(arena, target)
	var mid := from + Vector2(40.0, 0.0)
	_press(from)
	_motion(mid, MOUSE_BUTTON_MASK_LEFT)
	await get_tree().process_frame
	var ghost: Control = arena.get("_drag_ghost")
	_check(bool(arena.get("_drag_active")) and ghost != null,
			"走过阈值后进入拖拽、手里出现跟随的牌", "ghost=%s" % str(ghost != null))
	if ghost != null:
		_check(ghost.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"手里那张牌不吃输入（IGNORE）—— 否则它自己会把松开事件吞掉",
				"filter=%d" % ghost.mouse_filter)
		_check(ghost.modulate.a > 0.3 and ghost.modulate.a < 0.8,
				"跟随的牌是半透明的", "alpha=%.2f" % ghost.modulate.a)
		var center := ghost.position + ghost.size * 0.5
		_check(center.distance_to(mid) <= 2.0, "牌的中心对准鼠标（不是左上角压在上面）",
				"中心=%s 鼠标=%s" % [center, mid])
	_check(src.modulate.a < 0.9, "源牌压暗：看得出「这张被我拿起来了」",
			"a=%.2f" % src.modulate.a)

	# ---- 4. 目标格高亮跟着走 ----
	_motion(to, MOUSE_BUTTON_MASK_LEFT)
	await get_tree().process_frame
	# 顺手存一张：拖拽这种"看着才对"的东西，光有断言不够，得能亲眼看见
	# 半透明牌压在格子上是什么效果（等一帧真实绘制，见 [[panel-probe-timing]] 第 8 条）
	for k3 in 3:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img != null:
		print("SHOT  output/match_drag_ghost.png err=", img.save_png("output/match_drag_ghost.png"))
	var hint: Node = arena.get("_cell_hint")
	_check(Vector2i(hint.get("_hover")) == target,
			"拖到空格上时那一格单独点亮", "hover=%s 期望=%s" % [hint.get("_hover"), target])
	_check(ghost != null and absf(ghost.modulate.a - MatchArena.DRAG_ALPHA) < 0.01
			and ghost.modulate.r > 0.95,
			"落在合法空格 → 手里的牌是亮的（松手就会落）",
			"mod=%s" % (Color(0, 0, 0, 0) if ghost == null else ghost.modulate))

	# ---- 5. 松手落子 ----
	var dep0 := int(st.deployed_count())
	_release(to)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(int(st.deployed_count()) == dep0 + 1, "松手真的落子（且只落一次）",
			"%d → %d" % [dep0, int(st.deployed_count())])
	var placed := false
	for cd in st.cards:
		if bool(cd["deployed"]) and Vector2i(cd["cell"]) == target:
			placed = true
	_check(placed, "落到了拖过去那一格", "cell=%s" % target)
	_check(arena.get("_drag_ghost") == null, "松手后手里那张牌收掉了")
	_check(Vector2i(hint.get("_hover")) == Vector2i(-1, -1), "松手后目标格高亮清掉")
	_check(_notice(arena).contains("已落到"), "落子给一句话回执", "「%s」" % _notice(arena))

	# ---- 6. 拖到棋盘外 = 取消，牌回到手里 ----
	await _wait_turn(st)
	legal = st.legal_deploy(0)
	if legal.is_empty():
		_check(false, "还有可拖的牌（第 6 段前置）", "legal_deploy 空")
	else:
		var card2 := int(legal[0])
		var src2 := _hand_btn_of(arena, st, card2)
		_check(src2 != null, "第 6 段找得到要拖的按钮", "card=%d" % card2)
		if src2 != null:
			var from2: Vector2 = src2.get_global_rect().get_center()
			var outside := Vector2(vs.x * 0.5, 30.0)     # 顶部读数带里，肯定不在棋盘上
			var dep1 := int(st.deployed_count())
			_press(from2)
			_motion(from2 + Vector2(40.0, 0.0), MOUSE_BUTTON_MASK_LEFT)
			await get_tree().process_frame
			_motion(outside, MOUSE_BUTTON_MASK_LEFT)
			await get_tree().process_frame
			var g3: Control = arena.get("_drag_ghost")
			_check(g3 != null and g3.modulate.r < 0.85,
					"落在棋盘外 → 手里的牌压暗发灰（松手也落不了）",
					"mod=%s" % (Color(0, 0, 0, 0) if g3 == null else g3.modulate))
			_release(outside)
			await get_tree().process_frame
			await get_tree().process_frame
			_check(int(st.deployed_count()) == dep1, "松在棋盘外 → 不落子",
					"%d → %d" % [dep1, int(st.deployed_count())])
			_check(_notice(arena).contains("取消"), "取消也给回执", "「%s」" % _notice(arena))
			_check(int(arena.get("_sel_card")) == card2,
					"取消后这张仍是选中态（点格子也能落，不用重选）",
					"sel=%d 期望=%d" % [int(arena.get("_sel_card")), card2])
			_check(arena.get("_drag_ghost") == null, "取消后手里那张牌也收掉了")

	# ---- 7. 拖到已被占的格子上 = 取消 ----
	await _wait_turn(st)
	legal = st.legal_deploy(0)
	if not legal.is_empty():
		var card3 := int(legal[0])
		var src3 := _hand_btn_of(arena, st, card3)
		if src3 != null:
			var from3: Vector2 = src3.get_global_rect().get_center()
			var taken := Vector2i(-1, -1)
			for cd2 in st.cards:
				if bool(cd2["deployed"]):
					taken = Vector2i(cd2["cell"])
					break
			var dep2 := int(st.deployed_count())
			await _drag(from3, _cell_screen(arena, taken), 6)
			_check(int(st.deployed_count()) == dep2, "已占的格子不落子（拖过去也不会覆盖）",
					"%d → %d" % [dep2, int(st.deployed_count())])

	# ---- 8. 拖动期间不许被「到点代选」抢走 ----
	await _wait_turn(st)
	legal = st.legal_deploy(0)
	if not legal.is_empty():
		arena.set("player_stage_timeout", 0.4)
		arena.set("_stage_timer", 0.3)
		var card4 := int(legal[0])
		var src4 := _hand_btn_of(arena, st, card4)
		if src4 != null:
			var from4: Vector2 = src4.get_global_rect().get_center()
			var dep3 := int(st.deployed_count())
			_press(from4)
			_motion(from4 + Vector2(60.0, 0.0), MOUSE_BUTTON_MASK_LEFT)
			for k2 in 40:
				await get_tree().process_frame
			_check(bool(arena.get("_drag_active")), "拖住 0.7 秒之后仍在拖（计时被按住）",
					"active=%s" % str(arena.get("_drag_active")))
			_check(int(st.deployed_count()) == dep3,
					"拖动期间没有被「到点代选」抢先布掉",
					"%d → %d" % [dep3, int(st.deployed_count())])
			_release(from4 + Vector2(60.0, 0.0))
			await get_tree().process_frame
			await get_tree().process_frame
			_check(arena.get("_drag_ghost") == null, "收尾后 ghost 一定被清掉")

	_finish()


## 中途拿不到按钮也要正常收尾：探针最怕的不是红，是**不退出**
func _finish() -> void:
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(1 if not _fails.is_empty() else 0)
