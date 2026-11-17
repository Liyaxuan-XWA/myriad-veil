extends Node
## 补天石获取 / 红色品质 / 不可丢弃（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_mend_stone_source.tscn -- --no-save
##
## 判据：
##   · 通关一个位面（该界域最后一位 BOSS 首杀）→ 补天石 ×1；重复击杀不再给；
##   · 背包满也必得（grant_material_guaranteed）；
##   · 铸神晶 / 补天石：神话（红）品质、不能丢弃、介绍含「无比珍贵的材料，谨慎使用」。

const CRYSTAL := "mat_zhushenjing"
const STONE := "mat_butianshi"

var _passes := 0
var _fails: Array = []
var _saved: Dictionary = {}


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("\n########## 补天石来源 / 红色品质 / 不可丢弃 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _clear_domain(domain_id: String) -> Dictionary:
	var d := WorldDB.get_domain(domain_id)
	var ids: Array = d.get("boss_ids", [])
	var progress: Dictionary = CharacterData.domain_progress.get(domain_id, {})
	progress = {"unlocked": true, "cleared_bosses": ids.slice(0, ids.size() - 1)}
	CharacterData.domain_progress[domain_id] = progress
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": domain_id,
		"boss_id": String(ids[ids.size() - 1]),
	}
	return BattleResolver.resolve_victory()


func _run() -> void:
	_saved = {
		"inventory": CharacterData.inventory.duplicate(true),
		"domain_progress": CharacterData.domain_progress.duplicate(true),
		"boss_progress": CharacterData.boss_progress.duplicate(true),
		"origin_energy": CharacterData.origin_energy,
		"story_progress": CharacterData.story_progress,
		"realm_exp": CharacterData.realm_exp,
		"tutorial": CharacterData.tutorial_data.duplicate(true),
		"step": Tutorial.active_step.duplicate(true),
		"chapter": Tutorial.active_chapter,
		"ev": Tutorial.get("_listen_ev"),
		"cond": Tutorial.get("_listen_cond"),
		"count": Tutorial.get("_count"),
		"need_ok": Tutorial.get("_step_need_ok"),
		"battle": GameState.battle_context.duplicate(true),
	}

	# ===== 1. 品质 / 介绍 / 不可丢弃 =====
	for mid in [CRYSTAL, STONE]:
		var def := ItemDB.get_material(String(mid))
		_check(String(def.get("rarity", "")) == "mythic", "%s 是神话（红）品质" % mid,
			String(def.get("rarity", "")))
		_check(ItemDB.rarity_color("mythic") == UIKit.grade_color("仙器"),
			"%s 的红色 = 仙器色" % mid, str(ItemDB.rarity_color("mythic")))
		_check(String(def.get("desc", "")).contains("无比珍贵的材料，谨慎使用"),
			"%s 介绍含「无比珍贵的材料，谨慎使用」" % mid)
		var item := {"id": String(mid), "name": String(def.get("name", "")),
			"type": "material", "count": 1, "icon": "", "desc": ""}
		_check(not CharacterData.can_discard_item(item),
			"%s 不能丢弃" % mid)
		_check(CharacterData.discard_lock_reason(item) == "珍贵材料",
			"%s 的不可丢弃原因 = 珍贵材料" % mid,
			CharacterData.discard_lock_reason(item))
	var plain := {"id": "mat_xuecao", "name": "血草", "type": "material", "count": 1,
		"icon": "", "desc": ""}
	_check(CharacterData.can_discard_item(plain), "普通材料仍然可以丢弃")

	# ===== 2. 通关一个位面 → 补天石 ×1 =====
	CharacterData.inventory.clear()
	var c0 := CharacterData.count_material(STONE)
	var res := _clear_domain("domain_02")
	_check(CharacterData.count_material(STONE) == c0 + 1,
		"通关冲和界：补天石 +1", "%d → %d" % [c0, CharacterData.count_material(STONE)])
	_check(String(res.get("message", "")).contains("补天石 ×1"),
		"结算回执写明补天石 ×1", String(res.get("message", "")))
	_check(String(res.get("message", "")).contains("蕴仙髓 ×1"),
		"位面结算也写蕴仙髓 ×1", String(res.get("message", "")))
	_check(CharacterData.is_domain_cleared("domain_02"), "冲和界记为已通关")

	# 重复击杀最后一位：不再给
	var c1 := CharacterData.count_material(STONE)
	res = BattleResolver.resolve_victory()
	_check(CharacterData.count_material(STONE) == c1,
		"重复击杀：不再给补天石", "%d → %d" % [c1, CharacterData.count_material(STONE)])

	# ===== 3. 背包满也必得 =====
	CharacterData.inventory.clear()
	var filler := 1
	while CharacterData.bag_count_for(CharacterData.ITEM_MATERIAL) < CharacterData.BAG_CAP_MATERIAL:
		CharacterData.inventory.append({"id": "fill_%d" % filler, "name": "占位",
			"type": "material", "count": 1, "icon": "", "desc": ""})
		filler += 1
	var res2 := _clear_domain("domain_03")
	_check(CharacterData.count_material(STONE) == 1,
		"背包满：通关照给补天石（必得，强制入包）",
		str(CharacterData.count_material(STONE)))
	_check(String(res2.get("message", "")).contains("补天石 ×1"),
		"满包时的回执也写补天石 ×1", String(res2.get("message", "")))

	# ===== 4. 只是打掉界域里的一位（还没通关）不给 =====
	CharacterData.inventory.clear()
	var ids: Array = WorldDB.get_domain("domain_01").get("boss_ids", [])
	CharacterData.domain_progress["domain_01"] = {"unlocked": true, "cleared_bosses": []}
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN, "domain_id": "domain_01",
		"boss_id": String(ids[0])}
	var res_first := BattleResolver.resolve_victory()
	_check(CharacterData.count_material(STONE) == 0,
		"只杀界域第一位（未通关）：不给补天石", str(CharacterData.count_material(STONE)))
	_check(not String(res_first.get("message", "")).contains("补天石"),
		"未通关回执不写补天石", String(res_first.get("message", "")))

	# ===== 5. 每个位面各给一次（换一个界域再验）=====
	CharacterData.inventory.clear()
	var res3 := _clear_domain("domain_04")
	_check(CharacterData.count_material(STONE) == 1,
		"照影界通关：也 +1 补天石", str(CharacterData.count_material(STONE)))
	_check(String(res3.get("message", "")).contains("补天石 ×1"),
		"照影界回执写明补天石 ×1", String(res3.get("message", "")))

	# 还原
	CharacterData.inventory.clear()
	CharacterData.inventory.append_array(_saved["inventory"])
	CharacterData.domain_progress = _saved["domain_progress"]
	CharacterData.boss_progress = _saved["boss_progress"]
	CharacterData.origin_energy = _saved["origin_energy"]
	CharacterData.story_progress = _saved["story_progress"]
	CharacterData.realm_exp = _saved["realm_exp"]
	CharacterData.tutorial_data = _saved["tutorial"]
	Tutorial.active_step = _saved["step"]
	Tutorial.active_chapter = String(_saved["chapter"])
	Tutorial.set("_listen_ev", _saved["ev"])
	Tutorial.set("_listen_cond", _saved["cond"])
	Tutorial.set("_count", _saved["count"])
	Tutorial.set("_step_need_ok", _saved["need_ok"])
	GameState.battle_context = _saved["battle"]
	Tutorial.changed.emit()
	await _frames(2)
	print("")
