extends Node
## 观澜镜身：棋局里的队伍号与可攻击身份（票 005）
##
## MirrorImage 原来只有 `faction` 字符串，没有 team_id，入组也只入 "boss"/"ally_summon"。
## 棋局里因此两头都断：
##   · 三处查 `get_first_node_in_group("player")` 拿目标 ⇒ 棋盘上没有 player 节点，
##     恒 null ⇒ 镜像**既不出伤也不走位**
##   · `_team_enemy_units()` 只扫 match_piece ⇒ 镜像**根本打不到**，会一直堆在场上的
## 现在镜像从本体继承 team_id、带队伍号时入 match_piece，取目标走统一入口。
## 单打 / 塔 / 秘境 / 玩家侧的镜像没有队伍号 ⇒ 一律走原分支，行为一字不变。
##
## 用法：godot --headless --path . res://tools/probe_mirror_match.tscn -- --no-save

const GUANLAN := "boss_04"

var _passes := 0
var _fails: Array = []
var _spawned: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_spawned.clear()
	await _frames(8)


func _ready() -> void:
	print("\n########## 观澜镜身 · 棋局队伍号 ##########")
	await _check_match_mirror()
	await _check_single_player_unchanged()
	_finish()


func _piece(team: int, cell: Vector2i) -> Node2D:
	var p := MatchAdapter.spawn_piece(self, GUANLAN if team == 1 else "boss_01", team, cell)
	if p != null:
		_spawned.append(p)
	return p


## ① 棋局里的镜像：有队伍号、打得到、认得出目标
func _check_match_mirror() -> void:
	await _clear()
	var guan := _piece(1, Vector2i(0, 0))
	var foe := _piece(0, Vector2i(0, 1))
	await _frames(8)
	if guan == null or foe == null:
		_check(false, "① 前置：观澜与一只对方棋子都装出来了", "")
		return
	var img: MirrorImage = guan.call("_spawn_image", 0)
	await _frames(3)
	_check(img != null, "① 前置：镜像生成了", "")
	if img == null:
		return
	_check(int(img.get("team_id")) == 1, "① 镜像从本体继承队伍号", str(img.get("team_id")))
	_check(img.is_in_group(BossBase.MATCH_PIECE_GROUP),
			"① 镜像入了 match_piece（否则对方棋子永远选不到它）", "")
	_check(BossBase.hostile_units(foe).has(img),
			"① 对方棋子**打得到**镜像（旧写法它不在任何可攻击列表里）", "")
	_check(not BossBase.hostile_units(guan).has(img),
			"② 自家镜像不算自家棋子的敌人（不会自己砍自己）", "")
	_check(img.call("_focus_target") == foe,
			"① 镜像认得出该打谁（旧写法查 player 组恒 null）", "")
	# ⚠ 光验"认得出"不够 —— 上一轮就是只验到这里，实机照样崩：
	#   取到的是棋子，而伤害那行还按玩家签名传参（Cannot convert argument 3）。
	#   改了取目标就必须把"打到目标"也跑一遍。
	var foe_hp_before := float(foe.get("current_hp"))
	img.call("_boss_echo")
	await _frames(2)
	_check(float(foe.get("current_hp")) < foe_hp_before,
			"① 镜影斩真的落在对方棋子身上（签名按目标类型分流）",
			"%.0f → %.0f" % [foe_hp_before, float(foe.get("current_hp"))])
	_check(is_instance_valid(foe) and foe.is_inside_tree(),
			"① 结算后目标还活着在树里（没被错误签名打断战斗）", "")


## ② 反向判据：没有队伍号的镜像走原分支
func _check_single_player_unchanged() -> void:
	await _clear()
	var stub := Node2D.new()
	stub.name = "FakePlayer"
	stub.add_to_group("player")
	add_child(stub)
	_spawned.append(stub)
	# 直接实例化 ⇒ team_id 保持 -1，就是单打那套身份
	var guan: Node2D = (load("res://scenes/boss/domain_boss_04.tscn") as PackedScene).instantiate()
	add_child(guan)
	_spawned.append(guan)
	await _frames(8)
	var img: MirrorImage = guan.call("_spawn_image", 0)
	await _frames(3)
	_check(img != null, "② 前置：单打镜像生成了", "")
	if img == null:
		return
	_check(int(img.get("team_id")) < 0, "② 单打镜像没有队伍号", str(img.get("team_id")))
	_check(not img.is_in_group(BossBase.MATCH_PIECE_GROUP),
			"② 单打镜像不入 match_piece（没被顺手升级成棋子）", "")
	_check(img.call("_focus_target") == stub,
			"② 单打镜像仍按 player 组取目标", "")


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
