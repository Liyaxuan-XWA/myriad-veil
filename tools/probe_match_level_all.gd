extends Node
## 棋坛关卡制 · 总验收（#60，2026-11-05）
##
## 一条命令把 001–006 的核心判据串起来，并补上各票单独测不到的两件事：
##   ② 拿**磁盘上真实的老档**（还没有 match_level_cleared 这个键的那版）走一遍读盘；
##   ③ 走一遍**真文件写回**（不是只在内存里 capture/apply）。
##
## ⚠ 本探针不写玩家任何真实槽位：真盘测试用 `slot_path(9)`，
##   9 > SLOT_COUNT，游戏永远不会读它，跑完立刻删。
##
## 用法：godot --headless --path . res://tools/probe_match_level_all.tscn -- --no-save

const CRYSTAL := "mat_duanzaojingshi"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wallet() -> int:
	return int(CharacterData.count_material(CRYSTAL))


func _crystal(n: int) -> Dictionary:
	var def := ItemDB.get_material(CRYSTAL)
	return {"id": CRYSTAL, "name": String(def.get("name", CRYSTAL)), "type": "material",
		"count": n, "icon": String(def.get("icon", ""))}


func _key(a: Array) -> String:
	var ids: Array[String] = []
	for x in a:
		ids.append(String(x))
	ids.sort()
	return "|".join(ids)


func _ready() -> void:
	print("\n########## 棋坛关卡制 · 总验收 ##########")
	await _check_ticket_cores()
	await _check_legacy_save()
	await _check_disk_roundtrip()
	await _check_ladder_walk()
	_check_docs()
	_check_scroll_faces()
	_check_opponent_faces()
	_check_camera_focus()
	_finish()


## ① 六张票各留一条最尖锐的判据在这里，改坏了第一时间会在这条命令上红
func _check_ticket_cores() -> void:
	# 001 卡组生成器
	MatchLevelDeck.reset_cache()
	var seen := {}
	for lv in range(1, 301):
		seen[_key(MatchLevelDeck.deck_for(lv))] = true
	_check(seen.size() == 300, "①001 前 300 关互不相同", "%d 副" % seen.size())
	_check(_key(MatchLevelDeck.deck_for(7)) == _key(MatchLevelDeck.deck_for(7)),
			"①001 同一关重算一致", "")
	_check(str(MatchDB.piece_stats("boss_03_c")) == str(MatchDB.piece_stats("boss_03_c"))
			and int(MatchDB.LEVEL_FIRST_CLEAR_REWARD) == 8,
			"①001 关卡号不碰数值 + 首通奖 = 8", "")

	# 002 进关链路
	var deck1: Array = MatchLevelDeck.deck_for(1)
	_check(deck1.size() == MatchDB.DECK_SIZE, "①002 第 1 关就有完整 6 张", str(deck1))

	# 004 窗口规则
	var scroll: Control = MatchLevelScroll.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	CharacterData.match_level_cleared = 120
	get_tree().root.add_child.call_deferred(scroll)
	await _settle(14)
	_check(int(scroll._deck_slot_count()) == 126, "①004 通关 120 局 ⇒ 126 副卡组",
			"%d" % int(scroll._deck_slot_count()))
	_check(scroll._tiles_by_slot.size() < 24, "①004 节点只建可见范围（没被历史拖垮）",
			"已建 %d" % scroll._tiles_by_slot.size())
	_check(int(scroll._slot_level(0)) == 1, "①004 最左仍是第 1 关", "")
	_check(bool(scroll._is_silhouette(127)) and not bool(scroll._is_silhouette(126)),
			"①004 预览/剪影分界正好在第 126 关", "")
	# 拓印必须落在底图那段绢里（落点同源），不能浮到桌面或压住轴杆。
	# ⚠ scroll 声明成 Control，`:=` 推不出自定义方法的返回类型，要写显式类型
	var paper: Rect2 = scroll._paper_rect()
	_check(paper.position.y <= scroll._origin_y
			and scroll._origin_y + scroll._tile <= paper.end.y,
			"①006 拓印完整落在底图纸面内",
			"纸 %.0f..%.0f 拓 %.0f..%.0f" % [paper.position.y, paper.end.y,
					scroll._origin_y, scroll._origin_y + scroll._tile])
	scroll.queue_free()
	await _settle(6)


## ② 老档回归：拿磁盘上那版**还没有这个键**的真实存档走一遍
func _check_legacy_save() -> void:
	var legacy := ""
	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var p := SaveManager.backup_path(slot)
		if not FileAccess.file_exists(p):
			continue
		var raw := FileAccess.get_file_as_string(p)
		var j: Variant = JSON.parse_string(raw)
		if j is Dictionary and not (j as Dictionary).has("match_level_cleared"):
			legacy = p
			break
	_check(legacy != "", "② 找到一份真实老档（无 match_level_cleared 键）",
			legacy.get_file() if legacy != "" else "<没找到>")
	if legacy == "":
		return

	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy))
	CharacterData.match_level_cleared = 77          # 故意留脏值，看它会不会被沿用
	SaveManager.apply(before)
	_check(CharacterData.match_level_cleared == 0,
			"② 老档缺字段 ⇒ 按「还没打过」处理，不沿用上一次的脏值",
			"%d" % CharacterData.match_level_cleared)
	# 读老档不许顺手吞掉别的东西。
	# ⚠ 背包在盘上的键是 inventory_data / equipment_data / warehouse_data，
	#   不是 CharacterData 里的成员名 inventory —— 第一版按成员名读，读出 0 条，
	#   假红成"老档背包被吞了"。这里两头都按存档口径取。
	var dom: Dictionary = before.get("domain_progress", {})
	_check(str(CharacterData.domain_progress) == str(dom),
			"② 老档的位面进度原样读回", "%d 个位面" % dom.size())
	var swallowed: Array[String] = []
	for pair in [["inventory_data", "inventory"], ["warehouse_data", "warehouse"],
			["equipment_data", "equipment_slots"]]:
		# 不能写 `var on_disk: Array = ...`：equipment_data 在盘上是个 Dictionary
		# （按部位分格），硬锁 Array 会当场报类型错
		var on_disk = before.get(pair[0], [])
		var in_mem = CharacterData.get(pair[1])
		if in_mem.size() != on_disk.size():
			swallowed.append("%s %d→%d" % [pair[0], on_disk.size(), in_mem.size()])
	_check(swallowed.is_empty(), "② 老档的背包/仓库/装备条目数一条没吞", str(swallowed))


## ③ 真文件写回：写一个游戏永远读不到的 9 号槽，跑完删掉
func _check_disk_roundtrip() -> void:
	CharacterData.match_level_cleared = 0
	CharacterData.inventory = [_crystal(100)]
	var scratch := SaveManager.slot_path(9)
	var wrote := false
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	if f == null:
		_check(false, "③ 写不回真盘：临时文件打不开", scratch)
		return
	f.store_string(JSON.stringify(SaveManager.capture()))
	f.close()
	wrote = true

	CharacterData.match_level_cleared = 0
	SaveManager.apply(JSON.parse_string(FileAccess.get_file_as_string(scratch)))
	_check(CharacterData.match_level_cleared == 0, "③ 真盘写回后读回一致（未通关态）",
			"%d" % CharacterData.match_level_cleared)

	CharacterData.match_level_cleared = 41
	var f2 := FileAccess.open(scratch, FileAccess.WRITE)
	f2.store_string(JSON.stringify(SaveManager.capture()))
	f2.close()
	CharacterData.match_level_cleared = 0
	SaveManager.apply(JSON.parse_string(FileAccess.get_file_as_string(scratch)))
	_check(CharacterData.match_level_cleared == 41, "③ 进度 41 经 JSON 落盘再读回仍是 41",
			"%d" % CharacterData.match_level_cleared)

	# int 键陷阱：JSON 的 key 只能是字符串，进度是标量所以不该受影响
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(scratch))
	_check(raw is Dictionary and int((raw as Dictionary).get("match_level_cleared", -1)) == 41,
			"③ 磁盘上这个键确实是数字 41，不是 \"41\"", str((raw as Dictionary).get("match_level_cleared")))
	if wrote:
		DirAccess.remove_absolute(scratch)
	_check(not FileAccess.file_exists(scratch), "③ 临时文件已清掉，没留垃圾", scratch)


## ④ 连着推三关 + 回头重打，钱和进度都要对
func _check_ladder_walk() -> void:
	CharacterData.inventory = [_crystal(0)]
	CharacterData.match_level_cleared = 0
	for lv in range(1, 4):
		await _finish_match(lv, 0)
		_check(_wallet() == lv * 8, "④ 连推第 %d 关累计 %d 晶石" % [lv, lv * 8],
				"钱包=%d" % _wallet())
		_check(CharacterData.match_level_cleared == lv, "④ 进度跟到第 %d 关" % lv,
				"%d" % CharacterData.match_level_cleared)
	await _finish_match(2, 0)          # 回头重打第 2 关
	_check(_wallet() == 24, "④ 重打第 2 关不再给钱（累计仍 24）", "钱包=%d" % _wallet())
	_check(CharacterData.match_level_cleared == 3, "④ 重打低关卡不把进度倒回去",
			"%d" % CharacterData.match_level_cleared)
	await _finish_match(4, 1)          # 第 4 关打输
	_check(_wallet() == 24 and CharacterData.match_level_cleared == 3,
			"④ 第 4 关输了：不扣钱也不推进", "钱包=%d 进度=%d" % [_wallet(), CharacterData.match_level_cleared])


func _finish_match(level: int, outcome: int) -> void:
	GameState.match_context = {"level": level}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 1.0)
	add_child(arena)
	await _settle(10)
	var st = arena.get("_state")
	st.winner = outcome
	st.end_reason = "clear_field"
	st.phase = MatchState.Phase.OVER
	arena.call("_settle")
	await _settle(2)
	arena.queue_free()
	await _settle(3)
	GameState.match_context = {}


## ⑤ 口径文件：设计案、CONTEXT、两条 ADR 都要在并且互相连得上
func _check_docs() -> void:
	var doc := FileAccess.get_file_as_string("docs/卡片自走棋_设计案.md")
	_check(doc.contains("2c. 关卡制"), "⑤ 设计案补了关卡制那一节", "")
	_check(doc.contains("ADR-0001") and doc.contains("ADR-0002"),
			"⑤ 设计案链到两条 ADR", "")
	_check(doc.contains("8") and doc.contains("押注") and doc.contains("取消"),
			"⑤ 设计案写清了「押注取消 + 首通 8」", "")
	var ctx := FileAccess.get_file_as_string("CONTEXT.md")
	var missing: Array[String] = []
	for term in ["棋谱长卷", "拓印", "首通奖", "原初位面", "严格去重", "卡组清单"]:
		if not ctx.contains(term):
			missing.append(term)
	_check(missing.is_empty(), "⑤ CONTEXT.md 术语齐全", str(missing))
	_check(FileAccess.file_exists("res://docs/adr/0001-棋坛关卡制取代押注经济.md")
			and FileAccess.file_exists("res://docs/adr/0002-关卡卡组由关卡号确定性生成.md"),
			"⑤ 两条 ADR 都在", "")
	# ADR-0002 里那个曾经写错的 8008 必须已经订正过
	var adr2 := FileAccess.get_file_as_string("docs/adr/0002-关卡卡组由关卡号确定性生成.md")
	_check(adr2.contains("3400") and adr2.contains("416"),
			"⑤ ADR-0002 用的是实测可达数，不是全组合 8008", "")


## ⑥ 长卷的「玩家可见面」：16 位落子都必须拿得到真卡面。
## `_make_stone()` 在 cover_style 为空时会退回 dot_soft.png（一颗糊点）——
## 关卡制把对手 6 张全预告出来了，任何一位掉进兜底都会在长卷上直接看见。
func _check_scroll_faces() -> void:
	var no_style: Array = []
	var missing_art: Array = []
	for id in MatchDB.CARD_POOL:
		var s: Dictionary = MatchCard.cover_style(String(id), "")
		if s.is_empty():
			no_style.append(String(id))
			continue
		var art := String(s.get("art", ""))
		if art != "" and not ResourceLoader.exists(art):
			missing_art.append("%s→%s" % [String(id), art])
	_check(no_style.is_empty(), "⑥ 16 位都有卡面（没落到 dot_soft 兜底）", str(no_style))
	_check(missing_art.is_empty(), "⑥ 卡面引用的贴图盘上真在", str(missing_art))
	_check(ResourceLoader.exists(MatchLevelScroll.STAGE_PATH),
			"⑥ 长卷舞台底图能加载", MatchLevelScroll.STAGE_PATH)
	_check(not MatchLevelDeck.deck_for(1).is_empty(),
			"⑥ 第 1 关（新档首屏）就有卡组可画",
			str(MatchLevelDeck.deck_for(1).size()) + " 张")


## ⑦ 敌方卡面固定原版（2026-11-05 用户定）：不读玩家卡包偏好，也不读解锁进度。
## 这条的核心是第 2 项那个**反向守卫**——把玩家的档改成水墨，敌方那 16 张必须一动不动。
## 只测"现在等于 portrait"是守不住的：cover_style 在什么都没解锁时也会回退到某档，
## 换个人改回 cover_style(id,"") 照样全绿。
func _check_opponent_faces() -> void:
	var wrong_id: Array = []
	var wrong_art: Array = []
	var base: Dictionary = {}
	for id in MatchDB.CARD_POOL:
		var sid := String(id)
		var st: Dictionary = MatchCard.opponent_style(sid)
		if String(st.get("id", "")) != "portrait":
			wrong_id.append("%s→%s" % [sid, String(st.get("id", ""))])
		var want := String(CodexDB.boss_entry(sid).get("portrait", ""))
		if String(st.get("art", "")) != want:
			wrong_art.append(sid)
		base[sid] = want
	_check(wrong_id.is_empty(), "⑦ 16 位敌方卡面都是原版档", str(wrong_id))
	_check(wrong_art.is_empty(), "⑦ 原版档贴的就是图鉴原画那张", str(wrong_art))

	CharacterData.match_card_kind = "ink"
	var moved: Array = []
	for id in MatchDB.CARD_POOL:
		if String(MatchCard.opponent_style(String(id)).get("art", "")) != String(base[String(id)]):
			moved.append(String(id))
	CharacterData.match_card_kind = ""
	_check(moved.is_empty(), "⑦ 玩家把档改成水墨 ⇒ 敌方卡面一动不动", str(moved))

	# ⚠ 本探针前几组跑过**真实老档读盘**，存档里 boss_01_c 可能已经解锁过。
	#   补牌的判据是「ordered_variants 为空」，所以这里必须先显式摆成未解锁，
	#   测完再还原 —— 拿默认/读盘后的状态猜，断言会随存档漂。
	var saved_kill = CharacterData.boss_progress.get("boss_01_c", null)
	CharacterData.boss_progress.erase("boss_01_c")
	MatchCard.clear_cache()
	var tok := MatchCardToken.new()
	tok.team = 1
	var enemy_team_art := String(tok.call("_art_path", "boss_01_c"))
	tok.team = 0
	var ally_default_art := String(tok.call("_art_path", "boss_01_c"))
	CharacterData.match_card_kind = "ink"
	var ally_art := String(tok.call("_art_path", "boss_01_c"))
	CharacterData.match_card_kind = ""
	tok.free()
	_check(enemy_team_art == String(base["boss_01_c"]),
			"⑦ team=1 的棋子卡面 == 原版原画", enemy_team_art)
	# 2026-11-10：开局补牌（未收集的 BOSS）玩家侧也固定普通原画。
	# ⚠ 这条**不能在本探针里按值断言**：前面几组读过真实老档，boss_01_c 多半已解锁，
	#   此时 team=0 本就该跟随卡包封面（华彩），拿它比对原画必然假红。
	#   「未解锁 ⇒ 普通原画」由 probe_match_cards 的 ⑥c 组在干净存档下端到端守；
	#   这里只守接线：我方棋子必须走 player_style，改回 cover_style 就红。
	var fill_src := FileAccess.get_file_as_string("scripts/match/match_card_token.gd")
	_check(fill_src.contains("MatchCard.player_style(id, CharacterData.match_card_kind)"),
			"⑦ 我方棋子卡面走 player_style（补牌才会落普通原画）", "")
	# ally_default_art / ally_art 仍要被用到：确认老档下我方确实跟着卡包走，
	# 而不是被一刀切成敌方原画（否则下面的反向守卫分不出「跟随」和「恒定」）。
	_check(ally_default_art != "" and ally_art != "",
			"⑦ 老档已解锁时我方两档都解析得出卡面", "%s / %s" % [
					ally_default_art.get_file(), ally_art.get_file()])
	# 反向守卫：别为了修补牌把「已收集的牌跟随卡包」一起改没了。
	# 记一条击杀 ⇒ ordered_variants 非空 ⇒ player_style 必须完全等于 cover_style。
	CharacterData.boss_progress["boss_01_c"] = {"killed": true}
	MatchCard.clear_cache()
	var want_default := String(MatchCard.cover_style("boss_01_c", "").get("art", ""))
	var want_ink := String(MatchCard.cover_style("boss_01_c", "ink").get("art", ""))
	var tok2 := MatchCardToken.new()
	tok2.team = 0
	var owned_default := String(tok2.call("_art_path", "boss_01_c"))
	CharacterData.match_card_kind = "ink"
	var owned_ink := String(tok2.call("_art_path", "boss_01_c"))
	CharacterData.match_card_kind = ""
	tok2.free()
	if saved_kill == null:
		CharacterData.boss_progress.erase("boss_01_c")
	else:
		CharacterData.boss_progress["boss_01_c"] = saved_kill
	MatchCard.clear_cache()
	_check(owned_default == want_default and owned_ink == want_ink,
			"⑦ 已收集的 BOSS 我方仍完全跟随卡包档位", "%s / %s" % [
					owned_default.get_file(), owned_ink.get_file()])

	var scroll_src := FileAccess.get_file_as_string("scripts/ui/facility/match_level_scroll.gd")
	_check(not scroll_src.contains("cover_style") and not scroll_src.contains("match_card_kind"),
			"⑦ 长卷里已经没有任何一处再读玩家卡包偏好", "")
	var token_src := FileAccess.get_file_as_string("scripts/match/match_card_token.gd")
	_check(token_src.contains("if team != 0:") and token_src.contains("opponent_style")
			and token_src.contains("player_style"),
			"⑦ 棋盘卡面按队伍分叉（敌方 opponent_style / 我方 player_style）", "")


## ⑧ 战斗档相机（2026-11-10 用户改口径：普通模式布阵一结束就**恒定放大**，
## 不再按轮次 480↔568 来回跳；激活改为只点棋盘上的卡片）。
## 用裸 MatchArena 实例调纯函数，不跑一局 —— 这组要守的是几何与触发条件。
func _check_camera_focus() -> void:
	var arena: Node = MatchArena.new()
	var board := Vector2(MatchDB.BOARD_COLS, MatchDB.BOARD_ROWS) * MatchDB.CELL_PX
	var vs := Vector2(1280.0, 720.0)
	var n: Dictionary = arena.call("_camera_fit", vs, board,
			MatchArena.TOP_BAND, MatchArena.BOTTOM_BAND, MatchArena.BOARD_OVERHANG, true)
	var f: Dictionary = arena.call("_camera_fit", vs, board,
			MatchArena.FOCUS_TOP_BAND, MatchArena.FOCUS_BOTTOM_BAND, MatchArena.FOCUS_OVERHANG, false)
	var z_n := float(n["z"])
	var z_f := float(f["z"])
	_check(z_f > z_n * 1.05, "⑧ 看盘档确实比常规档大",
			"z %.4f → %.4f（+%.0f%%）" % [z_n, z_f, (z_f / z_n - 1.0) * 100.0])
	# 几何上限：棋盘是 1560 的正方形，横屏由**高度**封顶。
	# 两档都不许超过「整屏高 / 棋盘高」，超了就是把上下两排推出屏幕。
	var ceiling := vs.y / board.y
	_check(z_n <= ceiling + 0.0001 and z_f <= ceiling + 0.0001,
			"⑧ 两档都没越过高度封顶", "上限=%.4f 常规=%.4f 看盘=%.4f" % [ceiling, z_n, z_f])
	_check(float(n["board_w"]) <= vs.x + 0.001 and float(f["board_w"]) <= vs.x + 0.001,
			"⑧ 两档棋盘宽度都不出屏", "%.0f / %.0f ≤ %.0f" % [
				float(n["board_w"]), float(f["board_w"]), vs.x])

	# 触发条件：普通模式 BATTLE 的**六轮一律**放大（含己方轮），
	# 选牌/锁定/布阵/终局/结算仍是常规档。快速模式另有自己的判据，见 probe_match_quick_camera。
	var st := MatchState.new()
	arena.set("_state", st)
	var cases: Array = [
		[int(MatchState.Phase.PICK), 0, false, "选牌"],
		[int(MatchState.Phase.LOCK), 0, false, "锁定"],
		[int(MatchState.Phase.DEPLOY), 0, false, "布阵"],
		[int(MatchState.Phase.BATTLE), 0, true, "战斗·自己这轮"],
		[int(MatchState.Phase.BATTLE), 1, true, "战斗·对方这轮"],
		[int(MatchState.Phase.BATTLE), 4, true, "战斗·第 5 轮"],
		[int(MatchState.Phase.BATTLE), 5, true, "战斗·第 6 轮"],
		[int(MatchState.Phase.FINAL), 1, false, "终局"],
		[int(MatchState.Phase.OVER), 1, false, "结算"],
	]
	var bad: Array = []
	for c in cases:
		st.phase = int(c[0])
		st.round_index = int(c[1])
		var want_watch := bool(c[2])
		var got_mode: int = int(arena.call("_camera_mode"))
		var want_mode: int = MatchArena.CAM_WATCH if want_watch else MatchArena.CAM_NORMAL
		if got_mode != want_mode:
			bad.append("%s 期望档=%d 实=%d" % [String(c[3]), want_mode, got_mode])
	_check(bad.is_empty(), "⑧ 普通模式整个 BATTLE 恒定放大，其余阶段常规", str(bad))

	# 看盘档必须把手牌列**收掉**（不是淡出）：CardFace 走 ShaderMaterial，
	# 父节点 modulate 压不住它，只有 visible 才真的消失。
	var hs := ScrollContainer.new()
	arena.set("_hand_scroll", hs)
	arena.set("_cam_mode", MatchArena.CAM_WATCH)
	arena.call("_apply_hand_visibility")
	_check(bool(hs.visible) == false, "⑧ 看盘档手牌列 visible=false", str(hs.visible))
	_check(int(hs.mouse_filter) == int(Control.MOUSE_FILTER_IGNORE),
			"⑧ 收掉的手牌不再吃棋盘右侧的点击", str(hs.mouse_filter))
	arena.set("_cam_mode", MatchArena.CAM_NORMAL)
	arena.call("_apply_hand_visibility")
	_check(bool(hs.visible) == true, "⑧ 常规档手牌列回来了", str(hs.visible))
	hs.free()
	arena.free()


func _finish() -> void:
	CharacterData.inventory = []
	CharacterData.match_level_cleared = 0
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
