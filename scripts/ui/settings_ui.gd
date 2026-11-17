extends CanvasLayer
## 屏幕右上角「设置」入口 —— 常驻 autoload，主城与战斗场景都能点开
##
## 面板打开期间隐藏按钮，关闭后恢复，避免重复点击叠加面板。
## layer 90 低于 SystemPanel 的 101，保证面板盖在按钮之上。

var _btn: Button
var _panel: SystemPanel = null
## 常驻按钮是否允许显示（标题界面用自己的「设置」按钮时会临时关掉它）
var _entry_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_build()


func _build() -> void:
	_btn = UIKit.button("设置", Vector2(84, 32))
	# 贴右上角，而不是写死 x=1190：宽屏（20:9 逻辑视口 1600 宽）下写死坐标会让它
	# 浮在屏幕内侧、和同样靠右的战斗计时挤在同一行（2026-11-02 用户报计时被挡）。
	# 1280 基准下 -90 与原来的 1190 完全等价，战斗 HUD 的 TimeLabel 右边界留到 -104。
	_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_btn.position = Vector2(-90.0, 6.0)
	_btn.pressed.connect(_open_panel.bind(false))
	add_child(_btn)


func _open_panel(from_title: bool = false) -> void:
	if _panel:
		return
	var script = load("res://scripts/ui/settings_panel.gd")
	if script == null:
		return
	var p := script.new() as SystemPanel
	if p == null:
		return
	p.set("from_title", from_title)
	get_tree().root.add_child(p)
	p.closed.connect(_on_panel_closed)
	_panel = p
	_btn.visible = false
	p.open()


## 公开入口：供标题界面等外部调用（与点右上角按钮等价）
## from_title = true 时，设置里的退出按钮保持「退出游戏」，不会变成「返回登录界面」。
func open_panel(from_title: bool = false) -> void:
	_open_panel(from_title)


## 隐藏 / 恢复右上角常驻按钮（标题界面自带「设置」入口，避免重复）
## ⚠ 关闭面板时 _on_panel_closed 会按 _entry_enabled 恢复可见性，
##   否则标题界面开关一次设置后，常驻按钮会自己冒出来
func set_entry_visible(v: bool) -> void:
	_entry_enabled = v
	if _btn:
		_btn.visible = v


func _on_panel_closed() -> void:
	_panel = null
	if _btn:
		_btn.visible = _entry_enabled
