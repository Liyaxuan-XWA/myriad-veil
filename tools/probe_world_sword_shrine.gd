extends Node2D
## 练气区「石台插剑」彩蛋设施自检（2026-11-12）
##
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_world_sword_shrine.tscn -- --no-save
##
## 判据口径（和这一轮其它探针一致）：
##   ① 坐标关系用**算出来的数**断言，不写死期望像素；
##   ② 交互走真实入口（把玩家挪过去 → `_update_interaction()` → `_on_interact()`），
##      不直接调 `_interact_reliquary()` —— 那样「按 F 到底分不分得到」这一环没被覆盖；
##   ③ 「永久消失」必须跨**两个世界实例**验（重开场景 = 重进大陆），同场重调度只算半条；
##   ④ 每条禁令都另配一条「撤掉实现就红」的对照（见文档里的变异记录）。

const WORLD_SCENE := "res://scenes/world/secret_world.tscn"
const NID := "lq_sword_shrine"
const EID := "eq_wentian_jian"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _said(w: Node) -> String:
	var a = w.get("_announce")
	return "" if a == null else String(a.text)


func _shrine(w: Node) -> Dictionary:
	for raw in w.get("_content_def").get("reliquaries", []):
		var d: Dictionary = raw
		if String(d.get("node_id", "")) == NID:
			return d
	return {}


func _portal(w: Node) -> Vector2:
	for raw in w.get("_content_def").get("portals", []):
		var d: Dictionary = raw
		if String(d.get("region_id", "")) == SecretWorldDB.REGION_LIANQI:
			return Vector2(d.get("pos", Vector2.ZERO))
	return Vector2.INF


func _farm_cells(w: Node) -> Array:
	## 灵田九格的实际占地中心（世界坐标），用来验「剑不压田」
	var out: Array = []
	for raw in w.get("_content_def").get("farms", []):
		var d: Dictionary = raw
		if String(d.get("region_id", "")) != SecretWorldDB.REGION_LIANQI:
			continue
		var center := Vector2(d.get("pos", Vector2.ZERO))
		var sp := Vector2(d.get("spacing", Vector2(138.0, 100.0)))
		for r in int(d.get("rows", 3)):
			for c in int(d.get("cols", 3)):
				out.append(center + Vector2(
					(float(c) - 1.0) * sp.x, (float(r) - 1.0) * sp.y))
	return out


func _has_sword() -> bool:
	for raw in CharacterData.inventory:
		if String((raw as Dictionary).get("id", "")) == EID:
			return true
	for slot in CharacterData.equipment_slots.keys():
		var it = CharacterData.equipment_slots[slot]
		if it is Dictionary and String((it as Dictionary).get("id", "")) == EID:
			return true
	return false


## 永久背包里这把剑有几件（>1 = 重复发放）
func _inv_swords() -> Array:
	var out: Array = []
	for raw in CharacterData.inventory:
		if String((raw as Dictionary).get("id", "")) == EID:
			out.append(raw)
	return out


func _drop_from_inventory(item_id: String) -> void:
	for i in range(CharacterData.inventory.size() - 1, -1, -1):
		if String((CharacterData.inventory[i] as Dictionary).get("id", "")) == item_id:
			CharacterData.inventory.remove_at(i)


## 回到「从没拔过」的初始现场：身上没剑 + nodes 里没有 taken 标记
func _reset_to_untaken() -> void:
	_drop_from_inventory(EID)
	(_nodes() as Dictionary).erase(NID)


func _nodes() -> Dictionary:
	var t = CharacterData.secret_world.get("nodes", {})
	return t if t is Dictionary else {}


func _canary_gone() -> bool:
	for raw in CharacterData.inventory:
		if String((raw as Dictionary).get("id", "")) == "canary":
			return false
	return true


func _ready() -> void:
	print("\n########## 石台插剑 · 彩蛋设施 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# ===== 1. 数据与素材齐不齐 =====
	var cfg: Dictionary = SecretWorldDB.LIANQI_CONTENT.get("reliquaries", [{}])[0]
	_check(String(cfg.get("node_id", "")) == NID, "内容表登记了石台插剑", str(cfg.get("node_id", "")))
	_check(String(cfg.get("reward_equipment", "")) == EID, "奖励指向问天剑",
			String(cfg.get("reward_equipment", "")))
	var tpl := ItemDB.get_equipment_template(EID)
	_check(not tpl.is_empty() and String(tpl.get("equipment_type", "")) == "weapon",
		"问天剑是装备模板且类别是 weapon", str(tpl.get("equipment_type", "")))
	_check(absf(float(tpl.get("attributes", {}).get(AttributeDB.ATTR_STRENGTH, 0.0)) - 10.0)
			< 0.001, "力量 +10（用户指定）", str(tpl.get("attributes", {})))
	for f in ["cannot_discard", "cannot_dismantle", "cannot_enhance"]:
		_check(bool(tpl.get(f, false)), "模板带禁令字段 %s" % f)
	var vis := ArtDB.get_visual(String(cfg.get("visual_id", "")))
	_check(not vis.is_empty() and ResourceLoader.exists(String(vis.get("texture", ""))),
		"石台贴图条目存在且能加载", String(vis.get("texture", "")))
	var wvis := ArtDB.get_visual(String(tpl.get("weapon_visual", "")))
	_check(not wvis.is_empty() and ResourceLoader.exists(String(wvis.get("texture", ""))),
		"问天剑局内武器条目存在且能加载", String(wvis.get("texture", "")))

	# ===== 2. 起世界，验坐标关系 =====
	var w = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	var rel_pos := Vector2(cfg.get("pos", Vector2.ZERO))
	# 内容表已被 _offset_content 平移过，这里取**平移后**的那份
	var shrine := _shrine(w)
	var sp: Vector2 = Vector2(shrine.get("pos", Vector2.ZERO))
	var pp := _portal(w)
	_check(pp != Vector2.INF, "练气区传送门在并集内容里")
	_check(absf(sp.x - pp.x) < 1.0, "石台与传送门同 x（正上方，不偏左右）",
			"%.0f vs %.0f" % [sp.x, pp.x])
	_check(sp.y < pp.y, "石台在门的北侧（y 更小 = 屏幕上方）", "%.0f < %.0f" % [sp.y, pp.y])
	var gap := pp.y - sp.y
	_check(gap > WorldResource.REACH_PORTAL + WorldResource.REACH_RELIQUARY,
		"间距大于两个交互半径之和（不抢「最近交互」）",
		"%.0f > %.0f" % [gap, WorldResource.REACH_PORTAL + WorldResource.REACH_RELIQUARY])
	_check(gap > 120.0 and gap < 900.0, "离门「较近」但不在门口", "%.0f" % gap)
	var min_farm := 1e9
	for cell in _farm_cells(w):
		min_farm = minf(min_farm, sp.distance_to(cell as Vector2))
	_check(min_farm > 200.0, "不压灵田九格", "最近田格 %.0f" % min_farm)

	# ===== 3. 生成 =====
	_check(w.get("_resources").has(NID), "进图后石台在场")
	_check(not w.call("_nodes_table").has(NID), "未取走时没有 taken 记录")

	# ===== 4. 交互走真实入口 =====
	w.player.global_position = sp
	w.call("_update_interaction")
	_check(is_same(w.get("_nearest"), w.get("_resources")[NID]), "站到台上时最近交互对象是石台")
	var prompt := String(w.get("_prompt").text)
	_check(prompt.contains("F") and prompt.contains("问天剑"), "提示条写明按 F 拔剑", prompt)
	# 用户 2026-11-12 定：拔剑直接进**永久（主）背包**，不落局内背包
	var inv_before := _inv_swords().size()
	var run_before := int(w.get("_run_items").size())
	w.call("_on_interact")
	_check(_inv_swords().size() == inv_before + 1, "主背包多了一把剑",
			"%d → %d" % [inv_before, _inv_swords().size()])
	_check(int(w.get("_run_items").size()) == run_before,
		"局内背包没有代收（要的就是「不进临时背包」）",
			"%d → %d" % [run_before, int(w.get("_run_items").size())])
	var got: Dictionary = _inv_swords()[-1] if _inv_swords().size() > 0 else {}
	_check(String(got.get("id", "")) == EID and String(got.get("name", "")) == "问天剑",
		"拿到的正是问天剑", "%s %s" % [String(got.get("id", "")), String(got.get("name", ""))])
	_check(String(got.get("type", "")) == CharacterData.ITEM_EQUIPMENT,
		"入包的是装备实体", String(got.get("type", "")))
	_check(not w.get("_resources").has(NID), "取走后石台从场上消失")
	_check(_said(w).contains("拔出"), "播报写明拔出来了", _said(w))
	_check(_said(w).contains("已入背包"), "回执点名进的是永久背包（不是按 B 那个包）", _said(w))
	var rec = w.call("_nodes_table").get(NID, null)
	_check(rec is Dictionary, "永久标记已写进 nodes", str(rec))
	if rec is Dictionary:
		_check(not (rec as Dictionary).has("at"),
			"永久记录不许带 at（带了就被 _node_due 当刷新计时，剑会复活）", str(rec))

	# ===== 5. 永久：同场重调度 + 重开世界实例 =====
	w.call("_spawn_due_content")
	_check(not w.get("_resources").has(NID), "同一场里重复调度不再出现")
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var w2 = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w2)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not w2.get("_resources").has(NID), "重进苍澜大陆后石台仍不在")
	_check(_inv_swords().size() == 1, "重进时自愈认主背包，不会再发一把（不重复）",
			"%d 件" % _inv_swords().size())

	# ===== 6. 三条禁令（走各自判定函数）=====
	var item: Dictionary = CharacterData.make_equipment_instance(tpl)
	_check(not CharacterData.can_discard_item(item), "问天剑不可丢弃")
	_check(not CharacterData.can_dismantle_item(item), "问天剑不可分解")
	_check(CharacterData.dismantle_item(item) == 0, "dismantle_item 也拒绝（不只靠 UI）")
	var eres: Dictionary = CharacterData.enhance_item(item)
	_check(not bool(eres.get("ok", false)) and String(eres.get("message", "")).contains("传家"),
		"不可强化，且回执说清原因", String(eres.get("message", "")))
	# 对照：普通武器三条都不该被误伤
	var plain := ItemDB.get_equipment_template("eq_qingfengjian")
	var plain_item: Dictionary = CharacterData.make_equipment_instance(plain)
	_check(CharacterData.can_discard_item(plain_item)
			and CharacterData.can_dismantle_item(plain_item),
		"清风剑不受影响（禁令没误伤普通武器）")

	# ===== 7. 老存档实例没有这些字段：必须回查模板 =====
	var legacy := {"id": EID, "name": "问天剑", "type": CharacterData.ITEM_EQUIPMENT}
	_check(not CharacterData.can_discard_item(legacy)
			and not CharacterData.can_dismantle_item(legacy),
		"实例缺禁令字段时按模板回查（老档不复活成可丢可拆）", str(legacy.keys()))

	# ===== 8. 主背包满：剑不许消失 =====
	w2.call("_nodes_table").erase(NID)
	w2.call("_spawn_due_content")
	_check(w2.get("_resources").has(NID), "清掉标记后石台重新在场（题目成立）")
	# 铺满的是**永久背包的装备档**，不再是局内背包：满了只拒绝，一口都不吃
	var cap := CharacterData.BAG_CAP_EQUIPMENT
	while CharacterData.bag_count_for(CharacterData.ITEM_EQUIPMENT) < cap:
		CharacterData.inventory.append({
			"id": "probe_filler_equip", "name": "占位", "count": 1,
			"type": CharacterData.ITEM_EQUIPMENT,
		})
	_check(CharacterData.bag_count_for(CharacterData.ITEM_EQUIPMENT) == cap,
		"装备分背包铺到上限 %d（题目成立）" % cap)
	w2.player.global_position = Vector2(shrine.get("pos", Vector2.ZERO))
	w2.call("_update_interaction")
	w2.call("_on_interact")
	_check(w2.get("_resources").has(NID), "主背包满时石台**不消失**（彩蛋不能被吞掉）")
	_check(not w2.call("_nodes_table").has(NID), "背包满时也不写永久标记")
	_check(_said(w2).contains("背包已满"), "满了要给原因", _said(w2))
	_check(_said(w2).contains("问天剑"), "回执点名放不下的是这把剑", _said(w2))
	_check(_inv_swords().size() == 1, "满包这一次没有凭空多发剑",
			"%d 件" % _inv_swords().size())
	_drop_from_inventory("probe_filler_equip")
	_check(CharacterData.bag_count_for(CharacterData.ITEM_EQUIPMENT) < cap,
		"占位料已清干净，不脏后面的题")

	# ===== 9. 自愈：已取走但身上没有 → 补发 =====
	# ⚠ 必须靠**新世界的 _ready 自己跑**这条自愈，不能探针直接调 _ensure_reliquary_reward()：
	#   直接调的话，把生产调用点删掉探针照样全绿（变异③ 就是这么被抓出来的）。
	w2.call("_nodes_table")[NID] = {"taken": 1.0}
	# 把剑从身上彻底清干净（模拟「剑丢了但设施早已永久消失」）
	_drop_from_inventory(EID)
	w2.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _has_sword(), "现场：玩家确实不再持有这把剑（题目成立）")
	var w3 = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w3)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_has_sword(), "重进大陆时 _ready 的自愈把剑补回来（彩蛋不会永久丢）")
	_check(not w3.get("_resources").has(NID), "补发不会让石台又长回来")
	w3.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ===== 10. 拔完立刻死：走真实死亡回滚，自愈要在回滚之后把剑捞回来 =====
	# 这一节锁的是 _on_player_died 里「回滚 → _ensure_reliquary_reward」的顺序，
	# 不是探针自己调一遍私有函数：删掉那行调用就会红。
	# 金丝雀 = 快照之后塞进永久背包的一件东西，回滚真的发生时它会消失；
	# 只有「回滚确实吞了背包」+「剑又回来了」同时成立，才证明的是自愈在起作用。
	_reset_to_untaken()
	_check(not _has_sword(), "现场：身上没剑、nodes 里没标记（题目成立）")
	var w4 = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w4)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(w4.get("_resources").has(NID), "全新世界里石台确实会生成")
	CharacterData.inventory.append({"id": "canary", "name": "金丝雀", "count": 1,
			"type": CharacterData.ITEM_MATERIAL})
	w4.player.global_position = Vector2(_shrine(w4).get("pos", Vector2.ZERO))
	w4.call("_update_interaction")
	w4.call("_on_interact")
	_check(_inv_swords().size() == 1, "本局拔到了剑（快照之后才进背包）")
	w4.call("_on_player_died")
	# 死亡协程同步跑到 await 才返回；立刻置 _leaving 让 3 秒后的离场自己空转
	w4.set("_leaving", true)
	_check(_canary_gone(), "回滚真的把快照之后的永久背包吞掉了（题目成立）")
	_check(_has_sword(), "拔完立刻死：剑被自愈捞回来（不是靠快照）")
	_check(w4.call("_nodes_table").has(NID), "死后永久标记仍在，石台不会长回来")
	_check(int(w4.get("_run_items").size()) == 0, "局内背包照旧随死亡清空")
	print("")
