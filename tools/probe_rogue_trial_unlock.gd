extends Node
## 试炼之路入口前置解锁（2026-11-08 用户定：通关万界秘境·凡界的虎妖后开放）
##
## 验三态：全新档上锁 → 击败虎妖解锁 → 已有肉鸽进度的老档不反锁；
## 同时验「页签 / 踏入按钮 / 常驻提示 / 朱砂印」四处的联动与真实入口守卫。
## 用法：godot --headless --path . res://tools/probe_rogue_trial_unlock.tscn -- --no-save

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
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	print("\n########## 试炼之路入口前置解锁 ##########")
	var dp: Dictionary = CharacterData.domain_progress.duplicate(true)
	var runs := CharacterData.rogue_runs
	var best := CharacterData.rogue_best_floor

	# ===== 全新档：没打过虎妖、也没玩过试炼 → 上锁 =====
	CharacterData.domain_progress = {}
	CharacterData.rogue_runs = 0
	CharacterData.rogue_best_floor = 0
	_check(not RogueDB.trial_unlocked(), "全新档未通关虎妖 → 试炼未解锁")
	_check(RogueDB.TRIAL_UNLOCK_DOMAIN == "domain_01"
		and RogueDB.TRIAL_UNLOCK_BOSS == "boss_huyao",
		"前置指向凡界第一位 BOSS 虎妖",
		"%s / %s" % [RogueDB.TRIAL_UNLOCK_DOMAIN, RogueDB.TRIAL_UNLOCK_BOSS])

	var panel := TowerPanel.new()
	# ⚠ _ready 栈帧里 root 正在布置 children → 必须 call_deferred
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame

	var tabs: Array = panel.get("_tab_buttons")
	var tab: Button = tabs[1] as Button
	var enter: Button = panel.get("_rogue_enter_btn")
	var lock_lbl: Label = panel.get("_rogue_lock_label")
	var tag: PanelContainer = panel.get("_rogue_new_tag")
	var tag_lbl: Label = tag.get_child(0) as Label

	_check(not tab.disabled, "未解锁：页签仍可点（进去才看得到锁定原因）")
	_check(String(tab.tooltip_text).contains("虎妖"),
		"未解锁：页签 tooltip 写明条件", String(tab.tooltip_text))
	_check(enter.disabled, "未解锁：踏入试炼按钮不可点")
	_check(String(enter.tooltip_text).contains("虎妖"),
		"未解锁：按钮 tooltip 写明条件", String(enter.tooltip_text))
	_check(String(lock_lbl.text).contains("虎妖"),
		"未解锁：按钮上方常驻条件提示", String(lock_lbl.text))
	_check(is_equal_approx(lock_lbl.custom_minimum_size.y, 26.0),
		"提示行固定高度（解锁只清文字，几何不漂移）")
	_check(String(tag_lbl.text) == "未开放",
		"未解锁：朱砂印改「未开放」", String(tag_lbl.text))

	panel.call("_switch_tab", 1)
	_check(int(panel.get("_tab_index")) == 1,
		"未解锁：能切到试炼页查看禁用按钮与条件")
	_check(enter.disabled and String(lock_lbl.text).contains("虎妖"),
		"未解锁：试炼页里按钮禁用 + 条件提示可见")
	panel.call("_on_enter_rogue")
	_check(not RogueRun.active, "未解锁：直接调 _on_enter_rogue 也不开局")
	_check(bool(panel.get("_visible")),
		"未解锁：守卫在 close() 之前，面板没被误关")

	# ===== 击败虎妖：解锁 =====
	CharacterData.mark_boss_killed(RogueDB.TRIAL_UNLOCK_DOMAIN, RogueDB.TRIAL_UNLOCK_BOSS)
	_check(RogueDB.trial_unlocked(), "击败凡界虎妖后解锁")
	panel.call("_refresh_trial_lock")
	_check(not tab.disabled, "解锁后页签可点")
	_check(not enter.disabled, "解锁后按钮可点")
	_check(String(lock_lbl.text) == "", "解锁后提示清空（高度仍保留）")
	_check(String(tag_lbl.text) == "新玩法", "解锁后朱砂印恢复「新玩法」")
	panel.call("_switch_tab", 1)
	_check(int(panel.get("_tab_index")) == 1, "解锁后试炼页正常可用")

	# ===== 老档兼容：本模式先上线、门禁后补，不能反锁老玩家 =====
	CharacterData.domain_progress = {}
	CharacterData.rogue_runs = 3
	CharacterData.rogue_best_floor = 0
	_check(RogueDB.trial_unlocked(), "已有试炼局数的老档不反锁")
	CharacterData.rogue_runs = 0
	CharacterData.rogue_best_floor = 2
	_check(RogueDB.trial_unlocked(), "有历史最高层的老档不反锁")
	CharacterData.rogue_best_floor = 0
	_check(not RogueDB.trial_unlocked(), "清掉全部记录后重新上锁")

	# 还原（探针独立进程，但仍还原以免同一进程内后续步骤读到脏值）
	CharacterData.domain_progress = dp
	CharacterData.rogue_runs = runs
	CharacterData.rogue_best_floor = best
	RogueRun.restore()
	panel.close()
	await get_tree().process_frame
	if is_instance_valid(panel):
		panel.free()
