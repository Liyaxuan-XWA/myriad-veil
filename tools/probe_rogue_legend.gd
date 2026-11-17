extends Node
## 通用池传说档解锁门禁自检（设计案 §9.2，2026-11-08 补）
##
## 起因：设计案写「通用池传说（不灭 / 洗髓）第 10 层后开放」，卡也确实在
## GENERIC_BUFFS 里，但 roll_choices() 以前只看 rarity_weight，不判层数 →
## 第 1 层就能抽到。典型的「文档登记了 ≠ 运行时读到」。
##
## 验两层：① 纯规则函数 legend_pool_open 的四条边界
##        ② **真实抽卡入口** roll_choices 确实调用了它（构造确定性牌池，不靠概率抽样）
##
## 用法：godot --headless --path . res://tools/probe_rogue_legend.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 把除 keep 外的所有卡都标成「已叠满」，让牌池只剩 keep —— 确定性，不靠随机抽样
func _pool_only(keep: Array) -> void:
	RogueRun.buffs.clear()
	for fam in ["generic", "sword"]:
		for raw in RogueDB.POOLS[fam]:
			var def: Dictionary = raw
			var id := String(def.get("id", ""))
			if id == "" or keep.has(id):
				continue
			RogueRun.buffs[id] = RogueDB.stack_cap(id)


func _ids(arr: Array) -> Array:
	var out: Array = []
	for raw in arr:
		out.append(String((raw as Dictionary).get("id", "")))
	return out


func _pick_one(fam: String, rarity: String) -> String:
	for raw in RogueDB.POOLS[fam]:
		var def: Dictionary = raw
		if String(def.get("rarity", "")) == rarity:
			return String(def.get("id", ""))
	return ""


func _ready() -> void:
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	print("\n########## 通用池传说档解锁门禁 ##########")
	RogueRun.start_run("sword")
	var legend := RogueDB.RARITY_LEGEND
	var common := RogueDB.RARITY_COMMON

	# ===== ① 纯规则 =====
	_check(RogueDB.GENERIC_LEGEND_FLOOR == 10, "解锁层常量 = 10",
		str(RogueDB.GENERIC_LEGEND_FLOOR))
	_check(not RogueRun.legend_pool_open("generic", legend, 1),
		"第 1 层：通用传说不进池")
	_check(RogueRun.legend_pool_open("generic", legend, 10),
		"第 10 层：通用传说进池")
	_check(not RogueRun.legend_pool_open("generic", legend, 9),
		"第 9 层边界：仍锁")
	_check(RogueRun.legend_pool_open("sword", legend, 1),
		"流派自己的传说不受影响")
	_check(RogueRun.legend_pool_open("generic", common, 1),
		"通用池普通卡不受影响")

	# ===== ② 真实抽卡入口 =====
	var generics := ["g_revive", "g_cleanse"]
	for id in generics:
		_check(not RogueDB.get_buff(id).is_empty(), "通用传说卡 %s 在表里" % id)

	RogueRun.floor_no = 1
	_pool_only(generics)
	var low := _ids(RogueRun.roll_choices(3, false))
	_check(low.is_empty(), "第 1 层真实三选一抽不到不灭 / 洗髓", str(low))
	var low_force := _ids(RogueRun.roll_choices(3, true))
	_check(low_force.is_empty(), "第 1 层 BOSS 保底稀有也绕不过门禁", str(low_force))

	RogueRun.floor_no = 9
	var edge := _ids(RogueRun.roll_choices(3, false))
	_check(edge.is_empty(), "第 9 层仍抽不到（边界）", str(edge))

	RogueRun.floor_no = 10
	var high := _ids(RogueRun.roll_choices(3, false))
	_check(high.has("g_revive") and high.has("g_cleanse"),
		"第 10 层两张通用传说都能抽到", str(high))

	# 流派传说 / 通用普通卡仍能在第 1 层出现（别把门禁写宽了）
	RogueRun.floor_no = 1
	var sword_legend := _pick_one("sword", legend)
	if sword_legend != "":
		_pool_only([sword_legend])
		var fam_pick := _ids(RogueRun.roll_choices(3, false))
		_check(fam_pick.has(sword_legend),
			"第 1 层仍能抽到本流派传说", "%s / %s" % [sword_legend, str(fam_pick)])
	else:
		_check(false, "剑修池里有传说卡可测")
	var gen_common := _pick_one("generic", common)
	_pool_only([gen_common])
	var common_pick := _ids(RogueRun.roll_choices(3, false))
	_check(common_pick.has(gen_common), "第 1 层仍能抽到通用普通卡",
		"%s / %s" % [gen_common, str(common_pick)])

	RogueRun.restore()
