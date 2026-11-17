extends Node
## 大世界技能栏的「剑意就绪光环」（2026-11-12 用户报：大陆里剑意满时这两招没有竞技场里的特效）
## 用法：godot --headless --path . res://tools/probe_world_intent_aura.tscn -- --no-save
##
## 口径与竞技场一致：**剑意满 + 冷却转好 + 该招式吃剑意**（intent_full_at / intent_count_scale）
## 三条同时成立才转；普攻类功法（不吃剑意）满层也不转。

const WORLD := "res://scenes/world/secret_world.tscn"

var _passes := 0
var _fails: Array = []
var _saved_loadout: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 大世界 · 剑意就绪光环 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _aura(w: Node, i: int) -> Node2D:
	var slots: Array = w.get("_skill_slots")
	if i >= slots.size():
		return null
	return (slots[i] as Dictionary).get("aura") as Node2D


func _run() -> void:
	_saved_loadout = CharacterData.active_skill_loadout.duplicate()
	# 槽 0 = 一剑开天（吃剑意）；槽 1 = 刺（不吃剑意）；其余留空
	CharacterData.active_skill_loadout = ["skill_sword_heaven", "skill_sword_stab", "", ""]
	var w: Node = (load(WORLD) as PackedScene).instantiate()
	add_child(w)
	for i in 8:
		await get_tree().process_frame
	var p: Node2D = w.get("player")
	p.set_physics_process(false)
	p.set("sword_intent", 0)
	w.call("_update_skill_bar")
	await get_tree().process_frame
	var a0 := _aura(w, 0)
	_check(a0 != null, "技能格挂上了光环节点")
	_check(a0 != null and not a0.visible, "剑意没满：不转")
	# 满剑意 → 只有吃剑意的那一招转
	p.set("sword_intent", int(p.call("_sword_intent_max")))
	w.call("_update_skill_bar")
	await get_tree().process_frame
	_check(a0 != null and a0.visible, "剑意满：一剑开天的格子转起来了")
	var a1 := _aura(w, 1)
	_check(a1 != null and not a1.visible, "不吃剑意的招式（刺）满层也不转")
	# 冷却没好 → 不转
	p.set("skill_cooldowns", {"skill_sword_heaven": 3.0})
	w.call("_update_skill_bar")
	await get_tree().process_frame
	_check(a0 != null and not a0.visible, "冷却没好：不转")
	p.set("skill_cooldowns", {})
	w.call("_update_skill_bar")
	await get_tree().process_frame
	_check(a0 != null and a0.visible, "冷却转好：又转起来")
	# 位置：光环中心对齐格子中心
	var slots: Array = w.get("_skill_slots")
	var box: Control = (slots[0] as Dictionary).get("box")
	var center := box.global_position + box.size * 0.5
	_check(a0 != null and a0.global_position.distance_to(center) < 1.0,
			"光环对齐格子中心", str(a0.global_position) + " vs " + str(center))
	# 收尾
	w.queue_free()
	await get_tree().process_frame
	CharacterData.active_skill_loadout = _saved_loadout
	print("")
