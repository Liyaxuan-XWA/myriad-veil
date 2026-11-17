extends Node
## 赤金火麟探针（2026-10-29）：数据 / 骨骼 / 八式 / 霞印 / 二阶段日轮
## 用法：godot --headless --path . res://tools/probe_qilin_boss.tscn

var _fail := 0
var _pass := 0


func _check(ok: bool, name: String, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  ", name, ("  " + detail) if detail != "" else "")


func _ready() -> void:
	# 看门狗：任何 await 卡死都要退出，别让无头进程挂着
	get_tree().create_timer(25.0, true, false, true).timeout.connect(func() -> void:
		print("QILIN PROBE TIMEOUT")
		get_tree().quit(2))
	var cfg: Dictionary = SecretWorldDB.CORE_BOSS_JIEDAN
	_check(String(cfg.get("name", "")) == "赤金火麟", "首领名")
	_check(float(cfg.get("max_hp", 0.0)) == 20000.0, "血量 20000")
	_check(float(cfg.get("attack_power", 0.0)) == 100.0, "物攻 100")
	_check(ResourceLoader.exists(String(cfg.get("scene", ""))), "场景存在")

	# --- 形象 / 骨骼 ---
	var vis: Dictionary = ArtDB.VISUALS.get("world_core_jiedan", {})
	_check(not vis.is_empty(), "ArtDB 形象已注册")
	_check(ResourceLoader.exists(String(vis.get("rig", ""))), "rig.tres 存在")
	_check(ResourceLoader.exists(String(vis.get("texture", ""))), "立绘存在")
	var rig_data := load(String(vis.get("rig", ""))) as BossRigData
	_check(rig_data != null, "rig 数据可加载")
	if rig_data != null:
		_check(rig_data.validate() == "", "rig 自检", rig_data.validate())
		_check(Array(rig_data.part_name) == ["leg_hind_far", "tail", "body",
			"leg_hind", "leg_front", "head"], "分件表", str(rig_data.part_name))
		for p in rig_data.part_tex:
			_check(ResourceLoader.exists(String(p)), "分件贴图 " + String(p).get_file())
	var rig_script := load("res://scripts/visual/boss_rig_qilin.gd") as GDScript
	_check(rig_script != null and rig_script.can_instantiate(), "BossRigQilin 可实例化")
	var rig = rig_script.new() if (rig_script != null and rig_script.can_instantiate()) else null
	_check(rig is BossRig, "BossRigQilin 继承 BossRig")
	if rig != null and rig_data != null:
		_check(rig.setup(rig_data), "rig setup")
		var wanted := ["idle", "walk", "charge", "stomp", "rain", "sunburst",
			"combo", "ring", "eclipse", "meteor", "swipe", "attack"]
		for a in wanted:
			_check(rig.has_animation(a), "骨骼动画 " + a)
		rig.free()

	# --- 八式 / 特效 ---
	var skills: Array = cfg.get("core_skills", [])
	_check(skills.size() == 8, "八式", str(skills.size()))
	var phase2 := 0
	for raw in skills:
		var def: Dictionary = raw
		var id := String(def.get("id", ""))
		_check(id != "", "招式 id")
		_check(int(def.get("phase", 1)) <= 2, "相位 " + id)
		if int(def.get("phase", 1)) == 2:
			phase2 += 1
		var fx := String(def.get("fx_id", ""))
		_check(not ArtDB.get_skill_fx(fx).is_empty(), "特效 " + fx)
		var anim := String(def.get("anim", ""))
		_check(anim != "", "anim " + id)
	_check(phase2 == 2, "二阶段两式", str(phase2))
	_check(ArtDB.get_skill_fx("skill_qilin_brand").size() > 0, "炸印特效")
	_check(ArtDB.get_skill_fx("skill_qilin_swipe").size() > 0, "普攻特效")

	# --- 图鉴 / 掉落 ---
	var codex: Dictionary = CodexDB.BOSS_CODEX.get("world_core_jiedan", {})
	_check(not codex.is_empty(), "图鉴卡条目")
	if not codex.is_empty():
		_check(ResourceLoader.exists(String(codex.get("portrait", ""))), "图鉴立绘")
		_check(String(codex.get("mechanic_title", "")) != "", "机制标题")
	_check(ItemDB.get_equipment_template("eq_huolin_jia").get("equipment_name", "") == "火麟甲", "火麟甲条目")
	_check(ResourceLoader.exists("res://assets/ui/icon/equip_huolin_jia.png"), "火麟甲图标")

	# --- 实例化 ---
	var boss = (load(String(cfg.get("scene", ""))) as PackedScene).instantiate()
	add_child(boss)
	boss.configure(cfg, WorldEnemy.KIND_CORE, "赤金火麟")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(boss is JiedanCoreQilin, "子类正确")
	_check(boss.hit_spheres().size() == 3, "受击三球")
	_check(int(boss.max_hp) == 20000, "实例血量")
	_check(boss.skin != null and boss.skin.render_node is BossRig, "实例走骨骼")
	boss.set_physics_process(false)

	# 霞印：三层自爆、弹反卸印
	boss.call("_add_mark", 1)
	boss.call("_add_mark", 1)
	_check(int(boss.get("_mark_stacks")) == 2, "两层霞印")
	boss.call("on_parried", null)
	_check(int(boss.get("_mark_stacks")) == 1, "弹反卸一层")
	boss.call("_add_mark", 1)
	boss.call("_add_mark", 1)
	_check(int(boss.get("_mark_stacks")) == 0, "三层炸印清空")

	# 二阶段日轮
	boss.phase = 2
	boss.call("_on_phase_two")
	_check(boss.get("_sun") != null, "日轮已生成")
	_check(boss.get("_sun_fx").size() == 3, "日轮 + 两道地环")
	if boss.get("_sun") != null:
		var sun: Sprite2D = boss.get("_sun")
		_check(sun.global_position.distance_to(boss.spawn_home + Vector2(0, -200)) < 2.0,
			"日轮悬在场心上方")
	boss.call("_sun_pulse", boss.spawn_home + Vector2(120, 0))
	_check(int(boss.get("_mark_stacks")) == 1, "脉冲叠印")
	boss.call("_sun_pulse", boss.spawn_home + Vector2(500, 0))
	_check(int(boss.get("_mark_stacks")) == 1, "圈外脉冲不叠")

	# 八式各放一次：不崩、写冷却
	for raw in skills:
		var def: Dictionary = raw
		boss.set("_next_core_skill", def)
		boss.call("_cast_core_skill")
		await get_tree().process_frame
	for raw in skills:
		var def: Dictionary = raw
		var id := String(def.get("id", ""))
		_check(float(boss.get("_core_skill_cds").get(id, -1.0)) > 0.0, "冷却写入 " + id)

	# 火雨落点 / 燃烧坑计时器能跑
	await get_tree().create_timer(0.2, true, false, true).timeout
	boss.call("_die")
	await get_tree().process_frame
	_check(boss.get("_sun") == null, "死亡清日轮")
	_check((boss.get("_meteor_fields") as Array).is_empty(), "死亡清燃烧坑")

	print("QILIN PROBE  pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)
