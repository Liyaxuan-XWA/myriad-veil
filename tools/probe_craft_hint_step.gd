extends Node
## 「点开材料看合成指引」这一步的触发条件（2026-11-12 用户定）
## 用法：godot --headless --path . res://tools/probe_craft_hint_step.tscn -- --no-save
##
## 用户原话：触发条件改成「只有获得了能参与合成的物品才能触发，全局仅触发一次」。
## 判据：
##   · 普通材料（血草）进包 → 不触发；
##   · 合成材料（破境残晶）进包 → 触发一个独立小章 c3b，步骤就是 c3_where；
##   · 做完/跳过一次之后，再捡任何合成材料都不再触发；
##   · 锻造章 c3 里已经不含这一步（不再跟着锻造面板弹）。

const PLAIN := "mat_xuecao"

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


func _give(id: String) -> void:
	var def := ItemDB.get_material(id)
	CharacterData.add_item({"id": id, "name": String(def.get("name", id)), "type": "material",
		"count": 1, "icon": "", "desc": ""})


func _reset_tutorial() -> void:
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	CharacterData.tutorial_data = {"done": {}}


func _ready() -> void:
	print("\n########## 合成指引步骤 · 触发条件 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved = {
		"tutorial": CharacterData.tutorial_data.duplicate(true),
		"bag_seen": CharacterData.bag_seen_ids.duplicate(true),
		"bag_new": CharacterData.bag_new_ids.duplicate(true),
		"inventory": CharacterData.inventory.duplicate(true),
		"codex": CharacterData.codex_unlocked.duplicate(true),
	}
	# 找一件真的「能参与合成」的材料（破境残晶）
	var realm := String(ItemDB.POJING_SYNTH_RECIPES.keys()[0])
	var craft_id := String((ItemDB.POJING_SYNTH_RECIPES[realm] as Dictionary).get("di", ""))
	_check(not ItemDB.synth_hint_lines(craft_id).is_empty(), "破境残晶算「能参与合成」", craft_id)
	_check(ItemDB.synth_hint_lines(PLAIN).is_empty(), "普通材料（血草）不算", PLAIN)

	# ① 普通材料不触发
	_reset_tutorial()
	_give(PLAIN)
	await get_tree().process_frame
	_check(Tutorial.active_chapter == "", "捡普通材料：不触发合成指引", Tutorial.active_chapter)

	# ② 合成材料触发（独立小章，步骤就是 c3_where）
	_reset_tutorial()
	_give(craft_id)
	await get_tree().process_frame
	_check(Tutorial.active_chapter == "c3b", "捡到合成材料：触发合成指引章", Tutorial.active_chapter)
	_check(String(Tutorial.active_step.get("id", "")) == "c3_where",
			"步骤就是「点开材料看合成指引」", String(Tutorial.active_step.get("id", "")))

	# ③ 只触发一次：跳过这一步之后，再捡合成材料也不再弹
	Tutorial.skip_step()
	await get_tree().process_frame
	_check(Tutorial.active_chapter == "", "跳过之后本章收尾")
	_check(TutorialDB.first_open_step("c3b", Tutorial.call("_done")).is_empty(),
			"这一步已经记为完成，本章没有未完成步骤")
	_give(craft_id)
	await get_tree().process_frame
	_check(Tutorial.active_chapter == "", "再捡合成材料：**不会**再触发（全局只教一次）",
			Tutorial.active_chapter)

	# ④ 锻造章里已经不含这一步（不再跟着锻造面板一起弹）
	var in_c3 := false
	for raw in (TutorialDB.get_chapter("c3").get("steps", []) as Array):
		if String((raw as Dictionary).get("id", "")) == "c3_where":
			in_c3 = true
	_check(not in_c3, "锻造章 c3 里已经没有 c3_where")

	# 收尾
	CharacterData.tutorial_data = _saved["tutorial"]
	CharacterData.bag_seen_ids = _saved["bag_seen"]
	CharacterData.bag_new_ids = _saved["bag_new"]
	CharacterData.inventory = _saved["inventory"]
	CharacterData.codex_unlocked = _saved["codex"]
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.changed.emit()
	await get_tree().process_frame
	print("")
