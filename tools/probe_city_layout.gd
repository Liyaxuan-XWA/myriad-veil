extends Node
## 主城设施与战斗右上角自检（2026-11-02 用户三条要求 / 2026-11-04 补棋坛进度锁）
##   1) 记忆幻像碑暂时封锁（剧情未做）：压暗、点击不开面板、靠近提示说清楚
##   2) 万界秘境与万界塔调换站位，且设施之间不重叠
##   3) 万界棋坛要通关第一位面（凡界三只全杀）才解锁，锁着的时候必须把条件写在脸上
##   4) 通关后重进主城，棋坛的锁要真的自己解开
##   5) 战斗右上角「用时」计时不再被「设置」按钮压住
## 用法：godot --headless --path . tools/probe_city_layout.tscn -- --no-save

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
	print("\n########## 主城设施 / 战斗右上角探针 ##########")
	get_tree().create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		print("PROBE TIMEOUT")
		get_tree().quit(2))

	var scene := (load("res://scenes/main/primordial_realm.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# 主城 HUD 会给图鉴 / 成就（触屏还有背包）挂新手红点
	var badge_n := (Tutorial.get("_badges") as Array).size()
	_check(badge_n >= 2, "主城 HUD 挂上了新手红点", str(badge_n))

	# ===== 1. 记忆幻像碑封锁 =====
	var mem := scene.get_node_or_null("Facilities/Memory") as Node
	_check(mem != null, "记忆幻像碑设施仍在场景里（只是封锁，没删）")
	if mem != null:
		_check(bool(mem.get("is_locked")), "记忆幻像碑标记为暂未开启")
		var tag_found := false
		for c in mem.get_children():
			if c is Label and String((c as Label).text).contains("暂未开启"):
				tag_found = true
		_check(tag_found, "设施名下挂出「暂未开启」小字")
	scene.call("_on_facility_activated", "memory")
	await get_tree().process_frame
	_check(scene.get("_current_panel") == null, "点封锁设施不会打开面板")
	_check(String(scene.hint_label.text).contains("敬请期待"),
		"点击后给出「暂未开启」提示", String(scene.hint_label.text))
	scene.set("_near_facility_id", "memory")
	scene.call("_update_near_hint")
	_check(String(scene.hint_label.text).contains("暂未开启")
		and not String(scene.hint_label.text).contains("按 F 进入"),
		"靠近封锁设施时不再喊「按 F 进入」", String(scene.hint_label.text))
	scene.set("_near_facility_id", "")
	scene.call("_update_near_hint")

	# 别的设施不受影响
	scene.call("_on_facility_activated", "tower")
	await get_tree().process_frame
	var tp = scene.get("_current_panel")
	_check(tp != null, "万界塔设施仍可正常打开", str(tp))
	if tp != null and tp.has_method("close"):
		tp.call("close")
		await get_tree().process_frame

	# ===== 2. 万界秘境 / 万界塔换位置 =====
	var tower := scene.get_node("Facilities/Tower") as Node2D
	var gate := scene.get_node("Facilities/DomainGate") as Node2D
	_check(tower.position == Vector2(520, -300), "万界塔挪到原万界秘境的位置", str(tower.position))
	_check(gate.position == Vector2(0, -140), "万界秘境挪到原万界塔的位置", str(gate.position))
	var spots := {}
	for f in scene.get_node("Facilities").get_children():
		if f is Node2D:
			spots[String(f.get("facility_id"))] = (f as Node2D).position
	var too_close := ""
	var ids: Array = spots.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if (spots[ids[i]] as Vector2).distance_to(spots[ids[j]] as Vector2) < 130.0:
				too_close += "%s~%s " % [ids[i], ids[j]]
	_check(too_close == "", "九个设施站位互不重叠（≥130px）", too_close)
	_check(spots.has("domain_gate") and spots.has("tower") and spots.size() == 9,
			"设施数量是九个（含万界棋坛）", "n=%d" % spots.size())

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ===== 3. 万界棋坛：通关第一位面才解锁（2026-11-04 用户要求）=====
	# 探针跑在 --no-save 的空档上，凡界一只没打 → 这里必须是锁着的
	CharacterData.domain_progress = {}
	var mscene := (load("res://scenes/main/primordial_realm.tscn") as PackedScene).instantiate()
	add_child(mscene)
	await get_tree().process_frame
	await get_tree().process_frame
	var mt := mscene.get_node_or_null("Facilities/Match") as Node
	_check(mt != null, "万界棋坛设施在场景里")
	if mt != null:
		_check(String(mt.get("facility_id")) == "match", "棋坛 id 与分发分支对得上")
		_check(not CharacterData.is_domain_cleared("domain_01"),
				"前置条件成立：这份存档确实没通关凡界")
		_check(bool(mt.get("is_locked")), "没通关凡界时棋坛压暗上锁")
		var tag_text := ""
		for c in mt.get_children():
			if c is Label and String((c as Label).text).contains("通关"):
				tag_text = String((c as Label).text)
		# 进度锁不许写成含糊的「暂未开启」：那看着像功能没做，玩家不会再回来
		_check(tag_text.contains("凡界"), "棋坛名下直接写清差什么", tag_text)
		mscene.call("_on_facility_activated", "match")
		await get_tree().process_frame
		_check(mscene.get("_current_panel") == null, "点上锁的棋坛不打开对局")
		_check(String(mscene.hint_label.text).contains("凡界"),
				"点击后提示说出解锁条件", String(mscene.hint_label.text))
		mscene.set("_near_facility_id", "match")
		mscene.call("_update_near_hint")
		_check(String(mscene.hint_label.text).contains("凡界")
				and not String(mscene.hint_label.text).contains("按 F 进入"),
				"靠近上锁棋坛时不再喊「按 F 进入」", String(mscene.hint_label.text))
		mscene.set("_near_facility_id", "")
	# 一个位面固定 3 只，全杀才算通关：只打两只不能提前开
	_mark_domain("domain_01", 2)
	_check(String(mscene.call("_facility_gate_reason", "match")) != "",
			"凡界只杀两只仍算未通关，棋坛继续锁着")
	_mark_domain("domain_01", 3)
	_check(String(mscene.call("_facility_gate_reason", "match")) == "",
			"凡界三只全杀后解锁判定转为已通关")
	_check(String(mscene.call("_facility_gate_reason", "tower")) == "",
			"没上进度锁的设施不受影响")
	mscene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ===== 4. 通关后重进主城：锁要真的自己解开 =====
	# 锁是 _ready 按存档状态判的一次，所以只能换一份场景重判，就地改表证明不了这条路
	var cscene := (load("res://scenes/main/primordial_realm.tscn") as PackedScene).instantiate()
	add_child(cscene)
	await get_tree().process_frame
	await get_tree().process_frame
	# ⚠ 第三次进主城：HUD 红点每进一次挂一遍，_badges 不能跟着涨
	#   （2026-11-10 编辑器报错 previously freed 的根因就是旧条目没剔）
	_check((Tutorial.get("_badges") as Array).size() == badge_n,
		"反复进主城不累积红点条目", "%d → %d" % [badge_n, (Tutorial.get("_badges") as Array).size()])
	var mt2 := cscene.get_node_or_null("Facilities/Match") as Node
	if mt2 != null:
		_check(not bool(mt2.get("is_locked")), "通关凡界后再进主城，棋坛不再压暗")
		var gone := true
		for c in mt2.get_children():
			if c is Label and String((c as Label).text).contains("通关"):
				gone = false
		_check(gone, "上锁小字没留在名字下面")
		cscene.set("_near_facility_id", "match")
		cscene.call("_update_near_hint")
		_check(String(cscene.hint_label.text).contains("按 F 进入"),
				"解锁后靠近恢复正常「按 F 进入」", String(cscene.hint_label.text))
	# 功能封锁表与进度锁互不干扰
	var mem2 := cscene.get_node_or_null("Facilities/Memory") as Node
	_check(mem2 != null and bool(mem2.get("is_locked")),
			"记忆幻像碑仍按「暂未开启」封锁，没被进度锁逻辑带跑")
	CharacterData.domain_progress = {}
	cscene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# 离城后按钮全被释放：轮询必须自己剔除悬空条目（否则每 0.5 秒报 previously freed）
	Tutorial.call("_tick_badges", 0.6)
	_check((Tutorial.get("_badges") as Array).is_empty(),
		"离开主城后红点条目全部剔除", "剩 %d 条" % (Tutorial.get("_badges") as Array).size())

	# ===== 5. 战斗右上角：计时 vs 设置按钮 =====
	var arena = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	var tl := arena.get_node("HUD/TimeLabel") as Label
	_check(tl != null, "战斗 HUD 计时节点存在")
	if tl != null:
		_check(is_equal_approx(tl.anchor_left, 1.0) and is_equal_approx(tl.anchor_right, 1.0),
			"计时改为贴右边界")
		var btn: Button = SettingsUI.get("_btn")
		_check(btn != null, "设置入口按钮存在")
		var vp_w := get_viewport().get_visible_rect().size.x
		# 计时还没入树，按「离右缘多少像素」算绝对位置；设置按钮已在树里，position 就是解析后的绝对 x
		var timer_right := vp_w + tl.offset_right
		var btn_left := btn.position.x
		_check(timer_right <= btn_left + 0.5, "计时右缘在设置按钮左侧，不再被挡",
			"计时到 %.0f / 按钮从 %.0f 起" % [timer_right, btn_left])
		_check(tl.offset_right > -260.0, "计时没被推到离右缘过远的位置",
			"offset_right=%.0f" % tl.offset_right)
	arena.free()

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


## 把某界域的前 count 只 BOSS 标成已击杀（直接写进度表，不走击杀链）
## 这条探针守的是「通关判定 → 设施解锁」，首杀奖励 / 掉落 / 本源那些副作用没必要拖进来
func _mark_domain(domain_id: String, count: int) -> void:
	CharacterData.domain_progress[domain_id] = {"unlocked": false, "cleared_bosses": []}
	var cleared: Array = CharacterData.domain_progress[domain_id]["cleared_bosses"]
	var boss_ids: Array = WorldDB.get_domain(domain_id).get("boss_ids", [])
	for i in mini(count, boss_ids.size()):
		cleared.append(String(boss_ids[i]))
