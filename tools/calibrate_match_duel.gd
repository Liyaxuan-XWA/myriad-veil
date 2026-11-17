extends Node2D
## 量**对决里的有效 DPS**，不是打木桩的名义 DPS（2026-11-03 用户报：虎妖伤害太低、剑客太强）。
##
## 为什么必须另测一遍：`MatchDB.ATTACK_CALIB` 是拿假人 10 秒窗口校出来的
## —— 那只 BOSS 全程对着不动的木桩输出。真实对决里它要先走位接近、会被打断、
## 会转阶段、大招前摇 1.5 秒里对面也在打，于是"名义 1062 DPS"和"实际打到对面身上多少"
## 可以差好几倍。用户看到的"太低/太强"是后者，所以校准也必须按后者来。
##
## 量法：每只棋子都对同一把**量尺**（两仪·护体反击、倍率中位）打固定 22 秒
## （比一个战斗窗口 ROUND_SECONDS=15 长一点，保证两边都至少完整出手一轮），
## 记录它实际打到量尺身上的伤害 → 有效 DPS，再和名义 DPS 对照。
## 用法：godot --headless --path . res://tools/calibrate_match_duel.tscn -- --no-save
##       可选 `-- only=boss_huyao,boss_01_c` 只测几只、`-- secs=22` 改窗口

const REF := "boss_02"          ## 量尺：两仪真人（中位肉度 + 中位输出 + 会护体反击）
const CELLS := [Vector2i(1, 4), Vector2i(4, 1)]

var window := 22.0
var only: Array = []


func _ready() -> void:
	for raw in OS.get_cmdline_user_args():
		var t := String(raw)
		if t.begins_with("only="):
			only = t.trim_prefix("only=").split(",", false)
		if t.begins_with("secs="):
			window = maxf(4.0, float(t.trim_prefix("secs=")))
	var list: Array = only if not only.is_empty() else MatchDB.CARD_POOL.duplicate()
	print("CALIB 对决有效 DPS（量尺=%s，窗口=%.0f 秒）" % [REF, window])
	print("CALIB 卡                     名义DPS   有效DPS   有效/名义   自己掉血%   首次出手")
	for raw in list:
		var id := String(raw)
		if id == REF:
			continue
		var r := await _measure(id)
		var nominal: float = float(MatchDB.piece_stats(id).get("dps", 0.0))
		var eff := float(r["dps"])
		print("CALIB %-22s %8.0f %10.0f %10.2f %10.0f%% %8.1fs  两侧 %s（差 %d）" % [
				id, nominal, eff, (eff / nominal if nominal > 0.0 else 0.0),
				float(r["lost_pct"]), float(r["first"]), String(r["each"]),
				int(r["side_gap"])])
	# 量尺自己也要跑一遍，否则"某只特别强"可能只是"量尺今天特别脆"
	var self_r := await _measure(REF)
	print("CALIB %-22s %8.0f %10.0f %10.2f %10.0f%% %8.1fs  ← 量尺对照（自己打自己应该≈1.0）" % [
			REF + "(自检)", float(MatchDB.piece_stats(REF).get("dps", 0.0)),
			float(self_r["dps"]), float(self_r["dps"])
			/ float(MatchDB.piece_stats(REF).get("dps", 1.0)),
			float(self_r["lost_pct"]), float(self_r["first"])])
	get_tree().quit(0)


## 一只棋子 vs 量尺，跑 window 秒；返回它打出的有效 DPS、自己掉血比例、首次出手用时。
## 两边各跑一次（先后手与站位互换）取**平均**：取较高那次会把强牌再吹高一截，
## 校准是要把"平时打多少"钉住，不是"最好一局打多少"。
func _measure(id: String) -> Dictionary:
	var sides: Array = []
	for side in 2:
		sides.append(await _one(id, side))
	var sum_dps := 0.0
	var sum_lost := 0.0
	var first := -1.0
	for r in sides:
		sum_dps += float(r["dps"])
		sum_lost += float(r["lost_pct"])
		if float(r["first"]) >= 0.0 and (first < 0.0 or float(r["first"]) < first):
			first = float(r["first"])
	return {"dps": sum_dps / maxf(float(sides.size()), 1.0),
			"lost_pct": sum_lost / maxf(float(sides.size()), 1.0),
			"first": first,
			"each": "%0.0f·%0.0f" % [float(sides[0]["dps"]), float(sides[1]["dps"])],
			"side_gap": absf(float(sides[0]["dps"]) - float(sides[1]["dps"]))}


func _one(id: String, side: int) -> Dictionary:
	var card_id := id
	var ref_id := REF
	var card_cell: Vector2i = CELLS[0]
	var ref_cell: Vector2i = CELLS[1]
	if side == 1:
		card_cell = CELLS[1]
		ref_cell = CELLS[0]
	var card := MatchAdapter.spawn_piece(self, card_id, 0, card_cell)
	var ref := MatchAdapter.spawn_piece(self, ref_id, 1, ref_cell)
	if card == null or ref == null:
		print("CALIB 生成失败 ", id)
		return {"dps": 0.0, "lost_pct": 0.0, "first": -1.0}
	await get_tree().physics_frame
	var ref_max := float(ref.get("max_hp"))
	var card_max := float(card.get("max_hp"))
	var ref_lowest := ref_max
	var card_lowest := card_max
	var first := -1.0
	var t := 0.0
	while t < window:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(card) or not is_instance_valid(ref):
			break
		ref_lowest = minf(ref_lowest, float(ref.get("current_hp")))
		card_lowest = minf(card_lowest, float(card.get("current_hp")))
		if first < 0.0 and ref_lowest < ref_max:
			first = t
		if BossBase.is_unit_dead(ref) or BossBase.is_unit_dead(card):
			break
	var dealt := ref_max - ref_lowest
	var lost_pct := (card_max - card_lowest) / maxf(card_max, 1.0) * 100.0
	var out := {"dps": dealt / maxf(t, 0.001), "lost_pct": lost_pct, "first": first}
	if is_instance_valid(card):
		card.queue_free()
	if is_instance_valid(ref):
		ref.queue_free()
	await get_tree().process_frame
	return out
