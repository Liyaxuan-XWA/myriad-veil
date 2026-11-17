extends Node
## 试炼之路 · 刀修（刀痕流派）自检（2026-11-08）
## 覆盖：刀修开局功法、卡池按流派过滤、刀痕上限 / 留存 / 重痕 / 连斩伤害、
##       纳势蓄力上限与格挡减伤、满势断岳激活处数、定势受击不掉精力、
##       血刃低血增伤、血怒残血上限翻倍、踏痕 / 急血移速、饮痕回血、收局还原。
## 用法：godot --headless --path . res://tools/probe_rogue_scar.tscn -- --no-save

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


## 造一个不会自己动、不会还手的靶子（用来量刀痕伤害）
func _make_dummy(pos: Vector2) -> WorldEnemy:
	var packed := load(MINION_SCENE) as PackedScene
	var e := packed.instantiate() as WorldEnemy
	var cfg := {
		"pos": pos,
		"max_hp": 100000.0,
		"attack_power": 1.0,
		"move_speed": 1.0,
		"visual_id": "rogue_rat",
		"aggro_range": 1.0,
		"leash_range": 1.0,
		"melee_range": 1.0,
		"melee_angle": 1.0,
		"melee_coeff": 0.0,
		"body_radius": 20.0,
		"attack_name": "不动",
		"skills": [],
		"cast_coeff": 0.0,
	}
	e.position = pos
	e.configure(cfg, WorldEnemy.KIND_BEAST, "木桩")
	add_child(e)
	return e


func _run() -> void:
	print("\n########## 试炼之路 · 刀修 ##########")
	await get_tree().process_frame

	# ===== 1. 刀修开局 =====
	RogueRun.start_run("scar")
	await get_tree().process_frame
	_check(RogueRun.active and RogueRun.family == "scar", "开局：本局流派=刀修", RogueRun.family)
	var loadout: Array = CharacterData.active_skill_loadout
	_check(loadout.size() == 4, "4 个主动槽", str(loadout))
	var all_blade := true
	for sid in loadout:
		if not String(sid).begins_with("skill_blade_"):
			all_blade = false
	_check(all_blade, "开局四式全是刀修功法", str(loadout))
	_check(CharacterData.passive_skill_loadout.is_empty(), "刀修没有被动功法（空槽）")
	_check(CharacterData.learned_skills.has("skill_blade_peak"), "满势断岳已习得（暂不装配）")

	# ===== 2. 卡池按本局流派过滤 =====
	var sword_leak := 0
	var scar_seen := 0
	for i in 60:
		for raw in RogueRun.roll_choices(3, i % 2 == 0):
			var bid := String((raw as Dictionary).get("id", ""))
			if bid.begins_with("s_"):
				sword_leak += 1
			elif bid.begins_with("b_"):
				scar_seen += 1
	_check(sword_leak == 0, "剑修卡不会混进刀修局", "泄漏 %d 张" % sword_leak)
	_check(scar_seen > 0, "刀修卡能正常抽到", "出现 %d 次" % scar_seen)

	# ===== 3. 招式覆盖（纯数据，不需要场景）=====
	_check(is_equal_approx(float(MoveDB.resolve_player("form_blade_counter").get("charge_max", 0.0)), 5.0),
		"纳势蓄力上限基值 5")
	RogueRun.add_buff("b_pk_charge")
	_check(is_equal_approx(float(MoveDB.resolve_player("form_blade_counter").get("charge_max", 0.0)), 8.0),
		"蓄势：蓄力上限 8（加算不是乘算）",
		"%.1f" % float(MoveDB.resolve_player("form_blade_counter").get("charge_max", 0.0)))
	_check(is_equal_approx(float(MoveDB.resolve_player("form_blade_peak").get("scar_ignite_max", 0.0)), 3.0),
		"满势断岳激活处数基值 3")
	RogueRun.add_buff("b_pk_pierce")
	_check(is_equal_approx(float(MoveDB.resolve_player("form_blade_peak").get("scar_ignite_max", 0.0)), 5.0),
		"断岳·裂：沿途多激活 2 处 = 5")

	# ===== 4. 进战斗场景取玩家 =====
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
	# 冻结刷怪机并清场：后面要自己摆木桩量伤害，不能让小怪插进来
	rogue.set_process(false)
	rogue.set_physics_process(false)
	player.set("invincible_timer", 9999.0)
	for raw in (rogue.get("_alive") as Array).duplicate():
		if is_instance_valid(raw):
			(raw as Node).queue_free()
	await get_tree().process_frame

	# ===== 5. 刀痕场上限 / 留存 / 重痕 =====
	var field := ScarField.ensure()
	_check(field != null, "刀痕场可按需创建")
	if field == null:
		return
	_check(int(field.call("_max_normal")) == 4, "刀痕上限基值 4")
	RogueRun.add_buff("b_sp_cap")
	_check(int(field.call("_max_normal")) == 6, "拓痕：上限 6", str(int(field.call("_max_normal"))))

	RogueRun.add_buff("b_sp_life")
	field.clear_all()
	var scar: BladeScar = field.spawn_scar(Vector2(900.0, 0.0), BladeScar.SIDE_PLAYER,
		10.0, 1.0, null, "physical", player)
	var life_ok := scar != null and absf(scar.life - (BladeScar.SCAR_LIFE + 4.0)) < 0.01
	_check(life_ok, "余烬：刀痕留存 14 秒",
		"%.1f" % (scar.life if scar != null else -1.0))

	RogueRun.add_buff("b_sp_extra")
	field.clear_all()
	await get_tree().process_frame
	var scar_form: Dictionary = MoveDB.resolve_player("form_blade_scar")
	player.call("_apply_scar_effect", scar_form, Vector2.RIGHT)
	_check(field.normal_count() == 2, "重痕：一次留 2 道刀痕", str(field.normal_count()))

	# ===== 6. 连斩：刀痕斩击伤害 ×1.2（拿木桩量真实掉血）=====
	field.clear_all()
	await get_tree().process_frame
	var d1 := _make_dummy(Vector2(400.0, 60.0))
	await get_tree().process_frame
	# ⚠ 小怪 _ready 会把位置钳进战场边界，必须读它「落位之后」的坐标再放刀痕
	var pos1: Vector2 = d1.global_position
	var hp1 := float(d1.get("current_hp"))
	field.spawn_scar(pos1, BladeScar.SIDE_PLAYER, 40.0, 1.0, null, "physical", player)
	await get_tree().process_frame
	var ignited := field.ignite_in_radius(pos1, 60.0, 5, BladeScar.SIDE_PLAYER, player)
	var loss1 := hp1 - float(d1.get("current_hp"))
	d1.queue_free()
	await get_tree().process_frame
	RogueRun.add_buff("b_sp_mult")
	var d2 := _make_dummy(Vector2(400.0, 60.0))
	await get_tree().process_frame
	var pos2: Vector2 = d2.global_position
	var hp2 := float(d2.get("current_hp"))
	field.spawn_scar(pos2, BladeScar.SIDE_PLAYER, 40.0, 1.0, null, "physical", player)
	await get_tree().process_frame
	field.ignite_in_radius(pos2, 60.0, 5, BladeScar.SIDE_PLAYER, player)
	var loss2 := hp2 - float(d2.get("current_hp"))
	d2.queue_free()
	_check(ignited == 1 and loss1 > 0.0, "刀痕能引爆并造成伤害", "%.2f" % loss1)
	_check(loss1 > 0.0 and absf(loss2 / maxf(loss1, 0.001) - 1.2) < 0.02,
		"连斩：刀痕斩击 ×1.2", "%.2f → %.2f" % [loss1, loss2])

	# ===== 7. 断岳流：格挡减伤 / 蓄力上限 / 满势条数 =====
	var counter_form: Dictionary = MoveDB.resolve_player("form_blade_counter")
	RogueRun.add_buff("b_pk_block")
	player.call("_begin_counter_charge", "skill_blade_counter", counter_form, Vector2.RIGHT, 8.0)
	var block := float(player.get("_counter_block"))
	_check(absf(block - 0.805) < 0.001, "铁壁：格挡减伤 0.7 → 0.805", "%.3f" % block)
	_check(is_equal_approx(float(player.get("_counter_max")), 8.0), "蓄势：进战时读到的上限是 8",
		"%.1f" % float(player.get("_counter_max")))
	player.call("_finish_counter_ward")
	player.set("_counter_charging", false)

	# ===== 8. 定势：蓄力受击不掉精力 =====
	RogueRun.add_buff("b_pk_stamina")
	player.set("stamina", 5)
	player.set("_counter_charging", true)
	player.set("invincible_timer", 0.0)
	var hp_before_hit := float(player.get("hp"))
	player.call("take_damage", 3.0, "physical_melee", null, "")
	_check(int(player.get("stamina")) == 5, "定势：蓄力期间受击不掉精力",
		"精力 %d" % int(player.get("stamina")))
	_check(float(player.get("hp")) < hp_before_hit, "（对照）这一下确实掉了血")
	player.set("_counter_charging", false)
	player.set("stamina", 5)
	player.set("invincible_timer", 0.0)
	player.call("take_damage", 3.0, "physical_melee", null, "")
	_check(int(player.get("stamina")) == 4, "非蓄力受击照常 -1 精力",
		"精力 %d" % int(player.get("stamina")))

	# ===== 9. 血刀流：血刃 / 血怒 / 急血 =====
	player.set("_rogue_scale_left", 0.0)
	player.set("_rogue_step_ready", false)
	player.set("hp", float(player.get("max_hp")))
	var base_dmg := float(player.call("_rogue_modify_damage", 100.0, null, "physical_melee", ""))
	RogueRun.add_buff("b_bd_low")
	player.set("hp", float(player.get("max_hp")) * 0.5)
	var low_dmg := float(player.call("_rogue_modify_damage", 100.0, null, "physical_melee", ""))
	_check(absf(low_dmg / maxf(base_dmg, 0.001) - 1.3) < 0.01, "血刃：半血物理 ×1.3",
		"%.1f → %.1f" % [base_dmg, low_dmg])
	var half_spell := float(player.call("_rogue_modify_damage", 100.0, null, "elemental", ""))
	_check(absf(half_spell / maxf(base_dmg, 0.001) - 1.0) < 0.01, "血刃只加物理，法术不变",
		"%.1f" % half_spell)

	RogueRun.add_buff("b_bd_cap")
	player.set("hp", float(player.get("max_hp")) * 0.2)
	_check(int(field.call("_max_normal")) == 12, "血怒：残血时上限翻倍 6→12",
		str(int(field.call("_max_normal"))))
	player.set("hp", float(player.get("max_hp")) * 0.5)
	_check(int(field.call("_max_normal")) == 6, "血怒：回到半血即恢复 6")

	RogueRun.add_buff("b_bd_move")
	player.set("hp", float(player.get("max_hp")) * 0.2)
	var move_low := float(player.call("_rogue_move_mult"))
	_check(absf(move_low - 1.08) < 0.01, "急血：残血移速 ×1.08", "%.3f" % move_low)
	RogueRun.add_buff("b_bd_move")
	RogueRun.add_buff("b_bd_move")
	RogueRun.add_buff("b_bd_move")
	_check(RogueRun.buff_stacks("b_bd_move") == 3, "急血叠层封顶 3")

	# ===== 10. 踏痕：场上有刀痕时再 +8% =====
	RogueRun.add_buff("b_sp_move")
	field.clear_all()
	player.set("hp", float(player.get("max_hp")) * 0.2)
	var move_no_scar := float(player.call("_rogue_move_mult"))
	field.spawn_scar(Vector2(800.0, 0.0), BladeScar.SIDE_PLAYER, 10.0, 1.0, null, "physical", player)
	var move_with_scar := float(player.call("_rogue_move_mult"))
	_check(absf(move_no_scar - 1.24) < 0.01, "残血 + 三叠急血 = ×1.24", "%.3f" % move_no_scar)
	_check(absf(move_with_scar / maxf(move_no_scar, 0.001) - 1.08) < 0.01, "踏痕：有痕时再 ×1.08",
		"%.3f" % move_with_scar)

	# ===== 11. 饮痕：刀痕斩击命中回血 =====
	RogueRun.add_buff("b_bd_heal")
	player.set("hp", float(player.get("max_hp")) * 0.5)
	var d3 := _make_dummy(Vector2(400.0, 60.0))
	await get_tree().process_frame
	var pos3: Vector2 = d3.global_position
	var hp_before_heal := float(player.get("hp"))
	field.clear_all()
	field.spawn_scar(pos3, BladeScar.SIDE_PLAYER, 20.0, 1.0, null, "physical", player)
	await get_tree().process_frame
	field.ignite_in_radius(pos3, 60.0, 5, BladeScar.SIDE_PLAYER, player)
	var healed := float(player.get("hp")) - hp_before_heal
	var expect_heal := float(player.get("max_hp")) * 0.02
	_check(absf(healed - expect_heal) < 0.05, "饮痕：命中回 2% 气血",
		"%.2f / 期望 %.2f" % [healed, expect_heal])
	d3.queue_free()

	# ===== 12. 收局还原 =====
	RogueRun.restore()
	RogueRun.family = "sword"
	_check(not RogueRun.active, "收局：active=false")
	_check(CharacterData.active_skill_loadout.is_empty() or
		not String(CharacterData.active_skill_loadout[0]).begins_with("skill_blade_"),
		"收局：刀修功法已从存档数据里退出", str(CharacterData.active_skill_loadout))
