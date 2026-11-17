extends Node
## F2 开发者面板「修为」按钮的验收探针。
##
## 跑法：godot --headless --path . --quit-after 900 res://tools/probe_debug_exp_button.tscn -- --no-save
##
## 为什么要有：这个面板是给用户自己测试用的工具，按下去没反应（或到顶时静默不涨）
## 最容易被当成「按钮坏了」。所以判据不只看数值动没动，还看**回执文字有没有讲清楚**。
##
## ⚠ 探针会临时改 CharacterData 的境界/修为 —— 一律 `--no-save` 且结尾原样复原。

var _passes := 0
var _fails: Array = []


func _ready() -> void:
	print("\n########## F2 面板 · 修为按钮 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			out.append(c)
		_collect_buttons(c, out)


func _run() -> void:
	var panel := DebugItemPanel.new()
	add_child(panel)
	await get_tree().process_frame

	# ===== 1. 页面上真的有这三个按钮（不是只有处理函数能跑）=====
	var buttons: Array = []
	_collect_buttons(panel, buttons)
	var texts: Array[String] = []
	for b in buttons:
		texts.append(String((b as Button).text))
	var small := 0
	var large := 0
	var filled := 0
	for t in texts:
		if t.begins_with("修为 +"):
			if "100" in t and "1000" not in t:
				small += 1
			elif "1000" in t:
				large += 1
		elif t == "补满本阶段修为":
			filled += 1
	_check(small >= 1 and large >= 1 and filled >= 1,
		"快捷页有「修为 +100 / +1000 / 补满」三个按钮",
		"%d / %d / %d" % [small, large, filled])
	var label_ok := panel.get("_exp_label") != null
	_check(label_ok, "修为回执 Label 已建出来（不然点了看不到）")

	# ===== 2. 数值：加得进去、夹到上限、到顶不再涨 =====
	var keep_realm: String = CharacterData.current_realm
	var keep_stage := int(CharacterData.realm_stage)
	var keep_exp := int(CharacterData.realm_exp)
	var req := CharacterData.get_stage_exp_required()
	_check(req > 0, "本阶段所需修为读得出来", str(req))

	CharacterData.realm_exp = 0
	panel._grant_exp(100)
	_check(int(CharacterData.realm_exp) == mini(100, req),
		"+100 实际加 100（未夹时）", "%d" % int(CharacterData.realm_exp))
	var note1 := String(panel.get("_exp_note"))
	_check("实际 100" in note1 or "实际 %d" % mini(100, req) in note1,
		"回书写明实际到账数", note1)

	panel._grant_exp(999999)
	_check(int(CharacterData.realm_exp) == req,
		"超出部分夹到本阶段上限（不会溢出到不需要突破就能继续涨）",
		"%d / %d" % [int(CharacterData.realm_exp), req])
	panel._grant_exp(100)
	_check(int(CharacterData.realm_exp) == req, "已满时再加不涨")
	var note2 := String(panel.get("_exp_note"))
	_check("已满" in note2,
		"到顶那一次要点明原因（否则看着像按钮坏了）", note2)
	var label_text := String((panel.get("_exp_label") as Label).text)
	_check("需突破" in label_text, "Label 上有「本阶段已满，需突破」", label_text)

	CharacterData.realm_exp = 0
	panel._fill_exp()
	_check(int(CharacterData.realm_exp) == req, "「补满」一次到上限",
		"%d / %d" % [int(CharacterData.realm_exp), req])
	panel._fill_exp()
	_check("本来就是满的" in String(panel.get("_exp_note")),
		"重复点「补满」也说清楚", String(panel.get("_exp_note")))

	# ===== 3. 文案：化神没有小阶段，不能拼出「化神None / 化神」后面挂空档 =====
	CharacterData.current_realm = CharacterData.REALM_HUASHEN
	CharacterData.realm_exp = 0
	panel._refresh_exp_label()
	var hs := String((panel.get("_exp_label") as Label).text)
	_check("化神" in hs and "None" not in hs and "null" not in hs,
		"化神（无小阶段）的回执读得通", hs)
	_check(str(CharacterData.get_stage_exp_required()) in hs,
		"化神按 99999 封顶显示", hs)

	# ===== 4. 复原 =====
	CharacterData.current_realm = keep_realm
	CharacterData.realm_stage = keep_stage
	CharacterData.realm_exp = keep_exp
	panel.queue_free()
	await get_tree().process_frame
	_check(int(CharacterData.realm_exp) == keep_exp
			and CharacterData.current_realm == keep_realm,
		"探针跑完把 CharacterData 原样还回去了",
		"%s / %d" % [CharacterData.current_realm, int(CharacterData.realm_exp)])
