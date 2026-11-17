extends Node
## 棋坛关卡 · 长卷预告与窗口规则（#57，2026-11-05）
##
## 守四件事：
##   ① 窗口 = 已通关全部 + 当前关 + 往后 5 关，其后 6 枚剪影；
##   ② 深进度不许把最老的关卡砍掉，也不许把上千个卡面节点全建出来（虚拟化）；
##   ③ 剪影不生成卡组、点不动、不给主按钮；
##   ④ 横扫时可见槽位不许露白；朝向未定靠图形不靠往玩家脸上堆字。
##
## 用法：godot --headless --path . res://tools/probe_match_scroll_preview.tscn -- --no-save

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


func _mk(cleared: int) -> Control:
	CharacterData.match_level_cleared = cleared
	GameState.match_context = {}
	var s: Control = MatchLevelScroll.new()
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(s)
	await _settle(12)
	return s


func _kill(s: Control) -> void:
	s.queue_free()


func _ready() -> void:
	print("\n########## 棋坛关卡 · 长卷预告与窗口 ##########")
	await _check_window_rule()
	await _check_deep_progress()
	await _check_silhouette_inert()
	await _check_no_gap_on_scroll()
	await _check_orientation_is_graphic()
	_finish()


## ① 窗口规则
func _check_window_rule() -> void:
	var s := await _mk(0)
	_check(int(s._current) == 1, "① 新档当前关 = 1", "%d" % int(s._current))
	_check(int(s._deck_slot_count()) == 1 + MatchLevelScroll.PREVIEW_AHEAD,
			"① 有卡组的槽 = 当前关 + 往后 5", "%d" % int(s._deck_slot_count()))
	_check(int(s._slot_count()) == int(s._deck_slot_count()) + MatchLevelScroll.SILHOUETTE_SLOTS,
			"① 其后还挂 %d 枚剪影（读作「卷还在往右长」）" % MatchLevelScroll.SILHOUETTE_SLOTS,
			"%d" % int(s._slot_count()))
	_check(not bool(s._is_silhouette(6)), "① 第 6 关仍在预览窗口内（有卡组）", "")
	_check(bool(s._is_silhouette(7)), "① 第 7 关起变剪影", "")
	_check(int(s._slot_level(0)) == 1, "① 最左槽就是第 1 关", "%d" % int(s._slot_level(0)))
	_kill(s)
	await _settle(4)


## ② 深进度：历史不许被砍，节点不许全建
func _check_deep_progress() -> void:
	var s := await _mk(120)
	_check(int(s._deck_slot_count()) == 126, "② 通关 120 局 ⇒ 卷上 126 副卡组",
			"%d" % int(s._deck_slot_count()))
	_check(int(s._slot_level(0)) == 1, "② 最左仍是第 1 关（不再被 MAX_TILES 砍掉）",
			"%d" % int(s._slot_level(0)))
	_check(s._tiles_by_slot.size() < 24, "② 只建可见范围的节点（虚拟化）",
			"已建 %d / 共 %d 槽" % [s._tiles_by_slot.size(), int(s._slot_count())])
	_check(s._tiles_by_slot.size() >= 4, "② 可见范围内确实建了东西（不是空卷）",
			"%d" % s._tiles_by_slot.size())

	s._scroll_to_slot(0)
	await _settle(8)
	var at_head := false
	for slot in s._tiles_by_slot.keys():
		if int(s._slot_level(int(slot))) == 1:
			at_head = true
	_check(at_head, "② 滚到卷首能看见第 1 关的拓印", str(s._tiles_by_slot.keys()))
	_check(s._tiles_by_slot.size() < 24, "② 滚过去之后仍然只建可见范围",
			"%d" % s._tiles_by_slot.size())
	_kill(s)
	await _settle(4)


## ③ 剪影不生成卡组、点不动、不给按钮
func _check_silhouette_inert() -> void:
	var s := await _mk(0)
	s._scroll_to_slot(int(s._slot_count()) - 1)
	await _settle(8)
	var bad: Array[String] = []
	for slot in s._tiles_by_slot.keys():
		var lv := int(s._slot_level(int(slot)))
		if not bool(s._is_silhouette(lv)):
			continue
		var t: Dictionary = s._tiles_by_slot[slot]
		if not (t.get("deck", []) as Array).is_empty():
			bad.append("第 %d 关剪影竟然带着卡组" % lv)
		if (t["root"] as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			bad.append("第 %d 关剪影还吃点击" % lv)
	_check(bad.is_empty(), "③ 剪影无卡组且点不动", str(bad))
	_check(bool(s._cta.disabled), "③ 焦点落在剪影上时主按钮禁用", str(s._cta.text))
	_kill(s)
	await _settle(4)


## ④ 横扫时可见槽位不许露白
func _check_no_gap_on_scroll() -> void:
	var s := await _mk(9)
	var gaps: Array[String] = []
	for dx in range(0, 2600, 130):
		s._strip.position.x = -float(dx)
		s._sync_tiles()
		await _settle(2)
		for slot in (s._visible_slots() as Array):
			if not s._tiles_by_slot.has(int(slot)):
				gaps.append("x=%d 缺槽 %d" % [dx, int(slot)])
				break
		if not gaps.is_empty():
			break
	_check(gaps.is_empty(), "④ 横扫 20 档，可见槽位全部有节点（不露白）", str(gaps.slice(0, 4)))
	_kill(s)
	await _settle(4)


## ⑤ 朝向未定靠图形记号，不靠往玩家脸上堆字
func _check_orientation_is_graphic() -> void:
	# ⚠ 只扫代码不扫注释：源码里那句「不许写成『朝向未知』这类字」本身就是注释，
	#   连着注释一起扫会把它当成违规（#56 已经栽过同一类）。
	var src := _code_only(FileAccess.get_file_as_string("scripts/ui/facility/match_level_scroll.gd"))
	var hits: Array[String] = []
	for frag in ["朝向未知", "正/反未知", "未知朝向", "不确定"]:
		if src.contains(frag):
			hits.append(frag)
	_check(hits.is_empty(), "⑤ 代码里没有把「朝向未知」这类字印到卷上", str(hits))
	_check(src.contains("orientation"), "⑤ 改用统一的图形记号表达朝向未定", "")
	# 改版后的口径必须写在代码里，否则以后有人又把 6 张嵌回格子里当预测用
	_check(FileAccess.get_file_as_string("scripts/ui/facility/match_level_scroll.gd")
			.contains("不画 6×6 格子"), "⑤ 「普通模式不画格子」这条口径写进了代码", "")


## 剥掉注释后的源码。这些文件的字符串字面量里不含 `#`（颜色走 Color(...) 不是十六进制串），
## 所以按行切第一个 `#` 是安全的。
func _code_only(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		var at := String(line).find("#")
		out.append(String(line) if at < 0 else String(line).substr(0, at))
	return "\n".join(out)


func _finish() -> void:
	CharacterData.match_level_cleared = 0
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
