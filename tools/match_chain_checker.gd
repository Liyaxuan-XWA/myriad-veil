extends Node
## 棋坛关卡 · 场景链检查器（⑥）
##
## ⚠ 为什么单独一个脚本：`change_scene_to_file()` 会 **free 掉旧的 current_scene**，
##   而探针自己就是 current_scene —— 在探针里直接切场景等于把自己删了，
##   后面 `get_tree()` 拿到 null（probe_enter_world 的 enter_world_checker 同一套路）。
## 所以这个节点挂在 `get_tree().root` 上，切场景后仍然存活，由它跑完整条链并收尾。

var _passes := 0
var _fails: Array = []


func inherit(passes: int, fails: Array) -> void:
	_passes = passes
	_fails = fails.duplicate()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _key(a: Array) -> String:
	var ids: Array[String] = []
	for x in a:
		ids.append(String(x))
	ids.sort()
	return "|".join(ids)


func _name(n: Node) -> String:
	return "<null>" if n == null else String(n.name)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## 注入一次"真人按键"：只走 Input.parse_input_event，
## 不碰 VirtualPad 的 _virtual_keys —— 长卷里 ESC 有两条语义（真人键=退出 / 触屏虚拟键=开设置），
## 用 pad 的接口按就变成在测另一条路了。
func _press_real_key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	ev.echo = false
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func run_chain() -> void:
	CharacterData.match_level_cleared = 0
	GameState.match_context = {}
	get_tree().change_scene_to_file("res://scenes/main/primordial_realm.tscn")
	await _settle(30)
	var city := get_tree().current_scene
	_check(city != null and city.get_script() != null
			and String(city.get_script().resource_path).ends_with("primordial_realm.gd"),
			"⑥ 主城起来了", _name(city))
	if city == null:
		_finish()
		return

	# 先验一次进度锁：棋坛 gated 在「通关凡界」后面，新档点它必须被拦住。
	# 这条不是顺手加的 —— 上一版直接断言"点设施进长卷"，结果红在锁上，
	# 说明锁是真的会拦住玩家，那它就该被守着，而不是被测试悄悄绕过。
	city.call("_on_facility_activated", "match")
	await _settle(20)
	_check(String(get_tree().current_scene.name) == "PrimordialRealm",
			"⑥ 没通关凡界时点棋坛被进度锁拦住（不会直落长卷）",
			_name(get_tree().current_scene))

	var d01: Dictionary = WorldDB.get_domain("domain_01")
	for b in (d01.get("boss_ids", []) as Array):
		CharacterData.mark_boss_killed("domain_01", String(b))
	_check(CharacterData.is_domain_cleared("domain_01"),
			"⑥ 前置已满足：凡界通关", "")

	city.call("_on_facility_activated", "match")
	await _settle(30)
	var s1 := get_tree().current_scene
	_check(s1 != null and String(s1.name) == "MatchLevelScroll",
			"⑥ 点棋坛设施落到棋谱长卷（不再直进对局）", _name(s1))
	if s1 == null or String(s1.name) != "MatchLevelScroll":
		_finish()
		return
	_check(int(s1._current) == 1, "⑥ 新档当前关是第 1 关", "%d" % int(s1._current))

	# 点真的主按钮，不是调内部函数 —— "玩家点得动"才是这条链要守的东西
	s1._cta.pressed.emit()
	await _settle(30)
	var s2 := get_tree().current_scene
	_check(s2 != null and String(s2.name) == "MatchArena",
			"⑥ 「进入此关」落到对局场景", _name(s2))
	if s2 == null:
		_finish()
		return
	_check(int(s2.get("_level")) == 1, "⑥ 对局拿到的是第 1 关", str(s2.get("_level")))
	var st = s2.get("_state")
	if st == null:
		_check(false, "⑥ 对局状态机起来了", "state=null")
		_finish()
		return
	_check(_key((st.pools as Array)[1]) == _key(MatchLevelDeck.deck_for(1)),
			"⑥ 对局里的对手就是长卷预告的那一副", str((st.pools as Array)[1]))

	s2.call("_return_to_scroll")
	await _settle(30)
	var s3 := get_tree().current_scene
	_check(s3 != null and String(s3.name) == "MatchLevelScroll",
			"⑥ 结算「返回长卷」真的回到长卷", _name(s3))
	_check(not get_tree().paused, "⑥ 换场景没把 paused 漏给下一个场景", str(get_tree().paused))
	_check(GameState.match_context.is_empty(), "⑥ 离场清掉了关卡上下文", str(GameState.match_context))

	# 卷尾退出：这一屏以前唯一的出口是"进关再弃局"，用户实机第一下就撞上了。
	# 2026-11-05 按用户要求挪到右上角贴着「设置」，并加 ESC 同效 —— 两条都守：
	var bb: Button = s3._back_btn
	var br: Rect2 = bb.get_global_rect()
	## 用视口的**逻辑**尺寸（`Window.get_visible_size()` 这台引擎上没有这个函数，
	## 一旦调用就是运行时中断 —— 而 run_chain() 里没人兜底，探针会永远不退出）
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_check(bb.get_parent() == s3, "⑥ 返回键挂在长卷根上（不再挤底栏那一排）",
			str((bb.get_parent() as Node).name))
	_check(br.end.x <= vp.x - 80.0 and br.end.x >= vp.x - 300.0 and br.position.y < 60.0,
			"⑥ 返回键贴在右上角「设置」左边", "rect=%s 视口=%s" % [str(br), str(vp)])
	# 真人按 ESC（不是触屏注入）→ 等价于点那颗返回键
	_press_real_key(KEY_ESCAPE)
	await _settle(30)
	var s4 := get_tree().current_scene
	_check(s4 != null and String(s4.name) == "PrimordialRealm",
			"⑥ 长卷里按 ESC 回主城", _name(s4))
	_check(not get_tree().paused, "⑥ 卷尾退出没把 paused 漏给主城", str(get_tree().paused))
	# 回长卷再验一次按钮本身还在（挪位置不能把点击路径挪丢）
	get_tree().change_scene_to_file("res://scenes/match/match_level_scroll.tscn")
	await _settle(40)
	var s5 := get_tree().current_scene
	if s5 != null and s5.has_method("_on_back_pressed"):
		(s5 as MatchLevelScroll)._back_btn.pressed.emit()
		await _settle(30)
		var s6 := get_tree().current_scene
		_check(s6 != null and String(s6.name) == "PrimordialRealm",
				"⑥ 右上角「返回原初位面」点得动", _name(s6))
	else:
		_check(false, "⑥ 回长卷重进失败（没拿到 MatchLevelScroll）", _name(s5))
	_finish()


## 快速模式的整条场景链（票 009）。
## 单独一条而不是把 run_chain() 改成分叉：那条已经守了普通模式八步，
## 混进来一旦红了就分不清是哪条日程坏了。
## ⚠ 玩法推进走命令、退出走**真按按钮** —— "玩家点得动"才是这条链要守的东西。
func run_quick_chain() -> void:
	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = 0
	CharacterData.inventory = []
	GameState.match_context = {}
	get_tree().change_scene_to_file("res://scenes/main/primordial_realm.tscn")
	await _settle(30)
	var city := get_tree().current_scene
	_check(city != null and String(city.name) == "PrimordialRealm",
			"⑧ 快速链：主城起来了", _name(city))
	if city == null:
		_finish()
		return
	var d01: Dictionary = WorldDB.get_domain("domain_01")
	for b in (d01.get("boss_ids", []) as Array):
		CharacterData.mark_boss_killed("domain_01", String(b))
	city.call("_on_facility_activated", "match")
	await _settle(30)
	var s1 := get_tree().current_scene
	_check(s1 != null and String(s1.name) == "MatchLevelScroll",
			"⑧ 点棋坛落到长卷", _name(s1))
	if s1 == null or String(s1.name) != "MatchLevelScroll":
		_finish()
		return
	# 开关必须是开着的，而且长卷要照着它画
	var qb: Button = s1.get("_quick_btn")
	_check(qb != null and String(qb.text).contains("开"),
			"⑧ 长卷开关显示「开」", "" if qb == null else String(qb.text))
	var t1: Dictionary = s1._tile_for(1)
	_check(not t1.is_empty(), "⑧ 第 1 关拓印建出来了", "")
	var backs := 0
	if not t1.is_empty():
		for h in (t1["hosts"] as Array):
			for c in (h as Control).get_children():
				if c is TextureRect and (c as TextureRect).texture == MatchCard.back_texture():
					backs += 1
	_check(backs == 3, "⑧ 链上拓印仍是 3 枚牌背（换场景没退化）", "%d 枚" % backs)

	s1._cta.pressed.emit()
	await _settle(30)
	var s2 := get_tree().current_scene
	_check(s2 != null and String(s2.name) == "MatchArena",
			"⑧ 「进入此关」落到对局", _name(s2))
	if s2 == null:
		_finish()
		return
	var st = s2.get("_state")
	_check(bool(s2.get("_quick")) and bool(st.quick),
			"⑧ 对局拿到了快速模式", "arena=%s state=%s" % [str(s2.get("_quick")), str(st.quick)])
	_check(int(st.deployed_count()) == MatchDB.DECK_SIZE,
			"⑧ 进关即见对方 6 子已摆好", str(st.deployed_count()))
	_check(int(st.phase) == int(MatchState.Phase.PICK),
			"⑧ 玩家还停在选牌", String(MatchState.PHASE_NAME[int(st.phase)]))
	_check(int(s2.call("_camera_mode")) == MatchArena.CAM_NORMAL,
			"⑧ 选牌阶段是常规档", str(s2.call("_camera_mode")))

	# 玩家侧推进走命令（这是规则层的唯一入口，本来就该这样）
	var ids: Array = []
	for i in MatchDB.DECK_SIZE:
		ids.append(String((st.legal_pool(0) as Array)[i]))
	st.apply_command({"t": "pick", "team": 0, "ids": ids})
	_check(int(st.phase) == int(MatchState.Phase.DEPLOY),
			"⑧ 交完牌跳过 LOCK 直接布阵", String(MatchState.PHASE_NAME[int(st.phase)]))
	for i in MatchDB.DECK_SIZE:
		var legal: Array = st.legal_deploy(0)
		var cells: Array = MatchState.free_cells(st.occupied_cells())
		if legal.is_empty() or cells.is_empty():
			break
		st.apply_command({"t": "deploy", "team": 0,
				"card": int(legal[0]), "cell": cells[0]})
	_check(int(st.deployed_count()) == 12, "⑧ 玩家连摆 6 张不交替", str(st.deployed_count()))
	_check(int(st.phase) == int(MatchState.Phase.DEPLOY),
			"⑧ 摆满不自动开打", String(MatchState.PHASE_NAME[int(st.phase)]))

	# 直接喂 apply_command 绕过了 UI，得自己补一次刷新，否则「开战」钮的
	# 可见性还停在上一阶段 —— 这不是 bug，是探针的走法天生缺一步。
	s2.call("_refresh_stage")
	await _settle(2)
	# 「开战」必须真按得动
	var fight: Button = (s2.get("_buttons") as Dictionary).get("fight")
	_check(fight != null and fight.visible and not fight.disabled,
			"⑧ 摆完「开战」可点", "vis=%s dis=%s" % [str(fight.visible), str(fight.disabled)])
	fight.pressed.emit()
	await _settle(6)
	_check(int(st.phase) == int(MatchState.Phase.FINAL),
			"⑧ 点开战直接进终局", String(MatchState.PHASE_NAME[int(st.phase)]))
	_check(int(s2.call("_camera_mode")) == MatchArena.CAM_QUICK,
			"⑧ 终局切到快速档", str(s2.call("_camera_mode")))
	_check(not (s2.get("_action_bar") as Control).visible,
			"⑧ 快速档操作栏收掉", "")

	st.winner = 0
	st.end_reason = "clear_field"
	st.phase = MatchState.Phase.OVER
	s2.call("_settle")
	await _settle(8)
	var txt := String(s2.get("_result_label").text)
	_check(txt.contains("快速模式"), "⑧ 结算页标出档位", txt.split("\n")[0])
	_check(int(CharacterData.match_level_cleared) == 1,
			"⑧ 快速首通推进了关卡", str(CharacterData.match_level_cleared))
	_check(int(CharacterData.count_material("mat_duanzaojingshi")) == 8,
			"⑧ 快速首通同样 +8 晶石", str(CharacterData.count_material("mat_duanzaojingshi")))

	s2.call("_return_to_scroll")
	await _settle(30)
	var s3 := get_tree().current_scene
	_check(s3 != null and String(s3.name) == "MatchLevelScroll",
			"⑧ 结算「返回长卷」回到长卷", _name(s3))
	_check(not get_tree().paused, "⑧ 没把 paused 漏给下一个场景", str(get_tree().paused))
	_check(GameState.match_context.is_empty(), "⑧ 关卡上下文已清", str(GameState.match_context))
	if s3 != null and String(s3.name) == "MatchLevelScroll":
		_check(int(s3._current) == 2, "⑧ 回到长卷后当前关推进到第 2 关", str(int(s3._current)))
		_check(bool(CharacterData.match_quick_mode),
				"⑧ 开关状态跨场景保持（存档字段不是会话变量）", str(CharacterData.match_quick_mode))
		s3._back_btn.pressed.emit()
		await _settle(30)
		_check(String(get_tree().current_scene.name) == "PrimordialRealm",
				"⑧ 卷尾返回回主城", _name(get_tree().current_scene))
	CharacterData.match_quick_mode = false
	_finish()


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
