extends Node
## 锻造最优路径模拟器（2026-11-04）
## 用真实的 CharacterData.enhance_item / _roll_ascend_gain / AttributeDB 区间跑，
## 输出写到 output/forge_sim_report.txt（Windows 控制台会把中文吞掉）。

const OUT := "D:/GodotProjects/myriad-veil/output/forge_sim_report.txt"
const CRYSTAL := "mat_duanzaojingshi"
const CAP_AT_HUASHEN := "仙器"
const RUNS := 4000

var lines: Array[String] = []


func _log(s: String) -> void:
	lines.append(s)


func _ready() -> void:
	CharacterData.current_realm = "化神"
	_part_candidates()
	_part_trace("eq_zhenxu_jia", AttributeDB.ATTR_HP_MAX)
	_part_trace("eq_huolin_jia", AttributeDB.ATTR_HP_MAX)
	_part_trace("eq_changye_ren", AttributeDB.ATTR_STRENGTH)
	_part_monte("eq_zhenxu_jia", AttributeDB.ATTR_HP_MAX)
	_part_monte("eq_changye_ren", AttributeDB.ATTR_STRENGTH)
	_part_extra_cycles()
	_part_realm_ladder()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("OPEN_FAIL")
	else:
		f.store_string("\n".join(lines))
		f.close()
	print("SIM_DONE lines=", lines.size())
	get_tree().quit()


func _p(arr: Array, f: float):
	if arr.is_empty():
		return 0
	return arr[clampi(int(arr.size() * f), 0, arr.size() - 1)]


func _make_item(eid: String) -> Dictionary:
	var tpl: Dictionary = ItemDB.get_equipment_template(eid)
	var it: Dictionary = tpl.duplicate(true)
	it["type"] = CharacterData.ITEM_EQUIPMENT
	it["id"] = String(tpl.get("equipment_id", eid))
	it["enhancement_level"] = 0
	it["enhance_fail_count"] = 0
	it["is_broken"] = false
	return it


func _panel(item: Dictionary) -> String:
	var parts: Array[String] = []
	var attrs: Dictionary = item["attributes"]
	for k in attrs.keys():
		var key := String(k)
		var flag := "" if AttributeDB.can_enhance(key) else "[锁]"
		parts.append("%s%s=%s" % [flag, AttributeDB.attr_name(key),
			str(roundf(float(attrs[k]) * 10.0) / 10.0)])
	return "  ".join(parts)


## ---------- 1. 找出基础值最高的母本 ----------
func _part_candidates() -> void:
	_log("========== 1. 母本候选（非法宝，按基础值排） ==========")
	var rows: Array = []
	for tpl in ItemDB.EQUIPMENT_TEMPLATES:
		var d: Dictionary = tpl
		if String(d.get("equipment_type", "")) == "treasure":
			continue
		var attrs: Dictionary = d.get("attributes", {})
		var enh_total := 0.0
		var locked := 0
		for k in attrs.keys():
			if AttributeDB.can_enhance(String(k)):
				enh_total += float(attrs[k])
			else:
				locked += 1
		rows.append({
			"id": String(d.get("equipment_id", "")),
			"name": String(d.get("equipment_name", "")),
			"grade": String(d.get("equipment_grade", "")),
			"type": String(d.get("equipment_type", "")),
			"enh_total": enh_total,
			"n": attrs.size(),
			"locked": locked,
			"panel": _panel(d),
		})
	rows.sort_custom(func(a, b): return float(a["enh_total"]) > float(b["enh_total"]))
	for i in mini(12, rows.size()):
		var r: Dictionary = rows[i]
		_log("#%02d %-6s %-4s %s  词条%d(锁%d) 可强化合计%.1f  |  %s | %s" % [
			i + 1, r["grade"], r["type"], r["name"], int(r["n"]), int(r["locked"]),
			float(r["enh_total"]), r["id"], r["panel"]])
	_log("")


## ---------- 2. 理论极限：每锤大成功、全压同一条 ----------
func _part_trace(eid: String, affix: String) -> void:
	var item := _make_item(eid)
	var rng: Dictionary = AttributeDB.enhance_range(affix)
	var hi := float(rng.get("max", 0.0))
	_log("========== 2. 理论极限 %s（%s）：目标词条 %s，区间上限 +%.1f/级 ==========" % [
		eid, String(item.get("equipment_name", "")), AttributeDB.attr_name(affix), hi])
	_log("起点（%s +0）：%s" % [String(item["equipment_grade"]), _panel(item)])
	var grade := String(item["equipment_grade"])
	var crystals := 0
	var hammers := 0
	var cycle := 0
	var start_val := float(item["attributes"][affix])
	while grade != CAP_AT_HUASHEN:
		cycle += 1
		var cost := maxi(1, ItemDB.grade_index(grade) + 1)
		var attrs: Dictionary = item["attributes"]
		# 5 次大成功 = +10 级，每次给「同一条 × 2 × 区间上限」
		for k in 5:
			attrs[affix] = float(attrs[affix]) + 2.0 * hi
			hammers += 1
			crystals += cost
		_log("  [%d] %s 敲满 +10（5 锤大成功，每锤 +%d，共 +%d）→ %s（锤耗 %d/锤）" % [
			cycle, grade, int(round(2.0 * hi)), int(round(10.0 * hi)), _panel(item), cost])
		# 进阶：真函数，无随机，每条可强化词条 × 1.5
		var gains: Array = CharacterData._roll_ascend_gain(item)
		var next_g := ItemDB.next_grade(grade)
		item["equipment_grade"] = next_g
		hammers += 1
		crystals += cost
		var gt: Array[String] = []
		for g in gains:
			gt.append("%s+%.1f" % [AttributeDB.attr_name(String(g["attr_id"])), float(g["amount"])])
		_log("      进阶 %s→%s（1 锤，耗 %d）本轮奖励 %s → %s" % [
			grade, next_g, cost, " ".join(gt), _panel(item)])
		grade = next_g
	_log("  合计：锤数 %d　晶石 %d　%s 终值 %.1f（起点 %.1f，×%.2f）" % [
		hammers, crystals, AttributeDB.attr_name(affix),
		float(item["attributes"][affix]), start_val,
		float(item["attributes"][affix]) / maxf(0.001, start_val)])
	_log("  终面板：%s" % _panel(item))
	_log("")


## ---------- 3. 真实蒙特卡洛：全程走 enhance_item() ----------
func _part_monte(eid: String, affix: String) -> void:
	var tpl: Dictionary = ItemDB.get_equipment_template(eid)
	var n_affix: int = (tpl.get("attributes", {}) as Dictionary).size()
	var ok_finals: Array[float] = []
	var ok_panels: Array[float] = []
	var ok_hammers: Array[int] = []
	var ok_crystals: Array[int] = []
	var ok_great: Array[int] = []
	var ok_great_t: Array[int] = []
	var ok_fail: Array[int] = []
	var stop_at: Dictionary = {}
	var broken_total := 0
	var best_val := -1.0
	var best_steps: Array = []
	for r in RUNS:
		var item := _make_item(eid)
		if CharacterData.count_material(CRYSTAL) < 600:
			CharacterData.grant_material_guaranteed(CRYSTAL, 200000)
		var before := CharacterData.count_material(CRYSTAL)
		var hammers := 0
		var great := 0
		var great_t := 0
		var fails := 0
		# 每个品阶一桶：大成功 / 其中命中目标条 / 成功 / 失败 / 进阶失败 / 本阶结束面板
		var steps: Array = []
		var cur_grade := String(item["equipment_grade"])
		var bucket: Dictionary = {}
		while true:
			var res: Dictionary = CharacterData.enhance_item(item)
			if not bool(res.get("ok", false)):
				break
			hammers += 1
			var rr := String(res.get("result", ""))
			var is_asc := rr == ItemDB.ENHANCE_RESULT_ASCEND \
					or rr == ItemDB.ENHANCE_RESULT_ASCEND_FAIL
			var gb := String(res.get("grade_before", cur_grade))
			if not is_asc and gb != cur_grade:
				bucket["panel"] = _panel(item)
				steps.append(bucket)
				cur_grade = gb
				bucket = {}
			if rr == ItemDB.ENHANCE_RESULT_GREAT:
				great += 1
				bucket["great"] = int(bucket.get("great", 0)) + 1
				var g0: Array = res["attr_gains"]
				if not g0.is_empty() and String(g0[0]["attr_id"]) == affix:
					great_t += 1
					bucket["great_t"] = int(bucket.get("great_t", 0)) + 1
			elif rr == ItemDB.ENHANCE_RESULT_SUCCESS:
				bucket["succ"] = int(bucket.get("succ", 0)) + 1
			elif rr == ItemDB.ENHANCE_RESULT_FAIL:
				fails += 1
				bucket["fail"] = int(bucket.get("fail", 0)) + 1
			elif rr == ItemDB.ENHANCE_RESULT_BROKEN:
				fails += 1
				bucket["fail"] = int(bucket.get("fail", 0)) + 1
				broken_total += 1
			elif rr == ItemDB.ENHANCE_RESULT_ASCEND_FAIL:
				bucket["afail"] = int(bucket.get("afail", 0)) + 1
			if is_asc:
				bucket["panel"] = _panel(item)
				steps.append(bucket)
				cur_grade = String(res.get("grade_after", cur_grade))
				bucket = {}
		bucket["panel"] = _panel(item)
		if bucket.size() > 1:
			steps.append(bucket)
		var used := before - CharacterData.count_material(CRYSTAL)
		var val := float(item["attributes"][affix])
		var tot := 0.0
		var attrs: Dictionary = item["attributes"]
		for k in attrs.keys():
			tot += float(attrs[k])
		var made := String(item["equipment_grade"]) == CAP_AT_HUASHEN \
				and not bool(item.get("is_broken", false))
		if made:
			ok_finals.append(val)
			ok_panels.append(tot)
			ok_hammers.append(hammers)
			ok_crystals.append(used)
			ok_great.append(great)
			ok_great_t.append(great_t)
			ok_fail.append(fails)
			if val > best_val:
				best_val = val
				best_steps = steps
		else:
			var sg := String(item["equipment_grade"])
			if bool(item.get("is_broken", false)):
				sg += "（破损）"
			stop_at[sg] = int(stop_at.get(sg, 0)) + 1
	ok_finals.sort()
	ok_panels.sort()
	ok_hammers.sort()
	ok_crystals.sort()
	ok_great.sort()
	ok_great_t.sort()
	ok_fail.sort()
	var made_n := ok_finals.size()
	_log("========== 3. 蒙特卡洛 %s（%s，%d 条词条）× %d 次，全程真实 enhance_item ==========" % [
		eid, String(tpl.get("equipment_name", "")), n_affix, RUNS])
	_log("  一次成型（敲到 %s 且没破损）：%d / %d = %.1f%%　其中破损 %d 件" % [
		CAP_AT_HUASHEN, made_n, RUNS, 100.0 * made_n / RUNS, broken_total])
	var st: Array[String] = []
	for k in stop_at.keys():
		st.append("%s %d件" % [String(k), int(stop_at[k])])
	_log("  未成型的去向：%s" % "　".join(st))
	if made_n == 0:
		_log("")
		return
	_log("  【成型件】%s 终值：最差 %.1f　P10 %.1f　中位 %.1f　P90 %.1f　最好 %.1f" % [
		AttributeDB.attr_name(affix), ok_finals[0], _p(ok_finals, 0.10), _p(ok_finals, 0.50),
		_p(ok_finals, 0.90), ok_finals[made_n - 1]])
	_log("  【成型件】面板词条合计：中位 %.1f　P90 %.1f　最好 %.1f" % [
		_p(ok_panels, 0.5), _p(ok_panels, 0.9), ok_panels[made_n - 1]])
	_log("  【成型件】锤数：最少 %d　中位 %d　P90 %d（理论最短 30）" % [
		ok_hammers[0], _p(ok_hammers, 0.5), _p(ok_hammers, 0.9)])
	_log("  【成型件】晶石：最少 %d　中位 %d　P90 %d（理论最低 90）" % [
		ok_crystals[0], _p(ok_crystals, 0.5), _p(ok_crystals, 0.9)])
	_log("  【成型件】大成功总次数：中位 %d　P90 %d；其中命中这条词条：中位 %d　P90 %d" % [
		_p(ok_great, 0.5), _p(ok_great, 0.9), _p(ok_great_t, 0.5), _p(ok_great_t, 0.9)])
	_log("  【成型件】累计磨损：最少 %d　中位 %d　最多 %d（到 10 就破）" % [
		ok_fail[0], _p(ok_fail, 0.5), ok_fail[made_n - 1]])
	_log("  【最好一件 %s=%.1f 的逐级过程】" % [AttributeDB.attr_name(affix), best_val])
	var g_idx := 0
	for b in best_steps:
		g_idx += 1
		var d: Dictionary = b
		_log("    %d) 大成功 %d(中目标 %d)　成功 %d　失败 %d　进阶失败 %d　→ 本阶结束 %s" % [
			g_idx, int(d.get("great", 0)), int(d.get("great_t", 0)), int(d.get("succ", 0)),
			int(d.get("fail", 0)), int(d.get("afail", 0)), String(d.get("panel", ""))])
	_log("")


## ---------- 5. 「卡在低阶多攒几轮」值不值 ----------
func _part_extra_cycles() -> void:
	_log("========== 5. 进阶失败 = 在同一品阶多攒一个 +10 周期，值多少 ==========")
	_log("  规则核对：进阶失败 → 等级归零、品阶不变、**已得属性全部保留**、**不计磨损**")
	_log("  代价只是 1 锤 + 重敲一遍 +10 的晶石；而这批加值会被后面所有进阶继续 ×1.5")
	_log("")
	_log("  【真实函数逐值模拟·镇墟石甲，气血压满】")
	_log("  %4s %10s %10s %12s %14s" % ["额外轮", "凡品增量", "道器增量", "凡品晶石", "凡品气血终值"])
	var base_fan: Dictionary = _extra_final("凡品", 0)
	var base_dao: Dictionary = _extra_final("道器", 0)
	for nn in [0, 1, 2, 3, 5, 10]:
		var n := int(nn)
		var v_fan: Dictionary = _extra_final("凡品", n)
		var v_dao: Dictionary = _extra_final("道器", n)
		_log("  %+5d %10.1f %10.1f %12d %14.1f　（同 n 放道器：终值 %.1f / 晶石 %d）" % [
			n,
			float(v_fan["hp"]) - float(base_fan["hp"]),
			float(v_dao["hp"]) - float(base_dao["hp"]),
			int(v_fan["crystal"]), float(v_fan["hp"]),
			float(v_dao["hp"]), int(v_dao["crystal"])])
	_log("")
	_log("  【按成功率推：进阶失败率越高，终值越高（估算模型，与 MC 中位对齐）】")
	_log("    一轮 +10 的面板合计增量 ≈ 16.7；该轮后面还剩下 k 次进阶则 ×1.5^k")
	_log("    5 个品阶各 1 轮 = 16.7×(7.59+5.06+3.38+2.25+1.5) = 330 面板（加基础值 73×7.59=554）")
	for pp in [1.0, 0.8, 0.6, 0.5, 0.3]:
		var p := float(pp)
		var extra_per_grade := (1.0 - p) / p
		var extra_panel := extra_per_grade * 330.4
		_log("    进阶成功率 %.0f%%：每阶期望多 %s 轮 → 面板期望 %.0f（+%.0f）　磨损不受影响" % [
			p * 100.0, str(round(extra_per_grade * 100.0) / 100.0),
			884.0 + extra_panel, extra_panel])
	_log("")


## 在 dump_grade 多攒 n 轮（每轮 5 锤大成功 + 1 锤失败的进阶），其余立刻成功
func _extra_final(dump_grade: String, n: int) -> Dictionary:
	var item := _make_item("eq_zhenxu_jia")
	var affix := String(AttributeDB.ATTR_HP_MAX)
	var hi := float(AttributeDB.enhance_range(affix).get("max", 0.0))
	var grade := String(item["equipment_grade"])
	var crystals := 0
	var hammers := 0
	while grade != CAP_AT_HUASHEN:
		var cost := maxi(1, ItemDB.grade_index(grade) + 1)
		var rounds: int = 1 + (n if grade == dump_grade else 0)
		for c in rounds:
			var attrs: Dictionary = item["attributes"]
			for k in 5:
				attrs[affix] = float(attrs[affix]) + 2.0 * hi
				hammers += 1
				crystals += cost
			if c < rounds - 1:
				# 失败的那一锤：只扣晶石，不给 ×1.5
				hammers += 1
				crystals += cost
			else:
				CharacterData._roll_ascend_gain(item)
				hammers += 1
				crystals += cost
				item["equipment_grade"] = ItemDB.next_grade(grade)
		grade = String(item["equipment_grade"])
	return {"hp": float(item["attributes"][affix]), "crystal": crystals, "hammer": hammers}


## ---------- 4. 各境界能敲到什么程度 ----------
func _part_realm_ladder() -> void:
	_log("========== 4. 境界阶梯（镇墟石甲·气血上限：每阶 +10 全大成功压气血） ==========")
	for realm in ["练气", "筑基", "结丹", "元婴", "化神"]:
		CharacterData.current_realm = realm
		var cap := String(ItemDB.realm_grade_cap(realm))
		var item := _make_item("eq_zhenxu_jia")
		var grade := String(item["equipment_grade"])
		var ascends := 0
		var crystals := 0
		while grade != cap:
			var cost := maxi(1, ItemDB.grade_index(grade) + 1)
			var attrs: Dictionary = item["attributes"]
			for k in 5:
				attrs[AttributeDB.ATTR_HP_MAX] = float(attrs[AttributeDB.ATTR_HP_MAX]) + 8.0
				crystals += cost
			CharacterData._roll_ascend_gain(item)
			crystals += cost
			grade = ItemDB.next_grade(grade)
			ascends += 1
		# 到本境界上限后，真实 enhance_item 是否还受理
		var probe: Dictionary = item.duplicate(true)
		probe["equipment_grade"] = grade
		probe["enhancement_level"] = 0
		CharacterData.grant_material_guaranteed(CRYSTAL, 1000)
		var res: Dictionary = CharacterData.enhance_item(probe)
		_log("  %-3s → 上限 %s：%d 次进阶（×%.2f）　气血 %.1f　共 %d 锤 / %d 晶石　到上限后再敲：%s" % [
		realm, cap, ascends, pow(1.5, ascends),
		float(item["attributes"][AttributeDB.ATTR_HP_MAX]), ascends * 6, crystals,
		String(res.get("message", ""))])
	CharacterData.current_realm = "化神"
	_log("")
