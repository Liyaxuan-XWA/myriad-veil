extends Node
## 截对局界面：选牌 / 锁定 / 布阵 / 对战 / 清场各一张，看的是"卡面到底画没画出来"。
## 用法：godot --path . --resolution 1280x720 res://tools/shot_match_board.tscn -- --no-save
##
## ⚠ 每按一次阶段都要先等两三帧：HUD 是 Container 树，
##   `_refresh_stage()` 里新建的按钮当帧 size 还是 (0,0)，容器排序在帧尾才跑，
##   不等就直接抓图会得到一张"手牌区空白"的截图（上一版就栽在这）。

const PHASES := ["pick", "lock", "deploy", "battle", "final", "over"]

var _arena: Node
var _shot := {}
## 真实绘制过的帧数。窗口被别的程序完全挡住时，Windows 不再要求present，
## 引擎也就不重绘 —— 于是 `get_texture().get_image()` 连着几张抓出来是**同一帧**
## （2026-11-04 实测：battle_opp / battle_own / final / over 四张 md5 完全相同）。
## 所以每次抓图前必须等到这个数真的涨过。
var _post_draws := 0


func _ready() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	# ⚠ Window 上没有 move_to_front()，DisplayServer 在这个版本也不能这样静态调用
	#   （`Static function not found` 是**解析错**：脚本整个不加载、工具零输出挂死）。
	#   只留 always_on_top 就够把窗口从遮挡里拉出来。
	var win := get_window()
	if win != null:
		win.always_on_top = true
	_arena = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	# 选牌给 8 秒足够截图；其余阶段压到 0.3 秒让整局自己走完
	_arena.set("player_stage_timeout", 8.0)
	add_child(_arena)
	for guard in 30000:
		await get_tree().physics_frame
		var st = _arena.get("_state")
		if st == null:
			continue
		# 节奏是 10 秒选牌 + 20 秒战斗（2026-11-03 用户延长），一整局 180 秒起。
		# 截图工具不能为每个阶段等三分钟 —— 把窗口计时压到 0，
		# 让规则层走它自己的正常路径（到点代选 / 收轮 / 终局判定），不另写一套逻辑。
		var ph := int(st.phase)
		var pname := String(MatchState.PHASE_NAME.get(ph, "?"))
		# 激活窗口要拍**两个朝向**：己方轮（敌方牌压灰、己方牌呼吸）和对方轮
		# （规则层让玩家替对方挑进场时机，所以灯在敌方牌上）。只拍一张看不出串台。
		var key := pname
		if pname == "battle":
			key = "battle_own" if bool(st.is_own_round()) else "battle_opp"
		# 压节奏：开打的 8 秒和终局压成 0，一整局不用等三分钟。
		# ⚠ 但「激活选牌窗口」（battle 且没开打）**不许压** —— 用户要看的就是这一段的
		#   呼吸灯与灰纱，压成 0 等于每帧自动代选，窗口根本截不到（上一版只截到开打后）。
		var in_pick_window := ph == MatchState.Phase.BATTLE and not bool(st.fighting())
		var battle_pending := not bool(_shot.get("battle_own", false)) \
				or not bool(_shot.get("battle_opp", false))
		if (ph == MatchState.Phase.BATTLE or ph == MatchState.Phase.FINAL) \
				and not (in_pick_window and battle_pending):
			st.timer = 0.0
		if not PHASES.has(pname) or bool(_shot.get(key, false)):
			continue
		if pname == "battle":
			# 对战要场上真有棋子才有看点，否则截到的是空棋盘
			var pieces: Node = _arena.get_node_or_null("Pieces")
			if pieces == null or pieces.get_child_count() < 2:
				continue
			# 只认激活窗口：开打的时候整场是中性态（没有灯也没有灰纱），拍不到要点的东西
			if not in_pick_window:
				continue
			# 窗口里把手牌超时抬起来，否则 0.3 秒就到点代选，等不到抓图
			_arena.set("player_stage_timeout", 6.0)
			_arena.set("_stage_timer", 6.0)
		_shot[key] = true
		if pname == "pick":
			_pick_some()
		if pname == "deploy":
			# 布阵要拍出"选中一张之后空格亮呼吸框"这一层：不选牌等于什么都没演示，
			# 而这条正是用户要的"该点哪儿一眼看得见"
			_select_one_deploy()
		if pname == "lock":
			# 锁正反面要拍出"按下去有反应"的样子：选中一张 + 已锁一张 + 回执
			_arena.set("_sel_card", 1)
			_arena.set("_lock_down", 0)
			_arena.call("_refresh_stage")
			_arena.call("_set_notice", "赫连霄 → 已锁反面（藏起来，轮到系统翻）")
		# 除选牌/布阵外把窗口压到 0.3 秒，让整局自己走完。
		# ⚠ 布阵要留 8 秒：压成 0.3 之后截图里顶部倒计时永远是红的"0"，
		#   看着像 bug，其实是工具自己压的。
		if pname != "pick" and pname != "deploy":
			_arena.set("player_stage_timeout", 0.3)
		if pname == "over":
			# 结算面板是 _settle() 里才弹出来的，等它真的可见再拍
			for k in 60:
				await get_tree().process_frame
				var r = _arena.get("_result")
				if r != null and bool(r.visible):
					break
			var res = _arena.get("_result")
			print("DIAG[over] visible=", res.visible, " size=", res.size,
					" pos=", res.global_position, " minsize=", res.get_combined_minimum_size(),
					" deck=", (_arena.get("_result_deck") as Node).get_child_count())
		for k in 6:
			await get_tree().process_frame
		_diag(key)
		_grab("output/match_ui_%s.png" % key)
		# battle 拆成 own/opp 两张，所以比 PHASES 多一个
		if _shot.size() >= PHASES.size() + 1:
			break
	print("SHOTS ", _shot.keys())
	get_tree().quit(0)


## 选牌阶段替玩家点三张，截出来才看得见"已选"角标和提亮
func _pick_some() -> void:
	var pool: Array = _arena.get("_pool")
	var picked: Array = []
	for i in mini(3, pool.size()):
		picked.append(String(pool[i]))
	_arena.set("_picked", picked)
	_arena.call("_refresh_stage")


## 布阵阶段替玩家选中第一张合法牌：只有选中之后棋盘才标出可落空格
func _select_one_deploy() -> void:
	var st = _arena.get("_state")
	_arena.set("player_stage_timeout", 8.0)
	_arena.set("_stage_timer", 8.0)
	var legal: Array = st.legal_deploy(0)     # 0 = 玩家队
	if legal.is_empty():
		return
	var idx := int(legal[0])
	_arena.set("_sel_card", idx)
	_arena.call("_refresh_stage")
	var nm: String = _arena.call("_boss_name", String(st.cards[idx]["boss_id"]))
	_arena.call("_set_notice", "已选 %s —— 点一个发亮的空格落子" % nm)


func _diag(pname: String) -> void:
	var root: Control = _arena.get("_hud_root")
	var sc: Control = _arena.get("_hand_scroll")
	var hand: Control = _arena.get("_hand")
	var n := hand.get_child_count()
	var first := "?"
	if n > 0:
		var b := hand.get_child(0) as Control
		first = "size=%s tex=%s" % [b.size, _tex_of(b)]
	var cam: Camera2D = _arena.get("_cam")
	var vp := _arena.get_viewport()
	var vs := Vector2.ZERO if vp == null else vp.get_visible_rect().size
	var board := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX * cam.zoom.x
	print("DIAG[", pname, "] 视口=", vs, " 棋盘屏上=", board, " cam=", cam.position,
			" 手牌面板=", sc.position, "x", sc.size,
			" 卡面数=", n, " 第一张: ", first)
	if pname == "deploy" or pname.begins_with("battle"):
		_diag_tokens()


func _tex_of(node: Control) -> String:
	# 卡面现在是 CardFace（子树深度随卡种变），不能再按「第 2 层有没有 TextureRect」数
	for ch in node.get_children():
		for g in ch.get_children():
			if g is CardFace:
				return "CardFace kind=%s size=%s" % [g.kind(), g.size]
			if g is TextureRect and (g as TextureRect).texture != null:
				return "裸图 %s" % (g as TextureRect).size
			if g is Sprite2D and (g as Sprite2D).texture != null:
				return "有图"
	return "无图"


## 棋盘上那张牌现在是一个 MatchCardToken（一次 _draw() 画完五层），
## 截图时把它的状态打出来，出问题才知道是"没画"还是"画了但看不见"
func _diag_tokens() -> void:
	var toks: Node2D = _arena.get_node_or_null("Tokens")
	if toks == null:
		return
	for t in toks.get_children():
		if not (t is MatchCardToken):
			continue
		var tk := t as MatchCardToken
		print("   TOKEN ", tk.name, " revealed=", tk.is_revealed(),
				" team=", tk.team, " avail=", tk.avail,
					" idx=", tk.card_index, " proc=", tk.is_processing(),
					" pos=", tk.global_position,
				" 尺寸=%.0f×%.0f" % [tk.card_w(), tk.card_h],
				" modulate.a=%.2f" % tk.modulate.a)


func _on_post_draw() -> void:
	_post_draws += 1


func _grab(path: String) -> void:
	# 等到"这一帧真的画完了"再取图：窗口被挡住时引擎不重绘，
	# 不等就会连着几张存成同一帧（上面那段说明）。最多等 90 帧，等不到也照抓，
	# 让日志里那行 stale 暴露出来，而不是整个工具卡死。
	var n := _post_draws
	var waited := 0
	while _post_draws == n and waited < 90:
		waited += 1
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("!! 拿不到画面（无头模式没有真实窗口）")
		return
	var err := img.save_png(path)
	print("SHOT ", path, " err=", err, " 等新帧=", waited,
			"" if _post_draws > n else "  !! 窗口没重绘，这张可能是旧帧")
