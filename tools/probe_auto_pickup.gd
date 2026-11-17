extends Node2D
## 掉落物自动拾取 + 满包溢到仓库（2026-11-12 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_auto_pickup.tscn -- --no-save
##
## 判据口径：
##   ① 落点优先级用**真实拾取**验（ItemPickup.try_pickup → CharacterData），不直接调 add_item；
##   ② 自动拾取走竞技场 / 大世界自己的 _process 节拍（不手工调 _try_pickup_nearest）；
##   ③ 大世界里「刚丢下的」必须有一段时间捡不回来（否则拖出丢弃等于丢不掉）。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const WORLD_SCENE := "res://scenes/world/secret_world.tscn"
const PICKUP_SCENE := "res://scenes/items/item_pickup.tscn"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 掉落物自动拾取 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _make_drop(item: Dictionary) -> Area2D:
	var d := (load(PICKUP_SCENE) as PackedScene).instantiate() as Area2D
	d.set("item", item.duplicate(true))
	return d


func _mat(id: String, name_s: String, n: int) -> Dictionary:
	return {"id": id, "name": name_s, "type": "material", "count": n, "icon": "", "desc": ""}


func _drop_ids() -> Dictionary:
	var out := {}
	for raw in CharacterData.inventory:
		var it: Dictionary = raw
		out[String(it.get("id", ""))] = int(out.get(String(it.get("id", "")), 0)) + int(it.get("count", 1))
	return out


func _run() -> void:
	# ===== 1. 落点优先级：背包 → 堆叠 → 仓库 → 失败 =====
	var before := _drop_ids()
	var d1 := _make_drop(_mat("mat_xuecao", "血草", 2))
	add_child(d1)
	await get_tree().physics_frame
	_check(bool(d1.call("try_pickup")) and int(d1.get("last_sink")) == 1, "背包有空 ⇒ 进背包")
	_check(int(_drop_ids().get("mat_xuecao", 0)) == int(before.get("mat_xuecao", 0)) + 2,
			"数量进账 +2", str(_drop_ids().get("mat_xuecao", 0)))
	d1.queue_free()

	# 把「材料」分背包铺满，但留一格装晶石
	var cap := CharacterData.BAG_CAP_MATERIAL
	var saved_inv: Array = CharacterData.inventory.duplicate(true)
	var saved_wh: Array = CharacterData.warehouse.duplicate(true)
	CharacterData.inventory.clear()
	CharacterData.inventory.append(_mat(CharacterData.ENHANCE_MATERIAL, "锻造晶石", 5))
	var filler := 1
	while CharacterData.bag_count_for(CharacterData.ITEM_MATERIAL) < cap:
		CharacterData.inventory.append(_mat("fill_%d" % filler, "占位", 1))
		filler += 1
	var crystal_before := int(_drop_ids().get(CharacterData.ENHANCE_MATERIAL, 0))
	var d2 := _make_drop(_mat(CharacterData.ENHANCE_MATERIAL, "锻造晶石", 3))
	add_child(d2)
	await get_tree().physics_frame
	_check(bool(d2.call("try_pickup")) and int(d2.get("last_sink")) == 1,
			"背包**满格**但里面已有晶石 ⇒ 照样叠进背包", str(d2.get("last_sink")))
	_check(int(_drop_ids().get(CharacterData.ENHANCE_MATERIAL, 0)) == crystal_before + 3,
			"晶石数量真的叠上去了（5+3）", str(_drop_ids().get(CharacterData.ENHANCE_MATERIAL, 0)))
	d2.queue_free()

	var d3 := _make_drop(_mat("mat_new_thing", "新东西", 1))
	add_child(d3)
	await get_tree().physics_frame
	_check(bool(d3.call("try_pickup")) and int(d3.get("last_sink")) == 2,
			"背包满且没法叠 ⇒ 溢进仓库", str(d3.get("last_sink")))
	var in_wh := false
	for raw in CharacterData.warehouse:
		if String((raw as Dictionary).get("id", "")) == "mat_new_thing":
			in_wh = true
	_check(in_wh, "仓库里确实有这件东西")
	d3.queue_free()

	# 仓库也铺满 → 捡不起来（掉落物留在原地）
	while CharacterData.warehouse_count_for(CharacterData.ITEM_MATERIAL) < CharacterData.WAREHOUSE_CAP_PER_CATEGORY:
		CharacterData.warehouse.append(_mat("wh_%d" % filler, "仓库占位", 1))
		filler += 1
	var d4 := _make_drop(_mat("mat_full_full", "塞不进去", 1))
	add_child(d4)
	await get_tree().physics_frame
	_check(not bool(d4.call("try_pickup")) and int(d4.get("last_sink")) == 0,
			"背包与仓库都满 ⇒ 捡不起来（掉落物保留）")
	d4.queue_free()

	# 还原
	CharacterData.inventory.clear()
	CharacterData.inventory.append_array(saved_inv)
	CharacterData.warehouse.clear()
	CharacterData.warehouse.append_array(saved_wh)

	# ===== 2. 竞技场：走进范围自动捡，不用按 F =====
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN, "domain_id": "domain_01", "boss_id": "boss_01",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var p: Node2D = arena.get("player")
	p.set_physics_process(false)
	var crystal0 := int(_drop_ids().get(CharacterData.ENHANCE_MATERIAL, 0))
	var drop := _make_drop(_mat(CharacterData.ENHANCE_MATERIAL, "锻造晶石", 4))
	drop.position = p.global_position
	arena.add_child(drop)
	(arena.get("_drops_on_ground") as Array).append(drop)
	for i in 40:
		await get_tree().physics_frame
	for i in 40:
		await get_tree().process_frame
	_check(int(_drop_ids().get(CharacterData.ENHANCE_MATERIAL, 0)) == crystal0 + 4,
			"竞技场：站上去就自动捡（没按 F）",
			"%d → %d" % [crystal0, int(_drop_ids().get(CharacterData.ENHANCE_MATERIAL, 0))])
	_check(not (arena.get("_drops_on_ground") as Array).has(drop), "掉落物已从场上移除")
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ===== 3. 大世界：自动捡 + 刚丢下的有宽限 =====
	GameState.battle_context = {}
	var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	for i in 6:
		await get_tree().process_frame
	var wp: Node2D = w.get("player")
	wp.set_physics_process(false)
	var run_before := int((w.get("_run_items") as Array).size())
	w.call("_spawn_drop_item", _mat("mat_xuecao", "血草", 1), wp.global_position)
	for i in 40:
		await get_tree().physics_frame
	for i in 40:
		await get_tree().process_frame
	_check(int((w.get("_run_items") as Array).size()) == run_before + 1,
			"大世界：走进范围自动捡进局内行囊（不用按 F）",
			"%d → %d" % [run_before, int((w.get("_run_items") as Array).size())])
	# 拖出丢弃 → 不能马上被吸回来
	w.call("_drop_run_item", _mat("mat_xuecao", "血草", 1))
	var drops: Array = w.get("_drops")
	var dropped: Area2D = drops[drops.size() - 1] if not drops.is_empty() else null
	_check(dropped != null and not bool(dropped.call("auto_pickable")),
			"刚丢下的东西：自动拾取让开（否则永远丢不掉）")
	await get_tree().create_timer(2.4).timeout
	_check(not bool(dropped.call("auto_pickable")), "2.4 秒时仍在宽限里")
	await get_tree().create_timer(0.9).timeout
	_check(bool(dropped.call("auto_pickable")), "3 秒后宽限解除")
	w.queue_free()
	await get_tree().process_frame
	print("")
