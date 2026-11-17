extends Node
## 照影·迟照符（domain_04 位面法宝）自检（2026-11-07）
## 覆盖：模板 / 文案、催动、延迟记账、免伤不记账、30%×3 抹账上限、到期结算与致死、清理点。
## 用法：godot --headless --path . res://tools/probe_delayed_reckoning.tscn -- --no-save

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
	print("\n########## 照影·迟照符 · 延迟结算 ##########")
	var tpl := ItemDB.get_treasure_template("tr_zhaoying_zhefu")
	_check(not tpl.is_empty(), "模板已登记")
	_check(String(tpl.get("treasure_name", "")) == "照影·迟照符", "显示名")
	_check(String(tpl.get("active_type", "")) == "delayed_reckoning", "主动类型")
	_check(bool(tpl.get("is_plane_treasure", false)) \
		and String(tpl.get("domain_id", "")) == "domain_04", "仍属第四位面法宝")
	var stats := ItemDB.treasure_active_stats({}, tpl)
	_check(is_equal_approx(float(stats.get("duration", 0.0)), 4.0), "窗口 4 秒")
	_check(is_equal_approx(float(stats.get("cooldown", 0.0)), 38.0), "冷却 38 秒")
	_check(is_equal_approx(float(stats.get("mana", 0.0)), 20.0), "耗蓝 20")
	_check(is_equal_approx(float(stats.get("wipe_pct", 0.0)), 0.30), "抹除 30%")
	_check(int(stats.get("max_wipes", 0)) == 3, "最多 3 次")
	var lines := ItemDB.treasure_effect_lines(CharacterData.make_treasure_instance(tpl))
	_check(lines.size() >= 5, "说明按当前数值现算", str(lines.size()))
	_check("\n".join(lines).contains("待结池"), "说明写明待结池")

	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.set_physics_process(false)
	p.set_process(false)
	p.global_position = Vector2.ZERO
	p.mana = 999.0
	p.hp = p.max_hp
	var item := CharacterData.make_treasure_instance(tpl)

	# 催动
	p._start_delayed_reckoning_treasure(item, tpl)
	_check(p._reckoning_left > 3.9, "窗口开启 4 秒")
	_check(is_equal_approx(p.mana, 979.0), "消耗 20 灵力", "mana=%.1f" % p.mana)
	_check(p.summon_cooldown_left("tr_zhaoying_zhefu") > 37.0, "进入 38 秒冷却")
	_check(p.reckoning_left("tr_zhaoying_zhefu") > 3.9, "法宝栏显示剩余窗口")

	# 真正要扣血的那笔进池，不落地
	var hp0: float = p.hp
	p.invincible_timer = 0.0
	p.take_damage(100.0, "physical_melee", null, "")
	_check(is_equal_approx(p.hp, hp0), "迟照窗口内不掉血")
	_check(p._reckoning_pool > 0.0, "伤害记入待结池", "%.1f" % p._reckoning_pool)
	var pool0: float = p._reckoning_pool
	# 迟照分支照常给 0.3 秒无敌帧；连击第二笔应被免掉，不进池
	p.take_damage(100.0, "physical_melee", null, "")
	_check(is_equal_approx(p._reckoning_pool, pool0), "无敌帧免掉的伤害不记账")

	# 抹账：每次 30%，最多 3 次
	p._reckoning_on_wipe()
	_check(is_equal_approx(p._reckoning_pool, pool0 * 0.70), "第一次抹 30%")
	p._reckoning_on_wipe()
	p._reckoning_on_wipe()
	var after3: float = p._reckoning_pool
	_check(is_equal_approx(after3, pool0 * 0.343), "三次累计抹到 34.3%")
	p._reckoning_on_wipe()
	_check(is_equal_approx(p._reckoning_pool, after3), "第 4 次不再抹（上限 3）")

	# 到期一次性结算
	p._tick_reckoning(4.0)
	_check(p._reckoning_left == 0.0 and p._reckoning_pool == 0.0, "窗口与池已清空")
	_check(p.hp < hp0, "剩余账一次性扣血", "hp=%.1f" % p.hp)
	_check(p.took_damage_this_battle, "结算后计入本场受伤")
	_check(p.treasure_status_left("tr_zhaoying_zhefu") > 30.0, "结算后法宝栏显示冷却")

	# 结算致死走正常死亡（不替死）
	p._summon_cooldowns.clear()
	p.hp = 5.0
	p._start_delayed_reckoning_treasure(item, tpl)
	p.invincible_timer = 0.0
	p.take_damage(1000.0, "physical_melee", null, "")
	_check(is_equal_approx(p.hp, 5.0), "致死伤在窗口内仍不掉血")
	p._tick_reckoning(4.0)
	_check(bool(p.is_dead), "到期结算致死正常死亡")

	# 清理点
	p._reckoning_left = 2.0
	p._reckoning_pool = 50.0
	p.reset_player()
	_check(p._reckoning_left == 0.0 and p._reckoning_pool == 0.0, "重开战斗清空待结池")

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
