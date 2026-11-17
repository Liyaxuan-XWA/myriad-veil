extends Node
## 试炼局内回血丹自检（2026-11-08）
##
## 用户定：击败小怪概率掉落回血丹，**拾取即回血**，只在试炼局内可用、无法带出局外。
## 验真实链路：生成掉落 → 玩家走进范围 → 按 F 拾取 → 回血；
## 同时验「没进背包 / 没写图鉴 / 没进 ItemDB 主表 / 主模式与 BOSS 都不产 / 收局后不再生成」。
##
## 用法：godot --headless --path . res://tools/probe_rogue_heal_pill.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

var _passes := 0
var _fails: Array = []
var _dummy_hit := false


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
	print("\n########## 试炼局内回血丹 ##########")
	# ===== 数据口径 =====
	_check(RogueDB.MINION_HEAL_DROP_CHANCE > 0.0 and RogueDB.MINION_HEAL_DROP_CHANCE < 1.0,
		"掉率是合理概率", str(RogueDB.MINION_HEAL_DROP_CHANCE))
	_check(RogueDB.HEAL_PILL_PCT > 0.0, "回血量 > 0", "%.1f%%" % RogueDB.HEAL_PILL_PCT)
	_check(ItemDB.get_consumable(RogueDB.HEAL_PILL_ID).is_empty(),
		"回血丹 id 不在 ItemDB 主表（不是主模式物品）")
	_check(ResourceLoader.exists(RogueDB.HEAL_PILL_ICON), "图标资源存在（可替换口）",
		RogueDB.HEAL_PILL_ICON)
	_check(RogueDB.HEAL_PILL_ICON != "res://assets/ui/icon/pill_huichundan.png",
		"用专属小丹丸贴图（不是主模式 256² 大玉盘）", RogueDB.HEAL_PILL_ICON)
	# 「小巧」参数：局内覆盖表必须明显小于全局装备级掉落表现，且不能污染全局表
	var global_style: Dictionary = ArtDB.get_pickup_beam()
	var pill_style: Dictionary = ArtDB.get_rogue_heal_pickup_style()
	_check(float(pill_style.get("icon_longest", 999.0)) < float(global_style["icon_longest"]) * 0.6,
		"图标尺寸收小（< 全局 62px 的 60%）",
		"%.0f vs %.0f" % [float(pill_style["icon_longest"]), float(global_style["icon_longest"])])
	_check((pill_style["beam_size"] as Vector2).y < (global_style["beam_size"] as Vector2).y * 0.5,
		"光柱高度减半以上",
		"%.0f vs %.0f" % [(pill_style["beam_size"] as Vector2).y, (global_style["beam_size"] as Vector2).y])
	_check(int(pill_style.get("thickness_layers", 1)) == 0, "去掉躺地厚度叠层")
	_check(is_equal_approx(float(global_style["icon_longest"]), 62.0),
		"主模式全局掉落参数没被覆盖污染", str(global_style["icon_longest"]))

	# ===== 真实战斗场景 =====
	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	if rogue == null or player == null:
		_check(false, "试炼战斗场景创建成功")
		RogueRun.restore()
		return

	var inv0 := CharacterData.inventory.size()
	var codex0 := CharacterData.codex_unlocked.size()
	var drops: Array = arena.get("_drops_on_ground")

	# BOSS 掉落在试炼里仍整体屏蔽（唯一产出是结算晶石 + 局内回血丹）
	var boss_drops: Array = arena.call("_spawn_drops", "boss_huyao")
	_check(boss_drops.is_empty(), "试炼里 BOSS 不产主模式掉落")

	# 半血 → 生成一颗（探针直接调生成函数，绕开 18% 随机）
	player.set("hp", 50.0)
	rogue.call("_spawn_heal_pill", player.global_position)
	await get_tree().process_frame
	_check(drops.size() == 1, "地上出现 1 颗回血丹", str(drops.size()))
	if drops.is_empty():
		RogueRun.restore()
		arena.free()
		return
	var pickup: Area2D = drops[0] as Area2D
	# 小丹丸只有 30px，判定圈单独放宽到 56；但绝不能污染主模式共享的 Shape 资源
	var cs: CollisionShape2D = pickup.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var pill_r := 0.0
	if cs != null and cs.shape is CircleShape2D:
		pill_r = (cs.shape as CircleShape2D).radius
	_check(is_equal_approx(pill_r, RogueDB.HEAL_PILL_PICKUP_RADIUS),
		"回血丹判定圈单独放宽（小巧图标也好捡）", "%.1f" % pill_r)
	var plain := (load("res://scenes/items/item_pickup.tscn") as PackedScene).instantiate()
	var plain_cs: CollisionShape2D = plain.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var plain_r := 0.0
	if plain_cs != null and plain_cs.shape is CircleShape2D:
		plain_r = (plain_cs.shape as CircleShape2D).radius
	plain.free()
	_check(is_equal_approx(plain_r, 42.0),
		"主模式掉落物判定圈仍是 42px（共享 SubResource 没被污染）", "%.1f" % plain_r)
	var it: Dictionary = pickup.get("item")
	_check(String(it.get("id", "")) == RogueDB.HEAL_PILL_ID, "掉落物是试炼专属 id",
		String(it.get("id", "")))
	_check(String(it.get("type", "")) == "rogue_consumable",
		"type 不落在图鉴会记录的类别里", String(it.get("type", "")))
	_check(it.has("pickup_style") and it.has("pickup_tint"),
		"掉落物带小巧显示参数 + 专属光柱色")
	_check(String(it.get("icon", "")) == RogueDB.HEAL_PILL_ICON,
		"掉落物用的是专属小丹丸图标")
	var handler: Callable = pickup.get("pickup_handler")
	_check(handler.is_valid(), "拾取挂了局内 handler（不会进永久背包）")

	# ⚠ 必须确认当前真的落在试炼分支：_unhandled_input() 里
	#   `if current_source() == SOURCE_ROGUE: ... return` 会吞掉 F，
	#   这正是「探针全绿但玩家捡不了」的漏测点（2026-11-08 用户报）。
	_check(BattleResolver.current_source() == BattleResolver.SOURCE_ROGUE,
		"当前确实在试炼分支（会触发吞键的那条 return）",
		BattleResolver.current_source())
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(bool(pickup.call("has_player_inside")), "玩家已走进拾取范围")

	# 走真实键盘入口：Input.parse_input_event(KEY_F) → CombatArena._unhandled_input()
	# 🚫 别再直接调 arena._try_pickup_nearest()，那会绕过输入分发、掩盖吞键 bug。
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var ev_up := InputEventKey.new()
	ev_up.physical_keycode = KEY_F
	ev_up.keycode = KEY_F
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	await get_tree().process_frame

	var hp_after := float(player.get("hp"))
	_check(hp_after > 50.0 and hp_after <= 100.0,
		"按 F 拾取即回血", "50 → %.1f" % hp_after)
	_check(absf(hp_after - 65.0) < 0.5,
		"回血量 = 15% 最大血", "%.1f" % hp_after)
	_check(CharacterData.inventory.size() == inv0,
		"没有进永久背包（无法带出局外）", "%d → %d" % [inv0, CharacterData.inventory.size()])
	_check(CharacterData.codex_unlocked.size() == codex0,
		"没有写图鉴", "%d → %d" % [codex0, CharacterData.codex_unlocked.size()])
	_check(drops.is_empty(), "拾取后掉落物已回收", str(drops.size()))

	# 满血时也不会报错（rogue_heal_pct 早退，handler 仍返回 true 让特效播完）
	player.set("hp", 100.0)
	_check(bool(rogue.call("_on_heal_pill_picked", it)), "满血拾取不报错、不卡住掉落物")

	# ===== 模式隔离 =====
	RogueRun.restore()
	var n_before := drops.size()
	rogue.call("_spawn_heal_pill", player.global_position)
	rogue.call("_roll_minion_drop", player)
	_check(drops.size() == n_before, "收局后不再生成回血丹", str(drops.size()))
	_check(not RogueRun.active, "收局后 RogueRun.active = false")

	# ===== 反向锁：F 键前置放行后，主模式的 F 拾取不能被弄坏 =====
	# ⚠ 这次的根因就是「试炼分支 return 吞掉 F」，所以两个分支都要走真实键盘事件验一遍。
	GameState.battle_context = {"source": BattleResolver.SOURCE_ARENA}
	_check(BattleResolver.current_source() != BattleResolver.SOURCE_ROGUE,
		"已切到主模式分支（对照项）", BattleResolver.current_source())
	var dummy := (load("res://scenes/items/item_pickup.tscn") as PackedScene).instantiate() as Area2D
	dummy.item = {"id": "probe_dummy", "name": "探针占位",
		"type": "rogue_consumable", "count": 1}
	dummy.pickup_handler = Callable(self, "_dummy_picked")
	dummy.position = player.global_position
	arena.add_child(dummy)
	drops.append(dummy)
	_dummy_hit = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var f_down := InputEventKey.new()
	f_down.physical_keycode = KEY_F
	f_down.keycode = KEY_F
	f_down.pressed = true
	Input.parse_input_event(f_down)
	await get_tree().process_frame
	var f_up := InputEventKey.new()
	f_up.physical_keycode = KEY_F
	f_up.keycode = KEY_F
	f_up.pressed = false
	Input.parse_input_event(f_up)
	await get_tree().process_frame
	_check(_dummy_hit, "主模式按 F 也能触发拾取（前置放行没弄坏它）")

	arena.free()


## 主模式对照用的假 handler：只置标志，不进背包、不写图鉴
func _dummy_picked(_item: Dictionary) -> bool:
	_dummy_hit = true
	return true
