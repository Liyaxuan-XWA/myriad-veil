extends Node
## 赤金丹霞（结丹区）自检：四区并集几何 / 接缝 / 左上角传送门 / 霞心首领 / 数值与掉落
## 用法：godot --headless --path . tools/probe_jiedan_world.tscn

var _fails: Array = []
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _count_names(root: Node, prefix: String) -> int:
	var n := 0
	for c in root.get_children():
		if String(c.name).contains(prefix):
			n += 1
	return n


func _ready() -> void:
	print("\n########## 赤金丹霞探针 ##########")
	await get_tree().process_frame

	# ---- 数据表 ----
	var jd := SecretWorldDB.get_region(SecretWorldDB.REGION_JIEDAN)
	_check(jd.get("name", "") == "赤金丹霞", "结丹区名称")
	_check(jd.get("rect", Rect2()) == Rect2(-6000.0, -4000.0, 6000.0, 4000.0),
		"结丹区在筑基正左、同尺寸", str(jd.get("rect")))
	_check(jd.get("realm", "") == "结丹", "结丹区境界")
	_check(SecretWorldDB.get_herb_ids(SecretWorldDB.REGION_JIEDAN).size() == 5,
		"结丹草药 5 种")
	_check(SecretWorldDB.get_hide_ids(SecretWorldDB.REGION_JIEDAN).size() == 2,
		"结丹兽皮 2 种")
	_check(SecretWorldDB.get_herb_ids().size() == 20, "四区草药合计 20 种",
		"n=%d" % SecretWorldDB.get_herb_ids().size())
	_check(SecretWorldDB.kill_exp("world_jiedan", true) == 120, "结丹小怪修为 120")
	_check(float(SecretWorldDB.get_cultivator("world_jiedan").get("max_hp", 0)) == 4500.0,
		"结丹野修 4500 血")
	_check(float(SecretWorldDB.get_cultivator("world_jiedan").get("attack_power", 0)) == 60.0,
		"结丹野修 60 攻")
	_check(float(SecretWorldDB.BEASTS["jd_fengya"].get("max_hp", 0)) == 1900.0,
		"赤鬃锋牙兽 1900 血")
	_check(float(SecretWorldDB.BEASTS["jd_jianjia"].get("max_hp", 0)) == 2400.0,
		"赤岩坚甲兽 2400 血")
	var core := SecretWorldDB.get_core_boss(SecretWorldDB.REGION_JIEDAN)
	_check(core.get("name", "") == "赤金火麟", "霞心核心首领登记")
	_check(float(core.get("max_hp", 0)) == 20000.0 and float(core.get("attack_power", 0)) == 100.0,
		"火麟 20,000 血 / 100 攻", "%s / %s" % [core.get("max_hp"), core.get("attack_power")])
	_check((core.get("core_skills", []) as Array).size() == 8, "八式登记")
	var p1 := 0
	var p2 := 0
	for raw in core.get("core_skills", []):
		if int((raw as Dictionary).get("phase", 1)) == 1:
			p1 += 1
		else:
			p2 += 1
	_check(p1 == 6 and p2 == 2, "一阶段 6 式 / 二阶段 2 式", "%d / %d" % [p1, p2])
	for p in ["res://assets/scenes/tiles/jiedan_mask.png",
			"res://assets/scenes/tiles/jiedan_grass.png",
			"res://assets/scenes/tiles/jiedan_road.png",
			"res://assets/scenes/tiles/jiedan_forestfloor.png",
			"res://assets/scenes/tiles/jiedan_band_north.png",
			"res://assets/scenes/tiles/jiedan_band_south.png",
			"res://assets/scenes/tiles/jiedan_band_west.png",
			"res://assets/scenes/tiles/seam_transition_west.png",
			"res://assets/scenes/jiedan_sun_altar.png",
			"res://assets/ui/facilities/world_map_jiedan.png"]:
		_check(ResourceLoader.exists(p), "资源存在 " + p.get_file())

	# ---- 命名规则（2026-10-30 用户定）----
	# 材料 = 地区 + 草药/兽皮；丹药 = 境界 + 丹名
	var name_bad := ""
	var region_mats := {
		"青岚": ["mat_xuecao", "mat_lanyingcao", "mat_liyuanguo", "mat_falinghua",
			"mat_huguteng", "mat_ruishoupi", "mat_jianshoupi"],
		"云隐": ["mat_zj_xuecao", "mat_zj_lanyingcao", "mat_zj_liyuanguo",
			"mat_zj_falinghua", "mat_zj_huguteng", "mat_zj_ruishoupi", "mat_zj_jianshoupi"],
		"赤金": ["mat_jd_xuecao", "mat_jd_lanyingcao", "mat_jd_liyuanguo",
			"mat_jd_falinghua", "mat_jd_huguteng", "mat_jd_ruishoupi", "mat_jd_jianshoupi"],
	}
	for prefix in region_mats.keys():
		for mid in region_mats[prefix]:
			var mat_name := ItemDB.get_material_name(String(mid))
			if not mat_name.begins_with(String(prefix)):
				name_bad += "%s=%s " % [mid, mat_name]
	_check(name_bad == "", "四区材料名 = 地区 + 草药/兽皮", name_bad)

	var pill_bad := ""
	for pair in [["mat_xuecao", "练气"], ["mat_zj_xuecao", "筑基"], ["mat_jd_xuecao", "结丹"]]:
		var pn := String(ItemDB.recipe_for_material("pill", String(pair[0])).get("pill_name", ""))
		if not pn.begins_with(String(pair[1])):
			pill_bad += "%s→%s " % [pair[0], pn]
	_check(pill_bad == "", "丹药名 = 境界 + 丹名", pill_bad)

	var jd_pills := 0
	for mid2 in SecretWorldDB.get_herb_ids(SecretWorldDB.REGION_JIEDAN):
		if not ItemDB.recipe_for_material("pill", String(mid2)).is_empty():
			jd_pills += 1
	_check(jd_pills == 5, "结丹 5 味草药各有丹方", "%d/5" % jd_pills)
	var jd_tals := 0
	for hid in SecretWorldDB.get_hide_ids(SecretWorldDB.REGION_JIEDAN):
		if not ItemDB.recipe_for_material("talisman", String(hid)).is_empty():
			jd_tals += 1
	_check(jd_tals == 2, "结丹 2 种兽皮各有符方", "%d/2" % jd_tals)

	# 属性丹说明按各自配方数值出（不能沿用练气档的固定说明）
	var jd_pill_text := ItemDB.effect_text(ItemDB.recipe_for_material("pill", "mat_jd_liyuanguo"))
	var zj_pill_text := ItemDB.effect_text(ItemDB.recipe_for_material("pill", "mat_zj_liyuanguo"))
	_check(jd_pill_text.contains("18%") and zj_pill_text.contains("14%"),
		"丹药说明按境界数值", "%s | %s" % [jd_pill_text, zj_pill_text])
	_check(String(ItemDB.get_consumable("pill_jd_huichundan").get("realm", "")) == "结丹",
		"结丹回春丹登记境界")
	var jd_fire := ItemDB.get_consumable("tal_huoqiu_jiedan")
	_check(is_equal_approx(float(jd_fire.get("battle_effect", {}).get("damage", 0.0)), 500.0),
		"结丹火球符固定伤害 500")
	var jd_metal := ItemDB.get_consumable("tal_jinfeng_jiedan")
	_check(is_equal_approx(float(jd_metal.get("battle_effect", {}).get("damage", 0.0)), 600.0),
		"结丹金锋符固定伤害 600")

	# ---- 从区域面板直接进结丹区 ----
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_JIEDAN
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	var union: Rect2 = w.get_open_rect()
	_check(w._current_region_id == SecretWorldDB.REGION_JIEDAN, "直接进区落在赤金丹霞")
	_check(union == Rect2(-6000.0, -4000.0, 12000.0, 8000.0), "四区并集 12000x8000",
		str(union))
	_check(w.get_open_regions().size() == 4, "四个区域已解锁")
	_check(w.player.global_position.distance_to(Vector2(-4980.0, -3050.0)) < 100.0,
		"落点在左上角传送门旁", str(w.player.global_position))
	_check(w._portal != null and w._portal.global_position.distance_to(
		Vector2(-5200.0, -3200.0)) < 20.0, "传送门在左上角",
		str(w._portal.global_position) if w._portal != null else "null")
	_check(w._title.text.contains("赤金丹霞"), "HUD 标题切到赤金丹霞", w._title.text)
	_check(w._core_status.text.contains("赤金火麟"), "霞心核心首领状态提示",
		w._core_status.text)
	_check(w._terrain_mats.size() == 4, "四区各一张地形材质", "n=%d" % w._terrain_mats.size())
	_check(_count_names(w.get_node("Ground"), "TerrainGround") == 4, "四块地形板")
	_check(_count_names(w.get_node("Ground"), "Band_") == 11, "四区外沿带齐全",
		"n=%d" % _count_names(w.get_node("Ground"), "Band_"))
	_check(_count_names(w.get_node("Ground"), "SeamVertical") == 2, "两条东西向竖向接缝已建")
	_check(_count_names(w.get_node("Ground"), "SeamTransition_") == 2,
		"两条南北向接缝过渡已建")
	_check(absf(w.arena_half_extents.x - 5600.0) < 1.0 and absf(w.arena_half_extents.y - 3582.5) < 1.0,
		"并集战场尺寸 5600x3582.5", str(w.arena_half_extents))

	# ---- 结丹内容数量 ----
	_check(w._content_def["herbs"].size() == 64, "并集草药 64 株",
		"n=%d" % w._content_def["herbs"].size())
	_check(w._content_def["beasts"].size() == 32, "并集灵兽 32 只",
		"n=%d" % w._content_def["beasts"].size())
	_check(w._content_def["qi_orbs"].size() == 24, "并集灵气团 24 个")
	_check(w._content_def["cultivators"].size() == 8, "并集野修槽 8 个")
	_check(w._content_def["portals"].size() == 4, "并集四个传送门")
	_check(w._portals.size() == 4, "四个传送门实体已生成")
	_check(w.get_node_or_null("JiedanSunAltar") != null, "霞心日轮祭坛已生成")
	var herb_node = w._resources.get("jd_herb_xuecao_1")
	_check(herb_node != null and String(herb_node.display_name) == "赤金血参",
		"地面草药显示赤金血参", String(herb_node.display_name) if herb_node != null else "null")

	var boss = w._enemies.get("jiedan_core_boss")
	_check(boss != null and boss.max_hp == 20000.0 and boss.attack_power == 100.0,
		"火麟按 20,000/100 生成", str(boss.max_hp) if boss != null else "null")
	_check(boss != null and boss.global_position.distance_to(Vector2(-3000.0, -2000.0)) < 5.0,
		"火麟站在霞心", str(boss.global_position) if boss != null else "null")

	# ---- 跨区：东行回云隐谷，再往西回丹霞 ----
	w.player.global_position = Vector2(100.0, -2000.0)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check(w._current_region_id == SecretWorldDB.REGION_ZHUJI, "东行跨到云隐谷",
		w._title.text)
	w.player.global_position = Vector2(-500.0, -2000.0)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check(w._current_region_id == SecretWorldDB.REGION_JIEDAN, "西行跨回赤金丹霞",
		w._title.text)

	# ---- 结丹野修与掉落 ----
	w._spawn_cultivator({"slot_id": "jd_test_cult", "pos": Vector2(-3000.0, -1900.0),
		"radius": 10.0, "chance": 1.0, "region_id": SecretWorldDB.REGION_JIEDAN}, w._now())
	var cult = w._enemies.get("jd_test_cult")
	_check(cult != null and cult.max_hp == 4500.0 and cult.attack_power == 60.0,
		"结丹野修按 4500/60 生成", str(cult.max_hp) if cult != null else "null")
	_check(cult != null and cult.skill_ids.size() == 4, "结丹野修抽到 4 门功法")
	var herb_ids := SecretWorldDB.get_herb_ids(SecretWorldDB.REGION_JIEDAN)
	var hide_ids := SecretWorldDB.get_hide_ids(SecretWorldDB.REGION_JIEDAN)
	w._drop_beast_loot(Vector2(-3000.0, -1850.0), "jd_fengya")
	var got_hide := false
	for d in w._drops:
		var item: Dictionary = d.get("item")
		if item is Dictionary and String(item.get("id", "")) == "mat_jd_ruishoupi":
			got_hide = true
	_check(got_hide, "赤鬃兽掉赤金锐兽皮")
	var before: int = int(w._drops.size())
	w._drop_cultivator_loot(Vector2(-3000.0, -1800.0), SecretWorldDB.REGION_JIEDAN)
	var bad := false
	for i in range(before, w._drops.size()):
		var item2: Dictionary = w._drops[i].get("item")
		var iid := String(item2.get("id", "")) if item2 is Dictionary else ""
		if iid == "" or not (iid in herb_ids or iid in hide_ids):
			bad = true
	_check(not bad, "结丹野修只掉本区草药/兽皮")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
