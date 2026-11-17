extends Node2D
## 棋盘模式专属数值验收（2026-11-03 用户：虎妖伤害太低、剑客太强，只改棋盘数值）
##
## 三件事各自都要钉住，因为它们的失败方式不一样：
## ① 虎妖的伤害倍率**只在棋子上生效**。它走通用 prototype_boss，伤害是几个 @export
##    常数 × 阶段倍率，根本不读 `attack_power` —— 所以校准表给它的攻击力是空转的，
##    实测在棋盘上只打出 2 DPS（名义 1062）。
## ② 秘境 / 塔 / 演武场**一分都不能变**：同一记 100 点伤害，队伍号 -1 时落多少就是多少。
## ③ 剑客的满层「一剑开天·剑意盈天」在**一局里只放一次**，而且只限棋子；
##    常规形态（按剑意层数加范围）照放，招式表不能缺一门。
##
## 用法：godot --headless --path . res://tools/probe_match_balance.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, name: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("  ok  ", name, "  ", detail)
	else:
		_fails.append(name + " | " + detail)
		print("  !   ", name, "  ", detail)


func _ready() -> void:
	_check_table()
	await _check_pve_untouched()
	await _check_swordsman_once()
	await _check_huyao_duel()
	_check_calibration_shape()
	print("\n########## 棋盘数值：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(0 if _fails.is_empty() else 1)


# ===================== 一、倍率表本身 =====================

func _check_table() -> void:
	print("\n### 1. MatchDB 的倍率表")
	var want := float(MatchDB.ATTACK_CALIB["boss_huyao"]) / MatchDB.UNIT_ATTACK_POWER
	_check(absf(MatchDB.match_damage_scale("boss_huyao") - want) < 0.01,
			"虎妖的倍率 = 校准值 ÷ 单位攻击力（两处不会各走各的）",
			"%.2f 倍" % want)
	# ⚠ 这里只守**量级**（±25%），不钉死具体值：11-07 那一轮把 calib 从 26579 折到 23521，
	#   判据如果钉死 265.79 就会在正确重校之后红一次，那种红只会教人以后绕开它。
	_check(absf(MatchDB.match_damage_scale("boss_huyao") - 235.21) < 58.0,
			"倍率量级符合实测缺口（名义 1062 档；11-07 实测指数 1.13 折算后 235.21）",
			"%.2f" % MatchDB.match_damage_scale("boss_huyao"))
	for id in MatchDB.CARD_POOL:
		var s := String(id)
		if MatchDB.FLAT_DAMAGE_CARDS.has(s):
			continue
		_check(absf(MatchDB.match_damage_scale(s) - 1.0) < 0.0001,
				"其余棋子倍率恒为 1.0（不吃这次改动）", s)
	# 表里列的每一只必须**确实**还挂在通用 prototype 场景上；
	# 哪天它换成自己的脚本、伤害开始读 attack_power，这条就会提醒删掉倍率。
	for raw in MatchDB.FLAT_DAMAGE_CARDS:
		var id := String(raw)
		var scene := String(WorldDB.get_boss_scene(id))
		_check(scene.ends_with("scenes/boss/boss.tscn"),
				"%s 仍然走通用 prototype（倍率表的前提）" % id, scene)


# ===================== 二、PvE 一分不变 =====================

## 同一记 deal_damage_to(100) 分别由「PvE 的虎妖」和「棋盘上的虎妖」打出，
## 对面用两只一模一样的棋子 —— 减免相同，所以两边的差值就是倍率本身。
func _check_pve_untouched() -> void:
	print("\n### 2. PvE 不受影响")
	var atk_pve := MatchAdapter.spawn_piece(self, "boss_huyao", -1, Vector2i(1, 1))
	var tgt_pve := MatchAdapter.spawn_piece(self, "boss_huyao", 1, Vector2i(1, 2))
	var atk_m := MatchAdapter.spawn_piece(self, "boss_huyao", 0, Vector2i(4, 1))
	var tgt_m := MatchAdapter.spawn_piece(self, "boss_huyao", 1, Vector2i(4, 2))
	if atk_pve == null or tgt_pve == null or atk_m == null or tgt_m == null:
		_check(false, "四只虎妖都生成成功", "有 null")
		return
	await get_tree().physics_frame
	_check(absf(float(atk_pve.call("_match_damage_scale"))) - 1.0 < 0.0001,
			"队伍号 -1（秘境 / 塔 / 演武场）倍率是 1.0",
			str(atk_pve.call("_match_damage_scale")))
	_check(absf(float(atk_m.call("_match_damage_scale"))
			- MatchDB.match_damage_scale("boss_huyao")) < 0.0001,
			"棋子（team_id>=0）才吃倍率", str(atk_m.call("_match_damage_scale")))
	var hp0 := float(tgt_pve.get("current_hp"))
	var hm0 := float(tgt_m.get("current_hp"))
	var ok_pve := bool(atk_pve.call("deal_damage_to", tgt_pve, 100.0, "physical_melee"))
	var ok_mat := bool(atk_m.call("deal_damage_to", tgt_m, 100.0, "physical_melee"))
	var d_pve := hp0 - float(tgt_pve.get("current_hp"))
	var d_mat := hm0 - float(tgt_m.get("current_hp"))
	_check(ok_pve and ok_mat, "两边这记伤害都算命中",
			"pve=%s 棋子=%s" % [str(ok_pve), str(ok_mat)])
	_check(d_pve > 0.0, "PvE 那一下按原值扣血（没有被倍率污染）", "扣 %.1f" % d_pve)
	_check(d_pve < 130.0, "PvE 扣血仍在 100 点这一档（±减免/浮动）", "扣 %.1f" % d_pve)
	_check(absf(d_mat / maxf(d_pve, 0.001)
			- MatchDB.match_damage_scale("boss_huyao")) < 3.0,
			"棋盘上同一记伤害正好放大到倍率那么多",
			"%.1f vs %.1f = %.1fx" % [d_mat, d_pve, d_mat / maxf(d_pve, 0.001)])
	for n in [atk_pve, tgt_pve, atk_m, tgt_m]:
		(n as Node).queue_free()
	await get_tree().process_frame


# ===================== 三、剑客满层巨剑一局一次 =====================

func _mk_sword(team: int) -> Node:
	var p := MatchAdapter.spawn_piece(self, "boss_01_c", team, Vector2i(2, 2))
	if p != null:
		p.set("_phase2", true)
		p.set("target", null)
	return p


func _swing(p: Node) -> Dictionary:
	p.set("intent", DomainBoss01C.INTENT_MAX)
	p.call("_start_heaven_strike")
	var full := bool(p.get("_heaven_is_full"))
	var form_id := String((p.get("_heaven_form") as Dictionary).get("id", ""))
	var rng := float((p.get("_heaven_form") as Dictionary).get("range", 0.0))
	p.call("_fire_heaven", {})
	return {"full": full, "form": form_id, "range": rng,
			"casts": int(p.get("_heaven_full_casts"))}


func _check_swordsman_once() -> void:
	print("\n### 3. 满层一剑开天：棋盘一局一次，PvE 不限")
	var piece := _mk_sword(0)
	var dummy := _mk_sword(1)
	if piece == null or dummy == null:
		_check(false, "剑客棋子生成成功", "有 null")
		return
	await get_tree().physics_frame
	_check(bool(piece.call("_heaven_full_allowed")), "开局时满层形态可用", "")
	var first := _swing(piece)
	_check(bool(first["full"]) and int(first["casts"]) == 1,
			"第一次满层 → 放的是「剑意盈天」并记了一次", str(first))
	_check(not bool(piece.call("_heaven_full_allowed")),
			"用掉之后棋盘里满层形态不再可用", "")
	_check(not bool(piece.call("_heaven_will_be_full")),
			"招名/评分/强制抢放读的是同一个判定（不会出现报错名落普通剑）", "")
	var second := _swing(piece)
	_check(not bool(second["full"]) and int(second["casts"]) == 1,
			"第二次满层自动降回常规一剑开天（招式没被整门删掉）", str(second))
	_check(float(second["range"]) > 0.0, "降级那一剑仍按剑意层数算范围", str(second["range"]))
	# 弹刀作废的那一剑不能白烧唯一一次
	var p2 := _mk_sword(0)
	await get_tree().physics_frame
	p2.set("intent", 5)
	p2.call("_start_heaven_strike")
	_check(bool(p2.get("_heaven_is_full")), "起手先定成满层形态", "")
	p2.call("_abort_heaven")
	_check(not bool(p2.get("_heaven_is_full")), "弹刀作废后不占唯一一次", "")
	p2.call("_start_heaven_strike")
	_check(bool(p2.get("_heaven_is_full")), "作废之后下一次满层仍然是盈天形态", "")
	p2.queue_free()
	# PvE 对照：同一套调用必须每次都满层
	var pve := _mk_sword(-1)
	await get_tree().physics_frame
	var a := _swing(pve)
	var b := _swing(pve)
	_check(bool(a["full"]) and bool(b["full"]),
			"秘境 / 塔 / 演武场（team_id=-1）不受这条限制，两次都是盈天",
			"%s / %s" % [str(a["full"]), str(b["full"])])
	_check(bool(pve.call("_heaven_full_allowed")), "PvE 判定永远放行", "")
	for n in [piece, dummy, pve]:
		(n as Node).queue_free()
	await get_tree().process_frame


# ===================== 四、端到端：虎妖真的打得出血了 =====================

func _check_huyao_duel() -> void:
	print("\n### 4. 虎妖在棋盘上的实际输出")
	var a := MatchAdapter.spawn_piece(self, "boss_huyao", 0, Vector2i(1, 4))
	var b := MatchAdapter.spawn_piece(self, "boss_02", 1, Vector2i(4, 1))
	if a == null or b == null:
		_check(false, "对决双方生成成功", "有 null")
		return
	await get_tree().physics_frame
	var max_hp := float(b.get("max_hp"))
	var lowest := max_hp
	var t := 0.0
	while t < 12.0 and is_instance_valid(a) and is_instance_valid(b):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		lowest = minf(lowest, float(b.get("current_hp")))
	var dealt := max_hp - lowest
	var eff := dealt / maxf(t, 0.001)
	var nominal := float(MatchDB.piece_stats("boss_huyao").get("dps", 0.0))
	# 门槛只取名义值的 15%：这段里虎妖要先跑 950px 接近、还要挨打，
	# 早期采样天然偏低（22 秒口径实测能到 1243 DPS）。但修之前它只有 2 DPS，
	# 12 秒一共打掉 24 点血 —— 这条判据照样能把它当场拦下来。
	_check(dealt > nominal * t * 0.15,
			"对决里虎妖真的打得出血（修前 12 秒只打掉 24 点）",
			"共 %.0f 伤害 ≈ %.0f DPS，名义 %.0f，门槛 %.0f" % [
					dealt, eff, nominal, nominal * t * 0.15])
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


# ===================== 五、校准表的完整性 =====================

## 这次翻车的形状值得钉一条：`ATTACK_CALIB` 缺一只就会静默退回"目标 DPS 当攻击力"，
## 而目标 DPS 只有真实输出的几分之一 —— 表现就是"某只棋子怎么打都不掉血"，
## 和虎妖这次的倍率问题一模一样，只是没人报警。
func _check_calibration_shape() -> void:
	print("\n### 5. 校准表完整性")
	var missing: Array = []
	var off_band: Array = []
	for raw in MatchDB.CARD_POOL:
		var id := String(raw)
		if not MatchDB.ATTACK_CALIB.has(id):
			missing.append(id)
			continue
		var dps := float(MatchDB.piece_stats(id).get("dps", 0.0))
		# 设计口径是 ±20% 窄带（差异交给机制），超出就说明 FACTORS 被人顺手改过
		if dps < MatchDB.PIECE_DPS_BASE * 0.79 or dps > MatchDB.PIECE_DPS_BASE * 1.21:
			off_band.append("%s=%.0f" % [id, dps])
		if MatchDB.FLAT_DAMAGE_CARDS.has(id) and float(MatchDB.ATTACK_CALIB[id]) <= 0.0:
			off_band.append("%s 没有校准值却挂在倍率表里" % id)
	_check(missing.is_empty(), "16 张卡全都有 DPS 校准值（缺一只就静默弱十倍）", str(missing))
	_check(off_band.is_empty(), "名义 DPS 全在 ±20% 窄带内", str(off_band))
	_check(int(MatchDB.ATTACK_CALIB["boss_01_c"]) < int(MatchDB.ATTACK_CALIB["boss_huyao"]),
			"剑客不再靠高攻击力压制（2026-11-03 折算下调后比虎妖低一大截）",
			"剑客 %d / 虎妖 %d" % [int(MatchDB.ATTACK_CALIB["boss_01_c"]),
					int(MatchDB.ATTACK_CALIB["boss_huyao"])])
