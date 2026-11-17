extends Node
## 首杀虎妖成长链 · 端到端自检（2026-11-10）
##
## 用户要求：首杀秘境 BOSS 掉锻造晶石；第一次击败虎妖 → 教捡晶石 → 回城锻造
## （必成强化）→ 拖装 → 万界塔虎妖层 → 感悟收功法 → 功法库装配。
## 本探针走**真实入口**：
##   · 掉落走 combat_arena._spawn_drops（BOSS 死亡结算的同一函数）
##   · 拾取走 Input.parse_input_event(KEY_F) → _unhandled_input（🚫 不直调拾取）
##   · 教学推进走 Tutorial 事件与 0.25s cond 轮询，不手工 _finish_step
##   · 强化走 CharacterData.enhance_item（必成旗标由步骤机按 force_success 置位）
##
##   ① 秘境掉落：首杀 9 块晶石 / 重复 3 块；每颗带 drop.item 教学锚点
##   ② F 键拾取 → 背包 +1 → item_picked 事件推进教学
##   ③ cond 兜底：事件发早了被步骤机丢掉时，步一激活轮询立刻补完
##      （提前回城 / 提前拿锤 / 提前捡晶石三种乱序）
##   ④ 教学必成：c5_enhance 激活期间真实 enhance_item 全成功、离开即复位
##   ⑤ 接线守卫：first_kill 上下文 / after_huyao 触发 / 教学镜像数据源
##
## 用法：godot --headless --path . tools/probe_tutorial_huyao.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 首杀虎妖成长链探针 ##########")
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("PROBE TIMEOUT")
		get_tree().quit(2))
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	var saved_done: Dictionary = CharacterData.tutorial_data.duplicate(true)
	var saved_boss: Dictionary = CharacterData.boss_progress.duplicate(true)
	var saved_bag := CharacterData.count_material(CRYSTAL)

	# ===== ① 秘境掉落（真实 _spawn_drops，与 BOSS 死亡结算同一函数） =====
	GameState.battle_context = {"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01", "boss_id": "boss_huyao", "first_kill": true}
	var arena: Node = await _make_arena()
	arena.call("_spawn_drops", "boss_huyao")
	var crystals1 := _count_ground_crystals(arena)
	_check(crystals1 == 9, "秘境首杀掉 9 块锻造晶石", str(crystals1))
	var all_meta := true
	for raw in (arena.get("_drops_on_ground") as Array):
		if not (raw is Node) or String((raw as Node).get_meta("tut", "")) != "drop.item":
			all_meta = false
			break
	_check(all_meta, "每颗掉落物都带 drop.item 教学锚点")
	arena.free()
	await get_tree().process_frame
	await get_tree().process_frame

	GameState.battle_context = {"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01", "boss_id": "boss_huyao", "first_kill": false}
	var arena2: Node = await _make_arena()
	arena2.call("_spawn_drops", "boss_huyao")
	_check(_count_ground_crystals(arena2) == 3,
		"秘境重复击杀掉 3 块（与塔『之后』档对齐）", str(_count_ground_crystals(arena2)))
	arena2.free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ===== ② 真实教学链 + F 键拾取 =====
	GameState.battle_context = {"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_01", "boss_id": "boss_huyao", "first_kill": true}
	var arena3: Node = await _make_arena()
	arena3.call("_spawn_drops", "boss_huyao")
	var ground3: Array = arena3.get("_drops_on_ground")
	var crystal_pickup: Area2D = _first_crystal(ground3)
	_check(crystal_pickup != null, "地上有晶石掉落物")
	if crystal_pickup == null:
		_finish_cleanup(arena3, saved_done, saved_boss)
		return
	var player: Node2D = arena3.get("player")
	# ⚠ 登场演出会整段吞输入、还会用 tween 把玩家拖回入场位 ——
	#   传送与按键必须等 is_teleporting 结束（项目已知坑，heal_pill 探针同款教训）
	var t0 := Time.get_ticks_msec()
	while bool(player.get("is_teleporting")) and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	player.global_position = crystal_pickup.global_position
	# ⚠ 传送后至少等 8 个物理帧：CharacterBody2D 的 transform 同步到物理服务端
	#   需要 2 帧以上，只等 2 帧时 get_overlapping_bodies() 还是空（实测踩过）
	for _i in 8:
		await get_tree().physics_frame

	# 教学：走真实触发链开章（虎妖首杀标记 + 请求 → c5 第一步就是捡晶石）
	CharacterData.tutorial_data = {"done": {}}
	CharacterData.boss_progress = {"boss_huyao": {"killed": true, "first_kill": true}}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	CharacterData.force_enhance_success = false
	Tutorial.request_chapter_by_trigger("after_huyao")
	_check(Tutorial.active_chapter == "c5", "虎妖首杀 → 开成长链", Tutorial.active_chapter)
	_check(String(Tutorial.active_step.get("id", "")) == "c5_crystal",
		"第一步教捡晶石", String(Tutorial.active_step.get("id", "")))

	# ===== ③a 乱序回城：事件发太早被丢，cond in_realm 兜底 =====
	Tutorial.note("returned_realm")          # 玩家还没捡晶石就点了返回 → 应被丢
	_check(String(Tutorial.active_step.get("id", "")) == "c5_crystal",
		"乱序的 returned_realm 不会推走『捡晶石』步",
		String(Tutorial.active_step.get("id", "")))

	# 走真实键盘入口：Input.parse_input_event(KEY_F) → CombatArena._unhandled_input()
	# ⚠ BOSS 还活着会攻击/击退玩家，可能把人推出判定圈 → 「重传送→确认重叠→按F→验包」
	#   循环重试，直到真的捡到（实测只等一次会随机失败，第 2/4/10 次跑里翻过车）
	var bag0 := CharacterData.count_material(CRYSTAL)
	var ground0 := _count_ground_crystals(arena3)
	var picked := false
	for _attempt in 4:
		player.global_position = crystal_pickup.global_position
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 3000:
			await get_tree().physics_frame
			if bool(crystal_pickup.call("has_player_inside")):
				break
		if not bool(crystal_pickup.call("has_player_inside")):
			continue
		await _press_f()
		if CharacterData.count_material(CRYSTAL) > bag0:
			picked = true
			break
	var bag1 := CharacterData.count_material(CRYSTAL)
	_check(picked, "按 F 拾取晶石 → 背包 +1", "%d → %d" % [bag0, bag1])
	# ⚠ 玩家判定圈（r=42）能同时罩住相邻晶石（9 颗最小间距 42px），
	#   F 捡走的是「最近的一颗」——断言数总量而不是钉死某一颗引用
	_check(_count_ground_crystals(arena3) == ground0 - 1,
		"拾取后地上晶石少了一颗", "%d → %d" % [ground0, _count_ground_crystals(arena3)])
	_check(String(Tutorial.active_step.get("id", "")) == "c5_return",
		"item_picked 事件把教学推到『返回』步", String(Tutorial.active_step.get("id", "")))

	# 回城动作把战斗来源清空（真实行为）→ 轮询把刚才被丢的『返回』步补完
	GameState.battle_context = {}
	await _wait_poll()
	_check(_active_after_poll() == "c5_forge",
		"cond in_realm 补完『返回』步（事件早发被丢也能走通）",
		_active_after_poll())

	# ===== ③b 乱序拿锤 =====
	Tutorial.note("panel_opened:forge_panel")
	_check(String(Tutorial.active_step.get("id", "")) == "c5_place",
		"开锻造 → 教上砧", String(Tutorial.active_step.get("id", "")))
	GameState.forge_hammer_held = true       # 玩家抢先把锤子拿了
	Tutorial.note("forge_hammer")            # 发在『上砧』活着时 → 应被丢
	_check(String(Tutorial.active_step.get("id", "")) == "c5_place",
		"乱序的 forge_hammer 不会跳过上砧步")
	Tutorial.note("forge_place")             # 正常上砧
	_check(String(Tutorial.active_step.get("id", "")) == "c5_hammer",
		"上砧 → 到拿锤步", String(Tutorial.active_step.get("id", "")))
	await _wait_poll()
	_check(_active_after_poll() == "c5_enhance",
		"cond forge_hammer_held 立刻补完拿锤步（锤子已在手）", _active_after_poll())

	# ===== ④ 教学必成（真实 enhance_item） =====
	_check(bool(CharacterData.force_enhance_success),
		"c5_enhance 激活 → 必成旗标打开")
	CharacterData.ensure_starting_equipment()
	var sword: Dictionary = CharacterData.equipment_slots.get("weapon", {})
	_check(not sword.is_empty() and String(sword.get("id", "")) == "eq_tiejian",
		"身上武器是铁剑", String(sword.get("id", "")))
	for _i in 20:
		CharacterData.add_item(
			(ItemDB.make_material_drop(CRYSTAL) as Dictionary).get("item", {}))
	var all_ok := true
	var enh0 := int(sword.get("enhancement_level", 0))
	for i in 8:
		var r: Dictionary = CharacterData.enhance_item(sword)
		if String(r.get("result", "")) != ItemDB.ENHANCE_RESULT_SUCCESS \
				or int(sword.get("enhancement_level", 0)) != enh0 + i + 1:
			all_ok = false
			print("    强化第 %d 次结果：%s 等级 %d" % [i + 1,
				r.get("result", ""), int(sword.get("enhancement_level", 0))])
			break
	_check(all_ok, "教学期间真实强化 8 次全部成功且逐级 +1",
		"%d → %d" % [enh0, int(sword.get("enhancement_level", enh0))])
	_check(int(sword.get("enhance_fail_count", 0)) == 0, "必成不累计失败磨损")
	Tutorial.skip_step()
	_check(not bool(CharacterData.force_enhance_success),
		"离开强化步旗标立刻复位")
	var r2: Dictionary = CharacterData.enhance_item(sword)
	_check(String(r2.get("result", "")) == ItemDB.ENHANCE_RESULT_SUCCESS
			or String(r2.get("result", "")) == ItemDB.ENHANCE_RESULT_FAIL
			or String(r2.get("result", "")) == ItemDB.ENHANCE_RESULT_GREAT,
		"复位后恢复真随机（三种结果都合法）", String(r2.get("result", "")))

	# ===== ③c 感悟后的捡晶石同样有 has_crystal 兜底 =====
	# 回到「战斗中」状态（in_realm 必须 false，c5_back 才不会跟着轮询跑掉）
	GameState.battle_context = {"source": BattleResolver.SOURCE_TOWER, "floor": 1}
	_advance_to("c5_loot")
	_check(String(Tutorial.active_step.get("id", "")) == "c5_loot",
		"推进到感悟后的捡晶石步", String(Tutorial.active_step.get("id", "")))
	await _wait_poll()
	_check(_active_after_poll() == "c5_back",
		"cond has_crystal 兜底：背包已有晶石 → 步激活即补完", _active_after_poll())

	# ===== ⑤ 接线守卫 =====
	var br_src := FileAccess.get_file_as_string("scripts/systems/battle_resolver.gd")
	_check(br_src.contains('ctx["first_kill"] = first'),
		"结算层把首杀标记传给掉落层")
	_check(br_src.contains('request_chapter_by_trigger("after_huyao")'),
		"首杀虎妖当场开教学链（不等回城）")
	var arena_src := FileAccess.get_file_as_string("scripts/combat/combat_arena.gd")
	_check(arena_src.contains("DOMAIN_FIRST_KILL_CRYSTALS")
			and arena_src.contains("SOURCE_DOMAIN"),
		"秘境晶石按战斗来源分支（塔投影不受影响）")
	var forge_src := FileAccess.get_file_as_string("scripts/ui/panels/forge_panel.gd")
	_check(forge_src.contains("GameState.forge_hammer_held")
			and forge_src.contains("GameState.forge_anvil_id"),
		"锻造面板维护教学镜像（cond 兜底的数据源）")

	_finish_cleanup(arena3, saved_done, saved_boss)


## 真实键盘入口按一次 F（探针铁律：不直调拾取函数）
func _press_f() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var ev_up := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.keycode = KEY_F
	ev.pressed = false
	Input.parse_input_event(ev_up)
	await get_tree().process_frame


## 等 cond 轮询（0.25 秒间隔）至少跑两轮
func _wait_poll() -> void:
	await get_tree().create_timer(0.6).timeout
	await get_tree().process_frame


func _active_after_poll() -> String:
	return String(Tutorial.active_step.get("id", ""))


## 用「跳过此步」真实 API 把链推进到指定步骤
func _advance_to(step_id: String) -> void:
	var guard := 0
	while String(Tutorial.active_step.get("id", "")) != step_id \
			and Tutorial.active_chapter == "c5" and guard < 40:
		Tutorial.skip_step()
		guard += 1


func _count_ground_crystals(arena: Node) -> int:
	var n := 0
	for raw in (arena.get("_drops_on_ground") as Array):
		if raw is Node:
			var it = (raw as Node).get("item")
			if it is Dictionary and String((it as Dictionary).get("id", "")) == CRYSTAL:
				n += 1
	return n


func _first_crystal(ground: Array) -> Area2D:
	for raw in ground:
		if raw is Area2D:
			var it = (raw as Area2D).get("item")
			if it is Dictionary and String((it as Dictionary).get("id", "")) == CRYSTAL:
				return raw as Area2D
	return null


func _make_arena() -> Node:
	# ⚠ skip_next_intro 是一次性标记（读取即复位）：每个 arena 都要重新置位，
	#   否则入场卡开着 → _unhandled_input 里所有战斗键（含 F）全被吞
	BattleResolver.skip_next_intro = true
	var arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	return arena


func _finish_cleanup(arena3: Node, saved_done: Dictionary, saved_boss: Dictionary) -> void:
	CharacterData.tutorial_data = saved_done
	CharacterData.boss_progress = saved_boss
	CharacterData.force_enhance_success = false
	GameState.forge_hammer_held = false
	GameState.forge_anvil_id = ""
	BattleResolver.clear()
	GameState.battle_context = {}
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	if arena3 != null and is_instance_valid(arena3):
		arena3.free()
	await get_tree().process_frame
