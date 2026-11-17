extends Node
## 触屏虚拟按键（2026-10-22 用户要求：安卓可玩 · 布局可自定义 · 不影响 PC）
##
## 为什么要这么写——项目里的输入读取有三种方式，必须全部覆盖：
##   ① `_unhandled_input` 里判 `event.physical_keycode`（F / C / Y / ESC / Tab…）
##      → 本类合成 `InputEventKey` 用 `Input.parse_input_event()` 注入，**调用方零改动**
##   ② `Input.is_action_just_pressed("attack"/"dodge"/"parry")`
##      → `Input.action_press()/action_release()`，**调用方零改动**
##   ③ `Input.is_physical_key_pressed(KEY_1 / KEY_Q…)`（玩家轮询法宝与功法）
##      → 轮询读不到"虚拟按键"，所以 `player.gd` 那两处改调 `is_key_down()`
##
## PC 不受影响：`enabled = false` 时不处理任何输入、不注入任何事件、
## `is_key_down()` 只读真实键盘；UI 节点虽然建好但整层隐藏且 `mouse_filter = IGNORE`。
##
## 布局：`user://touch_ui.json` 存 `{"enabled": bool, "layout": {id: {x,y,r}}}`
## 归一化坐标（0~1，相对视口），所以手机各种比例都能用。

const CONFIG_PATH := "user://touch_ui.json"
## 游戏中的层级：HUD 是 1，系统面板是 101
const LAYER_PLAY := 90
## 编辑布局时必须高于系统面板（101），否则按钮被面板压住拖不到
const LAYER_EDIT := 130

## 摇杆默认位置与半径（按 720 高设计，实际按屏幕高度缩放）
const STICK_POS := Vector2(0.135, 0.720)
const STICK_RADIUS := 92.0
## 动态摇杆召唤区（归一化）：这块内任意一点按下都以按下点为圆心生成摇杆。
## 固定圈在手机上是「按偏一点就不走」的主要来源；代价是这块区域不再接受点按，
## 主城设施走「进入」键。
## ⚠ 上沿卡在 0.47 而不是 0.42：mobile_layout_audit 在 20:9 量到演武场训练面板
##   （(18,18) 起、400×320，底边 338）压进区顶 —— 面板底下的按钮就点不到了。
##   0.47 → 区顶 338.4，刚好让开面板底边。
const STICK_ZONE := Rect2(0.0, 0.47, 0.45, 0.53)
## 摇杆死区：小于这个比例不产生移动（防手抖）
const STICK_DEADZONE := 0.22
## 满舵点：推到半径的 92% 就是满速，拇指不必顶到圈边
const STICK_SATURATE := 0.92
## 命中放宽：手指没那么准，圈外一点也算按到
const BUTTON_HIT_SLACK := 1.15
const STICK_HIT_SLACK := 1.25
## 拇指可命中的最小半径（设计像素，720 高基准）：直径 64 ≈ 9mm，
## 低于这条的键（功法/法宝那几颗 r=28）在手机上就是「点了没反应」
const MIN_HIT_RADIUS := 32.0
## 一次「点按」：位移 ≤12 逻辑像素且时长 ≤0.25 秒，且起止都不在摇杆/按键圈内。
## 超过就只算拖动 —— 推摇杆、划屏幕都不该被当成点击（2026-11-13 误触设施根因）。
const TAP_MAX_MOVE := 12.0
const TAP_MAX_TIME := 0.25

## 虚拟键清单
##   id    布局存档的键，**改名会让旧布局失效**
##   kind  "key" = 模拟物理键（value 是 Key 常量）；"action" = InputMap 动作
##   ctx   "combat" 战斗 / "realm" 主城
##   r     半径（按 720 高设计，实际按屏幕高度等比缩放）
const BUTTON_DEFS := [
	# ===== 战斗：动作键（右手拇指区）=====
	{"id": "c_attack", "label": "攻", "kind": "action", "value": "attack",
		"pos": Vector2(0.870, 0.700), "r": 48.0, "ctx": "combat"},
	{"id": "c_parry", "label": "弹", "kind": "action", "value": "parry",
		"pos": Vector2(0.945, 0.500), "r": 38.0, "ctx": "combat"},
	{"id": "c_dodge", "label": "闪", "kind": "action", "value": "dodge",
		"pos": Vector2(0.745, 0.845), "r": 38.0, "ctx": "combat"},
	# 战斗轮盘（丹药 / 符纸）：等价键盘 G；放在「闪」右下方，避开攻/弹/闪的命中圈
	{"id": "c_item", "label": "道具", "kind": "key", "value": KEY_G,
		"pos": Vector2(0.945, 0.830), "r": 34.0, "ctx": "combat"},
	# ===== 战斗：功法 1~4（左侧竖排，避开底部技能栏）=====
	# ⚠ 行距 0.115（=82.8px）而不是 0.10：命中半径下限抬到 32 后，
	#   放宽 1.15 的两圈需要 ≥73.6px 才不重叠；mobile_layout_audit 在 20:9 下
	#   量到过「功1×功2 圆心距 72 < 74」—— 圈挨着圈，手指落在缝隙里会点错键。
	{"id": "c_skill_1", "label": "功1", "kind": "key", "value": KEY_Q,
		"pos": Vector2(0.260, 0.540), "r": 28.0, "ctx": "combat"},
	{"id": "c_skill_2", "label": "功2", "kind": "key", "value": KEY_E,
		"pos": Vector2(0.260, 0.655), "r": 28.0, "ctx": "combat"},
	{"id": "c_skill_3", "label": "功3", "kind": "key", "value": KEY_R,
		"pos": Vector2(0.260, 0.770), "r": 28.0, "ctx": "combat"},
	{"id": "c_skill_4", "label": "功4", "kind": "key", "value": KEY_T,
		"pos": Vector2(0.260, 0.885), "r": 28.0, "ctx": "combat"},
	# ===== 战斗：法宝 1~3（紧邻功法右侧一列，行距同上）=====
	{"id": "c_treasure_1", "label": "宝1", "kind": "key", "value": KEY_1,
		"pos": Vector2(0.360, 0.500), "r": 28.0, "ctx": "combat"},
	{"id": "c_treasure_2", "label": "宝2", "kind": "key", "value": KEY_2,
		"pos": Vector2(0.360, 0.615), "r": 28.0, "ctx": "combat"},
	{"id": "c_treasure_3", "label": "宝3", "kind": "key", "value": KEY_3,
		"pos": Vector2(0.360, 0.730), "r": 28.0, "ctx": "combat"},
	# ===== 战斗：拾取 / 重开 / 返回 =====
	{"id": "c_pickup", "label": "拾取", "kind": "key", "value": KEY_F,
		"pos": Vector2(0.070, 0.470), "r": 32.0, "ctx": "combat"},
	{"id": "c_restart", "label": "重开", "kind": "key", "value": KEY_C,
		"pos": Vector2(0.070, 0.360), "r": 28.0, "ctx": "combat"},
	{"id": "c_back", "label": "返回", "kind": "key", "value": KEY_ESCAPE,
		"pos": Vector2(0.070, 0.250), "r": 28.0, "ctx": "combat"},
	# ===== 主城（功法库 / 背包是 HUD 图标，不在这里重复）=====
	{"id": "r_enter", "label": "进入", "kind": "key", "value": KEY_F,
		"pos": Vector2(0.870, 0.760), "r": 44.0, "ctx": "realm"},
	# ⚠ 位置避开右上角的 HUD 图标（背包/功法库占 y 96~238）：放在「进入」上方
	{"id": "r_back", "label": "设置", "kind": "key", "value": KEY_ESCAPE,
		"pos": Vector2(0.945, 0.600), "r": 28.0, "ctx": "realm"},
]

## 配色（换皮只改这里；虚拟键要半透明，不能挡住画面）
const C_FILL := Color(0.07, 0.09, 0.13, 0.52)
const C_FILL_HELD := Color(0.30, 0.55, 0.75, 0.78)
const C_BORDER := Color(0.82, 0.74, 0.50, 0.55)
const C_BORDER_EDIT := Color(1.00, 0.86, 0.35, 0.95)
const C_TEXT := Color(0.94, 0.92, 0.86, 0.95)
const C_STICK_BASE := Color(0.07, 0.09, 0.13, 0.35)
const C_STICK_KNOB := Color(0.75, 0.80, 0.88, 0.62)

## 触屏开关变化（主城 HUD 的「背包/功法库」图标靠它显示隐藏）
signal enabled_changed(is_on: bool)

## 进入/退出布局编辑（场景可据此临时收起 HUD 文字，避免和编辑栏打架）
signal edit_mode_changed(is_on: bool)

var enabled := false          # 是否启用触屏按键
## 当前场景的按键组："realm" / "combat"；"none" = 这个界面不需要虚拟键（开始界面、棋坛…）。
## 默认 none：autoload 跨场景活着，谁不声明就一个键都不摆 —— 2026-11-13 用户报
## 「开始界面/棋坛也冒虚拟键」，根因就是默认值原来是 realm。
var _ctx := "none"
var _edit := false            # 编辑布局模式
var _edit_ctx := "combat"     # 正在编辑哪一组
## 战斗轮盘等全屏覆盖层打开时暂时收起虚拟键，避免它抢走轮盘扇区的触摸
var _overlay_blocked := false
## 「按下去要能穿过去」的屏幕矩形（说明卡这类画在虚拟键**上面**的浮层）：
## 命中这些矩形的触摸/合成鼠标不当摇杆认领，直接交给底下的控件。
## 2026-11-13 用户报：手游教学卡上的「知道了」点不了 —— 它正好落在摇杆召唤区里。
var _pass_rects: Array = []

var _layer: CanvasLayer
var _root: Control
var _stick: TouchStick
var _buttons: Dictionary = {}     # id -> TouchButton
var _defs_by_id: Dictionary = {}  # id -> def
var _layout: Dictionary = {}      # id -> {"x": float, "y": float, "r": float}
var _virtual_keys: Dictionary = {}  # keycode -> bool（虚拟按下状态）
var _finger_button: Dictionary = {} # touch index -> button id
## 每根手指的起点：index -> {"pos": Vector2, "usec": int, "owner": String}
## owner = ""（场景区，可能算点按）/ "__stick" / 虚拟键 id
var _finger_start: Dictionary = {}
## 最近一次判定成功的点按：{"pos": Vector2, "usec": int}，空 = 没有
var _last_tap: Dictionary = {}
var _stick_finger := -1
var _drag_off := Vector2.ZERO
var _edit_bar: Control
## 有没有真实触摸屏：有的话走触摸事件、忽略鼠标（避免 emulate_mouse_from_touch 双触发）
var _has_touchscreen := false


func _ready() -> void:
	# 面板会暂停场景；虚拟键必须照常响应，否则设置里调不了布局
	process_mode = Node.PROCESS_MODE_ALWAYS
	_has_touchscreen = DisplayServer.is_touchscreen_available()
	# ⚠ 真机上触摸除了 ScreenTouch 还会**额外生成一条鼠标事件**（实测事件序：
	#   MouseButton press → ScreenTouch press → MouseMotion/ScreenDrag ×N →
	#   MouseButton release → ScreenTouch release）。摇杆只吞得掉 ScreenTouch，
	#   那条合成鼠标会照原样发给 GUI 与 Area2D —— 抬手点到谁就触发谁，
	#   这就是「推摇杆误触设施」（2026-11-13 用户报）。
	#   开关 emulate_mouse_from_touch 只在启动时读一次，运行时 set_setting 实测无效
	#   （tools/probe_touch_mouse_emu.gd 两阶段对照），所以只能在 _input 里按落点吞。
	_load_config()
	enabled = bool(_config_flag())
	_build()
	_apply_enabled()


# ===================== 公共 API =====================

## 玩家轮询类输入（法宝 1/2/3、功法 Q/E/R/T）走这里：真实键 or 虚拟键
func is_key_down(code: int) -> bool:
	if Input.is_physical_key_pressed(code):
		return true
	return bool(_virtual_keys.get(code, false))


## 这一拍按下的键是不是**触屏按钮注入**的（不是真人敲键盘）。
## 场景里同一个键可能有两套语义：长卷上真人按 ESC = 返回原初位面，
## 而触屏那颗键面上写着「设置」—— 不分清的话，触屏玩家一点设置就被当成退出。
func is_virtual_key(code: int) -> bool:
	return bool(_virtual_keys.get(code, false))


## 上层浮层把自己「可点区域」报进来：命中这些矩形时不认领（传空数组 = 撤销）
func set_pass_rects(rects: Array) -> void:
	_pass_rects = rects


## 场景进入时声明自己的类型，决定显示哪一组虚拟键
func set_context(ctx: String) -> void:
	_ctx = ctx
	_refresh_visibility()


func is_touch_enabled() -> bool:
	return enabled


func set_enabled(v: bool) -> void:
	if enabled == v:
		return
	enabled = v
	_save_config()
	_apply_enabled()
	if not enabled:
		_release_all()
	enabled_changed.emit(enabled)


## 战斗轮盘打开 / 关闭时调用：打开时收起虚拟键并释放按键，关闭时恢复
func set_overlay_blocked(v: bool) -> void:
	if _overlay_blocked == v:
		return
	_overlay_blocked = v
	if v:
		_release_all()
	_refresh_visibility()


## 进入布局编辑（ctx 决定编辑哪一组）；设置面板负责先把自己关掉
func enter_edit_mode(ctx: String) -> void:
	if not enabled:
		set_enabled(true)
	_edit = true
	_edit_ctx = ctx
	_layer.layer = LAYER_EDIT
	_refresh_visibility()
	_show_edit_bar(true)
	_release_all()
	edit_mode_changed.emit(true)


func exit_edit_mode(save: bool) -> void:
	_edit = false
	_layer.layer = LAYER_PLAY
	_show_edit_bar(false)
	_refresh_visibility()
	_release_all()
	edit_mode_changed.emit(false)
	if save:
		_save_config()


func reset_layout(ctx: String) -> void:
	for def in BUTTON_DEFS:
		if String(def.get("ctx", "")) != ctx:
			continue
		_layout.erase(String(def.get("id", "")))
	_layout.erase("__stick_" + ctx)
	_apply_layout()
	_save_config()


## 给 HUD 图标用：模拟按一下某个键（按下再松开），不改变持续状态
func tap_key(code: int) -> void:
	if not enabled:
		return
	_inject_key(code, true)
	_inject_key(code, false)


## 场景侧改键面文字与可用性（主城「进入」键的三态回执就靠它）。
## PC 上 enabled=false 时按钮整层不可见，改了也没有可见后果。
func set_button_state(id: String, text: String, usable: bool) -> void:
	if not _buttons.has(id):
		return
	var b: TouchButton = _buttons[id]
	b.set_text(text)
	b.set_dim(not usable)


# ===================== 构建 =====================

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "VirtualPad"
	_layer.layer = LAYER_PLAY
	# ⚠ 必须始终处理输入：面板暂停场景时也要能点（编辑布局就在暂停态下进行）
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 根节点不吃鼠标：只有具体按键才接管，避免挡住游戏内的点击
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	_stick = TouchStick.new()
	_stick.name = "Stick"
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.hit_slack = STICK_HIT_SLACK
	_stick.c_base = C_STICK_BASE
	_stick.c_border = C_BORDER
	_stick.c_knob = C_STICK_KNOB
	_root.add_child(_stick)

	for def in BUTTON_DEFS:
		var b := TouchButton.new()
		b.def = def
		b.label = String(def.get("label", ""))
		b.c_fill = C_FILL
		b.c_fill_held = C_FILL_HELD
		b.c_border = C_BORDER
		b.c_border_edit = C_BORDER_EDIT
		b.c_text = C_TEXT
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(b)
		var id := String(def.get("id", ""))
		_buttons[id] = b
		_defs_by_id[id] = def

	_build_edit_bar()
	_apply_layout()
	_refresh_visibility()


func _build_edit_bar() -> void:
	_edit_bar = Control.new()
	_edit_bar.name = "EditBar"
	_edit_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edit_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_bar.visible = false
	_root.add_child(_edit_bar)

	var hint := Label.new()
	hint.text = "拖动按键调整位置 —— 点右上「完成」保存，点「重置」恢复默认"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_left = 160.0
	hint.offset_right = -160.0
	hint.offset_top = 14.0
	hint.offset_bottom = 44.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_bar.add_child(hint)

	var done := _make_edit_button("完成", Vector2(1.0, 0.0))
	done.pressed.connect(_on_edit_done)
	_edit_bar.add_child(done)

	var reset := _make_edit_button("重置", Vector2(0.0, 0.0))
	reset.pressed.connect(_on_edit_reset)
	_edit_bar.add_child(reset)


func _make_edit_button(text: String, anchor: Vector2) -> Button:
	# 走 UIKit 工厂：套游戏的金框皮，并自动挂点击音效
	var b := UIKit.button(text, Vector2(110, 44))
	# 顶部左/右角，留出安全边距
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.anchor_left = anchor.x
	b.anchor_right = anchor.x
	b.offset_left = -110.0 - 24.0 if anchor.x > 0.5 else 24.0
	b.offset_right = -24.0 if anchor.x > 0.5 else 110.0 + 24.0
	b.offset_top = 10.0
	b.offset_bottom = 54.0
	b.add_theme_font_size_override("font_size", 18)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


# ===================== 布局 =====================

func _apply_layout() -> void:
	var safe := _safe_rect()
	var scale := _size_scale(safe)
	# 摇杆
	var sdef: Dictionary = _layout.get("__stick_" + _ctx_edit_group(), {})
	var spar: Vector2 = STICK_POS
	if sdef.has("x"):
		spar = Vector2(float(sdef["x"]), float(sdef["y"]))
	var sr := STICK_RADIUS * scale
	_stick.radius = sr
	_stick.size = Vector2(sr * 2.0, sr * 2.0)
	_stick.position = _to_pixels(spar, safe) - Vector2(sr, sr)
	_stick.queue_redraw()

	for id in _buttons.keys():
		var b: TouchButton = _buttons[id]
		var def: Dictionary = _defs_by_id[id]
		var saved: Dictionary = _layout.get(id, {})
		var par: Vector2 = def.get("pos")
		var r: float = float(def.get("r"))
		if saved.has("x"):
			par = Vector2(float(saved["x"]), float(saved["y"]))
		if saved.has("r"):
			r = float(saved["r"])
		# 半径有下限：存过的旧布局（r=28）也不能低于拇指最小命中
		var rr := maxf(r, MIN_HIT_RADIUS) * scale
		b.radius = rr
		b.size = Vector2(rr * 2.0, rr * 2.0)
		b.position = _to_pixels(par, safe) - Vector2(rr, rr)
		b.queue_redraw()


## 归一化坐标 → 逻辑像素（落在安全区内，不是整块视口）
func _to_pixels(par: Vector2, safe: Rect2) -> Vector2:
	return safe.position + par * safe.size


## 尺寸缩放：**按宽高里较小的那一边**，不是只按高。
## 只按高缩放时，4:3 平板（1280×960）的摇杆圈会长到 153px 命中半径，
## 而功法列的横向间距按宽算只有 160px —— mobile_layout_audit 量出「功2 × 摇杆
## 圆心距 172 < 202」的重叠。20:9 横边更宽，min 取到高倍率，行为不变。
func _size_scale(safe: Rect2) -> float:
	return minf(safe.size.y / 720.0, safe.size.x / 1280.0)


## 刘海 / 手势条安全区，换算到逻辑视口坐标。拿不到就退回整块视口。
## ⚠ get_display_safe_area 给的是**屏幕像素**，要先减窗口位置、再按
##   「逻辑视口 / 窗口」比例缩放；headless 与窗口模式下窗口尺寸可能是 0，
##   那种情况直接用视口尺寸（等价于没有内缩）。
## 探针/调试用：非空时直接当作安全区（headless 拿不到真机内缩，只能这样验映射）
var safe_override := Rect2()


func _safe_rect() -> Rect2:
	var vp := _viewport_size()
	if safe_override.size.x > 0.0 and safe_override.size.y > 0.0:
		return safe_override
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return Rect2(Vector2.ZERO, vp)
	# get_display_safe_area 返回的是 Rect2i（整数屏幕像素），先转成浮点再换算
	var area := Rect2(DisplayServer.get_display_safe_area())
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return Rect2(Vector2.ZERO, vp)
	var k := vp / win
	var r := Rect2((area.position - Vector2(DisplayServer.window_get_position())) * k,
			area.size * k)
	var full := Rect2(Vector2.ZERO, vp)
	if not full.intersects(r):
		return full
	return full.intersection(r)


## 编辑时按编辑对象取摇杆位置；游戏中按当前场景
func _ctx_edit_group() -> String:
	return _edit_ctx if _edit else _ctx


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1280, 720)
	return vp.get_visible_rect().size


func _refresh_visibility() -> void:
	if _root == null:
		return
	var visible_any := false
	for id in _buttons.keys():
		var b: TouchButton = _buttons[id]
		var def: Dictionary = _defs_by_id[id]
		var def_ctx := String(def.get("ctx", "combat"))
		var show := _edit and def_ctx == _edit_ctx
		if not _edit:
			show = def_ctx == _ctx
		b.visible = show
		if show:
			visible_any = true
	_stick.visible = _edit or _ctx == "combat" or _ctx == "realm"
	visible_any = visible_any or _stick.visible
	_root.visible = enabled and visible_any and not _overlay_blocked
	_apply_layout()


func _apply_enabled() -> void:
	_sync_attack_mouse_binding()
	if _root == null:
		return
	_root.visible = enabled
	# 关闭时把屏幕上的半透明键盘全部收掉，避免残留按下状态
	if not enabled:
		for b in _buttons.values():
			(b as TouchButton).held = false
			(b as TouchButton).queue_redraw()
	else:
		_refresh_visibility()


## 触屏时解绑「鼠标左键 = 攻击」（2026-10-23 用户报「移动点击屏幕时会触发攻击」）
##
## 原因：安卓上 `emulate_mouse_from_touch` 会把**每一次触摸**都模拟成鼠标左键，
##   而 `attack` 动作绑着鼠标左键 → 点屏幕任何位置（拖摇杆、点 UI、点空地）都会挥刀。
##   触屏版靠虚拟「攻」键攻击（走 `Input.action_press`，不经过鼠标），所以左键可以直接摘掉。
##
## PC 上必须保留左键攻击 —— 关闭触屏时原样装回去（只改运行时 InputMap，不写盘）。
func _sync_attack_mouse_binding() -> void:
	var want_mouse := not enabled
	var found := false
	for e in InputMap.action_get_events("attack"):
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			found = true
			if not want_mouse:
				InputMap.action_erase_event("attack", e)
			break
	if want_mouse and not found:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", ev)


# ===================== 输入处理 =====================

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if _root == null or not _root.visible:
		return

	# ===== 触摸合成的鼠标事件：按落点挡 =====
	# 只在真有触摸屏时挡。PC 上手动开触屏按键时，鼠标就是「唯一那根手指」，
	# 挡掉会让调试用的鼠标点不动任何东西。
	if _has_touchscreen and (event is InputEventMouseButton or event is InputEventMouseMotion):
		var pos := _emul_mouse_pos(event)
		if _should_swallow_emul_mouse(pos):
			_eat()
		else:
			# 带触摸屏的桌面上这是**真鼠标**：也记进同一套点按判定，
			# 否则鼠标点设施会因为「没有手指记录」而永远打不开
			_track_mouse_as_finger(event, pos)
		return

	# 暂停态**不能整段退出**（2026-11-13 用户报：新手指引喊「按右键弹开」时，
	# 手游点「弹」没反应，卡死在那一步）：教学喂招、指引暂停都是 get_tree().paused=true，
	# 那时候虚拟键反而是唯一的输入手段。
	# 现在只把「摇杆」在暂停态关掉，虚拟键照常：
	#   · 摇杆在暂停态不认领按下 —— 左下角的 UI 按钮（如苍澜大陆页的「踏入」）
	#     落在摇杆命中区里，被 _eat() 吞掉就点不动（2026-10-22 那条修复仍然有效）；
	#   · 虚拟键照常认领，暂停态也能注入动作/按键。
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_handle_touch(t.index, t.position, t.pressed)
		return

	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		# 暂停态不改摇杆方向（摇杆在暂停里根本不认领按下，见 _handle_touch）
		if get_tree().paused:
			return
		_handle_drag(d.index, d.position)
		return

	# 没有真实触摸屏时（PC 上手动开启），用鼠标当单指，方便调试与验证
	if _has_touchscreen:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		_handle_touch(0, mb.position, mb.pressed)
	elif event is InputEventMouseMotion and _finger_button.has(0):
		_handle_drag(0, (event as InputEventMouseMotion).position)


func _emul_mouse_pos(e: InputEvent) -> Vector2:
	if e is InputEventMouseButton:
		return (e as InputEventMouseButton).position
	return (e as InputEventMouseMotion).position


## 触摸屏设备上的「真鼠标」也记成一根虚拟手指（index -1），
## 让 is_tap_at 对鼠标点击同样成立 —— 不然带触摸屏的笔记本就点不开设施。
func _track_mouse_as_finger(event: InputEvent, pos: Vector2) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_finger_start[-1] = {"pos": pos, "usec": Time.get_ticks_usec(), "owner": ""}
		elif _finger_start.has(-1):
			var st: Dictionary = _finger_start[-1]
			_finger_start.erase(-1)
			_settle_tap(st, pos)
		return
	if _finger_start.has(-1) and event is InputEventMouseMotion:
		(_finger_start[-1] as Dictionary)["pos"] = pos


## 这根手指现在归摇杆或某个虚拟键管吗？（正在被按住的那根，不是这一拍的落点）
func _pad_finger_down() -> bool:
	return _stick_finger != -1 or not _finger_button.is_empty()


## 要不要挡掉这条由触摸合成的鼠标事件。
## · 摇杆/按键正被按住 → 全挡：手指从摇杆滑到别处抬手时，那一下「点击」不是玩家的本意
## · 落点在摇杆召唤区或虚拟键圈内 → 挡：这一拍 press 比 ScreenTouch 还先到，
##   只能按落点判，不能等状态（实测事件序见 tools/probe_touch_mouse_emu.gd）
## · 暂停态只认第一条：面板开着时，摇杆圈底下的按钮还得能点
##   （2026-10-22「踏入」按钮就是这么救回来的，不能反过来又挡回去）
func _should_swallow_emul_mouse(pos: Vector2) -> bool:
	if _pad_finger_down():
		return true
	return not get_tree().paused and _owns_point(pos)


## 这一点归不归摇杆/虚拟键管（含命中放宽与动态摇杆召唤区）
func _owns_point(pos: Vector2) -> bool:
	if _edit:
		return false
	# 浮层（说明卡）画在虚拟键上面：它的矩形里要让路，不然按钮永远点不着
	for r in _pass_rects:
		if (r as Rect2).has_point(pos):
			return false
	if _stick.visible and (_stick.hit(pos) or _stick_zone_rect().has_point(pos)):
		return true
	return _button_at(pos) != ""


func _stick_zone_rect() -> Rect2:
	var s := _safe_rect()
	return Rect2(s.position + STICK_ZONE.position * s.size, STICK_ZONE.size * s.size)


## 世界/设施能不能把这次鼠标事件当成「一次点按」。
## ⚠ 合成鼠标的 release 比 ScreenTouch 的 release 先到，所以读的是
##   「还按着的那根手指」的实时状态，而不是抬起之后才写的记录。
## PC（没开触屏按键）恒为 true：鼠标本来就是点击，不参与这套判定。
func is_tap_at(pos: Vector2) -> bool:
	if not enabled or not _has_touchscreen:
		return true
	for idx in _finger_start.keys():
		var st: Dictionary = _finger_start[idx]
		if String(st["owner"]) != "":
			continue
		if (st["pos"] as Vector2).distance_to(pos) > TAP_MAX_MOVE:
			continue
		if float(Time.get_ticks_usec() - int(st["usec"])) / 1_000_000.0 > TAP_MAX_TIME:
			continue
		return true
	# 已经结算完的点按（真鼠标那一路在同一拍里就判完了，记录比事件晚一拍到 GUI）
	if not _last_tap.is_empty() \
			and Time.get_ticks_usec() - int(_last_tap["usec"]) < 100_000 \
			and (_last_tap["pos"] as Vector2).distance_to(pos) <= TAP_MAX_MOVE:
		return true
	return false


func _handle_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		_finger_start[idx] = {"pos": pos, "usec": Time.get_ticks_usec(), "owner": ""}
		# ---- 编辑模式：抓住命中的键拖动 ----
		if _edit:
			var eid := _button_at(pos)
			if eid != "":
				var eb: TouchButton = _buttons[eid]
				_finger_button[idx] = eid
				_finger_start[idx]["owner"] = eid
				_drag_off = pos - (eb.position + Vector2(eb.radius, eb.radius))
				# 给「抓住了」的视觉反馈；_press_button 在编辑模式下不会往游戏里注入输入
				_press_button(eid, true)
				_eat()
			return
		# ---- 按键优先于摇杆 ----
		# ⚠ 顺序很重要：摇杆的命中范围比它看起来大（手指偏一点也算），
		#   如果先判摇杆，靠得近的「功/宝」键会被它抢走（实测 headless 下必现）。
		#   小控件优先命中，摇杆吃剩下的区域。
		var id := _button_at(pos)
		if id != "":
			_finger_button[idx] = id
			_finger_start[idx]["owner"] = id
			_press_button(id, true)
			_eat()
			return
		# ---- 摇杆（动态：按下点就是圆心，不必摸到画出来的那个圈）----
		# ⚠ 暂停态整段跳过：摇杆命中区底下可能压着面板按钮（苍澜大陆页的「踏入」），
		#   在这里认领就等于把那一发点击吞掉。虚拟键不受这条限制 —— 教学喂招
		#   暂停时它是手游玩家唯一的输入手段（2026-11-13「按弹刀没反应」就是这么卡的）。
		if get_tree().paused:
			return
		if _stick.visible and (_stick.hit(pos) or _stick_zone_rect().has_point(pos)):
			_stick_finger = idx
			_finger_start[idx]["owner"] = "__stick"
			_place_stick(pos)
			# ⚠ 这一拍**不产生方向**：以前这里直接 _update_stick(pos)，等于把
			#   「圆心到按下点」的向量当成摇杆量 —— 一按就朝按下点窜一步，
			#   方向还是随机的，正好把人送到别的设施上（误触的另一半成因）。
			_eat()
		return

	# ---- 抬起 ----
	var had := _finger_start.has(idx)
	var st: Dictionary = _finger_start.get(idx, {})
	_finger_start.erase(idx)
	if idx == _stick_finger:
		_stick_finger = -1
		_release_stick()
		_home_stick()
		_eat()
		return
	if _finger_button.has(idx):
		var bid: String = _finger_button[idx]
		_finger_button.erase(idx)
		_press_button(bid, false)
		if _edit:
			_save_config()          # 拖一次存一次，不怕误退出
		_eat()
		return
	# 场景区那根手指：抬起时结算一次「点按」（滑出阈值就不算）
	if had and String(st.get("owner", "")) == "":
		_settle_tap(st as Dictionary, pos)


## 记下这一下是不是点按（供 is_tap_at 之外的事后判断/探针读取）
func _settle_tap(st: Dictionary, end: Vector2) -> void:
	var sp: Vector2 = st["pos"]
	var dt := float(Time.get_ticks_usec() - int(st["usec"])) / 1_000_000.0
	if sp.distance_to(end) <= TAP_MAX_MOVE and dt <= TAP_MAX_TIME \
			and not _owns_point(end) and not _owns_point(sp):
		_last_tap = {"pos": end, "usec": Time.get_ticks_usec()}
	else:
		_last_tap = {}


## 最近一次判定的点按（{} = 没有）。探针与调试用。
func last_tap() -> Dictionary:
	return _last_tap


## 动态摇杆：把圆心挪到按下点，整圈夹在安全区内
func _place_stick(pos: Vector2) -> void:
	var safe := _safe_rect()
	var r := _stick.radius
	var c := Vector2(clampf(pos.x, safe.position.x + r, safe.end.x - r),
			clampf(pos.y, safe.position.y + r, safe.end.y - r))
	_stick.position = c - Vector2(r, r)
	_stick.knob = Vector2.ZERO
	_stick.queue_redraw()


## 抬手后回默认位（默认位仍可由玩家在布局编辑里拖动保存）
func _home_stick() -> void:
	_apply_layout()


func _handle_drag(idx: int, pos: Vector2) -> void:
	if _edit:
		if not _finger_button.has(idx):
			return
		var id: String = _finger_button[idx]
		var b: TouchButton = _buttons[id]
		var safe := _safe_rect()
		var center := pos - _drag_off
		# 夹在安全区内，别把按键拖到刘海/手势条底下
		var r := b.radius
		center.x = clampf(center.x, safe.position.x + r, safe.end.x - r)
		center.y = clampf(center.y, safe.position.y + r, safe.end.y - r)
		b.position = center - Vector2(r, r)
		_layout[id] = {"x": (center.x - safe.position.x) / maxf(1.0, safe.size.x),
				"y": (center.y - safe.position.y) / maxf(1.0, safe.size.y),
				"r": b.radius / maxf(0.001, _size_scale(safe))}
		_eat()
		return

	if idx == _stick_finger:
		if _finger_start.has(idx):
			(_finger_start[idx] as Dictionary)["pos"] = pos
		_update_stick(pos)
		_eat()


## 圆形命中（半径放宽 BUTTON_HIT_SLACK，手指没那么准）
func _button_at(pos: Vector2) -> String:
	var ids := _buttons.keys()
	for i in range(ids.size() - 1, -1, -1):
		var id: String = ids[i]
		var b: TouchButton = _buttons[id]
		if not b.visible:
			continue
		var c := b.position + Vector2(b.radius, b.radius)
		if pos.distance_to(c) <= b.radius * BUTTON_HIT_SLACK:
			return id
	return ""


## 标记事件已处理：避免同一根手指同时点击到下面的 UI
func _eat() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


# ===================== 摇杆 =====================

func _update_stick(pos: Vector2) -> void:
	if _stick == null:
		return
	var c := _stick.position + _stick.size * 0.5
	var raw := (pos - c) / maxf(1.0, _stick.radius)
	var length := raw.length()
	if length > 1.0:
		raw = raw.normalized()
	_stick.knob = raw * _stick.radius * 0.55
	_stick.queue_redraw()
	# 死区以下不产生移动（防手抖）；推到半径的 92% 就是满舵，拇指不必顶到圈边
	var mag := clampf((length - STICK_DEADZONE)
			/ maxf(0.001, STICK_SATURATE - STICK_DEADZONE), 0.0, 1.0)
	var dir := raw.normalized() * mag
	_set_action_strength("move_right", maxf(0.0, dir.x))
	_set_action_strength("move_left", maxf(0.0, -dir.x))
	_set_action_strength("move_down", maxf(0.0, dir.y))
	_set_action_strength("move_up", maxf(0.0, -dir.y))


func _release_stick() -> void:
	if _stick != null:
		_stick.knob = Vector2.ZERO
		_stick.queue_redraw()
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


func _set_action_strength(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, minf(1.0, strength))
	else:
		Input.action_release(action)


# ===================== 按键 =====================

func _press_button(id: String, down: bool) -> void:
	if not _buttons.has(id):
		return
	var b: TouchButton = _buttons[id]
	# 边界判定：同一键可能被两根手指先后按，只认第一次
	if b.held == down:
		return
	b.held = down
	b.queue_redraw()
	if _edit:
		return      # 编辑模式只拖动，不往游戏里注入输入

	var kind := String(b.def.get("kind", "key"))
	if kind == "action":
		var act := String(b.def.get("value", ""))
		if act == "":
			return
		if down:
			Input.action_press(act)
		else:
			Input.action_release(act)
		# ⚠ 只改状态不够，必须**再补一发 InputEventAction**：
		#   `Input.action_press()` 不产生任何事件，而项目里有按事件读的写法 ——
		#   tutorial_overlay 判的是 `event.is_action_pressed("parry")`，
		#   于是手游玩家在新手指引里点「弹」永远没反应，整步卡死（2026-11-13 用户报）。
		#   轮询型调用方（player 的 is_action_just_pressed）不受影响：状态已经先置好了。
		var ev := InputEventAction.new()
		ev.action = act
		ev.pressed = down
		ev.strength = 1.0 if down else 0.0
		Input.parse_input_event(ev)
		return

	var code := int(b.def.get("value", 0))
	if code == 0:
		return
	_virtual_keys[code] = down
	_inject_key(code, down)


## 合成键盘事件：让项目里所有 `event.physical_keycode == KEY_X` 的判断自动生效
## （F 进入设施 / C 重开 / F 拾取 / ESC 返回 / Tab 角色面板 / Y 功法库）
func _inject_key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	ev.echo = false
	Input.parse_input_event(ev)


func _release_all() -> void:
	for id in _buttons.keys():
		var b: TouchButton = _buttons[id]
		b.held = false
		b.queue_redraw()
		# ⚠ action 类（攻/闪/弹/移动）不走 _virtual_keys，必须显式释放，
		#   否则关掉触屏后这些动作会一直是「按下」状态
		if String(b.def.get("kind", "key")) == "action":
			var act := String(b.def.get("value", ""))
			if act != "":
				Input.action_release(act)
	for code in _virtual_keys.keys():
		if bool(_virtual_keys[code]):
			_inject_key(int(code), false)
	_virtual_keys.clear()
	_finger_button.clear()
	_finger_start.clear()
	_last_tap.clear()
	_stick_finger = -1
	_release_stick()


# ===================== 编辑栏回调 =====================

func _on_edit_done() -> void:
	exit_edit_mode(true)


func _on_edit_reset() -> void:
	reset_layout(_edit_ctx)
	_apply_layout()


func _show_edit_bar(v: bool) -> void:
	if _edit_bar != null:
		_edit_bar.visible = v


# ===================== 存档 =====================

var _config: Dictionary = {}


func _config_flag() -> bool:
	if _config.has("enabled"):
		return bool(_config["enabled"])
	# 没存过：有触摸屏默认开（安卓），PC 默认关
	return _has_touchscreen


func _load_config() -> void:
	_config = {}
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		_config = parsed
	var lay = _config.get("layout", {})
	if lay is Dictionary:
		_layout = lay


func _save_config() -> void:
	_config["enabled"] = enabled
	_config["layout"] = _layout
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("触屏配置写入失败：" + CONFIG_PATH)
		return
	f.store_string(JSON.stringify(_config, "\t"))
	f.close()


# ===================== 子控件 =====================

class TouchButton extends Control:
	var def: Dictionary = {}
	var label := ""
	var radius := 40.0
	var held := false
	# 配色由外部构建时注入（内部类读不到外部脚本的 const）
	var c_fill := Color(0.07, 0.09, 0.13, 0.52)
	var c_fill_held := Color(0.30, 0.55, 0.75, 0.78)
	var c_border := Color(0.82, 0.74, 0.50, 0.55)
	var c_border_edit := Color(1.00, 0.86, 0.35, 0.95)
	var c_text := Color(0.94, 0.92, 0.86, 0.95)
	## 不可用态（主城「进入」键没靠近设施时压暗）
	var dim := false
	var _label_node: Label

	func _ready() -> void:
		_label_node = Label.new()
		_label_node.text = label
		_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label_node)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_restyle()

	## 键面文字：主城「进入」键要显设施名，长度不固定
	func set_text(t: String) -> void:
		if label == t:
			return
		label = t
		if _label_node != null:
			_label_node.text = t
		_restyle()

	func set_dim(v: bool) -> void:
		if dim == v:
			return
		dim = v
		_restyle()
		queue_redraw()

	func _restyle() -> void:
		if _label_node == null:
			return
		var size := maxf(12.0, radius * 0.62)
		# 汉字宽度≈字号：按字数缩到圈里放得下（「装备锻造台」五字不能溢出）
		var n := label.length()
		if n > 2:
			size = minf(size, maxf(11.0, radius * 1.7 / float(n)))
		_label_node.add_theme_font_size_override("font_size", int(size))
		_label_node.add_theme_color_override("font_color",
				Color(c_text.r, c_text.g, c_text.b, 0.45) if dim else c_text)

	func _draw() -> void:
		var c := Vector2(radius, radius)
		var fill := c_fill_held if held else c_fill
		if dim:
			fill = Color(fill.r, fill.g, fill.b, fill.a * 0.55)
		draw_circle(c, radius, fill)
		var border := c_border_edit if held else c_border
		if dim:
			border = Color(border.r, border.g, border.b, border.a * 0.45)
		draw_arc(c, radius - 1.5, 0.0, TAU, 40, border, 2.0, true)
		if held:
			draw_arc(c, radius - 5.0, 0.0, TAU, 40, c_border_edit, 1.5, true)


class TouchStick extends Control:
	var radius := 92.0
	var knob := Vector2.ZERO
	## 命中放宽（外部脚本的 const 在内部类里读不到，构建时注入）
	var hit_slack := 1.25
	var c_base := Color(0.07, 0.09, 0.13, 0.35)
	var c_border := Color(0.82, 0.74, 0.50, 0.55)
	var c_knob := Color(0.75, 0.80, 0.88, 0.62)

	func hit(pos: Vector2) -> bool:
		var c := position + size * 0.5
		return pos.distance_to(c) <= radius * hit_slack

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, radius, c_base)
		draw_arc(c, radius, 0.0, TAU, 48, c_border, 2.0, true)
		draw_circle(c + knob, radius * 0.34, c_knob)
