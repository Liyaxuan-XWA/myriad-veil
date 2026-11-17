extends Node
## 功法库搭配自检（2026-10-30）：
## 4 个主动键位可留空 / 任意指派 / 互换；卸下某个键不能把后面的技能整体前移；
## 被动槽仍只有 1 个，且可选择 / 更换 / 清空。
## 用法：godot --headless --path . tools/probe_skill_loadout.tscn -- --no-save

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 功法库搭配探针 ##########")
	var actives := ["skill_blade_slash", "skill_blade_scar", "skill_blade_peak",
		"skill_sword_stab", "skill_sword_myriad"]
	var passives := ["skill_yinyang_harmony", "skill_qi_ring_heal"]
	for sid in actives + passives:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = []
	CharacterData.passive_skill_loadout = []

	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame

	_check(SkillPanel.MAX_ACTIVE == 4 and CharacterData.MAX_ACTIVE_SKILLS == 4,
		"主动固定 4 个键位")

	panel._assign_active_to_slot(0, actives[0])
	_check(CharacterData.active_skill_loadout == [actives[0]], "装到 Q",
		str(CharacterData.active_skill_loadout))
	panel._assign_active_to_slot(2, actives[2])
	_check(CharacterData.active_skill_loadout == [actives[0], "", actives[2]],
		"可跳过 E 直接装到 R", str(CharacterData.active_skill_loadout))
	panel._assign_active_to_slot(1, actives[1])
	_check(CharacterData.active_skill_loadout == [actives[0], actives[1], actives[2]],
		"E 仍可补装", str(CharacterData.active_skill_loadout))
	panel._assign_active_to_slot(1, actives[4])
	_check(CharacterData.active_skill_loadout == [actives[0], actives[4], actives[2]],
		"换掉 E 的技能", str(CharacterData.active_skill_loadout))
	panel._assign_active_to_slot(2, actives[0])
	_check(CharacterData.active_skill_loadout == [actives[2], actives[4], actives[0]],
		"把 Q 的技能拖到 R 时互换键位", str(CharacterData.active_skill_loadout))
	var mapped := CharacterData.equipped_active_skills()
	_check(mapped.size() == 4 and mapped[0] == actives[2] and mapped[1] == actives[4]
		and mapped[2] == actives[0] and mapped[3] == "",
		"战斗键位按槽位保留空槽", str(mapped))
	panel._clear_active_slot(1)
	_check(CharacterData.active_skill_loadout == [actives[2], "", actives[0]],
		"卸下 E 不会让 R 前移", str(CharacterData.active_skill_loadout))
	_check(CharacterData.active_skill_count() == 2, "主动计数不计空槽",
		str(CharacterData.active_skill_count()))

	panel._assign_passive_to(passives[0])
	_check(CharacterData.passive_skill_loadout == [passives[0]], "装被动",
		str(CharacterData.passive_skill_loadout))
	panel._assign_passive_to(passives[1])
	_check(CharacterData.passive_skill_loadout == [passives[1]], "换被动仍是 1 门",
		str(CharacterData.passive_skill_loadout))
	panel._assign_passive_to("")
	_check(CharacterData.passive_skill_loadout.is_empty(), "清空被动槽")

	# 技能 → 装配：弹出四槽面板，选槽是「替换」不是交换
	panel._open_active_slot_popup(actives[3])
	await get_tree().process_frame
	await get_tree().process_frame
	var popup := panel.find_child("ActiveSlotPopup", true, false)
	_check(popup != null, "技能装配弹出四槽面板")
	if popup != null:
		_check(popup.find_children("AssignSlot_*", "Button", true, false).size() == 4,
			"面板显示 4 个键位槽")
	panel._close_active_slot_popup()
	await get_tree().process_frame

	# 真实按钮：点四槽面板里的空槽应直接装入
	CharacterData.active_skill_loadout = [actives[0], "", actives[2]]
	panel._open_active_slot_popup(actives[3])
	await get_tree().process_frame
	await get_tree().process_frame
	var empty_slot := panel.find_child("AssignSlot_1", true, false) as Button
	_check(empty_slot != null, "四槽面板的空槽按钮可点")
	if empty_slot != null:
		empty_slot.pressed.emit()
		await get_tree().process_frame
		_check(CharacterData.active_skill_loadout == [actives[0], actives[3], actives[2]],
			"点空槽直接装入（真实按钮）", str(CharacterData.active_skill_loadout))

	CharacterData.active_skill_loadout = [actives[0], "", actives[2]]
	panel._equip_active_to_slot_replace(1, actives[3])
	_check(CharacterData.active_skill_loadout == [actives[0], actives[3], actives[2]],
		"选空槽直接装入", str(CharacterData.active_skill_loadout))
	CharacterData.active_skill_loadout = [actives[0], actives[1], actives[2]]
	panel._equip_active_to_slot_replace(0, actives[3])
	_check(CharacterData.active_skill_loadout == [actives[3], actives[1], actives[2]],
		"选空槽/占位槽：替换原技能", str(CharacterData.active_skill_loadout))
	panel._equip_active_to_slot_replace(2, actives[3])
	_check(CharacterData.active_skill_loadout == ["", actives[1], actives[3]],
		"技能移到别的槽：原槽清空、目标槽替换",
		str(CharacterData.active_skill_loadout))
	panel._equip_active_to_slot_replace(1, actives[4])
	_check(CharacterData.active_skill_loadout == ["", actives[4], actives[3]],
		"目标槽有技能时先卸下再装", str(CharacterData.active_skill_loadout))
	_check(CharacterData.active_skill_count() == 2, "替换后计数正确",
		str(CharacterData.active_skill_count()))

	# ===== 符匣入口（2026-11-12 显眼化）=====
	# ⚠ 这里锁的是「入口能不能被看见」，不是「功能在不在」：
	#   原来它是 quiet_button（皮肤 = StyleBoxEmpty，一点底都没有）+ 字号 10，
	#   和右边同样灰同样小的提示句连成一句话 → 功能一直都在，玩家找不到。
	var cab_btn := _find_cabinet_entry(panel)
	_check(cab_btn != null, "功法库头部有符匣入口")
	if cab_btn != null:
		_check(String(cab_btn.get("tone")) != "quiet",
			"入口有按钮底（不是无底 quiet）", String(cab_btn.get("tone")))
		_check(int(cab_btn.get_theme_font_size("font_size")) >= 12,
			"入口字号 ≥12（不再是角标级 10）",
			str(int(cab_btn.get_theme_font_size("font_size"))))
		_check(cab_btn.custom_minimum_size.x >= 120.0,
			"入口宽度够放状态文字", str(cab_btn.custom_minimum_size))
		_check(not cab_btn.disabled, "空匣时入口仍可点（禁用反而更找不到）")

	# 文案随库存**现算**，不另存计数
	var keep_stock: Dictionary = CharacterData.talisman_stock.duplicate(true)
	CharacterData.talisman_stock.clear()
	panel._refresh_content()
	await get_tree().process_frame
	cab_btn = _find_cabinet_entry(panel)
	_check(cab_btn != null and "还没有符" in String(cab_btn.text),
		"空匣 → 文案说「还没有符」", String(cab_btn.text) if cab_btn != null else "null")
	CharacterData.talisman_stock["tal_jinfeng_lianqi"] = 3
	CharacterData.talisman_stock["tal_huoqiu_lianqi"] = 1
	panel._refresh_content()
	await get_tree().process_frame
	cab_btn = _find_cabinet_entry(panel)
	_check(cab_btn != null and "2 种" in String(cab_btn.text),
		"两种符 → 「符匣 · 2 种」（张数多也不重复计）",
		String(cab_btn.text) if cab_btn != null else "null")

	# ⚠ 关键一条：在匣里画完符（成符只加 talisman_stock，**不发 assigned**）后关掉，
	#   入口数字必须跟着刷 —— 撤掉 closed 里的 _refresh_content 这条就红。
	panel._open_cabinet(-1)
	await get_tree().process_frame
	await get_tree().process_frame
	var cab = panel.get("_cabinet")
	_check(cab != null and is_instance_valid(cab), "入口按下去真的打开符匣")
	CharacterData.talisman_stock["tal_yinlei_lianqi"] = 2
	if cab != null and is_instance_valid(cab):
		cab.call("_close")
		await get_tree().process_frame
		await get_tree().process_frame
	cab_btn = _find_cabinet_entry(panel)
	_check(cab_btn != null and "3 种" in String(cab_btn.text),
		"关掉符匣后计数刷新（成符不发 assigned）",
		String(cab_btn.text) if cab_btn != null else "null")

	for raw_k in keep_stock.keys():
		CharacterData.talisman_stock[String(raw_k)] = int(keep_stock[raw_k])
	for probe_k in ["tal_jinfeng_lianqi", "tal_huoqiu_lianqi", "tal_yinlei_lianqi"]:
		if not keep_stock.has(probe_k):
			CharacterData.talisman_stock.erase(probe_k)

	panel.close()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


## 在面板子树里找符匣入口：**按文案前缀认，不按节点名** ——
## 代码 new() 出来的节点名是 @Button@123 这种自动名，按名字找永远找不到（今天栽过两次）。
func _find_cabinet_entry(node: Node) -> Button:
	for c in node.get_children():
		if c is Button and String((c as Button).text).begins_with("符匣"):
			return c as Button
		var found := _find_cabinet_entry(c)
		if found != null:
			return found
	return null
