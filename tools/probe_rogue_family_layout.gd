extends Node
## 试炼入口页 · 切换 12 套流派时的几何自检（2026-11-08）
## 用户报「选择不同的流派时会导致面板变形」：把每次切换后的面板尺寸、左右栏宽度、
## 「踏入试炼」按钮绝对位置全部量出来，任何一个量随流派漂移都算失败。
## 用法：godot --headless --path . res://tools/probe_rogue_family_layout.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _geo(panel: TowerPanel) -> Dictionary:
	var root: Control = panel.get("_root")
	# 从已命名的容器拿（_build_rogue_page 里写了 name）
	var info: VBoxContainer = panel.get("_rogue_info_box")
	if info == null:
		return {}
	var left: Control = info.get_parent() as Control
	var main_node: Control = left.get_parent() as Control
	var right: Control = main_node.get_node_or_null("RogueRight") as Control
	var btn: Button = panel.get("_rogue_enter_btn")
	return {
		"root": root.size,
		"main": main_node.size if main_node != null else Vector2.ZERO,
		"left_w": left.size.x if left != null else -1.0,
		"right_w": right.size.x if right != null else -1.0,
		"info_h": info.size.y,
		"btn": btn.global_position if btn != null else Vector2.ZERO,
	}


func _same(a: Dictionary, b: Dictionary, key: String) -> bool:
	if not a.has(key) or not b.has(key):
		return false
	var x: Variant = a[key]
	var y: Variant = b[key]
	if x is Vector2 and y is Vector2:
		return (x as Vector2).is_equal_approx(y as Vector2)
	return is_equal_approx(float(x), float(y))


func _run() -> void:
	print("\n########## 试炼入口页 · 12 流派切换几何 ##########")
	var old_best := CharacterData.rogue_best_floor
	CharacterData.rogue_best_floor = 50          # 全解锁，才能逐一切
	var panel := TowerPanel.new()
	# ⚠ _ready 栈帧里 root 正在布置 children → 必须 call_deferred（否则面板脱树）
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	panel.call("_switch_tab", 1)
	await get_tree().process_frame
	await get_tree().process_frame

	# ===== 入口可见性（2026-11-08 用户报「试炼之路入口不明显」）=====
	var tabs: Array = panel.get("_tab_buttons")
	_check(tabs.size() == 2, "顶部有 2 个玩法页签", str(tabs.size()))
	var tab_tone := true
	var tall := true
	for b in tabs:
		var tb := b as Button
		if tb == null or String(tb.get("tone")) != "tab":
			tab_tone = false
		if tb == null or tb.custom_minimum_size.y < 40.0:
			tall = false
	_check(tab_tone, "页签走 tab 皮肤（有底，选中/未选中可辨）")
	_check(tall, "页签高度 ≥ 40，不再是一行暗字")
	var tag: Control = null
	var hint: Control = null
	var stack: Array = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "RogueNewTag":
			tag = n as Control
		if n.name == "RogueTabHint":
			hint = n as Control
		for c in n.get_children():
			stack.append(c)
	_check(tag != null and tag.visible, "试炼之路带朱砂「新玩法」标记")
	_check(hint != null and hint.visible, "页签右侧有切换引导语")
	_check(bool((tabs[1] as Button).call("is_selected")),
		"切到试炼页后该页签呈选中态")

	var root: Control = panel.get("_root")
	if root == null or panel.get("_rogue_info_box") == null:
		_check(false, "入口页构建成功")
		CharacterData.rogue_best_floor = old_best
		return
	_check(true, "入口页构建成功", str(root.size))

	var first: Dictionary = {}
	var drifting: Array[String] = []
	var checked := 0
	for raw_fam in RogueDB.FAMILY_ORDER:
		var fam := String(raw_fam)
		panel.call("_on_pick_family", fam)
		await get_tree().process_frame
		await get_tree().process_frame
		var g := _geo(panel)
		if g.is_empty():
			drifting.append(fam + "(几何读取失败)")
			continue
		checked += 1
		if first.is_empty():
			first = g
			print("    基准 %-10s root=%s left=%.1f right=%.1f info_h=%.1f btn=%s" % [
				fam, str(g["root"]), float(g["left_w"]), float(g["right_w"]),
				float(g["info_h"]), str(g["btn"])])
		else:
			for key in ["root", "main", "left_w", "right_w", "btn"]:
				if not _same(first, g, key):
					drifting.append("%s:%s(%s→%s)" % [fam, key, str(first[key]), str(g[key])])
			print("    %-10s left=%.1f right=%.1f info_h=%.1f" % [
				fam, float(g["left_w"]), float(g["right_w"]), float(g["info_h"])])

	_check(checked == RogueDB.FAMILY_ORDER.size(),
		"%d 套流派全部可切换并测量" % RogueDB.FAMILY_ORDER.size(), str(checked))
	_check(drifting.is_empty(), "切换流派不引起任何几何漂移",
		"无" if drifting.is_empty() else "、".join(drifting))

	# 内容不能被裁：左栏文字全部落在面板内
	var info: VBoxContainer = panel.get("_rogue_info_box")
	var overflow := 0
	for c in info.get_children():
		var l := c as Control
		if l != null and l.size.x > (info.size.x + 1.0):
			overflow += 1
	_check(overflow == 0, "左栏文案没有横向溢出", str(overflow))

	# ===== 0 层解锁面（2026-11-09：符箓改为初始开放）=====
	# ⚠ 只断言 FAMILY_UNLOCK_FLOOR 的数值抓不到「表改了但入口没读」，
	#   这里读**真实按钮的 disabled**，走的是刷新入口 `_refresh_family_picker()`。
	CharacterData.rogue_best_floor = 0
	panel.call("_refresh_family_picker")
	await get_tree().process_frame
	var open_at_zero: Array[String] = []
	var locked_at_zero: Array[String] = []
	for b in panel.get("_rogue_family_buttons"):
		var bb := b as Button
		if bb == null:
			continue
		var key := String(bb.get_meta("family", ""))
		if bb.disabled:
			locked_at_zero.append(key)
		else:
			open_at_zero.append(key)
	_check(open_at_zero.has("talisman"), "历史最高 0 层：符箓按钮可点",
		"、".join(open_at_zero))
	_check(locked_at_zero.has("yinyang"), "历史最高 0 层：两仪仍锁（需第 5 层）",
		"、".join(locked_at_zero))
	_check(open_at_zero.size() == 4, "历史最高 0 层恰好开放 4 套", str(open_at_zero.size()))
	CharacterData.rogue_best_floor = old_best
	panel.call("_refresh_family_picker")

	panel.call("close")
	CharacterData.rogue_best_floor = old_best
