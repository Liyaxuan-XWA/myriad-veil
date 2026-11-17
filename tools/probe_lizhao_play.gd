extends Node
## 离照 · 走位夺火实测（2026-10-29）
## 真实 CombatArena + 真实 Player + 离照 AI。同一个固定种子跑两段：
##   A 段「不躲」：捡到火种就站住 —— 证明不打走位时照旧被夺火，BOSS 没被削废；
##   B 段「会躲」：捡到火种后侧移，看到夺火招就撤 —— 证明躲开判定就能保住火种。
## 用法：godot --headless --path . res://tools/probe_lizhao_play.tscn

const STEAL_FORMS := ["form_sun_step", "form_sun_pull", "form_sun_wind", "form_sun_eclipse"]
const TICK := 0.1
const SPEED := 220.0


var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _sum(d: Dictionary) -> int:
	return int(d.values().reduce(func(a, b2): return a + b2, 0))


func _ready() -> void:
	print("\n########## 离照 · 走位夺火实测 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	seed(20261030)
	var ids := ["skill_sun_step", "skill_sun_slash", "skill_sun_throw", "skill_sun_pull",
		"skill_sun_wind", "skill_sun_eclipse", "skill_sun_wheel", "skill_sun_meteor"]
	for sid in ids:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	if not CharacterData.passive_skill_loadout.has("skill_sun_wheel"):
		CharacterData.passive_skill_loadout.append("skill_sun_wheel")
	# 故意带上一门灾功法：三灾轮盘会建出来，但这一战没有能涨灾势的对手 → 必须隐藏
	if not CharacterData.learned_skills.has("skill_calamity_step"):
		CharacterData.learned_skills.append("skill_calamity_step")
	if not CharacterData.active_skill_loadout.has("skill_calamity_step"):
		CharacterData.active_skill_loadout.append("skill_calamity_step")
	CharacterData.current_realm = "结丹"
	CharacterData.realm_stage = 2
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03_b",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 3:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	_check(player != null and is_instance_valid(player), "真实 Player 已生成")
	_check(boss != null and is_instance_valid(boss), "真实 BOSS 已生成")
	if player == null or boss == null:
		return
	_check(boss.boss_id == "boss_03_b", "箱庭加载的是离照", boss.boss_id)
	_check(player._calamity_wheel != null and is_instance_valid(player._calamity_wheel),
		"带上灾功法后三灾轮盘已创建")
	_check(not player._calamity_wheel.visible,
		"场上没有能涨灾势的对手 → 三灾轮不显示")
	var a := await _sim(player, boss, false)
	var b := await _sim(player, boss, true)
	_report("A 不躲", a)
	_report("B 会躲", b)
	_check(_sum(a["att"]) >= 3, "站住不躲时离照反复来抢火", "%d 次尝试" % _sum(a["att"]))
	_check(_sum(a["hit"]) >= 2, "不躲就照旧被夺火（BOSS 没被削废）",
		"%d 次命中" % _sum(a["hit"]))
	# 走位段只作参考：这一段的「躲」是脚本强行位移，不能代表真人操作；
	# 四招能不能躲由 probe_lizhao 的几何断言负责（每招都有命中 / 落空各一条）。
	_check(_sum(b["att"]) >= 1, "会躲时离照仍然来抢火", "%d 次尝试" % _sum(b["att"]))
	_check(b["player"] > 0 and b["boss"] > 0, "两段里双方都拿过火种",
		"玩家 %d / BOSS %d tick" % [int(b["player"]), int(b["boss"])])
	_check(is_instance_valid(boss) and not player.is_dead, "两段模拟都没有异常")
	GameState.battle_context = {}


func _report(tag: String, s: Dictionary) -> void:
	var parts := ""
	for k in STEAL_FORMS:
		parts += "%s %d→%d✗%d " % [String(k).replace("form_sun_", ""),
			int(s["att"].get(k, 0)), int(s["hit"].get(k, 0)), int(s["whiff"].get(k, 0))]
	print("  %s：%s｜持有 BOSS %d / 玩家 %d tick" % [tag, parts, int(s["boss"]), int(s["player"])])


## 跑一段自动战斗；dodge=false 捡到火种就站住，true 则侧移并在看到夺火招后撤。
## 这一段玩家不放任何功法：只测「走位 vs 离照的夺火判定」，归属变化全部来自 BOSS 侧。
func _sim(player: Node2D, boss: Node2D, dodge: bool) -> Dictionary:
	var att := {}
	var hit := {}
	var whiff := {}
	var pending: Array = []
	var boss_hold := 0
	var player_hold := 0
	var strafe := 1.0
	var last_skill := ""
	var t := 0.0
	boss.current_hp = boss.max_hp
	boss.phase = 1
	boss.state = BossBase.BossState.IDLE
	# 隔离：场上只留一枚火种，并关掉盗火者的自动凝种，免得第二枚种干扰走位决策
	CharacterData.passive_skill_loadout.erase("skill_sun_wheel")
	for s0 in get_tree().get_nodes_in_group("sun_seed"):
		s0.queue_free()
	await get_tree().process_frame
	player.global_position = boss.global_position + Vector2(0.0, 200.0)
	var starter := SunSeed.new()
	add_child(starter)
	starter.global_position = player.global_position
	starter.pickup(player)
	boss._seed = starter
	boss._seed_respawn_left = 9999.0
	while t < 24.0:
		await get_tree().create_timer(TICK, true, false, true).timeout
		t += TICK
		if not is_instance_valid(player) or not is_instance_valid(boss) or player.is_dead:
			break
		player.invincible_timer = 999.0
		player.hp = maxf(player.hp, player.max_hp * 0.9)
		var seed: Node = boss._seed
		var holding: bool = seed != null and is_instance_valid(seed) \
			and seed.holder == player and int(seed.state) == int(SunSeed.State.HELD)
		# 补给：BOSS 把火抢走 / 火种烧掉之后，立刻把火还给玩家，继续测下一次夺火
		if not holding and pending.is_empty():
			if seed != null and is_instance_valid(seed):
				seed.queue_free()
			starter = SunSeed.new()
			add_child(starter)
			starter.global_position = player.global_position
			starter.pickup(player)
			boss._seed = starter
			seed = starter
		# 隔离量：这一轮只测「走位 vs 夺火判定」，不让满层爆裂把火种带走
		if seed != null and is_instance_valid(seed) and seed.holder == player:
			seed.stacks = 0
			seed._stack_timer = 0.0
			seed._unstable_left = 0.0
		# 已登记的夺火尝试：一旦真的易主 / 被烧掉就记为命中
		for e in pending:
			if bool((e as Dictionary)["got"]):
				continue
			if _landed(e, boss, player):
				(e as Dictionary)["got"] = true
		for k in range(pending.size() - 1, -1, -1):
			var e2: Dictionary = pending[k]
			if t < float(e2["at"]):
				continue
			pending.remove_at(k)
			var form := String(e2["form"])
			if bool(e2["got"]):
				hit[form] = int(hit.get(form, 0)) + 1
			else:
				whiff[form] = int(whiff.get(form, 0)) + 1
		if seed != null and is_instance_valid(seed):
			if seed.is_free():
				var to_s: Vector2 = seed.global_position - player.global_position
				if to_s.length() > 4.0:
					player.global_position += to_s.normalized() * SPEED * TICK
			elif seed.holder == player and dodge:
				var to_b: Vector2 = boss.global_position - player.global_position
				if to_b.length() > 1.0:
					var fleeing := false
					for e3 in pending:
						if float((e3 as Dictionary)["at"]) > t:
							fleeing = true
					# 读招期间保持一个方向，别在预警圈里来回晃
					if not fleeing and int(t * 10.0) % 14 == 0:
						strafe = -strafe
					var tang := to_b.orthogonal().normalized() * strafe
					# 绕着 BOSS 转圈、把距离维持在 200~300：不顶墙，也不贴脸
					var d_rb := to_b.length()
					var radial := to_b.normalized() * (
						0.9 if d_rb < 200.0 else (-0.9 if d_rb > 300.0 else 0.0))
					var mv: Vector2 = tang + radial
					if mv.length() > 1.0:
						player.global_position += mv.normalized() * SPEED * TICK
			if seed.holder == boss:
				boss_hold += 1
			elif seed.holder == player:
				player_hold += 1
		var cur := String(boss._current_skill)
		for e4 in pending:
			var e5: Dictionary = e4
			if not e5.has("pc") and t >= float(e5["t0"]) \
					+ float(MoveDB.resolve_boss(String(e5["form"])).get("windup", 0.7)):
				e5["pc"] = player.global_position
		if cur != last_skill:
			last_skill = cur
			if cur in STEAL_FORMS and seed != null and is_instance_valid(seed) \
					and seed.holder == player:
				att[cur] = int(att.get(cur, 0)) + 1
				var kind := "hold"
				if cur == "form_sun_eclipse":
					kind = "lose"
				elif cur == "form_sun_wind":
					kind = "drop"
				pending.append({"form": cur, "at": t + _deadline(cur), "id": seed.get_instance_id(),
					"kind": kind, "got": false, "p0": player.global_position, "t0": t})
	return {"att": att, "hit": hit, "whiff": whiff, "boss": boss_hold, "player": player_hold}


## 该招从起手到结算最迟多久；过了这个时间还没易主 / 没烧掉就算被躲开
func _deadline(form: String) -> float:
	match form:
		"form_sun_step":
			return 0.90
		"form_sun_pull":
			return 1.15
		"form_sun_wind":
			return 0.72
		_:
			return 1.42


func _landed(e: Dictionary, boss: Node2D, player: Node2D) -> bool:
	for s in get_tree().get_nodes_in_group("sun_seed"):
		if int(s.get_instance_id()) != int(e["id"]):
			continue
		match String(e["kind"]):
			"lose":
				return int(s.state) == int(SunSeed.State.GONE)
			"drop":
				return s.holder != player
			_:
				return s.holder == boss
	return true
