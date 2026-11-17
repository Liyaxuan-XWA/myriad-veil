extends Node
## 试炼之路 · 关卡推进链自检（2026-11-08）
## 目的：发现「一直在同一层循环三波」这类推进断链 —— 清波 → 三选一 → 下一小关 →
##       第 4 小关 BOSS → 击杀 → 三选一 → 下一层。
## 做法：起真实 combat_arena（SOURCE_ROGUE），把每波怪秒杀，自动选第一张卡，
##       一路打印 floor/stage/wave/phase，看链条在哪一步断掉。
## 用法：godot --headless --path . res://tools/probe_rogue_progress.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const MAX_STEPS := 90

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
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


const PHASE_NAMES: Array[String] = ["IDLE", "FIGHT", "BREAK", "PICK", "BOSS", "OVER"]


func _phase_name(p: int) -> String:
	if p < 0 or p >= PHASE_NAMES.size():
		return "?%d" % p
	return PHASE_NAMES[p]


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _snap(rogue: Node) -> String:
	return "第 %d 层 · 小关 %d · 第 %d 波 · %s" % [
		RogueRun.floor_no, RogueRun.stage_no, RogueRun.wave_no,
		_phase_name(int(rogue.get("_phase")))]


## 场上怪 + BOSS 全秒杀（BOSS 要打多下才进死亡流程，循环几次）
func _kill_all(rogue: Node, arena: Node, player: Node2D) -> void:
	var alive: Array = rogue.get("_alive")
	for e in alive:
		if is_instance_valid(e):
			(e as Node).call("take_damage", 9999999.0, player, "true", "none")
	var boss: Node = arena.get("boss")
	if boss != null and is_instance_valid(boss) and boss.get("visible") == true:
		for i in 6:
			if not is_instance_valid(boss):
				break
			if int(boss.get("state")) == BossBase.BossState.DEAD:
				break
			boss.call("take_damage", 9999999.0, player, "true", "none")
			await get_tree().process_frame


func _maybe_pick(rogue: Node) -> bool:
	var panel: Node = rogue.get("_pick_panel")
	if panel == null or not is_instance_valid(panel):
		return false
	if panel.get("_visible") != true:
		return false
	var choices: Array = panel.get("choices")
	if choices.is_empty():
		return false
	var bid := String((choices[0] as Dictionary).get("id", ""))
	panel.emit_signal("picked", bid)
	panel.call("close")
	return true


func _run() -> void:
	print("\n########## 试炼之路 · 关卡推进链 ##########")
	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	if rogue == null or player == null:
		_check(false, "战斗场景 / 肉鸽调度器创建成功")
		return
	_check(true, "开局：第 1 层 · 小关 1 · 第 1 波",
		_snap(rogue))

	# ===== 血条配色：试炼里全是敌人，不许按大世界 kind 分色 =====
	var bars: Array = []
	for e in (rogue.get("_alive") as Array):
		if not is_instance_valid(e):
			continue
		var bar: ColorRect = (e as Node).get_node_or_null("HPBarBG/HPBar") as ColorRect
		if bar != null:
			bars.append(bar.color)
	_check(not bars.is_empty(), "首波小怪都挂了头顶血条", str(bars.size()))
	var all_red := true
	for c in bars:
		if not (c as Color).is_equal_approx(RogueDB.MINION_HP_COLOR):
			all_red = false
	_check(all_red, "首波小怪血条统一敌方红", str(bars))
	# 单造一只「修士 AI」小怪：它就是以前顶着蓝血条的那只（山魈射手借这套 AI）
	var tint_probe := (load("res://scenes/world/world_enemy.tscn") as PackedScene).instantiate()
	tint_probe.call("configure", {
		"max_hp": 100.0, "attack_power": 1.0,
		"hp_color": RogueDB.MINION_HP_COLOR,
		"name_color": RogueDB.MINION_NAME_COLOR,
	}, WorldEnemy.KIND_CULTIVATOR, "配色自检")
	var hp_c: Color = tint_probe.call("_hp_color")
	var nm_c: Color = tint_probe.call("_name_color")
	_check(hp_c.is_equal_approx(RogueDB.MINION_HP_COLOR),
		"修士 AI 小怪血条也被覆盖成敌方红", str(hp_c))
	_check(nm_c.is_equal_approx(RogueDB.MINION_NAME_COLOR),
		"修士 AI 小怪名字也走试炼配色", str(nm_c))
	tint_probe.free()

	var seen_floors: Array = []
	var seen_stages: Array = []
	var stuck_at := ""
	for step in MAX_STEPS:
		await get_tree().process_frame
		await get_tree().process_frame
		var phase := int(rogue.get("_phase"))
		# 三选一挂着就选掉
		if phase == 3:
			var picked := _maybe_pick(rogue)
			await _wait(1.5)
			print("[%02d] 三选一 → %s（选了 %s）" % [step, _snap(rogue), str(picked)])
			continue
		# 等 BREAK 走完
		if phase == 2:
			await _wait(2.2)
			print("[%02d] 喘息结束 → %s" % [step, _snap(rogue)])
			continue
		if phase == 4:
			var b: Node = arena.get("boss")
			var bst := "无效" if (b == null or not is_instance_valid(b)) else str(int(b.get("state")))
			print("    BOSS 阶段：boss_state=%s visible=%s" % [bst, "?" if (b == null or not is_instance_valid(b)) else str(b.get("visible"))])
			if b != null and is_instance_valid(b) and int(b.get("state")) == BossBase.BossState.DEAD:
				print("    ⚠ BOSS 已死但阶段仍是 BOSS —— 卡死")
				break
		if int(RogueRun.floor_no) not in seen_floors:
			seen_floors.append(int(RogueRun.floor_no))
		if int(RogueRun.stage_no) not in seen_stages:
			seen_stages.append(int(RogueRun.stage_no))
		print("[%02d] %s" % [step, _snap(rogue)])
		if RogueRun.floor_no > 3:
			break
		if step > 26:
			print("    （第 4 小关起：_alive=%d boss_visible=%s）" % [(rogue.get("_alive") as Array).size(), str((arena.get("boss") as Node).get("visible"))])
		await _kill_all(rogue, arena, player)
		# ⚠ BOSS 死后流程还压着一段「遗物落地等玩家按 F」的窗口（`BOSS_DROP_AUTOPICK`
		#   10 秒后自动收），收完才推进阶段。这里不等这段就会被下面的「BOSS 已死但
		#   阶段仍是 BOSS」判成卡关 —— 那是误判，不是真卡。
		#   为了不让探针多花 30 秒，把倒计时直接拨到 0（**只快进等待、不跳过逻辑**：
		#   下一帧仍由 _process 走真实的 _collect_boss_drops_auto()）。
		# （Phase.BOSS = 4；探针里不引 RogueArena 常量，跟随本文件既有写法用数字）
		if int(rogue.get("_phase")) == 4:
			var drop_t0 := Time.get_ticks_msec()
			while int(rogue.get("_phase")) == 4 \
					and Time.get_ticks_msec() - drop_t0 < 4000:
				rogue.set("_boss_drop_wait", 0.0)
				await get_tree().process_frame
		await _wait(0.3)

	# ===== 断言 =====
	_check(seen_stages.has(2) and seen_stages.has(3), "三小关都会走到",
		str(seen_stages))
	_check(seen_stages.has(RogueDB.STAGES_PER_FLOOR), "第 4 小关是 BOSS 关",
		str(seen_stages))
	_check(seen_floors.has(2) and seen_floors.has(3), "击杀 BOSS 后逐层推进（2、3 层）", str(seen_floors))
	_check(RogueRun.floor_no >= 3, "最终层数 ≥ 3", "第 %d 层" % RogueRun.floor_no)

	RogueRun.restore()
