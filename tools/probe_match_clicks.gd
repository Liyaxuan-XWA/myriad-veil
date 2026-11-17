extends Node
## 对局**点击链路**回归（2026-11-03 用户报「布阵时选不了牌也点不了格子」）
##
## 规则层探针喂的是 `apply_command()`，入口探针也只验到"阶段跑到了"，
## 所以**鼠标到底能不能落到控件/格子上**一直没人守 —— HUD 改成整屏浮层之后，
## 一个 `mouse_filter` 设错就会让选牌和落子同时死掉，而所有探针照样全绿。
##
## ⚠ 必须**窗口化**跑，不能 --headless：无头模式 Viewport 不给 GUI 派发合成鼠标事件，
##   三种 filter 全都"按钮收不到、世界收得到"，会把结论彻底带偏（实测过）。
## 用法：godot --path . --resolution 1280x720 res://tools/probe_match_clicks.tscn -- --no-save

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


func _click(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	get_viewport().push_input(m)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = at
	d.global_position = at
	get_viewport().push_input(d)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	get_viewport().push_input(u)
	# 按下与抬起之间也要过帧：Button 的 pressed 在 release 时发，
	# 而 _refresh_stage() 里旧按钮是 queue_free（帧尾才真释放），不过帧就会拿到旧节点
	await get_tree().process_frame
	await get_tree().process_frame


func _click_control(c: Control, label: String) -> void:
	if c == null:
		_check(false, label + " 存在", "拿到 null")
		return
	var r := c.get_global_rect()
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		_check(false, label + " 有可点的尺寸", "rect=" + str(r))
		return
	await _click(r.get_center())


## 手牌里第 i 张卡面按钮。⚠ 每次 _refresh_stage 都会重建，必须现取现点
func _hand_btn(arena: Node, i: int) -> Control:
	var hand: Node = arena.get("_hand")
	if hand == null or i >= hand.get_child_count():
		return null
	return hand.get_child(i) as Control


func _phase(arena: Node) -> String:
	var st = arena.get("_state")
	if st == null:
		return "?"
	return String(MatchState.PHASE_NAME.get(int(st.phase), "?"))


## 等阶段真的推进过去。⚠ 不能点完就断言：双方都提交完规则层才换阶段，
## 而 AI 是 `AI_ACT_DELAY=0.55s` 之后才动手的，探针里点得再快也得等它。
func _wait_phase(arena: Node, want: String, secs: float = 4.0) -> bool:
	for i in int(secs * 60.0):
		await get_tree().physics_frame
		if _phase(arena) == want:
			# ⚠ `st.phase` 先变、`phase` 事件晚一帧才 drain，而 _refresh_stage 会
			#   queue_free 掉整排手牌重建。不等就取按钮会拿到**上一阶段的旧按钮**
			#   （它的回调写的是 _sel_boss，于是 sel_card 永远 -1，看着像产品的锅）。
			for k in 4:
				await get_tree().physics_frame
			return true
	return false


func _notice(arena: Node) -> String:
	var l: Label = arena.get("_notice")
	return l.text if l != null else ""


func _ready() -> void:
	print("\n########## 卡片自走棋 · 点击链路 ##########")
	var vs := get_viewport().get_visible_rect().size
	_check(vs.x > 100.0 and vs.y > 100.0, "窗口化运行（无头下 GUI 收不到合成点击）", str(vs))
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	# 超时给足：本探针要自己点，不能被代打抢先推进
	arena.set("player_stage_timeout", 90.0)
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var st = arena.get("_state")
	_check(_phase(arena) == "pick", "开局停在选牌阶段", _phase(arena))

	# ---- 1. 点卡面按钮选牌 ----
	_check(_hand_btn(arena, 0) != null, "选牌阶段手牌铺出了卡面按钮",
			"n=%d" % (arena.get("_hand") as Node).get_child_count())
	for i in MatchDB.DECK_SIZE:
		await _click_control(_hand_btn(arena, i), "选牌卡面#%d" % i)
	_check((arena.get("_picked") as Array).size() == MatchDB.DECK_SIZE,
			"点满 6 张卡面（HUD 没有吞掉按钮的点击）",
			"picked=%d" % (arena.get("_picked") as Array).size())

	# ---- 2. 点「确认选牌」 ----
	var btns: Dictionary = arena.get("_buttons")
	await _click_control(btns.get("confirm") as Control, "确认选牌")
	await _wait_phase(arena, "lock")
	_check(_phase(arena) == "lock", "点确认后进入锁定阶段", _phase(arena))

	# ---- 3. 锁定：点卡与按锁都必须立刻有反馈 ----
	await _click_control(_hand_btn(arena, 0), "锁定卡面#0")
	_check(int(arena.get("_sel_card")) >= 0, "点卡面立刻记下选中的是哪张",
			"sel_card=%d" % int(arena.get("_sel_card")))
	_check(_notice(arena) != "", "点卡面给出一句话回执", "「%s」" % _notice(arena))
	var sel_btn := _hand_btn(arena, int(arena.get("_sel_card")))
	_check(sel_btn != null and sel_btn.modulate != Color.WHITE,
			"选中的卡面被提亮（回执不只是文字，牌面本身要变）")
	# 提亮在本来就发白的卡面上几乎看不见，所以还有一圈金框。
	# ⚠ 金框现在挂在按钮的 stack 子树里（卡面改成 CardFace 后多了一层），
	#   所以按名字在整棵子树里找，而不是只数按钮的直接子节点。
	var framed := false
	if sel_btn != null:
		var f := sel_btn.find_child("SelectFrame", true, false)
		if f is Panel:
			var sb := (f as Panel).get_theme_stylebox("panel") as StyleBoxFlat
			framed = sb != null and sb.border_width_left >= 3
	_check(framed, "选中的卡面带一圈金框（只提亮会被看成「没反应」）")
	# 没选牌就按锁：不许静默失败
	arena.set("_sel_card", -1)
	arena.set("_lock_down", -1)
	await _click_control(btns.get("lock_down") as Control, "空选时按锁反面")
	_check(int(arena.get("_lock_down")) < 0, "没选牌时按锁不会落槽")
	_check(_notice(arena).contains("先点一张牌"), "空选按锁给明确提示", "「%s」" % _notice(arena))
	await _click_control(_hand_btn(arena, 0), "锁定卡面#0")
	await _click_control(btns.get("lock_down") as Control, "锁反面")
	var bd: Button = btns.get("lock_down")
	_check(int(arena.get("_lock_down")) >= 0, "锁反面生效",
			"down=%d" % int(arena.get("_lock_down")))
	_check(bd.text.contains("已锁") and bd.disabled,
			"填过的锁键变成「已锁 ✓」并禁用（不然不知道还差哪一格）",
			"text=%s disabled=%s" % [bd.text, bd.disabled])
	_check(_notice(arena).contains("已锁反面"), "锁反面有回执", "「%s」" % _notice(arena))
	# 同一张牌不能既锁正又锁反，且必须说清为什么
	await _click_control(btns.get("lock_up") as Control, "同一张按锁正面")
	_check(int(arena.get("_lock_up")) < 0, "同一张牌不许重复锁",
			"up=%d" % int(arena.get("_lock_up")))
	_check(_notice(arena).contains("已经锁成"), "重复锁给明确提示", "「%s」" % _notice(arena))
	await _click_control(_hand_btn(arena, 1), "锁定卡面#1")
	await _click_control(btns.get("lock_up") as Control, "锁正面")
	_check(int(arena.get("_lock_up")) >= 0, "锁正面生效",
			"up=%d" % int(arena.get("_lock_up")))
	await _wait_phase(arena, "deploy")
	_check(_phase(arena) == "deploy", "锁完两张进入布阵", _phase(arena))

	# ---- 4. 布阵：点手牌选一张，再点棋盘上的格子 ----
	for guard in 40:
		if int(st.deploy_turn) == 0:
			break
		await _click_control(btns.get("skip") as Control, "跳过")
	_check(int(st.deploy_turn) == 0, "等到我方布阵回合", "turn=%d" % int(st.deploy_turn))
	await _click_control(_hand_btn(arena, 0), "布阵手牌#0")
	var sel := int(arena.get("_sel_card"))
	_check(sel >= 0, "点手牌真的选中了一张可落子的牌", "sel_card=%d" % sel)
	# 手牌每次换阶段都会重建，而 `phase` 事件比 `st.phase` 晚到一帧。
	# 旧写法在每次重建开头都无脑清一次选择 → 玩家刚点中的牌会被"迟到的换阶段"抹掉。
	arena.call("_refresh_stage")
	_check(int(arena.get("_sel_card")) == sel,
			"重建手牌（模拟迟到的换阶段刷新）不会抹掉刚选中的那张",
			"sel_card=%d" % int(arena.get("_sel_card")))
	var cell := Vector2i(2, 3)
	var world := MatchDB.cell_to_pos(cell)
	var screen: Vector2 = arena.get_canvas_transform() * world
	await _click(screen)
	var done := sel >= 0 and bool(st.cards[sel]["deployed"])
	_check(done, "点棋盘格子完成了落子（_unhandled_input 没被 HUD 吃掉）",
			"sel=%d deployed=%s" % [sel, bool(st.cards[sel]["deployed"]) if sel >= 0 else "-"])

	# ---- 5. filter 口径：整屏浮层必须 PASS，不能 STOP ----
	var root: Control = arena.get("_hud_root")
	_check(root.mouse_filter == Control.MOUSE_FILTER_PASS,
			"HUD 根节点 = PASS（STOP 会让浮层空处底下的棋盘收不到点击）",
			"filter=%d" % root.mouse_filter)
	var hs: Control = arena.get("_hand_scroll")
	_check(hs.mouse_filter == Control.MOUSE_FILTER_PASS, "手牌面板 = PASS",
			"filter=%d" % hs.mouse_filter)
	# 2026-11-04 起提示行是**通宽居中**放在顶部读数带里的，不再受手牌面板左边界约束。
	# 新的不变量有两条：① autowrap 仍要有明确宽度才生效；
	# ② 提示行与手牌面板都不得压住棋盘（棋盘被让出两条带才成立，见 _fit_camera）。
	var pl: Label = arena.get("_prompt")
	# ⚠ 别再 `var vs :=` 一次：本函数第 99 行已经声明过同名变量，
	#   GDScript 的同作用域重名是**解析错误**，整个脚本加载失败 → 窗口挂着不动，
	#   探针一条都不跑（这条已经踩过好几次了）。
	_check(pl.autowrap_mode != TextServer.AUTOWRAP_OFF
			and pl.custom_minimum_size.x > 100.0,
			"提示行有明确换行宽度（不会被截成半句）",
			"wrap=%d 宽=%.0f" % [pl.autowrap_mode, pl.custom_minimum_size.x])
	var band := arena.get("_top_band") as Control
	var bb := arena.get("_bottom_band") as Control
	_check(band != null and bb != null and band.size.y <= MatchArena.TOP_BAND + 1.0
			and bb.position.y >= vs.y - MatchArena.BOTTOM_BAND - 1.0,
			"两条 HUD 带各自占高正确（棋盘让出的就是这两条）",
			"顶带高=%.0f 底带顶=%.0f 视口高=%.0f" % [band.size.y, bb.position.y, vs.y])
	# 棋盘屏上高度必须正好落在两条带之间，且占满可用带（不留空边）
	var cam: Camera2D = arena.get("_cam")
	var board := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX * cam.zoom.x
	var usable := vs.y - MatchArena.TOP_BAND - MatchArena.BOTTOM_BAND \
			- MatchArena.BOARD_OVERHANG * 2.0
	_check(board.y <= usable + 1.0 and board.y >= usable * 0.99,
			"棋盘既不压 HUD 带、也没浪费可用带", "屏上高=%.0f 可用=%.0f" % [board.y, usable])
	# 手牌面板不许与顶带/底带重叠（否则第一张牌又钻到倒计时底下）
	_check(hs.position.y >= MatchArena.TOP_BAND - 0.5
			and hs.position.y + hs.size.y <= vs.y - MatchArena.BOTTOM_BAND + 1.0,
			"手牌面板完整落在两条带之间",
			"面板 y %.0f~%.0f" % [hs.position.y, hs.position.y + hs.size.y])
	# 顶部三条读数互不重叠，且都不许钻到右上角「设置」底下。
	# ⚠ 这一组只有**窗口化**才测得出来：无头探针里 label 的 size 一直是 0，
	#   上一版"注额 50（有效 50）　可选 4"后半截被设置按钮吃掉，是靠肉眼看截图才发现的。
	var note: Label = arena.get("_note_label")
	var score: Label = arena.get("_score_label")
	var timer: Label = arena.get("_timer_label")
	var sbtn: Control = SettingsUI.get("_btn") as Control
	var nr := note.get_global_rect()
	var tr := timer.get_global_rect()
	var sr := score.get_global_rect()
	var br := sbtn.get_global_rect()
	_check(nr.end.x <= br.position.x + 0.5,
			"注额读数右边界让开「设置」按钮（后半截不被吃掉）",
			"注额右=%.0f 设置左=%.0f" % [nr.end.x, br.position.x])
	_check(nr.position.x >= tr.end.x - 1.0,
			"注额读数不压倒计时框", "倒计时右=%.0f 注额左=%.0f" % [tr.end.x, nr.position.x])
	_check(sr.end.x <= tr.position.x + 1.0,
			"存活读数不压倒计时框", "存活右=%.0f 倒计时左=%.0f" % [sr.end.x, tr.position.x])

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(1 if not _fails.is_empty() else 0)
