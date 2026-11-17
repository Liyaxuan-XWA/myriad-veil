class_name AchievementPanel
extends SystemPanel
## 成就 —— 原初位面左上角「指引书 / 图鉴」下方的第三个入口。
## 2026-10-30 用户定：卡包从图鉴迁入「成就 → 成就收藏」；
## 成就任务页登记卡面获取条件（普通 / 华彩有背景 / 纯华彩无背景）。

var _view: AchievementView


func _init() -> void:
	panel_title = "成就"
	panel_hint = "成就任务 · 成就收藏（卡包）· ESC 返回"


func facility_visual() -> Dictionary:
	return UIKit.facility_style("achievement")


func panel_size() -> Vector2:
	return Vector2(1000.0, 660.0)


func _build_content() -> void:
	# 视图自己管右侧滚动，关掉外层滚动避免嵌套
	var outer := content.get_parent() as ScrollContainer
	if outer != null:
		outer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_view = AchievementView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_view)


func _refresh_content() -> void:
	if _view != null:
		_view.refresh()


## 拖过卡序才补一次自动存档（不拖不写，避免空耗轮转槽）
func close() -> void:
	if _view != null and is_instance_valid(_view) and _view.take_order_dirty():
		SaveManager.auto_save()
	super.close()


## ESC 先在卡包内部退一层（单卡 → 展开 → 格子），退到最外层才关面板
func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		if _view != null and _view.back():
			get_viewport().set_input_as_handled()
			return
	super._input(event)
