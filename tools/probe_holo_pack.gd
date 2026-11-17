extends Node
## 成就 · 卡包收藏册探针：
## 三种卡解锁（普通=击败 / 有背景=双倍血击败 / 无背景=无伤双倍血）、
## 只显示已获得卡、一 BOSS 一格、首位封面、拖动换位、首领卡并入、图鉴分类迁移。
## 用法：godot --headless --path . tools/probe_holo_pack.tscn -- --no-save

var _fails := 0
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails += 1
		print("FAIL  ", label, "  ", detail)


func _variant_ids(entry: Dictionary) -> Array:
	var out: Array = []
	for raw in CodexDB.ordered_variants(entry):
		out.append(String((raw as Dictionary).get("id", "")))
	return out


func _ready() -> void:
	print("\n########## 成就 · 卡包收藏册探针 ##########")
	# 前七层 12 胜；第 8/9 层只打过一次；第 1 层额外无伤双倍血；四位大陆首领都击杀
	for f in range(1, 8):
		CharacterData.tower_progress[f] = {"unlocked": true, "first_kill": true, "clear_count": 12}
	CharacterData.tower_progress[8] = {"unlocked": true, "first_kill": true, "clear_count": 1}
	CharacterData.tower_progress[9] = {"unlocked": true, "first_kill": true, "clear_count": 1}
	CharacterData.tower_progress[10] = {"unlocked": true, "first_kill": true, "clear_count": 12}
	# 水墨卡需双倍气血 10 秒内通关；这里给所有塔层 / 核心都记一笔 9 秒成绩
	for f in range(1, 11):
		CharacterData.tower_best_time[f] = 9.0
	CharacterData.tower_no_hit_double[1] = true
	CharacterData.tower_no_hit_double[10] = true
	CharacterData.secret_world["core_kills"] = {
		"world_lianqi": true, "world_zhuji": true, "world_jiedan": true,
		"world_yuanying": true,
	}
	for rid in ["world_lianqi", "world_zhuji", "world_jiedan", "world_yuanying"]:
		CharacterData.core_replay[rid] = {
			"clear_count": CodexDB.HOLO_CLEAR_REQUIRED, "best_time": 9.0,
		}
	CodexDB.set_card_order("boss_huyao", ["scene", "portrait", "plain", "ink"])

	# ---- 分类迁移 ----
	var cats := CodexDB.categories()
	var has_pack := false
	for c in cats:
		if String((c as Dictionary).get("id", "")) == CodexDB.CAT_PACK:
			has_pack = true
	_check(not has_pack, "图鉴卷目不再有卡包")
	_check(cats.size() == 4, "图鉴剩 4 个卷目", str(cats.size()))

	# ---- 数据：塔层 + 首领卡 ----
	_check(CodexDB.card_entries().size() == 16, "12 位塔层 + 4 位大陆首领都进卡包",
		str(CodexDB.card_entries().size()))
	_check(CodexDB.card_total() == 64, "共 64 张卡（16 位首领 × 4）",
		str(CodexDB.card_total()))
	_check(CodexDB.card_collected() == 40, "已获得 40 张",
		str(CodexDB.card_collected()))
	var huyao := CodexDB.card_entry("boss_huyao")
	_check(_variant_ids(huyao) == ["scene", "portrait", "plain", "ink"],
		"第 1 层四张卡，默认封面=华彩有背景", str(_variant_ids(huyao)))
	var ink_variant: Dictionary = {}
	for raw in (huyao.get("card_variants", []) as Array):
		if String((raw as Dictionary).get("id", "")) == "ink":
			ink_variant = raw as Dictionary
			break
	_check(String(ink_variant.get("kind", "")) == "still"
		and String(ink_variant.get("label", "")) == "水墨 · 纸本"
		and bool(ink_variant.get("unlocked", false)),
		"虎妖纸本水墨按 10 秒速通解锁", str(ink_variant.get("kind", "")))
	var daoke := CodexDB.card_entry("boss_01")
	_check(_variant_ids(daoke) == ["scene", "portrait", "ink"],
		"第 2 层没无伤双倍血时有三张（含速通水墨）", str(_variant_ids(daoke)))
	var core := CodexDB.card_entry("world_core_lianqi")
	_check(String(core.get("name", "")) == "青岚古猿" and int(core.get("floor", -1)) == 0,
		"首领卡：青岚古猿进卡包", String(core.get("name", "")))
	var core_ids: Array = []
	var core_locked := 0
	for raw in (core.get("card_variants", []) as Array):
		core_ids.append(String((raw as Dictionary).get("id", "")))
		if not bool((raw as Dictionary).get("unlocked", false)):
			core_locked += 1
	_check(core_ids == ["scene", "portrait", "plain", "ink"],
		"首领卡四种卡面都在", str(core_ids))
	_check(core_locked == 1, "核心纯华彩仍锁", "locked=%d" % core_locked)
	_check(_variant_ids(core) == ["scene", "portrait", "ink"],
		"核心双倍血 + 速通后亮华彩与水墨", str(_variant_ids(core)))
	var shihou := CodexDB.card_entry("world_core_shihou")
	var shihou_ids: Array = []
	for raw in (shihou.get("card_variants", []) as Array):
		shihou_ids.append(String((raw as Dictionary).get("id", "")))
	_check(String(shihou.get("name", "")) == "镇墟石犼" and shihou_ids == [
		"scene", "portrait", "plain", "ink",
	], "镇墟石犼四张卡进卡包", "%s %s" % [shihou.get("name", ""), shihou_ids])
	_check(CodexDB.card_collection_entries().size() == 14, "14 位 BOSS 都有已获得卡")

	# ---- 面板与收藏册 ----
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	_check(view != null, "成就面板已建")
	_check(view._page == AchievementView.PAGE_PACK, "默认落在成就收藏")
	var cells := view.find_children("BossCell_*", "PanelContainer", true, false)
	_check(cells.size() == 14, "一格一 BOSS（只列有卡的）", str(cells.size()))
	# 封面现在就是一张 CardFace（华彩封面才带 HoloCardView），但待机不跑动画：
	# 12 格同时跑会让收藏册掉帧（实测悬停视差直接失效），只允许悬停那一张动。
	var cover_faces := 0
	for c in cells:
		cover_faces += (c as Node).find_children("*", "CardFace", true, false).size()
	_check(cover_faces == cells.size(), "每格封面都是一张 CardFace",
		"%d/%d" % [cover_faces, cells.size()])
	var grid_holos := view.find_children("*", "HoloCardView", true, false)
	var animating := 0
	for h in grid_holos:
		if bool((h as Node).get("_idle_motion")):
			animating += 1
	_check(animating == 0, "格子封面待机不跑动画（华彩靠悬停）",
		"animating=%d / %d" % [animating, grid_holos.size()])

	# 点封面本身（华彩/普通封面都自己吃鼠标）要能进展开
	var cell_huyao := view.find_child("BossCell_boss_huyao", true, false) as Control
	if cell_huyao != null:
		var pt: Vector2 = get_viewport().get_final_transform() 			* cell_huyao.get_global_transform_with_canvas() * (cell_huyao.size * 0.5)
		var mv := InputEventMouseMotion.new()
		mv.position = pt
		mv.global_position = pt
		get_viewport().push_input(mv)
		await get_tree().process_frame
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = pressed
			mb.position = pt
			mb.global_position = pt
			get_viewport().push_input(mb)
			await get_tree().process_frame
		await get_tree().process_frame
		_check(view._mode == AchievementView.MODE_SPREAD and view._boss_id == "boss_huyao",
			"点格子封面直接进展开", "mode=%d boss=%s" % [view._mode, view._boss_id])
		view._mode = AchievementView.MODE_GRID
		view._render()

	# ---- 展开：只铺已拥有的卡 ----
	view.open_boss("boss_huyao")
	await get_tree().process_frame
	_check(view._mode == AchievementView.MODE_SPREAD, "点开进入卡牌展开")
	_check(view.find_children("*", "CardFace", true, false).size() == 4,
		"四张已获得卡都铺开")
	var spread_holos := view.find_children("*", "HoloCardView", true, false)
	_check(spread_holos.size() == 2, "两张华彩在场", str(spread_holos.size()))
	var spread_stills := 0
	for face in view.find_children("*", "CardFace", true, false):
		if (face as CardFace).kind() == "still":
			spread_stills += 1
	_check(spread_stills == 2, "纸本水墨与普通卡都是静态", str(spread_stills))
	await get_tree().create_timer(1.0, true, false, true).timeout
	var slots := view.find_children("CardSlot*", "Control", true, false)
	_check(slots.size() == 4, "四个卡槽", str(slots.size()))

	# ---- 拖动换位：把第一张（封面）拖到最右，封面换成原第二位 ----
	var stage := view.find_child("SpreadStage", true, false) as Control
	if stage != null and slots.size() == 4:
		var front: Control = slots[0]
		var start := front.position + view._spread_card * 0.5
		var targets := view._fan_targets(4, view._spread_card)
		var drop: Vector2 = targets[1].get("pos", Vector2.ZERO) + view._spread_card * 0.5
		view._drag_press(start)
		await get_tree().process_frame
		view._drag_move(drop)
		await get_tree().process_frame
		view._drag_release(drop)
		await get_tree().create_timer(0.6, true, false, true).timeout
		var ids: Array = view._spread_ids
		_check(String(ids[0]) != "scene", "拖动后首位封面换人", str(ids))
		var saved: Array = CharacterData.card_order.get("boss_huyao", [])
		_check(not saved.is_empty() and String(saved[0]) == String(ids[0]),
			"卡序已写入 CharacterData", str(saved))
		_check(String(_variant_ids(CodexDB.card_entry("boss_huyao"))[0]) == String(ids[0]),
			"收藏册封面跟随卡序")

	# ---- 单卡查看（只有已拥有卡） ----
	view.open_card(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(view._mode == AchievementView.MODE_SINGLE, "点卡进入单卡查看")
	_check(view.find_child("CardSingle", true, false) != null, "单卡大图已建")
	view._step_card(1)
	await get_tree().process_frame
	_check(view._single_index == 1, "下一张切到第二张", str(view._single_index))
	_check(view.back() and view._mode == AchievementView.MODE_SPREAD, "后退回到展开")
	_check(view.back() and view._mode == AchievementView.MODE_GRID, "再退回到收藏册")
	_check(not view.back(), "收藏册再退交给面板关闭")

	# ---- 未获得的卡 / BOSS 完全不显示 ----
	CharacterData.tower_progress[3] = {"unlocked": true, "first_kill": false, "clear_count": 0}
	var kills: Dictionary = CharacterData.secret_world.get("core_kills", {})
	kills.erase("world_lianqi")
	CharacterData.core_replay.erase("world_lianqi")
	view.refresh()
	await get_tree().process_frame
	_check(view.find_child("BossCell_boss_01_c", true, false) == null,
		"没卡的剑客不占格")
	_check(view.find_child("BossCell_world_core_lianqi", true, false) == null,
		"没打过的首领不占格")
	_check(view.find_children("BossCell_*", "PanelContainer", true, false).size() == 12,
		"隐藏后剩 12 格", str(view.find_children("BossCell_*", "PanelContainer", true, false).size()))

	# ---- 无伤双倍血才解锁纯华彩 ----
	CharacterData.tower_no_hit_double.erase(2)
	view.refresh()
	await get_tree().process_frame
	var daoke2 := CodexDB.card_entry("boss_01")
	_check(_variant_ids(daoke2).size() == 3 and CodexDB.ordered_variants(daoke2).size() == 3,
		"无伤双倍血未达成时纯华彩不出现", str(_variant_ids(daoke2)))
	CharacterData.tower_no_hit_double[2] = true
	var daoke3 := CodexDB.card_entry("boss_01")
	_check(_variant_ids(daoke3) == ["scene", "portrait", "plain", "ink"],
		"无伤双倍血达成后纯华彩出现", str(_variant_ids(daoke3)))

	# ---- 任务页 ----
	view._show_page(AchievementView.PAGE_TASKS)
	await get_tree().process_frame
	_check(view._page == AchievementView.PAGE_TASKS, "切到成就任务")
	_check(view._mode == AchievementView.MODE_GRID, "任务页无卡包状态残留")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
