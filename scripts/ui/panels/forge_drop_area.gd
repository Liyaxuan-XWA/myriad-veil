extends Control
## 背包投放区：把身上装备拖来卸下、把砧上装备拖回背包。
## 只负责命中与回调，视觉由面板自己画。

var panel: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return panel != null and panel._can_drop_on_bag(data)


func _drop_data(_at: Vector2, data: Variant) -> void:
	if panel != null and data is Dictionary:
		panel._on_forge_drop_to_bag(data)
