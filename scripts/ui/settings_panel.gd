class_name SettingsPanel
extends SystemPanel
## 设置界面：存档管理 + 返回登录界面 / 标题界面退出
##
## 槽位规则：
##   - 第 1–4 槽：自动存档，每次回到主城轮流覆盖
##   - 第 5 槽：手动存档槽，仅手动存档才覆盖
##
## 游戏内打开时，退出按钮 = 先自动存档再返回登录界面；标题界面打开时保持真正退出游戏。

## SettingsUI 在标题界面打开时置 true（按钮恢复为「退出游戏」）
var from_title := false
var _slot_box: VBoxContainer
## 触屏开关按钮（文案随状态变，_refresh_content 里更新）
var _touch_toggle: Button
var _exit_btn: Button
## 弃局返回（只在棋局场景里存在，所以可能为 null）
var _abandon_btn: Button


func _init() -> void:
	panel_title = "设置"
	panel_hint = "ESC 关闭"


func panel_size() -> Vector2:
	return Vector2(880.0, 660.0)


func _build_content() -> void:
	content.add_child(UIKit.note_card(
		"第 1–4 槽为自动存档：每次回到主城时轮流覆盖，保留最近四次回城的状态。\n"
		+ "第 5 槽为手动存档槽：只有点击「手动存档」才会覆盖。", UIKit.C_ACCENT))
	content.add_child(UIKit.section("存档槽", UIKit.C_ACCENT))
	_slot_box = UIKit.vbox(6)
	content.add_child(_slot_box)

	var manual_btn := UIKit.primary_button("手动存档（覆盖第 5 槽）", Vector2(280, 40))
	manual_btn.pressed.connect(_on_manual_save)
	manual_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(manual_btn)

	content.add_child(UIKit.section("触屏按键（安卓）", UIKit.C_ACCENT))
	_touch_toggle = UIKit.button("", Vector2(260, 38))
	_touch_toggle.pressed.connect(_on_toggle_touch)
	_touch_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(_touch_toggle)

	# 调整 / 重置并成一行：少占一行高度，触屏设置一屏就能看全
	var touch_row := UIKit.hbox(8)
	content.add_child(touch_row)
	var edit_combat := UIKit.button("调整战斗按键", Vector2(160, 36))
	edit_combat.pressed.connect(_on_edit_touch.bind("combat"))
	touch_row.add_child(edit_combat)
	var edit_realm := UIKit.button("调整主城按键", Vector2(160, 36))
	edit_realm.pressed.connect(_on_edit_touch.bind("realm"))
	touch_row.add_child(edit_realm)
	var reset_combat := UIKit.button("重置战斗布局", Vector2(160, 36))
	reset_combat.pressed.connect(_on_reset_touch.bind("combat"))
	touch_row.add_child(reset_combat)
	var reset_realm := UIKit.button("重置主城布局", Vector2(160, 36))
	reset_realm.pressed.connect(_on_reset_touch.bind("realm"))
	touch_row.add_child(reset_realm)

	content.add_child(UIKit.note_card(
		"触屏按键只在手机 / 平板上显示，电脑上完全不影响键鼠操作。\n"
		+ "点「调整按键」会关掉本界面并进入拖动模式：把按键拖到顺手的位置，点右上角「完成」保存。\n"
		+ "主城的「背包 / 功法库」是右上角的固定图标，不在这套可拖动按键里。", UIKit.C_ACCENT))

	content.add_child(UIKit.section("系统", UIKit.C_ACCENT))
	# 弃局返回：只在棋局场景出现（#58，用户定）。
	# 战斗 / 大世界不加这条 —— 它们有自己的退出规则，加了等于给 BOSS 战开一个无代价逃跑键，
	# 塔层与赤霄界三强就能被"打不过先回去换件装备再来"白嫖。
	if _in_match():
		_abandon_btn = UIKit.button("返回原初位面（本局作废）", Vector2(300, 38))
		_abandon_btn.pressed.connect(_on_abandon_pressed)
		_abandon_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		content.add_child(_abandon_btn)
	_exit_btn = UIKit.danger_button(
		"退出游戏（先自动存档）" if from_title else "返回登录界面（先自动存档）",
		Vector2(300, 40))
	_exit_btn.pressed.connect(_on_exit_pressed)
	_exit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(_exit_btn)


func _refresh_content() -> void:
	UIKit.clear_children(_slot_box)
	for i in range(1, SaveManager.SLOT_COUNT + 1):
		_slot_box.add_child(_make_slot_row(i))
	if _touch_toggle != null:
		_touch_toggle.text = "触屏按键：%s" % ("已开启" if VirtualPad.is_touch_enabled() else "已关闭")


func _make_slot_row(slot: int) -> Control:
	var info := SaveManager.get_slot_info(slot)

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.accent_card_style(
		UIKit.C_ACCENT if bool(info.get("exists", false)) else UIKit.C_SLOT_BORDER,
		0.62 if bool(info.get("exists", false)) else 0.40,
		0.26 if bool(info.get("exists", false)) else 0.12, 6))
	var hbox := UIKit.hbox(10)
	row.add_child(hbox)

	hbox.add_child(UIKit.label(SaveManager.slot_display_name(slot), UIKit.F_BODY, UIKit.C_ACCENT))

	var info_col := UIKit.vbox(2)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_col)

	if not bool(info.get("exists", false)):
		info_col.add_child(UIKit.label("空", UIKit.F_SMALL, UIKit.C_DISABLE))
	else:
		var summary := "%s　%s" % [String(info.get("realm", "?")), String(info.get("time_text", "—"))]
		info_col.add_child(UIKit.label(summary, UIKit.F_SMALL, UIKit.C_TEXT_DIM))

	hbox.add_child(UIKit.spacer())

	if bool(info.get("exists", false)):
		var load_btn := UIKit.button("读取", Vector2(80, 32))
		load_btn.pressed.connect(_on_load.bind(slot))
		hbox.add_child(load_btn)
		var del_btn := UIKit.danger_button("删除", Vector2(80, 32))
		del_btn.pressed.connect(_on_delete.bind(slot))
		hbox.add_child(del_btn)
	else:
		hbox.add_child(UIKit.label("—", UIKit.F_SMALL, UIKit.C_DISABLE))

	# 备份恢复入口：每次覆盖前都会留一份上一版，槽位被空档冲掉时可以用它回滚
	if bool(info.get("backup_exists", false)):
		var bak_btn := UIKit.paper_button("恢复备份", Vector2(100, 32))
		bak_btn.tooltip_text = "读取本槽上次被覆盖前的内容（只保留上一版）"
		bak_btn.pressed.connect(_on_restore_backup.bind(slot))
		hbox.add_child(bak_btn)
	return row


# ===================== 交互 =====================

func _on_manual_save() -> void:
	if SaveManager.manual_save():
		set_status("已手动存档到第 5 槽（%s）" % SaveManager.get_slot_info(SaveManager.MANUAL_SLOT).get("time_text", ""))
	else:
		set_status("手动存档失败", UIKit.C_DANGER)
	_refresh_content()


func _on_load(slot: int) -> void:
	if SaveManager.load_slot(slot):
		set_status("已读取第 %d 槽（%s）" % [slot, SaveManager.slot_display_name(slot)])
	else:
		set_status("读取失败：第 %d 槽无有效存档" % slot, UIKit.C_DANGER)
	_refresh_content()


func _on_toggle_touch() -> void:
	VirtualPad.set_enabled(not VirtualPad.is_touch_enabled())
	_refresh_content()
	set_status("触屏按键已%s" % ("开启" if VirtualPad.is_touch_enabled() else "关闭"), UIKit.C_OK)


## 进入布局编辑：**先关面板**，否则面板占着半屏没法拖
func _on_edit_touch(ctx: String) -> void:
	VirtualPad.enter_edit_mode(ctx)
	close()


func _on_reset_touch(ctx: String) -> void:
	VirtualPad.reset_layout(ctx)
	set_status("已重置%s按键布局" % ("战斗" if ctx == "combat" else "主城"), UIKit.C_OK)


func _on_delete(slot: int) -> void:
	SaveManager.delete_slot(slot)
	set_status("已删除第 %d 槽存档" % slot, UIKit.C_WARN)
	_refresh_content()


## 从上一版备份恢复：直接读回游戏内数据（不需要先重启）
func _on_restore_backup(slot: int) -> void:
	if SaveManager.restore_backup(slot):
		set_status("已从备份恢复第 %d 槽" % slot, UIKit.C_OK)
	else:
		set_status("第 %d 槽没有可用备份" % slot, UIKit.C_DANGER)
	_refresh_content()


func _on_exit_pressed() -> void:
	if from_title:
		# 标题界面的「退出」= 结束程序，和窗口 × 共用确认框入口
		GameState.ask_quit()
		return
	# 游戏内：先关闭面板恢复暂停状态，再由统一入口存档并切回登录界面
	close()
	GameState.return_to_title()


## 当前是不是站在棋局里。用类判断而不是场景路径字符串，
## 以后棋局换场景文件时这里不会跟着漏。
func _in_match() -> bool:
	var cs := get_tree().current_scene
	return cs != null and (cs is MatchArena or String(cs.name) == "MatchArena")


func _on_abandon_pressed() -> void:
	# ⚠ 这里**不能**先 close()：SystemPanel.close() 会把自己 queue_free，
	#   而确认回调 `_on_abandon_confirmed` 正是绑在这个面板实例上的 —— 面板先没了，
	#   回调就跟着失效，玩家点「弃局返回」什么都不发生（上一版实测就是这样）。
	#   确认框 layer=110 本来就盖在 SystemPanel(101) 之上，不需要提前让位。
	ConfirmDialog.ask(
		"返回原初位面",
		"这局棋会直接作废：关卡不算通过，但也不扣任何东西，随时能再进来重打。\n确定现在返回吗？",
		"弃局返回", "继续对局",
		_on_abandon_confirmed
	)


func _on_abandon_confirmed() -> void:
	# ⚠ 不能在这里直接收尾。`ConfirmDialog._confirm()` 是「先回调、后 `_close()`」，
	#   而 `_close()` 把 paused 恢复成**开框时**记下的值 —— 那一刻设置面板正开着，记的是 true。
	#   就地 close() 取消的暂停会被它盖回去，切到主城时树是冻住的。
	#   （战斗 ESC 那条没暴露这个，因为那里没有系统面板先开，记的是 false。）
	#   推迟一帧就落在 `_close()` 之后，收尾顺序才和玩家看到的一致。
	_leave_after_dialog.call_deferred()


func _leave_after_dialog() -> void:
	# 先抓住棋局再关面板：close() 末尾会 queue_free 自己
	var cs := get_tree().current_scene
	close()
	if cs != null and cs.has_method("abandon_match"):
		cs.call("abandon_match")
