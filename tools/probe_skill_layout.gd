extends Node
## 功法库展开详情自检（2026-10-30）：
## 长文本（负阴抱阳 / 气环·回息 / 盗火者等）展开后不能把内容区横向撑出面板宽度。
## 用法：godot --headless --path . tools/probe_skill_layout.tscn -- --no-save

var _passes := 0
var _fails: Array = []

const TARGETS := [
	"skill_yinyang_harmony", "skill_qi_ring_heal", "skill_sun_wheel",
	"skill_qi_breath", "skill_blade_scar",
]


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _group_for_skill(sid: String) -> String:
	for g in SkillDB.get_library_groups():
		for raw in (g as Dictionary).get("skills", []):
			if String((raw as Dictionary).get("skill_id", "")) == sid:
				return String((g as Dictionary).get("group_id", ""))
	return ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 功法库详情排版探针 ##########")
	for sid in TARGETS:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)

	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame

	for sid in TARGETS:
		panel._expanded_skills.clear()
		panel._expanded_skills[sid] = true
		for gid in panel._expanded.keys():
			panel._expanded[gid] = false
		var gid := _group_for_skill(String(sid))
		if gid != "":
			panel._expanded[gid] = true
		panel._refresh_content()
		await get_tree().process_frame
		await get_tree().process_frame
		var content := panel.content
		var content_w := content.size.x
		var min_w := content.get_combined_minimum_size().x
		_check(content_w > 100.0 and min_w <= content_w + 1.0,
			"展开详情不撑宽内容区：%s" % String(sid),
			"min=%.1f width=%.1f" % [min_w, content_w])
		var detail := panel.find_child("SkillDetail_" + String(sid), true, false)
		_check(detail != null, "详情节点存在：%s" % String(sid))
		if detail != null:
			var detail_w: float = float(detail.get_combined_minimum_size().x)
			_check(detail_w <= content_w + 1.0, "详情卡不超宽：%s" % String(sid),
				"detail=%.1f" % detail_w)
			var all_wrapped := true
			var no_markup := true
			for n in detail.find_children("*", "Label", true, false):
				var l := n as Label
				if l == null:
					continue
				if l.text.length() > 18 and l.autowrap_mode == TextServer.AUTOWRAP_OFF:
					all_wrapped = false
				if l.text.contains("**"):
					no_markup = false
			_check(all_wrapped, "长文本已换行：%s" % String(sid))
			_check(no_markup, "详情不显示 ** 标记：%s" % String(sid))
			var equip_btn: Button = null
			for b in detail.find_children("*", "Button", true, false):
				var btn := b as Button
				if btn != null and (btn.text.contains("装配") or btn.text.contains("卸下")):
					equip_btn = btn
			_check(equip_btn != null and equip_btn.size.y <= 40.0,
				"装配按钮不被纵向拉伸：%s" % String(sid),
				"h=%.1f" % (equip_btn.size.y if equip_btn != null else -1.0))

	panel.close()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
