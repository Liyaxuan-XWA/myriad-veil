extends Node
## 快速模式开关与存档字段（票 001）
##
## 这一票只验三件事：默认必须是「关」、老档缺字段不能沿用内存里的脏值、
## 开关拨动要真的能落盘再读回来（走真文件，不是只在内存里 capture/apply）。
##
## ⚠ 不碰玩家任何真实槽位：真盘测试用 `slot_path(9)`，9 > SLOT_COUNT，
##   游戏永远不会读它，跑完立刻删。
##
## 用法：godot --headless --path . res://tools/probe_match_quick_switch.tscn -- --no-save

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
	print("\n########## 快速模式开关 · 票 001 ##########")
	_check_legacy_default()
	_check_disk_roundtrip()
	await _check_scroll_toggle()
	await _check_strip_budget()
	_finish()


## ① 老档没有 match_quick_mode 这个键 ⇒ 必须按「关」处理。
## 这条不是走形式：存档读回是往 CharacterData 上**覆盖**，
## 缺字段时不显式置 false，就会把上一局留在内存里的 true 带进新档 ——
## 玩家开个新档莫名其妙进了快速模式，而且和「默认关」的拍定相反。
func _check_legacy_default() -> void:
	CharacterData.match_quick_mode = true
	SaveManager.apply({"player_name": "老档"})
	_check(CharacterData.match_quick_mode == false,
			"① 老档缺字段 ⇒ 按关处理，不沿用内存里的脏值",
			str(CharacterData.match_quick_mode))


## ② 真盘往返：开 → 落盘 → 清内存 → 读回；关 → 落盘 → 清内存 → 读回。
## 只在内存里 capture/apply 不算数 —— 那验的是字典，不是 JSON 序列化。
func _check_disk_roundtrip() -> void:
	var scratch := SaveManager.slot_path(9)
	for want in [true, false]:
		CharacterData.match_quick_mode = want
		var f := FileAccess.open(scratch, FileAccess.WRITE)
		if f == null:
			_check(false, "② 临时文件打不开", scratch)
			return
		f.store_string(JSON.stringify(SaveManager.capture()))
		f.close()
		CharacterData.match_quick_mode = not want      # 抹掉内存里的值，逼它真从盘上读
		SaveManager.apply(JSON.parse_string(FileAccess.get_file_as_string(scratch)))
		_check(CharacterData.match_quick_mode == want,
				"② 开关 %s 经真盘落盘再读回一致" % ("开" if want else "关"),
				str(CharacterData.match_quick_mode))

	# 磁盘上必须是 JSON 布尔 true/false，不是 "true"、不是 1/0。
	# 写成字符串的那一版，读回来会被上面的"只认真布尔"清洗成关 —— 玩家设了等于没设。
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(scratch))
	var on_disk: Variant = (raw as Dictionary).get("match_quick_mode", null)
	_check(on_disk is bool, "② 磁盘上这个键是真布尔，不是字符串也不是 1/0", str(on_disk))

	DirAccess.remove_absolute(scratch)
	_check(not FileAccess.file_exists(scratch), "② 临时文件已清掉，没留垃圾", scratch)


## ③ 底栏那颗开关：文案跟着字段、点一下真翻转、且不抢主按钮。
## 只测字段读写不算数——用户报的一直是"点了没反应"那一类，
## 所以文案变化和 tone 都要验。
func _check_scroll_toggle() -> void:
	CharacterData.match_quick_mode = false
	CharacterData.match_level_cleared = 2
	var s: Control = MatchLevelScroll.new()
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(s)
	await _settle(14)

	var btn := _find_quick_btn(s)
	_check(btn != null, "③ 底栏有「快速模式」开关", "")
	if btn == null:
		s.queue_free()
		return
	_check(String(btn.text).contains("关"), "③ 默认关时文案写「关」", String(btn.text))
	_check(String(btn.get("tone")) != "primary",
			"③ 开关不是 primary（整屏只有「进入此关」是主按钮）", String(btn.get("tone")))

	btn.pressed.emit()
	await _settle(2)
	_check(CharacterData.match_quick_mode == true, "③ 点一下 ⇒ 字段翻到开",
			str(CharacterData.match_quick_mode))
	_check(String(btn.text).contains("开"), "③ 点一下 ⇒ 文案立刻跟着变", String(btn.text))
	btn.pressed.emit()
	await _settle(2)
	_check(CharacterData.match_quick_mode == false, "③ 再点一下 ⇒ 翻回关",
			str(CharacterData.match_quick_mode))

	# 三颗钮要都在屏内且互不重叠。
	# ⚠ 2026-11-05 起「返回原初位面」不在底栏了（挪到右上角贴着常驻「设置」），
	#   所以这里量的不是"底栏三颗"，而是"这一屏的三颗出口/模式/主按钮"——
	#   返回键挪走之后底栏只剩 读数 + 6 张小卡 + 开关 + 进入，宽度预算反而更松。
	var cta: Control = s.get("_cta")
	var back: Control = s.get("_back_btn")
	var bad := _strip_bad(btn, cta, back, get_tree().root.get_visible_rect().size)
	_check(bad.is_empty(), "③ 开关/进入/返回三颗都在屏内且互不重叠", str(bad))
	_check(back.get_global_rect().position.y < 60.0,
			"③ 返回键已离开底栏（贴在右上角）", str(back.get_global_rect()))

	s.queue_free()
	await _settle(3)


## 底栏几何判据（③ 与 ④ 共用）。
## ⚠ 本机 4.7.2 build 的坑两处：Node 上没有 get_viewport_rect()（那是 CanvasItem 的），
##   Rect2 也没有 is_empty()。都要绕开，否则整脚本 parse error、探针零输出挂死。
func _strip_bad(quick: Control, cta: Control, back: Control, vs: Vector2) -> Array:
	var rects := {"开关": quick.get_global_rect(), "进入": cta.get_global_rect(),
			"返回": back.get_global_rect()}
	var bad: Array = []
	for k in rects:
		var r: Rect2 = rects[k]
		if r.end.x > vs.x + 1.0 or r.position.x < -1.0 or r.size.x <= 0.0:
			bad.append("%s 出屏/零宽 %s" % [k, str(r)])
		if r.end.y > vs.y + 1.0:
			bad.append("%s 掉出底边 %s" % [k, str(r)])
	var keys: Array = rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			var inter := a.intersection(b)
			if inter.size.x > 0.5 and inter.size.y > 0.5:
				bad.append("%s×%s 重叠 %s" % [keys[i], keys[j], str(inter)])
	return bad


## ④ 底栏宽度预算。
## ⚠ 先说清这条量的是**控件自己的布局数学**，不是玩家实际会撞到的窗口：
##   本项目 `window/stretch/mode = canvas_items` + `aspect = expand`，
##   任何窗口都会先被抬到**至少 1280×720 的布局单位**，
##   所以 740×360 的窗口里底栏照样放得下（`--only-narrow` 截图证实：
##   三颗钮 + 6 张缩略全在，只是整体缩小）。
##   第一版在这里加了"放不下就收掉缩略卡带"的保底 —— 那是给一个
##   引擎根本不会产生的状态写分支，已回滚（见票 009 ②）。
##   留下来的判据改成**预算本身**：底栏最小宽必须始终放得进引擎给的布局宽度。
##   以后谁再往底栏加第三颗钮、把最小宽推过 1280，这里立刻红。
func _check_strip_budget() -> void:
	var vs_real: Vector2 = get_tree().root.get_visible_rect().size
	var s: Control = MatchLevelScroll.new()
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(s)
	await _settle(14)
	var cta: Control = s.get("_cta")
	var back: Control = s.get("_back_btn")
	var row: Control = (cta.get_parent() as Control).get_parent()
	var need: float = row.get_combined_minimum_size().x
	print("    引擎给的布局宽=%.0f 底栏最小宽=%.0f（读数+缩略+开关+进入）" % [vs_real.x, need])
	_check(need <= vs_real.x,
			"④ 底栏最小宽放得进布局宽度（再加钮就会红在这里）",
			"需 %.0f / 有 %.0f ⇒ 余量 %.0f" % [need, vs_real.x, vs_real.x - need])
	_check(_strip_bad(_find_quick_btn(s), cta, back, vs_real).is_empty(),
			"④ 真实布局宽度下三颗钮都在屏内且互不重叠",
			str(_strip_bad(_find_quick_btn(s), cta, back, vs_real)))
	# 余量打印：底栏距离布局宽度还剩多少（850 是实测，不是猜）
	print("    余量=%.0fpx（再加一颗 150px 的钮还剩 %.0f）" % [
		vs_real.x - need, vs_real.x - need - 160.0])
	s.queue_free()
	await _settle(3)


func _find_quick_btn(node: Node) -> Button:
	for c in node.get_children():
		if c is Button and String((c as Button).text).contains("快速模式"):
			return c as Button
		var hit := _find_quick_btn(c)
		if hit != null:
			return hit
	return null


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
