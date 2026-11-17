extends Node
## 快速模式 · 总验收（票 007）
##
## 一条命令把票 001–006 的判据串起来，并补上各票单独测不到的三件事：
##   ③ **等价性实测** —— 同一关两种模式，钱和进度的增量必须完全一样；
##   ④ **反向判据** —— 普通模式不许被快速模式的任何分支碰到（行为代理，不靠源码扫描）；
##   ⑤ 老档缺字段 + 真盘 JSON 往返。
##
## ⚠ 本探针不写玩家任何真实槽位：真盘测试用 `slot_path(9)`，
##   9 > SLOT_COUNT，游戏永远不会读它，跑完立刻删。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_all.tscn -- --no-save

const CRYSTAL := "mat_duanzaojingshi"
const LEVELS := [1, 2, 5, 11, 23, 40]

var _passes := 0
var _fails: Array = []
var _arena: Node = null


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wallet() -> int:
	return int(CharacterData.count_material(CRYSTAL))


func _crystal(n: int) -> Dictionary:
	var def := ItemDB.get_material(CRYSTAL)
	return {"id": CRYSTAL, "name": String(def.get("name", CRYSTAL)), "type": "material",
		"count": n, "icon": String(def.get("icon", ""))}


func _ready() -> void:
	print("\n########## 棋坛快速模式 · 总验收 ##########")
	await _check_source_of_truth()
	await _check_schedule_split()
	await _check_equivalence()
	await _check_normal_untouched()
	await _check_save_boundaries()
	await _check_scroll_visible_face()
	await _check_docs()
	await _check_end_reason_copy()
	await _cleanup()
	_finish()


# ===================== ① 同源 =====================

## 布局的卡组必须就是 deck_for(关卡号)。这条是"拓印画的 == 对局打的"的地基；
## 地基裂了，② ③ ⑥ 全都会以谁也说不清的方式红。
func _check_source_of_truth() -> void:
	var bad_deck: Array = []
	var bad_shape: Array = []
	for lv in LEVELS:
		var want := {}
		for id in MatchLevelDeck.deck_for(lv):
			want[String(id)] = true
		var layout: Array = MatchQuickSetup.layout_for(lv)
		var got := {}
		var ups := 0
		var seen := {}
		for x in layout:
			var d: Dictionary = x
			got[String(d["boss_id"])] = true
			if bool(d["face_up"]):
				ups += 1
			var c: Vector2i = d["cell"]
			if seen.has(c):
				bad_shape.append("%d 格重复%s" % [lv, str(c)])
			seen[c] = true
			if not MatchDB.in_board(c):
				bad_shape.append("%d 出界%s" % [lv, str(c)])
		if want.keys().size() != got.keys().size():
			bad_deck.append("%d 张数 %d≠%d" % [lv, got.keys().size(), want.keys().size()])
		for k in want:
			if not got.has(k):
				bad_deck.append("%d 缺 %s" % [lv, k])
		if ups != 3:
			bad_shape.append("%d 是 %d 正" % [lv, ups])
	_check(bad_deck.is_empty(), "① layout_for 的卡组 == deck_for(关卡号)", str(bad_deck))
	_check(bad_shape.is_empty(), "① 布局形状：6 格互不相同、在盘内、恰好 3 正 3 反", str(bad_shape))


# ===================== ② 日程分叉 =====================

## 快速模式：pick → deploy → final，中间既没有 lock 也没有逐轮 battle。
## 普通模式：pick → lock → deploy → battle →…→ final，一条都没少。
func _check_schedule_split() -> void:
	var q := await _open_arena(true, 6)
	var seq: Array = [String(MatchState.PHASE_NAME[q.get("_state").phase])]
	var st = q.get("_state")
	# 快速模式开局就该看见对方 6 子
	_check(int(st.deployed_count()) == MatchDB.DECK_SIZE,
			"② 快速开局对方已摆 6 子", str(st.deployed_count()))
	_check(st.phase == MatchState.Phase.PICK, "② 快速开局停在选牌", str(st.phase))
	_play_player_deck(st)
	seq.append(String(MatchState.PHASE_NAME[st.phase]))
	_check(st.phase == MatchState.Phase.DEPLOY, "② 交完牌直接进布阵（无 LOCK）", str(st.phase))
	_check(_deployed_by(st, 0) == 0, "② 玩家 6 张还没落子", "")
	for i in 6:
		_deploy_one(st, 0)
	_check(int(st.deployed_count()) == 12, "② 玩家能连摆 6 张（不交替）", str(st.deployed_count()))
	_check(st.phase == MatchState.Phase.DEPLOY, "② 摆满不自动开打", str(st.phase))
	st.quick_start_battle()
	seq.append(String(MatchState.PHASE_NAME[st.phase]))
	_check(st.phase == MatchState.Phase.FINAL, "② 开战直接进终局（跳过六轮）", str(st.phase))
	_check(not seq.has("lock") and not seq.has("battle"),
			"② 快速模式序列里没有 lock/battle", str(seq))
	await _close_arena()

	var n := await _open_arena(false, 6)
	var nst = n.get("_state")
	var nseq: Array = [String(MatchState.PHASE_NAME[nst.phase])]
	_play_player_deck(nst)
	nst.apply_command({"t": "pick", "team": 1, "ids": (nst.legal_pool(1) as Array).duplicate()})
	nseq.append(String(MatchState.PHASE_NAME[nst.phase]))
	_check(nst.phase == MatchState.Phase.LOCK, "② 普通模式仍要过 LOCK", str(nst.phase))
	var l0: Dictionary = MatchPolicy.decide_lock(nst, 0)
	var l1: Dictionary = MatchPolicy.decide_lock(nst, 1)
	nst.apply_command({"t": "lock", "team": 0, "down": int(l0["down"]), "up": int(l0["up"])})
	nst.apply_command({"t": "lock", "team": 1, "down": int(l1["down"]), "up": int(l1["up"])})
	nseq.append(String(MatchState.PHASE_NAME[nst.phase]))
	_check(nst.phase == MatchState.Phase.DEPLOY, "② 锁完进布阵", str(nst.phase))
	_check(nst.deploy_turn == 0, "② 普通模式布阵先手是玩家", str(nst.deploy_turn))
	# 普通模式逐子交替：玩家落 1 子交先手，对方落 1 子交回来
	_deploy_one(nst, 0)
	_check(nst.deploy_turn == 1, "② 普通模式逐子交替（玩家落一子后交先手）",
			str(nst.deploy_turn))
	_deploy_one(nst, 1)
	_check(nst.deploy_turn == 0, "② 对方落一子后先手回到玩家", str(nst.deploy_turn))
	# 「跳过（按策略代打）」在普通模式只能代打**当前这一手**。
	# 快速模式把它改成了一次摆完 6 张，这条锁住普通模式不许跟着批量 ——
	# 一次摆完会直接抹掉逐轮布阵的对抗性。
	# ⚠ 只数**玩家自己**的落子：跳过把先手交还后，对局的 AI 会照常补一子，
	#   总数 +2 是对的（第一版按总数判，被 AI 这一子判成"批量"）。
	var p0 := _deployed_by(nst, 0)
	((n.get("_buttons") as Dictionary)["skip"] as Button).pressed.emit()
	await _frames(2)
	var p1 := _deployed_by(nst, 0)
	_check(p1 == p0 + 1, "② 普通模式「跳过」只替玩家落 1 子（不是批量 6 子）",
			"%d → %d" % [p0, p1])
	_check(nst.quick == false, "② 普通模式 quick 标记恒为 false", str(nst.quick))
	print("    普通模式序列=", str(nseq))
	await _close_arena()


func _deployed_by(st, team: int) -> int:
	var n := 0
	for i in st.team_cards(team):
		if bool((st.cards[i] as Dictionary)["deployed"]):
			n += 1
	return n


func _player_ids(st) -> Array:
	var out: Array = []
	for i in MatchDB.DECK_SIZE:
		out.append(String((st.legal_pool(0) as Array)[i]))
	return out


func _play_player_deck(st) -> void:
	st.apply_command({"t": "pick", "team": 0, "ids": _player_ids(st)})


func _deploy_one(st, team: int) -> void:
	var legal: Array = st.legal_deploy(team)
	var cells: Array = MatchState.free_cells(st.occupied_cells())
	if legal.is_empty() or cells.is_empty():
		return
	st.apply_command({"t": "deploy", "team": team, "card": int(legal[0]), "cell": cells[0]})


# ===================== ③ 等价性实测 =====================

## 同一关、同一结局，两种模式的钱包增量与进度增量必须逐字相同。
## 这是 ADR-0003「完全等价」唯一有意义的证法：不是"没写两行代码"，
## 而是跑出来的数字一样。
func _check_equivalence() -> void:
	var cases: Array = [
		# [首通与否, 关卡号, cleared, 胜方, 期望增量, 期望进度]
		[true, 7, 6, 0, 8, 7],
		[false, 5, 6, 0, 0, 6],      # 重打低关卡：不给钱，也不把进度倒回去
		[false, 8, 7, 1, 0, 7],      # 输：不扣钱也不推进
	]
	var bad: Array = []
	var texts := {}
	for c in cases:
		var lv := int(c[1])
		for quick in [false, true]:
			var d := await _settle_outcome(quick, lv, int(c[2]), int(c[3]))
			if int(d["delta"]) != int(c[4]) or int(d["progress"]) != int(c[5]):
				bad.append("%s 第%d关(cleared=%d,胜方%d) ⇒ +%d/进度%d 应为 +%d/进度%d" % [
					"快速" if quick else "普通", lv, int(c[2]), int(c[3]),
					int(d["delta"]), int(d["progress"]), int(c[4]), int(c[5])])
			texts["%d_%s" % [lv, "q" if quick else "n"]] = String(d["text"])
	_check(bad.is_empty(), "③ 三种结局 × 两种模式：钱与进度增量完全一致", str(bad))
	# 但文案必须看得出档位 —— 等价意味着数字相同，玩家只能靠这一行分辨自己走了哪条日程
	var label_bad: Array = []
	for c in cases:
		var lv := int(c[1])
		var q := String(texts["%d_q" % lv])
		var n := String(texts["%d_n" % lv])
		if not q.contains("快速模式"):
			label_bad.append("第%d关 快速结算没标档位：%s" % [lv, q])
		if n.contains("快速模式"):
			label_bad.append("第%d关 普通结算串了档位的字：%s" % [lv, n])
	_check(label_bad.is_empty(), "③ 结算页标得出档位，且普通模式不被污染", str(label_bad))


## 返回这一局结算后的 {delta, progress}
func _settle_outcome(quick: bool, lv: int, cleared: int, winner: int) -> Dictionary:
	var a := await _open_arena(quick, lv)
	var st = a.get("_state")
	if quick:
		_play_player_deck(st)
		for i in 6:
			_deploy_one(st, 0)
		st.quick_start_battle()
	st.winner = winner
	st.end_reason = "clear_field"
	CharacterData.inventory = [_crystal(100)]
	CharacterData.match_level_cleared = cleared
	a.call("_settle")
	await _frames(2)
	var out := {
		"delta": _wallet() - 100,
		"progress": int(CharacterData.match_level_cleared),
		"text": String(a.get("_result_label").text).split("\n")[0],
	}
	await _close_arena()
	return out


# ===================== ④ 反向判据 =====================

## 普通模式不许被快速模式的分叉碰到。用**行为代理**，不用调用计数：
## 计数要在生产代码里埋静态变量，那是为了测试污染产品。
func _check_normal_untouched() -> void:
	var a := await _open_arena(false, 9)
	var st = a.get("_state")
	_check(st.quick == false, "④ 普通模式状态机 quick=false", str(st.quick))
	_check(int(st.deployed_count()) == 0,
			"④ 普通模式开局没人被预摆（quick_open 没被走过）", str(st.deployed_count()))
	var n := int(a.call("_camera_mode"))
	_check(n == MatchArena.CAM_NORMAL, "④ 普通模式选牌阶段是常规档", str(n))
	# 宽时间窗只在 quick 那一侧生效
	st.phase = MatchState.Phase.FINAL
	_check(absf(float(st.final_limit()) - MatchDB.FINAL_LIMIT_SECONDS) < 0.001,
			"④ 普通终局上限仍是 120s，没被宽窗污染", str(st.final_limit()))
	st.final_elapsed = 180.0
	_check(absf(float(st.time_scale()) - 2.0) < 0.001,
			"④ 普通加速曲线仍按 60→120 推到顶", str(st.time_scale()))
	# 快速档的 HUD 搬家只在 CAM_QUICK 里做
	_check((a.get("_action_bar") as Control).visible,
			"④ 普通模式操作栏没被收掉", "")
	_check((a.get("_notice") as Control).visible,
			"④ 普通模式回执行没被收掉", "")
	await _close_arena()

	# 结算只有一条路：_settle 里没有按模式分叉的分支
	var src := FileAccess.get_file_as_string("scripts/match/match_arena.gd")
	var body := _function_body(src, "func _settle()")
	_check(body.contains("quick") == false,
			"④ 结算函数里没有任何 quick 分叉（真的只有一条经济路径）", "")
	_check(body.contains("LEVEL_FIRST_CLEAR_REWARD"),
			"④ 首通奖走同一个常量", "")


## 取出某个函数的源码体（到下一个顶格 func/## 为止）。
## 只用来读结构事实，不当行为判据。
func _function_body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + header.length())
	var k := src.find("\n\n\n", i + header.length())
	var stop := src.length()
	if j > 0:
		stop = min(stop, j)
	if k > 0:
		stop = min(stop, k)
	return src.substr(i, stop - i)


# ===================== ⑤ 存档边界 =====================

func _check_save_boundaries() -> void:
	# 老档缺字段：内存里留个脏 true，读盘必须变关
	CharacterData.match_quick_mode = true
	SaveManager.apply({"player_name": "老档"})
	_check(CharacterData.match_quick_mode == false,
			"⑤ 老档缺字段 ⇒ 按关，不沿用内存脏值", str(CharacterData.match_quick_mode))

	# 脏值：字符串 "false" 走 bool() 会读成开（非空字符串即真），必须压回关
	for dirty in ["false", "true", 1, 0, null, [], {}]:
		CharacterData.match_quick_mode = false
		SaveManager.apply({"match_quick_mode": dirty})
		if dirty is bool:
			continue
		_check(CharacterData.match_quick_mode == false,
				"⑤ 脏值 %s 一律压回关" % str(dirty), str(CharacterData.match_quick_mode))

	# 真盘往返：JSON 里必须是真布尔
	var scratch := SaveManager.slot_path(9)
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	if f == null:
		_check(false, "⑤ 临时文件打不开", scratch)
		return
	CharacterData.match_quick_mode = true
	f.store_string(JSON.stringify(SaveManager.capture()))
	f.close()
	CharacterData.match_quick_mode = false
	SaveManager.apply(JSON.parse_string(FileAccess.get_file_as_string(scratch)))
	_check(CharacterData.match_quick_mode == true, "⑤ 开关经真盘往返仍是开", "")
	var raw: Variant = (JSON.parse_string(FileAccess.get_file_as_string(scratch)) as Dictionary) \
			.get("match_quick_mode", null)
	_check(raw is bool, "⑤ 磁盘上是真布尔，不是 \"true\" 也不是 1", str(raw))
	DirAccess.remove_absolute(scratch)
	_check(not FileAccess.file_exists(scratch), "⑤ 临时文件已清掉", scratch)


# ===================== ⑥ 长卷可见面 =====================

func _check_scroll_visible_face() -> void:
	var lv := 4
	await _mk_scroll(true, lv - 1)
	var t := _tile(lv)
	if t.is_empty():
		_check(false, "⑥ 快速模式拓印建出来了", "")
	else:
		var layout: Array = MatchQuickSetup.layout_for(lv)
		var want := {}
		for x in layout:
			want[String((x as Dictionary)["boss_id"])] = (x as Dictionary)["cell"]
		var hosts: Array = t["hosts"]
		var board: Control = t["board"]
		var bad: Array = []
		var backs := 0
		for i in hosts.size():
			var bid := String((t["deck"] as Array)[i])
			if Vector2i(want.get(bid, Vector2i(-9, -9))) != Vector2i(board.stone_cell(i)):
				bad.append("%s 格不对" % bid)
			if _is_back(hosts[i] as Control):
				backs += 1
		_check(bad.is_empty(), "⑥ 拓印落位 == layout_for", str(bad))
		_check(backs == 3, "⑥ 3 枚牌背", "%d 枚" % backs)
		_check(bool(board.get("veil")) == false, "⑥ 快速模式面纱关掉", str(board.get("veil")))
		# ⚠ Array 没有 indexOf()（本机 4.7.2 缺），要索引就用循环下标
		var leaked := 0
		for i in hosts.size():
			if not _is_back(hosts[i] as Control):
				continue
			var nm := String(WorldDB.get_boss_name(String((t["deck"] as Array)[i])))
			if String((hosts[i] as Control).tooltip_text).contains(nm):
				leaked += 1
		_check(leaked == 0, "⑥ 牌背的 tooltip 不泄露身份", "%d 处" % leaked)
		var meta: Label = _scroll.get("_strip_meta")
		_check(String(meta.text).contains("真实落位"),
				"⑥ 读数带写了真布局标注", String(meta.text))
	await _destroy_scroll()

	# 关掉开关：拓印回到装饰落点 + 面纱，标注收回
	await _mk_scroll(false, lv - 1)
	var t2 := _tile(lv)
	if not t2.is_empty():
		var backs2 := 0
		for h in (t2["hosts"] as Array):
			if _is_back(h as Control):
				backs2 += 1
		_check(backs2 == 0, "⑥ 普通模式一张牌背都不画", "%d 枚" % backs2)
		_check(bool((t2["board"] as Control).get("veil")), "⑥ 普通模式面纱仍开着", "")
		_check(not String((_scroll.get("_strip_meta") as Label).text).contains("真实落位"),
				"⑥ 普通模式读数不带标注", String((_scroll.get("_strip_meta") as Label).text))
	await _destroy_scroll()


var _scroll: Control = null


func _mk_scroll(quick: bool, cleared: int) -> void:
	await _destroy_scroll()
	CharacterData.match_quick_mode = quick
	CharacterData.match_level_cleared = cleared
	GameState.match_context = {}
	_scroll = MatchLevelScroll.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(_scroll)
	await _frames(16)


func _destroy_scroll() -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.queue_free()
		await _frames(6)
	_scroll = null


func _tile(level: int) -> Dictionary:
	for s in _scroll._tiles_by_slot.keys():
		var t: Dictionary = _scroll._tiles_by_slot[int(s)]
		if int(t["level"]) == level:
			return t
	return {}


func _is_back(host: Control) -> bool:
	for c in host.get_children():
		if c is TextureRect and (c as TextureRect).texture == MatchCard.back_texture():
			return true
	return false


# ===================== ⑦ 文档交叉 =====================

func _check_docs() -> void:
	var doc := FileAccess.get_file_as_string("docs/卡片自走棋_设计案.md")
	_check(doc.contains("2d. 快速模式"), "⑦ 设计案补了快速模式那一节", "")
	_check(doc.contains("ADR-0003") and doc.contains("ADR-0004"),
			"⑦ 设计案链到两条新 ADR", "")
	_check(doc.contains("240") and doc.contains("616"),
			"⑦ 设计案写了宽时间窗与第三档的实测数", "")
	var ctx := FileAccess.get_file_as_string("CONTEXT.md")
	var missing: Array[String] = []
	# 只收术语表里该有的**词**。CAM_QUICK / layout_for 这类是代码标识符，
	# 写在判据里会把"文档有没有讲清概念"偷换成"文档有没有抄一遍代码"。
	for term in ["快速模式", "固定摆位", "玩家全正面", "开战", "宽时间窗",
			"拓印真布局", "快速档"]:
		if not ctx.contains(term):
			missing.append(term)
	_check(missing.is_empty(), "⑦ CONTEXT.md 快速模式术语齐全", str(missing))
	# 细化后的「预告」口径必须写进去，否则文档还在承诺"格子对应关系也摊开"
	_check(ctx.contains("格子对应关系"),
			"⑦ CONTEXT.md 写了细化后的预告口径", "")
	_check(FileAccess.file_exists("res://docs/adr/0003-快速模式是同一状态机的第二条日程.md")
			and FileAccess.file_exists("res://docs/adr/0004-快速模式摆位按关卡号固定而普通模式保持随机.md"),
			"⑦ 两条 ADR 都在", "")
	# 八张票都要带实测段（本项目的规矩：票面没写实测数字就等于没验收）
	var no_measure: Array = []
	for f in [1, 2, 3, 4, 5, 6, 7, 9]:
		var path := _ticket_path(f)
		if path == "":
			no_measure.append("00%d 不存在" % f)
		elif not FileAccess.get_file_as_string(path).contains("实测"):
			no_measure.append("00%d 没有实测段" % f)
	_check(no_measure.is_empty(), "⑦ 八张票都在且都带实测段", str(no_measure))


## ⚠ DirAccess.get_files() 返回的是**裸文件名**，不含目录前缀；
##   拿 "目录/001-" 去 begins_with 永远不匹配（第一版就是这么全红）。
func _ticket_path(f: int) -> String:
	var d := DirAccess.open("res://.scratch/棋坛快速模式/tickets")
	if d == null:
		d = DirAccess.open(".scratch/棋坛快速模式/tickets")
	if d == null:
		return ""
	var prefix := "00%d-" % f
	for n in d.get_files():
		if String(n).begins_with(prefix):
			return ".scratch/棋坛快速模式/tickets/" + String(n)
	return ""


# ===================== ⑧ 结算「结束方式」可读 =====================

## 快速模式大量走清场/超时这条路，结算页第二行直接就是玩家唯一看到的死法说明。
## 判据分三层：源码里出现的 reason 都有文案（防漏）、文案本身不许带英文（防抄错），
## 最后真开一局把每条 reason 渲染到结算页上（防翻译函数没接进去）。
func _check_end_reason_copy() -> void:
	var src := FileAccess.get_file_as_string("scripts/match/match_state.gd")
	var literals: Array = []
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("_end("):
			continue
		var a := line.rfind("\"")
		var b := line.find("\"")
		if b < 0 or a <= b:
			continue
		literals.append(line.substr(b + 1, a - b - 1))
	# 去重
	var uniq := {}
	for r in literals:
		uniq[String(r)] = true
	_check(uniq.keys().size() >= 5, "⑧ 从状态机里抓到结束方式清单", str(uniq.keys()))
	var missing: Array = []
	for r in uniq.keys():
		if not MatchDB.END_REASON_TEXT.has(String(r)):
			missing.append(String(r))
	_check(missing.is_empty(), "⑧ 每条结束方式都有玩家可读的文案", str(missing))

	var dirty: Array = []
	for k in MatchDB.END_REASON_TEXT.keys():
		var v := String(MatchDB.END_REASON_TEXT[k])
		# 中文的 to_lower/to_upper 都是恒等；只要有一个不等，就说明串里混了带大小写的字母
		if v.contains("_") or v.to_lower() != v or v.to_upper() != v:
			dirty.append("%s ⇒ %s" % [String(k), v])
	_check(dirty.is_empty(), "⑧ 文案里没有英文/下划线残留（不是把枚举换个位置印）", str(dirty))

	# 真渲染：五种死法各开一局，读结算页第二行
	var bad_render: Array = []
	for r in MatchDB.END_REASON_TEXT.keys():
		var reason := String(r)
		var a := await _open_arena(true, 6)
		var st = a.get("_state")
		st.winner = 0
		st.end_reason = reason
		a.call("_settle")
		await _frames(2)
		var lines: PackedStringArray = String(a.get("_result_label").text).split("\n")
		var line := "" if lines.size() < 2 else lines[1]
		if not line.begins_with("结束方式：") or line.contains(reason) \
				or line == String(MatchDB.END_REASON_TEXT[reason]):
			bad_render.append("%s ⇒ 「%s」" % [reason, line])
		await _close_arena()
	_check(bad_render.is_empty(), "⑧ 结算页第二行渲染的是中文，不是内部枚举", str(bad_render))


# ===================== 工具 =====================

func _open_arena(quick: bool, lv: int) -> Node:
	await _close_arena()
	CharacterData.match_quick_mode = quick
	CharacterData.match_level_cleared = lv - 1
	GameState.match_context = {"level": lv}
	var a: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	a.set("player_stage_timeout", 60.0)
	add_child(a)
	await _frames(24)
	_arena = a
	return a


func _close_arena() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
		await _frames(6)
	_arena = null
	GameState.reset_time_flow()


func _cleanup() -> void:
	await _close_arena()
	await _destroy_scroll()
	CharacterData.match_quick_mode = false
	GameState.match_context = {}


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
