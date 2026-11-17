extends Node2D
## 万界秘境 · 守关者按序挑战（2026-11-12 用户定）
##
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_domain_boss_order.tscn -- --no-save
##
## 判据口径：
##   ① 顺序**不写死在代码里**，就是 WorldDB.DOMAINS.boss_ids 的数组顺序 —— 探针验的是
##      「这条顺序被当成门槛」，不是「顺序等于某三个名字」（凡界那一组名字单独验一次，
##      因为用户点名了它）；
##   ② 推进进度一律走生产写入函数 `mark_boss_killed`，不手搓 domain_progress
##      （只有「老档跳着打过」这一种现实里已经存在的状态才直接摆）；
##   ③ 卡面走真实控件：`board.setup(凡界)` 之后从树里捞挑战按钮，判 disabled 与文案，
##      不重抄一遍判定；
##   ④ `start_domain` 两条路都验：拒绝时断言「sentinel 没被改写 + 场景没切」；
##      放行时把探针搬到 root 底下再真进一次战斗场景（见 §9 的注释）。

const BOARD := preload("res://scripts/ui/facility/domain_boss_board.gd")

const D1 := "domain_01"
const D2 := "domain_02"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ids(did: String) -> Array:
	var out: Array = []
	for b in WorldDB.get_domain(did).get("boss_ids", []):
		out.append(String(b))
	return out


## 把 boss_id 列表念成「虎妖 → 刀客 → 剑客」（GDScript 4 的数组推导嵌在调用里会解析炸，
## 所以老老实实循环）
func _names(ids: Array) -> String:
	var parts: Array[String] = []
	for i in ids:
		parts.append(WorldDB.get_boss_name(String(i)))
	return " → ".join(parts)


func _reset(did: String) -> void:
	CharacterData.domain_progress[did] = {"unlocked": false, "cleared_bosses": []}


## 卡面上的挑战按钮（两套卡面都挂 meta tut=domain.enter，按树顺序 = boss_ids 顺序）
func _fight_buttons(board: Control) -> Array:
	var out: Array = []
	for n in board.find_children("*", "Button", true, false):
		var b := n as Button
		if b != null and String(b.get_meta("tut", "")) == "domain.enter":
			out.append(b)
	return out


func _ready() -> void:
	print("\n########## 守关者按序挑战 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# ===== 1. 顺序本身：表里就是有序的 =====
	for d in WorldDB.DOMAINS:
		var did := String(d.get("domain_id", ""))
		var ids := _ids(did)
		_check(ids.size() == 3, "%s 有三位守关者" % WorldDB.get_domain_name(did), _names(ids))
	var first_ids := _ids(D1)
	_check(first_ids == ["boss_huyao", "boss_01", "boss_01_c"],
		"凡界顺序 = 虎妖 → 刀客 → 剑客（用户点名的一例）", _names(first_ids))

	# ===== 2. 空档：只有第一位能进 =====
	_reset(D1)
	_reset(D2)
	_check(CharacterData.is_boss_challengeable(D1, first_ids[0]), "空档：首位可挑战")
	_check(not CharacterData.is_boss_challengeable(D1, first_ids[1]), "空档：第二位锁着")
	_check(not CharacterData.is_boss_challengeable(D1, first_ids[2]), "空档：第三位锁着")
	# ⚠ 点名的是「现在该打的那一位」，不是「上一位」：第三位锁着时也该指虎妖
	var r2 := CharacterData.boss_lock_reason(D1, first_ids[1])
	var r3 := CharacterData.boss_lock_reason(D1, first_ids[2])
	_check(r2.contains("虎妖"), "第二位回执点名虎妖", r2)
	_check(r3.contains("虎妖"), "第三位回执同样点名虎妖（不是刀客）", r3)
	_check(CharacterData.domain_next_boss(D1) == String(first_ids[0]),
		"当前该打的那一位 = 首位", CharacterData.domain_next_boss(D1))

	# ===== 3. 逐位推进（走生产写入 mark_boss_killed） =====
	CharacterData.mark_boss_killed(D1, String(first_ids[0]))
	_check(CharacterData.is_boss_cleared(D1, String(first_ids[0])), "斩首位后进度落表")
	_check(CharacterData.is_boss_challengeable(D1, first_ids[1]), "第二位随之开放")
	_check(not CharacterData.is_boss_challengeable(D1, first_ids[2]), "第三位仍锁")
	_check(CharacterData.boss_lock_reason(D1, first_ids[2]).contains("刀客"),
		"第三位回执改口点刀客", CharacterData.boss_lock_reason(D1, first_ids[2]))
	_check(CharacterData.is_boss_challengeable(D1, first_ids[0]),
		"已斩过的仍可再战（不收回入口）")
	CharacterData.mark_boss_killed(D1, String(first_ids[1]))
	_check(CharacterData.is_boss_challengeable(D1, first_ids[2]), "斩次位后末位开放")
	_check(not CharacterData.is_domain_cleared(D1), "还差一位 ⇒ 本界未通关")
	_check(not CharacterData.is_domain_unlocked(D2), "本界未通关 ⇒ 下一界仍锁")

	# ===== 4. 通关与跨界：下一界从它自己的第一位开始 =====
	CharacterData.mark_boss_killed(D1, String(first_ids[2]))
	_check(CharacterData.is_domain_cleared(D1), "三位全斩 ⇒ 凡界通关")
	_check(CharacterData.is_domain_unlocked(D2), "凡界通关 ⇒ 冲和界开放")
	var d2_ids := _ids(D2)
	_check(CharacterData.is_boss_challengeable(D2, d2_ids[0]), "冲和界只有首位可打")
	_check(not CharacterData.is_boss_challengeable(D2, d2_ids[1]), "冲和界第二位锁着")
	_check(not CharacterData.is_boss_challengeable(D2, d2_ids[2]), "冲和界第三位锁着")
	_check(CharacterData.boss_lock_reason(D2, d2_ids[2]).contains("两仪"),
		"冲和界回执点自己界的首位（不串到凡界）", CharacterData.boss_lock_reason(D2, d2_ids[2]))

	# ===== 5. 界级锁优先于界内顺序 =====
	_reset(D1)
	var reason := CharacterData.boss_lock_reason(D2, d2_ids[0])
	_check(not CharacterData.is_boss_challengeable(D2, d2_ids[0]),
		"整界没开 ⇒ 界内首位也进不去")
	_check(reason == CharacterData.domain_lock_reason(D2) and reason.contains("凡界"),
		"整界锁时沿用界域口径（说「需先通关凡界」而不是「需先击败两仪真人」）", reason)

	# ===== 6. 老档跳着打过：已斩的不收回，门槛落在第一个没斩的 =====
	_reset(D1)
	CharacterData.domain_progress[D1] = {"unlocked": false, "cleared_bosses": [first_ids[2]]}
	_check(CharacterData.is_boss_challengeable(D1, first_ids[2]),
		"老档里跳着斩过的第三位仍然可以再战")
	_check(CharacterData.is_boss_challengeable(D1, first_ids[0]),
		"当前门槛 = 第一个还没斩的（虎妖）")
	_check(not CharacterData.is_boss_challengeable(D1, first_ids[1]),
		"中间的刀客仍锁（虎妖还没斩）")
	_check(CharacterData.domain_next_boss(D1) == String(first_ids[0]),
		"next 指向虎妖而不是刀客", CharacterData.domain_next_boss(D1))

	# ===== 7. 卡面真实按钮 =====
	_reset(D1)
	var board: Control = BOARD.new()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	board.setup(WorldDB.get_domain(D1))
	await get_tree().process_frame
	await get_tree().process_frame
	var btns := _fight_buttons(board)
	_check(btns.size() == 3, "凡界卡面摆出三个挑战按钮", "%d 个" % btns.size())
	var enabled := 0
	var gated: Array[String] = []
	for b in btns:
		var bb := b as Button
		if not bb.disabled:
			enabled += 1
			_check(bb.text == "挑战", "能打的那张按钮写「挑战」", bb.text)
		else:
			gated.append(bb.text)
	_check(enabled == 1, "空档时只有一张卡能点", "%d 张可点" % enabled)
	_check(gated.size() == 2 and gated[0].contains("虎妖") and gated[1].contains("虎妖"),
		"另两张置灰且写明「需先击败 虎妖」", str(gated))
	_check(String(btns[1].get_meta("gate", "")) == "boss_huyao",
		"置灰按钮带 gate 指认门槛（探针不靠文案猜）",
			String(btns[1].get_meta("gate", "")))
	_check(String(board.get("_note").text).contains("按序"),
		"底部规则一句话讲清按序现身", String(board.get("_note").text))
	# 斩掉首位后重画：虎妖那张不再有按钮（已击杀），门槛改指刀客
	CharacterData.mark_boss_killed(D1, String(first_ids[0]))
	board.setup(WorldDB.get_domain(D1))
	await get_tree().process_frame
	await get_tree().process_frame
	btns = _fight_buttons(board)
	_check(btns.size() == 2, "已斩的那位不再摆挑战按钮", "%d 个" % btns.size())
	var still_gated := 0
	for b in btns:
		var bb2 := b as Button
		if bb2.disabled:
			still_gated += 1
			_check(bb2.text.contains("刀客"), "门槛跟着进度走", bb2.text)
	_check(still_gated == 1, "斩首位后：一张可点一张仍锁", "%d 张仍锁" % still_gated)
	board.queue_free()
	await get_tree().process_frame

	# ===== 8. 放行路径：真的进得去战斗 =====
	# ⚠ `change_scene_to_file` 是**同步**的：调用返回时原场景（含探针自己）已经被释放。
	#   所以先把探针搬到 autoload 底下（见 _detach_for_scene_change 的坑）。
	#   放行必须排在拒绝**前面**：守卫一旦被删掉，拒绝那一脚也会切场景 —— 探针此时
	#   已经搬出去了才活得下来，红字才打印得出来（反过来排就只剩一屏静默）。
	_detach_for_scene_change()
	_reset(D1)
	GameState.battle_context = {"source": "__sentinel__"}
	var scene_pre := get_tree().current_scene
	BattleResolver.start_domain(D1, "boss_huyao")
	await get_tree().process_frame
	var ctx: Dictionary = GameState.battle_context
	_check(String(ctx.get("source", "")) == BattleResolver.SOURCE_DOMAIN
			and String(ctx.get("boss_id", "")) == "boss_huyao",
		"放行：battle_context 写的是凡界虎妖", str(ctx))
	_check(get_tree().current_scene != null and get_tree().current_scene != scene_pre,
		"放行：真的切进了战斗场景（入口没被改死）",
			str(get_tree().current_scene.name if get_tree().current_scene != null else null))

	# ===== 9. 拒绝路径：没轮到的进不去（入口这一侧也拦得住）=====
	_reset(D1)
	GameState.battle_context = {"source": "__sentinel__"}
	var scene_now := get_tree().current_scene
	BattleResolver.start_domain(D1, String(first_ids[2]))
	_check(String(GameState.battle_context.get("source", "")) == "__sentinel__",
		"start_domain 对没轮到的守关者什么都不做（context 未被改写）",
			str(GameState.battle_context))
	_check(get_tree().current_scene == scene_now, "没轮到 ⇒ 不切战斗场景")


## 把自己搬到常驻单例底下，好活过换场景。
## ⚠ 搬去 `root` 没用 —— 探针本身就是 current_scene，而 root 正是它的父节点，
##   `change_scene_to_file` 释放的恰好是这一整棵场景树。挂到 GameState（autoload）才活。
func _detach_for_scene_change() -> void:
	var host := get_node_or_null("/root/GameState")
	if host == null:
		return
	var p := get_parent()
	if p == host:
		return
	if p != null:
		p.remove_child(self)
	host.add_child(self)
