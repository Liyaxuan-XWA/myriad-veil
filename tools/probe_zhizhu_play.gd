extends Node
## 执烛 · 无头假玩家实测（2026-11-02）
## 真实 CombatArena + 真实 Player + 执烛 AI，跑三种节奏各 30 秒：
##   A 贴脸循环：靠近 → 站桩 1.2s 输出 → 拉开；
##   B 风筝：绕圈维持 300~420；
##   C 抢影：主动往「灯与执烛」之间站，用走位拆它的射程。
## 统计每招出手次数、开局距离、玩家掉血，以及**选招门禁违规次数**
## （= 释放那一帧影身根本没盖住玩家，却仍然放了投晷 / 缚影）。
## 用法：godot --headless --path . res://tools/probe_zhizhu_play.tscn -- --no-save

const TICK := 0.1
const GATED: Array[String] = ["form_shadow_reach", "form_shadow_bind"]
const ALL_FORMS: Array[String] = [
	"form_shadow_cut", "form_shadow_reach", "form_shadow_bind", "form_shadow_step",
	"form_shadow_dim", "form_shadow_beam", "form_shadow_split", "form_shadow_longnight",
]

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
	print("\n########## 执烛 · 无头假玩家实测 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	seed(20261102)
	for sid in ["skill_shadow_reach", "skill_shadow_cut", "skill_shadow_beam",
			"skill_shadow_bind", "skill_shadow_lamp"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = ["skill_shadow_reach", "skill_shadow_cut",
		"skill_shadow_beam", "skill_shadow_bind"]
	CharacterData.passive_skill_loadout = []
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 1
	_wear_baseline(1, 6)
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04_b",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	_check(player != null and is_instance_valid(player), "真实 Player 已生成")
	_check(boss != null and is_instance_valid(boss), "真实 BOSS 已生成")
	if player == null or boss == null:
		return
	player._apply_attributes_to_runtime(true)
	print("  玩家面板：HP %.0f · 物攻 %.0f · 法强 %.0f" % [
		player.max_hp, CharacterData.physical_attack(), CharacterData.spell_attack()])
	var a := await _sim(player, boss, 0)
	var b := await _sim(player, boss, 1)
	var c := await _sim(player, boss, 2)
	_report("A 贴脸循环", a)
	_report("B 风筝绕圈", b)
	_report("C 抢灯拆射程", c)
	var seen := {}
	var gate_total := 0
	for s in [a, b, c]:
		for k in (s as Dictionary)["att"].keys():
			seen[String(k)] = true
		gate_total += int((s as Dictionary)["gate_violation"])
	_check(gate_total == 0, "三段都没有「影身没盖住却硬放远程」的空放",
		"违规 %d 次" % gate_total)
	for f in ["form_shadow_cut", "form_shadow_reach", "form_shadow_bind",
			"form_shadow_step", "form_shadow_dim", "form_shadow_beam", "form_shadow_split"]:
		_check(seen.has(f), "AI 真的用过 " + f)
	_check(seen.has("form_shadow_longnight") or int(a["max_phase"]) < 2,
		"二阶段大招在打到半血后出现过", "seen=%s" % str(seen.has("form_shadow_longnight")))
	_check(int(a["max_phase"]) >= 2, "假玩家把战斗自然推进到二阶段",
		"phase=%d" % int(a["max_phase"]))
	var a_ranged := int((a["att"] as Dictionary).get("form_shadow_reach", 0)) 			+ int((a["att"] as Dictionary).get("form_shadow_bind", 0))
	var c_ranged := int((c["att"] as Dictionary).get("form_shadow_reach", 0)) 			+ int((c["att"] as Dictionary).get("form_shadow_bind", 0))
	var c_gate := int((c["gate"] as Dictionary).values().reduce(func(x, y2): return x + y2, 0))
	_check(c_gate == 0, "抢灯段里执烛一次也没有硬放远程", "违规 %d 次" % c_gate)
	print("      参考：远程招出手 A %d 次 / C %d 次（站灯下它挣不到影长）" % [a_ranged, c_ranged])
	_check(float(b["player_hp_lost"]) > 0.0, "风筝段仍然会被打到（不是无敌靶）",
		"掉血 %.0f" % float(b["player_hp_lost"]))
	_check(is_instance_valid(boss) and not player.is_dead, "三段模拟都没有异常 / 玩家没被秒杀")
	GameState.battle_context = {}


func _report(tag: String, s: Dictionary) -> void:
	var parts := ""
	for f in ALL_FORMS:
		var n := int((s["att"] as Dictionary).get(f, 0))
		if n > 0:
			parts += "%s %d(落空%d/违规%d) " % [String(f).replace("form_shadow_", ""),
				n, int((s["whiff"] as Dictionary).get(f, 0)),
				int((s["gate"] as Dictionary).get(f, 0))]
	print("  %s：%s" % [tag, parts])
	print("      开局距离 %.0f · 玩家掉血 %.0f · BOSS 结束血 %.0f · 最高阶段 %d" % [
		float(s["start_dist"]), float(s["player_hp_lost"]), float(s["boss_hp_end"]),
		int(s["max_phase"])])


## mode 0 贴脸循环 / 1 风筝绕圈 / 2 抢灯（站到灯与 BOSS 之间）
func _sim(player: Node2D, boss: Node2D, mode: int) -> Dictionary:
	var att := {}
	var whiff := {}
	var gate := {}
	var last_skill := ""
	var pending: Array = []
	var hp_min := 0.0
	var max_phase := 1
	boss.current_hp = boss.max_hp * (0.62 if mode == 0 else 1.0)
	boss.phase = 1
	boss.state = BossBase.BossState.IDLE
	boss._cools.clear()
	boss._recent.clear()
	player.hp = player.max_hp
	hp_min = player.max_hp
	player.global_position = boss.global_position + Vector2(0.0, 260.0)
	await get_tree().process_frame
	var start_dist: float = player.global_position.distance_to(boss.global_position)
	var t := 0.0
	var strafe := 1.0
	while t < 30.0:
		await get_tree().create_timer(TICK).timeout
		t += TICK
		if not is_instance_valid(player) or not is_instance_valid(boss):
			break
		if player.is_dead:
			player.hp = player.max_hp
		player.stamina = player.max_stamina
		player.mana = player.max_mana
		if boss.phase == 2:
			max_phase = 2
		_move_player(player, boss, mode, t, strafe)
		if int(t * 10.0) % 27 == 0:
			strafe = -strafe
		# 玩家真实出手（普攻 + 功法），让战斗自然推进到二阶段
		if int(t * 10.0) % 3 == 0 and not player.is_attacking:
			player.attack_dir = (boss.global_position - player.global_position).normalized()
			player._start_attack()
		if int(t * 10.0) % 22 == 0:
			for sid in CharacterData.active_skill_loadout:
				if player.try_use_skill(String(sid)):
					break
		# 记 BOSS 出手：起手那一帧登记，落帧看有没有打中
		var cur := String(boss._current_skill)
		if cur != "" and cur != last_skill:
			att[cur] = int(att.get(cur, 0)) + 1
			pending.append({"form": cur, "hp0": player.hp, "t0": t,
				"cover": boss._channel_covers(boss._channel(), player.global_position)})
		last_skill = cur
		for i in range(pending.size() - 1, -1, -1):
			var e: Dictionary = pending[i]
			var form := String(e["form"])
			var w: float = float(MoveDB.resolve_boss(form).get("windup", 0.7))
			if t < float(e["t0"]) + w + 0.22:
				continue
			pending.remove_at(i)
			if player.hp < float(e["hp0"]) - 0.5:
				continue
			whiff[form] = int(whiff.get(form, 0)) + 1
			if form in GATED and not bool(e["cover"]):
				## 起手时影身就没盖住人 —— 这才是「原地空放」，门禁必须拦住它
				gate[form] = int(gate.get(form, 0)) + 1
		hp_min = minf(hp_min, player.hp)
		player.hp = maxf(player.hp, player.max_hp * 0.62)
	return {"att": att, "whiff": whiff, "gate": gate,
		"gate_violation": int(gate.values().reduce(func(x, y2): return x + y2, 0)),
		"start_dist": start_dist, "player_hp_lost": player.max_hp - hp_min,
		"boss_hp_end": boss.current_hp, "max_phase": max_phase}


func _move_player(player: Node2D, boss: Node2D, mode: int, t: float, strafe: float) -> void:
	var to_b: Vector2 = boss.global_position - player.global_position
	var d := maxf(to_b.length(), 1.0)
	var radial := to_b.normalized()
	var tang := to_b.orthogonal().normalized() * strafe
	match mode:
		0:
			# 贴脸循环：靠近 → 站 1.2s → 拉开到 320
			var cyc := fmod(t, 4.0)
			if cyc < 1.4:
				player.global_position += radial * minf(220.0 * TICK, maxf(d - 96.0, 0.0))
			elif cyc < 2.6:
				pass
			else:
				player.global_position -= radial * 200.0 * TICK
		1:
			var keep := 360.0
			player.global_position += (tang * 1.0
					+ radial * (0.9 if d < keep - 40.0 else (-0.9 if d > keep + 40.0 else 0.0))) \
					.normalized() * 230.0 * TICK
		2:
			# 抢灯：站到「灯 → BOSS」连线的灯那一侧
			var lamp: Vector2 = boss._light_pos()
			var want: Vector2 = lamp + (boss.global_position - lamp).normalized() * 60.0
			var to_w: Vector2 = want - player.global_position
			if to_w.length() > 40.0:
				player.global_position += to_w.normalized() * 240.0 * TICK
	var lim: Vector2 = boss.arena_half_extents
	if lim != Vector2.ZERO:
		player.global_position = Vector2(
			clampf(player.global_position.x, -lim.x + 70.0, lim.x - 70.0),
			clampf(player.global_position.y, -lim.y + 70.0, lim.y - 70.0))


## 与 probe_zhizhu 同一套夹具：元婴初期 · 道器 +6（假玩家要能真的把战斗推进到二阶段）
func _wear_baseline(stage: int, enh: int) -> void:
	var enh_avg := {
		"strength": 1.5, "spell_power": 1.0, "hp_max": 3.0,
		"physical_resist": 1.0, "magic_resist": 1.0, "mana_max": 3.0,
		"mana_regen": 0.75, "speed_pct": 0.3, "attack_speed": 1.0,
		"spell_skill_damage_pct": 0.75, "stamina_regen_pct": 0.75,
	}
	for slot in CharacterData.SLOT_ORDER:
		CharacterData.equipment_slots[slot] = null
	var gear := ["eq_qingfengjian", "eq_jinwen_zhanpao", "eq_zhuri_lv",
		"eq_liangyi_yujue", "eq_qihai_yuzhui", "eq_leiwen_huqi"]
	var slots := ["weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3"]
	for i in gear.size():
		var tpl := ItemDB.get_equipment_template(String(gear[i]))
		var it := CharacterData.make_equipment_instance(tpl)
		var asc := maxi(0, ItemDB.grade_index("道器") - ItemDB.grade_index(String(it.get("equipment_grade", ""))))
		var attrs: Dictionary = {}
		var base = it.get("attributes_base", {})
		for k in base.keys():
			attrs[String(k)] = float(base[k])
		for j in asc:
			for k in attrs.keys():
				attrs[k] = float(attrs[k]) * 1.5
		for k in attrs.keys():
			if enh_avg.has(k):
				attrs[k] = float(attrs[k]) + float(enh_avg[k]) * float(enh)
		it["attributes"] = attrs
		it["equipment_grade"] = "道器"
		it["enhancement_level"] = enh
		CharacterData.equipment_slots[String(slots[i])] = it
