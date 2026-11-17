extends Node2D
## 棋盘棋子强度实测（2026-11-06 用户："测试一下棋盘上各个棋子的强度，你先试几个方向，再分别测试强度"）
##
## 为什么要拆好几个方向：`ATTACK_CALIB` 是 2026-11-03 用**单一口径**钉下来的
## （对量尺两仪打 22 秒、两侧平均），那条只回答"打出多少"，不回答"能不能打死对面"。
## 而 11-05/11-06 动过的两处（水镜环按整场结算归一化、叠纸折痕改意图折）恰恰改的是
## **命中几何与出手节奏** —— 纯 DPS 读数会把它们读成没变。
##
## 五个轴向，每个都是一场**真棋子**对决（不是 MatchCombat 那套抽象模型，它的注释
## 自己就写了"不能用来判断平衡"）：
##   eff    有效输出：vs 量尺打满一整场对决的时长（现 30 秒）、两侧各 reps 次。
##          ⚠ **收口用的官方口径就是这条，判据取日志第 5 列「有效/名义」（实测 ÷ 名义）**，
##            不是第 6 列的"指数"。指数 = 实测/名义 ÷ 基准自检，而基准自检（两仪打量尺）
##            会把**量尺自己的二阶段时机**耦合进每一行：11-07 把量尺面板按实测减免折算
##            （31500→26923）之后，同一份攻击力从 788 DPS 跳到 1090，于是全体棋子被
##            凭空除以 1.27 —— 看着像"大家都变弱了"，其实是尺子动了。名义是常数，
##            除以它两轮之间才能直接比；基准自检降级成诊断列。
##          ⚠ 窗口必须 ≥ 一场同级对决的真实寿命（26923 ÷ 900 ≈ 30 秒），否则"杀掉量尺"
##            的那几只只量到开场速率（刀客 A 1.22 / B 3.66 就是这么来的），折算会来回飘。
##   death  打到底：vs 三个锚点（中位 / 偏高 / 最肉）真打到一方倒下，记胜负·用时·残血。
##          唯一同时吃"输出+身板+机制"的轴向，也是玩家实际感知到的强弱。
##   ehp    有效血量：把来源冻成不打人的假人，按节拍喂**固定单发伤害**（物理 / 法术各一轮），
##          数它死前吞下多少原始伤害。抗性·护体·护身纸·转阶段无敌·回血全在同一条真实管线上生效。
##   place  站位与先后手敏感：同一只 vs 同一锚点跑 4 组格位，报极差。
##          老表里"两侧差 73%~91% 所以先不动"的那几只（观澜 / 执烛 / 苍角）就是要这条来回答。
##   team   团队边际贡献：3v3，双方另两只固定，只换被测试那一格，
##          比分差 = 这只棋子相对标准替补带来的净收益。
##   scale  测量自身的对照：同一批对决在 time_flow_base 1.0 / 2.0 各跑一遍，
##          看读数会不会被时间流速带走（顿帧按**真实**秒计、叠纸护身纸窗口读 ticks_msec，
##          两者都不跟着 time_scale 缩放 —— 所以这条不是可选优化，是必须量出来的偏差）。
##
## 用法：
##   godot --headless --path . res://tools/match_strength_probe.tscn -- --no-save
##     --axis=pilot|eff|death|ehp|place|team|scale      默认 pilot（三只 × 全轴向，先验信噪比与耗时）
##     --only=boss_02,boss_04                           只测几只（默认按轴向给的代表集 / 全 16）
##     --reps=1                                         每格重复次数（用来抵消帧抖动与出手随机）
##     --anchors=boss_02,boss_03,boss_04_c              death 的锚点
##     --window=22   --cap=45   --base=1.0              窗口秒 / 兜底秒 / time_flow_base

const PILOT_SET := ["boss_02", "boss_04", "boss_04_c"]
const DEFAULT_ANCHORS := ["boss_02", "boss_03", "boss_04_c"]
## 与 calibrate_match_duel 同一组格位，eff 的读数才能逐行对到 11-03 老表上。
const CELLS_A := Vector2i(1, 4)
const CELLS_B := Vector2i(4, 1)
## place 用的 4 组格位：近距错身 / 镜像互换 / 中腹对峙 / 全对角。
const PLACE_CFGS: Array = [
	[Vector2i(1, 4), Vector2i(4, 1)],
	[Vector2i(4, 1), Vector2i(1, 4)],
	[Vector2i(2, 2), Vector2i(3, 3)],
	[Vector2i(0, 0), Vector2i(5, 5)],
]
## 3v3 的固定班底：己方另两只、对方三只、被测试那只永远站中路 ——
## 只让一个变量动，读数才归得清是谁的功劳。
const TEAM_OWN_FIXED: Array = ["boss_02", "boss_02_b"]
const TEAM_ENEMY: Array = ["boss_01_c", "boss_03", "boss_02_c"]
const TEAM_FILLER := "boss_02_c"      ## 标准替补：边际贡献 = 这只 − 替补
const TEAM_CELLS_OWN: Array = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
const TEAM_CELLS_ENEMY: Array = [Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3)]

const EHP_RAW := 1500.0               ## 单发原始伤害（≈ 名义 DPS 的 1.7 倍，落在真实大招一档）
const EHP_INTERVAL := 0.5             ## 喂弹间隔（模拟秒）

var axis := "pilot"
var only: Array = []
var reps := 1
var anchors: Array = DEFAULT_ANCHORS.duplicate()
var window := 22.0
var cap := 45.0
var base_scale := 1.0
var ref_hp_mult := 1.0
var yard_atk := 0.0
var _wall0 := 0
var _runs := 0


func _ready() -> void:
	_parse_args()
	GameState.set_time_flow_base(base_scale)
	await _warm_all()
	print("MS ===== 轴向 %s ｜ only=%s reps=%d window=%.0f cap=%.0f base=%.2f 量尺血×%.0f 量尺攻击=%.0f =====" % [
			axis, str(only if not only.is_empty() else "全卡池/代表集"), reps, window, cap,
			base_scale, ref_hp_mult, yard_atk])
	_wall0 = Time.get_ticks_msec()
	match axis:
		"eff":
			await _axis_eff(_list())
		"death":
			await _axis_death(_list())
		"ehp":
			await _axis_ehp(_list())
		"place":
			await _axis_place(_list())
		"team":
			await _axis_team(_list())
		"scale":
			await _axis_scale(PILOT_SET)
		_:
			await _axis_pilot()
	print("MS ===== DONE %s 对决次数=%d 墙钟=%.1fs =====" % [axis, _runs, _elapsed()])
	get_tree().quit(0)


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var t := String(raw)
		# 传参写成 `--axis=ehp`（也兼容 `axis=ehp`）：不把这两个杠削掉，
		# 整条判据全部落空、工具静默跑成默认的 pilot —— 第一次就踩了这个。
		while t.begins_with("-"):
			t = t.trim_prefix("-")
		if t.begins_with("axis="):
			axis = t.trim_prefix("axis=")
		elif t.begins_with("only="):
			only = t.trim_prefix("only=").split(",", false)
		elif t.begins_with("reps="):
			reps = clampi(int(t.trim_prefix("reps=")), 1, 6)
		elif t.begins_with("anchors="):
			anchors = t.trim_prefix("anchors=").split(",", false)
		elif t.begins_with("window="):
			window = maxf(4.0, float(t.trim_prefix("window=")))
		elif t.begins_with("cap="):
			cap = maxf(6.0, float(t.trim_prefix("cap=")))
		elif t.begins_with("base="):
			base_scale = clampf(float(t.trim_prefix("base=")), 0.25, 4.0)
		elif t.begins_with("refhp="):
			ref_hp_mult = maxf(1.0, float(t.trim_prefix("refhp=")))
		elif t.begins_with("yard="):
			yard_atk = maxf(0.0, float(t.trim_prefix("yard=")))


func _list() -> Array:
	if not only.is_empty():
		return only
	if axis == "scale":
		return PILOT_SET.duplicate()
	return MatchDB.CARD_POOL.duplicate()


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _wall0) / 1000.0


## 开局把 16 只的场景与皮全部排进线程预载，等它排空再开测：
## 否则每场对决第一次登场都要在主线程解一张 455ms 的大图，耗时会藏在读数里。
func _warm_all() -> void:
	var secs := 0.0
	for raw in MatchDB.CARD_POOL:
		MatchAdapter.warm_boss(String(raw))
	while SkinWarm.is_busy() and secs < 60.0:
		await get_tree().process_frame
		SkinWarm.poll()
		secs += get_process_delta_time()
	print("MS 预热完成 %.1fs（预载队列排空）" % secs)


# ===================== 基元：一场对决 =====================

## to_death=false → 固定窗口；true → 打到一方倒下（cap 秒兜底）。
## 返回里 dealt/low/hp 三件事分开记，因为它们会分歧：能回血的棋子
## "最低血量"和"死前吞下的总伤害"差好几管，只看一个数会把续航读成脆。
func _duel(id_a: String, id_b: String, cell_a: Vector2i, cell_b: Vector2i,
		limit: float, to_death: bool) -> Dictionary:
	_runs += 1
	seed(20261106 + _runs * 7919)
	var a := MatchAdapter.spawn_piece(self, id_a, 0, cell_a)
	var b := MatchAdapter.spawn_piece(self, id_b, 1, cell_b)
	if a == null or b == null:
		await _sweep()
		return {"err": "spawn 失败 %s/%s" % [id_a, id_b]}
	await get_tree().physics_frame
	# `--refhp=K`：把量尺抬成"窗口内打不死"的靶子。
	# 为什么需要：会杀尺的那几只（刀客 4.02 / 观澜 2.76）用击杀窗算速率，
	# 量到的其实是**开场那一轮**；同一只刀客对 33600 血的赫连霄打满 21.6 秒只有 1475。
	# 所以"输出能力"必须在不会被杀死的靶子上量，"胜负"另外用 death 轴量。
	# ⚠ 放大后量尺一辈子进不了二阶段（转阶段判据是 current_hp ≤ max_hp×0.5），
	#   所以这条读数是"对一阶段量尺的稳定输出"，不是对局里的平均。
	if ref_hp_mult > 1.0 and not to_death:
		var new_max: float = float(b.get("max_hp")) * ref_hp_mult
		b.set("max_hp", new_max)
		b.set("current_hp", new_max)
	# `--yard=3393`：把**量尺那一只**的攻击力钉成常数。
	# 为什么必须钉：第二轮验收发现反馈环 —— 量尺作为一张牌也被一起削之后
	# （11-07 第三轮 3393→2935），它打被测棋子的伤害变小 ⇒ 被测棋子活得更久 ⇒
	# ramp 型（二阶段、刀痕、剑意）实测输出反而**涨**。
	# 赫连霄从 0.78 被加到 1.32（+28% 的攻击力被反馈放大成 +69% 的读数），
	# 刀客被削之后反而从 1.20 涨到 1.53。这种"越削越高"的量具不能拿来迭代收敛。
	# 钉住之后每只棋子的读数只取决于它自己的攻击力，折算才是单调的。
	if yard_atk > 0.0:
		b.set("attack_power", yard_atk)
	var a_max: float = float(a.get("max_hp"))
	var b_max: float = float(b.get("max_hp"))
	var out := {"t": 0.0, "a_max": a_max, "b_max": b_max,
			"a_low": a_max, "b_low": b_max, "a_hp": a_max, "b_hp": b_max,
			"a_heal": 0.0, "b_heal": 0.0, "cut": "",
			"a_burst": 0.0, "b_burst": 0.0,
			"a_alive": true, "b_alive": true, "err": ""}
	var t := 0.0
	var hp_a := a_max
	var hp_b := b_max
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var alive_a := MatchAdapter.is_alive(a)
		var alive_b := MatchAdapter.is_alive(b)
		# **窗口模式也要在死亡那一帧收手**：量尺两仪面板 31500 血，
		# 被 1430 DPS 的棋子 22 秒正好打死；不 break 的话 dealt 会封顶在
		# 31500/22=1432，凡是"其实杀掉了量尺"的棋子全部读成同一个数（第一版就踩了）。
		# 收手之后读数 = 满血 ÷ 击杀用时，是真实输出速率，带 K 标记。
		if not alive_a or not alive_b:
			out["a_alive"] = alive_a
			out["b_alive"] = alive_b
			if not alive_a and not alive_b:
				out["cut"] = "both"
			elif not alive_a:
				out["cut"] = "a"
				out["a_low"] = 0.0
			else:
				out["cut"] = "b"
				out["b_low"] = 0.0
			break
		var na: float = float(a.get("current_hp"))
		var nb: float = float(b.get("current_hp"))
		# 单帧最大掉血 ≈ 最重那一下（爆发）。平均值会把它藏起来：
		# 刀客对量尺的均速只有 765 DPS，但 7.9 秒一记 25000 直接带走 31500 血。
		if na < hp_a:
			out["a_burst"] = maxf(float(out["a_burst"]), hp_a - na)
		if nb < hp_b:
			out["b_burst"] = maxf(float(out["b_burst"]), hp_b - nb)
		if na > hp_a:
			out["a_heal"] = float(out["a_heal"]) + (na - hp_a)
		if nb > hp_b:
			out["b_heal"] = float(out["b_heal"]) + (nb - hp_b)
		hp_a = na
		hp_b = nb
		out["a_low"] = minf(float(out["a_low"]), na)
		out["b_low"] = minf(float(out["b_low"]), nb)
	out["t"] = t
	out["a_hp"] = hp_a
	out["b_hp"] = hp_b
	out["a_alive"] = MatchAdapter.is_alive(a)
	out["b_alive"] = MatchAdapter.is_alive(b)
	await _sweep()
	return out


## 每场之间把场上节点扫干净：伤害飘字、镜像、折痕缝全挂在根上，
## 上一只留下的镜像会在下一场替它打人 —— 11-03 那批"两侧差 73%"里
## 有一部分就是这个，所以本工具必须扫。
func _sweep() -> void:
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _beat(tag: String) -> void:
	print("MS   · %-26s 累计 %5.1fs 对决 %d 场" % [tag, _elapsed(), _runs])


# ===================== 轴向 eff：有效输出 =====================

func _axis_eff(list: Array) -> void:
	var ref := String(anchors[0]) if not anchors.is_empty() else "boss_02"
	# **先量基准**：让量尺打量尺。ATTACK_CALIB 的"有效/名义≈1.0"是 11-03 那一版读数下成立的，
	# 11-05/11-06 的阵营与卫星统一（BossBase.hostile_units / 战报台账 / 镜像归属）全动过
	# "谁能打到谁"，所以本工具必须自己重新钉一次基准，而不是拿 1.0 当理想值。
	# 后面那一列「指数」= 有效/名义 ÷ 基准比，才是和"带内 0.86~1.18"可比的那个数。
	var sr: Array = []
	for side in 2:
		var s0 := await _duel(ref, ref,
				CELLS_A if side == 0 else CELLS_B,
				CELLS_B if side == 0 else CELLS_A, window, false)
		sr.append((float(s0["b_max"]) - float(s0["b_low"])) / maxf(float(s0["t"]), 0.001))
	var ref_nominal: float = float(MatchDB.piece_stats(ref).get("dps", 1.0))
	var self_ratio := _mean(sr) / maxf(ref_nominal, 1.0)
	print("MS EFF 基准自检 %s 打量尺 = %.0f DPS（名义 %.0f）→ 本轮读数系数 %.2f" % [
			ref, _mean(sr), ref_nominal, self_ratio])
	print("MS EFF 卡                     名义DPS   有效DPS   有效/名义    指数    自己掉血%   回血   同格极差  先后手差   组内σ    ±SE   击杀")
	for raw in list:
		var id := String(raw)
		if id == ref:
			continue
		# 每个 side 各 reps 次：side0/side1 之差是**格位与先后手**的真实差，
		# 同一 side 内部散布才是噪声。混在一起平均会把"位置依赖"洗成"稳定"。
		var per_side: Array = [[], []]
		var kills := 0
		var lost_sum := 0.0
		var heal_sum := 0.0
		var n := 0
		for rep in reps:
			for side in 2:
				var s := await _duel(id, ref,
						CELLS_A if side == 0 else CELLS_B,
						CELLS_B if side == 0 else CELLS_A, window, false)
				if String(s["err"]) != "":
					continue
				var tt: float = maxf(float(s["t"]), 0.001)
				per_side[side].append((float(s["b_max"]) - float(s["b_low"])) / tt)
				if String(s["cut"]) == "b":
					kills += 1
				lost_sum += (float(s["a_max"]) - float(s["a_low"])) / maxf(float(s["a_max"]), 1.0) * 100.0
				heal_sum += float(s["a_heal"])
				n += 1
		if n == 0:
			print("MS EFF %-22s 生成失败" % id)
			continue
		var all: Array = per_side[0] + per_side[1]
		var mean := _mean(all)
		# 组内 σ：只算**同一 side 内部**的散布。极差里混着格位与先后手的真实差（那是棋子的性质，不是噪声），
		# 拿极差当 σ 会把标准误夸大约 2 倍 —— 于是"超没超出验收带"永远判不出来。
		var ssum := 0.0
		var scnt := 0
		for sd in 2:
			var arr: Array = per_side[sd]
			if arr.size() < 2:
				continue
			var mm: float = _mean(arr)
			var vv := 0.0
			for x in arr:
				vv += (float(x) - mm) * (float(x) - mm)
			ssum += vv / float(arr.size() - 1)
			scnt += 1
		var sigma_pct := sqrt(ssum / maxf(float(scnt), 1.0)) / maxf(mean, 1.0) * 100.0
		var se_pct := sigma_pct / sqrt(maxf(float(n), 1.0))
		var nominal: float = float(MatchDB.piece_stats(id).get("dps", 0.0))
		var ratio := mean / maxf(nominal, 1.0)
		print("MS EFF %-22s %8.0f %10.0f %10.2f %8.2f %10.0f%% %7.0f %8.0f%% %9.0f%% %7.0f%% %6.1f%%  杀尺 %d/%d" % [
				id, nominal, mean, ratio, ratio / maxf(self_ratio, 0.01),
				lost_sum / float(n), heal_sum / float(n),
				(_maxv(all) - _minv(all)) / maxf(mean, 1.0) * 100.0,
				absf(_mean(per_side[1]) - _mean(per_side[0])) / maxf(mean, 1.0) * 100.0,
				sigma_pct, se_pct, kills, n])
		_beat("eff " + id)


# ===================== 轴向 death：打到底 =====================

func _axis_death(list: Array) -> void:
	print("MS DEATH 锚点=%s 兜底=%.0fs" % [str(anchors), cap])
	print("MS DEATH 卡                     锚点        结果      用时   残血%  最低%  有效DPS  挨打DPS  单帧最大掉血")
	for raw in list:
		var id := String(raw)
		var score := 0.0
		var n := 0
		for ai in anchors.size():
			var ref := String(anchors[ai])
			if ref == id:
				continue
			for rep in reps:
				var flip: bool = (rep % 2) == 1
				var r := await _duel(id, ref,
						CELLS_B if flip else CELLS_A,
						CELLS_A if flip else CELLS_B, cap, true)
				if String(r["err"]) != "":
					print("MS DEATH %-22s %s 生成失败" % [id, ref])
					continue
				var tt: float = maxf(float(r["t"]), 0.001)
				var alive_a: bool = bool(r["a_alive"])
				var alive_b: bool = bool(r["b_alive"])
				var res := "同倒"
				var pts := 0.5
				if alive_a and not alive_b:
					res = "胜"
					pts = 1.0
				elif alive_b and not alive_a:
					res = "负"
					pts = 0.0
				else:
					var fa: float = float(r["a_hp"]) / maxf(float(r["a_max"]), 1.0)
					var fb: float = float(r["b_hp"]) / maxf(float(r["b_max"]), 1.0)
					res = "超时%.2fvs%.2f" % [fa, fb]
					pts = 1.0 if fa > fb + 0.02 else (0.0 if fb > fa + 0.02 else 0.5)
				score += pts
				n += 1
				print("MS DEATH %-22s %-14s %-8s %7.1fs %6.0f %6.0f %8.0f %8.0f  爆发 %.0f/%.0f" % [
						id, ref, res, tt,
						float(r["a_hp"]) / maxf(float(r["a_max"]), 1.0) * 100.0,
						float(r["a_low"]) / maxf(float(r["a_max"]), 1.0) * 100.0,
						(float(r["b_max"]) - float(r["b_low"])) / tt,
						(float(r["a_max"]) - float(r["a_low"])) / tt,
						float(r["a_burst"]), float(r["b_burst"])])
		if n > 0:
			print("MS DEATH %-22s >>> 胜点 %.2f / %d = %.0f%%" % [id, score, n, score / float(n) * 100.0])
		_beat("death " + id)


# ===================== 轴向 ehp：有效血量 =====================

## 来源冻结（不参与行动，只当伤害的发起者，让棘甲/反击这类"要有一个来源"的机制照旧成立）。
func _axis_ehp(list: Array) -> void:
	print("MS EHP 单发原始=%.0f 间隔=%.2fs 兜底=%.0fs" % [EHP_RAW, EHP_INTERVAL, cap])
	print("MS EHP 卡                     物理吞下  倍数   法术吞下  倍数   倒下用时(物/法)  被挡")
	for raw in list:
		var id := String(raw)
		var p := await _ehp_once(id, "physical_melee", "")
		var m := await _ehp_once(id, "elemental", "water")
		if String(p["err"]) != "" or String(m["err"]) != "":
			print("MS EHP %-22s 生成失败" % id)
			continue
		print("MS EHP %-22s %8.0f %6.2f %10.0f %6.2f %8.1f/%.1fs %5d" % [
				id, float(p["ehp"]), float(p["ehp"]) / maxf(float(p["max"]), 1.0),
				float(m["ehp"]), float(m["ehp"]) / maxf(float(m["max"]), 1.0),
				float(p["t"]), float(m["t"]), int(p["blocked"]) + int(m["blocked"])])
		_beat("ehp " + id)


func _ehp_once(id: String, kind: String, element: String) -> Dictionary:
	var src := MatchAdapter.spawn_piece(self, "boss_02", 1, CELLS_B)
	var vic := MatchAdapter.spawn_piece(self, id, 0, CELLS_A)
	if src == null or vic == null:
		await _sweep()
		return {"err": "spawn", "ehp": 0.0, "t": 0.0, "blocked": 0, "max": 1.0}
	src.set_physics_process(false)
	src.set_process(false)
	await get_tree().physics_frame
	var vic_max: float = float(vic.get("max_hp"))
	var raw_sent := 0.0
	var blocked := 0
	var t := 0.0
	var acc := 0.0
	while t < cap:
		await get_tree().physics_frame
		var dt: float = get_physics_process_delta_time()
		t += dt
		acc += dt
		if acc < EHP_INTERVAL:
			continue
		acc = 0.0
		if not MatchAdapter.is_alive(vic):
			break
		var before: float = float(vic.get("current_hp"))
		var landed: bool = src.call("deal_damage_to", vic, EHP_RAW, kind, element)
		var after: float = float(vic.get("current_hp"))
		if landed and after < before:
			raw_sent += EHP_RAW
		else:
			# 没掉血 = 无敌帧 / 转阶段保护 / 护体整招挡下：这一发按真实结算作废，不补
			blocked += 1
		if not MatchAdapter.is_alive(vic):
			break
	var out := {"err": "", "t": t, "blocked": blocked, "max": vic_max}
	out["ehp"] = raw_sent
	await _sweep()
	return out


# ===================== 轴向 place：站位敏感 =====================

func _axis_place(list: Array) -> void:
	var ref := String(anchors[0]) if not anchors.is_empty() else "boss_02"
	print("MS PLACE 锚点=%s 窗口=%.0fs 格位=%d 组" % [ref, window, PLACE_CFGS.size()])
	print("MS PLACE 卡                     最差    最好    均值   极差/均值  各组读数")
	for raw in list:
		var id := String(raw)
		if id == ref:
			continue
		var dps: Array = []
		var tags: Array = []
		var bursts: Array = []
		for cfg in PLACE_CFGS:
			var r := await _duel(id, ref, cfg[0], cfg[1], window, false)
			if String(r["err"]) != "":
				continue
			var tt: float = maxf(float(r["t"]), 0.001)
			dps.append((float(r["b_max"]) - float(r["b_low"])) / tt)
			bursts.append(float(r["b_burst"]))
			tags.append("%.0f%s" % [float(dps[dps.size() - 1]),
					"K" if String(r["cut"]) == "b" else ""])
		if dps.is_empty():
			continue
		var mean := _mean(dps)
		print("MS PLACE %-22s %7.0f %7.0f %7.0f %9.0f%%  %s  爆发 %.0f" % [
				id, _minv(dps), _maxv(dps), mean,
				(_maxv(dps) - _minv(dps)) / maxf(mean, 1.0) * 100.0, " / ".join(tags),
				_maxv(bursts)])
		_beat("place " + id)


# ===================== 轴向 team：3v3 边际贡献 =====================

## 分差 = 己方剩余血量比例均值 − 对方剩余血量比例均值（打满 T 秒，死了算 0）。
func _axis_team(list: Array) -> void:
	print("MS TEAM 己方固定=%s 对方=%s 替补=%s 窗口=%.0fs reps=%d" % [
			str(TEAM_OWN_FIXED), str(TEAM_ENEMY), TEAM_FILLER, window, reps])
	# reps 在这里不是可选项：试点实测同一只牌两次跑出 0.202 / -0.023，
	# 单样本的散布和牌与牌之间的差距同一个量级 —— 一次读数排出来的名次是噪声。
	var f_diff: Array = []
	for rep in reps:
		var fr := await _team_score(TEAM_FILLER)
		f_diff.append(float(fr["diff"]))
	var base := _mean(f_diff)
	print("MS TEAM 基准（替补 %s）%d 次分差 %s → 均值 %.3f（散布 %.3f）" % [
			TEAM_FILLER, f_diff.size(), _tag_list(f_diff), base,
			_maxv(f_diff) - _minv(f_diff)])
	print("MS TEAM 卡                     分差     边际    散布    己方阵亡  对方阵亡")
	for raw in list:
		var id := String(raw)
		if id == TEAM_FILLER:
			continue
		var diffs: Array = []
		var od := 0
		var fd := 0
		for rep in reps:
			var sc := await _team_score(id)
			diffs.append(float(sc["diff"]))
			od += int(sc["own_dead"])
			fd += int(sc["foe_dead"])
		var mean := _mean(diffs)
		print("MS TEAM %-22s %7.3f %+8.3f %7.3f %8.1f %8.1f  %s" % [
				id, mean, mean - base, _maxv(diffs) - _minv(diffs),
				float(od) / float(reps), float(fd) / float(reps), _tag_list(diffs)])
		_beat("team " + id)


func _team_score(tested: String) -> Dictionary:
	var own: Array = []
	own.append(tested)
	for raw in TEAM_OWN_FIXED:
		own.append(String(raw))
	var nodes_a: Array = []
	var nodes_b: Array = []
	for i in 3:
		nodes_a.append(MatchAdapter.spawn_piece(self, String(own[i]), 0, TEAM_CELLS_OWN[i]))
		nodes_b.append(MatchAdapter.spawn_piece(self, String(TEAM_ENEMY[i]), 1, TEAM_CELLS_ENEMY[i]))
	for n in nodes_a + nodes_b:
		if n == null:
			await _sweep()
			return {"diff": 0.0, "own_dead": 0, "foe_dead": 0, "err": 1}
	await get_tree().physics_frame
	var t := 0.0
	while t < window:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var fa := _hp_fraction(nodes_a)
	var fb := _hp_fraction(nodes_b)
	var out := {"diff": fa - fb,
			"own_dead": _count_dead(nodes_a), "foe_dead": _count_dead(nodes_b), "err": 0}
	await _sweep()
	return out


func _hp_fraction(nodes: Array) -> float:
	var sum := 0.0
	for n in nodes:
		if n == null or not is_instance_valid(n):
			continue
		if not MatchAdapter.is_alive(n):
			continue
		sum += float(n.get("current_hp")) / maxf(float(n.get("max_hp")), 1.0)
	return sum / maxf(float(nodes.size()), 1.0)


func _count_dead(nodes: Array) -> int:
	var k := 0
	for n in nodes:
		if n == null or not is_instance_valid(n) or not MatchAdapter.is_alive(n):
			k += 1
	return k


# ===================== 轴向 scale：时间流速会不会带走进数 =====================

func _axis_scale(list: Array) -> void:
	var ref := "boss_02"
	print("MS SCALE 同一批对决在 base=1.0 / 2.0 各跑一遍；差值 = 流速对读数的污染")
	print("MS SCALE 卡                     1.0 有效DPS   2.0 有效DPS   偏差")
	GameState.set_time_flow_base(1.0)
	var slow: Dictionary = {}
	for raw in list:
		var id := String(raw)
		if id == ref:
			continue
		var r := await _duel(id, ref, CELLS_A, CELLS_B, window, false)
		slow[id] = (float(r["b_max"]) - float(r["b_low"])) / maxf(float(r["t"]), 0.001)
	GameState.set_time_flow_base(2.0)
	for raw in list:
		var id := String(raw)
		if id == ref or not slow.has(id):
			continue
		var r := await _duel(id, ref, CELLS_A, CELLS_B, window, false)
		var fast := (float(r["b_max"]) - float(r["b_low"])) / maxf(float(r["t"]), 0.001)
		var one := float(slow[id])
		print("MS SCALE %-22s %10.0f %12.0f %10.0f%%" % [
				id, one, fast, (fast - one) / maxf(one, 1.0) * 100.0])
	GameState.set_time_flow_base(1.0)


# ===================== 试点：三只 × 全轴向，看信噪比与耗时 =====================

func _axis_pilot() -> void:
	print("MS PILOT 目标：判断每个轴向能不能用 —— 同一格重复两次看噪声，顺带记录墙钟耗时。")
	for id in PILOT_SET:
		print("\nMS PILOT ==== %s ====" % id)
		var a1 := await _duel(id, "boss_02", CELLS_A, CELLS_B, window, false)
		var a2 := await _duel(id, "boss_02", CELLS_A, CELLS_B, window, false)
		var d1 := _dps_of(a1)
		var d2 := _dps_of(a2)
		print("MS PILOT eff  同格两次 %.0f / %.0f DPS → 噪声 %.0f%%（耗时见下行）" % [
				d1, d2, absf(d2 - d1) / maxf(d1, 1.0) * 100.0])
		var b1 := await _duel(id, "boss_02", CELLS_B, CELLS_A, window, false)
		print("MS PILOT 先后手互换 %.0f / %.0f / %.0f → 位置敏感度 %.0f%%" % [
				d1, d2, _dps_of(b1),
				(_maxv([d1, d2, _dps_of(b1)]) - _minv([d1, d2, _dps_of(b1)]))
						/ maxf(_mean([d1, d2, _dps_of(b1)]), 1.0) * 100.0])
		var e1 := await _ehp_once(id, "physical_melee", "")
		var e2 := await _ehp_once(id, "physical_melee", "")
		print("MS PILOT ehp  两次吞下 %.0f / %.0f 原始伤害 → 噪声 %.1f%%" % [
				float(e1["ehp"]), float(e2["ehp"]),
				absf(float(e2["ehp"]) - float(e1["ehp"])) / maxf(float(e1["ehp"]), 1.0) * 100.0])
		var k1 := await _duel(id, "boss_04_c", CELLS_A, CELLS_B, cap, true)
		var k2 := await _duel(id, "boss_04_c", CELLS_B, CELLS_A, cap, true)
		print("MS PILOT death 两次结果 %s / %s（用时 %.1f / %.1fs）→ %s" % [
				_outcome(k1), _outcome(k2), float(k1["t"]), float(k2["t"]),
				"稳定" if _outcome(k1) == _outcome(k2) else "翻面：这条轴向单次不可信"])
		var s1 := await _team_score(id)
		var s2 := await _team_score(id)
		print("MS PILOT team  分差两次 %.3f / %.3f → 噪声 %.3f（基准替补单独跑）" % [
				float(s1["diff"]), float(s2["diff"]), absf(float(s2["diff"]) - float(s1["diff"]))])
		var t1 := await _duel(id, "boss_02", CELLS_A, CELLS_B, window, false)
		GameState.set_time_flow_base(2.0)
		var t2 := await _duel(id, "boss_02", CELLS_A, CELLS_B, window, false)
		GameState.set_time_flow_base(1.0)
		print("MS PILOT scale 同格 base1.0=%.0f base2.0=%.0f DPS → 偏差 %.0f%%" % [
				_dps_of(t1), _dps_of(t2),
				(_dps_of(t2) - _dps_of(t1)) / maxf(_dps_of(t1), 1.0) * 100.0])
		_beat("pilot " + id)
	print("\nMS PILOT 合计：对决 %d 场，墙钟 %.1fs → 单场平均 %.1fs" % [
			_runs, _elapsed(), _elapsed() / maxf(float(_runs), 1.0)])


func _dps_of(r: Dictionary) -> float:
	if String(r.get("err", "")) != "":
		return 0.0
	return (float(r["b_max"]) - float(r["b_low"])) / maxf(float(r["t"]), 0.001)


func _outcome(r: Dictionary) -> String:
	if bool(r["a_alive"]) and not bool(r["b_alive"]):
		return "胜"
	if bool(r["b_alive"]) and not bool(r["a_alive"]):
		return "负"
	return "超时/同倒"


func _tag_list(vals: Array) -> String:
	var out: Array = []
	for v in vals:
		out.append("%.3f" % float(v))
	return " / ".join(out)


func _mean(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var s := 0.0
	for v in vals:
		s += float(v)
	return s / float(vals.size())


func _minv(vals: Array) -> float:
	var m := INF
	for v in vals:
		m = minf(m, float(v))
	return 0.0 if is_inf(m) else m


func _maxv(vals: Array) -> float:
	var m := -INF
	for v in vals:
		m = maxf(m, float(v))
	return 0.0 if is_inf(m) else m
