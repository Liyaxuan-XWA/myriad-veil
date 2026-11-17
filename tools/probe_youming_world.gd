extends Node
## 幽冥灵墟（元婴区）自检：并集几何 / 两面外沿带 / 两条接缝 / 中央山门 /
## 灵兽与野修数值 / 掉落 / 跨区回丹霞与青岚。
## 用法：godot --headless --path . tools/probe_youming_world.tscn

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
	print("\n########## 幽冥灵墟探针 ##########")
	await get_tree().process_frame

	# ---- 数据表 ----
	var yy := SecretWorldDB.get_region(SecretWorldDB.REGION_YUANYING)
	_check(yy.get("name", "") == "幽冥灵墟", "元婴区名称")
	_check(yy.get("rect", Rect2()) == Rect2(-6000.0, 0.0, 6000.0, 4000.0),
		"元婴区在结丹正下、练气正左、同尺寸", str(yy.get("rect")))
	_check(yy.get("realm", "") == "元婴", "元婴区境界")
	_check(yy.get("unlocked", false), "元婴区已解锁")
	_check(SecretWorldDB.get_herb_ids(SecretWorldDB.REGION_YUANYING).size() == 5,
		"元婴草药 5 种")
	_check(SecretWorldDB.get_hide_ids(SecretWorldDB.REGION_YUANYING).size() == 2,
		"元婴兽皮 2 种")
	_check(SecretWorldDB.kill_exp("world_yuanying", true) == 240, "元婴小怪修为 240")
	_check(float(SecretWorldDB.get_cultivator("world_yuanying").get("max_hp", 0)) == 8000.0,
		"元婴野修 8000 血")
	_check(float(SecretWorldDB.get_cultivator("world_yuanying").get("attack_power", 0)) == 105.0,
		"元婴野修 105 攻")
	_check(float(SecretWorldDB.BEASTS["yy_fengya"].get("max_hp", 0)) == 3400.0,
		"幽冥锋牙兽 3400 血")
	_check(float(SecretWorldDB.BEASTS["yy_fengya"].get("attack_power", 0)) == 58.0,
		"幽冥锋牙兽 58 攻")
	_check(float(SecretWorldDB.BEASTS["yy_jianjia"].get("max_hp", 0)) == 4200.0,
		"幽冥坚甲兽 4200 血")
	_check(float(SecretWorldDB.BEASTS["yy_jianjia"].get("attack_power", 0)) == 62.0,
		"幽冥坚甲兽 62 攻")
	var yy_core := SecretWorldDB.get_core_boss(SecretWorldDB.REGION_YUANYING)
	_check(not yy_core.is_empty() and String(yy_core.get("name", "")) == "镇墟石犼",
		"元婴区核心首领 = 镇墟石犼", String(yy_core.get("name", "")))

	# ---- 材料命名与美术 ----
	var mat_bad := ""
	for mid in ["mat_yy_xuecao", "mat_yy_lanyingcao", "mat_yy_liyuanguo",
			"mat_yy_falinghua", "mat_yy_huguteng", "mat_yy_ruishoupi", "mat_yy_jianshoupi"]:
		if not ItemDB.get_material_name(mid).begins_with("幽冥"):
			mat_bad += "%s=%s " % [mid, ItemDB.get_material_name(mid)]
	_check(mat_bad == "", "元婴材料名 = 幽冥 + 草药/兽皮", mat_bad)
	var feng := ArtDB.get_visual("world_beast_youming_fengya")
	var jian := ArtDB.get_visual("world_beast_youming_jianjia")
	_check(not feng.is_empty() and ResourceLoader.exists(String(feng.get("texture", ""))),
		"锋牙兽形象登记且有贴图", String(feng.get("texture", "")))
	_check(not jian.is_empty() and ResourceLoader.exists(String(jian.get("texture", ""))),
		"坚甲兽形象登记且有贴图", String(jian.get("texture", "")))
	_check(ResourceLoader.exists("res://assets/ui/icon/mat_xuecao.png"),
		"元婴材料图标可加载（复用练气图标）")

	for p in ["res://assets/scenes/tiles/youming_mask.png",
			"res://assets/scenes/tiles/youming_grass.png",
			"res://assets/scenes/tiles/youming_road.png",
			"res://assets/scenes/tiles/youming_forestfloor.png",
			"res://assets/scenes/tiles/youming_band_west.png",
			"res://assets/scenes/tiles/youming_band_south.png",
			"res://assets/scenes/tiles/seam_transition_youming_north.png",
			"res://assets/scenes/tiles/seam_transition_youming_east.png",
			"res://assets/scenes/youming_gate.png",
			"res://assets/characters/world/youming_beast_fengya.png",
			"res://assets/characters/world/youming_beast_jianjia.png",
			"res://assets/ui/facilities/world_map_youming.png"]:
		_check(ResourceLoader.exists(p), "资源存在 " + p.get_file())

	# ---- 从区域面板直接进元婴区 ----
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_YUANYING
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	var union: Rect2 = w.get_open_rect()
	_check(w._current_region_id == SecretWorldDB.REGION_YUANYING, "直接进区落在幽冥灵墟")
	_check(union == Rect2(-6000.0, -4000.0, 12000.0, 8000.0), "四区并集 12000x8000",
		str(union))
	_check(w.get_open_regions().size() == 4, "四个区域已解锁")
	_check(w.player.global_position.distance_to(Vector2(-4980.0, 3050.0)) < 100.0,
		"落点在西南传送门旁", str(w.player.global_position))
	_check(w._portal != null and w._portal.global_position.distance_to(
		Vector2(-5200.0, 3200.0)) < 20.0, "传送门在西南角",
		str(w._portal.global_position) if w._portal != null else "null")
	_check(w._title.text.contains("幽冥灵墟") and w._title.text.contains("元婴"),
		"HUD 标题切到幽冥灵墟", w._title.text)
	_check(w._core_status.text.contains("镇墟石犼"), "区域 HUD 显示核心首领",
		w._core_status.text)
	_check(w._terrain_mats.size() == 4, "四区各一张地形材质", "n=%d" % w._terrain_mats.size())
	_check(_count_names(w.get_node("Ground"), "TerrainGround") == 4, "四块地形板")
	_check(_count_names(w.get_node("Ground"), "Band_") == 11, "四区外沿带齐全",
		"n=%d" % _count_names(w.get_node("Ground"), "Band_"))
	_check(_count_names(w.get_node("Ground"), "SeamVertical") == 2, "两条东沿竖向接缝已建",
		"n=%d" % _count_names(w.get_node("Ground"), "SeamVertical"))
	_check(_count_names(w.get_node("Ground"), "SeamTransition_") == 2,
		"两条南北向接缝过渡已建",
		"n=%d" % _count_names(w.get_node("Ground"), "SeamTransition_"))
	var gate := w.get_node_or_null("Ground/RegionLandmark_world_yuanying") as Sprite2D
	_check(gate != null and gate.texture != null, "中央灵墟山门已生成")
	var gate_bottom := Vector2.ZERO
	if gate != null and gate.texture != null:
		gate_bottom = gate.position + Vector2(
			gate.texture.get_width() * gate.scale.x * 0.5,
			gate.texture.get_height() * gate.scale.y)
	_check(gate != null and gate_bottom.distance_to(Vector2(-3000.0, 2000.0)) < 5.0,
		"山门底边压在区域中心", str(gate_bottom))
	_check(absf(w.arena_half_extents.x - 5600.0) < 1.0
		and absf(w.arena_half_extents.y - 3582.5) < 1.0,
		"并集战场尺寸 5600x3582.5", str(w.arena_half_extents))

	# ---- 并集内容数量 ----
	_check(w._content_def["herbs"].size() == 64, "并集草药 64 株",
		"n=%d" % w._content_def["herbs"].size())
	_check(w._content_def["beasts"].size() == 32, "并集灵兽 32 只",
		"n=%d" % w._content_def["beasts"].size())
	_check(w._content_def["qi_orbs"].size() == 24, "并集灵气团 24 个")
	_check(w._content_def["cultivators"].size() == 8, "并集野修槽 8 个")
	_check(w._content_def["portals"].size() == 4, "并集四个传送门")
	_check(w._portals.size() == 4, "四个传送门实体已生成")
	var herb_node = w._resources.get("yy_herb_xuecao_1")
	_check(herb_node != null and String(herb_node.display_name) == "幽冥血参",
		"地面草药显示幽冥血参", String(herb_node.display_name) if herb_node != null else "null")
	var beast_node = w._enemies.get("yy_beast_feng_1")
	_check(beast_node != null and beast_node.max_hp == 3400.0 and beast_node.attack_power == 58.0,
		"锋牙兽按 3400/58 生成", str(beast_node.max_hp) if beast_node != null else "null")

	# ---- 落点安全：出生/传送门旁不能有会主动扑人的野修或灵兽 ----
	var spawn_world := Vector2(-4980.0, 3050.0)
	var yy_center := Vector2(-3000.0, 2000.0)
	var near_bad := ""
	var yy_content := SecretWorldDB.get_region_content(SecretWorldDB.REGION_YUANYING)
	for c in yy_content.get("cultivators", []):
		var dc := (yy_center + Vector2(c.get("pos", Vector2.ZERO))).distance_to(spawn_world)
		if dc < 600.0:
			near_bad += "%s=%.0f " % [c.get("slot_id", "?"), dc]
	for b in yy_content.get("beasts", []):
		var db := (yy_center + Vector2(b.get("pos", Vector2.ZERO))).distance_to(spawn_world)
		if db < 600.0:
			near_bad += "%s=%.0f " % [b.get("node_id", "?"), db]
	_check(near_bad == "", "落点 600 内无野修/灵兽", near_bad)

	# ---- 跨区：北行回丹霞、东行回青岚 ----
	w.player.global_position = Vector2(-3000.0, -100.0)
	await get_tree().create_timer(0.6).timeout
	_check(w._current_region_id == SecretWorldDB.REGION_JIEDAN, "北行跨到赤金丹霞",
		w._title.text)
	w.player.global_position = Vector2(-3000.0, 100.0)
	await get_tree().create_timer(0.6).timeout
	_check(w._current_region_id == SecretWorldDB.REGION_YUANYING, "南行跨回幽冥灵墟",
		w._title.text)
	w.player.global_position = Vector2(100.0, 2000.0)
	await get_tree().create_timer(0.6).timeout
	_check(w._current_region_id == SecretWorldDB.REGION_LIANQI, "东行跨到青岚野",
		w._title.text)
	w.player.global_position = Vector2(-100.0, 2000.0)
	await get_tree().create_timer(0.6).timeout
	_check(w._current_region_id == SecretWorldDB.REGION_YUANYING, "西行跨回幽冥灵墟",
		w._title.text)

	# ---- 元婴野修与掉落 ----
	w._spawn_cultivator({"slot_id": "yy_test_cult", "pos": Vector2(-3000.0, 2050.0),
		"radius": 10.0, "chance": 1.0, "region_id": SecretWorldDB.REGION_YUANYING}, w._now())
	var cult = w._enemies.get("yy_test_cult")
	_check(cult != null and cult.max_hp == 8000.0 and cult.attack_power == 105.0,
		"元婴野修按 8000/105 生成", str(cult.max_hp) if cult != null else "null")
	_check(cult != null and cult.skill_ids.size() == 4, "元婴野修抽到 4 门功法")
	var herb_ids := SecretWorldDB.get_herb_ids(SecretWorldDB.REGION_YUANYING)
	var hide_ids := SecretWorldDB.get_hide_ids(SecretWorldDB.REGION_YUANYING)
	w._drop_beast_loot(Vector2(-3000.0, 2100.0), "yy_fengya")
	var got_hide := false
	for d in w._drops:
		var item: Dictionary = d.get("item")
		if item is Dictionary and String(item.get("id", "")) == "mat_yy_ruishoupi":
			got_hide = true
	_check(got_hide, "幽冥锋牙兽掉幽冥锐兽皮")
	var before: int = int(w._drops.size())
	w._drop_cultivator_loot(Vector2(-3000.0, 2150.0), SecretWorldDB.REGION_YUANYING)
	var bad := false
	for i in range(before, w._drops.size()):
		var item2: Dictionary = w._drops[i].get("item")
		var iid := String(item2.get("id", "")) if item2 is Dictionary else ""
		if iid == "" or not (iid in herb_ids or iid in hide_ids):
			bad = true
	_check(not bad, "元婴野修只掉本区草药/兽皮")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
