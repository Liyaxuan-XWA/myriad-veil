extends Node
## 指引在「无关界面」上必须消失（2026-11-12 用户定）
## 用法：godot --headless --path . res://tools/probe_tutorial_modal.tscn -- --no-save
##
## 判据口径：
##   · 用真实表现层（Tutorial 自建的 TutorialOverlay）与真实面板（DomainPanel / ConfirmDialog），
##     只把「当前步骤」按步骤表的结构合成出来 —— 步骤表本来就是数据；
##   · 三件事都要成立：无关界面开着 ⇒ 藏；关掉 ⇒ 自己回来且**步骤没被完成**；
##     锚点就在那层界面里 ⇒ 面板开着也照样露脸。

var _passes := 0
var _fails: Array = []
var _saved_step: Dictionary = {}


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _overlay() -> Node:
	# ⚠ 表现层是 Tutorial（autoload）自己的子节点，不在 root 下
	return Tutorial.get_node_or_null("TutorialOverlay")


func _set_step(step: Dictionary) -> void:
	Tutorial.active_step = step
	Tutorial.changed.emit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("\n########## 指引 · 无关界面遮挡 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	var ov := _overlay()
	_check(ov != null, "取到指引表现层")
	if ov == null:
		return
	_saved_step = Tutorial.active_step
	var card: Control = ov.get("_card")

	# ===== 1. 没有界面遮挡：卡片在 =====
	_set_step({"id": "__probe_a__", "text": "测试指引", "tip": "", "manual": true})
	await _frames(3)
	_check(card.visible, "没有模态界面时：卡片照常显示")

	# ===== 2. 开一个无关界面（万界秘境）：指引必须消失 =====
	var panel = DomainPanel.new()
	get_tree().root.add_child.call_deferred(panel)
	await _frames(2)
	panel.open()
	await _frames(4)
	_check(not card.visible and not bool(ov.get("_has_target")),
			"开着无关界面：「位面星图」这种模态一开，指引就消失")
	_check(GameState.top_modal() == panel, "模态栈的最上层就是它", str(GameState.top_modal()))

	# ===== 3. 关掉：自己回来，且步骤没被完成 =====
	panel.close()
	await _frames(4)
	_check(card.visible, "关掉界面：指引自己回来（回到相关场景才显示）")
	_check(String(Tutorial.active_step.get("id", "")) == "__probe_a__",
			"全程没有把步骤判完成（只有完成/跳过才永久消失）",
			String(Tutorial.active_step.get("id", "")))

	# ===== 4. 锚点就在那层界面里：面板开着也露脸 =====
	_set_step({"id": "__probe_b__", "text": "面板内指引", "anchor": "meta:panel", "manual": true})
	var panel2 = DomainPanel.new()
	get_tree().root.add_child.call_deferred(panel2)
	await _frames(2)
	panel2.open()
	await _frames(5)
	_check(card.visible, "锚点落在该界面里：面板开着也露脸")

	# ===== 5. 再叠一层无关界面（确认框）：仍然藏 =====
	var dlg := ConfirmDialog.ask("测试", "确认框叠在面板上面", "好", "取消", Callable(), false)
	await _frames(4)
	_check(not card.visible, "锚点不在最上层那个界面里：照样藏起来")
	dlg.call("_cancel")
	await _frames(4)
	_check(card.visible, "确认框关掉：又回到「锚点所属界面」这一层，指引回来")

	# 收尾
	panel2.close()
	await _frames(2)
	Tutorial.active_step = _saved_step
	Tutorial.changed.emit()
	await _frames(2)
	print("")
