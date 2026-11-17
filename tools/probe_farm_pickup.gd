extends Node2D
## 灵田与掉落物冲突自检（2026-11-02 用户报两条）
##   A) 掉落物掉在农田上时按 F 捡不起来 —— 地块 REACH 92 比拾取范围大，F 被地块吃掉
##   B) 单位站在农田上被农田盖住 —— 项目没有 YSort，同 z 时后 add_child 的田盖住先出生的怪
## 用法：godot --headless --path . tools/probe_farm_pickup.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _farm_nodes(w: Node) -> Array:
	var out: Array = []
	for raw in w._resources.values():
		if raw is FarmPlot:
			out.append(raw)
	return out


## 播报文本（_announce 在个别装配下可能还没建）
func _said(w: Node) -> String:
	var a = w._announce
	return "" if a == null else String(a.text)


func _drop(id: String, n: int) -> Dictionary:
	var def := ItemDB.get_material(id)
	return {"id": id, "name": String(def.get("name", id)), "type": "material",
		"count": n, "icon": String(def.get("icon", ""))}


## 在指定位置掉一件东西，并强制判定「玩家已在拾取范围内」
## （headless 里物理重叠不一定触发 body_entered，直接走 ItemPickup 自己的入口函数）
func _drop_at(w: Node, pos: Vector2, id: String) -> Area2D:
	w._spawn_drop_item(_drop(id, 1), pos)
	var p: Area2D = w._drops.back()
	p.call("_on_body_entered", w.player)
	return p


func _ready() -> void:
	print("\n########## 灵田 / 掉落物冲突探针 ##########")
	await get_tree().process_frame
	CharacterData.secret_world["core_kills"] = {}
	CharacterData.tilled_plots.clear()
	CharacterData.inventory = []

	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	CharacterData.secret_world["core_kills"][SecretWorldDB.REGION_ZHUJI] = true
	w._spawn_due_content()
	var plots: Array = []
	for raw in _farm_nodes(w):
		if String((raw as FarmPlot).region_id) == SecretWorldDB.REGION_ZHUJI:
			plots.append(raw)
	_check(plots.size() == 9, "云隐谷九块田已生成", "n=%d" % plots.size())
	if plots.is_empty():
		get_tree().quit(1)
		return
	var plot := plots[0] as FarmPlot

	# ===== B：层序 =====
	# 地面 -20 < 农田 -1 < 玩家 / 怪 / 掉落物 0：田是后生成的，不压一层就会盖住单位
	_check(plot.z_index < 0, "农田压在地面之上、单位之下", "z=%d" % plot.z_index)
	_check(w.player.z_index > plot.z_index, "玩家画在农田前面", "player z=%d" % w.player.z_index)
	_check(w.get_node("Ground").z_index < plot.z_index, "地面仍在最底",
		"ground z=%d" % int(w.get_node("Ground").z_index))
	var drop := _drop_at(w, plot.global_position, "mat_zj_xuecao")
	_check(drop.z_index > plot.z_index, "掉落物画在农田前面", "drop z=%d" % drop.z_index)
	var beasts: Array = []
	for raw in w._enemies.values():
		if raw is Node:
			beasts.append(raw)
	if not beasts.is_empty():
		_check(int((beasts[0] as Node).z_index) > plot.z_index,
			"野外单位画在农田前面", "n=%d z=%d" % [beasts.size(), int((beasts[0] as Node).z_index)])
	else:
		print("SKIP  本区暂无野外单位，跳过怪物层序")

	# ===== A：站在田上按 F =====
	w.player.global_position = plot.global_position
	w._update_interaction()
	_check(is_same(w._nearest, plot), "玩家确实站在田的交互范围内（bug 前提成立）")
	_check(drop.has_player_inside(), "掉落物也判定玩家在范围内")
	var before := int(w._run_items.size())
	w._on_interact()
	_check(int(w._run_items.size()) == before + 1, "站在田上按 F 先捡到掉落物")
	_check(not w._drops.has(drop), "捡到的东西已从场上移除")
	_check(_said(w).contains("拾取"), "播报是拾取而非地块提示",
		_said(w))
	_check(plot.crop_id() == "" and not plot.is_tilled(), "这次 F 没有改动地块状态")

	# ===== 提示让位：脚边有东西时不喊地块的话 =====
	var drop2 := _drop_at(w, plot.global_position, "mat_zj_lanyingcao")
	w._update_interaction()
	_check(is_same(w._nearest, plot), "提示切换时地块仍是最近资源")
	_check(not w._prompt_bg.visible, "脚边有东西时地块提示让位")
	drop2.call("_on_body_exited", w.player)
	w._update_interaction()
	_check(w._prompt_bg.visible, "东西离开脚下后地块提示回来")
	_check(String(w._prompt.text) == String(plot.prompt_text()),
		"回来的仍是这块田自己的提示", String(w._prompt.text))

	# ===== 没有掉落物时，F 仍然归地块管（不许把旧交互弄丢）=====
	w._on_interact()
	_check(_said(w).contains("荒地"), "无掉落物时 F 仍走地块逻辑",
		_said(w))
	_check(int(w._run_items.size()) == before + 1, "这次 F 没有多捡东西")

	# ===== 背包放不下时不许吞掉地块交互 =====
	for i in range(w.RUN_BAG_CAPACITY):
		w._run_items.append({"id": "mat_probe_fill_%d" % i, "name": "占位", "type": "material",
			"count": 1})
	var drop3 := _drop_at(w, plot.global_position, "mat_zj_huguteng")
	w.player.global_position = plot.global_position
	w._on_interact()
	_check(w._drops.has(drop3), "局内背包满时东西仍在地上（没被吞）")
	_check(_said(w).contains("背包已满")
		or _said(w).contains("荒地"),
		"拾取失败后播报回到地块 / 背包原因", _said(w))

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
