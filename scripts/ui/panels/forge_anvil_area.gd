extends Control
## 铁砧区：拖出砧上装备 / 接收背包或身上的装备（可交换）。
## 拖拽是非破坏性的：拖动时不改动任何数据，只有成功放下才真的移动。

var panel: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _get_drag_data(_at: Vector2) -> Variant:
	if panel == null:
		return null
	var data: Variant = panel._make_anvil_drag()
	if data == null:
		return null
	return data


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return panel != null and panel._can_drop_on_anvil(data)


func _drop_data(_at: Vector2, data: Variant) -> void:
	if panel != null and data is Dictionary:
		panel._on_forge_drop_on_anvil(data)

