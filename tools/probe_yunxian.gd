extends Node
## 蕴仙髓：化神仙器淬炼 / 三个来源（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_yunxian.tscn -- --no-save
##
## 判据：
##   · 化神期仙器不再被境界锁挡，但只能点顶栏「蕴仙」淬炼，每次消耗 1 枚
##     （不消耗锻造晶石）；常规敲砧与自动锻造都被拒；
##     低境界仙器 / 法宝仙器仍然锁；仙器满 +10 仍指向铸神。
##   · 蕴仙髓 = 神话红品质、不可丢弃、介绍含「无比珍贵」。
##   · 主线 BOSS 首杀各 1；万界塔 BOSS 5%（独立掷骰，区域核心重战不吃）；
##     九天之上的祭坛第二阶段 12 枚。

const WORLD_SCENE := "res://scenes/world/secret_world.tscn"
const WEAPON := "eq_qingfengjian"
const CRYSTAL := "mat_duanzaojingshi"
const YUNXIAN := "mat_yunxiansui"
const STONE := "mat_butianshi"
const DIVINE := "mat_zhushenjing"

var _passes := 0
var _fails: Array = []


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


func _tpl(eid: String) -> Dictionary:
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		if String((raw as Dictionary).get("equipment_id", "")) == eid:
			return CharacterData.make_equipment_instance(raw as Dictionary)
	return {}


func _xian(level: int = 0) -> Dictionary:
	var it := _tpl(WEAPON)
	it["equipment_grade"] = "仙器"
	it["enhancement_level"] = level
	return it


func _ready() -> void:
	print("\n########## 蕴仙髓 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	var saved_inv: Array = CharacterData.inventory.duplicate(true)
	var saved_realm := CharacterData.current_realm
	var saved_domain: Dictionary = CharacterData.domain_progress.duplicate(true)
	var saved_boss: Dictionary = CharacterData.boss_progress.duplicate(true)
	var saved_energy := CharacterData.origin_energy
	var saved_story := CharacterData.story_progress
	var saved_gate := CharacterData.huashen_gate_opened
	var saved_altars: Dictionary = (CharacterData.secret_world.get("god_altars", {}) as Dictionary).duplicate(true)
	var saved_battle: Dictionary = GameState.battle_context.duplicate(true)

	# ===== 1. 材料 =====
	var def := ItemDB.get_material(YUNXIAN)
	_check(not def.is_empty(), "蕴仙髓已登记")
	_check(String(def.get("rarity", "")) == "mythic", "蕴仙髓是神话（红）品质",
		String(def.get("rarity", "")))
	_check(ItemDB.rarity_color("mythic") == UIKit.grade_color("仙器"), "红色 = 仙器色")
	_check(String(def.get("desc", "")).contains("无比珍贵"), "介绍含「无比珍贵」")
	var yitem := {"id": YUNXIAN, "name": "蕴仙髓", "type": "material", "count": 1,
		"icon": "", "desc": ""}
	_check(not CharacterData.can_discard_item(yitem), "蕴仙髓不能丢弃")
	var tex := load(String(def.get("icon", ""))) as Texture2D
	_check(tex != null and tex.get_width() == 256 and tex.get_height() == 256,
		"蕴仙髓图标 256×256", str(tex.get_size()) if tex != null else "null")

	# ===== 2. 化神仙器：吃蕴仙髓，不吃晶石 =====
	CharacterData.current_realm = "化神"
	CharacterData.inventory.clear()
	CharacterData.grant_material(CRYSTAL, 100)
	var x := _xian(0)
	var r := CharacterData.enhance_item(x)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("蕴仙髓不足"),
		"0 髓：仙器强化被拒", String(r.get("message", "")))
	_check(CharacterData.count_material(CRYSTAL) == 100, "被拒时不扣锻造晶石")
	CharacterData.grant_material(YUNXIAN, 1)
	r = CharacterData.enhance_item(x)
	_check(bool(r.get("ok", false)), "化神期仙器可用蕴仙髓强化", String(r.get("message", "")))
	_check(CharacterData.count_material(YUNXIAN) == 0, "消耗蕴仙髓 ×1")
	_check(CharacterData.count_material(CRYSTAL) == 100, "仙器强化不吃锻造晶石")

	# 满 +10：仍然指向铸神，不消耗髓
	CharacterData.grant_material(YUNXIAN, 1)
	var maxed := _xian(ItemDB.MAX_ENHANCE)
	r = CharacterData.enhance_item(maxed)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("铸神"),
		"仙器满 +10：指向铸神", String(r.get("message", "")))
	_check(CharacterData.count_material(YUNXIAN) == 1, "满 +10 被拒时不扣髓")

	# 低境界仙器仍锁；法宝仙器仍锁
	CharacterData.current_realm = "元婴"
	var low := _xian(0)
	r = CharacterData.enhance_item(low)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("境界锁"),
		"元婴期仙器仍被境界锁挡", String(r.get("message", "")))
	CharacterData.current_realm = "化神"
	var tr := CharacterData.make_treasure_instance(ItemDB.get_treasure_template("tr_huyao_ling"))
	tr["equipment_grade"] = "仙器"
	r = CharacterData.enhance_item(tr)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("境界锁"),
		"法宝仙器不走淬炼例外", String(r.get("message", "")))
	_check(CharacterData.count_material(YUNXIAN) == 1, "两种被拒都不扣髓")

	# 凡品仍吃晶石
	var plain := _tpl(WEAPON)
	var before_c := CharacterData.count_material(CRYSTAL)
	var before_y := CharacterData.count_material(YUNXIAN)
	r = CharacterData.enhance_item(plain)
	_check(bool(r.get("ok", false)), "凡品照常强化", String(r.get("message", "")))
	_check(CharacterData.count_material(YUNXIAN) == before_y,
		"凡品不消耗蕴仙髓")
	_check(CharacterData.count_material(CRYSTAL) == before_c - 1,
		"凡品照常消耗 1 颗锻造晶石",
		"%d → %d" % [before_c, CharacterData.count_material(CRYSTAL)])

	# ===== 3. 锻造台显示 / 阻断 =====
	var panel := ForgePanel.new()
	add_child(panel)
	await _frames(4)
	var ui_xian := _xian(0)
	panel._anvil_item = ui_xian
	CharacterData.inventory.clear()
	CharacterData.grant_material(YUNXIAN, 1)
	panel.call("_refresh_content")
	await _frames(3)
	_check(String(panel.get("_plaque_cost").text).contains("蕴仙髓"),
		"铭牌消耗行显示蕴仙髓", String(panel.get("_plaque_cost").text))
	# 仙器只认顶栏「蕴仙」：常规锻造 / 自动锻造都被拒（2026-11-13 用户定）
	_check(String(panel.call("_forge_block_reason")).contains("蕴仙"),
		"常规锻造被拒：写明点上方「蕴仙」", String(panel.call("_forge_block_reason")))
	_check(String(panel.call("_forge_block_reason", true)) == "",
		"蕴仙专用通道：有髓可敲", String(panel.call("_forge_block_reason", true)))
	var auto_btn: Button = panel.get("_auto_btn")
	_check(auto_btn != null and auto_btn.disabled, "仙器：自动锻造键禁用")
	# 常规敲砧路径：拿起锤子点砧面也不该开锤
	panel._hammer_held = true
	var lv0 := int(ui_xian.get("enhancement_level", 0))
	panel.call("_try_strike", Vector2(664, 214))
	await _frames(2)
	_check(int(panel.get("_strike_state")) == 0
			and int(ui_xian.get("enhancement_level", 0)) == lv0,
		"常规敲砧：仙器不开锤", "state=%s lv=%s" % [panel.get("_strike_state"),
			ui_xian.get("enhancement_level")])
	_check(String(panel.get("_toast_label").text).contains("蕴仙"),
		"常规敲砧：回执指向「蕴仙」", String(panel.get("_toast_label").text))
	panel._hammer_held = false
	# 自动锻造路径：程序触发也不启动
	panel.call("_on_auto_pressed")
	await _frames(2)
	_check(not bool(panel.get("_auto_forge")), "自动锻造：仙器拒绝启动")
	# 顶栏「蕴仙」：点一下自动落料 + 敲一锤（2026-11-13 用户定）
	var ybtn: Button = panel.get("_yunxian_btn")
	var mat_row: HBoxContainer = panel.get("_mat_row")
	_check(ybtn != null and mat_row != null and ybtn.get_parent() == mat_row,
		"蕴仙动作并进顶栏材料行")
	_check(ybtn != null and not ybtn.disabled and String(ybtn.text) == "蕴仙 ×1",
		"仙器 + 有髓：蕴仙可用且显示数量", "%s disabled=%s" % [
			ybtn.text if ybtn != null else "null", ybtn.disabled if ybtn != null else "null"])
	var level_before := int(ui_xian.get("enhancement_level", 0))
	ybtn.pressed.emit()
	var fly: TextureRect = panel.get("_special_icon")
	_check(fly != null and fly.position.y < 92.0,
		"材料从顶栏按钮起飞", "icon y=%.0f" % (fly.position.y if fly != null else -1.0))
	await get_tree().create_timer(0.20).timeout
	_check(bool(panel.get("_special_busy")) and panel.get("_special_icon") != null,
		"点蕴仙：材料先飞向装备（演出中）")
	_check(int(ui_xian.get("enhancement_level", 0)) == level_before
			and CharacterData.count_material(YUNXIAN) == 1,
		"落锤前不结算：等级与髓都不动",
		"lv=%s 髓=%d" % [ui_xian.get("enhancement_level"), CharacterData.count_material(YUNXIAN)])
	await get_tree().create_timer(1.05).timeout
	_check(CharacterData.count_material(YUNXIAN) == 0, "蕴仙落锤：消耗蕴仙髓 ×1",
		str(CharacterData.count_material(YUNXIAN)))
	_check(not bool(panel.get("_special_busy")), "蕴仙演出结束、动作解锁")
	_check((panel.get("_last_special_flash") as Color) == Color(0.58, 0.88, 1.0, 1.0),
		"蕴仙落锤：装备亮青玉光", str(panel.get("_last_special_flash")))
	# 凡品不吃髓：蕴仙动作禁用（晶石锤照常）
	var plain_ui := _tpl(WEAPON)
	panel._anvil_item = plain_ui
	CharacterData.grant_material(YUNXIAN, 1)
	panel.call("_refresh_content")
	await _frames(3)
	_check(ybtn.disabled, "凡品：蕴仙动作禁用")
	_check(String(ybtn.text) == "蕴仙 ×1", "禁用时也显示持有数量", String(ybtn.text))
	panel._anvil_item = ui_xian
	CharacterData.inventory.clear()
	panel.call("_refresh_content")
	await _frames(3)
	_check(String(panel.call("_forge_block_reason")).contains("蕴仙"),
		"无髓：常规锻造依然被拒", String(panel.call("_forge_block_reason")))
	_check(String(panel.call("_forge_block_reason", true)).contains("蕴仙髓不足"),
		"无髓：蕴仙专用通道写明髓不足", String(panel.call("_forge_block_reason", true)))
	_check(String(panel.get("_forge_hint").text).contains("蕴仙髓不足"),
		"锻造提示也写蕴仙髓不足", String(panel.get("_forge_hint").text))
	panel.call("close")
	await _frames(2)

	# ===== 4. 主线 BOSS 首杀 +1；重复不给 =====
	CharacterData.inventory.clear()
	CharacterData.domain_progress = {"domain_01": {"unlocked": true, "cleared_bosses": []}}
	var c0 := CharacterData.count_material(YUNXIAN)
	CharacterData.mark_boss_killed("domain_01", "boss_huyao")
	_check(CharacterData.count_material(YUNXIAN) == c0 + 1,
		"主线 BOSS 首杀：蕴仙髓 +1",
		"%d → %d" % [c0, CharacterData.count_material(YUNXIAN)])
	CharacterData.mark_boss_killed("domain_01", "boss_huyao")
	_check(CharacterData.count_material(YUNXIAN) == c0 + 1,
		"重复击杀：不再给蕴仙髓")

	# ===== 5. 万界塔 5% =====
	_check(ItemDB.TOWER_YUNXIAN_DROP_CHANCE == 0.05, "塔掉落概率 5%",
		str(ItemDB.TOWER_YUNXIAN_DROP_CHANCE))
	var leaked := false
	for e in ItemDB.TOWER_FLOOR_DROPS_DEFAULT:
		if String((e as Dictionary).get("item_id", "")) == YUNXIAN:
			leaked = true
	_check(not leaked, "塔默认掉落表没有蕴仙髓（避免核心重战复用）")
	seed(20261113)
	var hits := 0
	for i in 2000:
		var d := ItemDB.roll_tower_yunxian_drop()
		if not d.is_empty():
			hits += 1
			if String((d.get("item", {}) as Dictionary).get("id", "")) != YUNXIAN:
				hits = -9999
	_check(hits >= 60 and hits <= 160, "2000 次掷骰约 5% 命中蕴仙髓", str(hits))

	# ===== 6. 九天之上祭坛：第二阶段 12 枚 =====
	CharacterData.current_realm = "化神"
	CharacterData.huashen_gate_opened = true
	CharacterData.inventory.clear()
	CharacterData.secret_world["god_altars"] = {}
	GameState.battle_context = {}
	var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await _frames(10)
	var hs: WorldResource = null
	var lq: WorldResource = null
	for raw in (w.get("_resources") as Dictionary).values():
		if raw is WorldResource and (raw as WorldResource).kind == WorldResource.KIND_GOD_ALTAR:
			if (raw as WorldResource).node_id == "hs_god_altar":
				hs = raw as WorldResource
			elif (raw as WorldResource).node_id == "lq_god_altar":
				lq = raw as WorldResource
	_check(hs != null, "九天之上祭坛已生成")
	if hs != null:
		CharacterData.set_god_altar_stage("hs_god_altar", 1)
		await _frames(2)
		_check(String(hs.prompt_text()).contains("蕴仙髓"), "化神后提示含蕴仙髓", hs.prompt_text())
		w.call("_on_god_altar", hs)
		await _frames(2)
		_check(CharacterData.count_material(YUNXIAN) == 12,
			"九天之上祭坛第二阶段：蕴仙髓 ×12", str(CharacterData.count_material(YUNXIAN)))
		_check(CharacterData.count_material(STONE) == 7
				and CharacterData.god_altar_stage("hs_god_altar") == 2,
			"原奖励（补天石 ×7）与阶段推进不变",
			"石 %d 阶段 %d" % [CharacterData.count_material(STONE),
				CharacterData.god_altar_stage("hs_god_altar")])
	if lq != null:
		CharacterData.inventory.clear()
		CharacterData.set_god_altar_stage("lq_god_altar", 1)
		w.call("_on_god_altar", lq)
		await _frames(2)
		_check(CharacterData.count_material(YUNXIAN) == 0,
			"其它区的祭坛不给蕴仙髓（只有九天之上）",
			str(CharacterData.count_material(YUNXIAN)))

	w.queue_free()
	await _frames(3)
	CharacterData.inventory.clear()
	CharacterData.inventory.append_array(saved_inv)
	CharacterData.current_realm = saved_realm
	CharacterData.domain_progress = saved_domain
	CharacterData.boss_progress = saved_boss
	CharacterData.origin_energy = saved_energy
	CharacterData.story_progress = saved_story
	CharacterData.huashen_gate_opened = saved_gate
	CharacterData.secret_world["god_altars"] = saved_altars
	GameState.battle_context = saved_battle
	print("")
