extends Node
## 镇墟石犼核心首领探针（2026-10-31）：数据 / 场景 / 闻声 / 石碣 / 二阶段。
## 用法：godot --headless --path . tools/probe_shihou_core.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _p: Node2D
var _boss: Node2D


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 镇墟石犼核心探针 ##########")
	var cfg := SecretWorldDB.get_core_boss(SecretWorldDB.REGION_YUANYING)
	_check(not cfg.is_empty(), "元婴区核心首领已登记")
	_check(String(cfg.get("name", "")) == "镇墟石犼", "核心名 = 镇墟石犼", String(cfg.get("name", "")))
	_check(String(cfg.get("visual_id", "")) == "world_core_shihou", "形象 id 已登记")
	_check(float(cfg.get("max_hp", 0.0)) == 44000.0, "血量 44,000")
	_check(float(cfg.get("attack_power", 0.0)) == 112.0, "攻击 112")
	var skills: Array = cfg.get("core_skills", [])
	_check(skills.size() == 6, "六招战斗八式（另两式为二阶段机制）", str(skills.size()))
	var ids: Array = []
	for raw in skills:
		ids.append(String((raw as Dictionary).get("id", "")))
	for want in ["shihou_pounce", "shihou_claw", "shihou_slam", "shihou_breath",
			"shihou_tail", "shihou_charge"]:
		_check(ids.has(want), "招式已登记 " + want)
	var region := SecretWorldDB.get_region(SecretWorldDB.REGION_YUANYING)
	_check(String(region.get("core_boss_id", "")) == "world_core_yuanying", "区域 core_boss_id 已接")
	_check(String(region.get("core_where", "")) == "九天门", "核心位置 = 九天门（它镇着这道门）")
	var content := SecretWorldDB.get_region_content(SecretWorldDB.REGION_YUANYING)
	_check((content.get("core_boss", {}) as Dictionary).has("pos"), "大世界内容已摆核心")
	_check(ArtDB.VISUALS.has("world_core_shihou"), "ArtDB 形象已登记")
	var vis: Dictionary = ArtDB.VISUALS.get("world_core_shihou", {})
	_check(String(vis.get("rig", "")) != "" and ResourceLoader.exists(String(vis.get("rig", ""))),
		"石犼 rig 已生成", String(vis.get("rig", "")))

	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	_p.global_position = Vector2(1250.0, 1000.0)
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.is_teleporting = false
	_p.invincible_timer = 0.0

	_boss = (load("res://scenes/world/youming_core_shihou.tscn") as PackedScene).instantiate()
	_boss.configure(cfg.duplicate(true).merged({"pos": Vector2(1000.0, 1000.0)}, true),
		WorldEnemy.KIND_CORE, "镇墟石犼")
	_boss.position = Vector2(1000.0, 1000.0)
	add_child(_boss)
	_boss.set_physics_process(false)
	_boss.set_process(false)
	await get_tree().process_frame

	_check(_boss.get("skin") != null, "石犼骨骼皮肤已挂")
	_check(_boss.get("_steles").size() == 6, "墓庭六根石碣", str(_boss.get("_steles").size()))
	_check(_boss.get_node_or_null("NoiseMarker") != null, "声点 marker 已建")
	_check(_boss.head_top_y() < -200.0, "血条/飘字锚点在头顶", str(_boss.head_top_y()))
	_check(_boss.hit_spheres().size() == 3, "三颗受击球")

	# 进战 + 闻声：目标是 marker，不是玩家
	_boss._tick_threat(0.016)
	_check(bool(_boss.get("_engaged")), "玩家进入仇恨圈即进战")
	_check(_boss.target != null and String(_boss.target.name) == "NoiseMarker",
		"追击目标是最后声点")
	_p.noise_ping_seq = 7
	_p.noise_ping_pos = Vector2(1180.0, 1000.0)
	_boss._deaf_left = 0.0
	_boss._tick_noise(0.016)
	_check((_boss.get("_last_noise") as Vector2).distance_to(Vector2(1180.0, 1000.0)) < 0.1,
		"出手声点被记录")
	# 静步：不再更新
	_boss._last_noise_seq = 7
	_boss._silent_time = 2.0
	_boss._tick_noise(0.016)
	_check((_boss.get("_last_noise") as Vector2).distance_to(Vector2(1180.0, 1000.0)) < 0.1,
		"静步后声点不再刷新")

	# 石碣：撞碑硬直 + 易伤
	var st: Dictionary = (_boss.get("_steles") as Array)[0]
	var st_pos: Vector2 = st.get("pos")
	_boss.global_position = st_pos
	var hp_before: float = _boss.current_hp
	_boss._vuln_left = 0.0
	var hit: bool = _boss._check_stele_hit(90.0)
	_check(hit, "撞碑判定成立")
	_check(int(_boss.get("state")) == 5, "撞碑进入硬直（STAGGER）", str(_boss.get("state")))
	_check(_boss._vuln_left > 4.0, "撞碑易伤 5 秒")
	_boss.take_damage(100.0, _p, "physical", "", false)
	_check(_boss.current_hp < hp_before - 100.0, "易伤期实际多掉血",
		"hp=%.1f" % _boss.current_hp)

	# 二阶段：封眼 + 震塌两根 + 听觉过敏 + 回声计时
	_boss.current_hp = _boss.max_hp * 0.49
	_boss._on_phase_two()
	await get_tree().process_frame
	_check(bool(_boss.get("_p2_started")), "二阶段破封已开启")
	_check(_boss._deaf_left > 0.0, "长吼自我震聋")
	var alive := 0
	for raw in _boss.get("_steles"):
		if bool((raw as Dictionary).get("alive", false)):
			alive += 1
	_check(alive == 4, "二阶段震塌两根石碣", str(alive))
	_check(float(_boss._step_interval()) == 0.30, "二阶段听觉过敏（脚步 0.3s）")

	# 招式：吐息自聋 / 爪击 / 震地 / 尾扫 / 盲扑撞碑
	_p.hp = _p.max_hp * 5.0
	_p.invincible_timer = 0.0
	_p.global_position = _boss.global_position + Vector2(180.0, 0.0)
	_boss._last_noise = _p.global_position
	_boss._update_facing_to_target()
	_boss._deaf_left = 0.0
	_boss._next_core_skill = (skills[3] as Dictionary).duplicate(true)
	var hp0: float = _p.hp
	_boss._cast_core_skill()
	await get_tree().create_timer(0.15).timeout
	_check(_boss._deaf_left > 2.0, "闻声吐息后自聋 2.5 秒")
	_check(_p.hp < hp0, "吐息命中声点方向")
	# 裂石爪
	_p.hp = _p.max_hp * 5.0
	_p.invincible_timer = 0.0
	_boss._last_noise = _p.global_position
	_boss._noise_marker.global_position = _p.global_position
	_boss.target = _boss._noise_marker
	_boss._update_facing_to_target()
	_boss._next_core_skill = (skills[1] as Dictionary).duplicate(true)
	hp0 = _p.hp
	_boss._cast_core_skill()
	await get_tree().create_timer(0.7).timeout
	_check(_p.hp < hp0, "裂石爪结算")
	# 震地 / 尾扫不报错
	_boss._next_core_skill = (skills[2] as Dictionary).duplicate(true)
	_boss._cast_core_skill()
	_boss._next_core_skill = (skills[4] as Dictionary).duplicate(true)
	_boss._cast_core_skill()
	# 盲扑：朝石碣冲，撞碑自硬直
	_boss.state = 0
	_boss._vuln_left = 0.0
	var st2: Dictionary = {}
	for raw in _boss.get("_steles"):
		if bool((raw as Dictionary).get("alive", false)):
			st2 = raw
			break
	if not st2.is_empty():
		_boss.global_position = (st2.get("pos") as Vector2) + Vector2(-420.0, 0.0)
		_boss._last_noise = st2.get("pos")
		_boss._next_core_skill = (skills[0] as Dictionary).duplicate(true)
		var p0: Vector2 = _boss.global_position
		_boss._cast_core_skill()
		for i in 8:
			_boss._tick_dash(0.04)
		_check(_boss.global_position.distance_to(p0) > 100.0, "盲扑真的位移")
		_check(int(_boss.get("state")) == 5 or _boss._vuln_left > 0.0,
			"盲扑撞碑进入硬直/易伤", "state=%d vuln=%.1f" % [_boss.state, _boss._vuln_left])

	# 图鉴 / 掉落 / 护甲
	_check(CodexDB.BOSS_CODEX.has("world_core_shihou"), "图鉴已登记镇墟石犼")
	var codex: Dictionary = CodexDB.BOSS_CODEX.get("world_core_shihou", {})
	_check(ResourceLoader.exists(String(codex.get("portrait", ""))),
		"图鉴卡面存在", String(codex.get("portrait", "")))
	_check(WorldDB.get_boss_name("world_core_shihou") == "镇墟石犼", "图鉴名 = 镇墟石犼")
	_check(int(CodexDB.boss_stats("world_core_shihou").get("hp", 0)) == 44000,
		"图鉴血量 44,000", str(CodexDB.boss_stats("world_core_shihou").get("hp", 0)))
	var card := CodexDB.card_entry("world_core_shihou")
	var card_ids: Array = []
	for raw in (card.get("card_variants", []) as Array):
		card_ids.append(String((raw as Dictionary).get("id", "")))
	_check(card_ids == ["scene", "portrait", "plain", "ink"],
		"卡包四张卡都在", str(card_ids))
	_check(CodexDB.boss_moves_info("world_core_shihou").size() == 6,
		"图鉴六招", str(CodexDB.boss_moves_info("world_core_shihou").size()))
	var drops: Array = CodexDB.boss_drops_info("world_core_shihou")
	var drop_ids: Array = []
	for d in drops:
		drop_ids.append(String((d as Dictionary).get("id", "")))
	_check(drop_ids.has("mat_pojing_di_huashen"), "掉落化神底髓（半枚，需熔铸）")
	_check(drop_ids.has("eq_zhenxu_jia"), "掉落镇墟石甲")
	var armor := ItemDB.get_equipment_template("eq_zhenxu_jia")
	_check(not armor.is_empty(), "护甲模板已登记")
	_check(ResourceLoader.exists(String(armor.get("icon", ""))), "护甲图标存在")

	# 收尾
	_p.queue_free()	# 收尾
	_p.queue_free()
	_boss.queue_free()
	await get_tree().create_timer(0.3).timeout
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
