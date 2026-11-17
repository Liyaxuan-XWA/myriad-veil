extends Node
## 试炼之路 · 数值实测（2026-11-08 用户报「第 1 层还没见到 BOSS 就死了」）
##
## 两段验证：
##  A. **模型**：从 RogueDB 真实表读 1~10 层，估「清波耗时 / 层内承伤 / 关间补给后净伤」，
##     打印曲线表并断言前几层能活到 BOSS、层间无断崖、难度单调递增。
##  B. **真实入口采样**：起一次 combat_arena（SOURCE_ROGUE），读场上小怪的 max_hp
##     与表是否一致，并真的触发一次「清一小关」看有没有回血。
##     ⚠ 只断言「表里 has(id)」抓不到「配置登记了但运行时没读」这类脱节，必须走真实入口。
##
## 估算口径（相对平衡用，不是精确战斗模拟）：
##   - 玩家裸装 HP 100 / 双抗 10，减伤走 AttributeDB.resist_reduction(10)
##   - 开局 DPS 18（普攻三段 10/10/14，扣掉走位与前摇的保守值），每层 4 次选卡 ×1.31
##   - 小怪每秒输出 = atk × 系数 / 1.8s 攻击循环 × 0.55 命中率（走位能躲掉一部分）
##   - 清波耗时 = 波内总 HP / 玩家 DPS；波内承伤 = 清波耗时 × 敌方 DPS × (1 − 玩家减伤)
##   - 每层 3 小关 × 3 波；每小关回 STAGE_HEAL_PCT%，进 BOSS 关再回 BOSS_STAGE_HEAL_PCT%
##
## 用法：godot --headless --path . res://tools/probe_rogue_balance.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

const PLAYER_MAX_HP := 100.0
const PLAYER_RESIST := 10.0
const PLAYER_BASE_DPS := 18.0
const PLAYER_DPS_GROWTH := 1.31
const ENEMY_ATTACK_CYCLE := 1.8
const HIT_RATIO := 0.55
const MAX_FLOOR := 10

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


# ===================== A. 数值模型 =====================

func _minion_dps(def: Dictionary, floor_no: int) -> float:
	var coeff := float(def.get("melee_coeff", 0.7))
	if String(def.get("kind", "")) == WorldEnemy.KIND_CULTIVATOR:
		coeff = float(def.get("cast_coeff", 0.8))
	return RogueDB.minion_atk(def, floor_no) * coeff / ENEMY_ATTACK_CYCLE * HIT_RATIO


func _wave_stats(floor_no: int, stage_no: int, wave_no: int) -> Dictionary:
	var ids := RogueDB.roll_wave(floor_no, stage_no, wave_no)
	var total_hp := 0.0
	var total_dps := 0.0
	var elites := 0
	for raw_id in ids:
		var id := String(raw_id)
		var def: Dictionary = RogueDB.MINIONS.get(id, {})
		if def.is_empty():
			continue
		total_hp += RogueDB.minion_hp(def, floor_no)
		total_dps += _minion_dps(def, floor_no)
		if id == "rogue_elite":
			elites += 1
	return {"count": ids.size(), "hp": total_hp, "dps": total_dps, "elites": elites}


func _layer_stats(floor_no: int) -> Dictionary:
	var player_dps := PLAYER_BASE_DPS * pow(PLAYER_DPS_GROWTH, float(floor_no - 1))
	var taken_mult := 1.0 - AttributeDB.resist_reduction(PLAYER_RESIST)
	var total_hp := 0.0
	var total_dmg := 0.0
	var total_sec := 0.0
	var total_count := 0
	var elites := 0
	var max_wave_sec := 0.0
	for stage in range(1, RogueDB.STAGES_PER_FLOOR):
		for wave in range(1, RogueDB.WAVES_PER_STAGE + 1):
			var w := _wave_stats(floor_no, stage, wave)
			var sec := float(w["hp"]) / player_dps
			total_hp += float(w["hp"])
			total_dmg += float(w["dps"]) * sec * taken_mult
			total_sec += sec
			total_count += int(w["count"])
			elites += int(w["elites"])
			max_wave_sec = maxf(max_wave_sec, sec)
	var heal_cap := (float(RogueDB.STAGES_PER_FLOOR - 1) * RogueDB.STAGE_HEAL_PCT
		+ RogueDB.BOSS_STAGE_HEAL_PCT) / 100.0 * PLAYER_MAX_HP
	# 回血不会超过实际损失
	var healed := minf(total_dmg, heal_cap)
	return {
		"floor": floor_no, "player_dps": player_dps, "enemy_hp": total_hp,
		"count": total_count, "elites": elites, "sec": total_sec,
		"max_wave_sec": max_wave_sec, "dmg": total_dmg,
		"heal": healed, "net": total_dmg - healed,
	}


func _run_model() -> Array:
	seed(20261108)   # roll_wave 有随机，固定种子让表格可复现
	print("\n层 | 怪数 | 精英 | 敌方总HP | 玩家DPS | 清层秒 | 承伤 | 补给 | 净伤")
	var rows: Array = []
	for f in range(1, MAX_FLOOR + 1):
		var r := _layer_stats(f)
		rows.append(r)
		print("%2d | %3d  | %2d   | %8.0f | %7.1f | %6.1f | %5.1f | %4.0f | %5.1f" % [
			f, int(r["count"]), int(r["elites"]), float(r["enemy_hp"]),
			float(r["player_dps"]), float(r["sec"]), float(r["dmg"]),
			float(r["heal"]), float(r["net"])])

	var f1: Dictionary = rows[0]
	_check(float(f1["net"]) < 70.0,
		"第 1 层：补给后净伤 < 70（100 血能活到 BOSS 且留余量）",
		"净伤 %.1f / 承伤 %.1f / 补给 %.0f" % [
			float(f1["net"]), float(f1["dmg"]), float(f1["heal"])])
	_check(int(f1["elites"]) == 0, "第 1 层不出精英", str(int(f1["elites"])))
	_check(int(f1["count"]) <= 16, "第 1 层总怪数已压到 16 只以内", str(int(f1["count"])))
	_check(float(f1["max_wave_sec"]) < 12.0,
		"第 1 层没有血牛（最慢一波 < 12 秒）", "%.1fs" % float(f1["max_wave_sec"]))
	_check(RogueDB.STAGE_HEAL_PCT > 0.0 and RogueDB.BOSS_STAGE_HEAL_PCT > 0.0,
		"关间补给已开启", "%.0f%% / %.0f%%" % [RogueDB.STAGE_HEAL_PCT, RogueDB.BOSS_STAGE_HEAL_PCT])

	# 前 3 层是教学缓冲，第 4 层起必须完全回到原曲线
	var relief_ok := true
	for f in range(4, MAX_FLOOR + 1):
		if not is_equal_approx(RogueDB.floor_relief(RogueDB.FLOOR_HP_RELIEF, f), 1.0) \
				or not is_equal_approx(RogueDB.floor_relief(RogueDB.FLOOR_ATK_RELIEF, f), 1.0):
			relief_ok = false
	_check(relief_ok, "第 4 层起缓冲归 1.0（后期曲线一分没动）")
	var boss_ok := true
	for f in range(3, MAX_FLOOR + 1):
		if not is_equal_approx(RogueDB.floor_relief(RogueDB.FLOOR_BOSS_RELIEF, f), 1.0):
			boss_ok = false
	_check(boss_ok, "第 3 层起 BOSS 缓冲归 1.0（BOSS 后期曲线不变）")
	var b1 := RogueDB.boss_hp(RogueDB.BOSS_TUTORIAL, 1)
	var b3 := RogueDB.boss_hp(RogueDB.BOSS_TUTORIAL, 3)
	_check(b1 < b3, "首层 BOSS 有教学缓冲（血低于第 3 层同档）",
		"%.0f vs %.0f" % [b1, b3])

	var rat := RogueDB.minion_atk(RogueDB.MINIONS["rogue_rat"] as Dictionary, 1)
	var rat3 := RogueDB.minion_atk(RogueDB.MINIONS["rogue_rat"] as Dictionary, 3)
	_check(rat < rat3 * 0.6, "第 1 层小怪攻击显著低于第 3 层（教学层）",
		"%.1f vs %.1f" % [rat, rat3])

	# 前期是教学爬升、后期是正式曲线；分两段验，别用一个阈值套 1~10 层
	var ramp_ok := true
	for i in range(1, 4):
		var ratio := float((rows[i] as Dictionary)["sec"]) 			/ maxf(0.1, float((rows[i - 1] as Dictionary)["sec"]))
		if ratio < 1.15 or ratio > 2.05:
			ramp_ok = false
	_check(ramp_ok, "1→4 层清层耗时渐进爬升（相邻 1.15~2.05×，无暴跳）")
	var flat_ok := true
	for i in range(4, rows.size()):
		var ratio2 := float((rows[i] as Dictionary)["sec"]) 			/ maxf(0.1, float((rows[i - 1] as Dictionary)["sec"]))
		if ratio2 < 0.75 or ratio2 > 1.40:
			flat_ok = false
	_check(flat_ok, "4~10 层正式曲线平稳（相邻 0.75~1.40×）")
	var overall := float((rows[rows.size() - 1] as Dictionary)["sec"]) 		/ maxf(0.1, float((rows[0] as Dictionary)["sec"]))
	_check(overall < 8.0, "第 10 层耗时没有失控（< 第 1 层 8×）", "%.2f×" % overall)
	return rows


# ===================== B. 真实入口采样 =====================

func _run_real_spawn() -> void:
	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	if rogue == null or player == null:
		_check(false, "真实战斗场景创建成功")
		RogueRun.restore()
		return

	var alive: Array = rogue.get("_alive")
	_check(alive.size() == RogueDB.wave_size(1, 1),
		"真实首波怪数 = 表里的 wave_size(1,1)",
		"%d / %d" % [alive.size(), RogueDB.wave_size(1, 1)])
	# 场上小怪的 max_hp 必须真的来自 minion_hp(表, 1)，不能是没乘缓冲的旧基准值
	var expected: Array = []
	for id in RogueDB.MINIONS_EARLY:
		var def: Dictionary = RogueDB.MINIONS.get(String(id), {})
		expected.append(RogueDB.minion_hp(def, 1))
	var hp_ok := not alive.is_empty()
	for e in alive:
		if not is_instance_valid(e):
			continue
		var hp := float(e.get("max_hp"))
		var matched := false
		for v in expected:
			if absf(float(v) - hp) < 0.6:
				matched = true
		if not matched:
			hp_ok = false
	_check(hp_ok, "真实小怪血量走的是新曲线（表登记 ≠ 运行时读到）",
		"表值 %s" % str(expected))

	# 触发一次「清一小关」：wave_no 拨到最后一波，玩家先扣成半血
	player.set("hp", 50.0)
	RogueRun.wave_no = RogueDB.WAVES_PER_STAGE
	rogue.call("_on_wave_cleared")
	await get_tree().process_frame
	var after := float(player.get("hp"))
	_check(after > 50.0 and after <= PLAYER_MAX_HP,
		"清一小关真的回血（rogue_heal_pct 接上了）",
		"50 → %.1f" % after)
	var panel: Node = rogue.get("_pick_panel")
	if panel != null and is_instance_valid(panel):
		panel.call("close")
	get_tree().paused = false
	arena.free()
	RogueRun.restore()


func _run() -> void:
	print("\n########## 试炼之路 · 数值实测 ##########")
	_run_model()
	_run_real_spawn()
