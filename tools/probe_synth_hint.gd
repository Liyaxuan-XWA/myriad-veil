extends Node
## 法宝合成材料「去哪合成」指引探针（2026-11-09 用户要求）
##
## 用户原话：「给每个法宝合成材料介绍里添加，去哪合成的文字说明，给玩家指引」。
## ⚠ 断言口径必须是「配方表**全量**覆盖」，不能抽查几件 —— 漏掉一件，玩家就会拿着
##   那件材料在背包里翻不出任何去处（这正好是最需要指引的时候）。

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 所有参与熔铸的材料：位面三件 / 元魂 / 破境残晶，按配方表现取并去重
func _all_synth_materials() -> Array:
	var out: Array = []
	for raw in ItemDB.PLANE_TREASURE_RECIPES:
		for mid in ((raw as Dictionary).get("material_ids", []) as Array):
			if not out.has(String(mid)):
				out.append(String(mid))
	for raw in ItemDB.SYNTH_RECIPES:
		var sid := String((raw as Dictionary).get("soul_id", ""))
		if sid != "" and not out.has(sid):
			out.append(sid)
	for realm in ItemDB.POJING_SYNTH_RECIPES.keys():
		var pj: Dictionary = ItemDB.POJING_SYNTH_RECIPES[realm]
		for key in ["di", "tian"]:
			var fid := String(pj.get(key, ""))
			if fid != "" and not out.has(fid):
				out.append(fid)
	return out


func _ready() -> void:
	print("\n########## 法宝合成指引探针 ##########")
	var mats := _all_synth_materials()
	# 期望数同样从三张配方表现算，不写死 32 —— 以后加位面/加档不用回来改探针
	var expect := 0
	for raw in ItemDB.PLANE_TREASURE_RECIPES:
		expect += ((raw as Dictionary).get("material_ids", []) as Array).size()
	expect += ItemDB.SYNTH_RECIPES.size()
	expect += ItemDB.POJING_SYNTH_RECIPES.size() * 2
	_check(mats.size() == expect, "熔铸材料去重后与配方表数量一致",
		"%d / 期望 %d" % [mats.size(), expect])

	# ===== 一、全量覆盖：一件都不能漏 =====
	var missing: Array = []
	for mid in mats:
		if ItemDB.synth_hint_lines(String(mid)).is_empty():
			missing.append(String(mid))
	_check(missing.is_empty(), "每件熔铸材料都有合成指引", "缺 %d 件 %s" % [missing.size(), str(missing)])

	# ===== 二、每条指引都要指到具体地方（设施名 + 页签）=====
	var bad_loc: Array = []
	var bad_prefix: Array = []
	var dupes: Array = []
	for mid in mats:
		var lines := ItemDB.synth_hint_lines(String(mid))
		if lines.size() != 1:
			dupes.append("%s×%d" % [String(mid), lines.size()])
		for line in lines:
			var s := String(line)
			if not (s.contains("装备锻造台") and s.contains("熔铸")):
				bad_loc.append(String(mid))
			if not s.begins_with("合成指引："):
				bad_prefix.append(String(mid))
	_check(bad_loc.is_empty(), "每条指引都写明「装备锻造台」与「熔铸」页", str(bad_loc))
	_check(bad_prefix.is_empty(), "每条指引都以「合成指引：」开头", str(bad_prefix))
	# 一件材料一行：既不能被两张表重复命中，也不能一个字都没写
	_check(dupes.is_empty(), "每件材料恰好一行指引", str(dupes))

	# ===== 三、位面材料：要写出「同界三件」与产物 =====
	# ⚠ 这里只断言「同界三件」而不是逐个列名字：详情框固定 146px，一行约 40 字，
	#   两个材料名带引号会把产物名挤到滚动区外。另两件的名字由熔铸页候选列表提供。
	for raw in ItemDB.PLANE_TREASURE_RECIPES:
		var rec := raw as Dictionary
		var ids: Array = rec.get("material_ids", [])
		var tpl := ItemDB.get_treasure_template(String(rec.get("result_id", "")))
		var tname := String(tpl.get("treasure_name", ""))
		for mid in ids:
			var text := "\n".join(ItemDB.synth_hint_lines(String(mid)))
			var ok := tname != "" and text.contains(tname) and text.contains("同界三件")
			_check(ok, "位面材料 %s 写明同界三件与产物" % String(mid), "产物「%s」" % tname)

	# ===== 四、元魂：写清「与同源破损装备」和召唤出的法宝 =====
	for raw in ItemDB.SYNTH_RECIPES:
		var rec2 := raw as Dictionary
		var sid := String(rec2.get("soul_id", ""))
		var tpl2 := ItemDB.get_treasure_template(String(rec2.get("result_id", "")))
		var tname2 := String(tpl2.get("treasure_name", ""))
		var t := "\n".join(ItemDB.synth_hint_lines(sid))
		_check(t.contains("破损装备") and tname2 != "" and t.contains(tname2),
			"元魂 %s 写明破损装备与产物" % sid, "产物「%s」" % tname2)

	# ===== 五、破境残晶：写清对侧那枚与境界 =====
	for realm in ItemDB.POJING_SYNTH_RECIPES.keys():
		var pj: Dictionary = ItemDB.POJING_SYNTH_RECIPES[realm]
		var di := String(pj.get("di", ""))
		var tian := String(pj.get("tian", ""))
		var t_di := "\n".join(ItemDB.synth_hint_lines(di))
		var t_tian := "\n".join(ItemDB.synth_hint_lines(tian))
		_check(t_di.contains("天髓") and t_di.contains(String(realm)),
			"地髓 %s 写明与天髓熔成%s破境晶" % [di, String(realm)], t_di)
		_check(t_tian.contains("地髓") and t_tian.contains(String(realm)),
			"天髓 %s 写明与地髓熔成%s破境晶" % [tian, String(realm)], t_tian)

	# ===== 六、反向锁：不该出现的地方一个字都不能多 =====
	# 不加反向锁的话，「给所有材料都挂一句」这种偷懒实现也能让上面全绿
	var plain := ["mat_xuecao", "mat_duanzaojingshi", "mat_ruishoupi", "mat_lanyingcao"]
	var leaked: Array = []
	for mid in plain:
		if not ItemDB.synth_hint_lines(String(mid)).is_empty():
			leaked.append(mid)
	_check(leaked.is_empty(), "普通药材 / 强化晶石不挂合成指引", str(leaked))
	# 产物不是材料：完整破境晶、法宝模板都不该出现「去合成」的指引
	_check(ItemDB.synth_hint_lines("mat_pojing_zhuji").is_empty(),
		"完整破境晶（产物）不再挂合成指引", "")
	_check(ItemDB.synth_hint_lines("tr_huyao_ling").is_empty(),
		"法宝本体不挂材料指引", "")
	_check(ItemDB.synth_hint_lines("").is_empty(), "空 id 返回空数组", "")

	# ===== 七、走真实入口：角色面板详情里真的能看到 =====
	# ⚠ 只断言数据层返回什么是不够的 —— 玩家看的是面板。这里按 UI 点击的回调
	#   _on_item_selected() 走一遍，读回 _detail 的实际文本。
	var backup: Array = CharacterData.inventory.duplicate(true)
	var mat := {
		"id": "mat_fanjie_duanren", "name": "凡铁断刃", "type": "material",
		"realm": "练气", "count": 1,
		"desc": "刀客那柄凡品弯刀崩下的断刃，铁色发灰，刃口却仍亮。凡界专属材料之一。",
	}
	CharacterData.inventory = [mat]
	CharacterPanel._refresh_bag()
	CharacterPanel._on_item_selected(mat, 0)
	var detail := String(CharacterPanel._detail.text)
	_check(detail.contains("合成指引："), "角色面板详情里出现指引行",
		detail.replace("\n", " ｜ "))
	# ⚠ 指引必须排在描述**之前**：详情框固定 146px，描述长短不一（地髓那条占两行），
	#   排后面时指引会被挤出可见区 —— 而那正是玩家最需要看到的一行。
	var desc_at := detail.find("描述：")
	var hint_at := detail.find("合成指引：")
	_check(desc_at >= 0 and hint_at >= 0 and hint_at < desc_at, "指引排在描述之前（固定高度下才一定可见）",
		"指引@%d 描述@%d" % [hint_at, desc_at])
	_check(detail.contains("凡界·换锋符"), "详情里写出产物名「凡界·换锋符」", "")
	_check(detail.contains("同界三件"), "详情里写明同界三件材料", "")
	# 反向锁（UI 层）：普通药材在同一个面板里**不能**冒出指引行
	var herb := {"id": "mat_xuecao", "name": "青岚血参", "type": "material",
		"realm": "练气", "count": 1,
		"desc": "青岚野常见的赤色灵参，药性偏温，是炼制回气血丹药的主材。"}
	CharacterData.inventory = [herb]
	CharacterPanel._refresh_bag()
	CharacterPanel._on_item_selected(herb, 0)
	var herb_detail := String(CharacterPanel._detail.text)
	_check(not herb_detail.contains("合成指引"), "普通药材详情里没有指引行",
		herb_detail.replace("\n", " ｜ "))

	# 还原：探针不能给玩家的背包留下东西
	CharacterData.inventory = backup
	CharacterPanel._refresh_bag()

	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())
