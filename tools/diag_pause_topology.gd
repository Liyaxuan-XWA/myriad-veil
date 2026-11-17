extends Node2D
## 用**生产拓扑**量暂停时谁能活着（对局场景就是要照这个摆）：
##   场景根 = MatchArena（默认 INHERIT，真游戏里它的父节点是 root viewport）
##   ├─ Pieces  INHERIT / PAUSABLE   ← 期望：暂停时冻住
##   ├─ Driver  ALWAYS（叶子）        ← 期望：暂停时仍逐帧跑
##   └─ Hud     ALWAYS + 孙 INHERIT   ← 期望：整支都活着（按钮要收输入）
##
## 反面教材那两支量的是"给场景根写 ALWAYS，再把棋子退回 PAUSABLE"这条路：
##   在这个最小复现里两种时机都冻得住（0 帧），可生产拓扑里同样写法的对局场景
##   实测冻不住棋子（_ready 先写 ALWAYS、棋子之后才建 → 窗口里点燃照跳、
##   延迟伤害照落地，见 probe_match_freeze 的负面测试）。
##   所以这条歧路的结局还取决于别的因素（节点类型、入树路径），**不要依赖它**；
##   只依赖本 diag 量清楚的一条：场景根 INHERIT 时，显式写 ALWAYS 的分支在暂停里照跑。
## 顺带一条底层事实（本 diag 自己就靠它推进）：树暂停时
## `create_timer()` 与 `physics_frame` / `process_frame` 照样每帧走。
## 用法：godot --headless --path . res://tools/diag_pause_topology.tscn

const TICKER := preload("res://tools/diag_ticker.gd")
const PHYS_TICKER := preload("res://tools/diag_physics_ticker.gd")

var _nodes: Dictionary = {}


func _leaf(name: String, m: Node.ProcessMode, parent: Node, physics: bool) -> Node:
	var c: Node = (PHYS_TICKER if physics else TICKER).new()
	c.name = name
	parent.add_child(c)
	c.process_mode = m          # 入树之后才写
	_nodes[name] = c
	return c


func _leaf_before(name: String, m: Node.ProcessMode, parent: Node) -> Node:
	var c: Node = TICKER.new()
	c.name = name
	c.process_mode = m          # 入树之前就写好（生产里棋子那支就是这个时机）
	parent.add_child(c)
	_nodes[name] = c
	return c


func _report(label: String) -> void:
	var out: Array = []
	for k in _nodes.keys() as Array:
		var n = _nodes[k]        # ⚠ 不能写成 `var n: Node`：ticks 是脚本上的动态属性
		out.append("%s=%d" % [str(k), int(n.ticks)])
		n.ticks = 0
	print("DIAG ", label, " → ", " | ".join(out))


func _ready() -> void:
	# 场景根**不写** process_mode（生产里对局场景就是这个状态）
	var arena := Node2D.new()
	arena.name = "Arena"
	add_child(arena)
	_leaf("根INHERIT下_叶子INHERIT", Node.PROCESS_MODE_INHERIT, arena, false)
	_leaf("根INHERIT下_叶子PAUSABLE", Node.PROCESS_MODE_PAUSABLE, arena, false)
	_leaf("根INHERIT下_叶子ALWAYS", Node.PROCESS_MODE_ALWAYS, arena, false)
	var hud := _leaf("根INHERIT下_HUD写ALWAYS", Node.PROCESS_MODE_ALWAYS, arena, false)
	_leaf("HUD的INHERIT孙子", Node.PROCESS_MODE_INHERIT, hud, false)
	# 反面教材：对局场景根写 ALWAYS（第一版的写法）
	var always_root := Node2D.new()
	always_root.name = "AlwaysRoot"
	add_child(always_root)
	always_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_leaf("ALWAYS根_入树后写PAUSABLE", Node.PROCESS_MODE_PAUSABLE, always_root, false)
	_leaf_before("ALWAYS根_先写PAUSABLE再入树", Node.PROCESS_MODE_PAUSABLE, always_root)
	# 棋子用的是 _physics_process，单独量一条
	_leaf("物理_根INHERIT下INHERIT", Node.PROCESS_MODE_INHERIT, arena, true)
	_leaf("物理_根INHERIT下ALWAYS", Node.PROCESS_MODE_ALWAYS, arena, true)

	await get_tree().create_timer(0.2).timeout      # 先确认起跑线都在跑
	_report("起跑（都没暂停）")
	get_tree().paused = true
	await get_tree().create_timer(0.4).timeout
	_report("暂停 0.4 秒后")
	get_tree().paused = false
	await get_tree().create_timer(0.4).timeout
	_report("恢复 0.4 秒后")
	get_tree().quit(0)
