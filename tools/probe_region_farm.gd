extends Node2D
## 区域灵田自检（2026-10-30）：
##   1) 三区各一块田，贴本区传送门，地块存档键按区域分段
##   2) 本区核心首领未死不出田；死后九块田出现
##   3) 三区田并存时地块状态互不串
##   4) 播种种子目录 = 本区草药，按品质从高到低
## 用法：godot --headless --path . tools/probe_region_farm.tscn -- --no-save

var _fails: Array = []
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _farm_nodes(w: Node) -> Array:
	var out: Array = []
	for raw in w._resources.values():
		if raw is FarmPlot:
			out.append(raw)
	return out


func _grade_of(mid: String) -> int:
	return ItemDB.grade_index(String(ItemDB.RARITY_GRADE.get(ItemDB.material_rarity(mid), "")))


func _ready() -> void:
	print("\n########## 区域灵田探针 ##########")
	await get_tree().process_frame
	CharacterData.secret_world["core_kills"] = {}
	CharacterData.home_progress.clear()
	CharacterData.tilled_plots.clear()

	# ---- 数据表：三区各一块田，贴本区传送门 ----
	var expected_bases := {
		SecretWorldDB.REGION_LIANQI: 0,
		SecretWorldDB.REGION_ZHUJI: 9,
		SecretWorldDB.REGION_JIEDAN: 18,
	}
	var prefixes := {}
	for rid in expected_bases.keys():
		var content := SecretWorldDB.get_region_content(rid)
		var farm: Dictionary = content.get("farm", {})
		var region_name := String(SecretWorldDB.get_region(rid).get("name", rid))
		_check(not farm.is_empty(), "%s 登记灵田" % region_name)
		if farm.is_empty():
			continue
		_check(int(farm.get("plot_base", -1)) == int(expected_bases[rid]),
			"%s 灵田地块段 %d" % [region_name, int(expected_bases[rid])],
			"base=%s" % farm.get("plot_base"))
		var prefix := String(farm.get("node_id_prefix", ""))
		_check(prefix != "" and not prefixes.has(prefix), "%s 灵田节点前缀唯一" % region_name, prefix)
		prefixes[prefix] = true
		var portal: Dictionary = content.get("portal", {})
		var gap := Vector2(farm.get("pos", Vector2.ZERO)).distance_to(
			Vector2(portal.get("pos", Vector2.ZERO)))
		_check(gap > 100.0 and gap < 800.0, "%s 灵田贴着本区传送门" % region_name, "d=%.0f" % gap)

	# ---- 种子目录：本区草药 + 品质从高到低 ----
	for rid in expected_bases.keys():
		var region_name := String(SecretWorldDB.get_region(rid).get("name", rid))
		var seeds := SecretWorldDB.get_herb_ids(rid)
		var realm := String(SecretWorldDB.get_region(rid).get("realm", ""))
		var bad := ""
		for mid in seeds:
			if ItemDB.get_material_realm(String(mid)) != realm:
				bad += String(mid) + " "
		_check(seeds.size() == 5 and bad == "", "%s 种子目录只列本区草药" % region_name,
			"n=%d %s" % [seeds.size(), bad])
		var ordered := FarmSeedPanel.sorted_seed_ids(seeds)
		var descending := ordered.size() == seeds.size()
		for i in range(1, ordered.size()):
			if _grade_of(String(ordered[i])) > _grade_of(String(ordered[i - 1])):
				descending = false
		_check(descending, "%s 种子按品质从高到低" % region_name, str(ordered))

	# ---- 世界：未杀核心不出田 ----
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_farm_nodes(w).size() == 0, "核心首领未败时大陆没有灵田")

	# 只杀云隐苍角 → 只有云隐谷门旁的九块田
	CharacterData.secret_world["core_kills"][SecretWorldDB.REGION_ZHUJI] = true
	w._spawn_due_content()
	var zj_plots: Array = []
	for raw in _farm_nodes(w):
		if String((raw as FarmPlot).region_id) == SecretWorldDB.REGION_ZHUJI:
			zj_plots.append(raw)
	_check(zj_plots.size() == 9, "击败云隐苍角后云隐谷出现九块田", "n=%d" % zj_plots.size())
	_check(_farm_nodes(w).size() == 9, "其它区域不跟着出田", "n=%d" % _farm_nodes(w).size())
	var seg_ok := true
	for raw in zj_plots:
		var plot := raw as FarmPlot
		if plot.state_base != 9 or plot.state_index() != 9 + plot.plot_index:
			seg_ok = false
	_check(seg_ok, "云隐田地块键在 9~17 段")
	var zj_portal := Vector2.ZERO
	for pd in w._content_def.get("portals", []):
		if String((pd as Dictionary).get("region_id", "")) == SecretWorldDB.REGION_ZHUJI:
			zj_portal = Vector2((pd as Dictionary).get("pos", Vector2.ZERO))
	var sum := Vector2.ZERO
	for raw in zj_plots:
		sum += (raw as FarmPlot).global_position
	var center: Vector2 = sum / float(maxi(1, zj_plots.size()))
	_check(center.distance_to(zj_portal) < 800.0, "云隐田落点贴着本区传送门",
		"d=%.0f" % center.distance_to(zj_portal))

	# ---- 三区全杀 → 三片田并存，状态互不串 ----
	CharacterData.secret_world["core_kills"][SecretWorldDB.REGION_LIANQI] = true
	CharacterData.secret_world["core_kills"][SecretWorldDB.REGION_JIEDAN] = true
	w._spawn_due_content()
	_check(_farm_nodes(w).size() == 27, "三区各九块田并存", "n=%d" % _farm_nodes(w).size())
	var keys := {}
	var lq_plot: FarmPlot = null
	var zj_plot: FarmPlot = null
	for raw in _farm_nodes(w):
		var plot := raw as FarmPlot
		keys[plot.state_index()] = true
		if plot.region_id == SecretWorldDB.REGION_LIANQI and plot.plot_index == 0:
			lq_plot = plot
		if plot.region_id == SecretWorldDB.REGION_ZHUJI and plot.plot_index == 0:
			zj_plot = plot
	_check(keys.size() == 27, "27 块田的存档键互不重叠", "n=%d" % keys.size())

	# 同号地块种不同种子：各读各的
	CharacterData.plant_plot(0, "mat_xuecao", 60)
	CharacterData.plant_plot(9, "mat_zj_xuecao", 60)
	_check(lq_plot != null and zj_plot != null, "练气/云隐 0 号田都在场")
	if lq_plot != null and zj_plot != null:
		_check(lq_plot.crop_id() == "mat_xuecao" and zj_plot.crop_id() == "mat_zj_xuecao",
			"同号田各自保存作物（0 号 vs 9 号段）",
			"%s / %s" % [lq_plot.crop_id(), zj_plot.crop_id()])
		_check(lq_plot.is_tilled() and zj_plot.is_tilled(),
			"种过作物的地块自动算已开垦")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
