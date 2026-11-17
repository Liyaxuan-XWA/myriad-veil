extends Node2D
## 试炼行囊 / 玉简 自检（2026-11-12 用户报两个 bug）
##   ① 面板会被内容撑变形、玉简页滚不动
##   ② 精力上限 / 额外回精力 的玉简没生效
##
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_rogue_gear.tscn -- --no-save
##
## 判据口径：
##   · 「变形」用**数值**验：`_root.size` 必须等于 `panel_size()`（设计值 820×570）；
##   · 「滚不动」用滚动条自己说：v_scroll_bar 的 max 必须大于 page；
##   · 「没生效」走**真实三选一回调**（rogue_arena._on_picked）→ 玩家运行时字段 → 灵环格数，
##     不直接调 player.refresh_runtime_attributes（那样接线断了也照样绿）。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const PANEL_SCENE := "res://scripts/ui/panels/rogue_gear_panel.gd"
const CARD := "g_stamina"

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
	print("\n########## 试炼行囊 · 面板与精力玉简 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# ===== 1. 数据层：蓄劲真的加到属性上 =====
	RogueRun.start_run("sword")
	var base := CharacterData.max_stamina()
	RogueRun.add_buff(CARD)
	_check(CharacterData.max_stamina() == base + 1, "蓄劲 ×1 ⇒ 精力上限 +1",
			"%d → %d" % [base, CharacterData.max_stamina()])
	RogueRun.add_buff(CARD)
	_check(CharacterData.max_stamina() == base + 2, "蓄劲 ×2 ⇒ 精力上限 +2",
			"%d → %d" % [base, CharacterData.max_stamina()])
	var parry_card := ""
	for raw in RogueDB.GENERIC_BUFFS:
		if (raw as Dictionary).get("stat", {}).has("stamina_on_parry"):
			parry_card = String((raw as Dictionary).get("id", ""))
	RogueRun.add_buff(parry_card)
	_check(parry_card != "" and RogueRun.stat("stamina_on_parry") >= 1.0,
			"「弹反成功额外回精力」也进了本局结算表",
			"%s = %.0f" % [parry_card, RogueRun.stat("stamina_on_parry")])

	# ===== 2. 玉简页：面板不变形 + 真的能滚 =====
	for raw in RogueDB.GENERIC_BUFFS:
		if RogueRun.buffs.size() >= 24:
			break
		RogueRun.add_buff(String((raw as Dictionary).get("id", "")))
	var panel = (load(PANEL_SCENE) as GDScript).new()
	get_tree().root.add_child.call_deferred(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open()
	for i in 5:
		await get_tree().process_frame
	var root_ctl: Control = panel.get("_root")
	var want: Vector2 = panel.call("panel_size")
	_check(root_ctl.size.is_equal_approx(want), "面板没有被内容撑变形",
			"%s vs 设计 %s" % [str(root_ctl.size), str(want)])
	panel.call("_switch_tab", 1)
	for i in 4:
		await get_tree().process_frame
	var deck: Control = panel.get("_page_deck")
	var scroll: ScrollContainer = null
	for n in deck.find_children("*", "ScrollContainer", true, false):
		scroll = n as ScrollContainer
	_check(scroll != null, "玉简页有滚动容器")
	if scroll != null:
		var vb := scroll.get_v_scroll_bar()
		_check(vb.max_value > vb.page + 1.0, "玉简多到 24 张时能上下滚",
				"max=%.0f page=%.0f" % [vb.max_value, vb.page])
		_check(scroll.size.y <= want.y, "滚动容器高度不超过面板（否则等于没滚）",
				"%.0f vs %.0f" % [scroll.size.y, want.y])
	# ⚠ close() 自己会把面板释放掉，别再 queue_free（会炸在已释放实例上）
	panel.close()
	await get_tree().process_frame
	await get_tree().process_frame
	RogueRun.finish_run(true)

	# ===== 3. 实机链：三选一拿蓄劲 → 玩家与灵环立刻跟上 =====
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	RogueRun.start_run("sword")
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var p: Node2D = arena.get("player")
	var rogue: Node = arena.get("_rogue")
	_check(p != null and rogue != null, "试炼场就绪（player + RogueArena）")
	if p == null or rogue == null:
		return
	var before := int(p.get("max_stamina"))
	var ring = p.get("_ring")
	_check(ring != null and int(ring.get("_stamina_max")) == before, "现场：灵环格数 = 玩家上限",
			"%d" % before)
	rogue.call("_on_picked", CARD)
	await get_tree().create_timer(1.6).timeout
	_check(int(p.get("max_stamina")) == before + 1, "拿到蓄劲后玩家上限**立刻** +1（不用等下一局）",
			"%d → %d" % [before, int(p.get("max_stamina"))])
	_check(int(ring.get("_stamina_max")) == before + 1, "灵环也多出一格（肉眼能看到）",
			"%d" % int(ring.get("_stamina_max")))
	# 额外回精力：此刻精力回满后再回也压在上限内（不越界）
	p.call("_recover_stamina", 99)
	_check(int(p.get("stamina")) == int(p.get("max_stamina")), "回精力不会越上限",
			"%d/%d" % [int(p.get("stamina")), int(p.get("max_stamina"))])
	arena.queue_free()
	await get_tree().process_frame
	RogueRun.finish_run(true)
	print("")
