extends Node
## 锻造台自动锻造探针（2026-11-01）
## 验证：自动连锻会连续消耗晶石；材料/满阶/破损时停；中止按钮能立即停。

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
	print("\n########## 自动锻造探针 ##########")
	var panel := ForgePanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel._auto_btn != null and panel._auto_stop_btn != null,
		"自动锻造 / 中止按钮已创建")
	_check(not panel._auto_stop_btn.visible, "未启动时不显示中止键")

	# 空砧不能启动
	panel._anvil_item = {}
	panel._on_auto_pressed()
	_check(not panel._auto_forge, "空砧不启动自动锻造")

	# 连续锻造：给 100 晶石，自动敲 1.6 秒，至少消耗 2 颗
	var tpl: Dictionary = {}
	for raw in ItemDB.EQUIPMENT_TEMPLATES:
		tpl = raw as Dictionary
		if String(tpl.get("equipment_type", "")) != "treasure":
			break
	CharacterData.inventory = []
	var item := CharacterData.make_equipment_instance(tpl)
	CharacterData.grant_material(CharacterData.ENHANCE_MATERIAL, 100)
	panel._anvil_item = item
	panel._hammer_held = true
	panel._refresh_content()
	var before := CharacterData.count_material(CharacterData.ENHANCE_MATERIAL)
	panel._on_auto_pressed()
	_check(panel._auto_forge, "自动锻造启动")
	_check(panel._auto_stop_btn.visible, "启动后显示中止键")
	await get_tree().create_timer(1.6, true, false, true).timeout
	var spent := before - CharacterData.count_material(CharacterData.ENHANCE_MATERIAL)
	_check(spent >= 2, "自动连续锻造至少敲 2 次", "消耗晶石 %d" % spent)
	_check(panel._auto_stop_btn.visible, "自动运行中中止键保持可见")
	panel._on_auto_stop_pressed()
	_check(not panel._auto_forge, "点中止后立即停止")
	_check(not panel._auto_stop_btn.visible, "停止后隐藏中止键")
	# 中止时已经抬起的那一锤会挥完；等它结算完，之后再也不能自动扣晶石
	var settle := 0.0
	while panel._strike_state != panel.STRIKE_IDLE and settle < 1.5:
		await get_tree().create_timer(0.05, true, false, true).timeout
		settle += 0.05
	var spent_after := CharacterData.count_material(CharacterData.ENHANCE_MATERIAL)
	await get_tree().create_timer(0.8, true, false, true).timeout
	_check(CharacterData.count_material(CharacterData.ENHANCE_MATERIAL) == spent_after,
		"中止后不再自动扣晶石")

	# 晶石不足会自己停
	CharacterData.inventory = []
	CharacterData.grant_material(CharacterData.ENHANCE_MATERIAL, 1)
	panel._anvil_item = CharacterData.make_equipment_instance(tpl)
	panel._hammer_held = true
	panel._refresh_content()
	panel._on_auto_pressed()
	var guard := 0.0
	while panel._auto_forge and guard < 8.0:
		await get_tree().create_timer(0.1).timeout
		guard += 0.1
	_check(not panel._auto_forge, "晶石不足时自动停止", "等待 %.1fs" % guard)

	# 满阶不能启动
	var max_item := CharacterData.make_equipment_instance(tpl)
	max_item["equipment_grade"] = "仙器"
	max_item["enhancement_level"] = ItemDB.MAX_ENHANCE
	CharacterData.grant_material(CharacterData.ENHANCE_MATERIAL, 99)
	panel._anvil_item = max_item
	panel._refresh_content()
	panel._on_auto_pressed()
	_check(not panel._auto_forge, "满阶装备不启动自动锻造")

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
