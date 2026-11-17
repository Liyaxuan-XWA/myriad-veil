extends Node
## 虚拟键「什么时候不该显示」自检（2026-11-13 用户：开始界面/棋坛这些界面不要冒虚拟键）
## 用法：godot --headless --path . --quit-after 200000 res://tools/probe_pad_context.tscn -- --no-save
##
## ⚠ 全程只改运行时字段（不调 set_enabled），绝不写 user://touch_ui.json。

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 虚拟键显示时机 ##########")
	var was := bool(VirtualPad.is_touch_enabled())
	VirtualPad.set("_has_touchscreen", true)
	VirtualPad.enabled = true
	VirtualPad.call("_apply_enabled")
	await _frames(3)

	var root: Control = VirtualPad.get("_root")
	var stick: Control = VirtualPad.get("_stick")

	# ===== 0. 默认值就是 none：autoload 跨场景活着，不声明就一个键都不该摆 =====
	_check(String(VirtualPad.get("_ctx")) == "none", "默认 ctx=none（开局不会冒虚拟键）",
		String(VirtualPad.get("_ctx")))

	# ===== 1. 没声明过场景 = 一个键都不摆（默认 none）=====
	VirtualPad.set_context("none")
	await _frames(2)
	_check(not root.visible, "ctx=none → 虚拟键整层不显示", "visible=%s" % root.visible)
	_check(not stick.visible, "ctx=none → 摇杆也不显示", "visible=%s" % stick.visible)

	# ===== 2. 玩法场景照旧 =====
	VirtualPad.set_context("realm")
	await _frames(2)
	_check(root.visible and stick.visible, "ctx=realm → 主城那组照常显示",
		"root=%s stick=%s" % [root.visible, stick.visible])
	VirtualPad.set_context("combat")
	await _frames(2)
	_check(root.visible and stick.visible, "ctx=combat → 战斗那组照常显示",
		"root=%s stick=%s" % [root.visible, stick.visible])
	VirtualPad.set_context("none")

	# ===== 3. 开始界面自己会收起虚拟键 =====
	VirtualPad.set_context("realm")     # 模拟「从玩法退回开始界面」：上一场景的 ctx 还留着
	await _frames(2)
	_check(root.visible, "前提：退回开始界面前虚拟键还显示着")
	var title: Node = (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate()
	add_child(title)
	await _frames(8)
	_check(String(VirtualPad.get("_ctx")) == "none", "开始界面 _ready 后 ctx=none",
		String(VirtualPad.get("_ctx")))
	_check(not root.visible, "开始界面上虚拟键不显示", "visible=%s" % root.visible)
	title.queue_free()
	await _frames(4)

	# ===== 4. 棋坛卷面同样收起 =====
	VirtualPad.set_context("realm")     # 模拟「从主城进棋坛」：上一场景的 ctx 还留着
	await _frames(2)
	_check(root.visible, "前提：从主城过来时虚拟键本来是显示的")
	var ms: Node = (load("res://scenes/match/match_level_scroll.tscn") as PackedScene).instantiate()
	add_child(ms)
	await _frames(10)
	_check(String(VirtualPad.get("_ctx")) == "none", "棋坛卷面 _ready 后 ctx=none",
		String(VirtualPad.get("_ctx")))
	_check(not root.visible, "棋坛卷面上虚拟键不显示", "visible=%s" % root.visible)
	ms.queue_free()
	await _frames(4)

	# ===== 5. 回主城要能重新显示（autoload 别把 none 记死）=====
	VirtualPad.set_context("realm")
	await _frames(2)
	_check(root.visible and stick.visible, "回到玩法场景 ctx=realm → 虚拟键回来",
		"root=%s stick=%s" % [root.visible, stick.visible])

	# 还原
	VirtualPad.call("_release_all")
	VirtualPad.set("enabled", was)
	VirtualPad.set("_has_touchscreen", false)
	VirtualPad.call("_apply_enabled")
	print("  触屏开关已还原为跑之前的 ", was, "（全程没写 touch_ui.json）")
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())
