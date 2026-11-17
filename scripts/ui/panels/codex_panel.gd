class_name CodexPanel
extends SystemPanel
## 万界图鉴 —— 原初位面左上角「指引书」下方的独立入口。

var _view: CodexView


func _init() -> void:
	panel_title = "万界图鉴"
	panel_hint = "BOSS 卡集 · 未解锁仅名字与获取方式 · 卡包在「成就 → 成就收藏」· ESC 关闭"

func facility_visual() -> Dictionary:
	return UIKit.facility_style("codex")



func panel_size() -> Vector2:
	return Vector2(1000.0, 660.0)


func _build_content() -> void:
	# 图鉴自己管理右侧滚动，关掉 SystemPanel 外层滚动，避免嵌套
	var outer := content.get_parent() as ScrollContainer
	if outer != null:
		outer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_view = CodexView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_view)


func _refresh_content() -> void:
	if _view != null:
		_view.refresh()
