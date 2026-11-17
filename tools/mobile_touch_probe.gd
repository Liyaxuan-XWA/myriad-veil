extends SceneTree
## 触摸事件注入自检：手机玩家真按下去，到底会发生什么。
##
## 全部用 Input.parse_input_event 注 InputEventScreenTouch / ScreenDrag —— 和安卓送进引擎
## 的那条路一致：会先经过 emulate_mouse_from_touch（工程默认 true）生成一个模拟鼠标事件，
## 所以既测虚拟键本身，也测「触摸被模拟成鼠标后穿透到下层 UI」这个副作用。
##
## ⚠ 注入的事件在**下一帧**才派发，所以每一步都要空等 FRAMES 帧再读状态；
##    读写放进同一个函数里 = 读到上一次的状态。
##
## 用法：godot --path . --resolution 1600x720 --script tools/mobile_touch_probe.gd

const FRAMES := 3

var _vp := Vector2.ZERO
var _frame := 0
var _wait := 0
var _q: Array = []
var _started := false
## 跑之前玩家的触屏开关状态：本工具只临时改运行时，绝不写盘
var _pad_was_enabled := false

var _tap_target: Button
var _tap_hits := 0
var _drag_src: DragSource
var _drag_dst: DropTarget
var _drop_log: Array[String] = []
var _spy: KeySpy
var _pad = null
var _defs: Array = []
var _stick_pos := Vector2(0.135, 0.720)


func _initialize() -> void:
	print("\n########## 触摸注入自检 ##########")


func _process(_d: float) -> bool:
	if _vp == Vector2.ZERO:
		_frame += 1
		if _frame < 10:
			return false
		_vp = root.get_visible_rect().size
		# ⚠ 不能用 `VirtualPad.xxx` 直接引用：--script 工具在 autoload 全局名注册进
		#    GDScript 分析器**之前**就编译好了，会报 Identifier not found。运行期取节点。
		_pad = root.get_node_or_null("VirtualPad")
		if _pad == null:
			push_error("取不到 VirtualPad autoload")
			return true
		var cm = _pad.get_script().get_script_constant_map()
		_defs = cm["BUTTON_DEFS"]
		_stick_pos = cm["STICK_POS"]
		# ⚠ 不能用 set_enabled(true)：那个会写 user://touch_ui.json，
		#   把玩家自己调过的键位配置顺带改成「触屏已开」，下次开 PC 版就满屏虚拟键。
		#   这里只改运行时状态，收尾再原样装回去。
		_pad_was_enabled = bool(_pad.is_touch_enabled())
		_pad.set("enabled", true)
		_pad.call("_apply_enabled")
		_build_widgets()
		_enqueue_all()
		_started = true
		print("视口 ", _vp, "  触屏按键=", _pad.is_touch_enabled(),
			"  真实触摸屏(桌面必为 false)=", DisplayServer.is_touchscreen_available())
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _q.is_empty():
		if _pad != null and is_instance_valid(_pad):
			_pad.set("enabled", _pad_was_enabled)
			_pad.call("_apply_enabled")
			print("已把触屏开关恢复成跑之前的状态 = ", _pad_was_enabled, "（没写盘）")
		print("################ 探针结束 ################")
		return true
	var item: Dictionary = _q.pop_front()
	(item["f"] as Callable).call()
	_wait = int(item["w"])
	return false


func _after(frames: int, f: Callable) -> void:
	_q.append({"f": f, "w": frames})


# ===================== 搭测试台 =====================

func _build_widgets() -> void:
	# 不设为 combat，战斗键（攻/拾取）根本不可见，_button_at 会直接跳过它们
	_pad.set_context("combat")
	_spy = KeySpy.new()
	_spy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_spy)

	var ac := _center("c_attack")
	_tap_target = Button.new()
	_tap_target.name = "UnderTheAttackButton"
	_tap_target.position = ac - Vector2(60, 25)
	_tap_target.size = Vector2(120, 50)
	_tap_target.text = "我在攻键底下"
	root.add_child(_tap_target)
	_tap_target.pressed.connect(func() -> void: _tap_hits += 1)

	_drag_src = DragSource.new()
	_drag_src.size = Vector2(90, 90)
	_drag_src.position = Vector2(_vp.x * 0.40, _vp.y * 0.22)
	root.add_child(_drag_src)
	_drag_dst = DropTarget.new()
	_drag_dst.size = Vector2(90, 90)
	_drag_dst.position = Vector2(_vp.x * 0.40, _vp.y * 0.22 + 160.0)
	root.add_child(_drag_dst)
	_drag_dst.log = _drop_log


func _center(id: String) -> Vector2:
	for def in _defs:
		if String(def.get("id", "")) == id:
			var p: Vector2 = def.get("pos")
			return Vector2(p.x * _vp.x, p.y * _vp.y)
	return Vector2.ZERO


func _stick_center() -> Vector2:
	return Vector2(_stick_pos.x * _vp.x, _stick_pos.y * _vp.y)


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.device = -1
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)


func _drag(idx: int, pos: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.device = -1
	d.position = pos
	d.relative = Vector2(0, 8)
	Input.parse_input_event(d)


# ===================== 步骤 =====================

func _enqueue_all() -> void:
	_after(1, _step_a)
	_after(1, _step_b1)
	_after(2, _step_b2)
	_after(1, _step_b3)
	_after(2, _step_b4)
	_after(1, _step_c1)
	_after(2, _step_c2)
	_after(1, _step_c3)
	_after(2, _step_c4)
	_after(1, _step_d1)
	_after(3, _step_d2)
	_after(1, _step_e1)
	_after(2, _step_e2)
	_after(2, _step_e3)
	_after(2, _step_e4)
	_after(2, _step_e5)
	_after(2, _step_e6)
	_after(1, _step_f1)
	_after(2, _step_f2)
	_after(2, _step_f3)
	_after(1, _step_g1)
	_after(3, _step_g2)


## A：触屏开着时，attack 还绑不绑鼠标左键（2026-10-23「点屏幕就挥刀」的根因）
func _step_a() -> void:
	var mouse_bound := false
	for e in InputMap.action_get_events("attack"):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			mouse_bound = true
	print("A  触屏开启时 attack 仍绑鼠标左键 = ", mouse_bound, "  ← 期望 false")


## B：单指点「攻」→ 动作按下 / 抬起后释放
func _step_b1() -> void:
	_tap_hits = 0
	_touch(1, _center("c_attack"), true)


func _step_b2() -> void:
	print("B1 按住攻键中：attack=", Input.is_action_pressed("attack"))


func _step_b3() -> void:
	_touch(1, _center("c_attack"), false)


func _step_b4() -> void:
	print("B2 抬指后：attack=", Input.is_action_pressed("attack"),
		"  攻键底下的按钮被点=", _tap_hits,
		"  ← attack 要 false；被点要 0（pressed 在抬指那刻才发，所以必须在这里读）")


## C：指 0 压摇杆右推 + 指 1 按攻 —— 手机玩家最基本的「边走边打」
func _step_c1() -> void:
	_touch(0, _stick_center(), true)


func _step_c2() -> void:
	_touch(0, _stick_center() + Vector2(70, 0), false)
	_touch(0, _stick_center() + Vector2(70, 0), true)


func _step_c3() -> void:
	_touch(1, _center("c_attack"), true)


func _step_c4() -> void:
	print("C  摇杆右推 + 攻同按：move_right=", "%.2f" % Input.get_action_strength("move_right"),
		"  attack=", Input.is_action_pressed("attack"), "  ← 两个都要非 0")
	_touch(1, _center("c_attack"), false)
	_touch(0, _stick_center() + Vector2(70, 0), false)


## D：点空地（不落在任何键/摇杆上）→ 会不会误挥刀
func _step_d1() -> void:
	_touch(2, Vector2(_vp.x * 0.55, _vp.y * 0.55), true)


func _step_d2() -> void:
	print("D  点空地按下瞬间：attack=", Input.is_action_pressed("attack"), "  ← 期望 false")
	_touch(2, Vector2(_vp.x * 0.55, _vp.y * 0.55), false)


## E：触摸拖拽能不能触发 Godot 的拖放（装备穿戴 / 铁砧都靠它）
func _src_c() -> Vector2:
	return _drag_src.global_position + _drag_src.size * 0.5


func _dst_c() -> Vector2:
	return _drag_dst.global_position + _drag_dst.size * 0.5


func _step_e1() -> void:
	_touch(3, _src_c(), true)


func _step_e2() -> void:
	_drag(3, _src_c() + Vector2(0, 20))


func _step_e3() -> void:
	print("E1 拖拽中段：gui_is_dragging=", root.gui_is_dragging(), "  源被调用=", _drag_src.grab_count)
	_drag(3, (_src_c() + _dst_c()) * 0.5)


func _step_e4() -> void:
	_drag(3, _dst_c())


func _step_e5() -> void:
	_touch(3, _dst_c(), false)


func _step_e6() -> void:
	print("E  触摸拖拽：源 _get_drag_data=", _drag_src.grab_count,
		"  落点 _drop_data=", _drop_log, "  ← 两边都有记录，手机上「拖拽穿戴」才成立")


## F：HUD 按钮（不在虚拟键上）能不能被触摸点到
func _step_f1() -> void:
	_tap_hits = 0
	_tap_target.position = Vector2(_vp.x * 0.30, _vp.y * 0.86)
	_tap_target.size = Vector2(140, 52)
	_touch(4, _tap_target.global_position + _tap_target.size * 0.5, true)


func _step_f2() -> void:
	_touch(4, _tap_target.global_position + _tap_target.size * 0.5, false)


func _step_f3() -> void:
	print("F  点普通 HUD 按钮：被点次数=", _tap_hits, "  ← 期望 1（=0 说明触摸打不开界面）")


## G：虚拟「拾取」键合成的键盘事件，_unhandled_input 那类判断收不收得到
func _step_g1() -> void:
	_spy.seen.clear()
	_touch(5, _center("c_pickup"), true)


func _step_g2() -> void:
	print("G  按虚拟拾取键收到物理键=", _spy.seen, "  ← 应含 70(KEY_F)，否则 F 类交互在触屏上是死的")
	_touch(5, _center("c_pickup"), false)


# ===================== 拖拽测试控件 =====================

class DragSource extends Button:
	var grab_count := 0

	func _ready() -> void:
		text = "拖我"
		mouse_filter = Control.MOUSE_FILTER_STOP


	func _get_drag_data(_at: Vector2) -> Variant:
		grab_count += 1
		return {"what": "test_item"}


class DropTarget extends Panel:
	var log: Array[String] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("what")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		log.append("drop:%s" % str(data))


## 专门验拟键注入的 InputEventKey 能不能走到 _unhandled_input
class KeySpy extends Control:
	var seen: Array[int] = []

	func _unhandled_input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k != null and k.pressed and not k.echo:
			seen.append(k.physical_keycode)
