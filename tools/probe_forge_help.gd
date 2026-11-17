extends Node
## 锻造说明：左上角小木牌 + 说明层（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_forge_help.tscn -- --no-save
##
## 用户三件事：
##   ① 指引「装备强化」里，在「失败 20%」下面补一条进阶失败：只重置强化次数，词条不减少；
##   ② 「进阶」里补一条进阶成功时属性额外涨多少（按当前值 +50%）；
##   ③ 锻造界面左上角加一块小木牌「锻造说明」，点开看这份完整说明。
## 判据：文案顺序 / 木牌位置与点击链路 / 说明层内容 / ESC 路径能收起。

const FAIL_LINE := "进阶失败：只重置当前的强化次数（等级归零），装备词条不会减少；磨损 +1（同样累计 10 次破损）。"
const GAIN_LINE := "进阶成功时，每条可强化词条按当前值额外 +50%（力量 20 → 30）；法宝改为提升召唤物属性与时长。"

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
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("\n########## 锻造说明 · 木牌与文案 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _labels_under(node: Node) -> String:
	var out: Array[String] = []
	for c in node.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	return "\n".join(out)


func _run() -> void:
	# ===== 1. 文案表：两条新说明在正确的小节与顺序 =====
	var idx := GuideDB.chapter_index_by_id("enhance")
	var blocks := GuideDB.chapter_blocks(idx)
	var pos_fail := -1
	var pos_fail20 := -1
	var pos_gain := -1
	var pos_section := -1
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		var x := String(b.get("x", ""))
		if x.begins_with("失败 20%"):
			pos_fail20 = i
		if x == FAIL_LINE:
			pos_fail = i
		if x == GAIN_LINE:
			pos_gain = i
		if String(b.get("t", "")) == "s" and x == "进阶":
			pos_section = i
	_check(pos_fail >= 0, "「进阶失败」这条在表里", str(pos_fail))
	_check(pos_fail == pos_fail20 + 1, "它紧跟在「失败 20%」下面",
		"失败20%%@%d 进阶失败@%d" % [pos_fail20, pos_fail])
	_check(pos_gain > pos_section and pos_section >= 0, "「进阶 +50%」这条在「进阶」小节里",
		"进阶@%d +50%%@%d" % [pos_section, pos_gain])

	# ===== 2. 木牌：左上角、可点 =====
	var panel := ForgePanel.new()
	add_child(panel)
	await _frames(3)
	panel.call("open")
	await _frames(6)
	var sign := panel.get("_help_sign") as Button
	_check(sign != null, "锻造台建出「锻造说明」木牌")
	if sign == null:
		return
	_check(sign.text == "锻造说明", "木牌写着「锻造说明」", sign.text)
	_check(sign.visible, "木牌可见")
	var sr := sign.get_global_rect()
	_check(sr.position.x <= 40.0 and sr.position.y >= 92.0 and sr.position.y <= 170.0,
		"木牌在界面左上角（木梁下方）", str(sr))
	_check(sr.size.x >= 96.0 and sr.size.y >= 28.0, "木牌放得下四个字", str(sr.size))
	var plaque_title: Control = null
	for c in (panel.get("_topbar") as Node).get_children():
		if c is PanelContainer:
			plaque_title = c as Control
			break
	_check(plaque_title != null and not sr.intersects(plaque_title.get_global_rect()),
		"不压在「锻造工坊」标题牌上",
		"%s vs %s" % [sr, plaque_title.get_global_rect()] if plaque_title != null else "无标题")

	# ===== 3. 点木牌 → 说明层出现，内容与指引书同源 =====
	sign.pressed.emit()
	await _frames(4)
	var layer: Control = panel.get("_help_layer") as Control
	_check(layer != null and is_instance_valid(layer), "点木牌真的弹出说明层")
	if layer == null:
		return
	var txt := _labels_under(layer)
	_check(txt.contains(FAIL_LINE), "说明层里有「进阶失败」那条")
	_check(txt.contains(GAIN_LINE), "说明层里有「进阶 +50%」那条")
	_check(txt.contains("失败 20%") and txt.contains("破损") and txt.contains("进阶"),
		"整页包含了强化 / 破损 / 进阶三节")
	var box_ok := false
	for c in layer.get_children():
		if c is PanelContainer:
			var br := (c as Control).get_global_rect()
			box_ok = br.position.x >= 0.0 and br.position.y >= 0.0 \
				and br.end.x <= 1280.0 and br.end.y <= 720.0
	_check(box_ok, "说明层不出屏幕")

	# ===== 4. 收起：走 ESC 同一条 _close_top_overlay =====
	var closed := bool(panel.call("_close_top_overlay"))
	await _frames(2)
	_check(closed and panel.get("_help_layer") == null, "「收起」/ ESC 能关掉说明层")
	# 再开一次，用说明层自己的收起按钮
	sign.pressed.emit()
	await _frames(3)
	_check(panel.get("_help_layer") != null, "可以重复打开")
	panel.call("_close_forge_help")
	await _frames(2)
	_check(panel.get("_help_layer") == null, "说明层的收起按钮也能关")
	panel.call("close")
	await _frames(2)
	print("")
