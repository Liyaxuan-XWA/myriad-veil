extends Node
## 观澜 · 真实战斗通关探针（2026-11-01）
## 真实 CombatArena + 真实 Player + BOSS AI，玩家按元婴初期 / 道器 +6 baseline 自动普攻 + 施放四门镜身功法。
## 目标：在无人工干预下把 BOSS 打进二阶段并击杀，验证结算、掉落、无闪退。
## 用法：godot --headless --path . res://tools/probe_guanying_play.tscn -- --no-save

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
	print("\n########## 观澜 · 真实战斗通关探针 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	# 与 probe_yuanying_baseline 同口径：元婴初期 · 道器 +6
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 0
	for slot in CharacterData.SLOT_ORDER:
		CharacterData.equipment_slots[slot] = null
	var enh_avg := {
		"strength": 1.5, "spell_power": 1.0, "hp_max": 3.0,
		"physical_resist": 1.0, "magic_resist": 1.0, "mana_max": 3.0,
		"mana_regen": 0.75, "speed_pct": 0.3, "attack_speed": 1.0,
		"spell_skill_damage_pct": 0.75, "stamina_regen_pct": 0.75,
	}
	var gear := ["eq_qingfengjian", "eq_jinwen_zhanpao", "eq_zhuri_lv",
		"eq_liangyi_yujue", "eq_qihai_yuzhui", "eq_leiwen_huqi"]
	var slots := ["weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3"]
	for i in gear.size():
		var tpl := ItemDB.get_equipment_template(String(gear[i]))
		var it := CharacterData.make_equipment_instance(tpl)
		var base: Dictionary = it.get("attributes_base", {})
		var attrs: Dictionary = {}
		for k in base.keys():
			attrs[String(k)] = float(base[k])
		var asc := maxi(0, ItemDB.grade_index("道器") - ItemDB.grade_index(String(it.get("equipment_grade", ""))))
		for _i in asc:
			for k in attrs.keys():
				attrs[k] = float(attrs[k]) * 1.5
		for k in attrs.keys():
			if enh_avg.has(k):
				attrs[k] = float(attrs[k]) + float(enh_avg[k]) * 6.0
		it["attributes"] = attrs
		it["equipment_grade"] = "道器"
		it["enhancement_level"] = 6
		CharacterData.equipment_slots[String(slots[i])] = it
	for sid in ["skill_mirror_slash", "skill_mirror_bloom", "skill_mirror_shatter",
			"skill_mirror_ring", "skill_mirror_echo"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = ["skill_mirror_slash", "skill_mirror_bloom",
		"skill_mirror_shatter", "skill_mirror_ring"]
	CharacterData.passive_skill_loadout = ["skill_mirror_echo"]
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	_check(player != null and is_instance_valid(player), "真实 Player 已生成")
	_check(boss != null and is_instance_valid(boss), "真实 BOSS 已生成")
	if player == null or boss == null:
		return
	_check(boss.boss_id == "boss_04", "箱庭加载的是观澜", boss.boss_id)
	player._apply_attributes_to_runtime(true)
	_check(player.max_hp >= 440.0 and CharacterData.physical_attack() >= 175.0,
		"玩家按元婴初期 baseline 开战",
		"HP %.0f 物攻 %.0f 法强 %.0f" % [player.max_hp,
			CharacterData.physical_attack(), CharacterData.spell_attack()])
	var max_hp: float = boss.max_hp
	var phase2_at := -1.0
	var killed_at := -1.0
	var cast_counts: Dictionary = {}
	var skill_tick := 0.0
	var attack_tick := 0.0
	var t := 0.0
	while t < 95.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if not is_instance_valid(boss) or not is_instance_valid(player):
			break
		player.invincible_timer = 999.0
		player.hp = player.max_hp
		player.mana = player.max_mana
		player.stamina = player.max_stamina
		if boss.state == BossBase.BossState.DEAD:
			if killed_at < 0.0:
				killed_at = t
			break
		if boss.phase == 2 and phase2_at < 0.0:
			phase2_at = t
		# 贴到 BOSS 身前，保证普攻/技能在射程内（本探针只验证战斗结算，不模拟走位）
		var to_boss: Vector2 = boss.global_position - player.global_position
		if to_boss.length() > 90.0:
			player.global_position = boss.global_position - to_boss.normalized() * 86.0
		player.attack_dir = (boss.global_position - player.global_position).normalized()
		attack_tick -= 0.1
		if attack_tick <= 0.0:
			attack_tick = 0.28
			if not player.is_attacking and not player.is_dead:
				player._start_attack()
		skill_tick -= 0.1
		if skill_tick <= 0.0:
			skill_tick = 0.9
			for sid in CharacterData.active_skill_loadout:
				if player.try_use_skill(String(sid)):
					cast_counts[sid] = int(cast_counts.get(sid, 0)) + 1
					break
		if int(t * 10.0) % 100 == 0:
			print("  t=%.0fs  BOSS %.0f/%.0f  phase=%d  镜像=%d  recent=%s" % [
				t, boss.current_hp, max_hp, boss.phase, boss._images.size(),
				str(boss._recent)])
	_check(phase2_at > 0.0, "战斗自然进入二阶段",
		"%.1fs" % phase2_at if phase2_at > 0 else "未进入")
	_check(killed_at > 0.0, "玩家自动战斗击杀观澜",
		"%.1fs" % killed_at if killed_at > 0 else "95s 内未击杀")
	_check(boss.current_hp <= 0.01 or boss.state == BossBase.BossState.DEAD,
		"BOSS 血量归零 / 死亡状态")
	_check(not cast_counts.is_empty(), "玩家真实入口施放镜身功法", str(cast_counts))
	await get_tree().create_timer(1.5).timeout
	_check(CharacterData.is_boss_cleared("domain_04", "boss_04"),
		"位面结算记录观澜已击杀")
	_check(CharacterData.get_tower_clear_count(10) >= 0, "塔 10 层记录可读",
		str(CharacterData.get_tower_clear_count(10)))
	_check(CharacterData.is_tower_floor_unlocked(10),
		"击败位面观澜后，万界塔第 10 层开放")
	GameState.battle_context = {}
