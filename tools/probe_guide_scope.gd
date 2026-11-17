extends Node
## 界内指引：退出界面暂时消失，条件再满足才回来（2026-11-12 用户定）
## 用法：godot --headless --path . res://tools/probe_guide_scope.tscn -- --no-save
##
## 用户原话：「将这类指引，退出界面时要暂时消失，要再达成出现指引条件时才会再次出现，
##   如果完成了指引或者跳过了指引下次才不会再出现。」
##
## 判据（真实表现层 + 真实背包 CharacterPanel，不造假控件）：
##   · 合成指引章开着、背包也开着 ⇒ 卡片在，聚光指着材料详情；
##   · 关掉背包 ⇒ 卡片整块消失，`_has_target` = false，步骤没被判完成；
##   · 期间换成无关面板（锻造台）⇒ 也不许拿「整块面板」兜底冒出来；
##   · 再打开背包 ⇒ 指引自己回来（锚点重扫 / 模态层数变化）；
##   · 空锚点的说明步照旧降级出卡片（设计案 3.1 的兜底只留这一种）；
##   · 跳过 / 完成后本章没有未完成步骤，再捡合成材料也不会回来。

const FOREIGN_PANEL := "res://scripts/ui/panels/domain_panel.gd"

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


func _give(id: String) -> void:
	var def := ItemDB.get_material(id)
	CharacterData.add_item({"id": id, "name": String(def.get("name", id)), "type": "material",
		"count": 1, "icon": "", "desc": ""})


func _overlay() -> Node:
	return Tutorial.get_node_or_null("TutorialOverlay")


func _card_visible() -> bool:
	var ov := _overlay()
	return ov != null and bool((ov.get("_card") as Control).visible)


func _target() -> Node:
	var ov := _overlay()
	return ov.get("_target_node") as Node if ov != null else null


func _has_target() -> bool:
	var ov := _overlay()
	return ov != null and bool(ov.get("_has_target"))


func _ready() -> void:
	print("\n########## 界内指引 · 离开界面暂时消失 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved = {
		"tutorial": CharacterData.tutorial_data.duplicate(true),
		"bag_seen": CharacterData.bag_seen_ids.duplicate(true),
		"bag_new": CharacterData.bag_new_ids.duplicate(true),
		"inventory": CharacterData.inventory.duplicate(true),
		"codex": CharacterData.codex_unlocked.duplicate(true),
		"step": Tutorial.active_step.duplicate(true),
		"chapter": Tutorial.active_chapter,
		"ev": Tutorial.get("_listen_ev"),
		"cond": Tutorial.get("_listen_cond"),
		"count": Tutorial.get("_count"),
		"need_ok": Tutorial.get("_step_need_ok"),
	}
	var ov := _overlay()
	_check(ov != null, "取到真实指引表现层")
	if ov == null:
		return
	# 干净状态：不在试炼、背包收着
	RogueRun.active = false
	if CharacterPanel.is_open():
		CharacterPanel.close_panel()
	await _frames(2)

	# ===== 1. 捡到能合成的材料 → 合成指引章开，但背包没开：指引先藏着 =====
	CharacterData.tutorial_data = {"done": {}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	var realm := String(ItemDB.POJING_SYNTH_RECIPES.keys()[0])
	var craft_id := String((ItemDB.POJING_SYNTH_RECIPES[realm] as Dictionary).get("di", ""))
	_give(craft_id)
	await _frames(3)
	_check(String(Tutorial.active_step.get("id", "")) == "c3_where",
		"捡到合成材料：当前步是「点开材料看合成指引」", String(Tutorial.active_step.get("id", "")))
	_check(not CharacterPanel.is_open(), "现场：背包是关着的")
	_check(not _card_visible() and not _has_target(), "背包没开：这张指引**不露脸**（不浮在城里）")

	# ===== 2. 打开背包：指引自己回来，聚光指着材料详情 =====
	CharacterPanel.open_panel()
	await _frames(4)
	_check(CharacterPanel.is_open(), "背包打开了")
	_check(_card_visible(), "打开背包：指引自己回来（没有靠事件触发）")
	var tgt := _target()
	_check(tgt != null and CharacterPanel.is_ancestor_of(tgt),
		"聚光指向背包里的材料详情", str(tgt))
	_check(_has_target(), "聚光框算得出来（不是降级卡片）")
	var tgt_name := ""
	if tgt != null:
		tgt_name = String(tgt.get_meta("tut", ""))
	_check(tgt_name == "forge.material", "锚点确实是 forge.material", tgt_name)
	_check(not Tutorial.is_done("c3_where"), "全程没有被判完成（只有完成/跳过才永久消失）")

	# ===== 3. 关掉背包：整块暂时消失 =====
	CharacterPanel.close_panel()
	await _frames(4)
	_check(not CharacterPanel.is_open(), "背包关掉了")
	_check(not _card_visible() and not _has_target(), "退出背包：指引暂时消失")
	_check(String(Tutorial.active_step.get("id", "")) == "c3_where",
		"步骤还挂在原位（序列不跳，下次还要用）", String(Tutorial.active_step.get("id", "")))
	_check(not Tutorial.is_done("c3_where"), "关界面不会把它判完成")

	# ===== 4. 换成无关面板（位面星图）：也不许拿「整块面板」兜底冒出来 =====
	# ⚠ 用走 SystemPanel 基础外壳的面板：它的 _root 挂着 tut=panel，
	#   正好能验出「找不到就圈整块面板」那条旧兜底会不会让指引诈尸。
	var panel: Node = (load(FOREIGN_PANEL) as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await _frames(8)
	panel.call("open")
	await _frames(8)
	_check(panel.call("is_open") == true, "位面星图打开了（无关界面）")
	_check(not _card_visible() and not _has_target(),
		"无关界面上不冒出来（不会圈着整块面板冒充材料详情）")
	panel.call("close")
	await _frames(4)

	# ===== 5. 再打开背包：出现条件再次满足 → 指引再回来 =====
	CharacterPanel.open_panel()
	await _frames(4)
	_check(_card_visible() and _has_target(), "再开背包：指引再次出现")
	tgt = _target()
	_check(tgt != null and CharacterPanel.is_ancestor_of(tgt), "再次指回材料详情", str(tgt))

	# ===== 6. 空锚点的纯说明步：照旧出卡片（唯一保留的降级形态）=====
	CharacterPanel.close_panel()
	await _frames(4)
	Tutorial.active_step = {"id": "__probe_plain__", "text": "纯说明步", "tip": "", "manual": true}
	Tutorial.changed.emit()
	await _frames(3)
	_check(_card_visible() and not _has_target(), "没有锚点的说明步：照旧出卡片（不聚光）")

	# ===== 7. 守卫：装符这一步的锚点在符匣里（旧锚点是战斗 HUD 的 Q 槽）=====
	var load_step := TutorialDB.get_step("c4_load")
	_check(String(load_step.get("anchor", "")) == "meta:talisman.assign",
		"装符这一步指到符匣右侧「装 Q/E/R/T」纸笺（不是战斗里的 Q 槽）",
		String(load_step.get("anchor", "")))

	# ===== 8. 跳过之后：本章没有未完成步骤，再捡材料也不回来 =====
	Tutorial.active_chapter = "c3b"
	Tutorial.call("_enter_step", TutorialDB.get_step("c3_where"))
	await _frames(2)
	Tutorial.skip_step()
	await _frames(2)
	_check(Tutorial.is_done("c3_where"), "跳过 = 记完成")
	_check(TutorialDB.first_open_step("c3b", Tutorial.call("_done")).is_empty(),
		"本章再没有未完成步骤")
	_give(craft_id)
	await _frames(2)
	_check(Tutorial.active_chapter == "", "再捡合成材料：不会再触发（全局只教一次）",
		Tutorial.active_chapter)

	# 收尾
	if CharacterPanel.is_open():
		CharacterPanel.close_panel()
	CharacterData.tutorial_data = _saved["tutorial"]
	CharacterData.bag_seen_ids = _saved["bag_seen"]
	CharacterData.bag_new_ids = _saved["bag_new"]
	CharacterData.inventory = _saved["inventory"]
	CharacterData.codex_unlocked = _saved["codex"]
	Tutorial.active_step = _saved["step"]
	Tutorial.active_chapter = String(_saved["chapter"])
	Tutorial.set("_listen_ev", _saved["ev"])
	Tutorial.set("_listen_cond", _saved["cond"])
	Tutorial.set("_count", _saved["count"])
	Tutorial.set("_step_need_ok", _saved["need_ok"])
	Tutorial.changed.emit()
	await _frames(3)
	print("")
