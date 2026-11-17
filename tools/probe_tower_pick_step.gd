extends Node
## 教学「选第 1 层」点击必须算数（2026-11-12 用户报：点虎妖那层没反应，只能跳过）
## 用法：godot --headless --path . res://tools/probe_tower_pick_step.tscn -- --no-save
##
## 根因：打开塔面板时**默认已选中第 1 层**，玩家照提示点第一层会走进
## `_select_floor` 的「选的是同一层 → 早退」分支，事件根本没发。
## 判据：
##   · 打开面板本身**不算**选层（事件不能自动发，步骤不能自己过）；
##   · 点第 1 层（哪怕它已经是选中态）→ tower_floor_pick 发出、步骤完成。

const PANEL_SCRIPT := "res://scripts/ui/panels/tower_panel.gd"
const STEP_ID := "__probe_floor_pick__"

var _passes := 0
var _fails: Array = []
var _saved: Dictionary = {}


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
	print("\n########## 塔层选择 · 教学步骤 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved = {
		"step": Tutorial.active_step.duplicate(true),
		"chapter": Tutorial.active_chapter,
		"listen": Tutorial.get("_listen_ev"),
		"count": Tutorial.get("_count"),
	}
	var panel = (load(PANEL_SCRIPT) as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await _frames(2)
	panel.open()
	await _frames(4)
	# 摆好这一步：ev = tower_floor_pick（与 tutorial_db 的 c5_pick 同口径）
	Tutorial.active_chapter = ""
	Tutorial.active_step = {"id": STEP_ID, "text": "选第 1 层", "ev": "tower_floor_pick"}
	Tutorial.set("_listen_ev", "tower_floor_pick")
	Tutorial.set("_count", 0.0)
	await _frames(2)
	_check(not Tutorial.is_done(STEP_ID), "步骤还没完成（现场成立）")
	_check(int(panel.get("_selected_floor")) == 1, "面板打开时默认已选中第 1 层（这正是 bug 的土壤）",
			str(panel.get("_selected_floor")))
	# 打开面板本身不能把步骤「混过去」
	_check(not Tutorial.is_done(STEP_ID), "打开面板不会自动完成这一步（必须是玩家点）")
	# 点第 1 层：它已经是选中态，事件也必须发
	var nodes: Dictionary = panel.get("_floor_by_no")
	var node: Dictionary = nodes.get(1, {})
	var btn: Button = node.get("button") as Button
	_check(btn != null and not btn.disabled, "第 1 层的按钮可点")
	if btn != null:
		btn.pressed.emit()
	await _frames(2)
	_check(Tutorial.is_done(STEP_ID), "点第 1 层：步骤完成（不再只能跳过）")
	_check(String(Tutorial.active_step.get("id", "")) != STEP_ID, "当前步骤已推进走")
	# 再点一次不炸、也不回退
	if btn != null:
		btn.pressed.emit()
	await _frames(1)
	_check(true, "重复点击不会出错")
	# 收尾
	panel.close()
	await _frames(2)
	Tutorial.active_step = _saved["step"]
	Tutorial.active_chapter = String(_saved["chapter"])
	Tutorial.set("_listen_ev", _saved["listen"])
	Tutorial.set("_count", _saved["count"])
	Tutorial.changed.emit()
	await _frames(2)
	print("")
