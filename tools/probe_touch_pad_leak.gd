extends Node
## 手游触控误触自检（2026-11-13 用户报「原初界面推摇杆经常误触设施」）
## 用法：godot --headless --path . --quit-after 200000 res://tools/probe_touch_pad_leak.tscn -- --no-save
##
## ⚠ 事件序是**照真机实测复刻**的（tools/probe_touch_mouse_emu.gd 量到）：
##   鼠标 press → 触摸 press → (鼠标 motion + ScreenDrag) ×N → 鼠标 release → 触摸 release。
##   headless 下引擎自己合成的鼠标事件坐标是坏的（窗口尺寸 0），所以这里由探针
##   自己按真机语义注入正确坐标的鼠标事件，触摸事件照旧注入 —— 测的是本项目的闸门，
##   不是引擎的合成算法。真机仍需跑一遍复核。
##
## ⚠ 本探针直接改 VirtualPad.enabled / _has_touchscreen，**不调 set_enabled**，
##   免得把 user://touch_ui.json 写成「触屏已开」，害用户下次开 PC 版满屏虚拟键。

var _passes := 0
var _fails: Array = []
var _hits := 0            # 设施被激活次数
var _fac: Area2D = null
var _cam: Camera2D = null
var _ui_btn: Button = null    # 埋在摇杆区底下的普通按钮
var _ui_down := 0
var _ui_press := 0
## 合成 MouseMotion 要不要带「左键按住」的 mask（悬停测试要留 false）
## 跑之前的触屏开关：PC 基线要先把触屏关干净，收尾原样装回去
var _pad_was_enabled := false
var _hover_pressed := false
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


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 手游触控误触 ##########")
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("PROBE TIMEOUT")
		get_tree().quit(2))
	_setup_world()
	await _run()
	_teardown()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _setup_world() -> void:
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	_vp = get_viewport().get_visible_rect().size
	if _vp.x < 100.0:
		_vp = Vector2(1280, 720)
	# 用真的 Facility 脚本：触屏守卫就在它里面
	_fac = (load("res://scripts/main/facility.gd") as GDScript).new()
	_fac.facility_id = "arena"
	_fac.facility_name = "演武场"
	add_child(_fac)
	var sh := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120, 80)   # 与主城设施同尺寸
	sh.shape = rect
	_fac.add_child(sh)
	# Facility 的 @onready 指向 $NameLabel：不给它就会刷一串「Node not found」
	var nl := Label.new()
	nl.name = "NameLabel"
	_fac.add_child(nl)
	_fac.activated.connect(func(_id: String) -> void: _hits += 1)
	_setup_ui_trap()


## 摇杆区底下埋一颗普通 Button：L1（合成鼠标闸门）单独就靠它验
## —— 设施那条路 L2 也会挡，分不清是谁起的作用；按钮只吃鼠标，
##   所以它响了就说明「触摸合成的鼠标真的漏到了 GUI」。
func _setup_ui_trap() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_ui_btn = Button.new()
	_ui_btn.text = ""
	_ui_btn.size = Vector2(120, 60)
	layer.add_child(_ui_btn)
	_ui_btn.button_down.connect(func() -> void: _ui_down += 1)
	_ui_btn.pressed.connect(func() -> void: _ui_press += 1)


func _teardown() -> void:
	VirtualPad.set("enabled", _pad_was_enabled)
	VirtualPad.set("_has_touchscreen", false)
	VirtualPad.call("_apply_enabled")
	print("触屏开关已还原为跑之前的 ", _pad_was_enabled, "（全程没写 touch_ui.json）")


func _run() -> void:
	await _frames(3)
	# ⚠ 不能假设触屏是关的：user://touch_ui.json 里存过 enabled=true，开机就是触屏态，
	#   下面三条 PC 基线会全红（踩过一次，还是被别的诊断工具写进去的）
	_pad_was_enabled = bool(VirtualPad.is_touch_enabled())
	VirtualPad.set("enabled", false)
	VirtualPad.call("_apply_enabled")
	var stick_c := Vector2(_vp.x * 0.135, _vp.y * 0.720)
	var zone_c := Vector2(_vp.x * 0.30, _vp.y * 0.85)      # 召唤区内、默认圈外
	var open_c := Vector2(_vp.x * 0.62, _vp.y * 0.22)      # 场景区（右上空白）

	# ===== 1. PC 基线：没开触屏按键时，鼠标点设施照旧开面板 =====
	_place_fac_at(stick_c)
	_hits = 0
	_mouse(true, stick_c)
	await _frames(2)
	_mouse(false, stick_c)
	await _frames(2)
	_check(_hits == 1, "PC：鼠标左键点设施 = 开一次（摇杆改造不影响键鼠）", str(_hits))
	# 悬停守卫直接调处理器验：引擎的 mouse_entered 时序不是这里的被测对象，
	# 这里要钉住的是「触屏关 = 放行、触屏开 = 拦掉」这一条分支
	_fac.call("set_highlight", false)
	_fac.call("_on_mouse_entered")
	# 命中过一次偶发红（同一份代码连跑两次是 40/0）：等几帧再读，别把抖动当回归
	for i in range(10):
		if _visual_lit():
			break
		await get_tree().process_frame
	_check(_visual_lit(), "PC：悬停守卫不拦（触屏关时照常高亮）", str(_fac.get("_visual").modulate))
	_fac.call("_on_mouse_exited")
	await _frames(2)
	_check(not _visual_lit(), "PC：离开后还原", str(_fac.get("_visual").modulate))
	# 摇杆区底下的按钮在 PC 上必须照常能点（闸门只在触屏时生效）
	_ui_btn.position = stick_c - Vector2(60, 30)
	_ui_down = 0
	_ui_press = 0
	var uc := _ui_btn.get_global_rect().get_center()
	_mouse(true, uc)
	await _frames(2)
	_mouse(false, uc)
	await _frames(2)
	_check(_ui_down == 1 and _ui_press == 1,
		"PC：摇杆区底下的按钮照常按得到", "down=%d press=%d" % [_ui_down, _ui_press])

	# ===== 2. 开触屏（模拟真机：有触摸屏 + 摇杆可见）=====
	VirtualPad.set("_has_touchscreen", true)
	VirtualPad.enabled = true
	VirtualPad.call("_apply_enabled")
	VirtualPad.set_context("realm")
	await _frames(3)
	_check(VirtualPad.is_touch_enabled(), "触屏按键已开")
	_check(VirtualPad.get("_root").visible, "虚拟键层可见（闸门才会生效）")

	# ===== 3. 真机事件序：在摇杆默认圈上按-拖-抬 =====
	# 设施放在抬手点：与埋在摇杆底下的那颗按钮错开，两条断言各自独立
	_place_fac_at(stick_c + Vector2(70, 40))
	_hits = 0
	_ui_down = 0
	_ui_press = 0
	await _android_finger(0, stick_c, [stick_c + Vector2(40, 20), stick_c + Vector2(70, 40)], 2)
	await _frames(3)
	_check(_hits == 0, "摇杆区按-拖-抬：设施一次都没被点开", str(_hits))
	# 这条单独验 L1：设施那条路 L2 也会挡，按钮只吃鼠标，漏了就一定响
	_check(_ui_down == 0 and _ui_press == 0,
		"摇杆区的合成鼠标根本没到 GUI（棋局棋盘/入场卡那类 Control 同样被保住）",
			"down=%d press=%d" % [_ui_down, _ui_press])

	# ===== 4. 摇杆按下后拖到设施上方抬手（抬手点已在摇杆区外）=====
	_place_fac_at(stick_c + Vector2(260, 60))
	_hits = 0
	await _android_finger(0, stick_c, [stick_c + Vector2(130, 30), stick_c + Vector2(260, 60)], 2)
	await _frames(3)
	_check(_hits == 0, "从摇杆滑到设施上抬手：不算点击（手指归摇杆管）", str(_hits))

	# ===== 5. 动态摇杆召唤区：默认圈外、区域内的按下 =====
	_place_fac_at(zone_c + Vector2(60, -30))
	_hits = 0
	# 先只按下，量圆心（抬手时 _home_stick 会把圆心送回默认位，量不到）
	_mouse(true, zone_c)
	_touch(true, zone_c, 0)
	await _frames(2)
	_check(_stick_center().distance_to(zone_c) <= 2.0,
		"动态摇杆：圆心挪到按下点（不必摸到画出来的圈）", str(_stick_center()))
	_drag_to(0, zone_c + Vector2(60, -30))
	await _frames(2)
	_mouse(false, zone_c + Vector2(60, -30))
	_touch(false, zone_c + Vector2(60, -30), 0)
	await _frames(3)
	_check(_hits == 0, "召唤区（默认圈外）按-拖-抬：也不误触", str(_hits))
	_check(_stick_center().distance_to(stick_c) <= 2.0,
		"抬手后摇杆回默认位（视觉不留在最后按过的地方）", str(_stick_center()))

	# ===== 6. 按下那一拍不产生移动方向 =====
	_release_all_fingers()
	await _frames(2)
	_touch(true, zone_c, 1)
	await _frames(2)
	_check(not Input.get_action_strength("move_right") \
			and not Input.get_action_strength("move_left") \
			and not Input.get_action_strength("move_up") \
			and not Input.get_action_strength("move_down"),
		"按下那一拍不产生方向（不再「一按就窜一步」）")
	# 死区内不产生移动：推 18px = 半径的 0.196，旧死区 0.18 会动、新的 0.22 不动
	_drag_to(1, zone_c + Vector2(_stick_radius() * 0.20, 0))
	await _frames(2)
	_check(not Input.get_action_strength("move_right"),
		"死区内（推 0.20 半径；旧值 0.18 会动）不动", str(Input.get_action_strength("move_right")))
	# 推出死区
	_drag_to(1, zone_c + Vector2(_stick_radius() * 0.60, 0))
	await _frames(2)
	_check(Input.get_action_strength("move_right") > 0.4,
		"推出死区才走（0.60 半径）", str(Input.get_action_strength("move_right")))
	# 92% 满舵
	_drag_to(1, zone_c + Vector2(_stick_radius() * 0.95, 0))
	await _frames(2)
	_check(is_equal_approx(Input.get_action_strength("move_right"), 1.0),
		"推到 92% 半径即满舵", str(Input.get_action_strength("move_right")))
	_touch(false, zone_c + Vector2(_stick_radius() * 0.95, 0), 1)
	await _frames(2)
	_check(not Input.get_action_strength("move_right"), "抬手后移动归零")

	# ===== 7. 场景区「点按」仍然能开设施（双入口）=====
	_place_fac_at(open_c)
	_hits = 0
	await _android_finger(0, open_c, [], 1)
	await _frames(3)
	_check(_hits == 1, "场景区轻点设施：仍然打开（点按入口保留）", str(_hits))

	# ===== 8. 场景区拖过阈值 / 长按 = 不算点击 =====
	_hits = 0
	await _android_finger(0, open_c, [open_c + Vector2(220, 0)], 2)
	await _frames(3)
	_check(_hits == 0, "场景区按住滑 220px 再抬：不开面板（那是拖动）", str(_hits))
	_hits = 0
	_touch(true, open_c, 0)
	_mouse(true, open_c)
	await _wait(0.4)
	_mouse(false, open_c)
	_touch(false, open_c, 0)
	await _frames(3)
	_check(_hits == 0, "按住 0.4 秒再抬：超过点按时长，不算点击", str(_hits))

	# ===== 9. 触屏下 hover 不跟着手指乱亮 =====
	_place_fac_at(stick_c + Vector2(80, 0))
	_fac.call("set_highlight", false)
	_hits = 0
	await _android_finger(0, stick_c - Vector2(160, 0),
			[stick_c - Vector2(60, 0), stick_c, stick_c + Vector2(80, 0)], 2)
	await _frames(3)
	_check(not _visual_lit(), "手指划过设施：不再跟着亮（触屏不算悬停）",
			str(_fac.get("_visual").modulate))
	_check(_hits == 0, "划过路径上有设施也不误触（汇总）", str(_hits))

	# ===== 9b. 场景区横扫过设施（既不是摇杆也不是点按）=====
	_place_fac_at(open_c)
	_fac.call("set_highlight", false)
	_hits = 0
	await _android_finger(0, open_c - Vector2(300, 0),
			[open_c - Vector2(120, 0), open_c], 2)
	await _frames(3)
	_check(_hits == 0, "场景区横扫 300px 停在设施上：不算点按，不开面板", str(_hits))
	_check(not _visual_lit(), "场景区横扫也不触发悬停高亮（触屏不算悬停）",
			str(_fac.get("_visual").modulate))
	# 同一分支的反面：触屏开着时，处理器自己被守卫挡掉
	_fac.call("_on_mouse_entered")
	_check(not _visual_lit(), "触屏：悬停处理器被守卫直接挡掉",
			str(_fac.get("_visual").modulate))

	# ===== 10. 虚拟键最小命中半径（缩放按「较小边」，不是只按高）=====
	var btns: Dictionary = VirtualPad.get("_buttons")
	var skill1: Control = btns.get("c_skill_1")
	var pscale: float = VirtualPad.call("_size_scale", VirtualPad.call("_safe_rect"))
	_check(skill1.get("radius") >= 32.0 * pscale - 0.5,
		"功法键 r=28 抬到拇指最小命中 32", "r=%.1f 下限=%.1f" % [skill1.get("radius"), 32.0 * pscale])
	_check(pscale <= _vp.y / 720.0 + 0.001 and pscale <= _vp.x / 1280.0 + 0.001,
		"尺寸缩放取宽高里较小的边（4:3 平板上摇杆圈不再压到功法列）", str(pscale))
	var defs: Dictionary = VirtualPad.get("_defs_by_id")
	_check(int((defs.get("c_skill_1") as Dictionary).get("r", 0)) == 28,
		"表里仍是 28（下限只作用于落位，不改存档口径）")

	# ===== 11. 安全区退化：headless 窗口尺寸 0 时必须退回整块视口 =====
	var safe: Rect2 = VirtualPad.call("_safe_rect")
	_check(safe.size.distance_to(_vp) < 2.0,
		"拿不到安全区时退回整块视口（不会把键挤没）", str(safe))

	# ===== 11b. 安全区内缩时键位要跟着缩（真机刘海/手势条的映射）=====
	VirtualPad.set("safe_override", Rect2(Vector2(80, 0), Vector2(_vp.x - 160, _vp.y)))
	VirtualPad.call("_apply_layout")
	await _frames(2)
	var btns2: Dictionary = VirtualPad.get("_buttons")
	var back_b: Control = btns2.get("r_back")
	var cx: float = back_b.position.x + back_b.radius
	_check(absf(cx - (80.0 + 0.945 * (_vp.x - 160))) < 1.5,
		"内缩 80px 后「设置」键跟着往左走（不再压在手势条上）",
		"cx=%.1f 期望=%.1f" % [cx, 80.0 + 0.945 * (_vp.x - 160)])
	_check(cx + back_b.radius <= _vp.x - 80.0 + 1.5,
		"键的右边缘仍在安全区内", str(cx + back_b.radius))
	VirtualPad.set("safe_override", Rect2())
	VirtualPad.call("_apply_layout")
	await _frames(2)

	# ===== 12. 主城「进入」键三态 =====
	await _realm_tri_state()

	# ===== 13. 返回键分层 =====
	await _back_layering()


# ===================== 主城三态 =====================

func _realm_tri_state() -> void:
	# 棋坛的进度锁要「没通关凡界」才成立：把状态钉死，别跟着玩家存档漂
	var dom_saved := CharacterData.domain_progress.duplicate(true)
	CharacterData.domain_progress = {}
	var realm := (load("res://scenes/main/primordial_realm.tscn") as PackedScene).instantiate()
	add_child(realm)
	await _frames(6)
	var btns: Dictionary = VirtualPad.get("_buttons")
	var enter: Control = btns.get("r_enter")
	_check(enter != null, "主城布局里有「进入」这颗键")
	if enter == null:
		return
	_check(String(enter.get("label")) == "走近设施" and bool(enter.get("dim")),
		"没靠近设施：键面写「走近设施」且压暗", "%s dim=%s" % [enter.get("label"), enter.get("dim")])

	var arena := realm.get_node_or_null("Facilities/Arena")
	arena.emit_signal("player_near", "arena", true)
	await _frames(3)
	_check(String(enter.get("label")) == "演武场" and not bool(enter.get("dim")),
		"靠近可进入的设施：键面换成设施名并点亮", "%s dim=%s" % [enter.get("label"), enter.get("dim")])

	var mem := realm.get_node_or_null("Facilities/Memory")
	mem.emit_signal("player_near", "memory", true)
	await _frames(3)
	_check(bool(enter.get("dim")) and String(enter.get("label")).contains("暂未开启"),
		"封锁设施：键面写「暂未开启」并压暗", String(enter.get("label")))

	var match_f := realm.get_node_or_null("Facilities/Match")
	match_f.emit_signal("player_near", "match", true)
	await _frames(3)
	_check(bool(enter.get("dim")) and String(enter.get("label")).length() > 2,
		"进度锁设施：键面直接写清解锁条件", String(enter.get("label")))

	arena.emit_signal("player_near", "arena", false)
	mem.emit_signal("player_near", "memory", false)
	match_f.emit_signal("player_near", "match", false)
	await _frames(2)
	realm.queue_free()
	await _frames(6)
	CharacterData.domain_progress = dom_saved


# ===================== 返回键分层 =====================

func _back_layering() -> void:
	# 主城在场：返回键 = 后退（ESC 链），不该弹退出确认
	var realm := (load("res://scenes/main/primordial_realm.tscn") as PackedScene).instantiate()
	add_child(realm)
	await _frames(6)
	_check(GameState.back_uses_esc, "主城声明「返回键 = 后退」")
	GameState.handle_go_back()
	await _frames(4)
	var d := _top_dialog()
	_check(d != null and d.dlg_title == "返回登录界面",
		"主城按返回键：走 ESC 语义问「返回登录界面」，不是退出游戏",
			"" if d == null else d.dlg_title)
	if d != null:
		_click_dialog(d, 0)      # 取消
		await _frames(4)
	# 场景离场后声明必须交还，否则退出确认永远出不来
	realm.queue_free()
	await _frames(8)
	_check(not GameState.back_uses_esc, "离场后交还返回键声明")
	GameState.handle_go_back()
	await _frames(4)
	var d2 := _top_dialog()
	_check(d2 != null and d2.dlg_title == "退出游戏",
		"没有后退语义时返回键退回退出确认", "" if d2 == null else d2.dlg_title)
	if d2 != null:
		_click_dialog(d2, 0)
		await _frames(4)


# ===================== 工具 =====================

func _place_fac_at(screen_pos: Vector2) -> void:
	_fac.position = screen_pos - _vp * 0.5


func _visual_lit() -> bool:
	var v = _fac.get("_visual")
	return v != null and is_instance_valid(v) and (v as CanvasItem).modulate.r > 1.2


func _stick_center() -> Vector2:
	var s: Control = VirtualPad.get("_stick")
	return s.position + s.size * 0.5


func _stick_radius() -> float:
	return VirtualPad.get("_stick").radius


func _mouse(pressed: bool, pos: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pos
	mb.global_position = pos
	# local 坐标投递：headless 视口有 0.05 的 final transform，
	# 用 parse_input_event 的话 Control 命中测试会算到屏幕外
	get_viewport().push_input(mb, true)


func _touch(pressed: bool, pos: Vector2, idx: int) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = pressed
	get_viewport().push_input(t, true)


func _drag_to(idx: int, pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	# 只有真的按着才带 mask：不带 mask 才是「悬停移动」，才会触发 mouse_entered
	if _hover_pressed:
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(mm, true)
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = pos
	get_viewport().push_input(d, true)


## 复刻真机一根手指：按下（鼠标先、触摸后）→ 拖 → 抬手（鼠标先、触摸后）
func _android_finger(idx: int, start: Vector2, moves: Array, hold_frames: int) -> void:
	_mouse(true, start)
	_touch(true, start, idx)
	await _frames(1)
	_hover_pressed = true
	for m in moves:
		_drag_to(idx, m as Vector2)
		await _frames(1)
	for i in range(hold_frames):
		await _frames(1)
	var end: Vector2 = start
	if not moves.is_empty():
		end = moves[moves.size() - 1]
	_mouse(false, end)
	_touch(false, end, idx)


func _release_all_fingers() -> void:
	VirtualPad.call("_release_all")


func _top_dialog() -> ConfirmDialog:
	for c in get_tree().root.get_children():
		if c is ConfirmDialog:
			return c as ConfirmDialog
	return null


func _click_dialog(d: ConfirmDialog, idx: int) -> void:
	var panel: Control = d.get("_root")
	var btn_row := panel.get_child(0).get_child(0).get_child(2)
	var b: Control = btn_row.get_child(idx)
	var c := b.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = c
	mm.global_position = c
	get_viewport().push_input(mm, true)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = c
	mb.global_position = c
	get_viewport().push_input(mb, true)
	var mu := InputEventMouseButton.new()
	mu.button_index = MOUSE_BUTTON_LEFT
	mu.pressed = false
	mu.position = c
	mu.global_position = c
	get_viewport().push_input(mu, true)
