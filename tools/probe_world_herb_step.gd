extends Node
## 「出门采第一株药」：按 F 采到草药就该完成（2026-11-13 用户报）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_world_herb_step.tscn -- --no-save
##
## 用户原话：「踩了草药不算完成，修复一下。」
## 根因：`world_pickup` 只由掉落物的 `_on_drop_picked` 上报；草药是 F 采集的
##   WorldResource，采集成功那条路没人报 → 步骤永远等不到。
##
## 判据：真实大世界场景（进图自动开 c8 章）→ 走到真的草药旁 → 调真实的 F 交互入口
##   `_on_interact()` → 草药被采走 + c8_gather 记完成 + 教学推到下一步。
## ⚠ 用真实 `_resources` 里的草药，不自己造节点：要证明的正是「世上这株草走这条链路」。

const WORLD_SCENE := "res://scenes/world/secret_world.tscn"

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
	print("\n########## 大世界 · 采第一株药 完成指引 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved = {
		"tutorial": CharacterData.tutorial_data.duplicate(true),
		"inventory": CharacterData.inventory.duplicate(true),
		"step": Tutorial.active_step.duplicate(true),
		"chapter": Tutorial.active_chapter,
		"ev": Tutorial.get("_listen_ev"),
		"cond": Tutorial.get("_listen_cond"),
		"count": Tutorial.get("_count"),
		"need_ok": Tutorial.get("_step_need_ok"),
	}
	CharacterData.tutorial_data = {"done": {}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	GameState.battle_context = {}

	var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await _frames(8)
	_check(w.get("player") != null, "大世界起来了")
	_check(Tutorial.active_chapter == "c8", "进图自动开第 8 章（苍澜大陆）",
		Tutorial.active_chapter)
	_check(String(Tutorial.active_step.get("id", "")) == "c8_gather",
		"当前步是「出门采第一株药」", String(Tutorial.active_step.get("id", "")))

	# 从真实生成表里挑一株草药（不自己造）
	var herb: WorldResource = null
	for raw in (w.get("_resources") as Dictionary).values():
		if raw is WorldResource and (raw as WorldResource).kind == WorldResource.KIND_HERB:
			herb = raw as WorldResource
			break
	_check(herb != null, "场上真的有一株草药")
	if herb == null:
		w.queue_free()
		await _frames(2)
		return

	# 站到草药旁边（关掉物理，防它自己走开），等世界自己把 _nearest 指到它
	var wp: Node2D = w.get("player")
	wp.set_physics_process(false)
	wp.global_position = herb.global_position
	await _frames(4)
	_check(w.get("_nearest") == herb, "交互指针已经指到这株草药", str(w.get("_nearest")))
	var node_id := herb.node_id
	var before_done := Tutorial.is_done("c8_gather")

	# 真实的 F 交互入口
	w.call("_on_interact")
	await _frames(3)
	_check(not before_done, "采集之前：这一步没完成")
	_check(not (w.get("_resources") as Dictionary).has(node_id) or not is_instance_valid(herb),
		"草药真的被采走了", node_id)
	_check(Tutorial.is_done("c8_gather"), "采到第一株药：这一步**记为完成**")
	_check(String(Tutorial.active_step.get("id", "")) == "c8_beast",
		"教学推到下一步「打死一只灵兽或野修」", String(Tutorial.active_step.get("id", "")))

	w.queue_free()
	await _frames(3)
	CharacterData.tutorial_data = _saved["tutorial"]
	CharacterData.inventory = _saved["inventory"]
	Tutorial.active_step = _saved["step"]
	Tutorial.active_chapter = String(_saved["chapter"])
	Tutorial.set("_listen_ev", _saved["ev"])
	Tutorial.set("_listen_cond", _saved["cond"])
	Tutorial.set("_count", _saved["count"])
	Tutorial.set("_step_need_ok", _saved["need_ok"])
	Tutorial.changed.emit()
	await _frames(2)
	print("")
