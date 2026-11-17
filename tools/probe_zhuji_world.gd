extends Node
## 云隐谷内容自检：并集内容 / 区域切换 / 地形节点 / 筑基数值与掉落
## 用法：godot --headless --path . tools/probe_zhuji_world.tscn

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
	print("\n########## 云隐谷内容探针 ##########")
	await get_tree().process_frame

	# ---- 数据表 ----
	_check(SecretWorldDB.get_herb_ids("world_zhuji").size() == 5, "筑基草药 5 种")
	_check(SecretWorldDB.get_hide_ids("world_zhuji").size() == 2, "筑基兽皮 2 种")
	_check(SecretWorldDB.get_herb_ids().size() == 15, "三区草药合计 15 种",
		"n=%d" % SecretWorldDB.get_herb_ids().size())
	_check(SecretWorldDB.kill_exp("world_zhuji", true) == 60, "筑基小怪修为 60")
	_check(SecretWorldDB.kill_exp("world_lianqi", true) == 30, "练气小怪修为 30")
	_check(float(SecretWorldDB.get_cultivator("world_zhuji").get("max_hp", 0)) == 1550.0,
		"筑基野修 1550 血")
	_check(float(SecretWorldDB.BEASTS["zj_fengya"].get("max_hp", 0)) == 620.0, "云隐锋牙兽 620 血")
	_check(float(SecretWorldDB.BEASTS["zj_jianjia"].get("max_hp", 0)) == 780.0, "云隐坚甲兽 780 血")
	for p in ["res://assets/scenes/tiles/zhuji_mask.png",
			"res://assets/scenes/tiles/zhuji_grass.png",
			"res://assets/scenes/tiles/zhuji_road.png",
			"res://assets/scenes/tiles/zhuji_forestfloor.png",
			"res://assets/scenes/tiles/zhuji_band_east.png",
			"res://assets/scenes/tiles/zhuji_band_north.png",
			"res://assets/scenes/tiles/zhuji_band_seam.png",
			"res://assets/ui/facilities/world_map_zhuji.png"]:
		_check(ResourceLoader.exists(p), "资源存在 " + p.get_file())

	# ---- 练气入口（默认落点）----
	SecretWorldDB.pending_spawn_region = ""
	var w1 = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(SecretWorldDB.get_region(w1._current_region_id).get("name", "") == "青岚野",
		"默认落青岚野", w1._current_region_id)
	_check(w1._content_def["herbs"].size() == 48, "并集草药 48 株",
		"n=%d" % w1._content_def["herbs"].size())
	_check(w1._content_def["beasts"].size() == 24, "并集灵兽 24 只",
		"n=%d" % w1._content_def["beasts"].size())
	_check(w1._content_def["qi_orbs"].size() == 18, "并集灵气团 18 个")
	_check(w1._content_def["cultivators"].size() == 6, "并集野修槽 6 个")
	_check(w1._content_def["portals"].size() == 3, "并集三个区域传送门",
		"n=%d" % w1._content_def["portals"].size())
	_check(w1._portals.size() == 3, "三个传送门实体已生成", "n=%d" % w1._portals.size())
	_check(w1._terrain_mats.size() == 3, "三区各一张地形材质", "n=%d" % w1._terrain_mats.size())
	_check(_count_names(w1.get_node("Ground"), "TerrainGround") == 3, "三块地形板")
	_check(_count_names(w1.get_node("Ground"), "Band_") == 9, "三区外沿带 9 段",
		"n=%d" % _count_names(w1.get_node("Ground"), "Band_"))
	_check(w1.get_node_or_null("SeamWall") == null, "接缝无屏障")
	_check(w1.get_node_or_null("Ground/SeamTransition_world_zhuji_world_lianqi") != null,
		"接缝真实地面过渡已建")
	_check(w1.arena_half_extents.x > 2700.0 and w1.arena_half_extents.y > 3500.0,
		"并集战场尺寸", str(w1.arena_half_extents))
	_check(w1.player.global_position.distance_to(Vector2(5330.0, 3420.0)) < 400.0,
		"默认落点在练气传送门旁", str(w1.player.global_position))
	var beast = w1._enemies.get("zj_beast_feng_1")
	_check(beast != null and beast.max_hp == 620.0 and beast.attack_power == 22.0,
		"云隐兽按筑基数值生成", str(beast.max_hp) if beast != null else "null")
	w1.queue_free()
	await get_tree().process_frame

	# ---- 区域面板直接进云隐谷 ----
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_ZHUJI
	var w2 = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w2)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(w2._current_region_id == SecretWorldDB.REGION_ZHUJI, "直接进区落在云隐谷")
	_check(w2.player.global_position.distance_to(Vector2(4980.0, -3050.0)) < 100.0,
		"云隐谷落点在右上角", str(w2.player.global_position))
	_check(w2._portal != null and w2._portal.global_position.distance_to(
		Vector2(5200.0, -3200.0)) < 20.0, "云隐谷传送门在右上角",
		str(w2._portal.global_position) if w2._portal != null else "null")
	_check(w2._portal != null and w2.player.global_position.distance_to(
		w2._portal.global_position) < 400.0, "落点紧邻云隐谷传送门",
		str(w2.player.global_position))
	_check(w2._title.text.contains("云隐谷"), "HUD 标题切到云隐谷", w2._title.text)
	_check(w2._core_status.text.contains("云隐苍角"), "云隐谷核心首领状态提示",
		w2._core_status.text)
	_check(w2._seen_region_ids.has(SecretWorldDB.REGION_ZHUJI), "云隐谷已标记见过")
	var stag = w2._enemies.get("zhuji_core_boss")
	_check(stag != null and stag is ZhujiCoreStag, "云隐苍角已在大世界生成")
	_check(stag != null and stag.has_plates() and stag._plates.size() == 3,
		"苍角随身三片苔甲")
	_check(stag != null and stag.global_position.distance_to(Vector2(3000.0, -2000.0)) < 5.0,
		"苍角站在谷心", str(stag.global_position) if stag != null else "null")
	_check(w2.get_node_or_null("CangjiaoStoneRing") != null, "谷心苔石圈已生成")

	# 跨区：往南走回青岚野，再回来
	w2.player.global_position = Vector2(3000.0, 900.0)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check(w2._current_region_id == SecretWorldDB.REGION_LIANQI, "南行跨回青岚野",
		w2._title.text)
	_check(w2._title.text.contains("青岚野"), "标题切回青岚野", w2._title.text)
	w2.player.global_position = Vector2(3000.0, -400.0)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check(w2._current_region_id == SecretWorldDB.REGION_ZHUJI, "北行跨回云隐谷")

	# ---- 筑基野修与掉落 ----
	w2._spawn_cultivator({"slot_id": "zj_test_cult", "pos": Vector2(3000.0, -400.0),
		"radius": 10.0, "chance": 1.0, "region_id": SecretWorldDB.REGION_ZHUJI}, w2._now())
	var cult = w2._enemies.get("zj_test_cult")
	_check(cult != null and cult.max_hp == 1550.0 and cult.attack_power == 46.0,
		"筑基野修按 1550/46 生成", str(cult.max_hp) if cult != null else "null")
	_check(cult != null and cult.skill_ids.size() == 4, "筑基野修抽到 4 门功法")
	var herb_ids := SecretWorldDB.get_herb_ids(SecretWorldDB.REGION_ZHUJI)
	var hide_ids := SecretWorldDB.get_hide_ids(SecretWorldDB.REGION_ZHUJI)
	w2._drop_beast_loot(Vector2(3000.0, -300.0), "zj_fengya")
	var got_hide := false
	for d in w2._drops:
		var item: Dictionary = d.get("item")
		if item is Dictionary and String(item.get("id", "")) == "mat_zj_ruishoupi":
			got_hide = true
	_check(got_hide, "云隐兽掉云隐锐兽皮")
	var before: int = int(w2._drops.size())
	w2._drop_cultivator_loot(Vector2(3000.0, -200.0), SecretWorldDB.REGION_ZHUJI)
	var bad := false
	for i in range(before, w2._drops.size()):
		var item: Dictionary = w2._drops[i].get("item")
		var iid := String(item.get("id", "")) if item is Dictionary else ""
		if iid == "" or not (iid in herb_ids or iid in hide_ids):
			bad = true
	_check(not bad, "筑基野修只掉本区草药/兽皮")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
