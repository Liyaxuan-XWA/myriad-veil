extends Node2D
## 「三选一里挑一张」这一步：要等第一次弹三选一才露面，全局一次（2026-11-12 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_rogue_card_step.tscn -- --no-save
##
## 判据：
##   · 步骤表里它带 need = rogue_pick_open；
##   · 进试炼、三选一还没弹的时候：step_visible() = false（卡片不露，序列不跳）；
##   · 第一次弹三选一：pick_open = true → 轮询把这一步点亮 → 指引卡片出现、锚到三选一面板；
##   · 三选一关掉（条件走了）→ 又藏回去；条件再满足 → 再回来（双向）；
##   · 做完之后：本章没有未完成步骤，再弹多少次都不回来。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

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
	print("\n########## 试炼 · 三选一指引步骤 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	var step := TutorialDB.get_step("c6_card")
	_check(String(step.get("need", "")) == "rogue_pick_open", "步骤带 need = rogue_pick_open",
			String(step.get("need", "")))
	_saved = {
		"step": Tutorial.active_step.duplicate(true),
		"chapter": Tutorial.active_chapter,
		"ev": Tutorial.get("_listen_ev"),
		"cond": Tutorial.get("_listen_cond"),
		"count": Tutorial.get("_count"),
		"tutorial": CharacterData.tutorial_data.duplicate(true),
	}
	# 进试炼（三选一暂时不会弹：开局第一关是刷怪）
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	RogueRun.start_run("sword")
	BattleResolver.skip_next_intro = true
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await _frames(4)
	var ov: Node = Tutorial.get_node_or_null("TutorialOverlay")
	_check(ov != null, "取到指引表现层")
	# 手动把这一步摆成「当前步」（正常流程里它排在选流派之后）
	CharacterData.tutorial_data = {"done": {}}
	Tutorial.active_chapter = "c6"
	Tutorial.call("_enter_step", step)
	await _frames(6)
	_check(not bool(RogueRun.pick_open), "现场：三选一还没弹")
	_check(not Tutorial.step_visible(), "三选一没弹之前：这一步**不露脸**")
	_check(ov != null and not bool((ov.get("_card") as Control).visible),
			"指引卡片是藏着的（不会一进试炼就挂在那）")
	# 第一次弹三选一
	var rogue: Node = arena.get("_rogue")
	_check(rogue != null, "取到 RogueArena 调度器")
	if rogue != null:
		rogue.call("_open_pick", false)
	await _frames(2)
	_check(bool(RogueRun.pick_open), "三选一弹出来了（pick_open = true）")
	await get_tree().create_timer(0.5).timeout
	_check(Tutorial.step_visible(), "第一次弹三选一：这一步被点亮")
	_check(ov != null and bool((ov.get("_card") as Control).visible), "指引卡片出现在三选一面板上")
	# 2026-11-12 用户定：出现条件一走（面板关掉）→ 立刻再藏；下次条件满足再回来。
	# 正常流程里选完卡就完成，这里直接拨 pick_open 验证「双向」本身。
	RogueRun.pick_open = false
	await get_tree().create_timer(0.4).timeout
	_check(not Tutorial.step_visible(), "三选一关掉：这一步又重新藏起来（不是只亮一次）")
	_check(ov != null and not bool((ov.get("_card") as Control).visible), "卡片也跟着藏回去")
	RogueRun.pick_open = true
	await get_tree().create_timer(0.4).timeout
	_check(Tutorial.step_visible(), "条件再次满足（下一次弹三选一）：又回来")
	# 只一次：完成之后本章没有未完成步骤
	Tutorial.call("_finish_step")
	await _frames(2)
	_check(Tutorial.is_done("c6_card"), "做完（选了一张）就记为完成")
	_check(TutorialDB.first_open_step("c6", Tutorial.call("_done")).is_empty()
			or String(TutorialDB.first_open_step("c6", Tutorial.call("_done")).get("id", "")) != "c6_card",
			"本章再也不会把它排回来（全局一次）",
			str(TutorialDB.first_open_step("c6", Tutorial.call("_done")).get("id", "")))
	# 收尾
	arena.queue_free()
	RogueRun.finish_run(true)
	await _frames(2)
	CharacterData.tutorial_data = _saved["tutorial"]
	Tutorial.active_step = _saved["step"]
	Tutorial.active_chapter = String(_saved["chapter"])
	Tutorial.set("_listen_ev", _saved["ev"])
	Tutorial.set("_listen_cond", _saved["cond"])
	Tutorial.set("_count", _saved["count"])
	Tutorial.changed.emit()
	await _frames(2)
	print("")
