extends Node2D
## 离照 / 逐日·天火 全链路自检（2026-10-29）
## 覆盖：数据 / 八式双侧 / 火种拾取与夺火 / 日冕 / 灼心 / 投日 / 日蚀 / 日轮 / 天火坠 / BOSS AI。

class StubPlayer extends Node2D:
	var is_dead := false
	var is_dodging := false
	var is_teleporting := false
	var knockback_velocity := Vector2.ZERO
	var debuffs: Dictionary = {}
	var hits: Array = []
	func take_damage(amount: float, _kind: String = "physical", _source: Node = null,
			_elem: String = "") -> void:
		hits.append(amount)
	func apply_debuff(id: String, duration: float, _quiet := false) -> bool:
		debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
		return true
	func clear_debuff(id: String) -> void:
		debuffs.erase(id)
	func head_top_y() -> float:
		return -110.0

class DummyBoss extends Node2D:
	var state := 0
	var uses_sun := true
	var hits: Array = []
	var kinds: Array = []
	var elements: Array = []
	var debuffs: Dictionary = {}
	var knockbacks: Array = []
	func take_damage(amount: float, _source: Node = null, kind: String = "physical",
			elem: String = "", _proj: bool = false) -> void:
		hits.append(amount)
		kinds.append(kind)
		elements.append(elem)
	func take_knockback(impulse: Vector2) -> void:
		knockbacks.append(impulse)
	func apply_debuff(id: String, duration: float) -> bool:
		debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
		return true
	func remove_debuff(id: String) -> void:
		debuffs.erase(id)
	func uses_sun_seed() -> bool:
		return uses_sun
	func head_top_y() -> float:
		return -110.0
	func hit_spheres() -> Array:
		return [Vector3(0.0, -10.0, 46.0)]

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _clear_seeds() -> void:
	for raw in get_tree().get_nodes_in_group("sun_seed"):
		var old := raw as Node
		if old != null and is_instance_valid(old):
			old.queue_free()


func _ready() -> void:
	print("\n########## 离照 · 逐日天火 探针 ##########")
	await get_tree().process_frame
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	_test_data()
	await _test_boss()
	await _test_player()
	_test_resolve()


func _test_data() -> void:
	var forms := ["form_sun_step", "form_sun_slash", "form_sun_throw", "form_sun_pull",
		"form_sun_wind", "form_sun_eclipse", "form_sun_wheel", "form_sun_meteor"]
	for f in forms:
		_check(MoveDB.has_form(String(f)), "形态已登记 " + String(f))
		_check(not MoveDB.resolve_boss(String(f)).is_empty(), "BOSS 侧可解析 " + String(f))
		_check(not MoveDB.resolve_player(String(f)).is_empty(), "玩家侧可解析 " + String(f))
	var throw_player := MoveDB.resolve_player("form_sun_throw")
	_check(is_equal_approx(float(throw_player.get("cooldown", 0.0)), 2.0),
		"投日玩家冷却 = 2 秒", "%.1f" % float(throw_player.get("cooldown", 0.0)))
	var ids := ["skill_sun_step", "skill_sun_slash", "skill_sun_throw", "skill_sun_pull",
		"skill_sun_wind", "skill_sun_eclipse", "skill_sun_wheel", "skill_sun_meteor"]
	for sid in ids:
		var sk := SkillDB.get_skill(String(sid))
		_check(not sk.is_empty(), "功法已登记 " + String(sid))
		_check(bool(sk.get("sun", false)), "功法带 sun 标记 " + String(sid))
		_check(SkillDB.get_effect_lines(String(sid)).size() >= 3,
			"功法效果行 >=3 " + String(sid))
	_check(String(SkillDB.get_skill("skill_sun_wheel").get("skill_type", ""))
		== SkillDB.TYPE_PASSIVE, "日轮玩家侧已改为被动")
	_check(String(SkillDB.get_skill("skill_sun_wheel").get("passive_effect", ""))
		== "sun_seed_bearer", "被动 effect = sun_seed_bearer")
	_check(not SkillDB.get_passive_by_effect("sun_seed_bearer").is_empty(),
		"盗火者被动可按 effect 查到")
	_check(WorldDB.get_boss_name("boss_03_b") == "离照", "boss_03_b 定名离照")
	_check(WorldDB.get_boss_scene("boss_03_b").ends_with("domain_boss_03_b.tscn"),
		"BOSS 场景已登记")
	_check(not WorldDB.get_boss_moves("boss_03_b").is_empty(), "BOSS 招式组已登记")
	var f8 := WorldDB.get_floor(8)
	_check(String(f8.get("boss_id", "")) == "boss_03_b", "塔第 8 层 = 离照",
		str(f8.get("boss_id", "")))
	_check(WorldDB.get_floor_reward_skills(8).size() == 8, "塔 8 层感悟池 = 8 门",
		"n=%d" % WorldDB.get_floor_reward_skills(8).size())
	var codex := CodexDB.boss_entry("boss_03_b")
	_check(not codex.is_empty(), "图鉴卡已登记")
	_check((codex.get("mechanic_points", []) as Array).size() >= 5, "图鉴机制要点 >=5")
	_check(not CodexDB.boss_status_info("boss_03_b").is_empty(), "图鉴状态含灼心")
	_check(not ItemDB.get_drops_for_boss("boss_03_b").is_empty(), "掉落表已登记")
	_check(not ItemDB.get_equipment_template("eq_jinwen_zhanpao").is_empty(), "烬纹战袍已登记")
	var robe_tpl := ItemDB.get_equipment_template("eq_jinwen_zhanpao")
	var robe_attrs: Dictionary = robe_tpl.get("attributes", {})
	_check(robe_attrs.has(AttributeDB.ATTR_SPELL_POWER)
		and robe_attrs.has(AttributeDB.ATTR_MAGIC_RESIST)
		and not robe_attrs.has(AttributeDB.ATTR_PHYSICAL_RESIST),
		"烬纹战袍 = 法系火袍词条", str(robe_attrs))
	var fire_tpl := ItemDB.get_equipment_template("eq_huolin_jia")
	var fire_attrs: Dictionary = fire_tpl.get("attributes", {})
	_check(fire_attrs.has(AttributeDB.ATTR_PHYSICAL_RESIST)
		and not fire_attrs.has(AttributeDB.ATTR_SPELL_POWER),
		"火麟甲 = 物理坦克词条", str(fire_attrs))
	_check(not ItemDB.get_equipment_template("eq_zhuri_lv").is_empty(), "逐日履已登记")
	_check(not ItemDB.get_material("mat_chixiao_risui").is_empty(), "赤霄日髓已登记")
	_check(not ItemDB.get_material("soul_lizhao").is_empty(), "离照元魂已登记")
	_check(not ItemDB.get_treasure_template("tr_huozheng_ling").is_empty(), "火正令已登记")
	_check(not ItemDB.get_synth_recipe_by_soul("soul_lizhao").is_empty(), "火正令合成配方已登记")
	_check(SkillDB.get_group_rules("boss_03_b").get("title", "").contains("逐日"),
		"功法库组规则卡已挂")
	_check(not BuffDB.get_buff("sun_crown").is_empty(), "日冕 buff 已登记")
	_check(not DebuffDB.get_debuff("sunburn").is_empty(), "灼心 debuff 已登记")
	_check(ItemDB.get_drops_for_boss("boss_03_b").size() == 3, "掉落表 2 装备 + 1 材料")
	var ids2 := ItemDB.get_boss_equipment_ids("boss_03_b")
	_check("eq_jinwen_zhanpao" in ids2 and "eq_zhuri_lv" in ids2, "离照装备 2 件", str(ids2))
	_check(not ItemDB.get_synth_recipe_for_equipment("eq_jinwen_zhanpao").is_empty(),
		"烬纹战袍可熔铸火正令")
	var entries_ok := true
	for e in ItemDB.get_drops_for_boss("boss_03_b"):
		var ee: Dictionary = e
		var eid := String(ee.get("item_id", ""))
		if String(ee.get("kind", "equipment")) == "material":
			if ItemDB.get_material(eid).is_empty():
				entries_ok = false
		elif ItemDB.get_equipment_template(eid).is_empty():
			entries_ok = false
	_check(entries_ok, "离照掉落表条目全部可解析")
	seed(20261029)
	var roll_hits := 0
	var roll_ids := {}
	for i in 60:
		var rolled: Array = ItemDB.roll_boss_drops("boss_03_b")
		if not rolled.is_empty():
			roll_hits += 1
		for d in rolled:
			var dd: Dictionary = d
			roll_ids[String(dd.get("template_id", dd.get("material_id", "")))] = true
	_check(roll_hits >= 30, "离照掉落 60 次稳定产出", "%d/60 %s" % [roll_hits, str(roll_ids.keys())])
	_check("mat_chixiao_risui" in roll_ids, "离照位面材料可掷出", str(roll_ids.keys()))
	var domain_bosses: Array = WorldDB.get_domain("domain_03").get("boss_ids", [])
	_check("boss_03_b" in domain_bosses, "domain_03 含离照")
	var groups := SkillDB.get_library_groups()
	var found_group := false
	for g in groups:
		if String((g as Dictionary).get("group_id", "")) == "boss_03_b":
			found_group = true
			_check(int((g as Dictionary).get("total", 0)) == 8, "功法库离照组 8 门",
				"n=%d" % int((g as Dictionary).get("total", 0)))
	_check(found_group, "功法库出现离照分组")
	var found_boss := false
	for e in CodexDB.boss_entries():
		if String((e as Dictionary).get("id", "")) == "boss_03_b":
			found_boss = true
	_check(found_boss, "图鉴 BOSS 列表出现离照")
	# 只要求「至少到照影界那一层」：后面再排新 BOSS 不该把这条判死
	_check(WorldDB.get_floors().size() >= 10, "万界塔至少排到照影界首位（第 10 层）",
		"n=%d" % WorldDB.get_floors().size())
	_check(ResourceLoader.exists(String(CodexDB.boss_entry("boss_03_b").get("portrait", ""))),
		"图鉴卡原画存在")
	_check(ResourceLoader.exists(String(ArtDB.get_visual("bg_lizhao_arena").get("texture", ""))),
		"焚天祭坛地面存在")
	_check(ResourceLoader.exists(String(ArtDB.get_visual("boss_lizhao").get("rig", ""))),
		"离照 rig 存在")
	for sid in ids:
		_check(ResourceLoader.exists("res://assets/ui/icon/%s.png" % String(sid)),
			"技能图标存在 " + String(sid))
	_check(ResourceLoader.exists("res://assets/ui/icon/equip_jinwen_zhanpao.png"), "烬纹战袍图标存在")
	_check(ResourceLoader.exists("res://assets/ui/icon/equip_zhuri_lv.png"), "逐日履图标存在")
	_check(ResourceLoader.exists("res://assets/ui/icon/mat_chixiao_risui.png"), "赤霄日髓图标存在")
	_check(ResourceLoader.exists("res://assets/ui/icon/soul_lizhao.png"), "离照元魂图标存在")
	_check(ResourceLoader.exists("res://assets/ui/icon/tr_huozheng_ling.png"), "火正令图标存在")
	_check(not SkillDB.get_group_rules("boss_03_b").is_empty(), "功法库组规则非空")


func _test_boss() -> void:
	var sp := StubPlayer.new()
	sp.add_to_group("player")
	sp.global_position = Vector2(220.0, 0.0)
	add_child(sp)
	var boss = (load("res://scenes/boss/domain_boss_03_b.tscn") as PackedScene).instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.global_position = Vector2.ZERO
	boss.set_arena_bounds(Vector2(600.0, 380.0), Vector2.ZERO)
	boss._update_threat_target(true)
	boss.target = sp
	_check(is_equal_approx(boss.max_hp, 15500.0), "BOSS 血量按结丹中期反推",
		"hp=%.0f" % boss.max_hp)
	_check(is_equal_approx(boss.attack_power, 96.0), "BOSS 攻击力按结丹中期反推",
		"atk=%.0f" % boss.attack_power)
	_check(bool(boss.uses_sun_seed()), "BOSS 声明可抢天火种")
	var skin = boss.get_node_or_null("Visual/Skin")
	var rig_node = skin.render_node if skin != null else null
	_check(rig_node is BossRigSun, "骨骼已由 BossRigSun 构建")
	if rig_node is BossRigSun:
		var ap = rig_node.get_node_or_null("Anim")
		_check(ap != null, "骨骼 AnimationPlayer 已创建")
		if ap != null:
			var names := (ap as AnimationPlayer).get_animation_list()
			for need in ["idle", "walk", "step", "slash", "throw", "pull",
					"wind", "eclipse", "wheel", "meteor"]:
				_check(need in names, "骨骼动画存在 " + String(need))
	_check(boss._sun_pips != null and is_instance_valid(boss._sun_pips), "BOSS 日冕读数已创建")
	boss._seed_respawn_left = 0.0
	boss._tick_seed(0.01)
	_check(boss._seed != null and is_instance_valid(boss._seed), "天火种已生成")
	var seed: SunSeed = boss._seed
	_check(seed.is_free() or seed.holder != null, "火种已落地或已被拾取")
	seed.drop(sp.global_position)
	seed._claim_lock = 0.0
	seed._tick_free()
	_check(seed.holder == sp, "玩家靠近自动拾取火种")
	seed.stacks = 2
	boss._tick_seed(0.01)
	_check(boss._sun_stacks == 0, "火种在玩家手里时 BOSS 日冕为 0")
	seed.steal_by(boss)
	boss._tick_seed(0.01)
	_check(boss._sun_stacks == 2, "BOSS 夺火后继承层数")
	_check(boss._sun_pips.visible, "BOSS 日冕读数显示")
	_check(boss._sun_pips.lit == 2, "BOSS 日冕读数 = 2 层")
	_check(is_equal_approx(boss.damage_taken_multiplier("physical"), 0.85),
		"BOSS 持种时减伤 15%")
	boss._sun_stacks = 0
	seed.drop(Vector2(120.0, 0.0))
	seed.set_claim_lock(0.0)
	var b2 := MoveDB.resolve_boss("form_sun_throw")
	_check(bool(b2.get("requires_seed", false)), "投日表单登记 requires_seed")
	# 火种在手里时投日：火种落地 + 延迟出伤
	seed.steal_by(boss)
	seed.stacks = 2
	boss._sun_stacks = 2
	sp.hits.clear()
	boss._cast_throw(b2)
	_check(seed.is_free(), "投日后火种落地")
	await get_tree().create_timer(0.35).timeout
	_check(sp.hits.size() >= 1, "投日命中玩家", "hits=%d" % sp.hits.size())
	# BOSS 夺玩家身的火：逐日步（近身接触）/ 牵日（420 远程）/ 焚风（掀落）
	var b_step := MoveDB.resolve_boss("form_sun_step")
	var b_pull := MoveDB.resolve_boss("form_sun_pull")
	var b_wind := MoveDB.resolve_boss("form_sun_wind")
	_check(int(b_step.get("steal_range", 0)) == 130, "逐日步夺火半径取自数据表")
	boss.global_position = Vector2.ZERO
	boss.facing = Vector2.RIGHT
	seed.steal_by(sp)
	seed.stacks = 1
	boss._cast_step(b_step)
	for i in 2:
		boss._tick_step(0.1)
	_check(seed.holder == boss, "BOSS 逐日步从玩家手里夺火")
	seed.steal_by(sp)
	boss.global_position = Vector2.ZERO
	boss._cast_pull(b_pull)
	await get_tree().create_timer(0.40).timeout
	_check(seed.holder == boss, "BOSS 牵日从玩家手里远程夺火")
	seed.steal_by(sp)
	boss._cast_wind(b_wind)
	_check(seed.is_free(), "BOSS 焚风把玩家手里的火种掀落")
	_check(seed.global_position.distance_to(sp.global_position) > 60.0, "掀落后火种被吹开")
	# 反风筝：玩家远距离持种、日蚀/逐日步/焚风都在冷却 → AI 用牵日远程抢
	seed.steal_by(sp)
	sp.global_position = Vector2(400.0, 0.0)
	boss.global_position = Vector2.ZERO
	boss._cools["form_sun_eclipse"] = 6.0
	boss._cools["form_sun_step"] = 6.0
	boss._cools["form_sun_wind"] = 6.0
	boss._cools.erase("form_sun_pull")
	boss._decide_wait = 0.0
	boss.state = BossBase.BossState.IDLE
	boss._choose()
	_check(String(boss._current_skill) == "form_sun_pull", "远距持种时 AI 选牵日抢火", str(boss._current_skill))
	boss.state = BossBase.BossState.IDLE
	boss._current_skill = ""
	boss._cools.clear()
	boss.global_position = Vector2.ZERO
	sp.global_position = Vector2(220.0, 0.0)
	boss._sun_stacks = 0
	seed.drop(Vector2(120.0, 0.0))
	seed.set_claim_lock(0.0)
	# 四招都能躲：走位离开判定形状 → 火种既不会被夺也不会被掀/烧掉
	seed.steal_by(sp)
	boss.global_position = Vector2.ZERO
	sp.global_position = Vector2(220.0, 0.0)
	boss.state = BossBase.BossState.IDLE
	boss._begin("form_sun_step")
	_check(boss._step_anchor_ready, "逐日步前摇第一帧就钉死落点")
	sp.global_position = Vector2(220.0, 260.0)
	boss._fire_skill()
	for i in 2:
		boss._tick_step(0.1)
	_check(seed.holder == sp, "躲出落点圆 → 逐日步夺火落空")
	_check(boss.global_position.distance_to(boss._step_target) < 4.0, "扑空仍然落在钉死的落点")
	boss._step_anchor_ready = false
	boss.global_position = Vector2.ZERO
	boss.facing = Vector2.RIGHT
	sp.global_position = Vector2(300.0, 130.0)
	boss._cast_pull(b_pull)
	await get_tree().create_timer(0.40).timeout
	_check(seed.holder == sp, "侧移躲开金丝走廊 → 牵日没拉住")
	sp.global_position = Vector2(100.0, 180.0)
	boss._cast_wind(b_wind)
	_check(seed.holder == sp, "绕到扇形外 → 焚风掀不掉火种")
	# 60° 掀种窗口：偏 35° 只吃伤害不丢火，偏 27° 才会被掀
	sp.global_position = Vector2(200.0, 140.0)
	boss._cast_wind(b_wind)
	_check(seed.holder == sp, "偏 35° 在掀种窗口外 → 焚风掀不掉火种")
	sp.global_position = Vector2(200.0, 100.0)
	boss._cast_wind(b_wind)
	_check(seed.is_free(), "偏 27° 在掀种窗口内 → 火种被掀落")
	seed.steal_by(sp)
	seed.global_position = sp.global_position
	sp.global_position = Vector2(200.0, 0.0)
	boss._cast_eclipse(MoveDB.resolve_boss("form_sun_eclipse"))
	sp.global_position = Vector2(200.0, 200.0)
	await get_tree().create_timer(0.62).timeout
	_check(seed.holder == sp, "跨出黑日预警圈 → 日蚀没烧掉火种")
	# 只按 0.55 秒的纯步行距离撤（约 121 像素）也要保得住火种
	sp.global_position = Vector2(200.0, 0.0)
	boss._cast_eclipse(MoveDB.resolve_boss("form_sun_eclipse"))
	sp.global_position = Vector2(200.0, 121.0)
	await get_tree().create_timer(0.72).timeout
	_check(seed.holder == sp, "撤出一步步行距离 → 日蚀烧不掉火种")
	# 连续两次夺火落空 → 火忌 6 秒：四招抢火全部哑火，伤害照常
	_check(boss.has_debuff("sun_fire_ban"), "连续两次夺火落空 → 火忌")
	_check(not DebuffDB.get_debuff("sun_fire_ban").is_empty(), "火忌已登记 debuff 表")
	boss._cools.clear()
	_check(not boss._ready_cd("form_sun_step"), "火忌期间逐日步被锁")
	_check(not boss._ready_cd("form_sun_pull"), "火忌期间牵日被锁")
	_check(not boss._ready_cd("form_sun_wind"), "火忌期间焚风被锁")
	_check(not boss._ready_cd("form_sun_eclipse"), "火忌期间日蚀被锁")
	_check(boss._ready_cd("form_sun_slash"), "火忌只锁抢火四招，日冕斩照常")
	_check(boss._ready_cd("form_sun_throw"), "火忌期间投日照常")
	_check(boss._ready_cd("form_sun_meteor"), "火忌期间天火坠照常")
	# 中间只要成功抢到一次，连续计数就清零（落空·命中·落空 不该上火忌）
	boss.remove_debuff("sun_fire_ban")
	boss._grab_whiffs = 0
	boss._seed_whiff("逐日步", "测试")
	boss._grab_landed()
	boss._seed_whiff("逐日步", "测试")
	_check(not boss.has_debuff("sun_fire_ban") and boss._grab_whiffs == 1,
		"成功夺火会打断连续落空计数", "streak=%d" % boss._grab_whiffs)
	boss.remove_debuff("sun_fire_ban")
	boss._grab_whiffs = 0
	boss.global_position = Vector2.ZERO
	boss._sun_stacks = 0
	seed.drop(Vector2(120.0, 0.0))
	seed.set_claim_lock(0.0)
	# 满层爆裂：BOSS 吃 6% 最大气血，火种消失并进入重生计时
	var burst_seed := SunSeed.new()
	add_child(burst_seed)
	burst_seed.global_position = boss.global_position
	burst_seed.steal_by(boss)
	burst_seed.stacks = 3
	boss.on_sun_seed_full(burst_seed)
	var hp_before: float = boss.current_hp
	burst_seed._burst_on_holder()
	_check(boss.current_hp < hp_before, "满层火种爆裂伤到 BOSS",
		"%.0f -> %.0f" % [hp_before, boss.current_hp])
	_check(burst_seed.state == SunSeed.State.GONE, "爆裂后火种销毁")

	# 二阶段转招
	boss._on_phase_two()
	_check(boss._phase_two, "进入二阶段")
	_check(float(boss._cools.get("form_sun_meteor", 1.0)) <= 0.0, "二阶段天火坠解禁")
	boss._seed_respawn_left = 0.0
	boss._tick_seed(0.01)
	_check(boss._seed != null, "火种重生")
	# 自主模拟：9 秒内至少 3 招
	boss.state = 0
	boss.set_physics_process(true)
	boss._decide_wait = 0.0
	await get_tree().create_timer(9.0).timeout
	_check(boss._recent.size() >= 3, "BOSS 自主模拟出招 >= 3", str(boss._recent))
	await _test_boss_casts(boss, sp)
	boss.set_physics_process(false)
	boss.queue_free()
	sp.queue_free()
	await get_tree().process_frame


func _test_boss_casts(boss, sp) -> void:
	# 把八式 BOSS 侧全部走一遍：主要抓延迟回调 / 火种状态错位的运行期错误
	boss.set_physics_process(false)
	boss.target = sp
	for sid in ["form_sun_slash", "form_sun_wind", "form_sun_wheel",
			"form_sun_eclipse", "form_sun_meteor", "form_sun_throw",
			"form_sun_pull", "form_sun_step"]:
		_clear_seeds()
		await get_tree().process_frame
		var s := SunSeed.new()
		add_child(s)
		s.global_position = boss.global_position
		if sid == "form_sun_throw":
			s.steal_by(boss)
			s.stacks = 1
		elif sid in ["form_sun_pull", "form_sun_eclipse"]:
			s.steal_by(sp)
		else:
			s.set_claim_lock(9.0)
		boss._seed = s
		boss.state = 0
		boss.state_timer = 0.0
		boss._current_skill = sid
		boss._fire_skill()
		if sid == "form_sun_step":
			boss._tick_step(0.2)
		await get_tree().create_timer(0.8, true, false, true).timeout
	_check(true, "BOSS 八式 cast 全路径已跑通")


func _test_player() -> void:
	# 清掉 BOSS 测试留下的火种，保证玩家侧从「场上无火种」开始
	_clear_seeds()
	await get_tree().process_frame
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector2.ZERO
	p.set_physics_process(false)
	p.set_process(false)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	var ids := ["skill_sun_step", "skill_sun_slash", "skill_sun_throw", "skill_sun_pull",
		"skill_sun_wind", "skill_sun_eclipse", "skill_sun_wheel", "skill_sun_meteor"]
	for sid in ids:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if String(sid) == "skill_sun_wheel":
			if not CharacterData.passive_skill_loadout.has(sid):
				CharacterData.passive_skill_loadout.append(sid)
		elif not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	p._refresh_sun_unlock()
	_check(bool(p._sun_unlocked), "学会逐日功法后日冕条解锁")
	_check(p._sun_pips != null and is_instance_valid(p._sun_pips), "玩家日冕 HUD 已创建")
	var boss := DummyBoss.new()
	boss.add_to_group("boss")
	boss.global_position = Vector2(220.0, 0.0)
	add_child(boss)
	var seed := SunSeed.new()
	add_child(seed)
	seed.global_position = p.global_position
	seed.set_claim_lock(0.0)
	seed.pickup(p)
	seed.stacks = 2
	p._tick_sun(0.0)
	_check(p._sun_step_dir(Vector2.ZERO, Vector2.DOWN).dot(Vector2.RIGHT) > 0.9,
		"持种 / 无输入时逐日步朝 BOSS")
	_check(p._sun_step_dir(Vector2.LEFT, Vector2.RIGHT).is_equal_approx(Vector2.LEFT),
		"有方向输入时逐日步优先按输入")
	_check(p.sun_stacks == 2, "玩家持种同步日冕层数", "n=%d" % p.sun_stacks)
	_check(p._sun_pips.visible, "日冕条显示")
	_check(p.has_buff("sun_crown"), "日冕 buff 已挂")
	var mult_with := CharacterData.sun_damage_mult
	_check(is_equal_approx(mult_with, 1.24), "日冕每层 +12%（2 层 = ×1.24）", "x%.2f" % mult_with)
	var non_fire_with := CharacterData.calc_skill_damage("skill_tiger_claw", false, false)
	seed.stacks = 3
	seed._unstable_left = 999.0
	p._tick_sun(0.0)
	_check(p.has_debuff("sunburn"), "满层后灼心")
	_check(is_equal_approx(CharacterData.sun_damage_mult, 1.36), "日冕 3 层 = ×1.36",
		"x%.2f" % CharacterData.sun_damage_mult)
	# 日冕焚心：满 3 层蓄 1 次引燃；下一次逐日功法命中后 1 秒，目标体内爆 2.0×法强火伤
	_check(bool(p._sun_nova_charge), "日冕满 3 层蓄引燃")
	_check(is_equal_approx(p._sun_nova_mult, 1.36), "引燃快照满层日冕乘区",
		"x%.2f" % p._sun_nova_mult)
	boss.hits.clear()
	boss.elements.clear()
	p.skill_cooldowns["skill_sun_step"] = 4.0
	p._sun_handle_cast("skill_sun_slash", Vector2.RIGHT)
	_check(boss.hits.size() == 1, "日冕斩先造成本招伤害", "hits=%d" % boss.hits.size())
	_check(not p._sun_nova_charge, "逐日功法命中后引燃已消费")
	_check(p._sun_nova_marker != null and is_instance_valid(p._sun_nova_marker),
		"目标体内引燃标记已生成")
	var nova_hits := boss.hits.size()
	await get_tree().create_timer(0.55).timeout
	_check(boss.hits.size() == nova_hits, "引燃 1 秒内不提前爆",
		"hits=%d" % boss.hits.size())
	await get_tree().create_timer(0.55).timeout
	_check(boss.hits.size() == nova_hits + 1, "满 1 秒后体内爆出一次",
		"hits=%d" % boss.hits.size())
	if boss.hits.size() >= nova_hits + 1:
		_check(String(boss.elements[-1]) == "fire", "引燃是火系伤害",
			str(boss.elements[-1]))
		var exp_nova: float = p._sun_nova_damage(p._sun_nova_mult)
		var got_nova := float(boss.hits[-1])
		_check(absf(got_nova - exp_nova) / maxf(1.0, exp_nova) < 0.15,
			"引燃伤害 = 2.0×法强×日冕", "%.1f / %.1f" % [got_nova, exp_nova])
		var base_nova: float = p._sun_nova_damage(1.0)
		_check(absf(base_nova / maxf(1.0, CharacterData.spell_attack()) - 2.0) < 0.12,
			"引燃基础系数 = 2.0×法强",
			"%.1f / %.1f" % [base_nova, CharacterData.spell_attack()])
		_check(not p.skill_cooldowns.has("skill_sun_step"), "引燃炸到敌人刷新逐日步 CD")
		_check(p.sun_stacks == 2 and seed.stacks == 2, "引燃消耗 1 层日冕",
			"player=%d seed=%d" % [p.sun_stacks, seed.stacks])
	# 引爆后不重新叠满不再触发
	boss.hits.clear()
	p._sun_handle_cast("skill_sun_slash", Vector2.RIGHT)
	await get_tree().create_timer(1.15).timeout
	_check(boss.hits.size() == 1, "未重新叠满不再触发引燃", "hits=%d" % boss.hits.size())
	# 掉层再叠满 → 投日也能触发：火种先脱手，引燃不该在延迟出伤前被清掉
	seed.stacks = 2
	p._tick_sun(0.0)
	seed.stacks = 3
	seed._unstable_left = 999.0
	p._tick_sun(0.0)
	_check(bool(p._sun_nova_charge), "掉层再叠满重新蓄引燃")
	boss.hits.clear()
	boss.elements.clear()
	p._sun_handle_cast("skill_sun_throw", Vector2.RIGHT)
	await get_tree().create_timer(0.40).timeout
	_check(boss.hits.size() >= 1, "投日先造成本招伤害", "hits=%d" % boss.hits.size())
	_check(not p._sun_nova_charge, "投日命中后引燃已消费")
	await get_tree().create_timer(1.0).timeout
	_check(boss.hits.size() >= 2, "引燃挂到投日命中的目标上", "hits=%d" % boss.hits.size())
	_check(seed.stacks == 2, "脱手火种也消耗 1 层日冕", "seed=%d" % seed.stacks)
	seed.steal_by(p)
	p._tick_sun(0.0)
	_check(p.sun_stacks == 2, "重新捡起原来的火后日冕少一层", "n=%d" % p.sun_stacks)
	seed.drop(Vector2(0.0, 100.0))
	p._tick_sun(0.0)
	_check(p._sun_step_dir(Vector2.ZERO, Vector2.RIGHT).dot(Vector2.DOWN) > 0.9,
		"无输入 / 场上有火种时逐日步朝火种")
	_check(p.sun_stacks == 0, "落地后日冕清零")
	_check(not p.has_buff("sun_crown"), "落地后日冕 buff 移除")
	_check(is_equal_approx(CharacterData.sun_damage_mult, 1.0), "落地后全伤害倍率回落")
	_check(mult_with > 1.0, "持种时全伤害倍率 >1", "x%.2f" % mult_with)
	var non_fire_without := CharacterData.calc_skill_damage("skill_tiger_claw", false, false)
	_check(non_fire_with > non_fire_without, "持种加成作用到非火功法",
		"持种 %.1f / 丢种 %.1f" % [non_fire_with, non_fire_without])
	# 盗火者被动：无种时自动凝种；消耗后再凝
	# （DummyBoss 声明会抢种；这里临时关掉，模拟「其他关卡」的携带场景）
	boss.uses_sun = false
	seed.queue_free()
	await get_tree().process_frame
	_check(p._find_sun_seed() == null, "被动凝种前场上无火种")
	p._sun_bearer_respawn_left = 0.0
	p._tick_sun_bearer(0.01)
	await get_tree().process_frame
	var made: SunSeed = p._find_sun_seed()
	_check(made != null, "盗火者被动在无种时凝出一枚")
	if made != null:
		made.consume()
		await get_tree().process_frame
		p._tick_sun_bearer(1.6)
		await get_tree().process_frame
		made = p._find_sun_seed()
		_check(made != null, "火种消耗后盗火者再凝一枚")
	# 投日：从玩家手里扔向目标
	if made != null:
		made.steal_by(p)
		made.stacks = 1
		p._tick_sun(0.0)
		boss.hits.clear()
		p._sun_handle_cast("skill_sun_throw", Vector2.RIGHT)
		_check(made.is_free(), "玩家投日后火种落地")
		await get_tree().create_timer(0.35).timeout
		_check(boss.hits.size() >= 1, "玩家投日命中 BOSS", "hits=%d" % boss.hits.size())
	# 牵日：BOSS 持种 → 玩家夺火
	_clear_seeds()
	await get_tree().process_frame
	boss.uses_sun = true
	var seed2 := SunSeed.new()
	add_child(seed2)
	seed2.global_position = boss.global_position
	seed2.steal_by(boss)
	p._sun_handle_cast("skill_sun_pull", Vector2.RIGHT)
	await get_tree().create_timer(0.3).timeout
	_check(seed2.holder == p, "牵日从 BOSS 手里夺火")
	# 牵日要真的扫中持种者：偏出走廊就拉不住
	seed2.steal_by(boss)
	boss.global_position = Vector2(220.0, 160.0)
	seed2.global_position = boss.global_position
	p._sun_handle_cast("skill_sun_pull", Vector2.RIGHT)
	await get_tree().create_timer(0.3).timeout
	_check(seed2.holder == boss, "牵日偏出走廊 → 拉不住")
	boss.global_position = Vector2(220.0, 0.0)
	# 日蚀：玩家持种 → 向前掷出并引爆
	seed2.steal_by(p)
	boss.hits.clear()
	p._sun_handle_cast("skill_sun_eclipse", Vector2.RIGHT)
	_check(not seed2.is_inside_tree() or seed2.state == SunSeed.State.GONE, "日蚀消耗火种")
	await get_tree().create_timer(0.55).timeout
	_check(boss.hits.size() >= 1, "日蚀命中 BOSS", "hits=%d" % boss.hits.size())
	# 天火坠：火种与目标各落一发（同处叠双倍）
	_clear_seeds()
	await get_tree().process_frame
	var seed3 := SunSeed.new()
	add_child(seed3)
	seed3.global_position = boss.global_position
	seed3.set_claim_lock(0.0)
	boss.hits.clear()
	p._sun_handle_cast("skill_sun_meteor", Vector2.RIGHT)
	await get_tree().create_timer(0.65).timeout
	_check(boss.hits.size() >= 2, "天火坠火种+目标双落点叠击", "hits=%d" % boss.hits.size())
	if boss.hits.size() >= 2:
		_check(is_equal_approx(float(boss.hits[0]), float(boss.hits[1])),
			"双落点伤害相同", "%.1f / %.1f" % [float(boss.hits[0]), float(boss.hits[1])])
	# 火种远离目标：只有目标圈命中
	_clear_seeds()
	await get_tree().process_frame
	var seed_far := SunSeed.new()
	add_child(seed_far)
	seed_far.global_position = Vector2(900.0, 0.0)
	seed_far.set_claim_lock(0.0)
	boss.hits.clear()
	p._sun_handle_cast("skill_sun_meteor", Vector2.RIGHT)
	await get_tree().create_timer(0.65).timeout
	_check(boss.hits.size() == 1, "火种远离时只有目标圈命中", "hits=%d" % boss.hits.size())

	# 火种飞行：投日/掀种不是瞬移，沿弧线落地
	_clear_seeds()
	await get_tree().process_frame
	var flying := SunSeed.new()
	add_child(flying)
	flying.global_position = Vector2(600.0, 200.0)
	flying.fly_to(Vector2(800.0, 200.0), 0.2, 40.0)
	_check(flying.global_position.distance_to(Vector2(600.0, 200.0)) < 12.0,
		"火种飞行起点不瞬移")
	await get_tree().create_timer(0.1).timeout
	var mid := flying.global_position
	_check(mid.x > 615.0 and mid.x < 785.0 and mid.y < 195.0,
		"火种飞行中点沿弧线", "mid=%s" % str(mid))
	await get_tree().create_timer(0.15).timeout
	_check(flying.global_position.distance_to(Vector2(800.0, 200.0)) < 2.0,
		"火种飞行落点准确", "pos=%s" % str(flying.global_position))
	flying.queue_free()
	await get_tree().process_frame

	# 无种基础版：三招都不再被火种门禁卡死
	_clear_seeds()
	await get_tree().process_frame
	p._sun_seed = null
	p._tick_sun(0.0)
	boss.hits.clear()
	p._sun_handle_cast("skill_sun_throw", Vector2.RIGHT)
	await get_tree().create_timer(0.12).timeout
	_check(boss.hits.size() >= 1, "无种投日仍能命中", "hits=%d" % boss.hits.size())
	_clear_seeds()
	await get_tree().process_frame
	p._sun_seed = null
	boss.hits.clear()
	p._sun_handle_cast("skill_sun_eclipse", Vector2.RIGHT)
	await get_tree().create_timer(0.55).timeout
	_check(boss.hits.size() >= 1, "无种日蚀仍能命中", "hits=%d" % boss.hits.size())
	_clear_seeds()
	await get_tree().process_frame
	p._sun_seed = null
	boss.hits.clear()
	p._sun_handle_cast("skill_sun_pull", Vector2.RIGHT)
	await get_tree().create_timer(0.12).timeout
	_check(boss.hits.size() >= 1, "无种牵日仍能造成伤害", "hits=%d" % boss.hits.size())

	# 玩家侧同样「打中才算」：焚风要扫到、逐日步要撞上，才掀得动 / 夺得到
	_clear_seeds()
	await get_tree().process_frame
	boss.uses_sun = true
	boss.global_position = Vector2(220.0, 0.0)
	var seed_sym := SunSeed.new()
	add_child(seed_sym)
	seed_sym.global_position = boss.global_position
	seed_sym.steal_by(boss)
	seed_sym.set_claim_lock(0.0)
	p._tick_sun(0.0)
	_check(seed_sym.holder == boss, "测试前提：BOSS 持种")
	p._sun_handle_cast("skill_sun_wind", Vector2.LEFT)
	_check(seed_sym.holder == boss, "玩家焚风朝反方向 → 掀不掉 BOSS 的火")
	boss.knockbacks.clear()
	p._sun_handle_cast("skill_sun_wind", Vector2.RIGHT)
	_check(seed_sym.is_free(), "玩家焚风扫到 → 火种被掀落")
	_check(not boss.knockbacks.is_empty(), "玩家焚风命中 BOSS → 触发击退",
		"kb=%d" % boss.knockbacks.size())
	_check(seed_sym.global_position.distance_to(boss.global_position) >= SunSeed.BOSS_STOP_RADIUS - 1.0,
		"掀种从 BOSS 边缘起飞，不穿身",
		"d=%.1f" % seed_sym.global_position.distance_to(boss.global_position))
	seed_sym.steal_by(boss)
	seed_sym.global_position = boss.global_position
	boss.global_position = Vector2(240.0, 0.0)
	p._tick_sun(0.0)
	p._sun_handle_cast("skill_sun_step", Vector2.RIGHT)
	_check(seed_sym.holder == boss, "玩家逐日步没打中 → 夺不到火")
	boss.global_position = Vector2(90.0, 0.0)
	seed_sym.global_position = boss.global_position
	p._tick_sun(0.0)
	p._sun_handle_cast("skill_sun_step", Vector2.RIGHT)
	_check(seed_sym.holder == p, "玩家逐日步打中 → 从 BOSS 手里夺火")
	# 焚风持续 0.3 秒：起手后才进入扇面的火种也会被掀飞
	_clear_seeds()
	await get_tree().process_frame
	boss.global_position = Vector2(220.0, 160.0)
	var late_seed := SunSeed.new()
	add_child(late_seed)
	late_seed.global_position = Vector2(0.0, -200.0)
	late_seed.set_claim_lock(1.0)
	p._sun_handle_cast("skill_sun_wind", Vector2.RIGHT)
	await get_tree().create_timer(0.08).timeout
	_check(late_seed.global_position.distance_to(Vector2(0.0, -200.0)) < 2.0,
		"焚风起手时火种不在扇面 → 未掀")
	late_seed.global_position = Vector2(150.0, 0.0)
	await get_tree().create_timer(0.45).timeout
	_check(late_seed.global_position.x > 540.0, "焚风持续期内进入扇面 → 后到也掀飞更远",
		"pos=%s" % str(late_seed.global_position))
	# 火种撞到 BOSS 会停下
	_clear_seeds()
	await get_tree().process_frame
	boss.global_position = Vector2(220.0, 0.0)
	boss.uses_sun = false
	var collide_seed := SunSeed.new()
	add_child(collide_seed)
	collide_seed.global_position = Vector2(100.0, 0.0)
	collide_seed.set_claim_lock(1.0)
	collide_seed.fly_to(Vector2(400.0, 0.0), 0.30, 30.0)
	await get_tree().create_timer(0.35).timeout
	_check(collide_seed.global_position.x > 150.0 and collide_seed.global_position.x < 200.0,
		"火种撞到 BOSS 前停下", "x=%.1f" % collide_seed.global_position.x)
	_check(not collide_seed._flying, "撞停后结束飞行")
	# 高抛物线也不能从 BOSS 头顶飞过去（碰撞按地面投影）
	_clear_seeds()
	await get_tree().process_frame
	boss.global_position = Vector2(200.0, 0.0)
	boss.uses_sun = false
	var arc_seed := SunSeed.new()
	add_child(arc_seed)
	arc_seed.global_position = Vector2(0.0, 0.0)
	arc_seed.set_claim_lock(1.0)
	arc_seed.fly_to(Vector2(400.0, 0.0), 0.40, 80.0)
	await get_tree().create_timer(0.50).timeout
	_check(arc_seed.global_position.x < 200.0, "高弧线火种不会从 BOSS 头顶飞过",
		"x=%.1f" % arc_seed.global_position.x)
	_check(not arc_seed._flying, "高弧线撞 BOSS 后结束飞行")
	# 90° 扇面：偏 35° 的火种也能掀
	_clear_seeds()
	await get_tree().process_frame
	boss.uses_sun = true
	boss.global_position = Vector2(150.0, 105.0)
	var wide_seed := SunSeed.new()
	add_child(wide_seed)
	wide_seed.global_position = boss.global_position
	wide_seed.steal_by(boss)
	wide_seed.set_claim_lock(0.0)
	p._sun_handle_cast("skill_sun_wind", Vector2.RIGHT)
	_check(wide_seed.is_free(), "火种偏 35° 仍在 90° 扇面 → 掀落")
	boss.uses_sun = false
	boss.global_position = Vector2(220.0, 0.0)
	_clear_seeds()
	await get_tree().process_frame

	# 真实入口 try_use_skill：无种也能放；主动日轮已改为被动
	_clear_seeds()
	await get_tree().process_frame
	p._tick_sun(0.0)
	p.mana = 999.0
	p.stamina = 9
	var no_seed_ok: bool = p.try_use_skill("skill_sun_throw")
	_check(no_seed_ok, "无火种时投日也可通过 try_use_skill（基础版）")
	var seed4 := SunSeed.new()
	add_child(seed4)
	seed4.global_position = p.global_position
	seed4.set_claim_lock(0.0)
	seed4.pickup(p)
	p._tick_sun(0.0)
	p.skill_cooldowns.clear()
	var throw_ok: bool = p.try_use_skill("skill_sun_throw")
	_check(throw_ok, "持种时投日可通过 try_use_skill")
	await get_tree().create_timer(0.55).timeout
	# 被动「盗火者」不在主动槽；旧主动入口必须拒绝
	_clear_seeds()
	await get_tree().process_frame
	p.skill_cooldowns.clear()
	p.mana = 999.0
	var wheel_ok: bool = p.try_use_skill("skill_sun_wheel")
	_check(not wheel_ok, "主动日轮入口已关闭（被动不再占主动槽）")

	# 玩家满层爆裂：掉 12% 气血并清种
	_clear_seeds()
	await get_tree().process_frame
	var ps := SunSeed.new()
	add_child(ps)
	ps.pickup(p)
	ps.stacks = 3
	p._tick_sun(0.0)
	var php0: float = p.hp
	ps._unstable_left = 0.01
	ps._tick_held(0.02)
	_check(p.hp < php0, "玩家满层爆裂掉血", "%.0f -> %.0f" % [php0, p.hp])
	_check(ps.state == SunSeed.State.GONE, "玩家爆裂后火种销毁")


func _test_resolve() -> void:
	CharacterData.current_realm = "结丹"
	CharacterData.realm_stage = 0
	CharacterData.realm_exp = 0
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03_b",
	}
	var res := BattleResolver.resolve_victory()
	_check(String(res.get("message", "")).contains("修为 +500"),
		"位面 03 第二位首杀给 500 修为", String(res.get("message", "")))
	_check(bool((CharacterData.boss_progress.get("boss_03_b", {}) as Dictionary).get("killed", false)),
		"位面 03 记录离照击杀")
	GameState.battle_context = {}
