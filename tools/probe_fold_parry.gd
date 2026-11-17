extends Node
## 叠纸八式的弹反结算实测（2026-11-05 用户报：「叠纸boss的技能我弹反后还是会受到伤害」）
##
## 每个形态量两个数：**不弹挨多少** 与 **卡在命中帧弹还挨多少**。
## 只有两个数差开，才说明弹反真的吃到了这一式；两个数一样，就是"弹反成功但照样掉血"。
## 判据按 MoveDB 里写死的 attack_kind 分档：
##   physical_melee / physical_projectile → 必须 0 伤（`_is_parryable` 认这两档）
##   elemental                            → 本来就不可弹（只打印，不判红）
## 用法：godot --headless --path . res://tools/probe_fold_parry.tscn -- --no-save

const FORMS: Array[String] = [
	"form_fold_press", "form_fold_trace", "form_fold_stride", "form_fold_pressmark",
	"form_fold_tear", "form_fold_twin",
]
## 只在定位"伤害落在哪一拍"时打开
const TRACE := false

var _passes := 0
var _fails: Array[String] = []
var hurt_logged := false


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(20261105)
	print("\n########## 叠纸 · 弹反结算实测 ##########")
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	if player == null or boss == null:
		print("没有 player/boss，跑不了")
		get_tree().quit(2)
		return
	player._apply_attributes_to_runtime(true)
	if boss._field == null or not is_instance_valid(boss._field):
		boss._ensure_field()
	print("  弹反窗口 0.22 秒 · 精力满 · 假人血打不完")

	var rows: Array = []
	for f in FORMS:
		var raw: Dictionary = await _case(player, boss, f, false)
		var par: Dictionary = await _case(player, boss, f, true)
		var kind := String(MoveDB.resolve_boss(f).get("attack_kind", ""))
		var parryable := kind == "physical_melee" or kind == "physical_projectile"
		rows.append([f.replace("form_fold_", ""), kind,
			float(raw["player"]), float(par["player"]), float(par["boss"]), parryable])
		var tag := String(f.replace("form_fold_", ""))
		if float(raw["player"]) < 0.0 or float(par["player"]) < 0.0:
			_check(false, "%s 有一轮没能起手（返回值 -1 不是 0 伤，不能当绿）" % tag,
				"不弹=%s 弹后=%s" % [str(raw["player"]), str(par["player"])])
			continue
		if parryable:
			_check(float(raw["player"]) > 0.5,
				"%s 不弹确实挨打（形状真的盖到人，否则 0 伤是假绿）" % tag,
				"伤 %.0f" % float(raw["player"]))
			_check(float(par["player"]) <= 0.5,
				"%s 弹反成功后玩家 0 伤" % tag, "弹后仍伤 %.0f" % float(par["player"]))
			## 文案承诺的是"纸面折回来割它自己"，所以这一记必须落在 BOSS 身上
			_check(float(par["boss"]) > 0.5,
				"%s 弹反成功后「纸面折返」割的是 BOSS 自己" % tag,
				"它掉血 %.0f" % float(par["boss"]))
		else:
			_check(float(raw["player"]) > 0.5, "%s 不弹确实挨打" % tag,
				"伤 %.0f" % float(raw["player"]))
			print("      （%s 是 %s，按任务书法术档不可弹：弹后伤 %.0f）" % [
				tag, kind, float(par["player"])])

	print("\n  ── 汇总（不弹 → 弹后：玩家 / BOSS 自己）──")
	for r in rows:
		print("     %-10s %-16s 玩家 %6.0f → %6.0f · BOSS 弹后掉 %6.0f   %s" % [
			r[0], r[1], float(r[2]), float(r[3]), float(r[4]),
			"可弹" if bool(r[5]) else "不可弹"])
	# 三重落纸单独说明：它是 0.34 秒一段的三段延时结算，0.22 秒的弹反窗口只盖得住第一段
	print("     triple      elemental        三段各 0.34s 落下，单段弹反盖不住三段（未测）")
	print("---- 通过 %d · 失败 %d ----" % [_passes, _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)


## 摆位：让指定的那一式确实盖得住人。每个形态各摆各的，不靠运气。
func _place_for(form: String, player: Node2D, boss: Node2D, field) -> void:
	var b: Vector2 = boss.global_position
	var sp_dir := Vector2.UP          # BOSS→玩家
	match form:
		"form_fold_press":
			_move(player, b + Vector2(0.0, -140.0))
			field.bisect(b, player.global_position, 520.0)
		"form_fold_pressmark":
			_move(player, b + Vector2(0.0, -300.0))
			field.bisect(b, player.global_position, 520.0)
		"form_fold_trace":
			_move(player, b + Vector2(0.0, -200.0))
			_through(field, b, player.global_position)
		"form_fold_tear":
			_move(player, b + Vector2(0.0, -300.0))
			_through(field, b, player.global_position)
		"form_fold_twin":
			_move(player, b + Vector2(0.0, -300.0))
			field.bisect(b, player.global_position, 520.0)
		"form_fold_stride":
			field.bisect(b, b + Vector2(0.0, -300.0), 520.0)
			var sp: Dictionary = field.nearest(b)
			var e: Vector2 = sp.get("a", Vector2.ZERO) as Vector2
			## 把玩家摆在某枚圆牌的出口附近：跨缝的落点必须离人 ≤190 才成立
			_move(player, e + Vector2(0.0, 60.0))
		_:
			_move(player, b + sp_dir * 200.0)


## 顺折：一条从 BOSS 穿过玩家的痕（循痕/碎痕的走廊要的是"这条线真的伸到人身上"）
func _through(field, from: Vector2, to: Vector2) -> void:
	var u: Vector2 = (to - from).normalized()
	var mid := (from + to) * 0.5
	field.spans = [{"a": mid - u * 400.0, "b": mid + u * 400.0}]
	field._rebuild_nodes()


func _move(player: Node2D, p: Vector2) -> void:
	player.global_position = p
	player.velocity = Vector2.ZERO


func _arm(player: Node2D) -> void:
	player.is_dead = false
	player.max_hp = 1.0e9
	player.hp = 1.0e9
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0
	player.stamina = player.max_stamina
	player.is_parrying = false
	player.parry_timer = 0.0
	player.auto_parry_timer = 0.0
	player.parry_cooldown_timer = 0.0
	player.parry_stance_timer = 0.0


func _case(player: Node2D, boss: Node2D, form: String, parry: bool) -> Dictionary:
	var field = boss._field
	hurt_logged = false
	_arm(player)
	boss.current_hp = boss.max_hp
	boss.phase = 1
	boss.state = BossBase.BossState.IDLE
	boss.velocity = Vector2.ZERO
	## 上一轮的弹反奖励会给 BOSS 挂僵直/沉默，`is_skill_locked()` 一真
	## `_begin` 就直接 return —— 不清的话这一格根本没出手，返回值 -1 会被误判成"弹反成功"
	boss._cc_silence_left = 0.0
	boss._cc_slow_left = 0.0
	boss.phase_transitioning = false
	boss._cools.clear()
	boss._hit_once.clear()
	boss._current_skill = ""
	boss._decide_wait = 1.0e6      ## 这一发由夹具指定，不给选招插手
	boss._refold_ask = 1.0e6
	field._down_left = 0.0
	field._preview_left = 0.0
	field.set_phase(1)
	field.rebuild_near(boss.global_position)
	_place_for(form, player, boss, field)
	boss.target = player
	field.anchor_pos = player.global_position
	for i in 2:
		await get_tree().physics_frame
	boss._begin(form)
	if String(boss._current_skill) != form:
		print("      %s 起手被闸口拦住（%s）→ 本轮不算" % [form, String(boss._current_skill)])
		return {"player": -1.0, "boss": -1.0}
	var windup := float(boss.state_timer)
	var frames := int(round(windup * 60.0))
	var hp0: float = player.hp
	var bhp0: float = boss.current_hp
	var last_hp: float = hp0
	for i in frames:
		await get_tree().physics_frame
		## 命中前 0.10 秒按下弹反：窗口 0.22 秒，既能赶上又不至于早到出窗
		if parry and i == maxi(frames - 6, 0):
			player._start_parry()
			boss._decide_wait = 1.0e6
			if TRACE:
				print("        · 第 %d 拍按弹反：is_parrying=%s timer=%.2f blocked=%s" % [
					i, str(player.is_parrying), float(player.parry_timer),
					str(player.is_action_blocked())])
		if absf(last_hp - player.hp) > 0.5:
			if TRACE:
				print("        ▶ 掉血 %6.1f @ 第 %d 拍（前摇 %d 拍）state=%s 弹=%s timer=%.2f 招=%s" % [
					last_hp - player.hp, i, frames, str(boss.state),
					str(player.is_parrying), float(player.parry_timer), String(boss._current_skill)])
			last_hp = player.hp
	for i in 40:
		await get_tree().physics_frame
		if absf(last_hp - player.hp) > 0.5:
			if TRACE:
				print("        ▶ 掉血 %6.1f @ 前摇后第 %d 拍 state=%s 弹=%s timer=%.2f 招=%s" % [
					last_hp - player.hp, i, str(boss.state),
					str(player.is_parrying), float(player.parry_timer), String(boss._current_skill)])
			last_hp = player.hp
	boss._current_skill = ""
	boss.state = BossBase.BossState.IDLE
	return {"player": hp0 - player.hp, "boss": bhp0 - boss.current_hp}
