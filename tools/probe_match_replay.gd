extends Node
## 已封卷的关卡必须能重打（2026-11-06 用户报「打过的关卡为什么无法重新挑战」）
##
## 关卡制的口径是**重打不给钱、不推进度，但必须能进**（§2c / ADR-0001）。
## 实现里两处都把"打过的"和"没解锁的"混成一类：按钮态与点击判定各写一份
## `_focused == _current`，于是点回第 3 关时钮变灰、文案还写着「尚未解锁」。
## 现在两处共用 `_cta_playable()`，这条探针盯着这个共用点与三种文案。
##
## 用法：godot --headless --path . res://tools/probe_match_replay.tscn -- --no-save

const SCROLL := "res://scenes/match/match_level_scroll.tscn"

var _passes := 0
var _fails: Array = []
var _planned := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _plan(n: int) -> void:
	_planned += n


func _ready() -> void:
	print("\n########## 已封卷关卡重打 ##########")
	CharacterData.match_level_cleared = 4
	GameState.match_context = {}
	var scroll: Node = (load(SCROLL) as PackedScene).instantiate()
	add_child(scroll)
	await get_tree().process_frame
	await get_tree().process_frame

	_plan(9)
	_check(int(scroll._current) == 5, "① 已通 4 关 ⇒ 当前关是第 5 关", str(scroll._current))
	# 共用判据本身：<= 当前关可进，将来关不可
	var wrong: Array = []
	for lv in [1, 3, 4, 5]:
		if not scroll._cta_playable(lv):
			wrong.append(lv)
	for lv in [6, 7, 12]:
		if scroll._cta_playable(lv):
			wrong.append(-lv)
	_check(wrong.is_empty(), "① `_cta_playable` 只挡「还没打到的将来关」", str(wrong))

	# 三种文案都要是玩家能读懂的中文，且按钮态跟着走
	scroll._focused = 2
	scroll._refresh_strip()
	_check(String(scroll._cta.text) == "重打此关", "② 焦点在已封卷的关 ⇒ 文案「重打此关」",
			String(scroll._cta.text))
	_check(not scroll._cta.disabled, "② 已封卷的关按钮可点", str(scroll._cta.disabled))
	_check(String(scroll._cta.tone) == "primary", "② 可点时它仍是这一屏唯一的主按钮",
			String(scroll._cta.tone))

	scroll._focused = 5
	scroll._refresh_strip()
	_check(String(scroll._cta.text) == "进入此关" and not scroll._cta.disabled,
			"③ 当前关文案与可点不变（反向判据）", str(scroll._cta.text))

	scroll._focused = 7
	scroll._refresh_strip()
	_check(String(scroll._cta.text) == "尚未解锁" and scroll._cta.disabled,
			"③ 将来关仍然禁用且文案是「尚未解锁」", str(scroll._cta.text))

	# 真效果：点下去要打进**选中的那一关**，不是当前关
	scroll._focused = 2
	scroll._enter(2)
	_check(int(GameState.match_context.get("level", -1)) == 2,
			"④ 重打进的是第 2 关（上下文写的是焦点关，不是当前关）",
			str(GameState.match_context))
	# 卡组跟着关卡号走：第 2 关的阵与长卷拓印画的必须是同一批
	var deck: Array = MatchLevelDeck.deck_for(2)
	_check(deck.size() == MatchDB.DECK_SIZE, "④ 第 2 关卡组仍是那 6 张（同源）", str(deck.size()))

	scroll.queue_free()
	await get_tree().process_frame
	GameState.match_context = {}
	CharacterData.match_level_cleared = 0
	_check(_passes + _fails.size() >= _planned, "⑤ 判据全部跑到（没有半途中止）",
			"%d/%d" % [_passes + _fails.size(), _planned])
	_finish()


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
