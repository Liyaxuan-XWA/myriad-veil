extends Node
## 试炼之路 · 虎妖「兽潮流」（虎煞）自检（2026-11-08）
## 覆盖：开关卡门禁、层数上限、伤害 / 攻速 / 移速三路接线、满层翻倍、
##       击杀真实叠层、满层击杀砍踏地冷却、收局清属性修正。
## 用法：godot --headless --path . res://tools/probe_rogue_hunt.tscn -- --no-save

const MINION_SCENE := "res://scenes/world/world_enemy.tscn"

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
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _make_dummy(pos: Vector2) -> WorldEnemy:
	var packed := load(MINION_SCENE) as PackedScene
	var e := packed.instantiate() as WorldEnemy
	var cfg := {
		"pos": pos, "max_hp": 100000.0, "attack_power": 1.0, "move_speed": 120.0,
		"visual_id": "rogue_rat", "aggro_range": 1.0, "leash_range": 1.0,
		"melee_range": 1.0, "melee_angle": 1.0, "melee_coeff": 0.0,
		"body_radius": 20.0, "attack_name": "不动", "skills": [], "cast_coeff": 0.0,
	}
	e.position = pos
	e.configure(cfg, WorldEnemy.KIND_BEAST, "木桩")
	add_child(e)
	return e


func _run() -> void:
	print("\n########## 试炼之路 · 兽潮流（虎煞）##########")
	await get_tree().process_frame

	# ===== 1. 数据完整性：兽潮流卡都在虎妖池里（2026-11-09 加「猎杀本能」后 6 张）=====
	var ids: Array = []
	for raw in RogueDB.BEAST_BUFFS:
		ids.append(String((raw as Dictionary).get("id", "")))
	_check(ids.size() >= 15, "虎妖池 ≥15 张（3 流派 × 5 + 机制拓展）", str(ids.size()))
	var hunt_cards := 0
	for id in ids:
		if String(id).begins_with("t_cy_"):
			hunt_cards += 1
	_check(hunt_cards >= 5, "兽潮流 ≥5 张已入池", str(hunt_cards))
	_check(RogueDB.family_of("t_cy_base") == "beast", "兽潮卡归属虎妖池")

	# ===== 2. 开关卡门禁：没有「虎煞」时击杀不产生任何层数 =====
	var spd_before_run := CharacterData.attribute("attack_speed")
	RogueRun.start_run("beast")
	await get_tree().process_frame
	_check(RogueRun.hunt_stacks == 0, "开局虎煞 0 层")
	RogueRun.add_hunt(1)
	_check(RogueRun.hunt_stacks == 0, "没拿「虎煞」卡时击杀不给层数")
	_check(absf(RogueRun.hunt_dmg_pct()) < 0.001, "没拿卡时虎煞增伤恒为 0")
	_check(RogueRun.hunt_cap() == RogueDB.HUNT_BASE_CAP, "基准上限 8",
		str(RogueRun.hunt_cap()))

	RogueRun.add_buff("t_cy_base")
	await get_tree().process_frame
	_check(RogueRun.has_flag("hunt_gain"), "「虎煞」打开 hunt_gain 开关")
	for i in 3:
		RogueRun.add_hunt(1)
	_check(RogueRun.hunt_stacks == 3, "击杀 3 次 → 3 层", str(RogueRun.hunt_stacks))

	# ===== 3. 上限：8 层封顶；「煞贯」抬到 12 =====
	for i in 20:
		RogueRun.add_hunt(1)
	_check(RogueRun.hunt_stacks == 8, "无卡时封顶 8 层", str(RogueRun.hunt_stacks))
	_check(RogueRun.hunt_is_full(), "8/8 判定为满层")
	RogueRun.add_buff("t_cy_cap")
	await get_tree().process_frame
	_check(RogueRun.hunt_cap() == 12, "「煞贯」把上限抬到 12", str(RogueRun.hunt_cap()))
	_check(not RogueRun.hunt_is_full(), "上限抬高后 8/12 不再是满层")

	# ===== 4. 伤害：每层 2%（虎煞）+ 额外 1%（凶性 ×3）= 5%/层 =====
	RogueRun.add_buff("t_cy_dmg")
	RogueRun.add_buff("t_cy_dmg")
	RogueRun.add_buff("t_cy_dmg")
	await get_tree().process_frame
	RogueRun.hunt_stacks = 4
	_check(absf(RogueRun.hunt_dmg_pct() - 20.0) < 0.001,
		"4 层 × 5% = +20% 伤害", "%.1f" % RogueRun.hunt_dmg_pct())

	# ===== 5. 攻速 / 移速：走属性修正与移速乘区 =====
	RogueRun.add_buff("t_cy_aspd")
	RogueRun.hunt_stacks = 0
	RogueRun.rebuild()
	var base_spd := CharacterData.attribute("attack_speed")
	RogueRun.hunt_stacks = 6
	RogueRun.rebuild()
	var now_spd := CharacterData.attribute("attack_speed")
	_check(absf((now_spd - base_spd) - 9.0) < 0.01,
		"噬血 ×1：6 层 = 攻速 +9%", "%.2f → %.2f" % [base_spd, now_spd])

	# ===== 6. 满层翻倍（万兽）=====
	RogueRun.add_buff("t_cy_bloom")
	await get_tree().process_frame
	_check(RogueRun.has_flag("hunt_full_bloom"), "「万兽」打开满层翻倍开关")
	RogueRun.hunt_stacks = 12
	RogueRun.rebuild()
	var full_pct := RogueRun.hunt_dmg_pct()
	_check(absf(full_pct - 120.0) < 0.001, "满层 12 层 × 5% × 2 = +120%",
		"%.1f" % full_pct)
	var full_spd := CharacterData.attribute("attack_speed")
	_check(absf((full_spd - base_spd) - 36.0) < 0.01,
		"满层时攻速也翻倍：12×1.5%×2 = 36%", "%.2f" % (full_spd - base_spd))

	# ===== 7. 进战斗场景：真实击杀叠层 + 满层砍踏地冷却 =====
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.get("player")
	var rogue: Node = arena.get("_rogue")
	_check(player != null and rogue != null, "战斗场景与 RogueArena 已创建")
	if player == null or rogue == null:
		return
	rogue.set_process(false)
	rogue.set_physics_process(false)
	player.set("invincible_timer", 9999.0)
	for raw in (rogue.get("_alive") as Array).duplicate():
		if is_instance_valid(raw):
			(raw as Node).queue_free()
	await get_tree().process_frame

	# 真实伤害出口：100 点物理经虎煞放大
	var dummy := _make_dummy(Vector2(360.0, 60.0))
	await get_tree().process_frame
	RogueRun.hunt_stacks = 0
	var plain := float(player.call("_rogue_modify_damage", 100.0, dummy, "physical_melee", ""))
	RogueRun.hunt_stacks = 4
	var scaled := float(player.call("_rogue_modify_damage", 100.0, dummy, "physical_melee", ""))
	_check(absf(scaled / maxf(plain, 0.001) - 1.2) < 0.01,
		"真实伤害出口吃虎煞：4 层 ×1.2", "%.1f → %.1f" % [plain, scaled])

	# 击杀入口叠层（未满层：只叠一层，不砍冷却）
	RogueRun.hunt_stacks = 0
	var cds: Dictionary = player.get("skill_cooldowns")
	cds["skill_tiger_stomp"] = 12.0
	player.call("_rogue_on_kill")
	_check(RogueRun.hunt_stacks == 1, "击杀入口叠 1 层", str(RogueRun.hunt_stacks))
	_check(absf(float(cds.get("skill_tiger_stomp", 0.0)) - 12.0) < 0.01,
		"未满层不砍踏地冷却", "%.1f" % float(cds.get("skill_tiger_stomp", 0.0)))

	# 满层击杀：踏地冷却 -4 秒
	RogueRun.hunt_stacks = RogueRun.hunt_cap()
	cds["skill_tiger_stomp"] = 12.0
	player.call("_rogue_on_kill")
	_check(absf(float(cds.get("skill_tiger_stomp", 0.0)) - 8.0) < 0.01,
		"满层 + 万兽：踏地冷却 12 → 8", "%.2f" % float(cds.get("skill_tiger_stomp", 0.0)))

	# 没拿「虎煞」的流派不该被击杀叠层污染
	RogueRun.buffs.erase("t_cy_base")
	RogueRun.rebuild()
	RogueRun.hunt_stacks = 0
	player.call("_rogue_on_kill")
	_check(RogueRun.hunt_stacks == 0, "移出「虎煞」后击杀不再叠层")

	# ===== 8. 收局还原 =====
	dummy.queue_free()
	RogueRun.restore()
	RogueRun.family = "sword"
	_check(not RogueRun.active, "收局：active=false")
	_check(RogueRun.hunt_stacks == 0, "收局：虎煞归零")
	_check(not CharacterData.attribute_mods.has("rogue_hunt"), "收局：攻速修正已清除")
	_check(absf(CharacterData.attribute("attack_speed") - spd_before_run) < 0.01,
		"收局：攻速回到进局前的值", "%.2f" % CharacterData.attribute("attack_speed"))
