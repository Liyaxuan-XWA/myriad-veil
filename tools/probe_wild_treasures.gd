extends Node
## 野修法宝第二组自检（2026-11-01）：断念铃 / 禁步桩 / 续命灯 / 蚀甲锥
## 覆盖：数据、图鉴来源、区域池、玩家侧、野修侧、反连锁、致死改判、破罡。
## 用法：godot --headless --path . res://tools/probe_wild_treasures.tscn

class DummyBoss extends Node2D:
	var state: int = BossBase.BossState.IDLE
	var is_ally: bool = false
	var debuffs: Dictionary = {}
	var skill_locks: Array = []
	var knockbacks: Array = []
	var bell_immune: bool = false

	func _ready() -> void:
		add_to_group("boss")

	func is_dead() -> bool:
		return false

	func has_debuff(id: String) -> bool:
		return float(debuffs.get(id, 0.0)) > 0.0

	func apply_debuff(id: String, duration: float) -> bool:
		debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
		return true

	func apply_skill_lock(seconds: float) -> void:
		skill_locks.append(seconds)
		state = BossBase.BossState.IDLE

	func is_treasure_bell_immune() -> bool:
		return bell_immune

	func mark_treasure_bell_immune(_seconds: float) -> void:
		bell_immune = true

	func take_knockback(impulse: Vector2) -> void:
		knockbacks.append(impulse)

	func head_top_y() -> float:
		return -80.0

	func hit_radius() -> float:
		return 20.0

	func hit_spheres() -> Array:
		return []


## 带碰撞体的木桩靶：专门验证投射物真的能从脚底高度命中，而不是只测回调
class CollisionTarget extends CharacterBody2D:
	var is_ally: bool = false
	var debuffs: Dictionary = {}

	func _ready() -> void:
		add_to_group("boss")
		collision_layer = 2
		collision_mask = 0
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 18.0
		cs.shape = c
		add_child(cs)

	func apply_debuff(id: String, duration: float) -> bool:
		debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
		return true

	func has_debuff(id: String) -> bool:
		return float(debuffs.get(id, 0.0)) > 0.0

	func is_dead() -> bool:
		return false

	func head_top_y() -> float:
		return -80.0


var _passes := 0
var _fails: Array = []
var _p: Node2D
var _enemy: Node2D


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 野修法宝第二组自检 ##########")
	await get_tree().process_frame
	_check_data()
	_check_pools()
	_check_runtime_pools()
	await _spawn_player()
	_test_player_bell()
	_test_player_silence()
	_test_player_stake()
	await _test_player_cone()
	_test_player_shred()
	_test_player_lamp()
	await _spawn_enemy()
	_test_enemy_bell()
	_test_enemy_stake()
	await _test_enemy_cone()
	_test_enemy_lamp()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_data() -> void:
	print("\n-- 数据 / 图鉴 --")
	var ids := ["tr_duannian_ling", "tr_jinbu_zhuang", "tr_xuming_deng", "tr_shixi_zhui"]
	var names := ["断念铃", "禁步桩", "续命灯", "蚀甲锥"]
	var kinds := ["mind_lock", "stake", "lamp", "corrode"]
	for i in ids.size():
		var id: String = ids[i]
		var tpl := ItemDB.get_treasure_template(id)
		_check(not tpl.is_empty(), "模板存在：" + id)
		_check(String(tpl.get("treasure_name", "")) == names[i], "显示名：" + names[i])
		_check(String(tpl.get("active_type", "")) == kinds[i], "主动类型：" + kinds[i])
		_check(String(tpl.get("treasure_grade", "")) == "法器", "品阶为法器：" + id)
		var item := CharacterData.make_treasure_instance(tpl)
		var lines := ItemDB.treasure_effect_lines(item)
		_check(lines.size() >= 3, "法宝说明至少三行：" + id, str(lines.size()))
		var icon := String(tpl.get("icon", ""))
		_check(icon != "" and FileAccess.file_exists(icon), "图标已落盘：" + id)
		_check(CodexDB.SOURCES.has(id), "图鉴来源已登记：" + id)
	_check(bool(DebuffDB.get_debuff("duannian").get("no_skill", false)), "断念：禁功法")
	_check(is_equal_approx(float(DebuffDB.get_debuff("jinbu").get("move_mult", 1.0)), 0.65),
		"禁步：移速 0.65")
	_check(bool(DebuffDB.get_debuff("jinbu").get("no_dodge", false)), "禁步：禁闪避")
	_check(bool(DebuffDB.get_debuff("jinbu").get("no_stamina_regen", false)),
		"禁步：精力停止回复（与木缚符的定身分开）")
	_check(is_equal_approx(float(DebuffDB.get_debuff("shixi").get("guard_shred", 0.0)), 0.5),
		"蚀甲：护体减伤减半")
	var stake_item := CharacterData.make_treasure_instance(
		ItemDB.get_treasure_template("tr_jinbu_zhuang"))
	var stake_text := "\n".join(ItemDB.treasure_effect_lines(stake_item))
	_check(stake_text.contains("禁步") and not stake_text.contains("定身"),
		"禁步桩文案不再写定身")
	var cone_item := CharacterData.make_treasure_instance(
		ItemDB.get_treasure_template("tr_shixi_zhui"))
	var cone_text := "\n".join(ItemDB.treasure_effect_lines(cone_item))
	_check(cone_text.contains("符箓除外"), "蚀甲锥文案写明符箓除外", cone_text)
	_check(DebuffDB.effect_text("jinbu").contains("精力停止恢复"),
		"禁步状态说明含精力停止")
	_check(DebuffDB.effect_text("shixi").contains("符箓除外"),
		"蚀甲状态说明含符箓除外")
	_check(not BuffDB.get_buff("xuming").is_empty(), "续命 buff 已登记")
	_check(is_equal_approx(DamageCalc.apply_guard_shred(0.30, 0.5), 0.65),
		"破罡公式：0.30 → 0.65")
	_check(is_equal_approx(DamageCalc.apply_guard_shred(1.20, 0.5), 1.20),
		"破罡公式不放大易伤")


func _check_pools() -> void:
	print("\n-- 区域携带池 --")
	_check(SecretWorldDB.CULTIVATOR.get("treasure_pool", []).has("tr_jinbu_zhuang"),
		"练气池含禁步桩")
	_check(SecretWorldDB.CULTIVATOR_ZHUJI.get("treasure_pool", []).has("tr_duannian_ling"),
		"筑基池含断念铃")
	_check(SecretWorldDB.CULTIVATOR_JIEDAN.get("treasure_pool", []).has("tr_xuming_deng"),
		"结丹池含续命灯")
	_check(SecretWorldDB.CULTIVATOR_YUANYING.get("treasure_pool", []).has("tr_shixi_zhui"),
		"元婴池含蚀甲锥")
	_check(not SecretWorldDB.CULTIVATOR.get("treasure_pool", []).has("tr_xuming_deng"),
		"练气池不出续命灯")


## 配置表登记了 ≠ 运行时真会掉。_roll_cultivator_treasure() 曾写死练气池，
## 四个区一律只掉 3 件（2026-11-07）。这里从真实入口采样，验证按境界取池。
func _check_runtime_pools() -> void:
	var scene := load("res://scenes/world/secret_world.tscn") as PackedScene
	if scene == null:
		_check(false, "大世界场景可实例化")
		return
	var sw := scene.instantiate()   # 不入树：只调纯抽取函数，不触发地图 / 存档初始化
	var bad: Array = []
	for rid in [SecretWorldDB.REGION_LIANQI, SecretWorldDB.REGION_ZHUJI,
			SecretWorldDB.REGION_JIEDAN, SecretWorldDB.REGION_YUANYING]:
		var want: Array = SecretWorldDB.get_cultivator(String(rid)).get("treasure_pool", [])
		var seen: Dictionary = {}
		for i in 240:
			var item: Dictionary = sw.call("_roll_cultivator_treasure", String(rid))
			var tid := String(item.get("id", ""))
			if tid != "":
				seen[tid] = true
		for wid in want:
			if not seen.has(String(wid)):
				bad.append("%s 抽不到 %s" % [rid, wid])
		for sid in seen.keys():
			if not want.has(String(sid)):
				bad.append("%s 多出 %s" % [rid, sid])
	sw.free()
	_check(bad.is_empty(), "四区野修按境界抽池（3/6/9/10 件齐且不多）", str(bad))


func _spawn_player() -> void:
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	await get_tree().process_frame
	await get_tree().process_frame
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.global_position = Vector2.ZERO


func _fresh_player(mana := 999.0) -> void:
	_p.reset_player()
	_p.max_hp = 1000.0
	_p.hp = 1000.0
	_p.max_mana = mana
	_p.mana = mana
	_p.invincible_timer = 0.0
	_p._hit_negated_timer = 0.0
	_p.is_dodging = false
	_p.is_parrying = false
	_p._counter_charging = false
	_p.auto_parry_timer = 0.0
	_p.debuffs.clear()
	_p._summon_cooldowns.clear()
	_p._treasure_bell_immune_left = 0.0


func _test_player_bell() -> void:
	print("\n-- 玩家侧：断念铃 --")
	_fresh_player()
	var tpl := ItemDB.get_treasure_template("tr_duannian_ling")
	var item := CharacterData.make_treasure_instance(tpl)
	var d := DummyBoss.new()
	d.global_position = Vector2(120.0, 0.0)
	d.state = BossBase.BossState.WINDUP
	add_child(d)
	var mana_before: float = _p.mana
	_p._start_mind_lock_treasure(item, tpl)
	_check(d.has_debuff("duannian"), "封技挂到目标")
	_check(d.skill_locks.size() == 1, "目标进入封技", str(d.skill_locks))
	_check(is_equal_approx(_p.mana, mana_before - 20.0 + 10.0), "断招返还 10 灵力",
		"mana=%.1f" % _p.mana)
	_check(is_equal_approx(_p.summon_cooldown_left("tr_duannian_ling"), 35.0),
		"冷却 35 秒")
	_p._start_mind_lock_treasure(item, tpl)
	_check(d.skill_locks.size() == 1, "冷却中不会二次封技")
	_p._summon_cooldowns.clear()
	var mana_after_cd: float = _p.mana
	_p._start_mind_lock_treasure(item, tpl)
	_check(d.skill_locks.size() == 1, "同一目标 8 秒内不再封技")
	_check(is_equal_approx(_p.mana, mana_after_cd), "抗性期间不扣灵力")
	d.queue_free()


func _test_player_silence() -> void:
	print("\n-- 玩家侧：断念封功法 --")
	_fresh_player()
	for sid in ["skill_qi_gather"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	_p.qi_rings = 0
	_p.skill_cooldowns.clear()
	var cast_ok: bool = _p.try_use_skill("skill_qi_gather")
	_check(cast_ok, "无封技时气聚可用")
	_p.reset_player()
	_p.mana = 999.0
	_p.max_mana = 999.0
	_p.apply_debuff("duannian", 1.0)
	var sealed: bool = _p.try_use_skill("skill_qi_gather")
	_check(not sealed, "断念期间功法不可用")
	_p.debuffs.erase("duannian")


func _test_player_stake() -> void:
	print("\n-- 玩家侧：禁步桩 --")
	_fresh_player()
	_p.debuffs["jinbu"] = 1.0
	_check(_p.debuff_blocks_stamina_regen(), "禁步实际拦住精力恢复")
	_p.debuffs.erase("jinbu")
	var tpl := ItemDB.get_treasure_template("tr_jinbu_zhuang")
	var item := CharacterData.make_treasure_instance(tpl)
	var d := DummyBoss.new()
	d.global_position = Vector2(120.0, 0.0)
	add_child(d)
	var mana_before: float = _p.mana
	_p._start_stake_treasure(item, tpl)
	var field = _p._stake_field
	_check(is_instance_valid(field), "桩场已生成")
	_check(is_equal_approx(_p.mana, mana_before - 15.0), "消耗 15 灵力")
	_check(is_equal_approx(_p.summon_cooldown_left("tr_jinbu_zhuang"), 28.0),
		"冷却 28 秒")
	_check(not d.has_debuff("jinbu"), "展开前不挂禁步")
	if is_instance_valid(field):
		field.set_process(false)
		field.tick(0.9)
		_check(d.has_debuff("jinbu"), "展开挂禁步")
		_check(float(d.debuffs.get("jinbu", 0.0)) >= 1.4, "展开首段禁步 1.5 秒",
			str(d.debuffs.get("jinbu", 0.0)))
		_check(not d.has_debuff("rooted"), "桩不硬定身（与木缚符分开）")
		_check(not _p.has_debuff("jinbu"), "玩家不会被自己的桩减速")
		_check(bool(field._finished) == false, "场地仍在持续")
		_p._tick_stake_treasure(0.9)
		_check(_p._stake_left < 4.0, "玩家侧倒计时在走")
		field.queue_free()
	d.queue_free()


func _test_player_cone() -> void:
	print("\n-- 玩家侧：蚀甲锥 --")
	await get_tree().process_frame
	_fresh_player()
	var tpl := ItemDB.get_treasure_template("tr_shixi_zhui")
	var item := CharacterData.make_treasure_instance(tpl)
	var ally := DummyBoss.new()
	ally.is_ally = true
	ally.global_position = Vector2(110.0, 0.0)
	add_child(ally)
	var target := DummyBoss.new()
	target.global_position = Vector2(140.0, 0.0)
	add_child(target)
	var mana_before: float = _p.mana
	_p._start_corrode_treasure(item, tpl)
	_check(is_equal_approx(_p.mana, mana_before - 15.0), "消耗 15 灵力")
	_check(is_equal_approx(_p.summon_cooldown_left("tr_shixi_zhui"), 30.0),
		"冷却 30 秒")
	var cone: Node = null
	for c in get_children():
		if c is TreasureCone:
			cone = c
	_check(cone != null, "锥子已掷出")
	if cone != null:
		cone.set_physics_process(false)
		_check(int(cone.collision_mask) == 2, "玩家锥只检测 BOSS 层")
		cone._on_body_entered(ally)
		_check(not ally.has_debuff("shixi"), "不会钉友军召唤物")
		cone._on_body_entered(target)
		_check(target.has_debuff("shixi"), "命中挂蚀甲")
		_check(target.get_node_or_null("TreasureCorrodeNail") != null, "锥子插在目标身上")
		_check(cone.is_queued_for_deletion(), "命中后释放")
	ally.queue_free()
	target.queue_free()
	# 真实飞行：让锥子按碰撞体飞过去，验证脚底高度能命中
	_p._summon_cooldowns.clear()
	_p.mana = 999.0
	var body := CollisionTarget.new()
	add_child(body)
	body.global_position = Vector2(160.0, 0.0)
	_p._start_corrode_treasure(item, tpl)
	for i in 18:
		await get_tree().physics_frame
	_check(body.has_debuff("shixi"), "锥子按真实碰撞命中脚底靶")
	body.queue_free()


func _test_player_shred() -> void:
	print("\n-- 玩家侧：破罡减伤 --")
	_fresh_player()
	_p._taiji_guard_left = 5.0
	_p._taiji_guard_pct = 0.3
	_p.invincible_timer = 0.0
	_p.take_damage(100.0, "physical_melee", null)
	var loss_normal: float = 1000.0 - float(_p.hp)
	_p.hp = 1000.0
	_p.invincible_timer = 0.0
	_p.debuffs["shixi"] = 8.0
	_p.take_damage(100.0, "physical_melee", null)
	var loss_shred: float = 1000.0 - float(_p.hp)
	_check(loss_shred > loss_normal * 1.25, "蚀甲让带护体的玩家掉血更多",
		"%.1f → %.1f" % [loss_normal, loss_shred])
	# 石附符是符箓：蚀甲锥只加 12% 受伤，不削符箓减伤
	_fresh_player()
	_p._taiji_guard_left = 0.0
	_p._talisman_stone_left = 99
	_p._talisman_stone_hits = 99
	_p._talisman_stone_reduce = 0.3
	_p.invincible_timer = 0.0
	_p.take_damage(100.0, "physical_melee", null)
	var loss_stone: float = 1000.0 - float(_p.hp)
	_p.hp = 1000.0
	_p.invincible_timer = 0.0
	_p._talisman_stone_left = 99
	_p._talisman_stone_hits = 99
	_p.debuffs["shixi"] = 8.0
	_p.take_damage(100.0, "physical_melee", null)
	var loss_stone_shixi: float = 1000.0 - float(_p.hp)
	_check(loss_stone_shixi < loss_stone * 1.2, "蚀甲不削石附符（符箓）",
		"%.1f → %.1f" % [loss_stone, loss_stone_shixi])


func _test_player_lamp() -> void:
	print("\n-- 玩家侧：续命灯 --")
	_fresh_player()
	var tpl := ItemDB.get_treasure_template("tr_xuming_deng")
	var item := CharacterData.make_treasure_instance(tpl)
	var d := DummyBoss.new()
	d.global_position = Vector2(100.0, 0.0)
	add_child(d)
	var mana_before: float = _p.mana
	_p._start_lamp_treasure(item, tpl)
	_check(_p._lamp_left > 9.9, "点亮 10 秒")
	_check(_p.has_buff("xuming"), "HUD 续命 buff")
	_check(is_equal_approx(_p.mana, mana_before - 25.0), "消耗 25 灵力")
	_check(is_equal_approx(_p.summon_cooldown_left("tr_xuming_deng"), 60.0),
		"冷却 60 秒")
	_p.hp = 100.0
	_p.invincible_timer = 0.0
	_p._apply_damage(9999.0, "physical_melee", null)
	_check(_p.hp == 1.0, "致死改判留 1 血", "hp=%.1f" % _p.hp)
	_check(not _p.has_buff("xuming"), "触发后灯熄")
	_check(_p._lamp_heal_left > 0.99, "开始 1 秒回血")
	_check(_p.invincible_timer >= 0.79, "触发后短暂无敌", "inv=%.2f" % _p.invincible_timer)
	_check(not d.knockbacks.is_empty(), "触发时击退身周敌人")
	_p._tick_lamp_treasure(1.0)
	_check(_p.hp >= 150.0, "1 秒回复 15% 最大气血", "hp=%.1f" % _p.hp)
	# 持续伤害致死也改判
	_p.hp = 3.0
	_p._lamp_left = 10.0
	_p._lamp_heal_left = 0.0
	_p._lamp_heal_ratio = 0.15
	_p._debuff_dot_timers.clear()
	_p.debuffs["burn"] = 1.0
	_p.invincible_timer = 0.0
	_p._tick_debuffs(0.5)
	_check(_p.hp == 1.0, "点燃致死也留 1 血", "hp=%.1f" % _p.hp)
	_check(_p._lamp_left == 0.0, "持续伤害触发后灯熄")
	_p.debuffs.erase("burn")
	# 第二下致死：灯已灭，照常死亡
	_p.hp = 100.0
	_p.invincible_timer = 0.0
	_p._apply_damage(9999.0, "physical_melee", null)
	_check(_p.is_dead, "灯只挡一次")
	d.queue_free()


func _spawn_enemy() -> void:
	_enemy = (load("res://scenes/world/world_enemy.tscn") as PackedScene).instantiate()
	var cfg := {
		"pos": Vector2(180.0, 0.0),
		"max_hp": 1000.0,
		"attack_power": 20.0,
		"visual_id": "player_liqingyun",
		"move_speed": 120.0,
		"aggro_range": 600.0,
		"leash_range": 1000.0,
		"skills": [],
		"treasure_mana_max": 100.0,
		"treasure_trigger_hp_ratio": 0.55,
	}
	_enemy.configure(cfg, "cultivator", "测试野修")
	add_child(_enemy)
	await get_tree().process_frame
	await get_tree().process_frame
	_enemy.set_physics_process(false)
	_enemy.set_process(false)
	_enemy.global_position = Vector2(180.0, 0.0)
	_enemy.spawn_home = Vector2(180.0, 0.0)
	_fresh_player()
	_p.is_dead = false
	_p.global_position = Vector2.ZERO
	_enemy._engaged = true
	_enemy.target = _p
	_enemy._treasure_mana = 100.0


func _set_enemy_treasure(id: String) -> void:
	var tpl := ItemDB.get_treasure_template(id)
	_enemy.carried_treasure = CharacterData.make_treasure_instance(tpl)
	_enemy._treasure_cooldown_left = 0.0
	_enemy._treasure_mana = 100.0
	_enemy._treasure_channel_left = 0.0
	_enemy._bell_pending = false
	_enemy._lamp_left = 0.0
	_enemy._lamp_heal_left = 0.0
	_enemy._treasure_invuln_left = 0.0
	_enemy.current_hp = _enemy.max_hp
	_enemy.state = BossBase.BossState.IDLE
	_enemy.debuffs.clear()
	_p.debuffs.clear()
	_p._treasure_bell_immune_left = 0.0
	_p.invincible_timer = 0.0
	_p._hit_negated_timer = 0.0
	_p.is_dodging = false
	_p.is_dead = false
	_p.mana = 999.0


func _test_enemy_bell() -> void:
	print("\n-- 野修侧：断念铃 --")
	_set_enemy_treasure("tr_duannian_ling")
	_enemy._tick_carried_treasure(0.1)
	_check(_enemy._bell_pending, "野修摇铃进入前摇")
	_check(is_equal_approx(_enemy._treasure_mana, 80.0), "野修消耗 20 灵力",
		"mana=%.1f" % _enemy._treasure_mana)
	_check(is_equal_approx(_enemy._treasure_cooldown_left, 35.0), "野修冷却 35 秒")
	_enemy._tick_carried_treasure(0.5)
	_check(_p.has_debuff("duannian"), "玩家被断念")
	_check(_p.is_treasure_bell_immune(), "玩家获得 8 秒断念抗性")
	_check(not _enemy._bell_pending, "摇铃结束")
	_p.debuffs.erase("duannian")
	# 前摇被玩家封技打断：不落封技，也不吃完整冷却
	_set_enemy_treasure("tr_duannian_ling")
	_enemy._tick_carried_treasure(0.1)
	_enemy.apply_skill_lock(1.0)
	_enemy._tick_carried_treasure(0.1)
	_check(not _enemy._bell_pending, "野修摇铃被断念打断")
	_check(not _p.has_debuff("duannian"), "被打断的铃不封玩家")
	_check(_enemy._treasure_cooldown_left <= 0.61, "打断不进完整冷却",
		"cd=%.2f" % _enemy._treasure_cooldown_left)
	_enemy._cc_silence_left = 0.0
	_p.debuffs.erase("duannian")


func _test_enemy_stake() -> void:
	print("\n-- 野修侧：禁步桩 --")
	_set_enemy_treasure("tr_jinbu_zhuang")
	_enemy._treasure_cooldown_left = 0.0
	_enemy._tick_carried_treasure(0.1)
	var field: Node = null
	for c in get_children():
		if c is TreasureStakeField:
			field = c
	_check(field != null, "野修在玩家脚下埋桩")
	if field != null:
		field.set_process(false)
		field.tick(0.9)
		_check(_p.has_debuff("jinbu"), "玩家被禁步")
		_check(not _p.has_debuff("rooted"), "野修的桩不硬定身")
		_check(not _enemy.has_debuff("jinbu"), "野修自己不吃自己的圈")
		field.queue_free()
	_p.debuffs.erase("jinbu")


func _test_enemy_cone() -> void:
	print("\n-- 野修侧：蚀甲锥 --")
	_set_enemy_treasure("tr_shixi_zhui")
	_enemy._tick_carried_treasure(0.1)
	var cone: Node = null
	for c in get_children():
		if c is TreasureCone:
			cone = c
	_check(cone != null, "野修掷出锥子")
	if cone != null:
		cone.set_physics_process(false)
		_check(String(cone.target_group) == "player", "野修锥打玩家阵营")
		_check(int(cone.collision_mask) == 1, "野修锥只检测玩家层")
		cone._on_body_entered(_p)
		_check(_p.has_debuff("shixi"), "玩家被蚀甲")
		_check(_p.get_node_or_null("TreasureCorrodeNail") != null, "玩家身上插锥")
	_p.debuffs.erase("shixi")
	# 真实飞行：野修锥按碰撞体命中玩家
	_p._hit_negated_timer = 0.0
	_p.invincible_timer = 0.0
	_p.is_dodging = false
	_set_enemy_treasure("tr_shixi_zhui")
	_enemy._tick_carried_treasure(0.1)
	var fly: Node = null
	for c in get_children():
		if c is TreasureCone and not c.is_queued_for_deletion():
			fly = c
	_check(fly != null, "野修锥再次掷出")
	if fly != null:
		for i in 24:
			await get_tree().physics_frame
		_check(_p.has_debuff("shixi"), "野修锥按真实碰撞命中玩家")
	_p.debuffs.erase("shixi")


func _test_enemy_lamp() -> void:
	print("\n-- 野修侧：续命灯 --")
	_set_enemy_treasure("tr_xuming_deng")
	_enemy.current_hp = _enemy.max_hp * 0.3
	_enemy._tick_carried_treasure(0.1)
	_check(_enemy._lamp_left > 9.9, "野修低血点灯")
	_check(is_instance_valid(_enemy._lamp_fx), "灯焰挂到野修身上")
	_enemy.take_damage(9999.0, null, "physical")
	_check(is_equal_approx(_enemy.current_hp, 1.0), "野修致死改判留 1 血",
		"hp=%.1f" % _enemy.current_hp)
	_check(_enemy._lamp_heal_left > 0.99, "野修开始 1 秒回血")
	_check(_enemy._treasure_invuln_left > 0.79, "野修触发后短暂无敌")
	_check(_p.knockback_velocity.length() > 0.1, "玩家被灯焰击退")
	_enemy._tick_lamp_state(1.0)
	_check(_enemy.current_hp >= 150.0, "野修回复 15% 最大气血",
		"hp=%.1f" % _enemy.current_hp)
	# 持续伤害致死也改判
	_enemy.current_hp = 3.0
	_enemy._lamp_left = 10.0
	_enemy._lamp_heal_left = 0.0
	_enemy._treasure_invuln_left = 0.0
	_enemy._apply_dot(3.0)
	_check(_enemy.current_hp == 1.0, "野修被持续伤害致死也留 1 血",
		"hp=%.1f" % _enemy.current_hp)
	_check(_enemy._lamp_left == 0.0, "野修持续伤害触发后灯熄")
	_enemy._treasure_invuln_left = 0.0
	_enemy.take_damage(9999.0, null, "physical")
	_check(_enemy.state == BossBase.BossState.DEAD or _enemy._died_emitted,
		"灯只挡一次，第二下致死")
