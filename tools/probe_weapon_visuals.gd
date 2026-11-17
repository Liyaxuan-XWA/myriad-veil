extends Node
## 武器局内贴图自检：每把武器都要落到一个存在的 ArtDB weapon_* 条目与贴图。

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 武器局内贴图探针 ##########")
	var checked := 0
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		var tpl: Dictionary = raw
		if String(tpl.get("equipment_type", "")) != "weapon":
			continue
		checked += 1
		var name := String(tpl.get("equipment_name", tpl.get("equipment_id", "")))
		var vid := String(tpl.get("weapon_visual", ""))
		if vid == "":
			vid = "player_weapon"
		var vis := ArtDB.get_visual(vid)
		var tex_path := String(vis.get("texture", ""))
		_check(vid != "" and tex_path != "", "%s 有局内武器条目" % name,
			"%s → %s" % [String(tpl.get("equipment_id", "")), vid])
		_check(ResourceLoader.exists(tex_path), "%s 贴图存在" % name, tex_path)
		if ResourceLoader.exists(tex_path):
			var tex := load(tex_path) as Texture2D
			_check(tex != null and tex.get_width() > 0 and tex.get_height() > 0,
				"%s 贴图可加载" % name,
				"%dx%d" % [tex.get_width(), tex.get_height()] if tex != null else "null")
			if tex != null:
				var img := tex.get_image()
				if img != null and img.detect_alpha() != Image.ALPHA_NONE:
					_check(img.get_used_rect().has_area(),
						"%s 贴图有非透明主体" % name, str(img.get_used_rect()))
	_check(checked == 10, "十把武器全部盘点（含长夜刃 / 纸错剑 / 问天剑）", "count=%d" % checked)
	_check(ArtDB.has_texture("weapon_zhuxian_chizhang"), "朱弦阵尺已接局内图")
	_check(ArtDB.has_texture("weapon_panguan_tiebi"), "判官铁笔已接局内图")
	_check(ArtDB.has_texture("weapon_jiefeng"), "劫锋已接局内图")
	_check(ArtDB.has_texture("weapon_jingtan_chi"), "镜潭尺已接局内图")
	# 旧存档装备实例没有 weapon_visual 字段时，必须按模板回查
	for item_id in ["eq_zhuxian_chizhang", "eq_panguan_tiebi", "eq_jiefeng"]:
		var old_item := {"id": item_id}
		_check(ItemDB.weapon_visual_for(old_item) != "",
			"旧装备实例可回查武器外观", "%s → %s" % [item_id,
				ItemDB.weapon_visual_for(old_item)])

	# 真实玩家同步：旧存档只存 id，也要切到对应武器外观
	var player: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await get_tree().process_frame
	CharacterData.equipment_slots["weapon"] = {"id": "eq_jiefeng"}
	player.call("refresh_training_loadout")
	await get_tree().process_frame
	_check(player.get("weapon") != null
		and String(player.get("weapon").get("weapon_id")) == "weapon_jiefeng",
		"旧存档装备实例同步到武器外观",
		"weapon_id=%s" % String(player.get("weapon").get("weapon_id")))

	# ===== 问天剑（2026-11-12 彩蛋武器）+ 「换装备就换手里那把」的自动切换 =====
	# ⚠ 必须**连着换两次**：只验一把武器能显示，抓不到「装备变化后没重算」这一类 bug
	#   （_sync_weapon_visual 靠 weapon_id 比对，漏掉一次调用就会一直挂着旧武器）。
	var wentian := ItemDB.get_equipment_template("eq_wentian_jian")
	_check(not wentian.is_empty()
			and String(wentian.get("weapon_visual", "")) == "weapon_wentian_jian",
		"问天剑登记了局内武器条目", String(wentian.get("weapon_visual", "")))
	_check(ArtDB.has_texture("weapon_wentian_jian"), "问天剑局内贴图已接入")

	CharacterData.equipment_slots["weapon"] = {"id": "eq_qingfengjian"}
	player.call("refresh_training_loadout")
	await get_tree().process_frame
	var first_id := String(player.get("weapon").get("weapon_id"))
	CharacterData.equipment_slots["weapon"] = {"id": "eq_wentian_jian"}
	player.call("refresh_training_loadout")
	await get_tree().process_frame
	var second_id := String(player.get("weapon").get("weapon_id"))
	_check(first_id == "weapon_qingfeng_jian", "先装清风剑 → 局内是清风剑", first_id)
	_check(second_id == "weapon_wentian_jian",
		"换装问天剑 → 局内武器样式自动跟着换（不用重开场景）",
		"%s → %s" % [first_id, second_id])
	CharacterData.equipment_slots["weapon"] = {}
	player.call("refresh_training_loadout")
	await get_tree().process_frame
	_check(String(player.get("weapon").get("weapon_id")) == "player_weapon",
		"卸下武器 → 回退默认御剑", String(player.get("weapon").get("weapon_id")))

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
