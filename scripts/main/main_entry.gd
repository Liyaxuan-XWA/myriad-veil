extends Node2D
## main.tscn 的启动重定向入口（别名场景）
##
## 历史原因：main.tscn 曾是阶段1的启动场景，内容只有一个 combat_arena 实例。
## 现启动流程已改为「开始界面」：project.godot run/main_scene = title_screen.tscn。
## 但编辑器 F6「运行当前场景」跑的是标签页里的场景、与 main_scene 无关，
## 标签页停在 main.tscn 时会直接进战斗。故把本场景降级为「别名入口」：
##
##   F5（任意标签页）              → 开始界面 →（点开始/继续）→ 原初位面
##   F6 停在 main.tscn             → 重定向到开始界面
##   F6 停在 combat_arena.tscn     → 直接进战斗（保留单独调试战斗的能力）
##   原初位面点「演武场」          → combat_arena.tscn
##
## 注意：演武场入口已改为直连 combat_arena.tscn，不再经过本场景，
## 因此不存在「main → 开始界面 → 原初位面 → 演武场 → main」的循环。

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"


func _ready() -> void:
	# _ready 阶段当前场景尚未完全挂进树，换场景需延后一帧
	_goto_title.call_deferred()


func _goto_title() -> void:
	# 注意：本句执行后当前节点即被释放，其后的任何代码（含 await）都不会运行
	get_tree().change_scene_to_file(TITLE_SCENE)
