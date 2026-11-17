extends Node
## 镇墟石犼「闻声」的适用范围（2026-11-05 用户拍定：单打专属）
##
## `_find_prey()` 返回 `get_first_node_in_group("player")` ⇒ 棋局里没有玩家节点，
## `_prey` 恒 null，于是 `_tick_noise()` / `_echo_pulse()` 都在第一行返回：
## 声追踪、P2 回声的「被听见了」、`shihou_pounce` 冷却重置全不触发。
##
## 这不是漏改，是**拍定的范围限制**：噪声源是玩家专属遥测
## （`noise_ping_seq` / `noise_ping_pos` / 闪避 / 结符），
## 「安静站着就不被听见」这套博弈的前提是场上有个在控制动静的人。
## 对面是 12 只 AI 时这条机制对人没有意义。
##
## 所以这条探针守两件事：
##   ① 限制确实成立且不报错（不是半坏状态）；
##   ② 石犼在棋局里**仍是会打的正常棋子** —— 目标解析走队伍路径，没被连带弄坏。
##
## 用法：godot --headless --path . res://tools/probe_shihou_scope.tscn -- --no-save

const SHIHOU := "world_core_shihou"
const PREY_PLANNED := 9        ## 计划跑到的判据数，见 _finish() 的说明

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


func _ready() -> void:
	print("\n########## 石犼闻声 · 适用范围 ##########")
	var prey := _piece(1, Vector2i(0, 0))
	var foe := _piece(0, Vector2i(0, 3))
	await _frames(10)
	if prey == null or foe == null:
		_check(false, "① 前置：石犼与一只对方棋子都装出来了", "")
		_finish()
		return

	# ① 限制成立
	_check(prey.get("_prey") == null,
			"① 棋局里 _prey 恒 null（闻声整套不启动，这是拍定的范围限制）", "")
	# 跑十帧不该有任何东西被"听见"
	var noise_before: Vector2 = prey.get("_last_noise")
	for i in 10:
		prey.call("_tick_noise", 0.1)
	await _frames(4)
	_check(prey.get("_last_noise") == noise_before,
			"① 空跑 _tick_noise 不改声点（不是半启动状态）", "")
	_check(is_instance_valid(prey) and prey.is_inside_tree(),
			"① 空跑后石犼仍活着在树里（没被自己的 null 分支弄崩）", "")

	# ② 仍是会打的正常棋子
	var foes: Array = BossBase.hostile_units(prey)
	_check(foes.size() == 1 and foes[0] == foe,
			"② 石犼的目标解析正常：按队伍拿到对方棋子", "%d 个" % foes.size())
	_check(prey.call("focus_node") == foe,
			"② focus_node 也指得对（招式朝向 / 距离都读它）", "")
	_check(not BossBase.is_unit_dead(prey), "② 石犼没进死亡态", "")
	_check(float(prey.get("attack_power")) > 0.0,
			"② 攻击力按棋子面板折算到位", "%.1f" % float(prey.get("attack_power")))

	# ③ 单打那条路照旧有声追踪（反向判据）
	# ⚠ 假猎物必须用**真玩家场景**：`youming_core_shihou.gd:126` 写的是
	#   `bool(p.get("is_dead"))`，裸 Node2D 桩上没这个属性 → get 回 null →
	#   本机没有 bool() 构造器，每帧刷一条 SCRIPT ERROR。
	#   这是本次开发第三次踩同一类夹具坑（前两次：probe_treasure_match、probe_shadow_match），
	#   规矩定下来：**凡是被生产代码用 bool()/float(get(...)) 读过的字段，桩一律不许裸造**，
	#   要么用真场景，要么先 grep 出被读的字段再补上。
	var solo: Node2D = (load("res://scenes/world/youming_core_shihou.tscn") as PackedScene).instantiate()
	add_child(solo)
	_spawned.append(solo)
	var stub: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(stub)
	_spawned.append(stub)
	await _frames(8)
	_check(BossBase.unit_team(solo) < 0, "③ 前置：单打石犼没有队伍号", str(BossBase.unit_team(solo)))
	_check(solo.get("_prey") == stub,
			"③ 单打仍认玩家为猎物（限制没被反向扩大）", "")

	_finish()


func _piece(team: int, cell: Vector2i) -> Node2D:
	var p := MatchAdapter.spawn_piece(self, SHIHOU, team, cell)
	if p != null:
		_spawned.append(p)
	return p


func _finish() -> void:
	# ⚠ 这条不是凑数：本机 GDScript 的运行时错误会**中断当前函数**，
	#   而 `_ready` 仍能走到 `_finish()` ⇒ 一个只跑了一半的探针照样打 fails=0。
	#   本次开发里真踩过两次（`Node.method()` / `bool(null)`），所以每个探针都要有到达哨兵。
	_check(_passes + _fails.size() >= PREY_PLANNED,
			"④ 判据全部跑到（防函数中途报错造成假绿）",
			"%d 条 / 计划 ≥%d" % [_passes + _fails.size(), PREY_PLANNED])
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
