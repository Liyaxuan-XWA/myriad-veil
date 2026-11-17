extends Node
## 卡片自走棋「能不能进、能不能跑完」回归（2026-11-03）
##
## 规则层和棋子各自有探针，但**整条链**没人守：主城设施没注册、
## 场景路径打错、对局场景一进来就报错 —— 这些都会让模式"代码全在但玩不到"。
## 这条探针走一遍真实入口链，并逼对局跑完全部阶段。
##
## 用法：godot --headless --path . res://tools/probe_match_entry.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 卡组判等用的排序指纹：顺序不该影响"是不是同一副"
func _sorted_key(a: Array) -> String:
	var ids: Array[String] = []
	for x in a:
		ids.append(String(x))
	ids.sort()
	return "|".join(ids)


func _ready() -> void:
	print("\n########## 卡片自走棋 · 入口链 ##########")
	# ---- 1. 主城里有这个设施 ----
	var realm := (load("res://scenes/main/primordial_realm.tscn") as PackedScene).instantiate()
	var fac := realm.get_node_or_null("Facilities/Match")
	_check(fac != null, "主城注册了 Facilities/Match")
	if fac != null:
		_check(String(fac.get("facility_id")) == "match",
				"设施 id 与分发分支对得上", "id=%s" % fac.get("facility_id"))
		_check(String(fac.get("facility_name")) != "", "设施有显示名",
				String(fac.get("facility_name")))
		# 位置不能和已有设施重叠，否则玩家只能点到其中一个
		var pos: Vector2 = fac.position
		var clash := ""
		for other in realm.get_node("Facilities").get_children():
			if other == fac or not (other is Node2D):
				continue
			if (other as Node2D).position.distance_to(pos) < 110.0:
				clash = String(other.name)
		_check(clash == "", "设施落点不与其他设施重叠", "撞=" + clash)
	realm.free()

	# ---- 2. 分发脚本认这个 id ----
	# 关卡制（#55）之后点设施先进**棋谱长卷**挑局，长卷才落到对局场景，
	# 所以主城这条分支不该再直指 match_arena.tscn —— 直指等于跳过长卷。
	var src := FileAccess.get_file_as_string("res://scripts/main/primordial_realm.gd")
	_check(src.contains("\"match\":"), "primordial_realm.gd 有 match 分发分支")
	_check(src.contains("match_level_scroll.tscn"), "分发先进棋谱长卷", "")
	_check(FileAccess.file_exists("res://scenes/match/match_level_scroll.tscn"),
			"长卷场景文件存在", "")
	_check(FileAccess.file_exists("res://scenes/match/match_arena.tscn"), "对局场景文件存在")

	# ---- 3. 对局场景能真跑起来并放棋子进场景 ----
	# 只验到「进入 battle 且棋子进场」为止：跑完整局是 probe_match_rules 的职责，
	# 这里重跑一遍要几分钟（每轮 6 秒选牌 + 8 秒战斗 × 6 轮 + 终局 120 秒），
	# 而这条探针守的是链路通不通。
	var arena := (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	# 玩家侧超时压到 1 秒：默认 45 秒是给真人看的，布阵 6 次要 270 秒才走完
	arena.set("player_stage_timeout", 1.0)
	add_child(arena)
	# ---- 3a. 开局不许把选牌阶段秒过 ----
	# `_stage_timer` 初值是 0.0，而 _process 的「等待玩家」分支先减表再判 <=0，
	# `_drain` 换阶段在其后 —— 于是**第一帧**就判超时，MatchPolicy 替玩家把 6 张挑完，
	# 玩家根本看不到选牌界面（2026-11-03 截图才暴露：pick 那张拍出来是 lock 的界面）。
	await get_tree().physics_frame
	await get_tree().physics_frame
	var st0 = arena.get("_state")
	var p0 := "?" if st0 == null else String(MatchState.PHASE_NAME.get(int(st0.phase), "?"))
	_check(p0 == "pick", "开局两帧后仍停在选牌阶段（没被超时秒过）", "phase=" + p0)
	_check((arena.get("_picked") as Array).is_empty(),
			"选牌没被策略代打（_picked 仍为空）")
	_check(float(arena.get("_stage_timer")) > 0.0,
			"进阶段时倒计时确实上了表", "timer=%.2f" % float(arena.get("_stage_timer")))

	# ---- 3b. 棋盘铺满整屏、但不越界（2026-11-03 用户要求放大到整个屏幕）----
	# 只断言**比例关系**：headless 下 get_viewport_rect() 不是实机那个尺寸，
	# 写死 1280×720 的判据会假绿/假红。
	var cam: Camera2D = arena.get("_cam")
	# ⚠ Node2D.get_viewport_rect() 返回的是「视口矩形在该节点局部坐标系里的大小」，
	#   会被相机缩放除掉 —— 拿它当屏幕真实像素会算出自相矛盾的判据。要真实像素只能走
	#   viewport.get_visible_rect()（Control 上的 get_viewport_rect() 没这个问题）。
	var vp := arena.get_viewport()
	var vs := Vector2.ZERO if vp == null else vp.get_visible_rect().size
	var board := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX
	if cam != null and vs.x > 0.0:
		var on := board * cam.zoom.x
		# 2026-11-04 起棋盘要让出顶部读数带与底部操作带，所以基准不再是整个 vs.y，
		# 而是"两条带之间那条可用带"。判据照旧两头：不出界、也不留空边。
		# 两端各再扣 BOARD_OVERHANG：归属签与呼吸灯外圈在牌的包围盒之外。
		var usable_y := maxf(vs.y - MatchArena.TOP_BAND - MatchArena.BOTTOM_BAND
				- MatchArena.BOARD_OVERHANG * 2.0, 160.0)
		_check(on.x <= vs.x + 0.5 and on.y <= usable_y + 0.5,
				"棋盘不越过屏幕、也不压进两条 HUD 带", "屏上=%s 可用高=%.1f" % [on, usable_y])
		_check(minf(on.x, on.y) >= minf(vs.x, usable_y) * 0.99,
				"棋盘已经放到「不越界」的上限（不是还留着空边）",
				"屏上=%s 可用=%s zoom=%.4f" % [on, Vector2(vs.x, usable_y), cam.zoom.x])
		var hs: Control = arena.get("_hand_scroll")
		_check(hs.mouse_filter == Control.MOUSE_FILTER_PASS,
				"手牌面板用 PASS（STOP 会吃掉最下排格子；IGNORE 会让整棵子树被跳过、卡面点不到）",
				"filter=%d" % hs.mouse_filter)
		var root_c: Control = arena.get("_hud_root")
		_check(root_c.mouse_filter == Control.MOUSE_FILTER_PASS,
				"HUD 根节点用 PASS（裸 Control 默认 STOP，会把全屏点击全吃掉）",
				"filter=%d" % root_c.mouse_filter)
	# ---- 3c. 对手卡组来自关卡号，不再从玩家池推导 ----
	# 2026-11-03 的老判据是「AI 卡池要避开玩家池」：那时两边共用同一份
	# `MatchPolicy.decide_deck()`，不避开就构造性撞成同一副，每轮双方放出同一只
	# BOSS，玩家读成"一方激活了两只"（实测每个 boss_id 恰好出现两次、各在一队）。
	# 关卡制之后对手那 6 张来自 `MatchLevelDeck.deck_for(关卡号)`，
	# **按 ADR-0002 就不该读玩家进度**，"避开"这条判据失去对象；
	# 改成守两件事：① 确实等于 deck_for(本局关卡号)；② 那条会自我复刻的旧推导路径已经删干净。
	var st_c3 = arena.get("_state")
	var ai_deck: Array = (st_c3.pools as Array)[1]
	var want: Array = MatchLevelDeck.deck_for(int(arena.get("_level")))
	_check(_sorted_key(ai_deck) == _sorted_key(want),
			"对手那 6 张 == deck_for(本局关卡号)", "实=%s 期=%s" % [str(ai_deck), str(want)])
	var arena_src := FileAccess.get_file_as_string("scripts/match/match_arena.gd")
	_check(not arena_src.contains("_ai_pool"),
			"旧的「从玩家池推导 AI 卡组」那条路已经删掉（不是留着没人调）", "")
	_check(not arena_src.contains("_seed_shuffle"),
			"随之失去唯一调用者的 _seed_shuffle 也一并清掉（不留死代码）", "")

	var st = null
	var seen := {}
	var spawned := 0
	var guard := 0
	while guard < 3000:
		guard += 1
		await get_tree().physics_frame
		st = arena.get("_state")
		if st == null:
			continue
		seen[String(MatchState.PHASE_NAME.get(int(st.phase), "?"))] = true
		var pieces: Node = arena.get_node_or_null("Pieces")
		spawned = pieces.get_child_count() if pieces != null else 0
		if bool(seen.get("battle", false)) and spawned > 0:
			break
	_check(bool(seen.get("pick", false)) and bool(seen.get("lock", false)) \
			and bool(seen.get("deploy", false)) and bool(seen.get("battle", false)),
			"对局跑通 pick→lock→deploy→battle", str(seen.keys()))
	_check(st != null and int(st.cards.size()) == 12, "整局 12 张卡",
			"n=%d" % (st.cards.size() if st != null else -1))
	_check(spawned > 0, "真棋子确实进了场", "n=%d" % spawned)
	var all_in := st != null
	if all_in:
		for c in st.cards:
			if not bool(c["deployed"]):
				all_in = false
	_check(all_in, "12 张全部落子且落点合法")
	# ---- 3d. 召唤物要借到主人的血条颜色 ----
	# 棋子自己 `get_parent().add_child(...)` 出来的单位没有队伍号，
	# 血条会退回场景默认红 → 自家召唤物看着像敌方（2026-11-03 用户报）。
	await get_tree().process_frame
	var host: Node = null
	for ch in arena.get_node("Pieces").get_children():
		if ch.get_child_count() > 0:
			host = ch
			break
	if host == null:
		_check(false, "场上有棋子 host 可测", "没找到")
	else:
		var owner: Node = host.get_child(0)
		var want_green: bool = BossBase.unit_team(owner) == 0
		var fake := (load("res://scenes/boss/domain_boss_01.tscn") as PackedScene).instantiate()
		host.add_child(fake)
		await get_tree().process_frame
		var bar: ColorRect = fake.get_node_or_null("HPBarBG/HPBar")
		_check(bar != null and bar.color == (BossBase.TEAM_HP_GREEN if want_green
				else BossBase.TEAM_HP_RED),
				"无队伍号的召唤单位按 host 借到主人的血条色",
				"color=%s 主人队=%d" % [str(bar.color) if bar != null else "无",
						BossBase.unit_team(owner)])
		_check(int(fake.get("team_id")) == -1,
				"只借显示色，没有擅自改阵营语义（team_id 仍是 -1）",
				"team_id=%d" % int(fake.get("team_id")))
		fake.queue_free()
		await get_tree().process_frame
	arena.queue_free()

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(1 if not _fails.is_empty() else 0)
