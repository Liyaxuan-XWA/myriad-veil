extends Node
## 只数 _physics_process 帧数的探针脚本（棋子用的就是这条回路）。

var ticks := 0


func _physics_process(_delta: float) -> void:
	ticks += 1
