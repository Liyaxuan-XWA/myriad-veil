extends Node
## 只计数、不做事的探针脚本：挂到哪些节点上，就看它在暂停时跑了几帧 _process。

var ticks := 0


func _process(_delta: float) -> void:
	ticks += 1
