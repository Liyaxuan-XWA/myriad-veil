extends Node
## 顺序任务面板自检（2026-11-11）
## 覆盖：静态审计（ev 有埋点 / cond 有实现 / 13 条唯一 / detail 长度粗筛 + 逐条实测高度）、
##       顺序解锁、事件推进、cond 轮询、会话缓冲乱序兜底、_ev_match 语义、
##       存档快照字段、面板几何（宽度恒定 / 高度有界）、
##       露脸条件（只在原初位面 / 系统面板·背包·确认框打开时藏起来）。
## 用法：godot --headless --path . res://tools/probe_quest_panel.tscn -- --no-save

const REALM_SCENE := "res://scenes/main/primordial_realm.tscn"

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
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


## 时序断言：轮询直到条件满足或超时（探针铁律：不数秒、用 ticks 轮询）
func _wait_until(fn: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(fn.call()):
			return true
		await get_tree().process_frame
	return bool(fn.call())


## 真实点击：push_input 走完整 GUI 分发
## ⚠ 探针铁律：别用 `pressed.emit()` —— 那样按钮被别的控件盖住、或 mouse_filter 写错都测不出来，
##   玩家点不到时探针照样全绿。
## ⚠ 必须传 `in_local_coords=true`：默认 false 时坐标要过 `get_final_transform()`（窗口 → viewport
##   的 stretch 变换），headless 下窗口尺寸和 viewport 不一致，点击会落到空处（hover 恒为 null），
##   表现为「探针点了没反应」而按钮本身完全正常。
func _click(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	get_viewport().push_input(m, true)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = pos
	d.global_position = pos
	get_viewport().push_input(d, true)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = pos
	u.global_position = pos
	get_viewport().push_input(u, true)


## 驱动**真实**制符路径：开 TalismanPanel → 符匣 → 走笔结算。
## 返回 = 任务 q_draw_talisman 是否因此打勾。
## ⚠ 只挑「本境界 100% 成功」的符方（`talisman_success_rate` 在玩家境界 ≥ 符方境界时返回 1.0），
##   否则 craft_talisman 里的 randf() 会让探针偶发假红。
func _craft_one_talisman_for_real() -> bool:
	var rec: Dictionary = {}
	for raw in ItemDB.all_talisman_recipes():
		var r: Dictionary = raw
		if float(ItemDB.talisman_success_rate(String(r.get("realm", "")))) >= 1.0:
			rec = r
			break
	if rec.is_empty():
		return false
	for k in (rec.get("materials", {}) as Dictionary).keys():
		CharacterData.add_item({"id": String(k), "count": 8})
	CharacterData.realm_exp = maxf(CharacterData.realm_exp, 9999.0)
	var sp = (load("res://scripts/ui/panels/talisman_panel.gd") as GDScript).new()
	get_tree().root.add_child(sp)
	sp.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var ok := false
	# 符匣是制符台在 open() 里动态挂上去的子面板，字段名 = _elem_cabinet
	var cab: Node = sp.get("_elem_cabinet")
	if cab != null and is_instance_valid(cab):
		var before := int(CharacterData.talisman_stock.size())
		cab.call("_open_brush", rec)
		await get_tree().process_frame
		cab.call("_set_brush_batch", 1)
		await get_tree().process_frame
		cab.call("_finish_brush")
		await get_tree().process_frame
		# 成品确实进匣了才算这道题出成（否则「没打勾」可能只是根本没做成东西）
		ok = int(CharacterData.talisman_stock.size()) > before \
				and Quest.is_done("q_draw_talisman")
	# ⚠ 无论成败都必须关掉面板：SystemPanel.open() 把整棵树 paused 了，漏关会连带
	#   把后面的用例全部污染（实测「原初位面露脸 / 面板几何」整片假红）
	sp.close()
	await get_tree().process_frame
	return ok


## 驱动**真实**主模式施符：往符匣塞两张不需要目标的符，真的走一遍 use_talisman()。
## 选水愈符·练气（effect=regen_hp）：金锋/火球/引雷/木缚都要「附近最近目标」，
## 探针场上没有 BOSS 会被 _talisman_needs_target 那关直接拒掉 → 假阴性。
## ⚠ 拆成三条独立断言而不是一个 bool：施放返回值、是否真扣符、任务是否打勾
##   是三件不同的事，合成一条就只知道「没过」而不知道卡在哪一关。
## ⚠ 玩家**不要提前 queue_free**：符卡 FX 挂在探针节点下、落点那一帧才结算，
##   它还要读施法者的 global_position，人先没了就是 previously freed 报错。
func _use_one_talisman_for_real() -> void:
	var item_id := "tal_shuihui_lianqi"
	CharacterData.talisman_stock[item_id] = int(CharacterData.talisman_stock.get(item_id, 0)) + 2
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	# ⚠ 登场演出会吞输入并挡住动作；探针要立刻施放就得先把这层收掉
	p.set("is_teleporting", false)
	p.set("invincible_timer", 999.0)
	p.set("mana", float(p.get("max_mana")))
	await get_tree().process_frame
	var before := int(CharacterData.talisman_stock.get(item_id, 0))
	# ⚠ 必须显式摆成真实位面：`BattleResolver.current_source()` 在 battle_context
	#   为空时**默认返回 arena**，于是 use_talisman 会走演武场那条「不扣符」分支，
	#   施放照样成功、任务照样打勾，但「符被扣掉一张」永远验不到（第一版就栽在这）。
	GameState.battle_context = {"source": "domain", "domain_id": "domain_01", "boss_id": "boss_01"}
	var ok := bool(p.call("use_talisman", item_id))
	var after := int(CharacterData.talisman_stock.get(item_id, 0))
	GameState.battle_context = {}
	_check(ok, "⑫ use_talisman 返回成功", "before=%d after=%d" % [before, after])
	_check(after == before - 1, "⑫ 真实位面里符匣确实少了一张（演武场才免符）",
			"%d → %d" % [before, after])
	await get_tree().process_frame
	_check(Quest.is_done("q_use_talisman"), "⑫ 施放后任务打勾（撤掉埋点必红）")


func _run() -> void:
	print("\n########## 顺序任务面板 ##########")
	await get_tree().process_frame

	# ===== 1. 静态审计：表完整 + ev 有埋点 + cond 有实现 =====
	var ids := {}
	for raw in QuestDB.QUESTS:
		var q: Dictionary = raw
		var id := String(q.get("id", ""))
		_check(id != "" and not ids.has(id), "任务 id 唯一", id)
		ids[id] = true
		var detail := String(q.get("detail", ""))
		# ⚠ 11-12：这里原来掐 48 字。但 48 只是「别把卡撑变形」的**代理指标**，
		#   真正的界是下面 §几何那两条（宽度恒定 / 高度 <200）。现在改成宽松的
		#   88 字防跑飞，加长与否由**实测高度**裁决 —— 不是把数字改大就算通过。
		_check(detail != "" and detail.length() <= 88,
			"指引一句话别写成长段（防跑飞，变形由实测高度裁决）",
			"%s %d 字" % [id, detail.length()])
	_check(QuestDB.QUESTS.size() == 13, "任务总数 13（11-12 加了练气区核心这条）", str(QuestDB.QUESTS.size()))

	# 收集 scripts/**.gd 全部源码，提取 note("...") 字面量集合
	var files: Array = []
	_collect_gd("res://scripts", files)
	var note_kinds := {}
	var re := RegEx.new()
	re.compile("note\\(\"([A-Za-z0-9_:]+)\"")
	for fp in files:
		var txt := (FileAccess.open(fp, FileAccess.READ) as FileAccess).get_as_text()
		for m in re.search_all(txt):
			# ⚠ 动态拼接埋点（note("craft_done:" + kind)）提取出来带尾冒号 → 去掉再入集合
			var kind := String((m as RegExMatch).get_string(1)).trim_suffix(":")
			note_kinds[kind] = true
	var runner_src := (FileAccess.open("res://scripts/tutorial/quest_runner.gd",
		FileAccess.READ) as FileAccess).get_as_text()
	var tut_src := (FileAccess.open("res://scripts/tutorial/tutorial_runner.gd",
		FileAccess.READ) as FileAccess).get_as_text()
	_check(tut_src.contains("Quest.on_event"),
		"Tutorial.note 已转发给任务系统（撤转发 = 事件全断）")
	for raw in QuestDB.QUESTS:
		var q: Dictionary = raw
		var ev := String(q.get("ev", ""))
		var cond := String(q.get("cond", ""))
		if ev != "":
			# ev 带参只比基础名（craft_done:pill → craft_done），与 runner._ev_match 同口径
			var base := ev.split(":")[0]
			_check(note_kinds.has(ev) or note_kinds.has(base),
				"事件键有真实埋点", "%s → %s" % [String(q.get("id", "")), ev])
		if cond != "":
			_check(runner_src.contains("\"" + cond + "\""),
				"cond 键在 _cond_met 有实现", "%s → %s" % [String(q.get("id", "")), cond])
	# cond 型任务至少要有一个事件都没配（纯轮询）——表设计自检
	var pure_cond := 0
	for raw in QuestDB.QUESTS:
		var q: Dictionary = raw
		if String(q.get("ev", "")) == "" and String(q.get("cond", "")) != "":
			pure_cond += 1
	_check(pure_cond >= 1, "存在纯 cond 任务（存档级事实）", str(pure_cond))

	# ===== 2. 顺序解锁 + 乱序事件被缓冲 =====
	CharacterData.quest_data = {"done": {}}
	Quest._seen.clear()
	await get_tree().process_frame
	_check(Quest.current_id() == "q_kill_huyao", "开局当前任务 = 击败虎妖", Quest.current_id())
	# 提前发后面任务的事件：不推进，但进会话缓冲（q2/q9 的事件后面靠它补）
	Tutorial.note("forge_enhance")
	Tutorial.note("craft_done:pill")
	_check(Quest.current_id() == "q_kill_huyao", "乱序事件不推进（q2/q9 未解锁）",
		Quest.current_id())

	# ===== 3. cond 轮询完成任务 1（存档级状态） =====
	CharacterData.boss_progress["boss_huyao"] = true
	var q2_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_enhance", 2000)
	_check(q2_ok, "击杀虎妖（cond）→ 解锁强化装备", Quest.current_id())

	# ===== 4. 会话缓冲：q2 激活后，提前发的 forge_enhance 自动补完成 =====
	var q3_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_tower", 2000)
	_check(q3_ok, "缓冲补完成强化（事件发在激活前）", Quest.current_id())

	# ===== 5. cond 轮询完成塔层 =====
	CharacterData.tower_progress[1] = {"unlocked": true, "first_kill": false, "clear_count": 1}
	var q4_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_equip_skill", 2000)
	_check(q4_ok, "塔通关（cond）→ 解锁装备功法", Quest.current_id())

	# ===== 6. 事件推进 =====
	Tutorial.note("skill_slotted")
	var q5_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_break_realm", 2000)
	_check(q5_ok, "装备功法（事件）→ 解锁突破境界", Quest.current_id())

	# ===== 7. cond 轮询完成境界突破 → 材料 =====
	CharacterData.realm_stage = 1
	var q6_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_boss_material", 2000)
	_check(q6_ok, "突破境界（cond）→ 解锁首领材料", Quest.current_id())
	CharacterData.inventory.append({"id": "mat_pojing_lianqi", "count": 1})
	var q7_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_rogue", 2000)
	_check(q7_ok, "破境材料入包（cond）→ 解锁试炼", Quest.current_id())
	# 清掉材料：q6 的 cond 不该把后面的事重复做（已 done 幂等，主要防误判逻辑漂移）
	CharacterData.inventory.pop_back()

	# ===== 8. 手动标 q7/q8 完成 → q9 靠缓冲补（第 2 步发过 craft_done:pill） =====
	var d: Dictionary = CharacterData.quest_data["done"]
	d["q_rogue"] = true
	d["q_match"] = true
	await get_tree().process_frame
	var q10_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_use_pill", 2000)
	_check(q10_ok, "q9 制作丹药靠会话缓冲补完成", Quest.current_id())

	# ===== 9. 后三件全走事件 =====
	Tutorial.note("pill_used")
	var q11_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_draw_talisman", 2000)
	_check(q11_ok, "使用丹药（事件）→ 解锁制符", Quest.current_id())
	# ⚠🚫 不许在这里手喂 Tutorial.note("craft_done:talisman") —— 那正是 2026-11-11
	#   「全绿却完不成」的原因：制符台打开即进符匣，成符走 talisman_cabinet._finish_brush()，
	#   CraftStage 里那句 note("craft_done:" + craft_kind()) 对制符根本不生效。
	#   必须驱动**真实结算路径**，任务才会打勾。
	_check(await _craft_one_talisman_for_real(),
		"制作符纸：走符匣真实成符路径才打勾（撤掉符匣埋点必红）")
	var q12_ok := await _wait_until(func() -> bool: return Quest.current_id() == "q_use_talisman", 2000)
	_check(q12_ok, "制作符纸（事件）→ 解锁使用符纸", Quest.current_id())
	# ⚠🚫 同样不许手喂 Tutorial.note("talisman_used")。11-11 这条任务的口径从
	#   「试炼局内用符」改回「主模式装配+施放」，因为试炼里没有制符台、
	#   而且旧事件只在选了符箓流派的那一局才可能发。这里必须真的施放成功一次。
	await _use_one_talisman_for_real()
	# ===== 9b. 第 13 条：练气区核心首领 → 筑基底髓 =====
	# ⚠ 走 **cond（存档级事实）**这条路，不手喂事件：`_core_kill_table()[rid] = true`
	#   就是生产代码写进 secret_world.core_kills 的形状，这里照写一次，
	#   让 0.5s 轮询自己勾上 —— 先打完首领、任务后来才解锁的玩家靠的就是这条路。
	var ck: Dictionary = CharacterData.secret_world.get("core_kills", {})
	ck["world_lianqi"] = true
	CharacterData.secret_world["core_kills"] = ck
	var q13_ok := await _wait_until(func() -> bool: return Quest.is_done("q_lianqi_core"), 3000)
	_check(q13_ok, "练气区核心击杀（cond）→ 第 13 条打勾", Quest.current_id())
	var all_ok := await _wait_until(func() -> bool: return Quest.all_done(), 2000)
	_check(all_ok, "施放符纸（事件）→ 全部完成", Quest.current_id())

	# ===== 10. _ev_match 语义 =====
	_check(Quest._ev_match("craft_done:pill", "craft_done:pill"), "带参 ev 全等匹配")
	_check(not Quest._ev_match("craft_done:pill", "craft_done:talisman"), "带参 ev 不串门")
	_check(Quest._ev_match("boss_died", "boss_died:boss_01"), "不带参 ev 只比基础名")

	# ===== 10b. 第 13 条的**区域精度** =====
	# ⚠ 埋点原来发裸 `world_core_kill`，四个区的核心首领共用一个键 ——
	#   只配裸 ev 的话，玩家先打结丹区核心也会把这条「练气区」的任务勾掉。
	#   事件名匹配这一层用真实 on_event 验；**埋点侧有没有真的带 region_id**
	#   是另一件事，单独用源码锁（最后两条）—— 两边都锁住才叫闭环。
	var only_last := {}
	for raw_q in QuestDB.QUESTS:
		var qid := String((raw_q as Dictionary).get("id", ""))
		if qid != "q_lianqi_core":
			only_last[qid] = true
	CharacterData.quest_data = {"done": only_last}
	CharacterData.secret_world = {"core_kills": {}}
	Quest._seen.clear()
	Quest.changed.emit()
	await get_tree().process_frame
	_check(Quest.current_id() == "q_lianqi_core", "第 13 条接在链尾", Quest.current_id())
	Quest.on_event("world_core_kill:world_zhuji")
	await get_tree().process_frame
	_check(not Quest.is_done("q_lianqi_core"), "别的区的核心击杀不勾这条（ev 全等匹配）")
	Quest.on_event("world_core_kill:world_lianqi")
	await get_tree().process_frame
	_check(Quest.is_done("q_lianqi_core"), "练气区的核心击杀才勾（事件路径）")
	var sw_src := FileAccess.get_file_as_string("res://scripts/world/secret_world.gd")
	_check(sw_src.contains('"world_core_kill:" + rid'),
		"埋点带 region_id（否则全等匹配永远不命中）")
	_check(not sw_src.contains('Tutorial.note("world_core_kill")'),
		"没有残留裸名埋点（裸名会被任何一区勾走）")
	# 恢复「全部完成」，后面的快照与几何节依赖它
	var all_done_map := {}
	for raw_q2 in QuestDB.QUESTS:
		all_done_map[String((raw_q2 as Dictionary).get("id", ""))] = true
	CharacterData.quest_data = {"done": all_done_map}
	Quest.changed.emit()
	await get_tree().process_frame

	# ===== 11. 存档快照字段 =====
	var snap := SaveManager.capture()
	_check(snap.has("quest_data") and (snap.get("quest_data") as Dictionary).has("done"),
		"capture 带 quest_data")
	var done_n: int = (snap.get("quest_data") as Dictionary).get("done", {}).size()
	_check(done_n == 13, "快照记录 13 条完成", str(done_n))
	SaveManager.apply(snap)
	_check(Quest.all_done(), "apply 回读后进度一致")

	# ===== 12. 露脸条件 + 单任务卡几何（**必须在真实原初位面里验**）=====
	# ⚠ 2026-11-11 用户报：「任务栏浮在万界秘境面板上层」。
	#   面板原先只判「非标题场景」，任何系统面板一开它就压在上面。
	#   这里走真实入口：实例化 primordial_realm.tscn 当 current_scene，
	#   再开真实的 DomainPanel（就是截图里那个「万界秘境」），不手工改标志位。
	# ⚠ 要连 boss_progress 一起清：q1 是 cond 任务，不清的话轮询会立刻把它补完成；
	#   会话缓冲 _seen 也要清，否则推进到 q2 时被旧事件直接顶到 q3。
	CharacterData.tutorial_data = {"legacy": true}    # 教学静默，别弹卡遮住面板
	CharacterData.quest_data = {"done": {}}
	CharacterData.boss_progress = {}
	Quest._seen.clear()
	Quest.set("_poll_left", 99999.0)   # 先压住轮询：主城 _ready 读档会把现场滚走
	var realm := (load(REALM_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(realm)
	get_tree().current_scene = realm
	for i in 3:
		await get_tree().process_frame
	# ⚠ 主城 _ready 会做存档初始化（把 quest_data 覆盖回空表）→ 必须**在它之后**摆现场
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.quest_data = {"done": {}}
	CharacterData.boss_progress = {}
	Quest.set("_poll_left", 99999.0)
	Quest.changed.emit()
	for i in 4:
		await get_tree().process_frame
	var qp: Node = Quest.get("_panel") as Node
	_check(qp != null, "任务面板已由 Quest 自建")
	if qp == null:
		return
	var box: Control = qp.get("_box") as Control
	var name_lb: Label = qp.get("_name") as Label
	var detail_lb: Label = qp.get("_detail") as Label
	_check(box.visible, "原初位面：任务面板显示")
	_check(name_lb.visible, "单任务卡：任务名行可见")
	_check(name_lb.text == "击败虎妖", "第一行就是任务名", name_lb.text)
	_check(detail_lb.text == String(QuestDB.get_quest("q_kill_huyao").get("detail", "")),
		"下面一段是具体怎么做", detail_lb.text)
	_check(name_lb.get_theme_font_size("font_size") >= 18, "任务名字号 ≥ 18（看清）",
		str(name_lb.get_theme_font_size("font_size")))
	_check(detail_lb.get_theme_font_size("font_size") >= 15, "指引字号 ≥ 15（看清）",
		str(detail_lb.get_theme_font_size("font_size")))
	_check(box.size.x >= 280.0 and box.size.x < 340.0, "面板宽度恒定（不变形）", str(box.size))
	_check(box.size.y > 0.0 and box.size.y < 200.0, "单任务卡高度（不再撑到 400+）", str(box.size))

	# ===== 逐条实测：把 12 条 detail 挨个塞进同一张卡，量它会不会变形 =====
	# ⚠ 必须等两帧让 autowrap 重排后再读 size：只 set text 就读，量到的还是上一条的行数。
	var max_h := 0.0
	var worst_id := ""
	var keep_detail := detail_lb.text
	for raw_q in QuestDB.QUESTS:
		var qd: Dictionary = raw_q
		detail_lb.text = String(qd.get("detail", ""))
		await get_tree().process_frame
		await get_tree().process_frame
		if box.size.y > max_h:
			max_h = box.size.y
			worst_id = String(qd.get("id", ""))
	_check(max_h > 0.0 and max_h < 200.0,
		"12 条文案逐条塞进卡里，最高的一条仍 <200（%s）" % worst_id, "%.1f" % max_h)
	_check(box.size.x >= 280.0 and box.size.x < 340.0,
		"加长后宽度依然恒定（不会跟着文字变宽）", str(box.size))
	detail_lb.text = keep_detail
	await get_tree().process_frame

	# 完成当前任务 → 自动换成下一个（cond 轮询：boss_progress 是存档级事实）
	CharacterData.boss_progress["boss_huyao"] = {"killed": true, "first_kill": true}
	Quest.set("_poll_left", 0.0)
	var swapped := await _wait_until(
		func() -> bool: return name_lb.text == "强化装备", 3000)
	_check(swapped, "完成一个才显示下一个", name_lb.text)
	_check(Quest.current_id() == "q_enhance", "确实推进到第 2 个任务", Quest.current_id())
	Quest.set("_poll_left", 99999.0)
	# 收起（2026-11-11 用户第三轮）：主框整块收掉，原位只留小箭头按钮，**不许留长框**
	var tab: Button = qp.get("_tab_btn") as Button
	_check(tab != null, "收起按钮已创建")
	if tab == null:
		return
	qp.call("_toggle_fold")
	for i in 3:
		await get_tree().process_frame
	_check(not box.visible, "收起后主面板整块收起来（不再留长框）")
	_check(tab.visible, "收起后只显示展开按钮")
	_check(tab.size.x <= 44.0 and tab.size.y <= 44.0, "展开按钮是小按钮（≤44px）", str(tab.size))
	# 真实入口：把鼠标推到按钮中心，走完整 GUI 分发（不是直接 emit pressed）
	_check(tab.get_global_rect().size.x > 0.0, "展开按钮有可点面积", str(tab.get_global_rect()))
	_click(tab.get_global_rect().get_center())
	for i in 3:
		await get_tree().process_frame
	_check(box.visible and not tab.visible, "点小箭头 → 面板真的展开")
	_check(box.size.x >= 280.0 and box.size.x < 340.0, "展开后宽度仍是 300（不变形）",
		str(box.size))
	_check(name_lb.visible and name_lb.text == "强化装备", "展开后任务名回来", name_lb.text)

	# ===== 13. 模态界面：任务面板必须让位（不压在任何面板上层）=====
	_check(not GameState.modal_ui_open(), "开局没有模态界面（计数 0）")
	var dlg: SystemPanel = (load("res://scripts/ui/panels/domain_panel.gd") as Script).new() as SystemPanel
	get_tree().root.add_child(dlg)
	dlg.open()
	for i in 3:
		await get_tree().process_frame
	_check(GameState.modal_ui_open(), "打开万界秘境 → 模态计数 +1")
	_check(not box.visible, "系统面板打开时任务面板藏起来（不压上层）")
	dlg.close()
	for i in 3:
		await get_tree().process_frame
	_check(not GameState.modal_ui_open(), "面板关闭 → 计数归零（不泄漏）")
	_check(box.visible, "关闭面板后任务面板恢复")
	# 角色面板（autoload、常驻）：同样要让位
	CharacterPanel.open_panel()
	for i in 3:
		await get_tree().process_frame
	_check(not box.visible, "背包打开时任务面板藏起来")
	CharacterPanel.close_panel()
	for i in 3:
		await get_tree().process_frame
	_check(box.visible and not GameState.modal_ui_open(), "背包关闭后恢复且计数归零")
	# 确认框（layer 110 比任务面板低 → 不藏就会被任务栏压住）
	var cf := ConfirmDialog.ask("自检", "确认框开着时任务面板不该露脸", "确定", "取消",
		func() -> void: pass)
	for i in 3:
		await get_tree().process_frame
	_check(not box.visible, "确认框打开时任务面板藏起来")
	cf.call("_cancel")     # 正常关闭
	for i in 3:
		await get_tree().process_frame
	_check(not GameState.modal_ui_open(), "确认框关闭 → 计数归零")
	_check(box.visible, "确认框消失后任务面板恢复")
	# 被 free（场景切换就是这条路径，不走 _close）也要兜底返还计数
	var cf2 := ConfirmDialog.ask("自检", "被 free 的确认框", "确定", "取消",
		func() -> void: pass)
	for i in 2:
		await get_tree().process_frame
	cf2.free()
	for i in 3:
		await get_tree().process_frame
	_check(not GameState.modal_ui_open(), "确认框被 free → 计数兜底归零")
	get_tree().paused = false

	# ===== 14. 非原初位面：整块不露脸（战斗 / 试炼 / 棋坛 / 大世界同理）=====
	# ⚠ 白名单判定：换成任意非主城场景，任务面板都不该出现。探针自己就是这样一个场景。
	get_tree().current_scene = self
	for i in 3:
		await get_tree().process_frame
	_check(not box.visible, "非原初位面（战斗/试炼/大世界）：任务面板不显示")
	_check(not tab.visible, "非原初位面：收起后的小箭头也不残留")
	get_tree().current_scene = realm
	for i in 3:
		await get_tree().process_frame
	_check(box.visible, "回原初位面：任务面板恢复显示")
	# 收起态穿过场景切换：回来必须还是「只有小箭头」，不能自己弹开也不能丢按钮
	qp.call("_toggle_fold")
	for i in 3:
		await get_tree().process_frame
	_check(tab.visible and not box.visible, "原初位面收起：只剩小箭头")
	get_tree().current_scene = self
	for i in 3:
		await get_tree().process_frame
	_check(not tab.visible, "收起态离开原初位面：小箭头跟着藏")
	get_tree().current_scene = realm
	for i in 3:
		await get_tree().process_frame
	_check(tab.visible and not box.visible, "切回主城：仍是收起态（只小箭头）")
	qp.call("_toggle_fold")          # 展开，给后面的断言留正常现场
	for i in 3:
		await get_tree().process_frame
	_check(box.visible and not tab.visible, "点开恢复完整面板")
	GameState.battle_context = {"source": BattleResolver.SOURCE_DOMAIN, "domain_id": "domain_01"}
	for i in 3:
		await get_tree().process_frame
	_check(box.visible, "原初位面残留战斗上下文：任务面板仍正常显示")
	GameState.battle_context = {}
	get_tree().current_scene = self
	realm.queue_free()
	await get_tree().process_frame

	# ===== 15. 变异守卫：撤掉 Tutorial.note 的转发会让事件全断 =====
	# （真实变异在开发期手动做过：撤转发 → 9 项红；撤缓冲 → 1 红；撤 cond → 3 红）
	_check(QuestDB.get_quest("q_kill_huyao").get("ev", "") == "",
		"任务 1 是纯 cond 任务（boss_progress 是存档级状态）")
	_check(QuestDB.get_quest("no_such").is_empty(), "查无此任务返回空")


func _collect_gd(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if dir.current_is_dir():
			if not f.begins_with("."):
				_collect_gd(full, out)
		elif f.ends_with(".gd"):
			out.append(full)
		f = dir.get_next()
