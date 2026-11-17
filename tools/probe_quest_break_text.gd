extends Node
## 「突破境界」任务介绍补了第二段（2026-11-12 用户定）
## 用法：godot --headless --path . res://tools/probe_quest_break_text.tscn -- --no-save
##
## 判据：任务表里这一条有两段（原文 + 修为来源），且当它轮到「当前任务」时，
## 面板拿去显示的就是这段原文（面板是逐字复制 detail，不加工）。

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


func _ready() -> void:
	print("\n########## 任务「突破境界」介绍文案 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	get_tree().quit(_fails.size())


func _run() -> void:
	var q := QuestDB.get_quest("q_break_realm")
	_check(not q.is_empty(), "任务表里取得到「突破境界」")
	var detail := String(q.get("detail", ""))
	_check(detail.contains("收集破境材料"), "原文保留（怎么突破）", detail.substr(0, 16))
	_check(detail.contains("修为达到瓶颈") and detail.contains("突破"), "补上了「修为瓶颈」这层")
	_check(detail.contains("打坐"), "写明挂机打坐")
	_check(detail.contains("主线 BOSS"), "写明击败主线 BOSS", detail)
	_check(detail.contains("大陆探索"), "写明大陆探索")
	_check(detail.contains("\n"), "是两段（第二段换行起）", "换行数=%d" % detail.count("\n"))

	# 轮到它当「当前任务」时，面板拿的就是这段原文
	_saved = CharacterData.quest_data.duplicate(true)
	CharacterData.quest_data = {"done": {}}
	var quests: Array = QuestDB.QUESTS
	for i in mini(4, quests.size()):
		(CharacterData.quest_data["done"] as Dictionary)[String((quests[i] as Dictionary).get("id", ""))] = true
	_check(Quest.current_id() == "q_break_realm", "做完前 4 个后，当前任务就是它", Quest.current_id())
	_check(String(Quest.current_quest().get("detail", "")) == detail,
			"当前任务取到的介绍 = 表里那段（面板逐字显示）")
	CharacterData.quest_data = _saved
	Quest.changed.emit()
	await get_tree().process_frame
	print("")
