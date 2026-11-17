extends Node
## 棋坛关卡 · 弃局返回（#58，2026-11-05）
##
## 守两件事：① 「返回原初位面」只在棋局场景出现，别给 BOSS 战开无代价逃跑键；
##          ② 弃局零代价 —— 不扣钱、不推进度、不限次，本局直接作废。
##
## 用法：godot --headless --path . res://tools/probe_match_abandon.tscn -- --no-save

const CRYSTAL := "mat_duanzaojingshi"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _wallet() -> int:
	return int(CharacterData.count_material(CRYSTAL))


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## 把棋局挂到 root 上并认作当前场景。
## ⚠ 必须 call_deferred：同步 add_child 会撞上 "Parent node is busy setting up children"
##   而被拒绝（上一版就栽在这，面板压根没进树，① 假红成"按钮不存在"）。
##   而 `current_scene` 又要求目标已经是 root 的子节点，所以顺序是
##   deferred add → 等帧 → 赋 current_scene。
func _enter_arena(level: int) -> Node:
	CharacterData.match_level_cleared = level - 1
	GameState.match_context = {"level": level}
	var arena: Node = (load("res://scenes/match/match_arena.tscn") as PackedScene).instantiate()
	arena.set("player_stage_timeout", 1.0)
	get_tree().root.add_child.call_deferred(arena)
	await _settle(12)
	get_tree().current_scene = arena
	await _settle(12)
	return arena


## 在"当前场景"之上打开设置面板，返回那个面板实例
func _open_settings() -> Node:
	var p: Node = load("res://scripts/ui/settings_panel.gd").new()
	p.set("from_title", false)
	get_tree().root.add_child.call_deferred(p)
	await _settle(4)
	p.open()
	await _settle(6)
	return p


func _find_btn(panel: Node, needle: String) -> Button:
	for c in _all_controls(panel):
		if c is Button and String((c as Button).text).contains(needle):
			return c as Button
	return null


func _all_controls(node: Node, acc: Array[Control] = []) -> Array[Control]:
	for ch in node.get_children():
		if ch is Control:
			acc.append(ch as Control)
		_all_controls(ch, acc)
	return acc


func _ready() -> void:
	print("\n########## 棋坛关卡 · 弃局返回 ##########")
	await _check_only_in_match()
	await _check_abandon_cost()
	_check_confirm_and_weight()
	_finish()


## ① 场景作用域：只有棋局里能看到这条
func _check_only_in_match() -> void:
	CharacterData.inventory = [_crystal(100)]
	var arena := await _enter_arena(3)
	_check(String(get_tree().current_scene.name) == "MatchArena",
			"① 测试台已把棋局认作当前场景", _scene_name(get_tree().current_scene))

	var p := await _open_settings()
	_check(_find_btn(p, "返回原初位面") != null, "① 棋局里设置面板有「返回原初位面」", "")
	_check(_find_btn(p, "返回登录界面") != null,
			"① 「返回登录界面」仍在原位（两条不是替换关系）", "")
	p.close()
	await _settle(6)
	arena.queue_free()
	await _settle(6)
	GameState.match_context = {}


## ② 弃局的代价：什么都不发生，除了回到原初位面
func _check_abandon_cost() -> void:
	CharacterData.inventory = [_crystal(100)]
	var deck_before: Array = MatchLevelDeck.deck_for(3)
	var arena := await _enter_arena(3)

	var p := await _open_settings()
	var btn := _find_btn(p, "返回原初位面")
	if btn == null:
		_check(false, "② 找不到弃局按钮，后面全跑不了", "")
		return
	# 有二次确认就先确认掉（防误触丢一局，见工单说明）。
	# ⚠ 按对话框自己的 ok_text 找按钮，不是硬写"确定" —— 否则实现里改个措辞测试就假红。
	btn.pressed.emit()
	await _settle(6)
	var dlg := _find_confirm_dialog()
	_check(dlg != null, "② 弃局弹出了二次确认（丢的是十几分钟，不是钱）", "")
	if dlg != null:
		print("      确认框：", String(dlg.get("dlg_title")), " / ", String(dlg.get("ok_text")))
		var ok_btn := _find_btn(dlg, String(dlg.get("ok_text")))
		_check(ok_btn != null, "② 确认框的确定按钮找得到", String(dlg.get("ok_text")))
		if ok_btn != null:
			ok_btn.pressed.emit()
	await _settle(40)

	_check(String(get_tree().current_scene.name) == "PrimordialRealm",
			"② 弃局回到原初位面（不是登录界面、不是长卷）",
			_scene_name(get_tree().current_scene))
	_check(not get_tree().paused, "② 弃局后没把 paused 漏给主城", str(get_tree().paused))
	_check(_wallet() == 100, "② 弃局不扣一分钱", "钱包=%d" % _wallet())
	_check(CharacterData.match_level_cleared == 2, "② 弃局不算通过、不推进度",
			"%d" % CharacterData.match_level_cleared)
	_check(MatchLevelDeck.deck_for(3) == deck_before, "② 重进第 3 关对手卡组一字不变",
			str(deck_before))
	GameState.match_context = {}


## ③ 权重与文案：这条是次要动作，不能盖过「返回登录界面」
func _check_confirm_and_weight() -> void:
	var src := FileAccess.get_file_as_string("scripts/ui/settings_panel.gd")
	_check(src.contains("返回原初位面"), "③ 面板源码里真有这条", "")
	_check(not src.contains("primary_button(\"返回原初位面"),
			"③ 它不是主按钮（一屏一个最高权重，那是「手动存档」的）", "")
	_check(not src.contains("danger_button(\"返回原初位面"),
			"③ 它不是危险按钮（弃局零代价，不该用扣钱那一档红）", "")
	# 只在棋局出现 ⇒ 判据必须按场景来，而不是无条件 add_child
	_check(src.contains("MatchArena") or src.contains("match_arena"),
			"③ 出现与否是按棋局场景判的（不是所有场景都摆）", "")


## 按类找，不按节点名猜：`ConfirmDialog.new()` 出来的节点名不保证含 "Confirm"，
## 上一版按名字找 → 假红成"没有二次确认"，而实际上确认框正开着并把树暂停着。
func _find_confirm_dialog() -> Node:
	for c in get_tree().root.get_children():
		if c is ConfirmDialog:
			return c
	return null


func _scene_name(n: Node) -> String:
	return "<null>" if n == null else String(n.name)


func _crystal(n: int) -> Dictionary:
	var def := ItemDB.get_material(CRYSTAL)
	return {"id": CRYSTAL, "name": String(def.get("name", CRYSTAL)), "type": "material",
		"count": n, "icon": String(def.get("icon", ""))}


func _finish() -> void:
	CharacterData.inventory = []
	GameState.match_context = {}
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
