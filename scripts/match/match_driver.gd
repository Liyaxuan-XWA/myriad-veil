class_name MatchDriver
extends Node
## 时停期间唯一还活着的帧驱动（2026-11-03 用户 B 案）。
##
## 为什么 `_process` 与棋盘点击要搬进这个空节点 —— 两条实测：
## · 给**对局场景根**写 PROCESS_MODE_ALWAYS（第一版的写法）时，pause 冻不住棋子：
##   窗口里点燃照跳、延迟伤害照落地（probe_match_freeze 第一版量到的就是这个）。
##   同一条写法在最小复现里却能冻住（tools/diag_pause_topology.tscn 的反面教材两支），
##   说明这条路的结局还取决于节点类型与入树路径 —— 不能依赖。
## · 场景根保持默认 INHERIT 时，整棵对局树被 pause 一把冻住，而**显式写 ALWAYS 的
##   分支照样逐帧跑**：实测暂停 0.4 秒里 INHERIT / PAUSABLE 叶子 = 0 帧，
##   ALWAYS 叶子与 HUD(ALWAYS) 的 INHERIT 孙子 = 25 帧。本节点走的就是第二条。
## 所以"要活的"只能待在**后面不挂战斗单位**的分支上：本节点是叶子，
## ALWAYS 传染不到任何棋子；HUD 那支下面本来就该全活（按钮要收输入）。

var arena: MatchArena


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if arena != null and is_instance_valid(arena):
		arena.tick(delta)


## 窗口里点棋盘选激活哪张：场景根暂停时收不到输入，点击必须从这个 ALWAYS 节点进来。
func _unhandled_input(event: InputEvent) -> void:
	if arena != null and is_instance_valid(arena):
		arena.on_unhandled_input(event)
