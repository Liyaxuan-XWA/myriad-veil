extends Node
## 元婴期丹药 / 符箓探针（2026-11-01）：
## 5 张元婴丹方 + 5 个 buff / 7 张元婴符 + 材料映射 / 制作入符匣。

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
	print("\n########## 元婴丹药 / 符箓探针 ##########")
	_check(ItemDB.PILL_RECIPES.size() == 20, "五境共 20 张丹方",
		str(ItemDB.PILL_RECIPES.size()))
	_check(ItemDB.ELEMENT_TALISMAN_QUALITIES.size() == 4, "四品阶符箓")
	_check(ItemDB.all_talisman_recipes().size() == 28, "七系 × 四品阶 = 28 张符方",
		str(ItemDB.all_talisman_recipes().size()))

	var pill_expect := {
		"pill_yy_huichundan": ["元婴回春丹", "mat_yy_xuecao"],
		"pill_yy_julingdan": ["元婴聚灵丹", "mat_yy_lanyingcao"],
		"pill_yy_julidan": ["元婴巨力丹", "mat_yy_liyuanguo"],
		"pill_yy_lingfadan": ["元婴灵法丹", "mat_yy_falinghua"],
		"pill_yy_jingangdan": ["元婴金刚丹", "mat_yy_huguteng"],
	}
	for pid in pill_expect.keys():
		var def := ItemDB.get_consumable(String(pid))
		_check(not def.is_empty(), "丹方存在 " + String(pid))
		if def.is_empty():
			continue
		_check(String(def.get("pill_name", "")) == String(pill_expect[pid][0]),
			"丹名 " + String(pid), String(def.get("pill_name", "")))
		_check(String(def.get("realm", "")) == "元婴", "元婴境界 " + String(pid))
		_check((def.get("materials", {}) as Dictionary).has(String(pill_expect[pid][1])),
			"药材落点 " + String(pid), str(def.get("materials", {})))
		_check(ResourceLoader.exists(String(def.get("icon", ""))), "丹药图标存在 " + String(pid))
	var heal := ItemDB.get_consumable("pill_yy_huichundan")
	_check(is_equal_approx(float(heal.get("battle_effect", {}).get("ratio", 0.0)), 0.25),
		"元婴回春 25%")
	var buff := ItemDB.get_consumable("pill_yy_julidan")
	var buff_id := String(buff.get("battle_effect", {}).get("buff_id", ""))
	_check(buff_id == "pill_juli_yy" and not BuffDB.get_buff(buff_id).is_empty(),
		"元婴巨力 buff 已登记", buff_id)
	_check(BuffDB.display_text("pill_juli_yy").contains("22%"), "元婴巨力说明 22%")
	var spell_pill := ItemDB.get_consumable("pill_yy_lingfadan")
	_check(float(((spell_pill.get("battle_effect", {}) as Dictionary).get("mods", {}) \
		as Dictionary).get("spell_power", {}).get("base_pct", 0.0)) == 22.0,
		"元婴灵法 +22% 本体法强")
	var resist_pill := ItemDB.get_consumable("pill_yy_jingangdan")
	var rmods: Dictionary = (resist_pill.get("battle_effect", {}) as Dictionary).get("mods", {})
	_check(float((rmods.get("physical_resist", {}) as Dictionary).get("flat", 0.0)) == 28.0
		and float((rmods.get("magic_resist", {}) as Dictionary).get("flat", 0.0)) == 28.0,
		"元婴金刚双抗 +28")
	_check(is_equal_approx(float(heal.get("battle_cooldown", 0.0)), 30.0)
		and is_equal_approx(float(heal.get("success_rate", 0.0)), 0.68),
		"元婴回春 CD 30 / 成功率 68%")

	for mid in ["mat_yy_xuecao", "mat_yy_lanyingcao", "mat_yy_liyuanguo",
			"mat_yy_falinghua", "mat_yy_huguteng"]:
		_check(not ItemDB.recipe_for_material("pill", String(mid)).is_empty(),
			"元婴药材可炼丹 " + String(mid))
		_check(ItemDB.product_name_for_material("pill", String(mid)).begins_with("元婴"),
			"药谱可显示元婴丹 " + String(mid))
	for skin in ["mat_yy_ruishoupi", "mat_yy_jianshoupi"]:
		_check(ItemDB.usable_material_ids("talisman").has(skin), "符谱收录元婴兽皮 " + skin)
		_check(ItemDB.product_name_for_material("talisman", String(skin)).contains("元婴"),
			"符谱可显示元婴符 " + skin)

	var tal_ids := ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling",
		"tal_shuihui", "tal_fengji", "tal_tushi"]
	for base_id in tal_ids:
		var item_id := String(base_id) + "_yuanying"
		var def := ItemDB.get_consumable(item_id)
		_check(not def.is_empty(), "元婴符存在 " + item_id)
		if def.is_empty():
			continue
		_check(String(def.get("realm", "")) == "元婴", "元婴符境界 " + item_id)
		_check(ResourceLoader.exists(String(def.get("icon", ""))), "符图标存在 " + item_id)
		_check(ResourceLoader.exists(String(def.get("card", ""))), "符卡面存在 " + item_id)
		var mats: Dictionary = def.get("materials", {})
		var expected_mat := "mat_yy_ruishoupi" \
			if String(def.get("talisman_type", "")) == "攻击" else "mat_yy_jianshoupi"
		_check(mats.has(expected_mat), "元婴符材料 " + item_id, str(mats))
		_check(TalismanPatterns.for_item(item_id).size() > 0, "元婴符符路 " + item_id)
		_check(not ItemDB.recipe_for_material("talisman", expected_mat).is_empty(),
			"元婴兽皮可制符 " + expected_mat)
	_check(is_equal_approx(ItemDB.talisman_cultivation_cost(
		ItemDB.get_consumable("tal_jinfeng_yuanying")), 200.0), "元婴符修为 200")

	# 制作元婴符：同级必成，进符匣，不占背包
	var saved_inv: Array = CharacterData.inventory.duplicate(true)
	var saved_stock: Dictionary = CharacterData.talisman_stock.duplicate(true)
	var saved_realm := CharacterData.current_realm
	var saved_stage := CharacterData.realm_stage
	var saved_exp := CharacterData.realm_exp
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 0
	CharacterData.realm_exp = 1000
	CharacterData.inventory = [{"id": "mat_yy_jianshoupi", "type": "material", "count": 1}]
	CharacterData.talisman_stock = {}
	var recipe := ItemDB.get_talisman_recipe("recipe_tal_tushi_yuanying")
	var res := CharacterData.craft_talisman(recipe, 1)
	_check(bool(res.get("success", false)) and CharacterData.talisman_count("tal_tushi_yuanying") == 1,
		"元婴制符同级必成并入符匣", String(res.get("message", "")))
	_check(CharacterData.inventory.size() == 0, "制符不占背包格")
	CharacterData.inventory = saved_inv
	CharacterData.talisman_stock = saved_stock
	CharacterData.current_realm = saved_realm
	CharacterData.realm_stage = saved_stage
	CharacterData.realm_exp = saved_exp

	# ===== 四区材料品质档（2026-11-02 用户定）=====
	# 规则：一个区的材料与该区的丹药 / 符箓同档。应有档直接取符箓品阶表，不在探针里再抄一份常量。
	var expect := {}
	for q in ItemDB.ELEMENT_TALISMAN_QUALITIES:
		expect[String((q as Dictionary).get("realm", ""))] = String((q as Dictionary).get("rarity", ""))
	_check(expect.get("练气") == "common" and expect.get("筑基") == "rare"
		and expect.get("结丹") == "epic" and expect.get("元婴") == "legendary",
		"符箓品阶表提供四区应有档", str(expect))
	var region_mats: Array = []
	for rid in [SecretWorldDB.REGION_LIANQI, SecretWorldDB.REGION_ZHUJI,
			SecretWorldDB.REGION_JIEDAN, SecretWorldDB.REGION_YUANYING]:
		region_mats.append_array(SecretWorldDB.get_herb_ids(rid))
	region_mats.append_array(ItemDB.TALISMAN_ATTACK_MATERIALS)
	region_mats.append_array(ItemDB.TALISMAN_FUNC_MATERIALS)
	var wrong := ""
	for mid in ItemDB.MATERIALS:
		var id := String((mid as Dictionary).get("id", ""))
		if id.begins_with("mat_pojing_"):
			# 破境材料（底髓 / 天髓 / 完整晶）也按 realm 同档，2026-11-02 用户定
			region_mats.append(id)
	for mid in region_mats:
		var realm := String(ItemDB.get_material_realm(String(mid)))
		var want := String(expect.get(realm, ""))
		if want == "":
			wrong += "%s(境界对不上) " % mid
		elif String(ItemDB.get_material(String(mid)).get("rarity", "")) != want:
			wrong += "%s(%s≠%s) " % [mid, ItemDB.material_rarity(String(mid)), want]
	_check(region_mats.size() == 40 and wrong == "",
		"四区草药 + 八张兽皮 + 十二件破境材料共 40 件全部与本境同档", wrong)

	# 用户点名的几件：颜色确实换了
	var orange := ItemDB.rarity_color("legendary")
	_check(ItemDB.material_border_color("mat_yy_xuecao") == orange
		and ItemDB.material_border_color("mat_yy_lanyingcao") == orange
		and ItemDB.material_border_color("mat_yy_ruishoupi") == orange,
		"幽冥血参 / 蓝萤草 / 锐兽皮描边为橙（原紫）")
	_check(ItemDB.material_border_color("mat_yy_xuecao")
		== ItemDB.rarity_color(String(ItemDB.get_consumable("pill_yy_julidan").get("rarity", ""))),
		"材料颜色与元婴丹药同档")
	_check(ItemDB.material_border_color("mat_zj_xuecao") == ItemDB.rarity_color("rare")
		and ItemDB.material_border_color("mat_zj_lanyingcao") == ItemDB.rarity_color("rare"),
		"云隐血参 / 蓝萤草抬到蓝（原绿）")
	_check(ItemDB.material_border_color("mat_jd_xuecao") == ItemDB.rarity_color("epic")
		and ItemDB.material_border_color("mat_jd_lanyingcao") == ItemDB.rarity_color("epic"),
		"赤金血参 / 蓝萤草抬到紫（原蓝）")
	# 破境链：一条链同色，练气链白 → 筑基链蓝 → 结丹链紫 → 元婴链橙
	_check(ItemDB.material_border_color("mat_pojing_zhuji") == ItemDB.rarity_color("common")
		and ItemDB.material_border_color("mat_pojing_di_zhuji") == ItemDB.rarity_color("common"),
		"筑基链三件同白（完整晶随链回到练气档）")
	_check(ItemDB.material_border_color("mat_pojing_jiedan") == ItemDB.rarity_color("rare")
		and ItemDB.material_border_color("mat_pojing_yuanying") == ItemDB.rarity_color("epic")
		and ItemDB.material_border_color("mat_pojing_huashen") == ItemDB.rarity_color("legendary"),
		"结丹 / 元婴 / 化神三档完整晶分别蓝 / 紫 / 橙")

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
