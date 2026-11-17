extends Node
## 凡界·换锋符（domain_01 位面法宝）自检（2026-11-07）
## 覆盖：材料 / 掉落 / 配方 / 图鉴 / 美术、模板与现算文案、催动、穿透判定、窗口后回归扇形、清理点。
## 用法：godot --headless --path . res://tools/probe_blade_form.tscn -- --no-save

class DummyEnemy extends Node2D:
	var hits: Array = []

	func _ready() -> void:
		add_to_group("boss")

	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			_element: String = "") -> void:
		hits.append(amount)

	func hit_spheres() -> Array:
		return [Vector3(0.0, 0.0, 18.0)]

	func notify_normal_attack_hit() -> void:
		pass

	func is_dead() -> bool:
		return false


var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _mk_enemy(pos: Vector2) -> DummyEnemy:
	var e := DummyEnemy.new()
	e.global_position = pos
	add_child(e)
	await get_tree().process_frame
	return e


func _ready() -> void:
	print("\n########## 凡界·换锋符 · 远程穿透剑气 ##########")
	_check_data()
	_check_art()
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.set_physics_process(false)
	p.set_process(false)
	p.global_position = Vector2.ZERO
	p.mana = 999.0
	p.hp = p.max_hp
	var tpl := ItemDB.get_treasure_template("tr_blade_form")
	var item := CharacterData.make_treasure_instance(tpl)

	var near := await _mk_enemy(Vector2(60.0, 0.0))
	var far := await _mk_enemy(Vector2(300.0, 0.0))
	var side := await _mk_enemy(Vector2(160.0, 120.0))
	p.attack_dir = Vector2.RIGHT

	# 催动
	p._start_blade_form_treasure(item, tpl)
	_check(p._blade_form_left > 4.9, "窗口开启 5 秒")
	_check(is_equal_approx(p.mana, 984.0), "消耗 15 灵力", "mana=%.1f" % p.mana)
	_check(p.summon_cooldown_left("tr_blade_form") > 21.0, "进入 22 秒冷却")
	_check(p.treasure_status_left("tr_blade_form") > 4.9, "法宝栏显示剩余窗口")
	var mana_after: float = float(p.mana)
	p._start_blade_form_treasure(item, tpl)
	_check(is_equal_approx(p.mana, mana_after), "窗口内重复催动不再扣蓝")

	# 穿透核心：近 / 远两只在同一条直线上都吃到剑气，侧向偏出长条的不吃
	p._perform_attack_hit()
	_check(near.hits.size() == 1, "近处目标命中", str(near.hits.size()))
	_check(far.hits.size() == 1, "远处目标被剑气穿透", str(far.hits.size()))
	_check(side.hits.is_empty(), "侧向偏出长条不命中", str(side.hits.size()))

	# 窗口结束后回归原本的近战扇形
	near.hits.clear()
	far.hits.clear()
	p._stop_blade_form()
	p._perform_attack_hit()
	_check(near.hits.size() == 1, "窗口后回归近战扇形", str(near.hits.size()))
	_check(far.hits.is_empty(), "窗口后远处不再命中", str(far.hits.size()))

	# 灵力不足 / 清理点
	p._summon_cooldowns.clear()
	p.mana = 0.0
	p._start_blade_form_treasure(item, tpl)
	_check(p._blade_form_left == 0.0, "灵力不足不启动")
	p._blade_form_left = 2.0
	p.reset_player()
	_check(p._blade_form_left == 0.0, "重开战斗清空换锋状态")

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_data() -> void:
	print("\n-- 数据 / 配方 / 文案 --")
	var tpl := ItemDB.get_treasure_template("tr_blade_form")
	_check(not tpl.is_empty(), "模板已登记")
	_check(String(tpl.get("treasure_name", "")) == "凡界·换锋符", "显示名")
	_check(String(tpl.get("active_type", "")) == "blade_form", "主动类型")
	_check(String(tpl.get("treasure_grade", "")) == "法器", "品阶低于后三位面")
	_check(bool(tpl.get("is_plane_treasure", false)) \
		and String(tpl.get("domain_id", "")) == "domain_01", "属第一位面")
	var stats := ItemDB.treasure_active_stats({}, tpl)
	_check(String(stats.get("kind", "")) == "blade_form", "主动数值类型")
	_check(is_equal_approx(float(stats.get("mana", 0.0)), 15.0), "耗蓝 15")
	_check(is_equal_approx(float(stats.get("duration", 0.0)), 5.0), "持续 5 秒")
	_check(is_equal_approx(float(stats.get("cooldown", 0.0)), 22.0), "冷却 22 秒")
	_check(is_equal_approx(float(stats.get("range", 0.0)), 320.0), "射程 320")
	_check(is_equal_approx(float(stats.get("width", 0.0)), 96.0), "宽度 96")
	var up := ItemDB.treasure_active_stats(
		{"equipment_id": "tr_blade_form", "equipment_grade": "灵器"}, tpl)
	_check(is_equal_approx(float(up.get("duration", 0.0)), 6.0), "进阶 +1 秒")
	var lines := ItemDB.treasure_effect_lines(CharacterData.make_treasure_instance(tpl))
	_check(lines.size() >= 5, "说明按当前数值现算", str(lines.size()))
	var text := "\n".join(lines)
	_check(text.contains("换锋") and text.contains("穿透"), "说明写明换锋与穿透", text)
	var recipe := ItemDB.get_plane_treasure_recipe("domain_01")
	_check(String(recipe.get("result_id", "")) == "tr_blade_form", "domain_01 配方已登记")
	var mats: Array = recipe.get("material_ids", [])
	_check(mats.size() == 3, "配方三件材料齐", str(mats))
	for mid in ["mat_fanjie_huya", "mat_fanjie_duanren", "mat_fanjie_jianxie"]:
		_check(not ItemDB.get_material(String(mid)).is_empty(), "材料登记：" + String(mid))
		_check(str(CodexDB.SOURCES.get(String(mid), "")) != "", "图鉴来源：" + String(mid))
	_check(str(CodexDB.SOURCES.get("tr_blade_form", "")) != "", "图鉴来源：换锋符")
	var drop_map := {
		"boss_huyao": "mat_fanjie_huya",
		"boss_01": "mat_fanjie_duanren",
		"boss_01_c": "mat_fanjie_jianxie",
	}
	for bid in drop_map.keys():
		var found := false
		for raw in ItemDB.get_drops_for_boss(String(bid)):
			var e: Dictionary = raw
			if String(e.get("item_id", "")) == String(drop_map[bid]):
				found = true
		_check(found, "掉落登记：" + String(bid), String(drop_map[bid]))


func _check_art() -> void:
	print("\n-- 美术 / 特效 --")
	for f in ["res://assets/ui/icon/mat_fanjie_huya.png",
			"res://assets/ui/icon/mat_fanjie_duanren.png",
			"res://assets/ui/icon/mat_fanjie_jianxie.png",
			"res://assets/ui/icon/tr_blade_form.png",
			"res://assets/effects/skills/blade_form_qi.png"]:
		_check(ResourceLoader.exists(f), "美术落盘：" + f)
	var fx := ArtDB.get_effect("fx_blade_form_qi")
	_check(not fx.is_empty(), "剑气特效已登记")
	_check(String(fx.get("texture", "")) != "", "特效贴图已接线",
		String(fx.get("texture", "")))
	_check(String(fx.get("fallback_kind", "")) == "rect_beam", "缺图可程序化回退")
