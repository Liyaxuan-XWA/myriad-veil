extends Node
## 铸神 / 补天 / 神器规则（2026-11-13 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_divine_mend.tscn -- --no-save
##
## 判据：
##   · 神器（最高品阶）没有强化等级：enhance_item 一律拒绝；旧痕保留并显示；
##   · 仙器满 +10 普通敲击不再进阶，只能铸神；铸神 = 仙器+10 + 铸神晶×1 → 神器；
##   · 补天石只清普通失败磨损，进阶失败的磨损保留；补完可继续强化；神器旧痕不可补；
##   · 锻造台按钮：条件/持有数/点击链路/神器铭牌状态（磨损刻度与数量）。

const WEAPON := "eq_qingfengjian"
const CRYSTAL := "mat_zhushenjing"
const STONE := "mat_butianshi"

var _passes := 0
var _fails: Array = []
var _saved_inv: Array = []


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


## 真实鼠标路径（验证顶栏材料钮能被点到，而不只是 pressed.emit）
## ⚠ headless 视口有 0.05 的 final transform，必须按 local 坐标投递
func _click(center: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = center
	m.global_position = center
	get_viewport().push_input(m, true)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = center
	d.global_position = center
	get_viewport().push_input(d, true)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = center
	u.global_position = center
	get_viewport().push_input(u, true)


func _tpl(eid: String) -> Dictionary:
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		if String((raw as Dictionary).get("equipment_id", "")) == eid:
			return CharacterData.make_equipment_instance(raw as Dictionary)
	return {}


func _xian_item(level: int = ItemDB.MAX_ENHANCE) -> Dictionary:
	var it := _tpl(WEAPON)
	it["equipment_grade"] = "仙器"
	it["enhancement_level"] = level
	return it


func _ready() -> void:
	print("\n########## 铸神 / 补天 / 神器规则 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().paused = false
	get_tree().quit(_fails.size())


func _run() -> void:
	_saved_inv = CharacterData.inventory.duplicate(true)
	CharacterData.inventory.clear()

	# ===== 1. 仙器满 +10：普通敲击被引向铸神 =====
	var it := _xian_item()
	CharacterData.grant_material(CharacterData.ENHANCE_MATERIAL, 200)
	var r := CharacterData.enhance_item(it)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("铸神"),
		"仙器满 +10：普通敲击提示去铸神", String(r.get("message", "")))

	# ===== 2. 铸神条件 =====
	r = CharacterData.forge_divine(_xian_item())
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("铸神晶不足"),
		"没有铸神晶：铸神失败", String(r.get("message", "")))
	r = CharacterData.forge_divine(_xian_item(ItemDB.MAX_ENHANCE - 1))
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("+10"),
		"没满 +10：铸神失败", String(r.get("message", "")))
	var broken := _xian_item()
	broken["is_broken"] = true
	r = CharacterData.forge_divine(broken)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("破损"),
		"破损仙器：铸神失败", String(r.get("message", "")))
	var tr := CharacterData.make_treasure_instance(ItemDB.get_treasure_template("tr_huyao_ling"))
	r = CharacterData.forge_divine(tr)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("法宝"),
		"法宝不铸神", String(r.get("message", "")))

	# ===== 3. 铸神成功：品阶最高、等级归零、旧痕保留、晶石 -1 =====
	CharacterData.grant_material(CRYSTAL, 1)
	var fresh := _xian_item()
	fresh["enhance_fail_count"] = 3
	fresh["enhance_ascend_fail_count"] = 2
	fresh["enhance_wear_seq"] = [
		{"k": "n"}, {"k": "a", "g": "道器"}, {"k": "n"}, {"k": "a", "g": "仙器"}, {"k": "n"}]
	var attrs_before := (fresh["attributes"] as Dictionary).duplicate(true)
	r = CharacterData.forge_divine(fresh)
	_check(bool(r.get("ok", false)), "铸神成功", String(r.get("message", "")))
	_check(String(fresh.get("equipment_grade", "")) == "神器/先天至宝",
		"品阶 → 神器/先天至宝", String(fresh.get("equipment_grade", "")))
	_check(int(fresh.get("enhancement_level", -1)) == 0, "神器没有强化等级")
	_check(int(fresh.get("enhance_fail_count", -1)) == 3
			and int(fresh.get("enhance_ascend_fail_count", -1)) == 2
			and (fresh.get("enhance_wear_seq") as Array).size() == 5,
		"铸神保留旧痕（3 普 + 2 进，流水 5 格）", "%s / %s / %d" % [
			fresh.get("enhance_fail_count"), fresh.get("enhance_ascend_fail_count"),
			(fresh.get("enhance_wear_seq") as Array).size()])
	_check((fresh["attributes"] as Dictionary) == attrs_before, "铸神不改词条数值")
	_check(CharacterData.count_material(CRYSTAL) == 0, "铸神晶 -1")
	r = CharacterData.forge_divine(fresh)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("仙器"),
		"神器不能再铸神", String(r.get("message", "")))

	# ===== 4. 神器不可强化 =====
	r = CharacterData.enhance_item(fresh)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("神器"),
		"神器：强化被拒", String(r.get("message", "")))
	var dev := _tpl("eq_fangzhu_shenqi")
	r = CharacterData.enhance_item(dev)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("神器"),
		"开发者神器：同样不可强化", String(r.get("message", "")))

	# ===== 5. 补天：只清普通磨损 =====
	var m := _xian_item(0)
	m["equipment_grade"] = "灵器"
	m["enhance_fail_count"] = 6
	m["enhance_ascend_fail_count"] = 2
	r = CharacterData.mend_item(m)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("补天石不足"),
		"没有补天石：补天失败", String(r.get("message", "")))
	CharacterData.grant_material(STONE, 1)
	r = CharacterData.mend_item(m)
	_check(bool(r.get("ok", false)) and int(m.get("enhance_fail_count", -1)) == 2
			and int(m.get("enhance_ascend_fail_count", -1)) == 2,
		"补天清掉 4 道普通磨损，进阶失败的 2 道保留",
		"fail=%s ascend=%s" % [m.get("enhance_fail_count"), m.get("enhance_ascend_fail_count")])
	_check(CharacterData.count_material(STONE) == 0, "补天石 -1")
	var kept_seq: Array = m.get("enhance_wear_seq", [])
	_check(kept_seq.size() == 2 and String((kept_seq[0] as Dictionary).get("k", "")) == "a",
		"流水里只剩 2 条进阶失败记录", str(kept_seq))
	r = CharacterData.mend_item(m)
	_check(not bool(r.get("ok", false)) and String(r.get("message", "")).contains("普通失败"),
		"只剩进阶失败磨损：不能再补", String(r.get("message", "")))

	# 交错流水：补天只删普通，进阶按原顺序保留（含各自失败时品阶）
	var mixed := _xian_item(0)
	mixed["equipment_grade"] = "灵器"
	mixed["enhance_fail_count"] = 5
	mixed["enhance_ascend_fail_count"] = 2
	mixed["enhance_wear_seq"] = [
		{"k": "n"}, {"k": "a", "g": "凡品"}, {"k": "n"}, {"k": "a", "g": "宝器"}, {"k": "n"}]
	CharacterData.grant_material(STONE, 1)
	r = CharacterData.mend_item(mixed)
	var mixed_seq: Array = mixed.get("enhance_wear_seq", [])
	_check(bool(r.get("ok", false)) and mixed_seq.size() == 2
			and String((mixed_seq[0] as Dictionary).get("g", "")) == "凡品"
			and String((mixed_seq[1] as Dictionary).get("g", "")) == "宝器",
		"交错流水补天后：两条进阶记录按原顺序、原品阶保留", str(mixed_seq))

	# 破损但普通磨损没清完：补天能补回可强化状态
	var near := _tpl(WEAPON)
	near["equipment_grade"] = "凡品"
	near["is_broken"] = true
	near["enhance_fail_count"] = 10
	near["enhance_ascend_fail_count"] = 3
	CharacterData.grant_material(STONE, 1)
	r = CharacterData.mend_item(near)
	_check(bool(r.get("ok", false)) and not bool(near.get("is_broken", true))
			and int(near.get("enhance_fail_count", -1)) == 3,
		"破损（普通 7 + 进阶 3）→ 补天回 3/10，可继续强化",
		str(r.get("message", "")))
	var er := CharacterData.enhance_item(near)
	_check(bool(er.get("ok", false)), "补天后可以继续强化", String(er.get("message", "")))

	# 进阶失败占满 10 道：补天无效
	var doomed := _tpl(WEAPON)
	doomed["equipment_grade"] = "灵器"
	doomed["is_broken"] = true
	doomed["enhance_fail_count"] = 10
	doomed["enhance_ascend_fail_count"] = 10
	CharacterData.grant_material(STONE, 1)
	r = CharacterData.mend_item(doomed)
	_check(not bool(r.get("ok", false)) and bool(doomed.get("is_broken", false)),
		"进阶失败磨损占满：补天救不回来", String(r.get("message", "")))

	# ===== 6. 真实锻造台：顶栏材料动作 / 铭牌 / 点击 =====
	CharacterData.inventory.clear()
	var panel := ForgePanel.new()
	panel.set("_tutorial_seen", true)
	add_child(panel)
	panel.call("open")
	await _frames(6)
	var item_ui := _xian_item()
	panel.call("_refresh_content")
	await _frames(3)
	var divine_btn: Button = panel.get("_divine_btn")
	var mend_btn: Button = panel.get("_mend_btn")
	var yunxian_btn: Button = panel.get("_yunxian_btn")
	var mat_row: HBoxContainer = panel.get("_mat_row")
	var plaque: Control = panel.get("_plaque")
	_check(divine_btn != null and mend_btn != null and yunxian_btn != null,
		"锻造台建出铸神 / 补天 / 蕴仙三枚材料动作")
	var row_kids := mat_row.get_children()
	_check(row_kids.size() == 4 and row_kids[1] == mend_btn and row_kids[2] == divine_btn
			and row_kids[3] == yunxian_btn,
		"材料动作都并进顶栏晶石那一行（补天 / 铸神 / 蕴仙）", str(row_kids))
	_check(mend_btn.get_global_rect().position.x < divine_btn.get_global_rect().position.x,
		"按钮位置已交换：补天在左、铸神在右",
		"补天 x=%.0f 铸神 x=%.0f" % [mend_btn.get_global_rect().position.x,
			divine_btn.get_global_rect().position.x])
	var row_y := divine_btn.get_global_rect().position.y
	_check(row_y >= 0.0 and row_y + divine_btn.size.y <= 92.0,
		"材料动作落在顶栏木梁内", "y=%.0f h=%.0f" % [row_y, divine_btn.size.y])
	_check((row_kids[0] as Control).get_global_rect().end.x
			<= mend_btn.get_global_rect().position.x,
		"晶石数量在材料动作左边",
		"晶石右缘 %.0f / 补天左缘 %.0f" % [(row_kids[0] as Control).get_global_rect().end.x,
			mend_btn.get_global_rect().position.x])
	_check(yunxian_btn.get_global_rect().end.x <= 1160.0,
		"材料动作不压到右上角「关闭」", "右缘 %.0f" % yunxian_btn.get_global_rect().end.x)
	_check(mend_btn.text.contains("×") and divine_btn.text.contains("×")
			and yunxian_btn.text.contains("×"),
		"三枚动作都显示持有数量", "%s / %s / %s" % [mend_btn.text, divine_btn.text,
			yunxian_btn.text])
	# 空砧：数量照样显示，三枚都禁用
	_check(divine_btn.disabled and mend_btn.disabled and yunxian_btn.disabled,
		"空砧：三枚材料动作禁用")
	_check(divine_btn.text.contains("×0") and mend_btn.text.contains("×0")
			and yunxian_btn.text.contains("×0"),
		"空砧也有数量读数", "%s / %s / %s" % [mend_btn.text, divine_btn.text,
			yunxian_btn.text])
	panel._anvil_item = item_ui
	CharacterData.grant_material(CRYSTAL, 1)
	panel.call("_refresh_content")
	await _frames(4)
	_check(not divine_btn.disabled and divine_btn.text.contains("×1"),
		"满 +10 仙器 + 晶石：铸神可用", "%s disabled=%s" % [divine_btn.text, divine_btn.disabled])
	_check(mend_btn.disabled, "没有普通磨损：补天禁用")
	mend_btn.pressed.emit()
	await _frames(2)
	_check(not bool(panel.get("_special_busy")), "禁用的补天被点也不起演")
	_check(String(panel.get("_plaque_cost").text).contains("铸神晶"),
		"铭牌消耗行显示铸神晶", String(panel.get("_plaque_cost").text))
	_check(String(panel.call("_forge_block_reason")).contains("铸神"),
		"锤子提示去铸神", String(panel.call("_forge_block_reason")))
	var take_btn: Button = panel.get("_take_btn")
	_check(not (divine_btn.get_global_rect().intersects(take_btn.get_global_rect()))
			and not (mend_btn.get_global_rect().intersects(take_btn.get_global_rect())),
		"新按钮不和「取下」重叠")
	divine_btn.pressed.emit()
	await get_tree().create_timer(0.20).timeout
	_check(bool(panel.get("_special_busy")) and panel.get("_special_icon") != null,
		"点铸神：材料先飞向装备（演出中）")
	_check(String(panel.get("_anvil_item").get("equipment_grade", "")) == "仙器",
		"落锤前不结算：装备还是仙器",
		String(panel.get("_anvil_item").get("equipment_grade", "")))
	await get_tree().create_timer(1.05).timeout
	_check(String(panel.get("_anvil_item").get("equipment_grade", "")) == "神器/先天至宝",
		"点「铸神」真的铸成神器", String(panel.get("_anvil_item").get("equipment_grade", "")))
	_check(not bool(panel.get("_special_busy")), "铸神演出结束、按钮解锁")
	_check((panel.get("_last_special_flash") as Color) == Color(1.0, 0.80, 0.38, 1.0),
		"铸神落锤：装备亮金光", str(panel.get("_last_special_flash")))
	_check(String(panel.get("_plaque_meta").text).contains("已铸神"),
		"铭牌改显示「已铸神」", String(panel.get("_plaque_meta").text))
	_check(bool(panel.get("_plaque_pips").visible), "神器显示磨损刻度")
	_check(String(panel.get("_plaque_pip_caption").text) == "磨损 0 / 10",
		"神器磨损数量写在刻度行首", String(panel.get("_plaque_pip_caption").text))
	_check(not bool(panel.get("_plaque_affix").visible), "神器不显示强化词条")
	_check(String(panel.get("_plaque_cost").text).contains("神兵已成"), "神器消耗行收成「神兵已成」")
	_check(divine_btn.disabled, "铸神后按钮禁用")

	# 神器带旧痕：刻度照原流水上色（普通亮灰 / 进阶失败当时品阶）
	var divine_wear := _xian_item(0)
	divine_wear["equipment_grade"] = "神器/先天至宝"
	divine_wear["enhance_fail_count"] = 2
	divine_wear["enhance_ascend_fail_count"] = 1
	divine_wear["enhance_wear_seq"] = [{"k": "n"}, {"k": "a", "g": "道器"}, {"k": "n"}]
	panel._anvil_item = divine_wear
	panel.call("_refresh_content")
	await _frames(3)
	var pips: Array = panel.get("_plaque_pip_nodes")
	_check(bool(panel.get("_plaque_pips").visible)
			and String(panel.get("_plaque_pip_caption").text) == "磨损 3 / 10",
		"神器带旧痕：刻度与数量都显示", String(panel.get("_plaque_pip_caption").text))
	_check((pips[0] as ColorRect).color == ForgePanel.NORMAL_WEAR_COLOR
			and (pips[2] as ColorRect).color == ForgePanel.NORMAL_WEAR_COLOR
			and (pips[1] as ColorRect).color == UIKit.grade_color("道器"),
		"神器旧痕按原记录上色（普通亮灰 / 进阶当时品阶）",
		"%s / %s / %s" % [(pips[0] as ColorRect).color, (pips[1] as ColorRect).color,
			(pips[2] as ColorRect).color])
	_check(bool(panel.get("_mend_btn").disabled), "神器补天仍禁用（旧痕不可清）")

	# 补天按钮：普通 6 / 进阶 2，持有 1 石
	var wear_item := _tpl(WEAPON)
	wear_item["equipment_grade"] = "灵器"
	wear_item["enhance_fail_count"] = 6
	wear_item["enhance_ascend_fail_count"] = 2
	panel._anvil_item = wear_item
	CharacterData.grant_material(STONE, 1)
	panel.call("_refresh_content")
	await _frames(3)
	_check(not mend_btn.disabled and mend_btn.text.contains("×1"),
		"有普通磨损 + 补天石：补天可用", "%s disabled=%s" % [mend_btn.text, mend_btn.disabled])
	_check(mend_btn.text == "补天 ×1", "按钮显示当前补天石数量", mend_btn.text)
	_click(mend_btn.get_global_rect().get_center())
	await get_tree().create_timer(0.20).timeout
	_check(bool(panel.get("_special_busy")) and panel.get("_special_icon") != null,
		"鼠标点顶栏补天：材料先飞向装备（演出中）")
	_check(int(panel.get("_anvil_item").get("enhance_fail_count", -1)) == 6,
		"落锤前不结算：磨损还是 6",
		str(panel.get("_anvil_item").get("enhance_fail_count")))
	await get_tree().create_timer(1.05).timeout
	_check(int(panel.get("_anvil_item").get("enhance_fail_count", -1)) == 2
			and int(panel.get("_anvil_item").get("enhance_ascend_fail_count", -1)) == 2,
		"点「补天」只清普通磨损", "fail=%s" % panel.get("_anvil_item").get("enhance_fail_count"))
	_check((panel.get("_last_special_flash") as Color) == Color(0.52, 0.92, 0.66, 1.0),
		"补天落锤：装备亮绿光", str(panel.get("_last_special_flash")))
	_check(mend_btn.disabled, "补完（无普通磨损）按钮禁用")
	# 熔铸页收起三枚动作，晶石读数留着
	panel.call("_switch_mode", "melt")
	await _frames(4)
	_check(not mend_btn.visible and not divine_btn.visible and not yunxian_btn.visible,
		"熔铸页收起三枚材料动作")
	_check((mat_row.get_child(0) as Control).visible, "熔铸页仍显示晶石读数")
	panel.call("close")
	await _frames(2)

	CharacterData.inventory.clear()
	CharacterData.inventory.append_array(_saved_inv)
	print("")
