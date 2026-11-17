extends Node
## BossBase.hostile_units() —— 卫星实体的统一取敌入口
##
## 起因：2026-11-05 实机发现棋局里 16 张卡至少 10 张的**卫星机制静默打空**。
## 主路径（BOSS 本体招式）走 `enemy_units()` 是对的，但刀痕 / 法宝场地 / 扇形弹体 /
## 火种 / 镜像 / 界灯都不是 BossBase，它们各自 `get_nodes_in_group("player")` ——
## 而**棋局里根本没有 "player" 组节点**（双方都是带 team_id 的 match_piece）。
## 这个探针守的就是那三类分派各自都还成立，尤其守住"不许把队友算进敌人"。
##
## 用法：godot --headless --path . res://tools/probe_hostile_units.tscn -- --no-save

const PIECE_A := "boss_01"        ## 刀客：留痕机制就是这次哑火的头号
const PIECE_B := "boss_huyao"

var _passes := 0
var _fails: Array = []


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


## ⚠ 每个用例结束都要清场：棋子是挂在 self 下的，不清就会累到下一个用例的计数里
##   （本项目老坑「偶发红先查判据累积状态」——第一版就是 ② 被  的三只污染成 2/3 个）。
var _spawned: Array = []


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_spawned.clear()
	await _frames(6)


func _ready() -> void:
	print("\n########## 卫星实体统一取敌 ##########")
	await _check_match_pieces()
	await _check_same_id_rivalry()
	await _check_dead_excluded()
	await _check_single_player_paths()
	_finish()


func _spawn(team: int, cell: int, boss_id: String = PIECE_A) -> Node2D:
	var p := MatchAdapter.spawn_piece(self, boss_id, team, Vector2i(cell % 6, int(cell / 6)))
	if p != null:
		_spawned.append(p)
	return p


## ① 棋局：两只敌对棋子互相看得见，且**看不见自己**。
func _check_match_pieces() -> void:
	await _clear()
	var a := _spawn(0, 0)
	var b := _spawn(1, 7)
	await _frames(4)
	_check(a != null and b != null, "① 前置：两只棋子都装出来了", "")
	if a == null or b == null:
		return
	var ha: Array = BossBase.hostile_units(a)
	var hb: Array = BossBase.hostile_units(b)
	_check(ha.size() == 1 and ha[0] == b, "① 0 队的敌人只有 1 队那只（不含自己）", str(ha.size()))
	_check(hb.size() == 1 and hb[0] == a, "① 1 队反过来也一样", str(hb.size()))
	# 同队第三只：这是旧写法最容易混的地方（"boss" 组里双方都在）
	var a2 := _spawn(0, 1)
	await _frames(4)
	var ha2: Array = BossBase.hostile_units(a)
	_check(ha2.size() == 1 and not ha2.has(a2),
			"① 同队第三只不许进敌人列表（旧写法按 boss 组就会把它算进去）", str(ha2.size()))
	_check(not BossBase.hostile_units(a2).has(a),
			"① 同队互为队友（反向也成立）", "")
	_check(BossBase.hostile_units(a2).has(b), "① 队友列表里仍含对方棋子", "")


## ② 同一只 BOSS 的两个实例分属两队 —— 棋局里玩家 6 张与对手 6 张可以重名，
## 所以"按 boss_id 找对手"必错，只能按队伍。
func _check_same_id_rivalry() -> void:
	await _clear()
	var x := _spawn(0, 20, PIECE_A)
	var y := _spawn(1, 21, PIECE_A)
	await _frames(4)
	if x == null or y == null:
		_check(false, "② 前置：同名两只都装出来了", "")
		return
	_check(BossBase.hostile_units(x).has(y) and BossBase.hostile_units(y).has(x),
			"② 同一只 BOSS 的两个实例按队伍互为敌人", "")
	_check(BossBase.hostile_units(x).size() == 1,
			"② 不会因为 boss_id 相同就把另一只当自己人", str(BossBase.hostile_units(x).size()))


## ③ 死人不占列表；空 source 不崩。
func _check_dead_excluded() -> void:
	await _clear()
	var a := _spawn(0, 30)
	var b := _spawn(1, 31)
	await _frames(4)
	if a == null or b == null:
		_check(false, "③ 前置：两只棋子都装出来了", "")
		return
	# `is_dead()` 读的是状态机而不是血量（boss_base.gd:2114），
	# 只把 current_hp 归零不会让它进列表剔除 —— 第一版就是这么假绿过去的。
	b.set("current_hp", 0.0)
	b.set("state", BossBase.BossState.DEAD)
	await _frames(2)
	_check(BossBase.hostile_units(a).is_empty(),
			"③ 对方死透后列表为空（AI 不能盯着尸体打）", str(BossBase.hostile_units(a).size()))
	_check(BossBase.hostile_units(null).is_empty(), "③ source 为 null 返回空而不是崩", "")
	_check(BossBase.hostile_target(a) == null, "③ 没敌人时 hostile_target 返回 null", "")


## ④ 单打 / 塔 / 秘境的老路径必须**一个都不变**（反向判据）。
## 棋局是新场景，改统一入口最容易伤到的就是这条已经跑了几周的路。
func _check_single_player_paths() -> void:
	await _clear()
	var player := Node2D.new()
	player.name = "FakePlayer"
	player.add_to_group("player")
	add_child(player)
	var boss: Node2D = (load("res://scenes/boss/domain_boss_01.tscn") as PackedScene).instantiate()
	add_child(boss)
	await _frames(4)
	_check(BossBase.unit_team(boss) < 0, "④ 前置：单打 BOSS 没有队伍号", str(BossBase.unit_team(boss)))
	_check(BossBase.hostile_units(boss).has(player),
			"④ 单打 BOSS 的敌人仍是玩家（走它自己的 enemy_units()）", "")
	_check(BossBase.hostile_units(player).has(boss),
			"④ 玩家侧卫星的敌人仍是 boss 组", "")
	_check(BossBase.hostile_target(boss) == player,
			"④ 单打取单个目标也拿到玩家", "")
	player.queue_free()
	boss.queue_free()
	await _frames(3)


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
