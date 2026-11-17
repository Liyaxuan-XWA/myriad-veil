extends Node
## 大陆核心的法宝卫星体：棋局里的取敌（票 003）
##
## 四只核心首领（练气/筑基/结丹/元婴）都在卡池里，它们带的禁步桩与蚀甲锥
## 原来都按组名取敌：
##   · 禁步桩 `if group == "boss" and not is_ally_unit(u): continue`
##     ⇒ 棋盘上 12 只全是 is_ally=false，每一个都被跳过 ⇒ **谁也圈不住**
##   · 蚀甲锥固定 `target_group = "player"` ⇒ 棋局里没有 player 节点 ⇒ **恒不命中**
## 两处都不崩，只是静默 0 效果，所以单打与规则层模拟都发现不了。
##
## 用法：godot --headless --path . res://tools/probe_treasure_match.tscn -- --no-save

const CORE := "world_core_shihou"

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
	print("\n########## 核心法宝 · 棋局取敌 ##########")
	await _check_stake_match()
	await _check_cone_match()
	await _check_single_player_paths()
	_finish()


## ① 禁步桩：施放者是棋子时按队伍筛
func _check_stake_match() -> void:
	await _clear()
	var a := _piece(0, Vector2i(0, 0))
	var b := _piece(1, Vector2i(0, 1))
	var mate := _piece(0, Vector2i(1, 1))
	await _frames(6)
	if a == null or b == null or mate == null:
		_check(false, "① 前置：三只棋子装出来了", "")
		return
	# 圈心放在 b 身上，半径 300 ⇒ 同队的 mate 也在圈内，但不该被圈住
	var f := _stake(a, b.global_position)
	var t: Array = f.call("_targets")
	_check(t.size() == 1 and t[0] == b, "① 棋子里禁步桩只圈对方队伍", "%d 个" % t.size())
	_check(not t.has(mate), "① 同队棋子不进目标列表", "")
	_check(not t.has(a), "① 施放者自己不进目标列表", "")
	# 反向：没传 caster 的老调用点行为一字不变（在棋局里仍是空 —— 这正是我们要传 caster 的理由）
	var f_old := TreasureStakeField.new()
	f_old.setup(b.global_position, false, 300.0, 0.8, 4.0, 1.5, 0.65, 0.6, "", null)
	add_child(f_old)
	_spawned.append(f_old)
	await _frames(2)
	_check((f_old.call("_targets") as Array).is_empty(),
			"① 没传 caster 时仍走旧分派（老调用点没被顺手改掉）", "")
	# ⚠ 列表非空不等于机制生效（mirror_image:471 就是这么漏的）：
	#   这里要把 _arm() 真跑一遍，看禁步有没有挂到对方棋子身上、有没有误挂到同队。
	f.call("_arm")
	await _frames(2)
	var foe_db: Dictionary = b.get("debuffs")
	var mate_db: Dictionary = mate.get("debuffs")
	_check(foe_db.has("jinbu"), "① 禁步真的挂到对方棋子身上", str(foe_db.keys()))
	_check(not mate_db.has("jinbu"), "① 同队棋子不会被禁步桩减速", str(mate_db.keys()))


## ② 蚀甲锥：施放者是棋子时按队伍筛，不再看 "player" 组名
func _check_cone_match() -> void:
	await _clear()
	var a := _piece(0, Vector2i(0, 0))
	var b := _piece(1, Vector2i(0, 1))
	var mate := _piece(0, Vector2i(1, 1))
	await _frames(6)
	if a == null or b == null:
		_check(false, "② 前置：两只棋子装出来了", "")
		return
	# 锥体照旧固定 target_group="player" —— 在棋局里这个字符串已经不参与判断
	var cone := TreasureCone.new()
	cone.setup(a, "player", Vector2.RIGHT, 900.0, 400.0, "shixi", 8.0, "")
	add_child(cone)
	_spawned.append(cone)
	await _frames(2)
	cone.call("_on_body_entered", b)
	_check(bool(cone.get("_hit")), "② 棋子里蚀甲锥命中对方棋子（旧写法恒不命中）", "")
	var cone2 := TreasureCone.new()
	cone2.setup(a, "player", Vector2.RIGHT, 900.0, 400.0, "shixi", 8.0, "")
	add_child(cone2)
	_spawned.append(cone2)
	await _frames(2)
	cone2.call("_on_body_entered", mate)
	_check(not bool(cone2.get("_hit")), "② 同队棋子不会被蚀甲锥打中", "")


## ③ 反向判据：非棋子施放者（野修 / 玩家）仍按老组名分派
func _check_single_player_paths() -> void:
	await _clear()
	# ⚠ 不能用裸 Node2D 当"假玩家"：treasure_cone.gd:157 写的是
	#   `bool(body.get("is_dead"))`，桩上没有这个属性 → get 回 null →
	#   本机 4.7.2 的 bool(null) 直接报 "Nonexistent 'bool' constructor"，
	#   函数在那一行就断了，量到的 _hit 永远是 false（第一版就是这么红的）。
	#   真玩家有这些字段，所以这条判据要用真场景。
	var dummy: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(dummy)
	_spawned.append(dummy)
	var wild := Node2D.new()
	wild.name = "FakeWild"
	wild.add_to_group("boss")
	add_child(wild)
	_spawned.append(wild)
	await _frames(6)
	# 野修放的圈（cast_by_player=false）照旧只圈玩家阵营
	var f := TreasureStakeField.new()
	f.setup(dummy.global_position, false, 300.0, 0.8, 4.0, 1.5, 0.65, 0.6, "", null)
	add_child(f)
	_spawned.append(f)
	await _frames(2)
	var t: Array = f.call("_targets")
	_check(t.has(dummy) and not t.has(wild),
			"③ 非棋子施放者仍按旧组名分派（野修圈玩家、不圈同行）", str(t.size()))
	# 锥体的非棋子分支：这里**故意不打玩家** —— 刚入树的真玩家带着出生无敌帧，
	# `invincible_timer > 0` 会在归属判定之前就 return，量到的是玩家的宽限期而不是路由。
	# 路由本身用 boss 组桩验就够：target_group="boss" ⇒ 同组非友军算目标。
	var peer := Node2D.new()
	peer.name = "FakeWild2"
	peer.add_to_group("boss")
	add_child(peer)
	_spawned.append(peer)
	await _frames(2)
	var cone := TreasureCone.new()
	cone.setup(wild, "boss", Vector2.RIGHT, 900.0, 400.0, "shixi", 8.0, "")
	add_child(cone)
	_spawned.append(cone)
	await _frames(2)
	cone.call("_on_body_entered", peer)
	_check(bool(cone.get("_hit")),
			"③ 非棋子锥体仍按 target_group 判定（没被队伍分支抢走）", "")


func _piece(team: int, cell: Vector2i) -> Node2D:
	var p := MatchAdapter.spawn_piece(self, CORE, team, cell)
	if p != null:
		_spawned.append(p)
	return p


func _stake(caster: Node, pos: Vector2) -> Node:
	var f := TreasureStakeField.new()
	f.setup(pos, false, 300.0, 0.8, 4.0, 1.5, 0.65, 0.6, "", caster)
	add_child(f)
	_spawned.append(f)
	return f


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
