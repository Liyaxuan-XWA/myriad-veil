extends Node
## 铸神祭坛：每区一座 + 两阶段奖励（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_god_altar.tscn -- --no-save
##
## 判据：
##   · 五个区域的内容表各有一座祭坛，落点在本区可行走范围内、离其它内容 ≥250；
##   · 祭坛美术（world_god_altar + PNG）与两枚材料图标都存在；
##   · 首次交互：铸神晶 ×1 直接进主背包（不进局内背包），阶段 1；
##   · 未化神时再交互：什么都不给；化神后再交互：铸神晶 ×1 + 补天石 ×7，阶段 2；
##   · 阶段 2 之后不再给；背包满时整份不领、阶段不推进；
##   · 阶段写进存档快照（secret_world.god_altars）。

const WORLD_SCENE := "res://scenes/world/secret_world.tscn"
const CRYSTAL := "mat_zhushenjing"
const STONE := "mat_butianshi"
const ALTAR_ID := "lq_god_altar"

var _passes := 0
var _fails: Array = []
var _saved_inv: Array = []
var _saved_realm := ""
var _saved_altars := {}


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
	print("\n########## 铸神祭坛 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved_inv = CharacterData.inventory.duplicate(true)
	_saved_realm = CharacterData.current_realm
	_saved_altars = (CharacterData.secret_world.get("god_altars", {}) as Dictionary).duplicate(true)
	CharacterData.secret_world["god_altars"] = {}

	# ===== 1. 内容表：每区一座，落点安全 =====
	var regions := [
		SecretWorldDB.REGION_LIANQI, SecretWorldDB.REGION_ZHUJI,
		SecretWorldDB.REGION_JIEDAN, SecretWorldDB.REGION_YUANYING,
		SecretWorldDB.REGION_HUASHEN,
	]
	for rid in regions:
		var c := SecretWorldDB.get_region_content(String(rid))
		var arr = c.get("god_altars", [])
		_check(arr is Array and (arr as Array).size() == 1,
			"区域 %s 有一座祭坛" % rid, str((arr as Array).size() if arr is Array else -1))
	# 练气区：离传送门 / 灵田 / 石台 / 其它内容都 ≥250
	var lq := SecretWorldDB.get_region_content(SecretWorldDB.REGION_LIANQI)
	var altar_pos := Vector2(((lq.get("god_altars", []) as Array)[0] as Dictionary).get("pos", Vector2.ZERO))
	var min_d := 99999.0
	for key in ["herbs", "qi_orbs", "beasts", "reliquaries"]:
		for raw in (lq.get(key, []) as Array):
			var p := Vector2(((raw as Dictionary).get("pos", Vector2.ZERO)))
			min_d = minf(min_d, altar_pos.distance_to(p))
	for key in ["portal", "core_boss", "farm"]:
		var e = lq.get(key, null)
		if e is Dictionary:
			min_d = minf(min_d, altar_pos.distance_to(Vector2((e as Dictionary).get("pos", Vector2.ZERO))))
	_check(min_d >= 250.0, "练气祭坛离其它内容 ≥250", "%.0f" % min_d)
	_check(Rect2(-3000.0, -2000.0, 6000.0, 4000.0).has_point(altar_pos),
		"练气祭坛落在区域坐标内", str(altar_pos))

	# ===== 2. 美术与材料 =====
	var vis: Dictionary = ArtDB.VISUALS.get("world_god_altar", {})
	_check(not vis.is_empty(), "ArtDB 有 world_god_altar")
	_check(ResourceLoader.exists(String(vis.get("texture", ""))), "祭坛贴图存在",
		String(vis.get("texture", "")))
	for mid in [CRYSTAL, STONE]:
		var mat := ItemDB.get_material(String(mid))
		_check(not mat.is_empty(), "材料 %s 已登记" % mid)
		_check(ResourceLoader.exists(String(mat.get("icon", ""))), "%s 图标存在" % mid,
			String(mat.get("icon", "")))
		var tex := load(String(mat.get("icon", ""))) as Texture2D
		_check(tex != null and tex.get_width() == 256 and tex.get_height() == 256,
			"%s 图标 256×256" % mid, str(tex.get_size()) if tex != null else "null")

	# ===== 3. 真实大世界：祭坛被生成 =====
	GameState.battle_context = {}
	var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await _frames(10)
	var altars: Array = []
	for raw in (w.get("_resources") as Dictionary).keys():
		var n = (w.get("_resources") as Dictionary)[raw]
		if n is WorldResource and (n as WorldResource).kind == WorldResource.KIND_GOD_ALTAR:
			altars.append(n)
	var expect := 4
	if SecretWorldDB.is_region_open(SecretWorldDB.get_region(SecretWorldDB.REGION_HUASHEN)):
		expect += 1
	_check(altars.size() == expect, "已开放区域各生成一座祭坛", "%d / 期望 %d" % [altars.size(), expect])
	var altar: WorldResource = null
	for a in altars:
		if (a as WorldResource).node_id == ALTAR_ID:
			altar = a as WorldResource
	_check(altar != null, "找到练气祭坛")
	if altar == null:
		w.queue_free()
		return
	_check(altar.get_meta("visual_id", "") == "world_god_altar",
		"祭坛视觉 id 正确", str(altar.get_meta("visual_id", "")))

	# ===== 4. 交互两阶段 =====
	var wp: Node2D = w.get("player")
	wp.set_physics_process(false)
	wp.global_position = altar.global_position
	await _frames(4)
	_check(w.get("_nearest") == altar, "站到祭坛旁：交互指针指向祭坛")
	_check(String(altar.prompt_text()).contains("取走铸神晶"), "阶段 0 提示取铸神晶", altar.prompt_text())
	var c0 := CharacterData.count_material(CRYSTAL)
	w.call("_on_interact")
	await _frames(2)
	_check(CharacterData.count_material(CRYSTAL) == c0 + 1, "首次交互：主背包 +1 铸神晶",
		"%d → %d" % [c0, CharacterData.count_material(CRYSTAL)])
	_check(CharacterData.god_altar_stage(ALTAR_ID) == 1, "阶段 → 1")
	var altar_vis: CanvasItem = altar.get("_visual") as CanvasItem
	_check(altar_vis != null, "祭坛有视觉节点")
	if altar_vis != null:
		_check(altar_vis.modulate.r < 0.95, "取走第一份后祭坛压暗", str(altar_vis.modulate))
	var in_run_bag := false
	for raw in (w.get("_run_items") as Array):
		if String((raw as Dictionary).get("id", "")) == CRYSTAL:
			in_run_bag = true
	_check(not in_run_bag, "铸神晶没有进局内背包")

	# 未化神再交互：什么都不给
	var c1 := CharacterData.count_material(CRYSTAL)
	_check(String(altar.prompt_text()).contains("化神"), "未化神：提示化神后再来", altar.prompt_text())
	w.call("_on_interact")
	await _frames(2)
	_check(CharacterData.count_material(CRYSTAL) == c1
			and CharacterData.god_altar_stage(ALTAR_ID) == 1,
		"未化神：再交互不给东西、阶段不动")

	# 化神后再交互：+1 晶 +7 石
	CharacterData.current_realm = "化神"
	await _frames(2)
	_check(String(altar.prompt_text()).contains("补天石"), "化神后：提示可再取补天石", altar.prompt_text())
	var s0 := CharacterData.count_material(STONE)
	w.call("_on_interact")
	await _frames(2)
	_check(CharacterData.count_material(CRYSTAL) == c1 + 1
			and CharacterData.count_material(STONE) == s0 + 7,
		"化神后再取：铸神晶 +1、补天石 +7",
		"晶 %d / 石 %d" % [CharacterData.count_material(CRYSTAL), CharacterData.count_material(STONE)])
	_check(CharacterData.god_altar_stage(ALTAR_ID) == 2, "阶段 → 2")
	if altar_vis != null:
		_check(altar_vis.modulate.r < 0.65, "取空后祭坛再暗一档", str(altar_vis.modulate))
	var c2 := CharacterData.count_material(CRYSTAL)
	w.call("_on_interact")
	await _frames(2)
	_check(CharacterData.count_material(CRYSTAL) == c2
			and CharacterData.god_altar_stage(ALTAR_ID) == 2, "阶段 2：不再给东西")
	_check(String(altar.prompt_text()).contains("已空"), "阶段 2 提示祭坛已空", altar.prompt_text())

	# ===== 5. 背包满：整份不领、阶段不推进 =====
	CharacterData.set_god_altar_stage(ALTAR_ID, 1)
	CharacterData.inventory.clear()
	var filler := 1
	while CharacterData.bag_count_for(CharacterData.ITEM_MATERIAL) < CharacterData.BAG_CAP_MATERIAL:
		CharacterData.inventory.append({"id": "fill_%d" % filler, "name": "占位",
			"type": "material", "count": 1, "icon": "", "desc": ""})
		filler += 1
	var before_stage := CharacterData.god_altar_stage(ALTAR_ID)
	w.call("_on_interact")
	await _frames(2)
	_check(CharacterData.god_altar_stage(ALTAR_ID) == before_stage
			and CharacterData.count_material(STONE) == 0,
		"背包满：奖励留在祭坛上、阶段不推进")

	# ===== 6. 存档快照包含祭坛阶段 =====
	CharacterData.set_god_altar_stage(ALTAR_ID, 2)
	var snap := SaveManager.capture()
	var sw = (snap.get("secret_world", {}) as Dictionary)
	var stages = sw.get("god_altars", {})
	_check(stages is Dictionary and int((stages as Dictionary).get(ALTAR_ID, -1)) == 2,
		"存档快照里带 god_altars 阶段", str(stages))
	# 读档白名单也要真的把阶段还原回来
	CharacterData.set_god_altar_stage(ALTAR_ID, 0)
	SaveManager.apply(snap)
	_check(CharacterData.god_altar_stage(ALTAR_ID) == 2,
		"读档后祭坛阶段还原", str(CharacterData.god_altar_stage(ALTAR_ID)))

	w.queue_free()
	await _frames(3)
	CharacterData.inventory.clear()
	CharacterData.inventory.append_array(_saved_inv)
	CharacterData.current_realm = _saved_realm
	CharacterData.secret_world["god_altars"] = _saved_altars
	print("")
