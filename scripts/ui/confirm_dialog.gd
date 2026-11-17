class_name ConfirmDialog
extends CanvasLayer
## 通用确认对话框 —— 用于所有「不可逆 / 高风险」操作的二次确认
##
## 典型场景：
##   - 原初位面按 ESC → 确认是否返回登录界面（返回前自动存档）
##   - 战斗中按 ESC → 确认是否放弃当前战斗返回原初位面
##
## 用法（一行调用）：
##   ConfirmDialog.ask("返回登录界面", "确定返回吗？", "返回登录", "取消", _on_confirmed)
##
## 设计要点：
##   1. 默认按钮是「取消」，且 ESC = 取消 —— 连按 ESC 不会误确认
##   2. 打开时暂停游戏（战斗中 BOSS 不会趁确认时偷袭），关闭时恢复原暂停状态
##   3. layer=110，高于 SystemPanel(101)，保证盖在任何系统面板之上
##   4. 一次性节点：关闭即 queue_free

signal confirmed
signal cancelled

var dlg_title: String = "确认"
var dlg_message: String = ""
var ok_text: String = "确定"
var cancel_text: String = "取消"
## 危险操作（返回登录界面 / 放弃战斗）用警示色，普通操作用常规色
var danger: bool = false

var _on_confirm: Callable
var _was_paused := false
var _root: PanelContainer
## 是否已登记进 GameState 的模态计数（open → true，关闭 / 被 free → false）
## ⚠ 确认框是 layer 110、任务面板 118 —— 不登记任务面板会盖在确认框上面
var _modal_counted := false


# ===================== 对外入口 =====================

## 弹出确认框；on_confirm 在玩家点「确定」时调用
static func ask(
	title: String,
	message: String,
	ok: String,
	cancel: String,
	on_confirm: Callable,
	is_danger: bool = false
) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	d.dlg_title = title
	d.dlg_message = message
	d.ok_text = ok
	d.cancel_text = cancel
	d.danger = is_danger
	d._on_confirm = on_confirm

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return d
	tree.root.add_child(d)
	d.open()
	return d


func _ready() -> void:
	# ALWAYS：暂停后仍能收到输入，否则连 ESC 都关不掉自己
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_root) or not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			# ESC 一律等同「取消」，防止连按误确认
			get_viewport().set_input_as_handled()
			_cancel()


# ===================== 生命周期 =====================

func open() -> void:
	_root.visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	if not _modal_counted:
		_modal_counted = true
		GameState.push_modal_ui(self)


func _close() -> void:
	get_tree().paused = _was_paused
	_mark_closed()
	queue_free()


## ⚠ 场景切换时确认框是被 free 的、不走 _close()，这里兜底返还计数
func _exit_tree() -> void:
	_mark_closed()


func _mark_closed() -> void:
	if not _modal_counted:
		return
	_modal_counted = false
	if is_instance_valid(GameState):
		GameState.pop_modal_ui(self)


func _confirm() -> void:
	confirmed.emit()
	if _on_confirm.is_valid():
		_on_confirm.call()
	_close()


func _cancel() -> void:
	cancelled.emit()
	_close()


# ===================== 构建 =====================

func _build() -> void:
	add_child(UIKit.dim_rect())

	_root = PanelContainer.new()
	var dialog_accent := UIKit.C_DANGER if danger else UIKit.C_ACCENT
	_root.add_theme_stylebox_override("panel",
		UIKit.accent_card_style(dialog_accent, 0.98, 0.56, 10))
	add_child(_root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UIKit.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_right", UIKit.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_root.add_child(margin)

	var vbox := UIKit.vbox(14)
	margin.add_child(vbox)

	var head := UIKit.hbox(9)
	head.add_child(UIKit.facility_disc(
		{"accent": UIKit.C_DANGER if danger else UIKit.C_ACCENT, "glyph": "问"}, 30))
	head.add_child(UIKit.label(dlg_title, UIKit.F_TITLE, Color(0.98, 0.94, 0.84)))
	head.add_child(UIKit.spacer())
	vbox.add_child(head)

	var msg := UIKit.readable_label(dlg_message, UIKit.F_BODY)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(360.0, 0.0)
	vbox.add_child(msg)

	var btn_row := UIKit.hbox(12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	# 先放「取消」再放「确定」：默认焦点落在取消上，回车不会误触发危险操作
	var cancel_btn := UIKit.button(cancel_text, Vector2(140, 36))
	cancel_btn.pressed.connect(_cancel)
	btn_row.add_child(cancel_btn)

	var ok_btn := UIKit.danger_button(ok_text, Vector2(140, 36)) if danger \
		else UIKit.primary_button(ok_text, Vector2(140, 36))
	ok_btn.pressed.connect(_confirm)
	btn_row.add_child(ok_btn)

	var hint := UIKit.readable_label("ESC = 取消", 10, UIKit.C_TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	call_deferred("_apply_size")


func _apply_size() -> void:
	var w := 460.0
	var h := _root.get_combined_minimum_size().y
	_root.position = Vector2((1280.0 - w) * 0.5, (720.0 - h) * 0.5)
	_root.size = Vector2(w, h)
