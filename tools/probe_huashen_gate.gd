extends Node
## 破境材料全链探针（2026-11-02）：残晶 → 锻造台熔铸 → 完整破境晶 → 大突破 / 九天门
##
## 规则：
##   地髓 = 各境界大陆区域核心首领首杀必得（半枚）
##   天髓 = 对应位面**第三位** BOSS 首杀必得（半枚；照影界第三位是叠纸 boss_04_c）
##   两枚在锻造台「熔铸」页合璧 → 完整破境晶 → 才算大突破材料
##   化神例外：完整晶拿去幽冥灵墟中心的九天门开门（不吃材料），
##             进九天之上后在中央化神坛上才吃掉晶、当场突破。
##
## 用法：godot --headless --path . res://tools/probe_huashen_gate.tscn -- --no-save

const REALMS := ["筑基", "结丹", "元婴", "化神"]
## 目标境界 → [区域 id, 位面第三位 BOSS id, 位面 id]
const CHAIN := {
	"筑基": ["world_lianqi", "boss_01_c", "domain_01"],
	"结丹": ["world_zhuji", "boss_02_c", "domain_02"],
	"元婴": ["world_jiedan", "boss_03_c", "domain_03"],
	"化神": ["world_yuanying", "boss_04_c", "domain_04"],
}


var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _count(mid: String) -> int:
	return CharacterData.count_material(mid)


func _take_all(mid: String) -> void:
	var i := CharacterData.inventory.size() - 1
	while i >= 0:
		if String(CharacterData.inventory[i].get("id", "")) == mid:
			CharacterData.remove_item_at(i, int(CharacterData.inventory[i].get("count", 1)))
		i -= 1


func _clear_chain() -> void:
	for r in REALMS:
		var rec := ItemDB.get_pojing_synth_recipe(r)
		for k in ["di", "tian", "result"]:
			_take_all(String(rec.get(k, "")))


func _set_yuanying_peak() -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = CharacterData.REALM_STAGES.size() - 1
	CharacterData.realm_exp = CharacterData.get_stage_exp_required()


func _ready() -> void:
	print("\n########## 破境材料链探针 ##########")
	var snap_realm := CharacterData.current_realm
	var snap_stage := CharacterData.realm_stage
	var snap_exp := CharacterData.realm_exp
	var snap_limit := CharacterData.current_world_realm_limit
	var snap_gate := CharacterData.huashen_gate_opened
	var snap_bp := CharacterData.boss_progress.duplicate(true)
	var snap_dp := CharacterData.domain_progress.duplicate(true)
	var held := {}
	for r in REALMS:
		var rec := ItemDB.get_pojing_synth_recipe(r)
		for k in ["di", "tian", "result"]:
			var mid := String(rec.get(k, ""))
			held[mid] = _count(mid)

	_test_items()
	_test_icon_art()
	_test_core_rewards()
	_test_first_kill()
	await _test_forge()
	_test_gate_and_altar()
	await _test_panel_refuses()
	_test_region()

	CharacterData.current_realm = snap_realm
	CharacterData.realm_stage = snap_stage
	CharacterData.realm_exp = snap_exp
	CharacterData.current_world_realm_limit = snap_limit
	CharacterData.huashen_gate_opened = snap_gate
	CharacterData.boss_progress = snap_bp
	CharacterData.domain_progress = snap_dp
	_clear_chain()
	for mid in held:
		if int(held[mid]) > 0:
			CharacterData.grant_material(String(mid), int(held[mid]))

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


## ===== 1. 十二件材料本身 =====
func _test_items() -> void:
	_clear_chain()
	for r in REALMS:
		var rec := ItemDB.get_pojing_synth_recipe(r)
		var di := ItemDB.get_material(String(rec.get("di", "")))
		var tian := ItemDB.get_material(String(rec.get("tian", "")))
		var full := ItemDB.get_material(String(rec.get("result", "")))
		_check(not di.is_empty() and not tian.is_empty() and not full.is_empty(),
			"%s 三件材料都已登记" % r)
		_check(String(di.get("name", "")).ends_with("底髓")
			and String(tian.get("name", "")).ends_with("天髓"),
			"%s 残晶命名成对" % r,
			"%s / %s" % [String(di.get("name", "")), String(tian.get("name", ""))])
		_check(ResourceLoader.exists(String(di.get("icon", "")))
			and ResourceLoader.exists(String(tian.get("icon", ""))),
			"%s 残晶图标存在" % r)
		_check("天髓" in String(di.get("desc", "")) or "熔铸" in String(di.get("desc", "")),
			"%s 地髓描述指向合成" % r)
		var req := ItemDB.get_breakthrough_requirements(r)
		_check(req.has(String(rec.get("result", ""))) and req.size() == 1,
			"%s 突破材料 = 一枚完整晶" % r, str(req))
		_check(ItemDB.is_breakthrough_material(String(rec.get("di", "")))
			and ItemDB.is_breakthrough_material(String(rec.get("tian", ""))),
			"%s 两枚残晶也不可丢弃" % r)
	_check(not ItemDB.is_breakthrough_material("mat_yy_xuecao"), "普通材料仍可丢弃")
	_check(ItemDB.find_pojing_recipe("mat_pojing_di_zhuji", "mat_pojing_tian_zhuji")
		.get("result", "") == "mat_pojing_zhuji", "熔铸匹配：地+天（正序）")
	_check(ItemDB.find_pojing_recipe("mat_pojing_tian_zhuji", "mat_pojing_di_zhuji")
		.get("result", "") == "mat_pojing_zhuji", "熔铸匹配：不分先后")
	_check(ItemDB.find_pojing_recipe("mat_pojing_di_zhuji", "mat_pojing_di_zhuji").is_empty(),
		"两枚同名残晶不成方")
	_check(ItemDB.find_pojing_recipe("mat_pojing_di_zhuji", "mat_pojing_tian_jiedan").is_empty(),
		"跨档搭配不成方")
	_check(ItemDB.find_pojing_recipe("mat_pojing_di_zhuji", "").is_empty(), "缺一枚不成方")


## ===== 2. 十二件材料的图标必须各有各的图 =====
## 2026-10-26 那批占位是「四件完整晶共用一张 mat_pojing_zhuji.png」，2026-11-02 补正式素材。
## 这条守卫防的是以后加材料时又悄悄把 icon 指回复用的那张。
func _test_icon_art() -> void:
	var seen := {}
	for r in REALMS:
		var rec := ItemDB.get_pojing_synth_recipe(r)
		for k in ["di", "tian", "result"]:
			var mid := String(rec.get(k, ""))
			var path := String(ItemDB.get_material(mid).get("icon", ""))
			_check(path == "res://assets/ui/icon/%s.png" % mid,
				"%s 图标指向自己的文件名" % mid, path)
			if seen.has(path):
				_check(false, "图标不被复用",
					"%s 与 %s 同为 %s" % [mid, String(seen[path]), path])
			seen[path] = mid
			var img := Image.load_from_file(path)
			_check(img != null and img.get_width() == 256 and img.get_height() == 256,
				"%s 图标 256×256" % mid,
				"%dx%d" % [img.get_width(), img.get_height()] if img != null else "读不出来")
	_check(seen.size() == 12, "12 件材料 12 张不同图标", "n=%d" % seen.size())
	# 化神坛进了世界：贴图在盘上，且节点会真的挂出来
	_check(ResourceLoader.exists("res://assets/scenes/world/huashen_altar.png"),
		"化神坛贴图已落盘")


## ===== 3. 区域核心首领改发地髓 =====
func _test_core_rewards() -> void:
	for r in REALMS:
		var di := String(ItemDB.get_pojing_synth_recipe(r).get("di", ""))
		var region := SecretWorldDB.get_region(String(CHAIN[r][0]))
		_check(not region.is_empty(), "%s 区域可查（%s）" % [r, String(CHAIN[r][0])])
		_check((region.get("core_reward", {}) as Dictionary).has(di),
			"%s 区域 core_reward 发的是地髓" % r, str(region.get("core_reward", {})))
		var core := SecretWorldDB.get_core_boss(String(CHAIN[r][0]))
		_check((core.get("reward", {}) as Dictionary).has(di),
			"%s 核心首领 reward 与区域一致" % r, str(core.get("reward", {})))
	_check((SecretWorldDB.get_region(SecretWorldDB.REGION_HUASHEN)
		.get("core_reward", {}) as Dictionary).is_empty(),
		"九天之上没有核心首领，也不发材料")


## ===== 4. 位面第三位 BOSS 首杀发天髓 =====
func _test_first_kill() -> void:
	_clear_chain()
	for r in REALMS:
		var boss_id := String(CHAIN[r][1])
		var domain_id := String(CHAIN[r][2])
		var tian := String(ItemDB.get_pojing_synth_recipe(r).get("tian", ""))
		CharacterData.boss_progress.erase(boss_id)
		_check(CharacterData.mark_boss_killed(domain_id, boss_id),
			"%s 首杀按第一次算（%s）" % [r, boss_id])
		_check(_count(tian) == 1, "%s 首杀必得天髓（%s）" % [r, tian], "n=%d" % _count(tian))
		CharacterData.mark_boss_killed(domain_id, boss_id)
		_check(_count(tian) == 1, "%s 重复击杀不重发天髓" % r, "n=%d" % _count(tian))
		_take_all(tian)
		CharacterData.ensure_first_kill_rewards()
		_check(_count(tian) == 1, "%s 天髓丢了会自愈补发" % r, "n=%d" % _count(tian))
		CharacterData.boss_progress.erase(boss_id)
		_take_all(tian)
		CharacterData.ensure_first_kill_rewards()
		_check(_count(tian) == 0, "%s 没打过就不发天髓" % r, "n=%d" % _count(tian))


## ===== 5. 锻造台「熔铸」页真的能合成 =====
func _test_forge() -> void:
	_clear_chain()
	var panel = load("res://scripts/ui/panels/forge_panel.gd").new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	CharacterData.grant_material("mat_pojing_di_zhuji", 1)
	CharacterData.grant_material("mat_pojing_tian_zhuji", 1)
	var ids: Array = []
	for c in panel._synth_candidates():
		ids.append(String((c as Dictionary).get("id", "")))
	_check(ids.has("mat_pojing_di_zhuji") and ids.has("mat_pojing_tian_zhuji"),
		"两枚残晶出现在熔铸候选里", str(ids))
	panel._synth_slot_data = [
		_slot_of(panel, "mat_pojing_di_zhuji"), _slot_of(panel, "mat_pojing_tian_zhuji"), {},
	]
	_check(panel._matched_pojing_recipe().get("result", "") == "mat_pojing_zhuji",
		"面板识别出这是一档合璧方")
	_check(String(panel._synth_block_reason()) == "", "识别成立时不再拦")
	panel._refresh_synth()
	_check("破境晶" in String(panel._melt_button.text), "按钮写明这次出的是破境晶",
		panel._melt_button.text)
	panel._try_synthesize()
	await get_tree().create_timer(2.0).timeout
	_check(_count("mat_pojing_zhuji") == 1, "合成产出完整筑基破境晶",
		"n=%d" % _count("mat_pojing_zhuji"))
	_check(_count("mat_pojing_di_zhuji") == 0 and _count("mat_pojing_tian_zhuji") == 0,
		"两枚残晶被吃掉")
	# 混投要拦住：残晶不与其他料同炉
	CharacterData.grant_material("mat_pojing_di_zhuji", 1)
	panel._synth_slot_data = [
		_slot_of(panel, "mat_pojing_di_zhuji"),
		{"kind": "soul", "id": "soul_boss_huyao", "name": "元魂", "count": 1, "desc": "", "icon": ""},
		{},
	]
	var reason := String(panel._synth_block_reason())
	_check(reason != "" and "不与其他料同炉" in reason, "残晶与元魂混投被拦", reason)
	_check(_count("mat_pojing_di_zhuji") == 1, "被拦下时不吃材料")
	panel.close()
	panel.queue_free()
	await get_tree().process_frame
	_clear_chain()


## 从面板候选表里取一份真实槽位数据（形状与玩家点击放进去的完全一致）
func _slot_of(panel, mid: String) -> Dictionary:
	for c in panel._synth_candidates():
		if String((c as Dictionary).get("id", "")) == mid:
			return c
	return {"kind": "pojing", "id": mid, "name": mid, "count": 1, "desc": "", "icon": ""}


## ===== 6. 九天门（不吃料）+ 化神坛（吃料突破）=====
func _test_gate_and_altar() -> void:
	_clear_chain()
	CharacterData.huashen_gate_opened = false
	CharacterData.current_realm = "结丹"
	CharacterData.realm_stage = 0
	CharacterData.realm_exp = 0
	_check(not bool(CharacterData.huashen_gate_check().get("ok", false)),
		"结丹修为开不了九天门", String(CharacterData.huashen_gate_check().get("message", "")))
	_set_yuanying_peak()
	CharacterData.realm_exp -= 1
	_check(not bool(CharacterData.huashen_gate_check().get("ok", false)),
		"修为差一点都不算圆满")
	CharacterData.realm_exp += 1
	CharacterData.grant_material("mat_pojing_di_huashen", 1)
	CharacterData.grant_material("mat_pojing_tian_huashen", 1)
	var c := CharacterData.huashen_gate_check()
	_check(not bool(c.get("ok", false)), "只有两枚残晶开不了门（必须先合成）",
		String(c.get("message", "")))
	_check("熔铸" in String(c.get("message", "")), "提示会教玩家去熔铸",
		String(c.get("message", "")))
	_clear_chain()
	CharacterData.grant_material("mat_pojing_huashen", 1)
	c = CharacterData.huashen_gate_check()
	_check(bool(c.get("ok", false)), "完整化神破境晶 + 元婴后期圆满 → 可开门",
		String(c.get("message", "")))
	_check(CharacterData.open_huashen_gate(), "按 F 开门成功")
	_check(CharacterData.huashen_gate_opened, "门标记为已开（存档位）")
	_check(_count("mat_pojing_huashen") == 1, "开门不吃晶", "n=%d" % _count("mat_pojing_huashen"))
	_check(CharacterData.current_realm == "元婴", "开门本身不突破", CharacterData.current_realm)
	_check("九天之上" in CharacterData.huashen_gate_prompt(),
		"开过之后门前提示改口", CharacterData.huashen_gate_prompt())
	var a := CharacterData.huashen_altar_check()
	_check(bool(a.get("ok", false)), "登坛条件成立", String(a.get("message", "")))
	_check(String(a.get("message", "")).contains("炼化化神破境晶"),
		"登坛提示写「炼化化神破境晶」", String(a.get("message", "")))
	_check(CharacterData.perform_huashen_breakthrough(), "登坛突破成功")
	_check(CharacterData.current_realm == "化神", "境界推到化神", CharacterData.current_realm)
	_check(_count("mat_pojing_huashen") == 0, "晶在坛上被吃掉", "n=%d" % _count("mat_pojing_huashen"))
	_check(CharacterData.current_world_realm_limit == "化神", "境界上限推到化神")
	_check(not bool(CharacterData.huashen_altar_check().get("ok", false)),
		"已经化神就不再吃第二枚晶", String(CharacterData.huashen_altar_check().get("message", "")))


## 境界面板不许就地化神；前三档照旧在面板突破
func _test_panel_refuses() -> void:
	CharacterData.huashen_gate_opened = false
	CharacterData.current_world_realm_limit = "化神"
	_clear_chain()
	var panel = load("res://scripts/ui/panels/realm_panel.gd").new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	# 先验前三档：完整晶进面板 → 真的突破并吃掉
	CharacterData.current_realm = "练气"
	CharacterData.realm_stage = CharacterData.REALM_STAGES.size() - 1
	CharacterData.realm_exp = CharacterData.get_stage_exp_required()
	CharacterData.grant_material("mat_pojing_zhuji", 1)
	panel._on_breakthrough()
	await get_tree().create_timer(2.2).timeout
	_check(CharacterData.current_realm == "筑基", "练气→筑基仍在面板突破",
		CharacterData.current_realm)
	_check(_count("mat_pojing_zhuji") == 0, "面板吃掉的是完整的筑基破境晶")
	# 再验化神：摆回元婴后期圆满 + 一枚完整晶
	_set_yuanying_peak()
	CharacterData.grant_material("mat_pojing_huashen", 1)
	panel._on_breakthrough()
	await get_tree().process_frame
	_check(CharacterData.current_realm == "元婴", "境界面板点突破不会就地化神",
		CharacterData.current_realm)
	_check(_count("mat_pojing_huashen") == 1, "面板也不吃掉化神破境晶")
	var said := _status_line(panel)
	_check("九天门" in said, "面板把人指到九天门", said)
	panel.close()
	panel.queue_free()
	await get_tree().process_frame


func _test_region() -> void:
	var hs := SecretWorldDB.get_region(SecretWorldDB.REGION_HUASHEN)
	CharacterData.huashen_gate_opened = false
	_check(not SecretWorldDB.is_region_open(hs), "门没开 → 九天之上进不去")
	CharacterData.huashen_gate_opened = true
	_check(SecretWorldDB.is_region_open(hs), "门开过 → 九天之上永久可进")
	var yy := SecretWorldDB.get_region(SecretWorldDB.REGION_YUANYING)
	var lm = yy.get("landmark", {})
	var expect: Vector2 = (yy.get("rect", Rect2()) as Rect2).get_center() \
		+ Vector2((lm as Dictionary).get("pos", Vector2.ZERO))
	_check(SecretWorldDB.huashen_gate_pos().distance_to(expect) < 0.01,
		"九天门交互点与山门贴图同一坐标", str(SecretWorldDB.huashen_gate_pos()))
	var altar := SecretWorldDB.huashen_altar_pos()
	_check((hs.get("rect", Rect2()) as Rect2).has_point(altar),
		"化神坛落在九天之上区域内", str(altar))
	var spawn: Vector2 = (SecretWorldDB.get_region_content(SecretWorldDB.REGION_HUASHEN)
		.get("spawn", {}) as Dictionary).get("pos", Vector2.ZERO)
	_check(altar.distance_to(spawn) > 400.0, "化神坛不在落点上（一进场不会贴着坛）",
		"%.0f" % altar.distance_to(spawn))
	var gate := HuashenGate.new()
	gate.setup_gate()
	_check(gate.kind == WorldResource.KIND_GATE, "门是 gate 种类", gate.kind)
	_check("九天门" in gate.prompt_text() or "九天之上" in gate.prompt_text(),
		"门前提示带门名", gate.prompt_text())
	var t := HuashenGate.new()
	t.setup_altar()
	_check(t.kind == WorldResource.KIND_ALTAR, "坛是 altar 种类", t.kind)
	_check(t.reach_distance() < gate.reach_distance(), "坛的交互范围比门紧一些")
	gate.free()
	t.free()


func _status_line(node: Node) -> String:
	for c in node.get_children():
		if String(c.name) == "StatusLine" and c is Label:
			return (c as Label).text
		var deep := _status_line(c)
		if deep != "":
			return deep
	return ""
