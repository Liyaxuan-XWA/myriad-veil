extends Node
## 云隐苍角核心首领自检（2026-10-29）：
##   数据 / 8 式 / 三片苔甲减伤与破碎 / 二阶段雾隐识破与雾爆 / 核心奖励。
## 用法：godot --headless --path . res://tools/probe_zhuji_core_stag.tscn

class DummyPlayer extends Node2D:
	var hp: float = 1200.0
	var is_dead: bool = false
	var hits: Array = []
	var debuffs: Dictionary = {}

	func _ready() -> void:
		add_to_group("player")

	func take_damage(amount: float, _attack_kind: String, _source: Node = null,
			_element: String = "") -> void:
		hits.append(amount)
		hp -= amount

	func apply_debuff(id: String, duration: float, _quiet: bool = true) -> bool:
		debuffs[id] = maxf(float(debuffs.get(id, 0.0)), duration)
		return true

	func has_debuff(id: String) -> bool:
		return float(debuffs.get(id, 0.0)) > 0.0

	func remove_debuff(id: String) -> void:
		debuffs.erase(id)


var _passes := 0
var _fails: Array = []
var _boss: Node
var _player: DummyPlayer


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 云隐苍角自检 ##########")
	var cfg := SecretWorldDB.get_core_boss("world_zhuji")
	_check(not cfg.is_empty(), "云隐谷核心首领配置存在")
	_check(String(cfg.get("name", "")) == "云隐苍角", "名字 = 云隐苍角")
	_check(String(cfg.get("scene", "")) != "" and ResourceLoader.exists(String(cfg.get("scene", ""))),
		"专属场景已登记")
	var skills: Array = cfg.get("core_skills", [])
	_check(skills.size() == 8, "八式齐全", "n=%d" % skills.size())
	var fx_missing: Array = []
	for raw in skills:
		var fx_id := String((raw as Dictionary).get("fx_id", ""))
		if fx_id == "" or ArtDB.get_visual(fx_id).is_empty():
			fx_missing.append(fx_id)
	_check(fx_missing.is_empty(), "八式特效均已登记", str(fx_missing))
	_check(int(cfg.get("max_hp", 0)) == 4000 and int(cfg.get("attack_power", 0)) == 62,
		"数值：4000 血 / 62 攻", "%s / %s" % [cfg.get("max_hp"), cfg.get("attack_power")])
	_check(int((cfg.get("reward", {}) as Dictionary).get("mat_pojing_di_jiedan", 0)) == 1,
		"首杀奖励：结丹底髓（半枚，与冲和界第三位的天髓熔铸）")
	_check(not ItemDB.get_equipment_template("eq_cangjiao_jia").is_empty(),
		"苍角甲装备模板存在")
	_check(not (SecretWorldDB.get_region_content("world_zhuji").get("core_boss", {}) as Dictionary).is_empty(),
		"云隐谷内容表已挂核心首领")
	var drop_ids: Array = []
	for d in CodexDB.boss_drops_info("world_core_zhuji"):
		drop_ids.append(String((d as Dictionary).get("id", "")))
	_check(drop_ids.has("mat_pojing_di_jiedan") and drop_ids.has("eq_cangjiao_jia")
		and not drop_ids.has("eq_tengjia"), "图鉴卡掉落是苍角自己的", str(drop_ids))
	var card_moves := CodexDB.boss_moves_info("world_core_zhuji")
	_check(card_moves.size() == 8
		and String((card_moves[0] as Dictionary).get("name", "")) == "角撞·裂岩",
		"图鉴卡招式是苍角自己的", "n=%d" % card_moves.size())
	var card_stats := CodexDB.boss_stats("world_core_zhuji")
	_check(int(card_stats.get("hp", 0)) == 4000, "图鉴卡血量 4000",
		str(card_stats.get("hp")))

	_player = DummyPlayer.new()
	add_child(_player)
	_player.global_position = Vector2.ZERO
	var packed := load(String(cfg.get("scene", ""))) as PackedScene
	_boss = packed.instantiate()
	var stats: Dictionary = cfg.duplicate(true)
	stats["pos"] = Vector2.ZERO
	_boss.configure(stats, WorldEnemy.KIND_CORE, String(cfg.get("name", "核心首领")))
	add_child(_boss)
	await get_tree().process_frame
	await get_tree().process_frame
	_boss.set_physics_process(false)
	_boss.set_process(false)
	_boss.set("target", _player)
	_boss.global_position = Vector2.ZERO
	await get_tree().process_frame

	var spheres: Array = _boss.call("hit_spheres")
	var left := INF
	var right := -INF
	for raw in spheres:
		var sv: Vector3 = raw
		left = minf(left, sv.x - sv.z)
		right = maxf(right, sv.x + sv.z)
	_check(spheres.size() >= 3 and right - left >= 180.0, "受击球覆盖身体横宽",
		"n=%d span=%.1f" % [spheres.size(), right - left])
	_check(int(_boss.call("get", "_plates").size()) == 3, "三片苔甲已生成",
		"n=%d" % int(_boss.call("get", "_plates").size()))
	_check(bool(_boss.call("has_plates")), "苔甲护甲生效")
	_check(absf(float(_boss.call("damage_taken_multiplier", "physical")) - 0.58) < 0.001,
		"甲在时减伤 42%", str(_boss.call("damage_taken_multiplier", "physical")))

	# 弹反角撞/角扫：直接震碎最近的一片
	_boss.call("on_parried", _player)
	await get_tree().process_frame
	_check(_boss.get("_plates").size() == 2, "弹反震碎一片苔甲",
		"n=%d" % int(_boss.call("get", "_plates").size()))
	_check(bool(_boss.call("has_plates")), "震碎一片后护甲仍在")

	# 余下两片各打三下
	var plates: Array = _boss.get("_plates").duplicate()
	for raw in plates:
		var p = raw
		for i in 3:
			if is_instance_valid(p):
				p.call("take_hit")
	_check(not bool(_boss.call("has_plates")), "三片尽碎，护甲消失")
	_check(absf(float(_boss.call("damage_taken_multiplier", "physical")) - 1.0) < 0.001,
		"破甲后伤害恢复正常", str(_boss.call("damage_taken_multiplier", "physical")))

	# 二阶段雾隐：命中真身识破
	_boss.set("phase", 2)
	_boss.set("_mist_cd", 0.0)
	_boss.call("_begin_mist")
	_check(bool(_boss.get("_mist_hidden")), "二阶段进入雾隐")
	_check(_boss.get("_mist_marker") != null, "真身角光标记已生成")
	var hp0: float = float(_boss.get("current_hp"))
	_boss.call("take_damage", 10.0, _player, "physical", "", false)
	_check(not bool(_boss.get("_mist_hidden")), "命中真身立刻识破")
	_check(is_equal_approx(float(_boss.get("current_hp")), hp0), "识破这一下不扣血")

	# 再次雾隐，超时雾爆
	_boss.set("_mist_cd", 0.0)
	_boss.call("_begin_mist")
	_player.hits.clear()
	_boss.call("_burst_mist")
	_check(not bool(_boss.get("_mist_hidden")), "雾爆后现身")
	_check(not _player.hits.is_empty(), "雾爆命中区域内玩家", "n=%d" % _player.hits.size())
	_check(float(_player.debuffs.get("lock_step", 0.0)) >= 1.4, "雾爆附带锁步")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("FAILED  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
