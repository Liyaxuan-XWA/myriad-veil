extends Node
## 弹刀喂招 · 真实入口端到端（2026-11-10）
##
## 为什么不满足于 probe_tutorial 里的 `_test_pause`：
##   那里是手工 emit 信号，只能证明「信号接得上」；
##   而用户要的是「真 BOSS 抬手 → 暂停教你 → 按右键 → 真的弹中」。
## 这里走真链路：
##   1. 造一场真的凡界位面战（combat_arena 场景 + GameState.battle_context）
##   2. 等 BOSS 自己抬手（走 BossBase._begin_attack → attack_windup 信号）
##   3. 断言暂停生效、喂招卡弹出
##   4. 用真实输入事件按右键（Input.parse_input_event，走 overlay 的 _input）
##   5. 断言解除暂停、玩家进入弹反窗口、攻击落下那一帧真的被弹中（parry_success 计数 +1）
##
## 用法：godot --headless --path . tools/probe_tut_parry_live.tscn -- --no-save
## ⚠ 教学不改数值：本探针只验链路，不碰 PARRY_WINDOW / 伤害。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

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
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	var backup: Dictionary = CharacterData.tutorial_data.duplicate(true)
	CharacterData.tutorial_data = {"done": {}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}

	# 走到「它抬手就按右键弹刀」这一步（用真事件推进，不是硬塞 active_step）
	Tutorial.start_chapter("c2")
	Tutorial.note("attack_hit", 3)
	_check(Tutorial.is_active_step("c2_parry"), "已推进到弹刀教学步", str(Tutorial.active_step.get("id", "")))

	# 真·凡界位面战（跳入场卡，否则树一开始就是暂停的）
	BattleResolver.skip_next_intro = true
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01",
		"boss_id": "domain_boss_01",
	}
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame

	_check(bool(arena.get("_tut_parry_hooked")), "战斗侧已挂上抬手教学")
	_check(int(arena.get("_tut_parry_left")) == 3, "喂招次数 = 3",
		str(arena.get("_tut_parry_left")))

	# 功法槽锚点：c5_cast / c4_load 靠它聚光，指不到就只会圈整块 HUD
	var ov: Node = Tutorial.get("_overlay") as Node
	var q: Variant = ov.call("_resolve_anchor", "meta:hud.skill.q")
	var qr: Rect2 = Rect2()
	if q != null:
		qr = ov.call("_rect_of", q)
	_check(q != null and qr.size.x > 8.0 and qr.size.x < 200.0,
		"战斗里 Q 功法槽锚点指到格子", str(qr.size))

	# 等 BOSS 自己抬手（最多 15 秒；超时就是链路断了，不要静默通过）
	var paused_at := -1
	for i in 900:
		await get_tree().process_frame
		if Tutorial.is_pause_prompt():
			paused_at = i
			break
	_check(paused_at >= 0, "真 BOSS 抬手触发了暂停喂招", "第 %d 帧" % paused_at)
	if paused_at < 0:
		_cleanup(arena, backup)
		return
	_check(get_tree().paused, "暂停时树确实是暂停的")
	_check(int(arena.get("_tut_parry_left")) == 2,
		"喂招次数已消耗一次", str(arena.get("_tut_parry_left")))

	var player: Node = arena.get("player")
	var before := float(Tutorial.get("_count"))

	# 真右键：走 overlay._input → Tutorial._on_pause_parry → arena 代按
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2(640.0, 360.0)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	for i in 2:
		await get_tree().process_frame

	_check(not Tutorial.is_pause_prompt(), "按右键后喂招提示关闭")
	_check(not get_tree().paused, "解除暂停后树继续跑")
	_check(bool(player.get("is_parrying")), "代按成功：玩家进入弹反")
	_check(float(player.get("parry_timer")) > 0.0, "弹反窗口还开着",
		str(player.get("parry_timer")))

	# 攻击落下那一帧应在窗口内 → 必然弹中（教学强度不动的承诺就靠这条兜着）
	var hp_before := float(player.get("hp"))
	for i in 40:
		await get_tree().process_frame
		if float(Tutorial.get("_count")) > before:
			break
	_check(float(Tutorial.get("_count")) > before,
		"攻击落下被弹中（parry_success 计数 +1）", "%.0f → %.0f" % [before, float(Tutorial.get("_count"))])
	_check(absf(float(player.get("hp")) - hp_before) < 0.01,
		"弹中这一下没掉血", "%.1f → %.1f" % [hp_before, float(player.get("hp"))])

	# ===== 触屏那一轮：手游玩家只有虚拟键，这一轮就是 2026-11-13 用户报的场景 =====
	await _touch_round(arena, player, ov)

	_cleanup(arena, backup)


## 真链路第二遍：BOSS 再抬手 → 暂停 → **手指点虚拟「弹」键** → 必须同样弹中。
## 这一轮以前必红：① 虚拟键在暂停态被 VirtualPad._input 整段跳过；
## ② action 类键只调 Input.action_press，不产生事件，
##    而 overlay 判的是 event.is_action_pressed("parry")。
func _touch_round(arena: Node, player: Node, ov: Node) -> void:
	VirtualPad.set("_has_touchscreen", true)
	VirtualPad.set("enabled", true)
	VirtualPad.call("_apply_enabled")
	VirtualPad.set_context("combat")
	await get_tree().process_frame
	await get_tree().process_frame

	var parry_c := Vector2.ZERO
	var b: Control = (VirtualPad.get("_buttons") as Dictionary).get("c_parry")
	if b != null:
		parry_c = b.position + Vector2(b.radius, b.radius)
	_check(parry_c != Vector2.ZERO, "战斗布局里找到虚拟「弹」键", str(parry_c))

	var paused_at := -1
	for i in range(900):
		await get_tree().process_frame
		if Tutorial.is_pause_prompt():
			paused_at = i
			break
	_check(paused_at >= 0, "触屏轮：BOSS 再次抬手触发暂停喂招", "第 %d 帧" % paused_at)
	if paused_at < 0:
		return
	_check(get_tree().paused, "触屏轮：树确实处于暂停（喂招就是暂停态）")
	var prompt_txt := String(ov.get("_pause_label").text)
	# 「按右键弹开」里也含「弹」字，必须正反两面都判
	_check(prompt_txt.contains("「弹」键") and not prompt_txt.contains("右键"),
		"触屏轮：喂招提示说的是「弹」键而不是右键", prompt_txt)

	var before := float(Tutorial.get("_count"))
	# 真机事件序：合成鼠标 press 先到，触摸 press 后到
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = parry_c
	get_viewport().push_input(mb, true)
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = parry_c
	t.pressed = true
	get_viewport().push_input(t, true)
	for i in range(2):
		await get_tree().process_frame
	# ⚠ 读数要在**抬手之前**：弹中之后 player 的 is_parrying 立刻翻回 false，
	#   等抬手再读就会看到 false（第一版就是这么误报的）
	_check(not Tutorial.is_pause_prompt(), "触屏轮：点虚拟「弹」后喂招提示关闭")
	_check(not get_tree().paused, "触屏轮：树解除暂停继续跑")
	_check(bool(player.get("is_parrying")), "触屏轮：代按成功，玩家进入弹反")
	var mu := InputEventMouseButton.new()
	mu.button_index = MOUSE_BUTTON_LEFT
	mu.pressed = false
	mu.position = parry_c
	get_viewport().push_input(mu, true)
	var tu := InputEventScreenTouch.new()
	tu.index = 0
	tu.position = parry_c
	tu.pressed = false
	get_viewport().push_input(tu, true)
	for i in range(3):
		await get_tree().process_frame

	var hp2 := float(player.get("hp"))
	for i in range(40):
		await get_tree().process_frame
		if float(Tutorial.get("_count")) > before:
			break
	_check(float(Tutorial.get("_count")) > before,
		"触屏轮：这一招真的被弹中（parry_success +1）",
		"%.0f → %.0f" % [before, float(Tutorial.get("_count"))])
	_check(absf(float(player.get("hp")) - hp2) < 0.01,
		"触屏轮：弹中这一下没掉血", "%.1f → %.1f" % [hp2, float(player.get("hp"))])


func _cleanup(arena: Node, backup: Dictionary) -> void:
	VirtualPad.set("enabled", false)
	VirtualPad.set("_has_touchscreen", false)
	VirtualPad.call("_apply_enabled")
	get_tree().paused = false
	if Tutorial.is_pause_prompt():
		Tutorial.resume()
	if is_instance_valid(arena):
		arena.queue_free()
	GameState.battle_context = {}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	CharacterData.tutorial_data = backup
