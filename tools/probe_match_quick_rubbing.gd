extends Node
## 长卷拓印画真实布局 + 反面牌背（票 006）
##
## 核心不是"画得对"，而是**同源**：拓印画的落位必须就是对局开局真正摆的那一份。
## 只测"拓印 == layout_for"是同义反复 —— 它测不出"对局没用 layout_for"。
## 所以 ⑦ 拿真对局对撞，⑧ 反过来验关掉开关后新分支一次都不被走到。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_rubbing.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _scroll: Control = null


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 拓印真布局与牌背 · 票 006 ##########")
	await _check_quick_rubbing()
	await _check_back_tooltips_silent()
	await _check_strip_still_revealed()
	await _check_normal_unchanged()
	await _check_silhouette_never_computes()
	await _check_label_follows_switch()
	await _check_same_source_as_match()
	_finish()


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 建一个长卷并停在指定关（焦点槽 = level-1）。
func _mk(cleared: int, quick: bool) -> void:
	await _destroy()
	CharacterData.match_quick_mode = quick
	CharacterData.match_level_cleared = cleared
	GameState.match_context = {}
	_scroll = MatchLevelScroll.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(_scroll)
	await _settle(16)


func _destroy() -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.queue_free()
		_scroll = null
		await _settle(6)


func _tile(level: int) -> Dictionary:
	for s in _scroll._tiles_by_slot.keys():
		var t: Dictionary = _scroll._tiles_by_slot[int(s)]
		if int(t["level"]) == level:
			return t
	return {}


## 判断一枚落子画的是牌背还是卡面：**看子节点**，不看 meta ——
## 读实现自己写的标记等于让它自己给自己发合格证。
func _is_back(host: Control) -> bool:
	for c in host.get_children():
		if c is TextureRect and (c as TextureRect).texture == MatchCard.back_texture():
			return true
	return false


func _has_face(host: Control) -> bool:
	for c in host.get_children():
		if c is CardFace:
			return true
	return false


## ① 快速模式：拓印 6 格 == layout_for(关卡号) 逐张同，且 3 张牌背 / 3 张卡面。
func _check_quick_rubbing() -> void:
	var lv := 4
	await _mk(lv - 1, true)
	var t := _tile(lv)
	_check(not t.is_empty(), "① 前置：第 %d 关的拓印建出来了" % lv, "")
	if t.is_empty():
		return
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
		var c: Vector2i = board.stone_cell(i)
		if not want.has(bid):
			bad.append("卡组里没有 %s" % bid)
		elif Vector2i(want[bid]) != c:
			bad.append("%s 格 %s ≠ layout_for 的 %s" % [bid, str(c), str(want[bid])])
		if _is_back(hosts[i] as Control):
			backs += 1
	_check(bad.is_empty(), "① 拓印 6 格逐张 == layout_for(关卡号)", str(bad))
	_check(backs == 3, "① 恰好 3 枚画牌背", "%d 枚" % backs)
	var faces := 0
	for h in hosts:
		if _has_face(h as Control):
			faces += 1
	_check(faces == 3, "① 另外 3 枚仍是卡面", "%d 枚" % faces)
	await _destroy()


## ② 牌背那 3 枚的 tooltip **不许出现 BOSS 名字**。
## 细化后的「预告」口径：身份全摊开，但反面卡的格子对应关系不摊开。
## 这条专门防"悬念从 tooltip 漏出去"——名字写在上面，牌背就白盖了。
func _check_back_tooltips_silent() -> void:
	var lv := 6
	await _mk(lv - 1, true)
	var t := _tile(lv)
	var leaked: Array = []
	if not t.is_empty():
		var hosts: Array = t["hosts"]
		for i in hosts.size():
			var h: Control = hosts[i]
			if not _is_back(h):
				continue
			var tip := String(h.tooltip_text)
			var bid := String((t["deck"] as Array)[i])
			var nm := String(WorldDB.get_boss_name(bid))
			if tip.contains(bid) or (nm != bid and tip.contains(nm)):
				leaked.append("%s(%s) → %s" % [bid, nm, tip])
	_check(leaked.is_empty(), "② 牌背的 tooltip 不泄露身份", str(leaked))
	await _destroy()


## ③ 底栏那 6 张小卡必须仍然全亮、仍然有名字。
## 拓印盖牌背 + 底栏照常点名，两边合起来才是"身份摊开、对应关系不摊开"。
func _check_strip_still_revealed() -> void:
	var lv := 8
	await _mk(lv - 1, true)
	_scroll._scroll_to_slot(lv - 1)
	await _settle(10)
	var cards: HBoxContainer = _scroll.get("_strip_cards")
	var named := 0
	var backed := 0
	for h in cards.get_children():
		if String((h as Control).tooltip_text) != "":
			named += 1
		if _is_back(h as Control):
			backed += 1
	_check(named == MatchDB.DECK_SIZE, "③ 底栏 6 张都有名字 tooltip", "%d 张" % named)
	_check(backed == 0, "③ 底栏一张都不盖牌背（身份全摊开没被收回）", "%d 张" % backed)
	await _destroy()


## ④ 反向判据：普通模式**不画格子**、改成 3×2 卡组清单，面纱仍在。
## 口径变更（2026-11-05 用户拍定）：以前普通模式把 6 张嵌进 STONE_CELLS 装饰格，
## 读起来和真阵型一模一样，而那份阵型在进关前根本不存在 —— 是拿不存在的事实骗人。
## 现在普通模式连格子都不画，只有快速模式（摆位进关前已定死）才配得上格子。
func _check_normal_unchanged() -> void:
	var lv := 3
	await _mk(lv - 1, false)
	var t := _tile(lv)
	_check(not t.is_empty(), "④ 前置：普通模式拓印建出来了", "")
	if t.is_empty():
		await _destroy()
		return
	var hosts: Array = t["hosts"]
	var backed := 0
	for h in hosts:
		if _is_back(h as Control):
			backed += 1
	_check(backed == 0, "④ 普通模式一张牌背都不画（朝向此时真的未知）", "%d 张" % backed)
	var board: Control = t["board"]
	_check(board.get("veil") == true, "④ 普通模式面纱仍开着", str(board.get("veil")))
	# 口径变更的正主：没有 6×6 网格，也就没有"落点"可言
	_check(bool(t.get("list")) == true, "④ 普通模式走清单分支", str(t.get("list")))
	_check(bool(board.get("grid")) == false,
			"④ 普通模式不画 6×6 格子（不会再被读成真阵型）", str(board.get("grid")))
	_check(hosts.size() == MatchDB.DECK_SIZE,
			"④ 清单仍是 6 张，一张都没少", "%d 张" % hosts.size())
	# 清单必须落在方块里、互不重叠 —— 否则等于把卡画到卷外或叠成一坨
	var plate := board as Control
	var outside: Array = []
	var rects: Array = []
	for i in hosts.size():
		var h: Control = hosts[i]
		var r: Rect2 = Rect2(h.position, h.size)
		if r.position.x < 0.0 or r.position.y < 0.0 \
				or r.end.x > plate.size.x + 0.5 or r.end.y > plate.size.y + 0.5:
			outside.append("%d %s" % [i, str(r)])
		for j in rects.size():
			var o: Rect2 = rects[j]
			var inter := o.intersection(r)
			if inter.size.x > 1.0 and inter.size.y > 1.0:
				outside.append("%d×%d 重叠 %s" % [j, i, str(inter)])
		rects.append(r)
	_check(outside.is_empty(), "④ 清单 6 张都在方块内且互不重叠", str(outside))
	# 卡面要还读得清：3 列排下来每张至少 60px 宽（340 方块时实测约 80）
	var narrow := 0
	for i in hosts.size():
		if (hosts[i] as Control).size.x < 60.0:
			narrow += 1
	_check(narrow == 0, "④ 清单卡面宽度够读（≥60px）", "%d 张过窄" % narrow)
	await _destroy()


## ⑤ 剪影关零调用 layout_for —— 守住"未来的关还没算"。
## 用缓存键验，不用调用计数：MatchQuickSetup 内部就有 _cache，
## 剪影关的关卡号一旦出现在里面，说明真的算过了。
func _check_silhouette_never_computes() -> void:
	await _destroy()
	MatchQuickSetup.reset_cache()
	var lv := 1
	await _mk(0, true)
	_scroll._scroll_to_slot(10)
	await _settle(14)
	var slots := 0
	for s in _scroll._tiles_by_slot.keys():
		var t: Dictionary = _scroll._tiles_by_slot[int(s)]
		if t["silhouette"] == true:
			slots += 1
			_check((t["hosts"] as Array).is_empty(), "⑤ 剪影关没有落子", "")
	_check(slots > 0, "⑤ 前置：确实滚进了剪影段", "%d 枚" % slots)
	var future: Array = []
	for k in MatchQuickSetup._cache.keys():
		if int(k) > int(_scroll._deck_slot_count()):
			future.append(int(k))
	_check(future.is_empty(), "⑤ 剪影关一次都没触发 layout_for", str(future))
	await _destroy()


## ⑥ 读数带那行标注从字段现算：拨一下开关，文案立刻跟着变。
func _check_label_follows_switch() -> void:
	var lv := 2
	await _mk(lv - 1, false)
	_scroll._scroll_to_slot(lv - 1)
	await _settle(8)
	var meta: Label = _scroll.get("_strip_meta")
	_check(not String(meta.text).contains("真实落位"),
			"⑥ 普通模式读数不带真布局标注", String(meta.text))
	CharacterData.match_quick_mode = true
	_scroll.call("_rebuild_focus_reading")
	await _settle(6)
	_check(String(meta.text).contains("真实落位"),
			"⑥ 拨到快速 ⇒ 读数立刻写「真实落位」", String(meta.text))
	CharacterData.match_quick_mode = false
	_scroll.call("_rebuild_focus_reading")
	await _settle(6)
	_check(not String(meta.text).contains("真实落位"),
			"⑥ 拨回普通 ⇒ 标注立刻收回", String(meta.text))
	await _destroy()


## ⑦ 同源对撞（本票最重要的一条）：
## 拓印上对方 6 个格子，必须等于真开一局快速模式后规则层实际 deployed 的格子。
## 只比 layout_for 是左手查右手；这条才守得住 ADR-0004 的硬约束。
func _check_same_source_as_match() -> void:
	var lv := 5
	await _mk(lv - 1, true)
	var t := _tile(lv)
	var rub := {}
	if not t.is_empty():
		var hosts: Array = t["hosts"]
		var board: Control = t["board"]
		for i in hosts.size():
			rub[String((t["deck"] as Array)[i])] = board.stone_cell(i)
	await _destroy()

	CharacterData.match_quick_mode = true
	CharacterData.match_level_cleared = lv - 1
	GameState.match_context = {"level": lv}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await _settle(24)
	var st = arena.get("_state")
	var real := {}
	for i in st.team_cards(1):
		var c: Dictionary = st.cards[i]
		real[String(c["boss_id"])] = c["cell"]
	arena.queue_free()
	GameState.match_context = {}
	await _settle(4)

	_check(real.size() == MatchDB.DECK_SIZE, "⑦ 前置：真对局对方摆了 6 子", str(real.size()))
	var bad: Array = []
	for k in rub:
		if not real.has(k):
			bad.append("拓印里的 %s 对局没有" % k)
		elif Vector2i(rub[k]) != Vector2i(real[k]):
			bad.append("%s 拓印%s ≠ 对局%s" % [k, str(rub[k]), str(real[k])])
	for k in real:
		if not rub.has(k):
			bad.append("对局里的 %s 拓印没画" % k)
	_check(bad.is_empty(), "⑦ 拓印格子集合 == 真对局实际 deployed 集合", str(bad))


func _finish() -> void:
	await _destroy()
	CharacterData.match_quick_mode = false
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
