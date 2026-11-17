extends Node
## 教学「把新功法装到 Q 槽」必须能完成（2026-11-12 用户报：装上了还是不算）
## 用法：godot --headless --path . res://tools/probe_skill_slot_step.tscn -- --no-save
##
## 三条路都要通：
##   ① 玩家在步骤开始前就装好了 ⇒ **状态兜底**（cond: skill_in_slot_q）自己过；
##   ② Q 空着 ⇒ 装配那一刻发 skill_slotted，事件过；
##   ③ 槽里本来就是这门，再点一次「装配→选同一门」⇒ 也要发事件（早退之前发）。

const PANEL_SCRIPT := "res://scripts/ui/panels/skill_panel.gd"
const SID := "skill_sword_stab"
# 每个用例一个独立的步骤 id：同一个 id 在用例①被 _mark_done 了之后，
# is_done() 会一直为真，后面的用例就全是假绿（第一版就是这么漏的）。
const STEP_A := "__probe_skill_slot_cond__"
const STEP_B := "__probe_skill_slot_ev__"
const STEP_C := "__probe_skill_slot_same__"

var _passes := 0
var _fails: Array = []
var _saved_loadout: Array = []
var _saved_state: Dictionary = {}


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


func _begin_step(sid: String) -> void:
	Tutorial.active_chapter = ""
	Tutorial.active_step = {"id": sid, "text": "把新功法装到 Q 槽",
		"ev": "skill_slotted", "cond": "skill_in_slot_q"}
	Tutorial.set("_listen_ev", "skill_slotted")
	Tutorial.set("_listen_cond", "skill_in_slot_q")
	Tutorial.set("_count", 0.0)
	Tutorial.set("_poll_left", 0.0)
	Tutorial.changed.emit()


func _ready() -> void:
	print("\n########## 教学 · 功法装到 Q 槽 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved_loadout = CharacterData.active_skill_loadout.duplicate()
	_saved_state = {
		"step": Tutorial.active_step.duplicate(true),
		"chapter": Tutorial.active_chapter,
		"listen_ev": Tutorial.get("_listen_ev"),
		"listen_cond": Tutorial.get("_listen_cond"),
		"count": Tutorial.get("_count"),
	}

	# ===== ① 状态兜底：Q 里已经有功法 → 不点任何东西也应完成 =====
	CharacterData.active_skill_loadout = [SID, "", "", ""]
	_check(bool(Tutorial.call("_cond_met", "skill_in_slot_q")), "Q 槽有功法 ⇒ 状态兜底为真")
	_begin_step(STEP_A)
	await _frames(30)
	_check(Tutorial.is_done(STEP_A), "已经装好的情况下：步骤自己完成（用户报的就是这种）")

	# ===== ② 事件：Q 空着，装配那一刻算数 =====
	CharacterData.active_skill_loadout = ["", "", "", ""]
	_check(not bool(Tutorial.call("_cond_met", "skill_in_slot_q")), "Q 槽空着 ⇒ 状态兜底为假")
	_begin_step(STEP_B)
	await _frames(2)
	_check(not Tutorial.is_done(STEP_B), "还没装：步骤在等")
	var panel = (load(PANEL_SCRIPT) as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await _frames(2)
	panel.open()
	await _frames(2)
	panel.call("_equip_active_to_slot_replace", 0, SID)
	await _frames(2)
	_check(String(CharacterData.active_skill_loadout[0]) == SID, "Q 槽真的装上了", str(CharacterData.active_skill_loadout))
	_check(Tutorial.is_done(STEP_B), "装配那一刻事件发出去、步骤完成")

	# ===== ③ 槽里本来就是这门：再点一次也要算 =====
	# 先把 Q 装上，再开一步——此时 Q 里就是这门
	CharacterData.active_skill_loadout = ["", "", "", ""]
	panel.call("_equip_active_to_slot_replace", 0, SID)
	_begin_step(STEP_C)
	Tutorial.set("_listen_cond", "")                       # 只认事件，状态兜底不参与
	await _frames(2)
	_check(not Tutorial.is_done(STEP_C), "现场：步骤还在等（Q 里已经是它）")
	panel.call("_equip_active_to_slot_replace", 0, SID)   # 再选同一门
	await _frames(2)
	_check(Tutorial.is_done(STEP_C), "槽里本来就是它：再点一次也发事件、步骤完成")

	# 收尾
	panel.close()
	await _frames(2)
	CharacterData.active_skill_loadout = _saved_loadout
	Tutorial.active_step = _saved_state["step"]
	Tutorial.active_chapter = String(_saved_state["chapter"])
	Tutorial.set("_listen_ev", _saved_state["listen_ev"])
	Tutorial.set("_listen_cond", _saved_state["listen_cond"])
	Tutorial.set("_count", _saved_state["count"])
	Tutorial.changed.emit()
	await _frames(2)
	print("")
