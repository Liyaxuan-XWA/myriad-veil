extends Node2D
## 逐只实测棋子的**真实 DPS**，产出 MatchDB.ATTACK_CALIB。
##
## 为什么必须实测而不是算：招式伤害 = attack_power × 招式系数，
## 但一只 BOSS 在一段时间里**实际出手几次**取决于它的 AI 节奏 —— 前摇、走位、
## 召镜像、放领域、二阶段演出全在吃时间。观澜和赫连霄的标称 attack_power 只差 1.16 倍，
## 实测真实 DPS 却差 2.4 倍（89 vs 247）。所以「±20% 面板窄带」光靠改系数表是假的，
## 必须拿实测出手速率回来除。
##
## 用法（很慢，建议挂后台）：
##   godot --headless --path . res://tools/calibrate_match_dps.tscn -- --no-save secs=10
## 输出直接贴进 MatchDB.ATTACK_CALIB。

const UNIT_ATTACK_POWER := 100.0        # 已知的单位攻击力，用它反推速率
const DUMMY_HP := 1.0e9                 # 不还手、不会死的靶子

var measure_secs := 10.0
## 只测某一批：`only=cores` / `only=tower` / `only=all`（默认 all）。
## 核心首领那四只曾经被错装成通用 prototype，测出的数作废、需要单独重跑。
var only := "all"


func _want(boss_id: String) -> bool:
	if only == "all":
		return true
	var is_core := MatchDB.is_core_boss(boss_id)
	return is_core if only == "cores" else not is_core


func _ready() -> void:
	for raw in OS.get_cmdline_user_args():
		var s := String(raw)
		if s.begins_with("secs="):
			measure_secs = maxf(2.0, float(s.trim_prefix("secs=")))
		elif s.begins_with("only="):
			only = s.trim_prefix("only=")
	print("\n########## 棋子真实 DPS 实测（每只 %.0f 秒，only=%s）==========" % [measure_secs, only])
	print("const ATTACK_CALIB := {")
	for id in MatchDB.CARD_POOL:
		if not _want(String(id)):
			continue
		var dps := await _measure(String(id))
		var target := float(MatchDB.piece_stats(String(id))["dps"])
		# 需要的攻击力 = 目标DPS / (单位攻击力打出的DPS) × 单位攻击力
		var need := target * UNIT_ATTACK_POWER / maxf(dps, 0.001)
		print("\t\"%s\": %.0f,  # 实测 %.0f DPS @atk=%.0f → 目标 %.0f（%.1fx）" % [
			id, need, dps, UNIT_ATTACK_POWER, target, need / UNIT_ATTACK_POWER])
	print("}")
	get_tree().quit(0)


## 放一只待测棋子 + 一只不还手的靶子，量单位时间内靶子掉了多少血。
func _measure(boss_id: String) -> float:
	var attacker := MatchAdapter.spawn_piece(self, boss_id, 0, Vector2i(2, 2))
	var dummy := MatchAdapter.spawn_piece(self, boss_id, 1, Vector2i(3, 2))
	if attacker == null or dummy == null:
		print("!! ", boss_id, " 生成失败")
		return 0.0
	attacker.set("attack_power", UNIT_ATTACK_POWER)
	# 靶子：攻击力归零（不打回去，否则污染测量）、血量拉到打不死
	dummy.set("attack_power", 0.0)
	dummy.set("max_hp", DUMMY_HP)
	dummy.set("current_hp", DUMMY_HP)
	# 待测方也要扛得住 —— 它要是中途把靶子打掉或者自己被打死就测不完
	attacker.set("max_hp", DUMMY_HP)
	attacker.set("current_hp", DUMMY_HP)
	var start := float(dummy.get("current_hp"))
	var t := 0.0
	var frames := 0
	while t < measure_secs:
		await get_tree().physics_frame
		frames += 1
		t += get_physics_process_delta_time()
		if not is_instance_valid(attacker) or not is_instance_valid(dummy):
			break
		if BossBase.is_unit_dead(attacker):
			break
	var dealt := start - float(dummy.get("current_hp")) if is_instance_valid(dummy) else 0.0
	var secs := maxf(t, 0.001)
	if is_instance_valid(attacker):
		attacker.queue_free()
	if is_instance_valid(dummy):
		dummy.queue_free()
	await get_tree().process_frame
	return dealt / secs
