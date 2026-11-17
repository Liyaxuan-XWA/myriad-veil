extends Node
## 棋坛关卡 · 结算经济（#56，2026-11-05）
##
## 口径来自 ADR-0001：关卡制下**取消押注**，只发一次性首通奖 8 锻造晶石；
## 重打已通关、失败、平局一律 0 收支，绝不扣玩家东西。
##
## 用法：godot --headless --path . res://tools/probe_match_level_reward.tscn -- --no-save

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


func _wallet() -> int:
	return int(CharacterData.count_material(CRYSTAL))


## 起一局并把结果摆成要的样子（真跑完一局要几分钟，这里只验结算这一段）
## ⚠ 不要在这里重置 match_level_cleared —— 各用例自己先摆好进度再调进来。
func _finish_match(level: int, outcome: int) -> Dictionary:
	GameState.match_context = {"level": level}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 1.0)
	add_child(arena)
	for i in 10:
		await get_tree().physics_frame
	var st = arena.get("_state")
	st.winner = outcome
	st.end_reason = "clear_field"
	st.phase = MatchState.Phase.OVER
	arena.call("_settle")
	var text := String(arena.get("_result_label").text)
	var before := _wallet()
	arena.queue_free()
	await get_tree().process_frame
	return {"text": text, "wallet": before, "arena": arena}


func _ready() -> void:
	print("\n########## 棋坛关卡 · 结算经济 ##########")
	CharacterData.inventory = []
	CharacterData.match_level_cleared = 0

	await _check_first_clear()
	await _check_replay()
	await _check_loss_and_draw()
	await _check_empty_wallet()
	_check_bet_retired()
	_check_hud_has_no_bet()
	_finish()


## ① 首通第 4 关 ⇒ +8 锻造晶石、进度推到 4、文案写清是首通奖
func _check_first_clear() -> void:
	CharacterData.inventory = [_crystal(100)]
	CharacterData.match_level_cleared = 3
	var r := await _finish_match(4, 0)      # winner == PLAYER_TEAM == 0
	_check(_wallet() == 108, "① 首通第 4 关只加 8 晶石（不是押注的 50）", "钱包=%d" % _wallet())
	_check(CharacterData.match_level_cleared == 4, "① 进度记到第 4 关",
			"%d" % CharacterData.match_level_cleared)
	_check(r.text.contains("8"), "① 结算文案把数额写出来", _one_line(r.text))


## ② 重打已通关并获胜 ⇒ 一分不给，进度不许倒退也不许再发
func _check_replay() -> void:
	CharacterData.inventory = [_crystal(100)]
	CharacterData.match_level_cleared = 9
	var r := await _finish_match(3, 0)
	_check(_wallet() == 100, "② 重打已通关获胜不给钱（最容易写成 +8 的一条）",
			"钱包=%d" % _wallet())
	_check(CharacterData.match_level_cleared == 9, "② 进度不被低关卡改写",
			"%d" % CharacterData.match_level_cleared)


## ③ 失败 / 平局 ⇒ 0 收支，而且绝不扣东西
func _check_loss_and_draw() -> void:
	CharacterData.inventory = [_crystal(100)]
	CharacterData.match_level_cleared = 4
	var lose := await _finish_match(5, 1)     # AI_TEAM == 1 胜
	_check(_wallet() == 100, "③ 输了不扣一分钱（押注制下这里会 -50）", "钱包=%d" % _wallet())
	_check(CharacterData.match_level_cleared == 4, "③ 失败不推进度",
			"%d" % CharacterData.match_level_cleared)
	_check(not lose.text.contains("-50") and not lose.text.contains("失去"),
			"③ 失败文案不再出现扣钱", _one_line(lose.text))

	CharacterData.inventory = [_crystal(100)]
	CharacterData.match_level_cleared = 4
	var draw := await _finish_match(5, MatchState.WIN_DRAW)
	_check(_wallet() == 100, "③ 平局 0 收支", "钱包=%d" % _wallet())
	_check(CharacterData.match_level_cleared == 4, "③ 平局不算通过",
			"%d" % CharacterData.match_level_cleared)


## ④ 零代价的可证伪测试：钱包为空时进关、输掉，钱包仍然为空
func _check_empty_wallet() -> void:
	CharacterData.inventory = []
	CharacterData.match_level_cleared = 0
	var r := await _finish_match(1, 1)
	_check(_wallet() == 0, "④ 空钱包进关输掉之后仍然为空", "钱包=%d" % _wallet())
	_check(r.text != "", "④ 空钱包也照样给一句结算", _one_line(r.text))


## ⑤ 押注从关卡路径上撤干净，但纯函数按 ADR 保留给以后的真人对局
func _check_bet_retired() -> void:
	# ⚠ 只扫代码、不扫注释：解释"为什么押注撤掉了"的注释是要留给后来人的，
	#   拿它当"还在用押注"是误报，逼人说谎式删注释更糟。
	var src := _code_only(FileAccess.get_file_as_string("scripts/match/match_arena.gd"))
	var hits: Array[String] = []
	for frag in ["bet_matched", "BET_MIN", "BET_MAX", "consume_materials"]:
		if src.contains(frag):
			hits.append(frag)
	_check(hits.is_empty(), "⑤ 对局代码里不再有任何押注调用（含扣钱分支）", str(hits))
	_check(not src.contains("_bet"), "⑤ 随之失去全部用途的 _bet 也删干净了", "")
	# 反过来：MatchDB 那三个必须还在，否则以后接联机要重写规则
	var db := _code_only(FileAccess.get_file_as_string("scripts/match/match_db.gd"))
	_check(db.contains("static func bet_matched") and db.contains("const BET_MIN"),
			"⑤ bet_matched / BET_MIN / BET_MAX 仍保留在 MatchDB（ADR-0001）", "")
	# 奖励数额是表里的常量，不是写在结算函数里的字面量
	_check(int(MatchDB.LEVEL_FIRST_CLEAR_REWARD) == 8, "⑤ 首通奖 = 8 来自 MatchDB 常量",
			"%s" % str(MatchDB.LEVEL_FIRST_CLEAR_REWARD))


## ⑥ HUD 右侧读数不该还挂着已经不结算的注额
func _check_hud_has_no_bet() -> void:
	var src := _code_only(FileAccess.get_file_as_string("scripts/match/match_arena.gd"))
	_check(not src.contains("注额"), "⑥ HUD 与结算里「注额」字样已清干净", "")


## 剥掉注释后的源码。GDScript 的 `#` 只在行首与行中作注释，
## 本项目的字符串字面量里没有 `#`（颜色用的是 Color(...) 不是十六进制串），所以直接切。
func _code_only(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		var at := String(line).find("#")
		out.append(String(line) if at < 0 else String(line).substr(0, at))
	return "\n".join(out)


func _crystal(n: int) -> Dictionary:
	var def := ItemDB.get_material(CRYSTAL)
	return {"id": CRYSTAL, "name": String(def.get("name", CRYSTAL)), "type": "material",
		"count": n, "icon": String(def.get("icon", ""))}


func _one_line(t: String) -> String:
	var parts := t.split("\n")
	return String(parts[0]) if not parts.is_empty() else t


func _finish() -> void:
	CharacterData.inventory = []
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
