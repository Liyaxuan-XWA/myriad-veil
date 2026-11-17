extends Node
## 11-12 审计查出的 4 张「选了没效果」的卡，接线后的行为验收。
##
## 跑法：godot --headless --path . --quit-after 900 res://tools/probe_rogue_cards_fixed.tscn -- --no-save
##
## 判据口径（和 probe_talisman_family 同一套）：
##   ① 不看「代码里有没有这一行」，看**加这张卡前后，战斗读数变没变**；
##   ② 每组都带一条「题目成立」前置断言，防止在空现场上测出一个假绿；
##   ③ 读数等事件（掉血 / 回灵），不猜时长；施放走真实入口（Input.action_press）。
##
## 覆盖：不灭（复活数派生）· 焚息（投日命中回灵）· 剑气随身（平A附带剑气）· 焚风（乘对字段）。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const MINION_SCENE := "res://scenes/world/world_enemy.tscn"

var _passes := 0
var _fails: Array = []
var _dummies: Array = []
var _dummy_seq := 0
## 最近一次平A测量的重试次数，拼进读数（偶发整刀不落地时要能看出是哪趟）
var _attack_diag := ""


func _ready() -> void:
	print("\n########## 四张修复卡 · 行为验收 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


func _make_dummy(pos: Vector2) -> WorldEnemy:
	var e := (load(MINION_SCENE) as PackedScene).instantiate() as WorldEnemy
	_dummy_seq += 1
	e.name = "Dummy%d" % _dummy_seq
	var cfg := {
		"pos": pos, "max_hp": 1000000.0, "attack_power": 1.0, "move_speed": 0.0,
		"visual_id": "rogue_rat", "aggro_range": 1.0, "leash_range": 1.0,
		"melee_range": 1.0, "melee_angle": 1.0, "melee_coeff": 0.0,
		"body_radius": 20.0, "attack_name": "不动", "skills": [], "cast_coeff": 0.0,
	}
	e.position = pos
	e.configure(cfg, WorldEnemy.KIND_BEAST, "木桩")
	if not e.is_in_group("boss"):
		e.add_to_group("boss")
	add_child(e)
	e.global_position = pos
	_dummies.append(e)
	return e


func _park_dummies() -> void:
	for d in _dummies:
		if is_instance_valid(d):
			d.global_position = Vector2(4000.0, 0.0)


func _hp(node: Node) -> float:
	return float(node.get("current_hp"))


func _wait_hit(target: Node, from_hp: float, limit_ms: int = 900) -> void:
	var t0 := Time.get_ticks_msec()
	while _hp(target) >= from_hp and Time.get_ticks_msec() - t0 < limit_ms:
		await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	# ===== 1. 不灭：复活数必须是**派生**的，不是开局算死的一次性数字 =====
	RogueRun.start_run("sword", [])
	_check(RogueRun.revive_total() == RogueDB.REVIVE_PER_RUN,
		"没拿不灭时复活数 = 基值", "%d" % RogueRun.revive_total())
	_check(RogueRun.revive_left() == RogueRun.revive_total(),
		"开局剩余 = 总数", "%d" % RogueRun.revive_left())
	RogueRun.add_buff("g_revive")
	_check(RogueRun.stat("revive_plus") > 0.0, "不灭进了 stat 通道",
		str(RogueRun.stat("revive_plus")))
	_check(RogueRun.revive_total() == RogueDB.REVIVE_PER_RUN + 1,
		"拿到不灭 → 本局复活次数 +1",
		"%d → %d" % [RogueDB.REVIVE_PER_RUN, RogueRun.revive_total()])
	_check(RogueRun.revive_left() == RogueRun.revive_total(),
		"中途选到也立刻补足（不是只写进 stats 没人算）")
	RogueRun.revives_used = 1
	_check(RogueRun.revive_left() == RogueRun.revive_total() - 1,
		"用掉一条后剩余正确", "%d" % RogueRun.revive_left())
	RogueRun.buffs.clear()
	RogueRun.rebuild()
	_check(RogueRun.revive_total() == RogueDB.REVIVE_PER_RUN,
		"退掉不灭后总数回到基值（派生不残留）", "%d" % RogueRun.revive_total())
	RogueRun.revives_used = 0
	RogueRun.restore()

	# ===== 2. 进战斗场景：焚息 / 剑气随身 都要真打一下 =====
	RogueRun.start_run("sword", [])
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.get("player")
	var rogue: Node = arena.get("_rogue")
	if player == null or rogue == null:
		_check(false, "战斗场景创建失败")
		RogueRun.restore()
		return
	rogue.set_process(false)
	rogue.set_physics_process(false)

	# ===== 3. 焚息：投日**命中**才回灵，且必须真回 =====
	var wind_form: Dictionary = MoveDB.resolve_player("form_sun_wind")
	_check(not wind_form.is_empty() and not MoveDB.resolve_player("form_sun_throw").is_empty(),
		"逐日招式能 resolve（题目成立）")

	# ===== 4. 焚风：乘的必须是 spell_coeff（ phys_coeff 是 0，乘它等于没乘）=====
	var wind0 := float(MoveDB.resolve_player("form_sun_wind").get("spell_coeff", 0.0))
	var wind_phys := float(MoveDB.resolve_player("form_sun_wind").get("phys_coeff", 0.0))
	_check(wind0 > 0.0 and wind_phys == 0.0,
		"焚风基线：spell_coeff 有值、phys_coeff 为 0（这就是老写法空转的原因）",
		"spell=%.2f phys=%.2f" % [wind0, wind_phys])
	RogueRun.add_buff("u_wind")
	var wind1 := float(MoveDB.resolve_player("form_sun_wind").get("spell_coeff", 0.0))
	_check(wind1 > wind0 * 1.14 and wind1 < wind0 * 1.16,
		"焚风 ×1.15 真的乘进了结算", "%.2f → %.2f" % [wind0, wind1])
	RogueRun.buffs.clear()
	RogueRun.rebuild()

	# ===== 5. 焚息：投日命中回灵 =====
	# ⚠ 走真实入口 `try_use_skill`（扣蓝 / 冷却 / 校验都在里面），不要直接调 `_cast_sun_*`：
	#   第一版直接调私有施法，蓝没扣、命中也没落地，读出来的差值全是假的。
	# ⚠ 比的是**两趟读数的差**，不是「放之前 vs 放之后」—— 投日要扣蓝，
	#   直接前后比会把扣的蓝算成没回。同一招扣的蓝是同一个数，差值才等于回灵量。
	var mana_no := 0.0
	var mana_yes := 0.0
	for pass_i in range(2):
		RogueRun.buffs.clear()
		if pass_i == 1:
			RogueRun.add_buff("u_throw_mana")
		RogueRun.rebuild()
		_clear_skill_cd(player)
		_equip_skill("skill_sun_throw")
		_park_dummies()
		var d := _make_dummy(player.global_position + Vector2(260.0, 0.0))
		await get_tree().process_frame
		player.set("mana", float(player.get("max_mana")))
		var h0 := _hp(d)
		var cast_ok := bool(player.call("try_use_skill", "skill_sun_throw"))
		await _wait_hit(d, h0)
		await _wait_ms(150)
		if pass_i == 0:
			_check(cast_ok, "投日能通过真实入口施放（题目成立）", str(cast_ok))
			mana_no = float(player.get("mana"))
		else:
			mana_yes = float(player.get("mana"))
	_check(mana_no < float(player.get("max_mana")) - 1.0,
		"投日真的扣了蓝（题目成立：不扣蓝就说明根本没施放）",
		"max=%s → mana=%.2f" % [str(player.get("max_mana")), mana_no])
	var want := RogueRun.stat("sun_throw_mana")
	_check(want > 0.0, "焚息叠层后进 stat 通道", str(want))
	_check(absf((mana_yes - mana_no) - want) < 1.5,
		"焚息：投日命中真的回灵（两趟读数差 = 回灵量）",
		"不带卡 %.2f → 带卡 %.2f，差 %.2f / 期望 %.1f" % [
			mana_no, mana_yes, mana_yes - mana_no, want])
	RogueRun.buffs.clear()
	RogueRun.rebuild()

	# ===== 6. 剑气随身：满剑意的平A要多出一段 ≈ 0.5× 法强 =====
	var swing := await _attack_damage(player, false)
	_check(swing > 0.0, "满剑意平A能打出伤害（题目成立：不带卡也得有基线）",
			"%.1f %s" % [swing, _attack_diag])
	var swing_qi := await _attack_damage(player, true)
	var expect := CharacterData.spell_attack() * 0.50
	var extra := swing_qi - swing
	_check(absf(extra - expect) < maxf(2.0, expect * 0.30),
		"剑气随身：多出来的那一段 ≈ 0.5× 法强",
		"平A %.1f → 带卡 %.1f，多出 %.1f / 期望 %.1f（%s）" % [
			swing, swing_qi, extra, expect, _attack_diag])
	_check(RogueRun.has_flag("intent_attack_qi"), "剑气随身的 flag 通道在")

	await _wait_ms(200)
	for d in _dummies:
		if is_instance_valid(d):
			d.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	RogueRun.restore()
	_check(true, "收尾：战斗场景已释放，RogueRun.restore() 跑过")


## 清掉功法冷却：Dictionary 是引用，取出来 clear() 就改到玩家身上那份
func _clear_skill_cd(player: Node) -> void:
	var cd: Dictionary = player.get("skill_cooldowns")
	cd.clear()


## 把一张功法装进「习得 + 装配」两份表 —— can_use_skill 两个都查，缺一个就报「尚未…」
func _equip_skill(skill_id: String) -> void:
	if not (skill_id in CharacterData.learned_skills):
		CharacterData.learned_skills.append(skill_id)
	if not (skill_id in CharacterData.active_skill_loadout):
		if CharacterData.active_skill_loadout.size() > 0:
			CharacterData.active_skill_loadout[0] = skill_id
		else:
			CharacterData.active_skill_loadout.append(skill_id)


## 把场景里**不是我造的**敌人清掉。
## ⚠ 试炼战斗场景一开局就自己刷了一波小怪（Rogue_rogue_rat），它们就贴在玩家身边：
##   平A / 剑气会打到它们头上，我的木桩反而没掉血 —— 这就是「带卡那趟读数和基线一样」
##   的真因（诊断行里出现过「锁定 Rogue_rogue_rat」）。queue_free 不发 died 信号，
##   加上 rogue 的 _process 已被停掉，不会误判成清波推进。
func _clear_other_enemies(keep: Node) -> void:
	for raw in get_tree().get_nodes_in_group("boss"):
		if raw == keep or not is_instance_valid(raw):
			continue
		if String((raw as Node).name).begins_with("Dummy"):
			continue
		(raw as Node).queue_free()


## 满剑意平A一次的总落伤。带不带卡只差那一段剑气。
## ⚠ 按键必须等**真的被分发吃到**（combo 自增 = _start_attack 跑过）再松手：
##   只 press+await 固定时长，headless 下常常一整刀都没起手，基线读成 0
##   （第一版就是这么红的 —— 反倒是带卡那趟冒出 15.2 证明剑气本身是通的）。
func _attack_damage(player: Node2D, with_card: bool) -> float:
	var dealt := 0.0
	var tries := 0
	for attempt in range(3):
		tries += 1
		dealt = await _one_swing(player, with_card)
		# 题目成立要**每一趟**都成立：变异①那一跑就是第二刀整刀没落（读 0.0），
		# 比值跟着假红。基线红了才有资格谈带卡的差值。
		if dealt > 0.0:
			break
	_attack_diag = "试 %d 次 · %s" % [tries, _attack_diag]
	return dealt


## 一刀一测。按键必须等**真的被分发吃到**（combo 自增 = _start_attack 跑过）再松手：
## 只 press+await 固定时长，headless 下常常一整刀都没起手（第一版就是这么红的）。
func _one_swing(player: Node2D, with_card: bool) -> float:
	RogueRun.buffs.clear()
	if with_card:
		RogueRun.add_buff("s_jq_atk")
	RogueRun.rebuild()
	_park_dummies()
	var d := _make_dummy(player.global_position + Vector2(120.0, 0.0))
	_clear_other_enemies(d)
	await get_tree().process_frame
	player.set("sword_intent", RogueRun.cap("sword_intent_max"))
	player.set("attack_combo", 0)
	player.set("is_attacking", false)
	player.set("attack_dir", Vector2.RIGHT)
	player.set("velocity", Vector2.ZERO)
	await _wait_ms(80)
	var h0 := _hp(d)
	var combo0 := int(player.get("attack_combo"))
	Input.action_press("attack")
	var guard := 0
	while int(player.get("attack_combo")) == combo0 and guard < 60:
		await get_tree().physics_frame
		guard += 1
	Input.action_release("attack")
	guard = 0
	while bool(player.get("is_attacking")) and guard < 240:
		await get_tree().physics_frame
		guard += 1
	# ⚠ 这里**不能**用 _wait_hit（一掉血就返回）：平A与剑气是同一帧起的两段结算，
	#   但吸附 tween / 连段收尾还会往后排几十毫秒，早读会把剑气那一段读丢
	#   （实测带卡那趟读出 9.9 ≈ 纯平A，假红一次）。等整刀落定再取总量。
	await _wait_ms(450)
	var dealt := h0 - _hp(d)
	# 现场读数：剑气不出来时，要能一眼看出是**门槛没过**还是**没锁到目标**
	var tgt = player.call("_intent_slash_target")
	_attack_diag = "剑意 %d/%d / 锁定 %s / 距 %.0f / dir=%.2f / 场上敌人 %d" % [
		int(player.get("sword_intent")), RogueRun.cap("sword_intent_max"),
		str(tgt.get("name")) if tgt != null else "null",
		player.global_position.distance_to(d.global_position),
		(player.get("attack_dir") as Vector2).x,
		get_tree().get_nodes_in_group("boss").size()]
	d.global_position = Vector2(4000.0, 0.0)
	return dealt
