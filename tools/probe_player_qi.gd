extends Node2D
## 玩家侧气君八式对齐自检（2026-10-28）：环身气 / SkillFx / 八式 / 吐纳引导

class DummyBoss extends Node2D:
	var hits: Array = []
	var debuffs: Array = []
	var knockbacks: Array = []
	var kinds: Array = []
	var slows: Array = []
	var skill_locks: Array = []
	var radius := 20.0
	func take_damage(amount: float, _source: Node = null, kind: String = "physical",
			_element: String = "", _from_projectile: bool = false) -> void:
		hits.append(amount)
		kinds.append(kind)
	func apply_debuff(id: String, duration: float) -> bool:
		debuffs.append([id, duration])
		return true
	func take_knockback(impulse: Vector2) -> void:
		knockbacks.append(impulse)
	func apply_slow(mult: float, seconds: float) -> void:
		slows.append([mult, seconds])
	func apply_skill_lock(seconds: float) -> void:
		skill_locks.append(seconds)
	func hit_radius() -> float:
		return radius
	func edge_distance_to(world_pos: Vector2) -> float:
		return maxf(0.0, global_position.distance_to(world_pos) - radius)

var _p: Node2D
var _b: DummyBoss
var _fails: Array = []
var _passes := 0

func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)

func _count_fx(cls: String) -> int:
	var n := 0
	for c in get_children():
		var sc = c.get_script()
		if sc is Script and String((sc as Script).resource_path).contains(cls):
			n += 1
	return n

func _ready() -> void:
	print("\n########## 玩家侧气君八式对齐探针 ##########")
	await get_tree().process_frame
	_b = DummyBoss.new()
	_b.add_to_group("boss")
	_b.global_position = Vector2(120.0, 0.0)
	add_child(_b)
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	_p.global_position = Vector2.ZERO
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.is_teleporting = false
	_p.invincible_timer = 0.0
	_p.auto_parry_timer = 0.0
	for sid in ["skill_qi_gather", "skill_qi_wave", "skill_qi_spin", "skill_qi_lock",
			"skill_qi_ward", "skill_qi_step", "skill_qi_burst", "skill_qi_breath"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	# 回血被动：先学会但不穿，验证「不戴不回血」
	if not CharacterData.learned_skills.has("skill_qi_ring_heal"):
		CharacterData.learned_skills.append("skill_qi_ring_heal")
	CharacterData.passive_skill_loadout.erase("skill_qi_ring_heal")
	_p._refresh_qi_unlock()
	_run()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _run() -> void:
	var p = _p
	var b = _b
	# 回血被动登记与获取池
	var gate := SkillDB.get_passive_by_effect("qi_ring_leech")
	_check(String(gate.get("skill_id", "")) == "skill_qi_ring_heal", "气环·回息被动登记")
	_check(WorldDB.get_floor_reward_skills(6).has("skill_qi_ring_heal"),
		"气环·回息在塔 6 层感悟池")
	# 被动槽只有 1 格；旧档多带的只保留第一门
	_check(SkillPanel.MAX_PASSIVE == 1 and CharacterData.MAX_PASSIVE_SKILLS == 1,
		"被动功法只能带 1 门")
	var saved_passives: Array = CharacterData.passive_skill_loadout.duplicate()
	CharacterData.passive_skill_loadout = [
		"skill_yinyang_harmony", "skill_sun_wheel", "skill_qi_ring_heal",
	]
	CharacterData.trim_passive_loadout()
	_check(CharacterData.passive_skill_loadout == ["skill_yinyang_harmony"],
		"旧档多带被动只留第一门", str(CharacterData.passive_skill_loadout))
	CharacterData.passive_skill_loadout = saved_passives
	# 环身气
	p._refresh_qi_hud()
	_check(true, "HUD 刷新无异常（只刷环身气）")
	_check(p.qi_rings == 0, "初始 0 环")
	p._add_qi(2)
	p._tick_qi_rings(0.016)
	_check(p.qi_rings == 2, "聚 2 环", "qi=%d" % p.qi_rings)
	_check(p._qi_ring_nodes.size() == 5, "世界层 5 个环槽", "n=%d" % p._qi_ring_nodes.size())
	var vis := 0
	for spr in p._qi_ring_nodes:
		if is_instance_valid(spr) and spr.visible:
			vis += 1
	_check(vis == 2, "只亮有气的两枚环", "vis=%d" % vis)
	# 环身气接触：只留 1 枚环，把 boss 摆到 0 号环心 → 碰一次结算一次
	# 回血要佩戴被动「气环·回息」；这里先不穿，验证只伤敌不回血
	p.qi_rings = 1
	p._refresh_qi_hud()
	p._tick_qi_rings(0.016)
	b.global_position = p.global_position + (p._qi_ring_nodes[0] as Sprite2D).position
	p.hp = p.max_hp * 0.5
	var ring_hp0: float = p.hp
	b.hits.clear(); b.kinds.clear(); b.debuffs.clear()
	# ⚠ 两个坑（2026-11-08 回归连挂 5 项）：
	#   ① _tick_qi_rings() 的环相位走 Time.get_ticks_msec() 真实时钟，手动 tick 之间
	#      夹着别的断言时环心会漂移 → 这里只跑 _tick_qi_ring_contacts()，不推进相位。
	#   ② 前面的步骤里 boss 初始位置 (120,0) 可能已经被记进 _qi_ring_contacts，
	#      于是这次「新接触」被当成持续接触，静默不结算 → 必须先清空接触集合。
	#   游戏里 60fps 每帧位移 ~1px < 36 判定半径，两个问题都不会出现。
	p._qi_ring_contacts.clear()
	p._tick_qi_ring_contacts()
	_check(b.hits.size() == 1, "气环碰到的敌人结算一次伤害", "hits=%d" % b.hits.size())
	_check(b.kinds.size() == 1 and String(b.kinds[0]) == "elemental",
		"气环伤害走法术伤害", str(b.kinds))
	_check(not p._qi_ring_leech_equipped() and absf(p.hp - ring_hp0) < 0.01,
		"未戴被动气环不回血", "hp=%.2f→%.2f" % [ring_hp0, p.hp])
	_check(not b.debuffs.is_empty() and String(b.debuffs[0][0]) == "qi_stagnation",
		"气环接触挂滞气", str(b.debuffs))
	# 同一段接触：环继续绕、boss 不动，不再重复结算。
	# ⚠ 每次判定前把 boss 重新对齐到「当前」环心：批量跑探针时负载抖动可能让
	#   真实时钟相位在这几行之间被别处推进一点，不重对齐就会偶发漏判。
	b.global_position = p.global_position + (p._qi_ring_nodes[0] as Sprite2D).position
	p._tick_qi_ring_contacts()
	_check(b.hits.size() == 1, "同一次接触只结算一次", "hits=%d" % b.hits.size())
	# 离开后穿上被动，再回来 = 新的一次接触 + 10% 回血
	b.global_position = Vector2(600.0, 0.0)
	p._tick_qi_ring_contacts()
	CharacterData.passive_skill_loadout.append("skill_qi_ring_heal")
	p.hp = p.max_hp * 0.5
	var ring_hp1: float = p.hp
	b.global_position = p.global_position + (p._qi_ring_nodes[0] as Sprite2D).position
	p._tick_qi_ring_contacts()
	_check(p._qi_ring_leech_equipped(), "佩戴气环·回息后被动生效")
	_check(b.hits.size() == 2, "离开后再次碰到可再次结算", "hits=%d" % b.hits.size())
	if b.hits.size() >= 2:
		var healed: float = p.hp - ring_hp1
		var expect_heal: float = float(b.hits[1]) * 0.10
		_check(absf(healed - expect_heal) < 0.05, "佩戴后接触伤害的 10% 回血",
			"healed=%.2f expect=%.2f" % [healed, expect_heal])
	# 把 boss 放回中距离，气环收回 2 枚给后面的招式用
	b.global_position = Vector2(300.0, 0.0)
	p._tick_qi_rings(0.016)
	p.qi_rings = 2
	p._refresh_qi_hud()

	# 技能名 / SkillFx
	var before_fx := _count_fx("skill_fx")
	p._qi_precast("skill_qi_wave", Vector2.RIGHT)
	var labels := 0
	for c in get_children():
		if c is Label and String((c as Label).text) == "冲气·裂空":
			labels += 1
	_check(labels == 1, "气君八式起手报招名")

	# 冲气：花 1 环 + SkillFx
	b.global_position = Vector2(200.0, 0.0)
	b.hits.clear()
	var qi_before: int = int(p.qi_rings)
	_p._qi_handle_cast("skill_qi_wave", Vector2.RIGHT)
	_check(p.qi_rings == qi_before - 1, "冲气花 1 环", "qi=%d" % p.qi_rings)
	_check(b.hits.size() >= 1, "冲气命中直线上的敌人", "hits=%d" % b.hits.size())
	_check(_count_fx("skill_fx") > before_fx, "冲气走 SkillFx（与 BOSS 同管线）",
		"fx=%d" % _count_fx("skill_fx"))
	# 有环 / 无环的伤害倍率：1.30 → 1.80 = +0.5 倍
	var wave_with: float = float(b.hits[0]) if not b.hits.is_empty() else 0.0
	b.hits.clear()
	p.qi_rings = 0
	p._refresh_qi_hud()
	p._qi_handle_cast("skill_qi_wave", Vector2.RIGHT)
	var wave_without: float = float(b.hits[0]) if not b.hits.is_empty() else 0.0
	_check(wave_without > 0.0 and wave_with > wave_without * 1.30,
		"有环冲气伤害 +0.5 倍", "%.1f vs %.1f" % [wave_with, wave_without])

	# 回旋：伤害 + 击退 + SkillFx
	b.global_position = Vector2(100.0, 0.0)
	b.hits.clear(); b.knockbacks.clear()
	p._qi_handle_cast("skill_qi_spin", Vector2.RIGHT)
	_check(b.hits.size() == 1, "回旋命中 168 内", "hits=%d" % b.hits.size())
	_check(b.knockbacks.size() == 1, "回旋击退 320", str(b.knockbacks))

	# 气锁：SkillFx + 不吞通用结算；有环时压 BOSS 移速 + 封技
	b.global_position = Vector2(120.0, 0.0)
	p.qi_rings = 1
	p._refresh_qi_hud()
	b.slows.clear(); b.skill_locks.clear()
	var before_lock := _count_fx("skill_fx")
	var handled: bool = bool(_p._qi_handle_cast("skill_qi_lock", Vector2.RIGHT))
	_check(not handled, "气锁交给通用形态结算（含滞气）")
	_check(_count_fx("skill_fx") > before_lock, "气锁走 SkillFx")
	_check(p.qi_rings == 0, "气锁花 1 环", "qi=%d" % p.qi_rings)
	_check(b.slows.size() == 1 and is_equal_approx(float(b.slows[0][0]), 0.5)
		and is_equal_approx(float(b.slows[0][1]), 2.0), "气锁 BOSS 减速 50% / 2 秒", str(b.slows))
	_check(b.skill_locks.size() == 1 and is_equal_approx(float(b.skill_locks[0]), 2.0),
		"气锁封技 2 秒", str(b.skill_locks))

	# 缩地：起手铺云步，结算交给通用；落地凝 1 枚气环
	b.hits.clear()
	p.qi_rings = 0
	p._refresh_qi_hud()
	var before_step := _count_fx("qi_fx")
	p._qi_precast("skill_qi_step", Vector2.RIGHT)
	_check(_count_fx("qi_fx") > before_step, "缩地起手铺云步拖尾")
	_check(not _p._qi_handle_cast("skill_qi_step", Vector2.RIGHT), "缩地落点走通用结算")
	_check(p.qi_rings == 1, "缩地落地凝 1 环", "qi=%d" % p.qi_rings)

	# 化劲：只花 1 环、减伤 40%、存 60%、结束物理气浪
	p.qi_rings = 3
	p._refresh_qi_hud()
	p._qi_handle_cast("skill_qi_ward", Vector2.RIGHT)
	_check(p.qi_rings == 2, "化劲只花 1 环", "qi=%d" % p.qi_rings)
	_check(p._qi_ward_left > 2.0, "化劲 2.2 秒窗口", "left=%.2f" % p._qi_ward_left)
	p.hp = p.max_hp
	p.invincible_timer = 0.0
	var hp0: float = p.hp
	p.take_damage(100.0, "elemental")
	var d0: float = hp0 - p.hp
	p.hp = p.max_hp
	p.invincible_timer = 0.0
	p._qi_ward_left = 0.0
	var hp1: float = p.hp
	p.take_damage(100.0, "elemental")
	var d1: float = hp1 - p.hp
	_check(d0 < d1 * 0.75, "化劲减伤 40%", "%.1f vs %.1f" % [d0, d1])
	b.global_position = Vector2(100.0, 0.0)
	b.hits.clear()
	p._qi_ward_left = 0.2
	p._tick_qi_ward(0.3)
	_check(b.hits.size() == 1, "化劲结束放气浪", "hits=%d" % b.hits.size())

	# 气爆：0 环也能放；有环按枚加伤；SkillFx
	b.global_position = Vector2(150.0, 0.0)
	b.hits.clear()
	p.qi_rings = 0
	p._refresh_qi_hud()
	p._qi_handle_cast("skill_qi_burst", Vector2.RIGHT)
	_check(p.qi_rings == 0 and b.hits.size() == 1, "0 环气爆仍结算基础伤害")
	p.qi_rings = 2
	p._refresh_qi_hud()
	b.hits.clear()
	p._qi_handle_cast("skill_qi_burst", Vector2.RIGHT)
	_check(p.qi_rings == 0 and b.hits.size() == 1, "有环气爆清空全部环并命中")

	# 吐纳：要花 1 环；1.2 秒引导；小伤不断、大伤打断
	p.hp = p.max_hp * 0.5
	b.global_position = Vector2(800.0, 0.0)
	p.qi_rings = 1
	p._refresh_qi_hud()
	p._qi_handle_cast("skill_qi_breath", Vector2.RIGHT)
	_check(p.qi_rings == 0, "吐纳花 1 环", "qi=%d" % p.qi_rings)
	_check(p._qi_channel_left > 1.0, "吐纳进入 1.2 秒引导", "left=%.2f" % p._qi_channel_left)
	p.invincible_timer = 0.0
	p.take_damage(p.max_hp * 0.05, "elemental")
	var hp_before_heal: float = p.hp
	p._tick_qi_channel(1.3)
	_check(p.hp > hp_before_heal, "小伤不打断，引导结束回血",
		"%.1f → %.1f" % [hp_before_heal, p.hp])
	p.hp = p.max_hp * 0.5
	p.qi_rings = 1
	p._refresh_qi_hud()
	p._qi_handle_cast("skill_qi_breath", Vector2.RIGHT)
	p.invincible_timer = 0.0
	p.take_damage(p.max_hp * 0.09, "elemental")
	var hp_cancel: float = p.hp
	p._tick_qi_channel(0.2)
	_check(p._qi_channel_left <= 0.0 and p.hp == hp_cancel, "大伤打断吐纳、不回血",
		"left=%.2f" % p._qi_channel_left)
	_check(is_instance_valid(p._qi_channel_fx) == false, "打断后清掉引导特效")

	# 无环时吐纳被门禁拦下（不白扣灵力 / 冷却）
	p.qi_rings = 0
	p._refresh_qi_hud()
	_check(not p.try_use_skill("skill_qi_breath"), "无环时吐纳被拦")

	# 聚气满环门禁
	p.qi_rings = 5
	p._refresh_qi_hud()
	_check(not p.try_use_skill("skill_qi_gather"), "满 5 环时聚气被拦")

	# ---- 刀痕：伤害类型跟留痕技能（2026-10-30 用户定）----
	CharacterData.set_attribute_mod("probe_scar", {
		AttributeDB.ATTR_SPELL_POWER: {"flat": 30.0},
		AttributeDB.ATTR_SPELL_SKILL_DAMAGE_PCT: {"flat": 50.0},
		AttributeDB.ATTR_STRENGTH: {"flat": 20.0},
	})
	b.global_position = p.global_position + Vector2(90.0, 0.0)
	b.hits.clear(); b.kinds.clear()
	p._apply_scar_effect({"scar_effect": "create", "scar_offset": 90.0,
		"phys_coeff": 1.0, "spell_coeff": 0.0}, Vector2.RIGHT)
	var field := ScarField.get_active()
	var scar: BladeScar = null
	if field != null:
		for c in field.get_children():
			if c is BladeScar:
				scar = c
	var expected_phys := CharacterData.physical_attack()
	_check(scar != null and scar.damage_kind == "physical"
		and is_equal_approx(scar.damage_power, expected_phys),
		"物理留痕 = 物攻快照（不吃法强）",
		"%.2f vs %.2f" % [scar.damage_power if scar != null else -1.0, expected_phys])
	if scar != null:
		CharacterData.sun_damage_mult = 1.25
		var hits := scar.slash(1)
		_check(hits == 1 and not b.hits.is_empty()
			and is_equal_approx(float(b.hits[0]), scar.damage_power * 1.25)
			and String(b.kinds[0]) == "physical",
			"物理刀痕引爆 = 物攻 × 日冕，物理伤害",
			"%s / %s" % [str(b.hits), str(b.kinds)])
	# 法术留痕：同一口刀痕框架换成法强口径
	b.global_position = p.global_position + Vector2(90.0, 0.0)
	b.hits.clear(); b.kinds.clear()
	p._apply_scar_effect({"scar_effect": "create", "scar_offset": 90.0,
		"phys_coeff": 0.0, "spell_coeff": 1.0}, Vector2.RIGHT)
	var scar2: BladeScar = null
	if field != null:
		for c in field.get_children():
			if c is BladeScar:
				scar2 = c
	var expected_spell := CharacterData.spell_attack() * CharacterData.spell_skill_damage_mult()
	_check(scar2 != null and scar2.damage_kind == "elemental"
		and is_equal_approx(scar2.damage_power, expected_spell),
		"法术留痕 = 法强 × 法技增伤快照",
		"%.2f vs %.2f" % [scar2.damage_power if scar2 != null else -1.0, expected_spell])
	if scar2 != null:
		var hits2 := scar2.slash(1)
		_check(hits2 == 1 and not b.hits.is_empty()
			and is_equal_approx(float(b.hits[0]), scar2.damage_power * 1.25)
			and String(b.kinds[0]) == "elemental",
			"法术刀痕引爆 = 法强快照 × 日冕，法术伤害",
			"%s / %s" % [str(b.hits), str(b.kinds)])
	CharacterData.sun_damage_mult = 1.0
	CharacterData.clear_attribute_mod("probe_scar")
