extends Node
## 教学喂招暂停时，手游的虚拟键必须还能按（2026-11-13 用户报：指引喊「按右键弹开」，
## 手游点「弹」没反应，卡死在那一步，游戏进行不下去）
## 用法：godot --headless --path . --quit-after 200000 res://tools/probe_tut_parry_touch.tscn -- --no-save
##
## ⚠ 只改运行时 VirtualPad.enabled，不碰 set_enabled（那个会写 user://touch_ui.json，
##   会把玩家自己调过的键位配置顺带改成「触屏已开」）。

var _passes := 0
var _fails: Array = []
var _pad_was_enabled := false
var _btn_down := 0
var _btn_press := 0
var _btn: Button = null
var _spy: Node = null
var _spy_parry := 0
var _parry_ev := 0
var _parry_poll := 0
var _vp := Vector2(1280, 720)


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


## 本探针自己就是那个 ALWAYS 哨兵：判据与 tutorial_overlay 完全一致
## （overlay 在 _input 里写的是 `event.is_action_pressed("parry")`），
## 所以这里收到几次，overlay 就能收到几次。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("parry"):
		_spy_parry += 1
		_parry_ev += 1


## 轮询型读法（player 就是这一路）：暂停态里也要看得见按下沿
func _process(_d: float) -> void:
	if Input.is_action_just_pressed("parry"):
		_parry_poll += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 教学暂停里的虚拟键 ##########")
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("PROBE TIMEOUT")
		get_tree().quit(2))
	_vp = get_viewport().get_visible_rect().size
	_btn = Button.new()
	_btn.text = "我在摇杆圈底下"
	_btn.size = Vector2(120, 50)
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.add_child(_btn)
	add_child(layer)
	_btn.button_down.connect(func() -> void: _btn_down += 1)
	# 判据用 pressed（= 真的按成功了）：button_down 只到「按下」，
	# 摇杆把后续那发合成鼠标 release 吞掉时 button_down 照样是 1，看不出问题
	_btn.pressed.connect(func() -> void: _btn_press += 1)
	_pad_was_enabled = bool(VirtualPad.is_touch_enabled())
	await _run()
	# ===== 收尾：只改运行时，原样装回 =====
	get_tree().paused = false
	VirtualPad.set("enabled", _pad_was_enabled)
	VirtualPad.set("_has_touchscreen", false)
	VirtualPad.call("_apply_enabled")
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _center(id: String) -> Vector2:
	var b: Control = (VirtualPad.get("_buttons") as Dictionary).get(id)
	return b.position + Vector2(b.radius, b.radius)


func _mouse(pressed: bool, pos: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pos
	get_viewport().push_input(mb, true)


func _touch(pressed: bool, pos: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	get_viewport().push_input(t, true)


## 按下（真机序：鼠标 press 先到，触摸 press 后到），不抬手
func _press(pos: Vector2) -> void:
	_mouse(true, pos)
	_touch(true, pos)


## 抬手 + 让收尾跑完
func _release(pos: Vector2) -> void:
	_mouse(false, pos)
	_touch(false, pos)
	for i in range(3):
		await get_tree().process_frame


## 一按一抬（hold 拍中间不读数）
func _tap(pos: Vector2, hold: int) -> void:
	_press(pos)
	for i in range(hold):
		await get_tree().process_frame
	await _release(pos)


func _run() -> void:
	await _frames(3)
	# ===== 0. 开机顺序：VirtualPad 必须比 Tutorial 先 ready =====
	# 指引的暂停框在 _build 时就按触屏状态写好文案，顺序反了它就永远读到「没触屏」
	var names: Array = ProjectSettings.get_property_list().map(
		func(k): return String(k["name"]) if String(k["name"]).begins_with("autoload/") else "")
	var vp_idx := names.find("autoload/VirtualPad")
	var tut_idx := names.find("autoload/Tutorial")
	_check(vp_idx >= 0 and tut_idx >= 0 and vp_idx < tut_idx,
		"VirtualPad 比 Tutorial 先注册（暂停框文案才读得到触屏状态）",
		"pad=%d tutorial=%d" % [vp_idx, tut_idx])

	# ===== 1. 把探针装成「触屏 + 战斗布局」=====
	VirtualPad.set("_has_touchscreen", true)
	VirtualPad.set("enabled", true)
	VirtualPad.call("_apply_enabled")
	VirtualPad.set_context("combat")
	await _frames(4)
	_check(VirtualPad.is_touch_enabled(), "触屏按键已开")
	_check(VirtualPad.get("_root").visible, "虚拟键层可见")

	# ===== 2. PC 基线：没暂停时点「弹」，动作按得下去 =====
	get_tree().paused = false
	_spy_parry = 0
	Input.action_release("parry")
	await _tap(_center("c_parry"), 2)
	_check(_spy_parry >= 1, "未暂停时点虚拟「弹」→ parry 动作按下被收到", str(_spy_parry))
	_check(not Input.is_action_pressed("parry"), "抬手后 parry 释放（不会一直挂着）")

	# ===== 3. 核心：教学喂招那种「整棵树暂停」里点「弹」 =====
	get_tree().paused = true
	await _frames(2)
	_spy_parry = 0
	Input.action_release("parry")
	await _tap(_center("c_parry"), 2)
	_check(_spy_parry >= 1,
		"暂停态（教学喂招）点虚拟「弹」→ parry 照样按得下去", str(_spy_parry))
	_check(_parry_poll >= 1,
		"暂停态里轮询型读法也看得到按下沿（player 那一路）", str(_parry_poll))
	_check(not Input.is_action_pressed("parry"), "暂停态抬手也释放 parry")

	# ===== 4. 同一根因的另外两颗键：攻 / 闪 =====
	_parry_ev = 0
	_parry_poll = 0
	Input.action_release("attack")
	_press(_center("c_attack"))
	await _frames(2)
	_check(Input.is_action_pressed("attack") and _parry_ev == 0,
		"暂停态点住「攻」不放 → attack 动作是按下态（且不冒充 parry）",
		"attack=%s parry事件=%d" % [Input.is_action_pressed("attack"), _parry_ev])
	await _release(_center("c_attack"))
	_check(not Input.is_action_pressed("attack"), "暂停态抬手即释放攻键")
	_parry_ev = 0
	Input.action_release("dodge")
	_press(_center("c_dodge"))
	await _frames(2)
	_check(Input.is_action_pressed("dodge") and _parry_ev == 0,
		"暂停态点住「闪」也生效（且不冒充 parry）",
		"dodge=%s parry事件=%d" % [Input.is_action_pressed("dodge"), _parry_ev])
	await _release(_center("c_dodge"))

	# ===== 5. 暂停态里摇杆不认领：摇杆圈底下的 UI 按钮仍要能点 =====
	# （2026-10-22「踏入」按钮那条修复不能因为这次改动翻回去）
	_btn.position = _stick_center() - Vector2(60, 25)
	await _frames(2)
	_btn_down = 0
	_btn_press = 0
	Input.action_release("move_right")
	await _tap(_stick_center(), 2)
	_check(_btn_press == 1,
		"暂停态在摇杆圈里按下 → 底下的按钮真的按成功（摇杆不认领、不吞 release）",
		"down=%d pressed=%d" % [_btn_down, _btn_press])
	_check(not Input.is_action_pressed("move_right"),
		"暂停态摇杆不产生移动量", str(Input.get_action_strength("move_right")))

	# ===== 6. 对照：不暂停时同一个位置，摇杆要认领、按钮要让位 =====
	get_tree().paused = false
	await _frames(2)
	_btn_down = 0
	_btn_press = 0
	await _tap(_stick_center(), 2)
	_check(_btn_down == 0 and _btn_press == 0,
		"未暂停时摇杆认领这一按（底下的按钮不被误点）", str(_btn_down))
	_check(_stick_center().distance_to(_stick_home()) <= 2.0,
		"抬手后摇杆回默认位", str(_stick_center()))

	# ===== 7. 文案：触屏不再说「右键 / ESC」=====
	var ov = Tutorial.get("_overlay")
	if ov != null and is_instance_valid(ov):
		Tutorial.active_step = {"id": "probe_step", "text": "它抬手就按右键弹刀",
				"text_touch": "它抬手就点右下的「弹」键弹刀", "ev": "", "n": 0}
		ov.call("_refresh_card")
		await _frames(2)
		var shown := String(ov.get("_card_label").text)
		_check(shown == "它抬手就点右下的「弹」键弹刀",
			"触屏读 text_touch，PC 读 text", shown)
		Tutorial.active_step = {}
	else:
		_check(false, "指引浮层已随 Tutorial 建好", "拿不到 _overlay")
	var ca := FileAccess.get_file_as_string("res://scripts/combat/combat_arena.gd")
	_check(ca.contains("func _tut_parry_prompt()")
			and ca.contains("Tutorial.pause_prompt(_tut_parry_prompt())"),
		"喂招提示改走设备分支，不再硬写「按右键」")
	var tov := FileAccess.get_file_as_string("res://scripts/tutorial/tutorial_overlay.gd")
	_check(tov.contains("点「弹」键弹刀") and tov.contains("点「返回」跳过此步"),
		"暂停框底句在触屏说「弹 / 返回」而不是「右键 / ESC」")
	var tdb := FileAccess.get_file_as_string("res://scripts/data/tutorial_db.gd")
	_check(tdb.contains("\"text_touch\""), "教程数据里有触屏版文案")


func _stick_center() -> Vector2:
	var s: Control = VirtualPad.get("_stick")
	return s.position + s.size * 0.5


func _stick_home() -> Vector2:
	return Vector2(_vp.x * 0.135, _vp.y * 0.720)
