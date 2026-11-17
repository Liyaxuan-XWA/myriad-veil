extends Node
## 新手指引自检（2026-11-10）
## 覆盖：
##   ① 步骤表完整性：id 唯一、文案非空、每步都有「怎么算完成」（事件 / 手动 / 状态）
##   ② 步骤机：事件推进、跨章、跳过、手动确认、老档不弹
##   ③ 章节触发：面板键 / 战斗 / 新号
##   ④ 红点：只认确定性待办，且「看过就清」
##   ⑤ 暂停喂招：进入暂停 → 代按 → 解除（战斗教学的核心链路）
##   ⑥ 锚点解析：找不到时降级为卡片，不报错
## 用法：godot --headless --path . tools/probe_tutorial.tscn -- --no-save

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	var backup: Dictionary = CharacterData.tutorial_data.duplicate(true)
	CharacterData.tutorial_data = {"done": {}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}

	_test_table()
	_test_audit()
	_test_flow()
	_test_legacy()
	_test_triggers()
	_test_badges()
	await _test_pause()
	await _test_layout()
	await _test_anchor()
	await _test_badge_lifecycle()
	await _test_panel_trigger()
	_test_tower_intro()

	CharacterData.tutorial_data = backup


# ===================== ① 表 =====================

func _test_table() -> void:
	var steps := TutorialDB.all_steps()
	_check(steps.size() >= 30, "步骤总数 ≥ 30", str(steps.size()))
	var ids := {}
	var dup := 0
	var no_text := 0
	var no_done := 0
	for raw in steps:
		var s: Dictionary = raw
		var id := String(s.get("id", ""))
		if ids.has(id):
			dup += 1
		ids[id] = true
		if String(s.get("text", "")) == "":
			no_text += 1
		var has_ev := String(s.get("ev", "")) != ""
		var has_cond := String(s.get("cond", "")) != ""
		var manual := bool(s.get("manual", false))
		if not has_ev and not has_cond and not manual:
			no_done += 1
	_check(dup == 0, "步骤 id 无重复", str(dup))
	_check(no_text == 0, "每步都有文案", str(no_text))
	_check(no_done == 0, "每步都有完成方式（事件 / 状态 / 手动）", str(no_done))

	var ch_bad := 0
	for raw in TutorialDB.CHAPTERS:
		var ch: Dictionary = raw
		if String(ch.get("title", "")) == "" or String(ch.get("trigger", "")) == "":
			ch_bad += 1
		if (ch.get("steps", []) as Array).is_empty():
			ch_bad += 1
	_check(ch_bad == 0, "每章都有标题 / 触发键 / 至少一步", str(ch_bad))

	# 步骤 → 章节 反查必须能找到（判定 / 存档都靠它）
	_check(not TutorialDB.get_step("c1_move").is_empty(), "get_step 能按 id 取到步骤")
	_check(TutorialDB.get_chapter("c3").get("trigger", "") == "panel:forge_panel",
		"第 3 章触发键 = 锻造面板", String(TutorialDB.get_chapter("c3").get("trigger", "")))

	# ⚠ 回归（2026-11-10 用户报）：战斗章让玩家「按 Q 放功法」，可新号 learned_skills
	#   开局为空（CharacterData §2.9），空槽按 Q 在 _poll_skill_keys 里直接 continue
	#   → 这一步永远做不完，玩家只能点跳过。
	var skill_step := ""
	for raw in (TutorialDB.get_chapter("c2").get("steps", []) as Array):
		var s: Dictionary = raw
		if String(s.get("ev", "")) == "skill_used":
			skill_step = String(s.get("id", ""))
	_check(skill_step == "", "战斗章不要求放功法（新号一门都没有）", skill_step)
	_check(String(TutorialDB.get_step("c5_cast").get("ev", "")) == "skill_used",
		"功法施放教学挂在拿到功法之后（c5_cast）")

	# ⚠ 用户 2026-11-10：首杀「虎妖」要走完整成长链（捡晶石 → 锻造 → 塔 → 功法）。
	#   第一步必须是「捡晶石」（战斗结算里就开章），触发键改为 after_huyao、
	#   need 钉死 boss_killed:boss_huyao；塔段保留 c5_go / path:Facilities/Tower。
	var c5_first := TutorialDB.first_open_step("c5", {})
	_check(String(c5_first.get("id", "")) == "c5_crystal", "第 5 章从「捡晶石」开始",
		String(c5_first.get("id", "")))
	_check(String(TutorialDB.get_step("c5_go").get("anchor", "")) == "path:Facilities/Tower",
		"c5_go 聚光指到主城塔设施", String(TutorialDB.get_step("c5_go").get("anchor", "")))
	_check(String(TutorialDB.get_chapter("c5").get("trigger", "")).contains("after_huyao"),
		"第 5 章允许「首杀虎妖」触发", String(TutorialDB.get_chapter("c5").get("trigger", "")))
	_check(String(TutorialDB.get_chapter("c5").get("need", "")) == "boss_killed:boss_huyao",
		"第 5 章前置钉死虎妖本体", String(TutorialDB.get_chapter("c5").get("need", "")))
	# 教学必成：全表只有强化教学这一步允许 force_success
	var forced: Array = []
	for raw_s in TutorialDB.all_steps():
		var s2: Dictionary = raw_s
		if bool(s2.get("force_success", false)):
			forced.append(String(s2.get("id", "")))
	_check(forced == ["c5_enhance"], "force_success 只挂在强化教学步上", ", ".join(forced))


# ===================== ② 步骤机 =====================

func _test_flow() -> void:
	Tutorial.start_chapter("c1")
	_check(Tutorial.active_chapter == "c1", "start_chapter 进入第 1 章")
	_check(Tutorial.active_step.get("id", "") == "c1_move", "停在第 1 步 c1_move")

	# 位移不够不推进
	Tutorial.note("moved", 100.0)
	_check(Tutorial.active_step.get("id", "") == "c1_move", "位移不足 240 不推进")
	Tutorial.note("moved", 200.0)
	_check(Tutorial.active_step.get("id", "") == "c1_gate", "累计 300 位移 → 进入 c1_gate")

	# 事件带参数：别的面板不算
	Tutorial.note("panel_opened:forge_panel")
	_check(Tutorial.active_step.get("id", "") == "c1_gate", "别的面板不推进 c1_gate")
	Tutorial.note("panel_opened:domain_panel")
	_check(Tutorial.active_step.get("id", "") == "c1_enter", "打开万界秘境 → c1_enter")

	Tutorial.note("battle_started:domain")
	_check(Tutorial.active_step.get("id", "") == "c1_win", "进凡界战斗 → c1_win")
	Tutorial.note("boss_died")
	_check(Tutorial.active_step.get("id", "") == "c1_bag", "击杀 BOSS → c1_bag")
	Tutorial.note("bag_opened")
	_check(Tutorial.active_chapter == "", "第 1 章走完自动收尾")
	_check(Tutorial.is_done("c1_move") and Tutorial.is_done("c1_bag"),
		"完成标记写进 tutorial_data.done")

	# 跳过：算完成，不再回来
	Tutorial.start_chapter("c2")
	Tutorial.skip_step()
	_check(Tutorial.is_done("c2_attack"), "跳过也会记完成（不反复烦人）")
	_check(Tutorial.active_step.get("id", "") == "c2_parry", "跳过推进到下一步")

	# 手动确认
	Tutorial.active_step = TutorialDB.get_step("c2_blood")
	Tutorial.complete_current()
	_check(Tutorial.is_done("c2_blood"), "「知道了」类步骤靠 complete_current 完成")


# ===================== ③ 老档 =====================

func _test_legacy() -> void:
	CharacterData.tutorial_data = {"legacy": true}
	Tutorial.active_chapter = ""
	Tutorial.maybe_start("new")
	_check(Tutorial.active_chapter == "", "老档不自动弹引导")
	CharacterData.tutorial_data = {"done": {}}


# ===================== ④ 触发 =====================

func _test_triggers() -> void:
	Tutorial.active_chapter = ""
	Tutorial.maybe_start("panel:forge_panel")
	_check(Tutorial.active_chapter == "c3", "首次打开锻造台 → 第 3 章",
		Tutorial.active_chapter)

	# 做过一半的章不会再从头开
	Tutorial.active_chapter = ""
	Tutorial.start_chapter("c3")
	Tutorial.skip_step()
	Tutorial.active_chapter = ""
	Tutorial.maybe_start("panel:forge_panel")
	_check(Tutorial.active_step.get("id", "") == "c3_enhance",
		"重开章节从没做的那步继续", String(Tutorial.active_step.get("id", "")))

	# 全做完的章不再触发
	CharacterData.tutorial_data = {"done": {}}
	for raw in (TutorialDB.get_chapter("c3").get("steps", []) as Array):
		var sid := String((raw as Dictionary).get("id", ""))
		(CharacterData.tutorial_data["done"] as Dictionary)[sid] = true
	Tutorial.active_chapter = ""
	Tutorial.maybe_start("panel:forge_panel")
	_check(Tutorial.active_chapter == "", "整章做完不再触发")


# ===================== ⑤ 红点 =====================

func _test_badges() -> void:
	CharacterData.tutorial_data = {"done": {}, "unseen_items": 0}
	_check(Tutorial.badge_count("bag") == 0, "没有新东西时背包红点不亮")
	CharacterData.tutorial_data["unseen_items"] = 3
	_check(Tutorial.badge_count("bag") == 3, "新物品数量就是红点数")
	Tutorial.mark_seen("bag")
	_check(Tutorial.badge_count("bag") == 0, "打开背包后红点清零")

	# 成就红点：未领取数 ≥ 0 且是纯读（调两次结果一致）
	var a := Tutorial.badge_count("achievement")
	var b := Tutorial.badge_count("achievement")
	_check(a == b and a >= 0, "成就红点是纯读（多次调用一致）", "%d/%d" % [a, b])


# ===================== ⑥ 暂停喂招 =====================

func _test_pause() -> void:
	var got := []
	var cb := func() -> void: got.append("parry")
	Tutorial.pause_parry.connect(cb)
	Tutorial.pause_prompt("它抬手了")
	_check(Tutorial.is_pause_prompt(), "进入暂停喂招")
	_check(get_tree().paused, "树真的暂停了（BOSS 前摇被冻住）")
	Tutorial.call("_on_pause_parry")
	_check(got.size() == 1, "右键回调能到战斗侧")
	Tutorial.resume()
	_check(not get_tree().paused, "解除暂停")
	Tutorial.pause_parry.disconnect(cb)

	# 跳过：不代按，只解暂停
	var skipped := []
	var cb2 := func() -> void: skipped.append("skip")
	Tutorial.pause_skip.connect(cb2)
	Tutorial.pause_prompt("它抬手了")
	Tutorial.call("_on_pause_skip")
	Tutorial.resume()
	_check(skipped.size() == 1, "跳过回调能到战斗侧")
	Tutorial.pause_skip.disconnect(cb2)


# ===================== ⑦ 锚点 =====================

func _test_anchor() -> void:
	var overlay: Node = Tutorial.get("_overlay") as Node
	_check(overlay != null, "引导浮层已创建")
	var hit: Variant = overlay.call("_resolve_anchor", "meta:不存在的键")
	_check(hit == null, "找不到锚点返回 null（降级成卡片，不报错）")
	var bad_path: Variant = overlay.call("_resolve_anchor", "path:不存在的节点")
	_check(bad_path == null, "节点路径不存在也返回 null")

	# ⚠ 回归（2026-11-10 踩过）：世界设施是 Area2D 而不是 Control。
	#   旧代码写 `node as Control`，对 Area2D 恒为 null → 所有 path:Facilities/* 静默降级，
	#   截图里「万界秘境」根本没有聚光。这里用一个假设施把这条链路钉死。
	var host := Node2D.new()
	host.name = "Facilities"
	get_tree().root.add_child(host)
	var gate := Area2D.new()
	gate.name = "DomainGate"
	gate.position = Vector2(300.0, 200.0)
	host.add_child(gate)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120.0, 80.0)
	cs.shape = rect
	gate.add_child(cs)

	var got: Variant = overlay.call("_resolve_anchor", "path:Facilities/DomainGate")
	_check(got is Node2D, "Area2D 设施能被 path: 锚点找到", str(got))
	var box = overlay.call("_rect_of", got)
	_check(box != null and absf(box.size.x - 120.0) < 1.0 and absf(box.size.y - 80.0) < 1.0,
		"设施聚光框取碰撞体尺寸 120×80", str(box))

	# 走一遍真步骤：c1_gate 的锚点就是这个设施，必须真的画出聚光（不是降级）
	Tutorial.active_chapter = "c1"
	Tutorial.active_step = TutorialDB.get_step("c1_gate")
	overlay.call("_refresh_card")
	_check(bool(overlay.get("_has_target")), "c1_gate 真的指到了目标（不是降级）", str(overlay.get("_target_rect")))

	# 真面板：锻造台三个锚点必须指到具体控件。
	# ⚠ 只查「字符串存在」不够 —— 键挂错父节点 / 控件被隐藏时同样指不到
	#   （2026-11-12 起找不到就是 null、浮层整块藏，不再回落到整块面板）。
	#   这里额外卡一条：聚光框不能大过 900px（那说明圈到的是整块面板，指得毫无意义）。
	var panel: Node = (load("res://scripts/ui/panels/forge_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	panel.call("open")
	for i in 8:
		await get_tree().process_frame
	for key in ["forge.slot", "forge.enhance", "forge.tab_synth"]:
		var n: Variant = overlay.call("_resolve_anchor", "meta:" + key)
		var rr: Rect2 = Rect2()
		if n != null:
			rr = overlay.call("_rect_of", n)
		_check(n != null and rr.size.x > 8.0, "锻造台锚点 %s 指到真实控件" % key, str(rr.size))
		_check(rr.size.x < 900.0, "锻造台锚点 %s 不是整面板兜底" % key, str(rr.size))
	panel.call("close")          # close() 内部已经 queue_free，别再调一次（会报 previously freed）
	await get_tree().process_frame
	await get_tree().process_frame

	host.queue_free()
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}


# ===================== ⑧ 布局 =====================

func _test_layout() -> void:
	# ⚠ 回归：PanelContainer 直接挂在 CanvasLayer 下不会随内容收缩，
	#   首帧按「宽度≈1」换行算出的高度会把它撑到 900+ px 且永不回落。
	# 2026-11-11：旧教学清单已重置成顺序任务面板（quest_panel.gd，挂 Quest 下），
	#   这条回归跟着改守任务面板（同样直接挂 CanvasLayer，同坑）。
	CharacterData.tutorial_data = {"done": {}}
	CharacterData.quest_data = {"done": {}}
	Tutorial.start_chapter("c1")
	for i in 3:
		await get_tree().process_frame
	var overlay: Node = Tutorial.get("_overlay") as Node
	var card: Control = overlay.get("_card") as Control
	_check(card.size.y > 0.0 and card.size.y < 200.0, "说明卡高度正常", str(card.size))
	var qp: Node = Quest.get("_panel") as Node
	_check(qp != null, "任务面板已由 Quest 自建")
	if qp != null:
		# 2026-11-11 用户第二次收紧：任务面板**只在原初位面、且没有面板开着时**露脸。
		# 这里不是主城（探针自身就是当前场景）→ 必须整块藏起来。
		# 面板几何回归（宽恒定 / 高度收敛）挪到 probe_quest_panel 的真实主城里验，
		# 不在这里造主城（那会把教学章节和存档初始化搅进来）。
		var lst: Control = qp.get("_box") as Control
		_check(not lst.visible, "非原初位面：任务面板整块不显示")
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	CharacterData.tutorial_data = {"done": {}}
	CharacterData.quest_data = {"done": {}}


# ===================== ⑨ 红点生命周期 =====================

## ⚠ 回归（2026-11-10 编辑器报错）：离开主城时 HUD 按钮被释放，但 _badges 里的条目
##   还指着它，0.5 秒一次的轮询拿已释放对象去 call →
##   "previously freed is not a subclass of the expected argument class"，无限刷屏。
##   这里连验三件事：重复挂载去重 / 释放后剔除 / 重建后能重新挂上。
func _test_badge_lifecycle() -> void:
	var overlay: Node = Tutorial.get("_overlay") as Node
	Tutorial.set("_badges", [])
	Tutorial.set("_last_badges", {})
	(overlay.get("_badge_dots") as Dictionary).clear()

	var holder := Control.new()
	add_child(holder)
	var btn := Control.new()
	btn.size = Vector2(80.0, 30.0)
	holder.add_child(btn)

	Tutorial.attach_badge(btn, "codex")
	Tutorial.attach_badge(btn, "codex")
	_check((Tutorial.get("_badges") as Array).size() == 1, "同一按钮重复挂载只记一条",
		str((Tutorial.get("_badges") as Array).size()))
	_check((overlay.get("_badge_dots") as Dictionary).size() == 1, "浮层也只挂一个红点",
		str((overlay.get("_badge_dots") as Dictionary).size()))

	# 模拟「离开主城」：按钮连同它的红点一起被释放
	btn.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check((Tutorial.call("_live_badges") as Array).is_empty(),
		"按钮释放后悬空条目被剔除", "剩 %d 条" % (Tutorial.get("_badges") as Array).size())

	# 修复前这一句就会抛 previously freed（参数是已释放对象）
	Tutorial.call("_tick_badges", 0.6)
	_check((Tutorial.get("_badges") as Array).is_empty(),
		"轮询不会把失效条目再塞回去", "剩 %d 条" % (Tutorial.get("_badges") as Array).size())

	# 重建 HUD：新按钮能挂上，且死键已被清（实例 id 复用不会误判成「已挂过」）
	var btn2 := Control.new()
	btn2.size = Vector2(80.0, 30.0)
	holder.add_child(btn2)
	Tutorial.attach_badge(btn2, "codex")
	_check((overlay.get("_badge_dots") as Dictionary).size() == 1, "重建后红点表不留死键",
		str((overlay.get("_badge_dots") as Dictionary).size()))
	_check((Tutorial.get("_badges") as Array).size() == 1, "新按钮重新登记成功",
		str((Tutorial.get("_badges") as Array).size()))

	holder.queue_free()
	await get_tree().process_frame
	Tutorial.set("_badges", [])
	Tutorial.set("_last_badges", {})
	(overlay.get("_badge_dots") as Dictionary).clear()


# ===================== ⑩ 埋点 / 锚点静态审计 =====================

## ⚠ 用户 2026-11-10 报「指引让我放技能，可我没有技能」——这类「步骤写了、代码里没人报」
##   的死步骤，手测很难抓全（玩家只会卡住然后跳过）。这里直接扫源码兜底：
##   · 表里每个 ev 必须在某处出现 note("<ev>…")
##   · 表里每个 meta 锚点必须在某处出现 set_meta("tut", "<key>")
##   ⚠ 只扫字面量：写成三元/拼接（a if x else b）会漏，所以锚点键一律写全字面量。
func _test_audit() -> void:
	var files: Array = []
	_collect_gd("res://scripts", files)
	_check(files.size() > 50, "源码清单读全", str(files.size()))
	var src := ""
	for f in files:
		var fa := FileAccess.open(String(f), FileAccess.READ)
		if fa != null:
			src += fa.get_as_text()

	var dead_ev: Array = []
	var dead_anchor: Array = []
	var dead_path: Array = []
	# path: 锚点指向主城设施（Area2D），不在 scripts 里 → 直接对场景文件校验
	var realm_tscn := ""
	var rf := FileAccess.open("res://scenes/main/primordial_realm.tscn", FileAccess.READ)
	if rf != null:
		realm_tscn = rf.get_as_text()
	for raw in TutorialDB.all_steps():
		var s: Dictionary = raw
		var sid := String(s.get("id", ""))
		var ev := String(s.get("ev", ""))
		if ev != "":
			var base: String = ev.split(":")[0]
			if not src.contains("note(\"%s" % base):
				dead_ev.append("%s→%s" % [sid, base])
		var anchor := String(s.get("anchor", ""))
		if anchor.begins_with("meta:"):
			var key := anchor.trim_prefix("meta:")
			if not src.contains("set_meta(\"tut\", \"%s\")" % key):
				dead_anchor.append("%s→%s" % [sid, key])
		elif anchor.begins_with("path:Facilities/"):
			# ⚠ 只写对字符串没用：节点名错一个字，聚光就静默降级成卡片
			var nm := anchor.trim_prefix("path:Facilities/")
			if not realm_tscn.contains(
					'[node name="%s" type="Area2D" parent="Facilities"' % nm):
				dead_path.append("%s→%s" % [sid, nm])
	_check(dead_ev.is_empty(), "每个事件埋点真的有人报（没有永远做不完的步骤）",
		", ".join(dead_ev))
	_check(dead_anchor.is_empty(), "每个 meta 锚点真的挂在控件上（不会静默降级）",
		", ".join(dead_anchor))
	_check(dead_path.is_empty(), "每个 path 锚点在主城场景里真的有这个设施",
		", ".join(dead_path))

	# 章节 need 前置键：写错一个字母这章就永远不开（不报错、不弹卡片）
	var dead_need: Array = []
	for raw in TutorialDB.CHAPTERS:
		var ch: Dictionary = raw
		var need := String(ch.get("need", ""))
		if need != "" and not src.contains("\"%s\":" % need):
			dead_need.append("%s→%s" % [String(ch.get("id", "")), need])
	_check(dead_need.is_empty(), "章节 need 前置键真的在 _cond_met 里实现",
		", ".join(dead_need))


func _collect_gd(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not n.begins_with("."):
			var full := dir_path + "/" + n
			if d.current_is_dir():
				_collect_gd(full, out)
			elif n.ends_with(".gd"):
				out.append(full)
		n = d.get_next()
	d.list_dir_end()


# ===================== ⑪ 面板触发链路 =====================

## ⚠ 回归（2026-11-10 查「首杀回城不触发万界塔」时发现）：
##   第 3 / 4 / 5 章的 trigger 写的是 `panel:xxx_panel`，但 SystemPanel.open()
##   只 note 事件、从没调 maybe_start → 这三章永远不会开始。
##   这里用真面板打开一次，把「打开面板 → 开章」这条链路钉死。
func _test_panel_trigger() -> void:
	CharacterData.tutorial_data = {"done": {}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	var panel: Node = (load("res://scripts/ui/panels/forge_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	panel.call("open")
	await get_tree().process_frame
	_check(Tutorial.active_chapter == "c3",
		"打开锻造面板真的会开始第 3 章（不止记事件）", Tutorial.active_chapter)
	panel.call("close")          # close() 内部已经 queue_free，别再调一次
	await get_tree().process_frame
	await get_tree().process_frame
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	CharacterData.tutorial_data = {"done": {}}


# ===================== ⑫ 首杀 BOSS 回城 → 万界塔 =====================

## 用户 2026-11-10：第一次击败 BOSS 后回原初位面要触发万界塔指引。
## 两条路都必须通：
##   · 第 1 章还停在「回城开背包」→ 只排队，那步做完自动接上（不打断清单）
##   · 第 1 章已做完 → 回城立刻开，聚光直接指到塔
func _test_tower_intro() -> void:
	var saved_done: Dictionary = CharacterData.tutorial_data.duplicate(true)
	var saved_boss: Dictionary = CharacterData.boss_progress.duplicate(true)

	CharacterData.tutorial_data = {"done": {}}
	CharacterData.boss_progress = {}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	CharacterData.force_enhance_success = false
	_check(not Tutorial.has_killed_boss(), "没打过 BOSS 不算首杀")
	Tutorial.request_chapter_by_trigger("after_huyao")
	_check(Tutorial.active_chapter == "", "没打过 BOSS 时不会开局去塔")
	# need 钉死虎妖：杀了别的 BOSS（理论上不可能先于虎妖）也不许开这一章
	CharacterData.boss_progress = {"probe_boss": {"killed": true, "first_kill": true}}
	Tutorial.request_chapter_by_trigger("after_huyao")
	_check(Tutorial.active_chapter == "", "首杀的不是虎妖时不开成长链")

	CharacterData.boss_progress = {"boss_huyao": {"killed": true, "first_kill": true}}
	_check(Tutorial.has_killed_boss(), "首杀虎妖后回城 → 该引导去塔")

	var c1_steps: Array = TutorialDB.get_chapter("c1").get("steps", [])
	# 首杀回城时第 1 章正停在最后一步「回城开背包」
	for i in range(c1_steps.size() - 1):
		(CharacterData.tutorial_data["done"] as Dictionary)[
			String((c1_steps[i] as Dictionary).get("id", ""))] = true
	Tutorial.start_chapter("c1")
	_check(Tutorial.active_step.get("id", "") == "c1_bag", "回城时第 1 章停在开背包",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.request_chapter_by_trigger("after_huyao")
	_check(Tutorial.active_chapter == "c1", "还有章在做时不打断")
	_check(String(Tutorial.get("_queued_chapter")) == "c5", "成长链排进队列",
		String(Tutorial.get("_queued_chapter")))
	Tutorial.note("bag_opened")
	_check(Tutorial.active_chapter == "c5", "第 1 章收尾后自动接上成长链",
		Tutorial.active_chapter)
	_check(Tutorial.active_step.get("id", "") == "c5_crystal", "成长链从「捡晶石」开始",
		String(Tutorial.active_step.get("id", "")))
	# 战斗内链路：捡晶石 → 返回 → 锻造（上砧 / 拿锤 / 强化必成 / 取下 / 拖装）→ 塔选层
	Tutorial.note("item_picked:mat_duanzaojingshi")
	_check(Tutorial.active_step.get("id", "") == "c5_return", "捡到晶石 → 教返回",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("returned_realm")
	_check(Tutorial.active_step.get("id", "") == "c5_forge", "回城 → 教开锻造",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("panel_opened:forge_panel")
	_check(Tutorial.active_step.get("id", "") == "c5_place", "开锻造 → 教上砧",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("forge_place")
	_check(Tutorial.active_step.get("id", "") == "c5_hammer", "上砧 → 教拿锤",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("forge_hammer")
	_check(Tutorial.active_step.get("id", "") == "c5_enhance", "拿锤 → 教强化",
		String(Tutorial.active_step.get("id", "")))
	_check(bool(CharacterData.force_enhance_success),
		"强化教学步激活期间必成旗标打开")
	Tutorial.note("forge_enhance")
	_check(Tutorial.active_step.get("id", "") == "c5_take", "强化 → 教取下",
		String(Tutorial.active_step.get("id", "")))
	_check(not bool(CharacterData.force_enhance_success),
		"离开强化步必成旗标立刻复位")
	Tutorial.note("forge_take")
	_check(Tutorial.active_step.get("id", "") == "c5_equip", "取下 → 教拖装",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("gear_equipped")
	_check(Tutorial.active_step.get("id", "") == "c5_go", "穿回铁剑 → 教去万界塔",
		String(Tutorial.active_step.get("id", "")))
	# 玩家走过去 / 按 F 打开塔面板 → 这一步完成，接「选一层」
	Tutorial.note("panel_opened:tower_panel")
	_check(Tutorial.active_step.get("id", "") == "c5_pick", "打开塔面板 → 选一层挑战",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("tower_floor_pick")
	_check(Tutorial.active_step.get("id", "") == "c5_start", "选层 → 教点挑战",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("tower_challenge")
	_check(Tutorial.active_step.get("id", "") == "c5_first", "点挑战 → 教击败投影",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("boss_died")
	_check(Tutorial.active_step.get("id", "") == "c5_insight", "击败 → 教感悟收下",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("skill_learned")
	_check(Tutorial.active_step.get("id", "") == "c5_loot", "收下 → 教捡晶石",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("item_picked:mat_duanzaojingshi")
	_check(Tutorial.active_step.get("id", "") == "c5_back", "捡完 → 教返回",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("returned_realm")
	_check(Tutorial.active_step.get("id", "") == "c5_book", "回城 → 教开功法库",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("panel_opened:skill_panel")
	_check(Tutorial.active_step.get("id", "") == "c5_equip_skill", "开库 → 教装 Q 槽",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("skill_slotted")
	_check(Tutorial.active_step.get("id", "") == "c5_cast", "装好 → 教按 Q",
		String(Tutorial.active_step.get("id", "")))
	Tutorial.note("skill_used")
	_check(Tutorial.active_chapter == "", "整条链走完收章", Tutorial.active_chapter)

	# 第 1 章早做完了：回城应该立刻开，不等任何事件
	CharacterData.tutorial_data = {"done": {}}
	for raw in c1_steps:
		(CharacterData.tutorial_data["done"] as Dictionary)[
			String((raw as Dictionary).get("id", ""))] = true
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	Tutorial.request_chapter_by_trigger("after_huyao")
	_check(Tutorial.active_chapter == "c5", "第 1 章做完 → 回城立刻开成长链",
		Tutorial.active_chapter)
	_check(String(Tutorial.get("_queued_chapter")) == "", "没有多余排队")

	# 成长链做完后不再重复触发
	for raw in (TutorialDB.get_chapter("c5").get("steps", []) as Array):
		(CharacterData.tutorial_data["done"] as Dictionary)[
			String((raw as Dictionary).get("id", ""))] = true
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.request_chapter_by_trigger("after_huyao")
	_check(Tutorial.active_chapter == "", "整章做完后回城不再弹")

	CharacterData.tutorial_data = saved_done
	CharacterData.boss_progress = saved_boss
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	CharacterData.force_enhance_success = false
