extends Node
## 进阶失败计入磨损 + 铭牌磨损刻度分色（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_forge_ascend_wear.tscn -- --no-save
##
## 用户原话：「改成进阶失败也增加破损，并且在锻打铭牌的磨损显示的颜色为进阶失败时境界对应的
##   颜色，将普通磨损的颜色换为黑色。」
## 判据：
##   · 装备进阶失败：fail_count +1、ascend_fail_count +1，累计到 10 就 broken；
##     法宝不记磨损（铭牌不显示刻度）；
##   · 铭牌刻度：按发生顺序逐格（最旧在左）；普通失败 = 亮灰，进阶失败 = 失败当时品阶色，
##     进阶到更高品阶后旧格颜色不变（修掉「高阶覆盖低阶」）；
##   · 全部数值现读字段，不硬编码。

const CRYSTAL := "mat_duanzaojingshi"
const NORMAL_GRAY := Color(0.72, 0.74, 0.78, 1.0)

var _passes := 0
var _fails: Array = []
var _saved_inv: Array = []
var _saved_realm := ""


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


func _tpl(eid: String) -> Dictionary:
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		if String((raw as Dictionary).get("equipment_id", "")) == eid:
			return CharacterData.make_equipment_instance(raw as Dictionary)
	return {}


func _ready() -> void:
	print("\n########## 进阶失败计入磨损 · 铭牌分色 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved_inv = CharacterData.inventory.duplicate(true)
	_saved_realm = CharacterData.current_realm
	CharacterData.force_enhance_success = false
	CharacterData.grant_material(CRYSTAL, 999)
	seed(20261113)

	var base := _tpl("eq_qingfengjian")
	_check(not base.is_empty(), "取到测试装备")
	if base.is_empty():
		return
	base["enhancement_level"] = ItemDB.MAX_ENHANCE

	# ===== 1. 装备进阶失败：+1 磨损、+1 进阶失败计数、等级归零、属性不变 =====
	var fail_item := {}
	var fail_res := {}
	for i in 80:
		var it := base.duplicate(true)
		it["enhancement_level"] = ItemDB.MAX_ENHANCE
		var attrs_before := (it["attributes"] as Dictionary).duplicate(true)
		var res := CharacterData.enhance_item(it)
		if String(res.get("result", "")) == ItemDB.ENHANCE_RESULT_ASCEND_FAIL:
			fail_item = it
			fail_res = res
			_check((it["attributes"] as Dictionary) == attrs_before,
				"进阶失败不再涨词条（属性原样）")
			break
	_check(not fail_item.is_empty(), "80 次内观察到一次进阶失败（20% × 80）")
	if not fail_item.is_empty():
		_check(int(fail_item.get("enhance_fail_count", -1)) == 1,
			"装备进阶失败：磨损 +1", str(fail_item.get("enhance_fail_count")))
		_check(int(fail_item.get("enhance_ascend_fail_count", -1)) == 1,
			"进阶失败计数 +1", str(fail_item.get("enhance_ascend_fail_count")))
		_check(int(fail_item.get("enhancement_level", -1)) == 0, "等级归零")
		_check(not bool(fail_item.get("is_broken", false)), "磨损 1/10：还没破损")
		_check(String(fail_res.get("message", "")).contains("磨损 1 / 10"),
			"回执写明磨损 1 / 10", String(fail_res.get("message", "")))
		var seq: Array = fail_item.get("enhance_wear_seq", [])
		var last: Dictionary = seq[-1] if not seq.is_empty() else {}
		_check(String(last.get("k", "")) == "a" and String(last.get("g", "")) == "凡品",
			"流水最后一条记住「进阶失败 + 失败时品阶」", str(last))

	# ===== 1b. 普通失败也进流水 =====
	var normal_item := {}
	for i in 80:
		var nit := base.duplicate(true)
		nit["enhancement_level"] = 0
		var nres := CharacterData.enhance_item(nit)
		if String(nres.get("result", "")) == ItemDB.ENHANCE_RESULT_FAIL:
			normal_item = nit
			break
	_check(not normal_item.is_empty(), "80 次内观察到一次普通失败")
	if not normal_item.is_empty():
		var nseq: Array = normal_item.get("enhance_wear_seq", [])
		var nlast: Dictionary = nseq[-1] if not nseq.is_empty() else {}
		_check(String(nlast.get("k", "")) == "n", "普通失败流水记 k=n", str(nlast))

	# ===== 2. 进阶成功不给磨损（对照） =====
	var ok_item := {}
	for i in 80:
		var it := base.duplicate(true)
		it["enhancement_level"] = ItemDB.MAX_ENHANCE
		var res := CharacterData.enhance_item(it)
		if String(res.get("result", "")) == ItemDB.ENHANCE_RESULT_ASCEND:
			ok_item = it
			break
	_check(not ok_item.is_empty(), "80 次内观察到一次进阶成功（80% × 80）")
	if not ok_item.is_empty():
		_check(int(ok_item.get("enhance_fail_count", -1)) == 0
				and int(ok_item.get("enhance_ascend_fail_count", -1)) == 0,
			"进阶成功不加磨损", "%s / %s" % [ok_item.get("enhance_fail_count"),
				ok_item.get("enhance_ascend_fail_count")])

	# ===== 3. 进阶失败也能敲到破损（9/10 起再失败一次）=====
	var broke_item := {}
	var broke_res := {}
	for i in 120:
		var it := base.duplicate(true)
		it["enhancement_level"] = ItemDB.MAX_ENHANCE
		it["enhance_fail_count"] = 9
		it["enhance_ascend_fail_count"] = 9
		var res := CharacterData.enhance_item(it)
		if String(res.get("result", "")) == ItemDB.ENHANCE_RESULT_BROKEN:
			broke_item = it
			broke_res = res
			break
	_check(not broke_item.is_empty(), "磨损 9/10 时进阶失败 → 直接破损")
	if not broke_item.is_empty():
		_check(bool(broke_item.get("is_broken", false)), "is_broken = true")
		_check(int(broke_item.get("enhance_fail_count", -1)) == 10
				and int(broke_item.get("enhance_ascend_fail_count", -1)) == 10,
			"磨损与进阶失败计数都到 10", "%s / %s" % [broke_item.get("enhance_fail_count"),
				broke_item.get("enhance_ascend_fail_count")])
		_check(String(broke_res.get("message", "")).contains("进阶失败")
				and String(broke_res.get("message", "")).contains("破损"),
			"回执写明「进阶失败……装备破损」", String(broke_res.get("message", "")))

	# ===== 4. 法宝不记磨损（它没有磨损刻度）=====
	CharacterData.current_realm = "化神"   # 解开法器法宝的境界锁
	var tr := CharacterData.make_treasure_instance(
		ItemDB.get_treasure_template("tr_huyao_ling"))
	tr["enhancement_level"] = 0
	var tr_fail := {}
	for i in 120:
		var it := tr.duplicate(true)
		var res := CharacterData.enhance_item(it)
		if String(res.get("result", "")) == ItemDB.ENHANCE_RESULT_ASCEND_FAIL:
			tr_fail = it
			break
	_check(not tr_fail.is_empty(), "120 次内观察到一次法宝进阶失败")
	if not tr_fail.is_empty():
		_check(int(tr_fail.get("enhance_fail_count", -1)) == 0
				and int(tr_fail.get("enhance_ascend_fail_count", -1)) == 0,
			"法宝进阶失败不记磨损（铭牌没有磨损刻度）",
			"%s / %s" % [tr_fail.get("enhance_fail_count"),
				tr_fail.get("enhance_ascend_fail_count")])
	CharacterData.current_realm = _saved_realm

	# ===== 5. 铭牌刻度：老档按「普通在前、进阶在后」合成 =====
	var panel := ForgePanel.new()
	add_child(panel)
	await _frames(3)
	panel.call("open")
	await _frames(6)
	var item := _tpl("eq_qingfengjian")
	item["equipment_grade"] = "灵器"
	item["enhance_fail_count"] = 5
	item["enhance_ascend_fail_count"] = 2
	panel._anvil_item = item
	panel.call("_refresh_content")
	await _frames(4)
	var pips: Array = panel.get("_plaque_pip_nodes")
	var grade_color := UIKit.grade_color("灵器")
	var empty_color: Color = panel.call("_pip_empty_color")
	_check(pips.size() == 10, "铭牌有 10 格磨损刻度", str(pips.size()))
	var c0: Color = (pips[0] as ColorRect).color
	var c2: Color = (pips[2] as ColorRect).color
	var c3: Color = (pips[3] as ColorRect).color
	var c4: Color = (pips[4] as ColorRect).color
	var c5: Color = (pips[5] as ColorRect).color
	_check(c0 == NORMAL_GRAY and c2 == NORMAL_GRAY,
		"老档合成：前 3 格普通失败 = 亮灰", "%s / %s" % [c0, c2])
	_check(c3 == grade_color and c4 == grade_color,
		"老档合成：后 2 格进阶失败 = 装备品阶色（灵器蓝）", "%s / %s" % [c3, c4])
	_check(c5 == empty_color, "第 6 格起是空位（原空色）", str(c5))

	# 显式流水：普通 / 进阶交错，进阶格各记各的品阶色；进阶到更高品阶也不改旧格
	item["equipment_grade"] = "仙器"
	item["enhance_wear_seq"] = [
		{"k": "n"}, {"k": "a", "g": "灵器"}, {"k": "n"}, {"k": "a", "g": "宝器"}]
	item["enhance_fail_count"] = 4
	item["enhance_ascend_fail_count"] = 2
	panel._anvil_item = item
	panel.call("_refresh_content")
	await _frames(3)
	_check((pips[0] as ColorRect).color == NORMAL_GRAY
			and (pips[1] as ColorRect).color == UIKit.grade_color("灵器")
			and (pips[2] as ColorRect).color == NORMAL_GRAY
			and (pips[3] as ColorRect).color == UIKit.grade_color("宝器"),
		"交错流水按发生顺序着色，进阶格不被当前品阶覆盖",
		"%s %s %s %s" % [(pips[0] as ColorRect).color, (pips[1] as ColorRect).color,
			(pips[2] as ColorRect).color, (pips[3] as ColorRect).color])

	# 没有进阶失败时：所有已磨损格都是亮灰
	item["enhance_wear_seq"] = []
	item["enhance_fail_count"] = 4
	item["enhance_ascend_fail_count"] = 0
	panel._anvil_item = item
	panel.call("_refresh_content")
	await _frames(3)
	var all_gray := true
	for i in 4:
		if (pips[i] as ColorRect).color != NORMAL_GRAY:
			all_gray = false
	_check(all_gray and (pips[4] as ColorRect).color == empty_color,
		"没有进阶失败：4 格全亮灰，第 5 格空")
	panel.call("close")
	await _frames(2)

	# 还原
	CharacterData.inventory.clear()
	CharacterData.inventory.append_array(_saved_inv)
	print("")
