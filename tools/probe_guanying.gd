extends Node
## 观澜 · 镜身照影全链路探针（2026-11-01）
## 覆盖：数据 / 场景 / 八式 / 二阶段 / 镜像 / 换镜暴露 / 镜返 / 水镜环 /
##       首战空手破镜 / 玩家侧完整继承 / 图鉴 / 掉落 / 塔 10 层 / 无势条无叠爆。
## 用法：godot --headless --path . res://tools/probe_guanying.tscn

var _passes := 0
var _fails: Array = []

## 与 tools/probe_yuanying_baseline.gd 同一套「元婴初期 · 道器 +6」：真穿装备，
## 不靠临时属性补丁，这样掉落 / 强化 / 法器都走真实属性入口。
const ENH_AVG := {
	"strength": 1.5, "spell_power": 1.0, "hp_max": 3.0,
	"physical_resist": 1.0, "magic_resist": 1.0, "mana_max": 3.0,
	"mana_regen": 0.75, "speed_pct": 0.3, "attack_speed": 1.0,
	"spell_skill_damage_pct": 0.75, "stamina_regen_pct": 0.75,
}
const BASELINE_GEAR := ["eq_qingfengjian", "eq_jinwen_zhanpao", "eq_zhuri_lv",
	"eq_liangyi_yujue", "eq_qihai_yuzhui", "eq_leiwen_huqi"]


func _mk_gear(id: String, grade: String, enh: int) -> Dictionary:
	var tpl := ItemDB.get_equipment_template(id)
	var it := CharacterData.make_equipment_instance(tpl)
	var asc := maxi(0, ItemDB.grade_index(grade) - ItemDB.grade_index(String(it.get("equipment_grade", ""))))
	var attrs: Dictionary = {}
	var base = it.get("attributes_base", {})
	for k in base.keys():
		attrs[String(k)] = float(base[k])
	for i in asc:
		for k in attrs.keys():
			attrs[k] = float(attrs[k]) * 1.5
	for k in attrs.keys():
		if ENH_AVG.has(k):
			attrs[k] = float(attrs[k]) + float(ENH_AVG[k]) * float(enh)
	it["attributes"] = attrs
	it["equipment_grade"] = grade
	it["enhancement_level"] = enh
	return it


func _wear_baseline(stage: int, enh: int) -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = stage
	for slot in CharacterData.SLOT_ORDER:
		CharacterData.equipment_slots[slot] = null
	var slots := ["weapon", "armor", "shoes", "accessory_1", "accessory_2", "accessory_3"]
	for i in BASELINE_GEAR.size():
		CharacterData.equipment_slots[slots[i]] = _mk_gear(String(BASELINE_GEAR[i]), "道器", enh)


func _count_projectiles(host: Node, sid: String) -> int:
	var n := 0
	for c in host.get_children():
		if c.get("skill_id") != null and String(c.get("skill_id")) == sid \
				and c.get("damage") != null and float(c.get("damage")) > 0.0:
			n += 1
	return n


func _count_rings(host: Node) -> int:
	var n := 0
	for c in host.get_children():
		if c is MirrorRingField:
			n += 1
	return n


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _clear_images(boss: Node) -> void:
	for raw in boss.get("_images"):
		if is_instance_valid(raw):
			raw.queue_free()
	boss.get("_images").clear()


func _clear_rings(host: Node) -> void:
	for child in host.get_children():
		if child is MirrorRingField:
			child.queue_free()


func _ready() -> void:
	print("\n########## 观澜 · 镜身照影全链路探针 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	# ===== 1. 位面 / 塔 / 场景 =====
	var dom := WorldDB.get_domain("domain_04")
	_check(not dom.is_empty(), "照影界已登记", str(dom.get("name", "")))
	_check(String(dom.get("prev_domain", "")) == "domain_03", "照影界接在赤霄界之后")
	# 首位 = 观澜；照影界后面还可以有第 2/3 位（boss_04_b 等），本探针只守自己那一份
	var dom_bosses: Array = dom.get("boss_ids", [])
	_check(not dom_bosses.is_empty() and String(dom_bosses[0]) == "boss_04",
		"照影界首位 = boss_04", str(dom_bosses))
	_check(WorldDB.get_boss_name("boss_04") == "观澜", "BOSS 名 = 观澜")
	_check(WorldDB.get_boss_scene("boss_04") == "res://scenes/boss/domain_boss_04.tscn",
		"BOSS 场景已登记")
	_check(ResourceLoader.exists(WorldDB.get_boss_scene("boss_04")), "BOSS 场景文件存在")
	_check(WorldDB.get_floors().size() >= 10, "万界塔至少 10 层",
		"n=%d" % WorldDB.get_floors().size())
	_check(String(WorldDB.get_floor(10).get("boss_id", "")) == "boss_04", "第 10 层 = 观澜")
	_check(WorldDB.get_floor_reward_skills(10).size() == 9, "第 10 层感悟池 = 9 门",
		"n=%d" % WorldDB.get_floor_reward_skills(10).size())

	# ===== 2. 招式 / 功法 / 术语 =====
	var forms := WorldDB.get_boss_form_ids("boss_04")
	_check(forms.size() == 8, "观澜八式已登记", str(forms))
	var learned := WorldDB.get_boss_skill_ids("boss_04")
	_check(learned.size() == 9, "功法库 = 8 主动 + 1 被动", "n=%d" % learned.size())
	var mirror_actives := 0
	var mirror_passive := 0
	for sid in learned:
		var sk := SkillDB.get_skill(String(sid))
		if String(sk.get("source_boss_id", "")) != "boss_04":
			continue
		if bool(sk.get("mirror", false)):
			if String(sk.get("skill_type", "")) == SkillDB.TYPE_ACTIVE:
				mirror_actives += 1
			else:
				mirror_passive += 1
		var txt := SkillDB.get_effect_text(String(sid))
		if String(sk.get("skill_type", "")) == SkillDB.TYPE_ACTIVE:
			_check(txt != "", "功法有现算效果文案：%s" % sid)
	_check(mirror_actives == 8, "玩家主动八式均带 mirror 标记", "n=%d" % mirror_actives)
	_check(mirror_passive == 1, "被动照影已登记")
	var rules := SkillDB.get_group_rules("boss_04")
	_check(String(rules.get("title", "")).begins_with("镜身"), "功法库组规则 = 镜身",
		String(rules.get("title", "")))
	var rules_text := SkillDB.group_rules_text(rules)
	_check(rules_text.contains("镜像") and rules_text.contains("镜返") and rules_text.contains("镜滞"),
		"组规则讲清镜像 / 镜返 / 镜滞")
	_check(rules_text.contains("50%") and rules_text.contains("1.2"), "组规则数值来自常量",
		rules_text.substr(0, 60))
	var wujiu_group := SkillDB.group_rules_text(SkillDB.get_group_rules("boss_03_c"))
	_check(not wujiu_group.contains("镜身"), "镜身没有串到上一组")
	# 无势条 / 无叠层 / 无引爆
	var bad_terms := ["momentum", "stacks", "detonate", "势条", "满层爆"]
	var has_bad := false
	for fid in forms:
		var f := MoveDB.get_form(String(fid))
		for term in bad_terms:
			if f.has(term):
				has_bad = true
		for sub in ["player", "boss"]:
			var d: Dictionary = f.get(sub, {})
			for term in bad_terms:
				if d.has(term):
					has_bad = true
	_check(not has_bad, "招式表没有势条 / 叠层 / 引爆字段")
	_check(not SkillDB.get_skill("skill_mirror_echo").has("mirror_stacks"),
		"被动照影没有层数字段")

	# ===== 3. 美术 / 掉落 / 图鉴 =====
	var vis := ArtDB.get_visual("boss_guanying")
	_check(not vis.is_empty(), "ArtDB 已登记 boss_guanying")
	_check(FileAccess.file_exists("res://assets/characters/boss/boss_guanying.png"),
		"观澜全身图存在")
	_check(FileAccess.file_exists("res://assets/characters/boss/guanying_rig/rig.tres"),
		"观澜 rig 存在")
	_check(FileAccess.file_exists("res://assets/characters/boss/guanying_rig/body.png")
		and FileAccess.file_exists("res://assets/characters/boss/guanying_rig/mirror.png"),
		"观澜 rig 两件贴图存在")
	_check(FileAccess.file_exists("res://assets/scenes/zhaoying_arena_ground.png"),
		"照影界地面存在")
	_check(FileAccess.file_exists("res://assets/effects/skills/mirror_seal.png"),
		"镜印地贴存在")
	_check(FileAccess.file_exists("res://assets/ui/codex/card_boss_guanying.png"),
		"卡面原图存在")
	for sid in learned:
		var sk2 := SkillDB.get_skill(String(sid))
		var ip := String(sk2.get("icon", ""))
		_check(ip != "" and FileAccess.file_exists(ip), "功法图标存在：%s" % sid, ip)
	for iid in ["equip_jingtan_chi", "eq_shuiyue_pao", "mat_zhaoying_jingsha",
			"soul_guanying", "tr_guanying_ling"]:
		var path := ""
		if iid == "equip_jingtan_chi":
			path = "res://assets/ui/icon/%s.png" % iid
		else:
			var it: Dictionary = ItemDB.get_equipment_template(iid)
			if it.is_empty():
				it = ItemDB.get_material(iid)
			if it.is_empty():
				it = ItemDB.get_treasure_template(iid)
			path = String(it.get("icon", ""))
		_check(path != "" and FileAccess.file_exists(path), "物品图标存在：%s" % iid, path)
	_check(FileAccess.file_exists("res://assets/effects/weapons/jingtan_chi.png"),
		"镜潭尺局内贴图存在")
	# art_db 的 SKILL_FX 八式
	for sid in ["skill_mirror_slash", "skill_mirror_thrust", "skill_mirror_bloom",
			"skill_mirror_shatter", "skill_mirror_swap", "skill_mirror_return",
			"skill_mirror_ring", "skill_mirror_myriad"]:
		var cfg := ArtDB.get_skill_fx(sid)
		_check(not cfg.is_empty() and String(cfg.get("motif", "")) == "mirror",
			"镜水特效配置：%s" % sid)

	var drops: Array = ItemDB.get_drops_for_boss("boss_04")
	_check(drops.size() == 3, "观澜掉落 = 2 装 + 1 材料", "n=%d" % drops.size())
	var has_mat := false
	for d in drops:
		if String((d as Dictionary).get("item_id", "")) == "mat_zhaoying_jingsha":
			has_mat = true
			_check(absf(float(d.get("chance", 1.0)) - 0.2) < 0.001, "位面材料 20% 掉落")
	_check(has_mat, "掉落表含照影镜砂")
	_check(not ItemDB.get_equipment_template("eq_jingtan_chi").is_empty(), "镜潭尺已登记")
	_check(not ItemDB.get_equipment_template("eq_shuiyue_pao").is_empty(), "水月袍已登记")
	_check(not ItemDB.get_treasure_template("tr_guanying_ling").is_empty(), "镜主令已登记")
	_check(not ItemDB.get_synth_recipe_by_soul("soul_guanying").is_empty(),
		"观澜元魂 → 镜主令配方存在")
	var codex: Dictionary = CodexDB.BOSS_CODEX.get("boss_04", {})
	_check(not codex.is_empty(), "BOSS 图鉴已登记")
	_check(String(codex.get("mechanic_title", "")) == "镜身 · 照影", "图鉴机制标题")
	_check(String(codex.get("mechanic", "")).contains("倒影")
		and String(codex.get("mechanic", "")).contains("镜像"), "图鉴讲清真假镜身")
	_check(Array(codex.get("status_extra", [])).size() >= 1, "图鉴登记镜滞状态")
	var sources: Dictionary = CodexDB.SOURCES
	_check(sources.has("mat_zhaoying_jingsha") and sources.has("soul_guanying")
		and sources.has("tr_guanying_ling"), "图鉴获取方式已登记")

	# ===== 4. 场景 / 真实箱庭 =====
	for sid in learned:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = []
	for sid in learned:
		if String(SkillDB.get_skill(String(sid)).get("skill_type", "")) == SkillDB.TYPE_ACTIVE:
			CharacterData.active_skill_loadout.append(sid)
	CharacterData.passive_skill_loadout = ["skill_mirror_echo"]
	_wear_baseline(0, 6)
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
	_check(boss is DomainBoss04, "BOSS 使用 DomainBoss04")
	_check(boss.max_hp == 40000.0 and boss.attack_power == 180.0,
		"BOSS 数值 = 40000 / 180（元婴后期 TTK 约 50s）",
		"hp=%.0f atk=%.0f" % [boss.max_hp, boss.attack_power])
	_check(is_equal_approx(boss.magic_resist, 100.0), "BOSS 法抗 = 100（减伤 50%）",
		"法抗 %.0f" % boss.magic_resist)
	_check(boss._reflection != null and is_instance_valid(boss._reflection),
		"真身脚下倒影已生成")
	player._apply_attributes_to_runtime(true)
	_check(player.max_hp >= 440.0 and CharacterData.physical_attack() >= 175.0
		and CharacterData.spell_attack() >= 145.0,
		"元婴初期 · 道器 +6 baseline 已穿上",
		"HP %.0f 物攻 %.0f 法强 %.0f" % [player.max_hp,
			CharacterData.physical_attack(), CharacterData.spell_attack()])
	player.global_position = boss.global_position + Vector2(0.0, 130.0)
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	print("  玩家面板：HP %.0f · 物攻 %.0f · 法强 %.0f · 物抗 %.0f · 法抗 %.0f" % [
		player.max_hp, CharacterData.physical_attack(), CharacterData.spell_attack(),
		CharacterData.attribute(AttributeDB.ATTR_PHYSICAL_RESIST),
		CharacterData.attribute(AttributeDB.ATTR_MAGIC_RESIST)])

	# ===== 5. BOSS AI：镜像 / 八式 / 无空放 =====
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	var t := 0.0
	while t < 4.5:
		await _wait(0.1)
		t += 0.1
		if not is_instance_valid(boss):
			break
		player.invincible_timer = 999.0
		player.hp = player.max_hp
	_check(boss._recent.size() >= 2, "BOSS AI 在真实箱庭出招 >=2", str(boss._recent))
	_check(boss._images.size() >= 1, "BOSS AI 主动召出镜像", "n=%d" % boss._images.size())
	# AI 行为已验证；后面直接调招式验证机制，关掉 BOSS 的帧循环，
	# 否则它会在玩家站桩测试时继续普攻/放招，命中无敌帧把镜滞刷新挡掉。
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.state = BossBase.BossState.IDLE
	var used := {}
	for sid in boss._recent:
		used[String(sid)] = true
	for f in ["form_mirror_slash", "form_mirror_thrust", "form_mirror_bloom",
			"form_mirror_shatter", "form_mirror_ring", "form_mirror_swap",
			"form_mirror_return", "form_mirror_myriad"]:
		if used.has(f):
			print("  AI 用过 ", f)
	# 没有镜像时不可碎镜 / 换镜
	_clear_images(boss)
	_check(not boss._in_reach("form_mirror_shatter"), "无镜像时碎镜不在可选用范围")
	# 一阶段不会万镜归一
	_check(boss.phase == 1, "一阶段尚未转阶段")
	var old_state: int = boss.state
	boss.state = BossBase.BossState.IDLE
	boss._decide_wait = 0.0
	boss._cools.clear()
	boss._choose()
	var first_pick: String = String(boss._current_skill)
	_check(first_pick != "form_mirror_myriad", "一阶段不会选万镜归一", first_pick)
	boss.state = old_state

	# ===== 5b. 物理招式必须可弹反 =====
	_clear_images(boss)
	for n in get_tree().get_nodes_in_group("mirror_image"):
		if n is MirrorImage and not bool(n.get("is_ally")):
			n.queue_free()
	await _wait(0.2)
	boss.target = player
	boss._set_facing((player.global_position - boss.global_position).normalized())
	player.global_position = boss.global_position + Vector2(0.0, 60.0)
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0
	player.hp = player.max_hp
	player.is_parrying = false
	player.parry_cooldown_timer = 0.0
	player.stamina = player.max_stamina
	player._start_parry()
	var hp_parry: float = player.hp
	boss._cast_slash(MoveDB.resolve_boss("form_mirror_slash"))
	await _wait(0.05)
	_check(absf(player.hp - hp_parry) < 0.01, "镜水斩可被弹反",
		"hp %.0f" % player.hp)
	player._end_parry()
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	# ===== 6. 镜像 1 击碎 / 空手可破 =====
	var img: MirrorImage = boss._spawn_image(0)
	await _wait(0.1)
	_check(img != null and is_instance_valid(img), "BOSS 镜像已生成")
	_check(not img.is_in_group("ally_summon"), "BOSS 镜像不在友军组")
	_check(img.has_method("hit_spheres") and img.hit_radius() > 0.0, "镜像可被命中")
	var img_hp: float = img.unit_hp()
	if not boss._images.has(img):
		boss._images.append(img)
	img.take_damage(1.0, player, "physical", "")
	await _wait(0.05)
	_check(not is_instance_valid(img) or bool(img.get("_dead")), "任意 1 点命中即碎镜",
		"hp %.0f" % img_hp)
	# 空手：玩家不学任何观澜功法也能打真身 / 碎镜
	var hp_before_bare: float = boss.current_hp
	boss.take_damage(50.0, player, "physical", "")
	_check(boss.current_hp < hp_before_bare, "空手物理打真身有效",
		"%.0f -> %.0f" % [hp_before_bare, boss.current_hp])
	var img2: MirrorImage = boss._spawn_image(1)
	await _wait(0.05)
	img2.take_damage(1.0, player, "elemental", "")
	await _wait(0.05)
	_check(is_instance_valid(img2) and not bool(img2.get("_dead")),
		"法术命中镜像不会碎镜（法免）")
	img2.take_damage(1.0, player, "physical", "")
	_check(not is_instance_valid(img2) or bool(img2.get("_dead")),
		"法免镜像仍可被物理打碎")

	# ===== 6b. 镜像要会走位，不能当静态贴图 =====
	_clear_images(boss)
	player.global_position = boss.global_position + Vector2(0.0, 130.0)
	var mover: MirrorImage = boss._spawn_image(0)
	_check(mover.get_node_or_null("FakeHPBar") != null, "BOSS 镜像头顶有同款假血条")
	var spawn_dist: float = mover.global_position.distance_to(player.global_position)
	_check(spawn_dist > 60.0 and spawn_dist < 170.0,
		"BOSS 镜像从玩家四周站起", "%.0fpx" % spawn_dist)
	var mover_from: Vector2 = mover.global_position
	await _wait(0.9)
	_check(mover != null and is_instance_valid(mover)
		and mover.global_position.distance_to(mover_from) > 8.0,
		"BOSS 镜像会自己走位",
		"%.1fpx" % mover.global_position.distance_to(mover_from))
	_clear_images(boss)
	_clear_rings(player.get_parent())
	# 镜像复读本体招式：玩家站到 BOSS 射程外，只有玩家四周的镜像这一下能打到
	player.global_position = boss.global_position + Vector2(350.0, 0.0)
	var mimic_img: MirrorImage = boss._spawn_image(0)
	await _wait(0.08)
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0
	player.is_parrying = false
	player.hp = player.max_hp
	var hp_before_mimic: float = player.hp
	boss._cast_slash(MoveDB.resolve_boss("form_mirror_slash"))
	await _wait(0.08)
	_check(player.hp < hp_before_mimic, "镜像会复读本体招式（镜水斩）",
		"%.0f -> %.0f" % [hp_before_mimic, player.hp])
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	_clear_images(boss)
	_clear_rings(player.get_parent())

	# ===== 7. 换镜暴露 / 镜返 / 水镜环 / 碎镜 =====
	_clear_images(boss)
	var img3: MirrorImage = boss._spawn_image(0)
	await _wait(0.05)
	var pos_before: Vector2 = boss.global_position
	boss._cast_swap(MoveDB.resolve_boss("form_mirror_swap"))
	_check(boss.global_position.distance_to(pos_before) > 20.0, "换镜后真身位置改变",
		"%.0f -> %.0f" % [pos_before.length(), boss.global_position.length()])
	_check(boss._exposed_left > 0.0, "换镜后真身暴露")
	_check(absf(boss.damage_taken_multiplier("physical") - 1.2) < 0.001,
		"暴露期间受伤 +20%")
	var exposed_hp: float = boss.current_hp
	boss.take_damage(100.0, player, "physical", "")
	_check(boss.current_hp < exposed_hp, "暴露窗口可打真身")
	boss._exposed_left = 0.0
	# 镜返：一次物理伤害被挡并反弹
	boss._return_left = 1.2
	var boss_hp_before: float = boss.current_hp
	var player_hp_before: float = player.hp
	player.invincible_timer = 0.0
	boss.take_damage(80.0, player, "physical", "")
	_check(boss.current_hp >= boss_hp_before - 0.01, "镜返挡下这次物理伤害",
		"boss %.0f -> %.0f" % [boss_hp_before, boss.current_hp])
	_check(player.hp < player_hp_before, "镜返把伤害奉还给玩家",
		"player %.0f -> %.0f" % [player_hp_before, player.hp])
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	# 物理投射物也要吃镜返：player_projectile 把 projectile 当 source，真正攻击者在 source 字段
	var proj: Node = (load("res://scenes/combat/player_projectile.tscn") as PackedScene).instantiate()
	proj.set("source", player)
	arena.add_child(proj)
	proj.set_physics_process(false)
	proj.set_process(false)
	boss._return_left = 1.2
	var bhp2: float = boss.current_hp
	var php2: float = player.hp
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0
	boss.take_damage(70.0, proj, "physical", "", true)
	_check(boss.current_hp >= bhp2 - 0.01, "镜返也挡物理投射物",
		"boss %.0f -> %.0f" % [bhp2, boss.current_hp])
	_check(player.hp < php2, "投射物镜返同样奉还玩家",
		"player %.0f -> %.0f" % [php2, player.hp])
	proj.queue_free()
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	boss._cools.clear()
	# 水镜环
	boss._cast_ring(MoveDB.resolve_boss("form_mirror_ring"))
	await _wait(0.1)
	_check(boss._ring != null and is_instance_valid(boss._ring), "水镜环已铺下")
	player.global_position = boss.global_position
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0
	player.hp = player.max_hp
	await _wait(0.4)
	_check(player.has_debuff("mirror_slow"), "水镜环挂上镜滞")
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	# 水镜环先撤掉，避免它继续给后面「碎镜挂镜滞」叠无敌帧
	if boss._ring != null and is_instance_valid(boss._ring):
		boss._ring.queue_free()
		boss._ring = null
	# —— 棋局归一化的守卫（2026-11-06 用户问「为什么下棋模式里水镜环伤害这么高」）——
	# 同一式两个口径必须各自钉住：PvE 不许被摊薄（玩家走得出圈，那档压力是设计的），
	# 棋局必须被摊成 ceil(时长/TICK) 拍（棋子站桩，4 拍全中就等于名义系数的 4 倍）。
	# 用 use_random=false 取名义值，再按 ±10% 容差比：真实结算带随机浮动，
	# 卡死等号会让这条判据变成掷硬币。
	var ring_nominal: float = MoveDB.boss_damage(
			"form_mirror_ring", float(boss.attack_power), int(boss.phase), false)
	boss._cast_ring(MoveDB.resolve_boss("form_mirror_ring"))
	await _wait(0.05)
	var pve_tick: float = float(boss._ring.damage)
	_check(pve_tick > ring_nominal * 0.88 and pve_tick < ring_nominal * 1.12,
			"水镜环（PvE）单次 tick = 名义一击，没被摊薄",
			"tick %.0f / 名义 %.0f" % [pve_tick, ring_nominal])
	boss._ring.queue_free()
	boss._ring = null
	var keep_team := int(boss.team_id)
	boss.team_id = 0
	boss._cast_ring(MoveDB.resolve_boss("form_mirror_ring"))
	await _wait(0.05)
	var ticks := ceilf(float(boss._ring.duration) / MirrorRingField.TICK)
	var match_total: float = float(boss._ring.damage) * ticks
	_check(absf(match_total - ring_nominal) < ring_nominal * 0.12,
			"水镜环（棋局）整场合计 = 名义一击（摊成 %.0f 拍）" % ticks,
			"单次 %.0f × %.0f = %.0f / 名义 %.0f" % [
				float(boss._ring.damage), ticks, match_total, ring_nominal])
	boss._ring.queue_free()
	boss._ring = null
	boss.team_id = keep_team
	player.global_position = boss.global_position + Vector2(0.0, 130.0)
	# 碎镜：镜像位置爆炸 + 镜滞
	_clear_images(boss)
	var img4: MirrorImage = boss._spawn_image(0)
	await _wait(0.05)
	var shatter_pos: Vector2 = img4.global_position
	player.global_position = shatter_pos
	player.invincible_timer = 0.0
	player._hit_negated_timer = 0.0
	player.hp = player.max_hp
	boss._cast_shatter(MoveDB.resolve_boss("form_mirror_shatter"))
	await _wait(0.1)
	_check(not is_instance_valid(img4) or bool(img4.get("_dead")), "碎镜捏碎镜像")
	_check(player.has_debuff("mirror_slow") or boss.has_debuff("mirror_slow"),
		"碎镜范围挂镜滞")
	player.invincible_timer = 999.0
	player.hp = player.max_hp

	# ===== 8. 二阶段：上限 3 具 + 万镜归一 =====
	boss.current_hp = boss.max_hp * 0.49
	boss.take_damage(1.0, player, "physical", "")
	await _wait(0.4)
	_check(boss.phase == 2, "50% 触发二阶段", "phase=%d" % boss.phase)
	for raw in boss._images:
		if raw is MirrorImage:
			_check(bool(raw.get("_phase_red")), "二阶段镜像同步转红")
			break
	_check(boss._max_images() == 3, "二阶段镜像上限 = 3", "n=%d" % boss._max_images())
	boss._cools.clear()
	_clear_images(boss)
	for i in 3:
		boss._spawn_image(i)
	await _wait(0.1)
	_check(boss._images.size() == 3, "二阶段可同时有 3 具镜像", "n=%d" % boss._images.size())
	var hp_before_myriad: float = boss.current_hp
	boss._cast_myriad(MoveDB.resolve_boss("form_mirror_myriad"))
	await _wait(0.15)
	_check(boss._current_skill == "" and boss.state == BossBase.BossState.RECOVER, "万镜归一正常收招")
	# 镜像同帧补刀：玩家应掉血（玩家无敌关掉）
	# 镜像现在绕玩家站位；测补斩时把玩家放到镜像旁边，不要用 BOSS 脚下
	var echo_img: MirrorImage = boss._images[0]
	player.global_position = echo_img.global_position + Vector2(0.0, 46.0)
	player.invincible_timer = 0.0
	player.hp = player.max_hp
	echo_img.call("force_echo")
	await _wait(0.1)
	_check(player.hp < player.max_hp, "镜像补斩命中玩家",
		"%.0f -> %.0f" % [player.max_hp, player.hp])
	player.invincible_timer = 999.0
	player.hp = player.max_hp

	# ===== 9. 玩家侧完整继承 =====
	# 玩家侧测试期间关掉 BOSS AI：否则它会用范围招式把玩家刚召出的镜像打碎，
	# 测出来像「技能放不出来」，实际是对手的正常反制。
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.state = BossBase.BossState.IDLE
	# 清掉 BOSS 残留的水镜环与镜像：它们会继续打碎玩家刚召出的镜像，
	# 那是正常的对手反制，但会干扰「玩家侧技能是否可用」的判定。
	_clear_rings(player.get_parent())
	boss._ring = null
	_clear_images(boss)
	player._hit_negated_timer = 0.0
	for sid in learned:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	for sid in learned:
		if String(SkillDB.get_skill(String(sid)).get("skill_type", "")) == SkillDB.TYPE_ACTIVE \
				and not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player.stamina = player.max_stamina
	player._mirror_clear_images()
	player.global_position = boss.global_position + Vector2(0.0, 120.0)
	# 镜花
	_check(player.try_use_skill("skill_mirror_bloom"), "玩家可施放镜花")
	await _wait(0.3)
	_check(player._mirror_images.size() == 1, "镜花召出 1 具镜像",
		"n=%d" % player._mirror_images.size())
	_check(player._mirror_images[0].faction == "player", "玩家镜像阵营正确")
	_check(player._mirror_images[0].is_in_group("ally_summon"), "玩家镜像可被 BOSS 扫到")
	# 再召一具；被动「照影」在身上 → 上限 2 + 1 = 3
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	_check(player.try_use_skill("skill_mirror_bloom"), "玩家可再施放镜花")
	await _wait(0.3)
	_check(player._mirror_images.size() == 2, "镜花可连召两具",
		"n=%d" % player._mirror_images.size())
	_check(player._mirror_max_images() == MirrorImage.MAX_IMAGES
			+ MirrorImage.PASSIVE_EXTRA_IMAGES,
		"带被动「照影」时上限 = 2 + 1", str(player._mirror_max_images()))
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	_check(player.try_use_skill("skill_mirror_bloom"), "被动抬高的第 3 具也能召出")
	await _wait(0.3)
	_check(player._mirror_images.size() == 3, "场上同时 3 具镜像",
		"n=%d" % player._mirror_images.size())
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	_check(not player.try_use_skill("skill_mirror_bloom"), "镜像满时镜花不白扣资源")
	_check(player.mana >= player.max_mana - 0.01, "镜花被挡时灵力未扣")
	CharacterData.passive_skill_loadout = []
	_check(player._mirror_max_images() == MirrorImage.MAX_IMAGES,
		"摘掉被动后上限回到 2", str(player._mirror_max_images()))
	CharacterData.passive_skill_loadout = ["skill_mirror_echo"]
	# 镜水斩：一次出手让场上所有镜像一起复读、一起消散
	var boss_hp0: float = boss.current_hp
	player.skill_cooldowns.clear()
	player.stamina = player.max_stamina
	player.global_position = boss.global_position + Vector2(0.0, 80.0)
	_check(player.try_use_skill("skill_mirror_slash"), "玩家可施放镜水斩")
	await _wait(0.35)
	_check(boss.current_hp < boss_hp0, "镜水斩命中真身",
		"%.0f -> %.0f" % [boss_hp0, boss.current_hp])
	await _wait(0.35)
	_check(player._mirror_images.is_empty(), "所有镜像一起复读后消散",
		"n=%d" % player._mirror_images.size())
	# ===== 9b. 复读范围（2026-11-01 改版）：打得出伤害的功法都复读，所有镜像一起放 =====
	# 走真实 try_use_skill 入口：复读排在 `_cast_skill` 的本体结算之后
	for sid in ["skill_sword_chop", "skill_yinyang_finger", "skill_blade_dash"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	player._mirror_clear_images()
	player._mirror_spawn(boss.global_position + Vector2(40.0, 0.0))
	player._mirror_spawn(boss.global_position + Vector2(-40.0, 0.0))
	await _wait(0.1)
	var echo_n: int = player._mirror_images.size()
	_check(echo_n == 2, "复读测试：先铺两具镜像", "n=%d" % echo_n)
	var echo_hp: float = boss.current_hp
	player.skill_cooldowns.clear()
	player.stamina = player.max_stamina
	player.mana = player.max_mana
	player._cast_skill("skill_sword_chop")
	await _wait(0.8)
	_check(player._mirror_images.is_empty(),
		"一次出手把场上所有镜像一起放掉", "%d -> %d" % [echo_n, player._mirror_images.size()])
	_check(boss.current_hp < echo_hp, "镜像复读自己也打出伤害")
	# 法术功法现在同样复读（玄冥指…）
	player._mirror_clear_images()
	player._mirror_spawn(boss.global_position + Vector2(30.0, 0.0))
	await _wait(0.1)
	echo_hp = boss.current_hp
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player._cast_skill("skill_yinyang_finger")
	await _wait(0.8)
	_check(player._mirror_images.is_empty(), "法术功法也让镜像复读（一并消散）",
		"n=%d" % player._mirror_images.size())
	# 万剑归宗：镜像要「真的放出飞剑」，不是原地结算 —— 用无镜像 / 有镜像的弹体差量证明。
	# 两处都要离 BOSS 足够远，否则量到的时候弹体已经命中并回收了。
	player._mirror_clear_images()
	player.global_position = boss.global_position + Vector2(0.0, 420.0)
	player.sword_intent = 0
	player._sync_sword_intent_skill_mult()
	player.skill_cooldowns.clear()
	player.stamina = player.max_stamina
	player._cast_skill("skill_sword_myriad")
	await _wait(0.5)
	var proj_base := _count_projectiles(player.get_parent(), "skill_sword_myriad")
	await _wait(2.5)
	player._mirror_spawn(player.global_position + Vector2(0.0, 240.0))
	await _wait(0.1)
	_check(player._mirror_images.size() == 1, "万剑差量测试：镜像在场",
		"n=%d" % player._mirror_images.size())
	player.sword_intent = 0
	player._sync_sword_intent_skill_mult()
	player.skill_cooldowns.clear()
	player.stamina = player.max_stamina
	player._cast_skill("skill_sword_myriad")
	await _wait(0.5)
	var proj_with := _count_projectiles(player.get_parent(), "skill_sword_myriad")
	_check(player._mirror_images.is_empty(), "万剑复读会消耗镜像",
		"n=%d" % player._mirror_images.size())
	_check(proj_base >= 2 and proj_with >= proj_base + 2,
		"镜像复读万剑归宗时真的生成飞剑弹体",
		"无镜像=%d 有镜像=%d" % [proj_base, proj_with])
	await _wait(2.5)
	# 镜湖：镜像亲自在自己脚下铺一圈水场
	player._mirror_clear_images()
	_clear_rings(player.get_parent())
	await _wait(0.1)
	var ring_base := _count_rings(player.get_parent())
	player._mirror_spawn(boss.global_position + Vector2(0.0, 220.0))
	await _wait(0.1)
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player._cast_skill("skill_mirror_ring")
	await _wait(0.5)
	_check(_count_rings(player.get_parent()) >= ring_base + 2,
		"镜像复读镜湖会真的铺出水场（本体 + 镜像各一圈）",
		"base=%d now=%d" % [ring_base, _count_rings(player.get_parent())])
	_clear_rings(player.get_parent())
	player._mirror_clear_images()
	# 一剑开天（满层变体）：整套巨剑演出由镜像自己挂出来，出伤对齐剑落地
	player._mirror_spawn(boss.global_position + Vector2(0.0, 240.0))
	await _wait(0.1)
	_check(player._mirror_images.size() == 1, "一剑开天测试：镜像在场",
		"n=%d" % player._mirror_images.size())
	var heaven_img: MirrorImage = player._mirror_images[0]
	player.sword_intent = 5
	player._sync_sword_intent_skill_mult()
	player.skill_cooldowns.clear()
	player.stamina = player.max_stamina
	player._cast_skill("skill_sword_heaven")
	# 本体这一剑在前摇 + 劈落（≈0.6 秒）后落地，镜像是在那一刻才开始复读的
	await _wait(0.95)
	var has_heaven_fx := false
	var img_alive := is_instance_valid(heaven_img) and not bool(heaven_img.is_dead())
	if img_alive:
		for c in heaven_img.get_children():
			if c is SwordHeavenFx:
				has_heaven_fx = true
	_check(has_heaven_fx, "镜像复读一剑开天会挂出整套巨剑演出")
	_check(img_alive, "巨剑还在空中时镜像不碎（不会把剑一起带走）")
	var heaven_hp_mid: float = boss.current_hp
	await _wait(0.9)
	_check(boss.current_hp < heaven_hp_mid,
		"镜像的一剑开天在剑落地那一刻才出伤",
		"%.0f -> %.0f" % [heaven_hp_mid, boss.current_hp])
	_check(not is_instance_valid(heaven_img) or bool(heaven_img.is_dead()),
		"落地结算后镜像消散")
	player.sword_intent = 0
	player._sync_sword_intent_skill_mult()
	player._mirror_clear_images()
	# 镜像抢了仇恨以后，BOSS 的 AI 必须能把 MirrorImage 一路当目标读下去。
	# （2026-11-02 用户实机：分身复读一剑开天打出伤害 → 仇恨落到分身身上 →
	#  观澜 _choose() 里 bool(p.get("is_dead")) 拿到 null →
	#  「Invalid call. Nonexistent 'bool' constructor」每 0.28 秒刷一条，一局刷出 188 条）
	var aggro_img: MirrorImage = player._mirror_spawn(boss.global_position + Vector2(0.0, 200.0))
	await _wait(0.1)
	_check(aggro_img != null, "仇恨测试：镜像在场")
	boss._threat.clear()
	boss.target = player
	boss.threat_target = player
	boss.add_threat(aggro_img, 900.0)
	boss._update_threat_target(true)
	_check(boss.target == aggro_img, "镜像打出的伤害会抢到仇恨", str(boss.target))
	boss.state = BossBase.BossState.IDLE
	boss._decide_wait = 0.0
	boss._cools.clear()
	_clear_images(boss)
	boss._choose()
	_check(boss.state == BossBase.BossState.WINDUP,
		"目标是镜像时 BOSS 照常出招（is_dead 读数不再把 AI 卡死）",
		"state=%s" % str(boss.state))
	# 分身被打碎 → 仇恨立刻作废，BOSS 必须马上回玩家本体，不能对着空气打
	# 这一段要 BOSS 的 AI 真的在跑：前面玩家侧测试把它的 process 关了，这里临时打开
	boss.set_physics_process(true)
	boss.set_process(true)
	aggro_img.take_damage(1.0)
	await _wait(0.3)
	_check(boss.target == player, "镜像碎掉后 BOSS 立刻回打玩家本体", str(boss.target))
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.state = BossBase.BossState.IDLE
	boss._current_skill = ""
	_clear_images(boss)
	# 召镜两式不参与复读：镜花自己放出去的那具不会被自己用掉
	player._mirror_clear_images()
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	_check(player.try_use_skill("skill_mirror_bloom"), "镜花照常召镜")
	await _wait(0.8)
	_check(player._mirror_images.size() == 1, "镜花不会把刚召出的镜像当复读用掉",
		"n=%d" % player._mirror_images.size())
	# 多段招式（破步突进斩 dash_times=2）：每具镜像只复读一次
	player._mirror_clear_images()
	player._mirror_spawn(boss.global_position + Vector2(40.0, 0.0))
	player._mirror_spawn(boss.global_position + Vector2(-40.0, 0.0))
	await _wait(0.1)
	var dash_form := SkillDB.get_skill_form("skill_blade_dash")
	_check(int(dash_form.get("dash_times", 1)) > 1, "测试前提：破步突进斩是多段招式",
		str(dash_form.get("dash_times", 1)))
	player.skill_cooldowns.clear()
	player.stamina = player.max_stamina
	player._cast_skill("skill_blade_dash")
	await _wait(2.0)
	_check(player._mirror_images.is_empty(), "多段招式一次出手每具镜像只放一次",
		"n=%d" % player._mirror_images.size())
	# 没打中也照样放完消散：把镜像丢到离 BOSS 很远的地方，用一记短程功法
	player._mirror_clear_images()
	var far_img: MirrorImage = player._mirror_spawn(player.global_position + Vector2(900.0, 0.0))
	await _wait(0.1)
	_check(far_img != null, "远位镜像已召出")
	player.skill_cooldowns.clear()
	player.stamina = player.max_stamina
	player._cast_skill("skill_sword_chop")
	await _wait(0.8)
	_check(player._mirror_images.is_empty(),
		"镜像打不到目标也会释放并消散（不看命中）",
		"n=%d" % player._mirror_images.size())
	# 碎镜先吃掉本体的那一具，剩下的镜像才跟着复读
	player._mirror_clear_images()
	player._mirror_spawn(boss.global_position + Vector2(30.0, 0.0))
	player._mirror_spawn(boss.global_position + Vector2(0.0, 30.0))
	await _wait(0.1)
	boss.remove_debuff("mirror_slow")
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player._cast_skill("skill_mirror_shatter")
	await _wait(0.8)
	_check(boss.has_debuff("mirror_slow"), "玩家碎镜给 BOSS 挂镜滞")
	_check(player._mirror_images.is_empty(), "碎镜：本体用掉一具，剩下的镜像跟着炸开")
	player._mirror_clear_images()
	# 照影刺 + 万镜：补齐八式入口
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player.stamina = player.max_stamina
	player._mirror_clear_images()
	player.global_position = boss.global_position + Vector2(0.0, 120.0)
	player.attack_dir = (boss.global_position - player.global_position).normalized()
	var boss_hp_thrust: float = boss.current_hp
	# 照影刺带 40px 前冲：探针没有摇杆输入，显式按「上」把朝向钉向 BOSS
	Input.action_press("move_up", 1.0)
	_check(player.try_use_skill("skill_mirror_thrust"), "玩家可施放照影刺")
	await _wait(0.7)
	Input.action_release("move_up")
	_check(boss.current_hp < boss_hp_thrust, "照影刺命中真身",
		"%.0f -> %.0f" % [boss_hp_thrust, boss.current_hp])
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player._mirror_clear_images()
	_check(player.try_use_skill("skill_mirror_myriad"), "玩家可施放万镜")
	await _wait(0.8)
	_check(player._mirror_images.size() == player._mirror_max_images(),
		"万镜一次补满到当前上限（带被动 = 3 具）",
		"n=%d cap=%d" % [player._mirror_images.size(), player._mirror_max_images()])
	# 换镜
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player._mirror_clear_images()
	player._mirror_spawn(player.global_position + Vector2(80.0, 0.0))
	await _wait(0.1)
	# 镜像现在会自己走位；换镜测试要量「施放瞬间」的镜像点，先停下这一具
	if not player._mirror_images.is_empty():
		player._mirror_images[0].set_process(false)
	var ppos: Vector2 = player.global_position
	var imgpos: Vector2 = player._mirror_images[0].global_position
	_check(player.try_use_skill("skill_mirror_swap"), "玩家可施放换镜")
	await _wait(0.2)
	_check(player.global_position.distance_to(imgpos) < 12.0, "换镜与镜像互换位置",
		"p %.0f -> %.0f" % [ppos.length(), player.global_position.length()])
	_check(player.invincible_timer > 0.0, "换镜后短暂无敌")
	# 碎镜
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player._mirror_clear_images()
	player._mirror_spawn(boss.global_position + Vector2(0.0, 60.0))
	await _wait(0.1)
	boss.remove_debuff("mirror_slow")
	_check(player.try_use_skill("skill_mirror_shatter"), "玩家可施放碎镜")
	await _wait(0.2)
	_check(boss.has_debuff("mirror_slow"), "玩家碎镜给 BOSS 挂镜滞")
	# 镜返（2026-11-01 改版）：挡的是**术法**，按 100% 原样反弹；物理近战不再被镜面吃掉
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	_check(player.try_use_skill("skill_mirror_return"), "玩家可施放镜返")
	await _wait(0.15)
	var php: float = player.hp
	var bhp: float = boss.current_hp
	player.invincible_timer = 0.0
	player.take_damage(120.0, "elemental", boss, "fire")
	_check(absf(player.hp - php) < 0.01, "玩家镜返挡下术法",
		"hp %.0f -> %.0f" % [php, player.hp])
	# 观澜本体法抗 100（减伤 50%）：120 的反弹落地约 60，仍远高于旧版 35% 的 42
	_check(bhp - boss.current_hp >= 50.0, "镜返按 100% 反弹术法（经对方法抗后）",
		"boss %.0f -> %.0f" % [bhp, boss.current_hp])
	_check(not player.has_buff("mirror_return"), "镜返是一次性架势")
	var php_r: float = player.hp
	var bhp_r: float = boss.current_hp
	player.take_damage(80.0, "physical_melee", boss)
	_check(player.hp < php_r, "镜返不再挡物理近战", "%.0f -> %.0f" % [php_r, player.hp])
	_check(absf(boss.current_hp - bhp_r) < 0.01, "物理近战不会被镜返反弹")
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	# 镜湖
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	_check(player.try_use_skill("skill_mirror_ring"), "玩家可施放镜湖")
	await _wait(0.2)
	var field_found := false
	for child in player.get_parent().get_children():
		if child is MirrorRingField:
			field_found = true
	_check(field_found, "玩家镜湖生成了 MirrorRingField")
	# 被动照影
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	player._mirror_clear_images()
	player._mirror_passive_cd = 0.0
	player._mirror_passive_on_perfect_dodge()
	await _wait(0.1)
	_check(player._mirror_images.size() == 1, "被动照影在完美闪避后留镜")
	_check(player._mirror_passive_cd > 0.0, "照影被动进入内置 CD")
	# 无镜像时碎镜 / 换镜门槛
	player._mirror_clear_images()
	player.skill_cooldowns.clear()
	player.mana = player.max_mana
	_check(not player.try_use_skill("skill_mirror_shatter"), "无镜像时碎镜被拦")
	_check(not player.try_use_skill("skill_mirror_swap"), "无镜像时换镜被拦")
	# 普攻/其他功法也能碎 BOSS 镜像（首战空手可破）
	_clear_rings(player.get_parent())
	var img5: MirrorImage = boss._spawn_image(2)
	await _wait(0.1)
	img5.take_damage(1.0, player, "physical", "")
	_check(not is_instance_valid(img5) or bool(img5.get("_dead")), "普攻/任意命中可碎 BOSS 镜像")

	# ===== 10. 召唤法宝：盟友观澜的镜像替玩家打敌方 BOSS =====
	var tr_tpl := ItemDB.get_treasure_template("tr_guanying_ling")
	_check(not tr_tpl.is_empty() and String(tr_tpl.get("summon_boss_id", "")) == "boss_04",
		"镜主令召唤的是观澜")
	var summoned_ok: bool = player._summon_ally_boss(tr_tpl, 0, 0, 0.0)
	_check(summoned_ok, "镜主令成功召出友军观澜")
	var ally: Node2D = null
	for raw in arena.get_children():
		if raw is DomainBoss04 and bool(raw.get("is_ally")):
			ally = raw as Node2D
	_check(ally != null and is_instance_valid(ally), "友军观澜已在场")
	if ally != null:
		ally.set_physics_process(false)
		ally.set_process(false)
		ally.global_position = boss.global_position + Vector2(78.0, 0.0)
		ally.call("_cast_bloom", MoveDB.resolve_boss("form_mirror_bloom"))
		await _wait(0.2)
		var ally_imgs: Array = ally.get("_images")
		_check(ally_imgs.size() >= 1, "友军观澜也会召镜像", "n=%d" % ally_imgs.size())
		if not ally_imgs.is_empty():
			var ai: MirrorImage = ally_imgs[0] as MirrorImage
			_check(ai.faction == "ally_boss" and ai.is_in_group("ally_summon"),
				"友军镜像阵营 = ally_boss，进友军组")
			var bhp3: float = boss.current_hp
			ai.call("force_echo")
			await _wait(0.15)
			_check(boss.current_hp < bhp3, "友军镜像补斩打到敌方 BOSS",
				"%.0f -> %.0f" % [bhp3, boss.current_hp])
		ally.queue_free()

	# ===== 11. 数值反推 =====
	for fid in ["form_mirror_slash", "form_mirror_thrust", "form_mirror_shatter",
			"form_mirror_ring", "form_mirror_myriad"]:
		var dmg := MoveDB.boss_damage(String(fid), boss.attack_power, 1)
		var b := MoveDB.resolve_boss(String(fid))
		var kind := String(b.get("attack_kind", "physical_melee"))
		var elem := String(b.get("damage_element", ""))
		var taken := float(DamageCalc.incoming(dmg, CharacterData, kind, elem).get("amount", dmg))
		print("  一阶段 %s 基础伤害 = %.0f，过玩家抗性 %.0f（%.1f%% 气血）" % [
			fid, dmg, taken, taken / player.max_hp * 100.0])
		_check(taken < player.max_hp * 0.5, "单招不会打掉一半以上气血：%s" % fid,
			"%.0f vs %.0f" % [taken, player.max_hp])
		_check(dmg > 20.0 and dmg < player.max_hp,
			"单招原始伤害不会超过满血：%s" % fid, "%.0f vs %.0f" % [dmg, player.max_hp])
	var raw_spell := 1000.0
	var spell_taken := float(DamageCalc.incoming(raw_spell, boss, "elemental", "water").get("amount", raw_spell))
	_check(spell_taken < raw_spell * 0.6, "BOSS 法抗实际减伤生效",
		"%.0f -> %.0f" % [raw_spell, spell_taken])
	var dmg_p2 := MoveDB.boss_damage("form_mirror_slash", boss.attack_power, 2)
	var dmg_p1 := MoveDB.boss_damage("form_mirror_slash", boss.attack_power, 1)
	_check(dmg_p2 > dmg_p1, "二阶段伤害倍率生效", "%.0f -> %.0f" % [dmg_p1, dmg_p2])
	_check(CharacterData.physical_attack() > 100.0 and CharacterData.spell_attack() > 80.0,
		"玩家元婴面板具备基本输出",
		"物攻 %.0f 法强 %.0f" % [CharacterData.physical_attack(), CharacterData.spell_attack()])

	GameState.battle_context = {}
