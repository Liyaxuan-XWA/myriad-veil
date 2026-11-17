extends Node
## 关软件先弹「保存并退出」确认框（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 60000 res://tools/probe_quit_confirm.tscn -- --no-save
## ⚠ 全程带 --no-save：write_enabled 恒为 false，任何一次「保存并退出」都不会落到真实存档文件

var _passes := 0
var _fails: Array = []
var _quit_calls := 0
var _saved_auto_save := true
var _saved_tower: Dictionary = {}


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## headless 视口有 0.05 的 final transform，合成鼠标必须按 local 坐标投递
func _click(center: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = center
	m.global_position = center
	get_viewport().push_input(m, true)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = center
	d.global_position = center
	get_viewport().push_input(d, true)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = center
	u.global_position = center
	get_viewport().push_input(u, true)


func _press_esc() -> void:
	var p := InputEventKey.new()
	p.physical_keycode = KEY_ESCAPE
	p.pressed = true
	get_viewport().push_input(p, true)
	var r := InputEventKey.new()
	r.physical_keycode = KEY_ESCAPE
	r.pressed = false
	get_viewport().push_input(r, true)


func _dialog() -> ConfirmDialog:
	return GameState.get("_quit_dialog") as ConfirmDialog


func _dialog_count() -> int:
	var n := 0
	for c in get_tree().root.get_children():
		if c is ConfirmDialog:
			n += 1
	return n


## 确认框按钮：0=取消侧 1=确认侧（PanelContainer→Margin→VBox 的第 3 个子节点）
func _btn(d: ConfirmDialog, idx: int) -> Button:
	var panel: Control = d.get("_root")
	var vbox := panel.get_child(0).get_child(0)
	return vbox.get_child(2).get_child(idx) as Button


func _click_btn(d: ConfirmDialog, idx: int) -> void:
	_click((_btn(d, idx) as Control).get_global_rect().get_center())


func _reopen() -> ConfirmDialog:
	GameState.ask_quit()
	await _frames(3)
	return _dialog()


## 真实存档文件的内容摘要（md5 + 修改时间）：探针短暂放开过 auto_save_enabled，
## 收尾必须证明 5 个槽与备份一个字节都没被动过
func _slot_digests() -> Array:
	var out: Array = []
	for slot in [1, 2, 3, 4, 5]:
		for fname in ["save_slot_%d.json" % slot, "save_slot_%d.bak.json" % slot]:
			var path := "user://%s" % fname
			if not FileAccess.file_exists(path):
				out.append("%s:-" % fname)
			else:
				out.append("%s:%s@%d" % [fname,
					FileAccess.get_file_as_string(path).md5_text(),
					FileAccess.get_modified_time(path)])
	return out


func _ready() -> void:
	print("\n########## 退出确认框 ##########")
	_saved_auto_save = SaveManager.auto_save_enabled
	_saved_tower = CharacterData.tower_progress.duplicate(true)
	# 「结束进程」换成记录器：能验「点确认确实走了退出入口」而探针不会自杀
	GameState.quit_handler = func() -> void: _quit_calls += 1
	await _run()
	# ===== 收尾：还原被临时放开过的闸门与数据 =====
	GameState.quit_handler = Callable(GameState, "_quit_process")
	GameState.quit_requested = false
	GameState.quit_save_result = {}
	CharacterData.tower_progress = _saved_tower
	SaveManager.auto_save_enabled = _saved_auto_save
	get_tree().paused = false
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# 通知传播期间 root 正忙着挂子节点，那时 add_child 会被拒；先让探针完整进树
	await _frames(2)
	# 探针短暂放开过 auto_save_enabled：收尾再证明真实存档文件一个字节都没被动过
	var slots_before := _slot_digests()
	# ===== 1. 引擎闸门 + 三个入口都改到确认框 =====
	_check(not get_tree().auto_accept_quit,
		"auto_accept_quit=false：窗口 × 不再由引擎直接结束进程",
		str(get_tree().auto_accept_quit))
	var gs_src := FileAccess.get_file_as_string("res://scripts/systems/game_state.gd")
	# 只关 auto_accept_quit 不够：手机端 quit_on_go_back 仍会在通知送到之前先退
	_check(not get_tree().quit_on_go_back,
		"quit_on_go_back=false：安卓返回键不再直接结束进程", str(get_tree().quit_on_go_back))
	_check(gs_src.contains("set_quit_on_go_back(false)"), "两道退出闸门都关掉了", "")
	_check(gs_src.contains("NOTIFICATION_WM_GO_BACK_REQUEST")
			and gs_src.contains("NOTIFICATION_WM_CLOSE_REQUEST"),
		"× 与返回键两个通知都接进同一入口")
	_check(gs_src.contains("var quit_handler: Callable = _quit_process")
			and gs_src.contains("func _quit_process() -> void:")
			and gs_src.contains("\tget_tree().quit()"),
		"默认退出入口 = _quit_process → get_tree().quit()")
	var ts_src := FileAccess.get_file_as_string("res://scripts/ui/title_screen.gd")
	_check(ts_src.contains("GameState.ask_quit()") and not ts_src.contains("get_tree().quit()"),
		"标题界面「退出」走确认框，不再直接退进程")
	var sp_src := FileAccess.get_file_as_string("res://scripts/ui/settings_panel.gd")
	_check(sp_src.contains("GameState.ask_quit()") and not sp_src.contains("get_tree().quit()"),
		"标题界面的设置「退出」同样走确认框")

	# ===== 2. quit_plan 五档文案（纯函数，不用真的切场景）=====
	var p0: Dictionary = GameState.quit_plan(false, false, false, false)
	_check(String(p0["ok"]) == "退出" and String(p0["cancel"]) == "取消"
			and String(p0["msg"]).contains("不在游戏内") and not bool(p0["danger"]),
		"标题界面：退出 / 取消，不承诺保存", str(p0))
	var p1: Dictionary = GameState.quit_plan(true, false, true, true)
	_check(String(p1["ok"]) == "保存并退出" and String(p1["cancel"]) == "继续游戏"
			and String(p1["msg"]).contains("自动存档槽")
			and String(p1["msg"]).contains("1–4 轮转") and bool(p1["danger"]),
		"游戏内有进度：按钮「保存并退出」并写明存档槽", str(p1))
	var p2: Dictionary = GameState.quit_plan(true, false, true, false)
	_check(String(p2["ok"]) == "退出" and String(p2["msg"]).contains("还没有可保存的进度")
			and not bool(p2["danger"]),
		"新开空白局：不许写成「会保存」", str(p2))
	var p3: Dictionary = GameState.quit_plan(true, true, false, false)
	_check(String(p3["cancel"]) == "继续挑战" and String(p3["msg"]).contains("试炼之路")
			and bool(p3["danger"]),
		"试炼之路：明说本局不写存档", str(p3))
	var p4: Dictionary = GameState.quit_plan(true, false, false, false)
	_check(String(p4["msg"]).contains("不写入存档") and String(p4["cancel"]) == "继续游戏"
			and bool(p4["danger"]),
		"写盘被关（--no-save）：说「不写入」而不是「没进度」", str(p4))
	# 试炼优先：即便「有进度」也不许按钮写「保存」
	var p5: Dictionary = GameState.quit_plan(true, true, true, true)
	_check(String(p5["ok"]) == "退出" and not String(p5["ok"]).contains("保存"),
		"试炼局里按钮不写「保存」", str(p5))

	# ===== 3. 窗口 × → 弹框 =====
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames(4)
	var d: ConfirmDialog = _dialog()
	# 「弹出来了」= 节点进了树并且真的建好了内部控件；只查引用非空会被
	# 「add_child 失败但对象还在」骗过去（M4 变异就是这么露馅的）
	var panel: Control = null if d == null else d.get("_root")
	_check(d != null and is_instance_valid(d) and panel != null and panel.visible,
		"窗口 × 后确实弹出可用的确认框",
		"d=%s panel=%s" % [d, panel])
	if d == null:
		return
	_check(d.dlg_title == "退出游戏", "标题为「退出游戏」", d.dlg_title)
	_check(d.dlg_message.contains("不写入存档"), "本场景文案走「写盘被关」那档", d.dlg_message)
	_check(d.ok_text == "退出" and d.cancel_text == "继续游戏",
		"按钮：退出 / 继续游戏", "%s / %s" % [d.ok_text, d.cancel_text])
	_check(d.danger, "写盘被关时按危险色", str(d.danger))
	_check(d.layer == 110, "压在系统面板之上（layer 110）", str(d.layer))
	_check(get_tree().paused, "确认期间游戏暂停", str(get_tree().paused))
	_check(is_instance_valid(_btn(d, 0)) and is_instance_valid(_btn(d, 1)), "两个按钮都构建出来了")

	# ===== 4. 连点窗口 ×：只有一层框 =====
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames(3)
	_check(_dialog_count() == 1, "连点窗口 × 不叠第二层确认框", str(_dialog_count()))

	# ===== 5. ESC = 取消：既不存档也不退出 =====
	_press_esc()
	await _frames(6)
	_check(_dialog() == null, "ESC 关掉确认框")
	_check(not GameState.quit_requested and _quit_calls == 0,
		"ESC 不触发保存与退出", "quit_requested=%s calls=%d" % [GameState.quit_requested, _quit_calls])
	_check(not get_tree().paused, "取消后恢复原来的暂停状态", str(get_tree().paused))

	# ===== 6. 点「继续游戏」：同样不存档不退出 =====
	d = await _reopen()
	if d == null:
		return
	await _frames(3)
	_click_btn(d, 0)
	await _frames(6)
	_check(_dialog() == null, "点「继续游戏」关闭确认框")
	_check(not GameState.quit_requested and _quit_calls == 0,
		"取消不存档也不退出", "quit_requested=%s calls=%d" % [GameState.quit_requested, _quit_calls])

	# ===== 7. 有进度 → 按钮变「保存并退出」，点它先落盘再退出 =====
	# writable 只看 auto_save_enabled，所以这一步不用放开 write_enabled：
	# auto_save 自己会被 write_enabled 拦住，一个字节都不会落盘
	CharacterData.tower_progress = {1: {"unlocked": true, "first_kill": true, "clear_count": 1}}
	SaveManager.auto_save_enabled = true
	d = await _reopen()
	if d == null:
		return
	await _frames(3)
	var ok_btn: Button = _btn(d, 1)
	_check(ok_btn != null and ok_btn.text == "保存并退出",
		"有进度时确认按钮变「保存并退出」", ok_btn.text if ok_btn != null else "<nil>")
	_check(d.dlg_message.contains("自动存档槽"), "有进度时文案改为会写存档槽", d.dlg_message)
	GameState.quit_requested = false
	if ok_btn != null:
		_click_btn(d, 1)
	await _frames(6)
	_check(_quit_calls == 1, "点确认走了退出入口", str(_quit_calls))
	_check(GameState.quit_requested, "quit_requested 置真")
	_check(GameState.quit_save_result.get("attempted") == true
			and int(GameState.quit_save_result.get("slot", -2)) == -1,
		"退出前真的调了 auto_save（write 关着 → slot=-1、不落盘）", str(GameState.quit_save_result))
	_check(not SaveManager.write_enabled, "收回写盘闸门", str(SaveManager.write_enabled))
	_check(_dialog() == null, "确认后确认框关闭")

	# ===== 8. 回到初始数据：按钮退回「退出 / 继续游戏」，退出时仍不落盘 =====
	CharacterData.tower_progress = _saved_tower
	GameState.quit_requested = false
	_quit_calls = 0
	d = await _reopen()
	if d == null:
		return
	_check(String(_btn(d, 1).text) == "退出" and _btn(d, 0).text == "继续游戏",
		"没进度时按钮回到「退出 / 继续游戏」", "%s / %s" % [_btn(d, 1).text, _btn(d, 0).text])
	# auto_save_enabled 还开着（收尾统一还原），write_enabled 关着 → 一定不写盘
	var r := GameState.save_before_quit()
	_check(r.get("attempted") == true and int(r.get("slot", -2)) == -1,
		"退出前调了 auto_save，slot=-1 表示这次没落盘", str(r))
	_check(not SaveManager.write_enabled, "本探针全程没放开过写盘", str(SaveManager.write_enabled))
	_click_btn(d, 1)
	await _frames(6)
	_check(_quit_calls == 1, "空档点确认同样走退出入口", str(_quit_calls))

	# ===== 9. 安卓返回键同样弹框，取消后不留残框 =====
	_quit_calls = 0
	GameState.quit_requested = false
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(4)
	var d2: ConfirmDialog = _dialog()
	_check(d2 != null and is_instance_valid(d2), "安卓返回键同样弹确认框")
	if d2 != null:
		_click_btn(d2, 0)
		await _frames(6)
	_check(_dialog_count() == 0 and _quit_calls == 0,
		"返回键取消后无残框、未退出", "count=%d calls=%d" % [_dialog_count(), _quit_calls])

	# ===== 10. 试炼之路里走的是另一套文案（RogueRun.active，不是存档闸门）=====
	RogueRun.active = true
	d = await _reopen()
	if d != null:
		_check(d.cancel_text == "继续挑战" and d.dlg_message.contains("试炼之路")
				and d.ok_text == "退出" and d.danger,
			"试炼局里：退出 / 继续挑战，明说本局不写存档",
			"%s / %s / %s" % [d.ok_text, d.cancel_text, d.dlg_message])
		_click_btn(d, 0)
		await _frames(6)
	else:
		_check(false, "试炼局里弹出了确认框", "d=null")
	RogueRun.active = false

	# ===== 11. 收尾硬保证：真实存档文件一个字节都没被动过 =====
	# Array 的 == 是引用比较，拼成字符串再比值
	await _frames(3)
	var slots_after := _slot_digests()
	_check(";".join(slots_after) == ";".join(slots_before),
		"全程没有任何一次落盘（5 个槽 + 备份内容摘要不变）",
		"前=%s\n后=%s" % [";".join(slots_before), ";".join(slots_after)])
