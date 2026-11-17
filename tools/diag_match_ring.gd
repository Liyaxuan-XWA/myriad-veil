extends Node2D
## 观澜「水镜环」在棋局里的伤害构成（2026-11-06 用户问：为什么下棋模式里这么高）
##
## 它不判 PASS/FAIL，只回答三个问题：
##   ① 一次水镜环铺出**几枚**环（本体 + 每具镜像各一枚？），每枚 tick 几次；
##   ② 单次 tick 的伤害，和同一只棋子其它招式的单次伤害比是多少；
##   ③ 战报台账里「镜环场」这一行占它总输出的多少。
## 用法：godot --headless --path . res://tools/diag_match_ring.tscn -- --no-save

const REF := "boss_02"
const TARGET := "boss_04"
const CELLS := [Vector2i(1, 4), Vector2i(4, 1)]
const WINDOW := 22.0

var _rings: Array = []          ## 活过的每一枚环：{id, by, radius, dur, dmg, ticks}


func _ready() -> void:
	print("\n########## 观澜 · 棋局水镜环构成 ##########")
	var card := MatchAdapter.spawn_piece(self, TARGET, 0, CELLS[0])
	var ref := MatchAdapter.spawn_piece(self, REF, 1, CELLS[1])
	if card == null or ref == null:
		print("生成失败")
		get_tree().quit(2)
		return
	print("  棋子攻击力=%.0f 最大血=%.0f ｜ 量尺攻击力=%.0f 最大血=%.0f" % [
		float(card.get("attack_power")), float(card.get("max_hp")),
		float(ref.get("attack_power")), float(ref.get("max_hp"))])
	print("  名义 DPS（表里算出来的）=%.0f" % float(MatchDB.piece_stats(TARGET).get("dps", 0.0)))

	var t := 0.0
	while t < WINDOW:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(card) or not is_instance_valid(ref):
			break
		_scan_rings(card)

	print("\n  ── 环的实测 ──")
	var ring_total := 0.0
	var ring_ticks := 0
	for r in _rings:
		var e: Dictionary = r
		var ticks := int(e["ticks"])
		ring_total += float(e["dmg"]) * float(ticks)
		ring_ticks += ticks
		print("     来源=%-10s 半径=%.0f 时长=%.1fs 单次=%.0f 实际 tick=%d ⇒ 这枚环合计=%.0f" % [
			String(e["by"]), float(e["radius"]), float(e["dur"]), float(e["dmg"]),
			ticks, float(e["dmg"]) * float(ticks)])
	print("     环共 %d 枚 · tick 共 %d 次 · 合计伤害≈%.0f" % [
		_rings.size(), ring_ticks, ring_total])

	print("\n  ── 战报台账（它自己那侧的每一行）──")
	var rows: Dictionary = card.report_rows
	var tot: float = card.report_total()
	var keys: Array = rows.keys()
	keys.sort_custom(func(a, b): return float(rows[a]) > float(rows[b]))
	for k in keys:
		print("     %-14s %8.0f   %5.1f%%" % [String(k), float(rows[k]),
				100.0 * float(rows[k]) / maxf(tot, 1.0)])
	print("     %-14s %8.0f" % ["合计", tot])
	get_tree().quit(0)


## 扫场上活着的环，记下它的参数；tick 次数按环自己的存活时长推。
func _scan_rings(card: Node) -> void:
	for c in get_children():
		if not (c is MirrorRingField):
			continue
		var f := c as MirrorRingField
		var id := f.get_instance_id()
		var found := false
		for r in _rings:
			if int((r as Dictionary)["id"]) == id:
				var e: Dictionary = r
				e["ticks"] = maxi(int(e["ticks"]), int(f._age / MirrorRingField.TICK) + 1)
				e["seen_end"] = f._age
				found = true
				break
		if found:
			continue
		var by := "已释放的来源"
		if is_instance_valid(f.source_unit):
			by = "本体" if f.source_unit == card else \
					("镜像" if f.source_unit is MirrorImage else String(f.source_unit.name))
		_rings.append({"id": id, "by": by, "radius": f.radius, "dur": f.duration,
				"dmg": f.damage, "ticks": 0, "seen_end": f._age})
