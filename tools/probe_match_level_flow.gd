extends Node
## 棋坛关卡 · 进关链路最小闭环（#55，2026-11-05）
##
## 端到端只验一条路：主城点设施 → 棋谱长卷 → 点当前关进对局 →
## 对手就是 deck_for(当前关) → 结算「返回」落回长卷并停在下一关。
##
## 用法：godot --headless --path . res://tools/probe_match_level_flow.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _entered_level := -1


func _on_level_entered(level: int) -> void:
	_entered_level = level


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 棋坛关卡 · 进关链路 ##########")
	_check_save_field()
	await _check_arena_reads_level()
	# ⚠ 必须 await：_check_scroll() 内部有 await，不写的话协程刚挂起就被 _finish() 的
	#   quit() 掐死，整组 ③ 静默不跑（GDScript 老坑：函数含 await 就成了协程）。
	await _check_scroll()
	_check_city_entry()
	# ⑥ 要真切场景，而 change_scene_to_file 会 free 掉当前场景 —— 也就是这个探针自己。
	# 所以把检查器挂到 root 上跑，由它汇总并退出（详见 match_chain_checker.gd 头部）。
	var keeper := Node.new()
	keeper.name = "ChainChecker"
	keeper.set_script(load("res://tools/match_chain_checker.gd"))
	get_tree().root.add_child(keeper)
	keeper.inherit(_passes, _fails)
	# ⚠ 不要 await：run_chain() 里会 change_scene_to_file，而本探针就是那个 current_scene，
	#   await 挂起后回来时自己已经被 free 了（Invalid call / Nonexistent constructor）。
	#   检查器挂在 root 上，由它自己跑完并 quit。
	keeper.run_chain()


func _check_scroll() -> void:
	CharacterData.match_level_cleared = 3
	var scroll: Control = MatchLevelScroll.new()
	scroll.size = Vector2(1280, 720)
	add_child(scroll)
	for i in 8:
		await get_tree().process_frame

	_check(int(scroll._current) == 4, "③ 已通关 3 局 ⇒ 当前关是第 4 关", "%d" % int(scroll._current))
	# #57 之后长卷是虚拟化的：_tiles_by_slot 只装可见范围，
	# 所以"铺了哪些关"要看槽位数，不能看已建节点数。
	_check(int(scroll._deck_slot_count()) == 4 + MatchLevelScroll.PREVIEW_AHEAD,
			"③ 卷上有卡组的槽 = 已通关 + 当前关 + 往后 5", "%d" % int(scroll._deck_slot_count()))

	var wrong: Array[String] = []
	for slot in scroll._tiles_by_slot.keys():
		var t: Dictionary = scroll._tiles_by_slot[int(slot)]
		var lv := int(t["level"])
		var got: Array = t["deck"]
		if not _same_set(got, MatchLevelDeck.deck_for(lv)):
			wrong.append("第 %d 关拓印 %s ≠ deck_for" % [lv, str(got)])
	_check(wrong.is_empty(), "③ 每枚拓印嵌的就是这一关的固定卡组", str(wrong))

	# 每关 6 枚落子都要真的挂上格子，漏一格就是"少打一只"的错觉
	var holes: Array[String] = []
	for slot in scroll._tiles_by_slot.keys():
		var t: Dictionary = scroll._tiles_by_slot[int(slot)]
		var board = t["board"]
		for i in MatchDB.DECK_SIZE:
			var c: Vector2i = board.stone_cell(i)
			if c.x < 0 or c.y < 0:
				holes.append("第 %d 关第 %d 枚没落格" % [int(t["level"]), i])
	_check(holes.is_empty(), "③ 六枚落子全部有格子（不许出现空位）", str(holes))

	# 主按钮只给当前关
	scroll._focus(6)
	_check(scroll._cta.disabled, "③ 预览关没有可点的「进入此关」", str(scroll._cta.text))
	scroll._focus(4)
	_check(not scroll._cta.disabled, "③ 当前关有且只有一个主按钮", str(scroll._cta.text))

	GameState.match_context = {}
	# ⚠ 不能写 `var got := -1` 再让 lambda 改它：GDScript 的 lambda **按值捕获**局部变量，
	#   改的是副本，信号发了也读不到（探针会假红）。用成员变量传。
	_entered_level = -1
	scroll.level_entered.connect(_on_level_entered)
	# 这里只验"选中了哪一关 + 上下文写没写"，所以走 _enter 不走 _launch：
	# _launch 会 change_scene_to_file，把作为 current_scene 的本探针直接 free 掉。
	# 真按主按钮那条路由 ⑥（match_chain_checker）在 root 上跑。
	scroll._enter(4)
	_check(_entered_level == 4, "③ 选当前关发出的是这一关的关号", "%d" % _entered_level)
	_check(int(GameState.match_context.get("level", -1)) == 4,
			"③ 进关前把关卡号写进了 match_context", str(GameState.match_context))
	scroll.queue_free()
	await get_tree().process_frame
	GameState.match_context = {}
	CharacterData.match_level_cleared = 0


## ④ 主城设施改指长卷；长卷再落到对局。链路两头都得在。
func _check_city_entry() -> void:
	_check(FileAccess.file_exists("res://scenes/match/match_level_scroll.tscn"),
			"④ 长卷场景文件存在", "scenes/match/match_level_scroll.tscn")
	var city := FileAccess.get_file_as_string("res://scripts/main/primordial_realm.gd")
	_check(city.contains("match_level_scroll.tscn"),
			"④ 点设施先进长卷（不再直落对局）", "")
	_check(not city.contains("change_scene_to_file(\"res://scenes/match/match_arena.tscn\")"),
			"④ 主城里没有「跳过长卷直进对局」的残留路径", "")
	var arena := FileAccess.get_file_as_string("scripts/match/match_arena.gd")
	_check(arena.contains("match_level_scroll.tscn"),
			"⑤ 结算「返回长卷」真的切回长卷场景", "")
	_check(arena.contains("back.text = \"返回长卷\""),
			"⑤ 结算按钮文案跟着去处改（还写「返回主城」就是骗人）", "")
	# 押注那套经济在关卡制下已经不再结算，但纯函数要留给以后真人对局（ADR-0001）。
	# ⚠ 判据要看 MatchDB 而不是对局场景：#56 之后对局里本来就不该再出现 bet_matched，
	#   押在 arena 上等于把"调用点已撤掉"误判成"函数被删了"。
	var betdb := FileAccess.get_file_as_string("scripts/match/match_db.gd")
	_check(betdb.contains("static func bet_matched"),
			"⑤ bet_matched 保留在 MatchDB 未删（联机还要用，别当死代码清了）", "")


## ② 对局真的按关卡号取对手卡组，而不是继续走那套「避开玩家池」的随机池
func _check_arena_reads_level() -> void:
	GameState.match_context = {"level": 7}
	CharacterData.match_level_cleared = 6

	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 1.0)
	add_child(arena)
	for i in 6:
		await get_tree().physics_frame

	var st = arena.get("_state")
	if st == null:
		_check(false, "② 对局状态机起来了", "state=null")
		GameState.match_context = {}
		return
	var ai_deck: Array = (st.pools as Array)[1]
	var want: Array = MatchLevelDeck.deck_for(7)
	_check(_same_set(ai_deck, want), "② 对手那 6 张 == deck_for(7)（不是随机池）",
			"实=%s 期=%s" % [str(ai_deck), str(want)])
	_check(int(arena.get("_level")) == 7, "② 对局记住的是我传进去的那一关",
			"%d" % int(arena.get("_level")))

	# 换一关要真的换一副，别把关卡号当摆设
	arena.queue_free()
	await get_tree().process_frame
	GameState.match_context = {"level": 12}
	var arena2: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena2.set("player_stage_timeout", 1.0)
	add_child(arena2)
	for i in 6:
		await get_tree().physics_frame
	var st2 = arena2.get("_state")
	var deck12: Array = (st2.pools as Array)[1]
	_check(_same_set(deck12, MatchLevelDeck.deck_for(12)), "② 第 12 关换成了另一副固定卡组",
			str(deck12))
	_check(not _same_set(deck12, want), "② 两关的卡组确实不同", "")
	arena2.queue_free()
	await get_tree().process_frame
	GameState.match_context = {}


static func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var ka: Array[String] = []
	var kb: Array[String] = []
	for x in a:
		ka.append(String(x))
	for x in b:
		kb.append(String(x))
	ka.sort()
	kb.sort()
	return ka == kb


## ① 进度字段：默认 0、能存能读、老档缺字段不崩
func _check_save_field() -> void:
	_check(CharacterData.match_level_cleared == 0, "① 新档默认还没打过任何关",
		"%d" % CharacterData.match_level_cleared)

	CharacterData.match_level_cleared = 7
	var snap: Dictionary = SaveManager.capture()
	_check(int(snap.get("match_level_cleared", -1)) == 7, "① 写盘带上这个字段",
		str(snap.get("match_level_cleared", "<缺键>")))

	CharacterData.match_level_cleared = 0
	SaveManager.apply(snap)
	_check(CharacterData.match_level_cleared == 7, "① 读盘恢复进度",
		"%d" % CharacterData.match_level_cleared)

	# 老档：整个键都不存在，必须回到 0 而不是报错/返回 null
	var legacy: Dictionary = SaveManager.capture()
	legacy.erase("match_level_cleared")
	CharacterData.match_level_cleared = 41
	SaveManager.apply(legacy)
	_check(CharacterData.match_level_cleared == 0, "① 老档缺字段按「没打过」处理，不是沿用脏值",
		"%d" % CharacterData.match_level_cleared)

	# 脏档：写成字符串 / null 也不能把 int 字段污染成非数字
	for bad in ["9", null, {}, -3]:
		var dirty: Dictionary = SaveManager.capture()
		dirty["match_level_cleared"] = bad
		CharacterData.match_level_cleared = 5
		SaveManager.apply(dirty)
		var v: int = CharacterData.match_level_cleared
		_check(v >= 0, "① 脏值 %s 读回后仍是合法进度" % str(bad), "%d" % v)

	CharacterData.match_level_cleared = 0
