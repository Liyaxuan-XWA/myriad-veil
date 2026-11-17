extends Node
## 虎妖 · 墙边后撤不出远程自检（2026-11-11 用户报「二阶段近距离（墙边）秒放砂石乱舞」）
##
## 根因：砂石乱舞（P2）/碎岩飞砂（P1）的**前摇就是后撤位移**。
##   玩家把虎妖逼到墙角时 `clamp_burst_dir` 把后撤方向卡成 ZERO（原地后撤），
##   0.32 秒后照放 5 发弹幕 —— 贴脸、零位移，体感就是「秒放」。
## 修复口径：后撤落点仍在近战距离内（拉不开距离）→ 这次后撤作废，改爪击；
##   后撤结束时还贴身也兜底改爪击（既有设计：贴身只放爪击）。
##
## 用例：
##   ① 角落 P2（后撤 ZERO）→ 不出砂石乱舞，改爪击
##   ② 场地中央 P2 → 正常 5 发砂石乱舞
##   ③ 中央起手、后撤途中玩家追到落点 → 兜底改爪击
##   ④ 角落 P1（后撤 ZERO）→ 不出碎岩飞砂，改爪击
##   ⑤ 场地中央 P1 → 正常 1 发碎岩飞砂
## 用法：godot --headless --path . res://tools/probe_huyao_wall_burst.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
## 探针注入的战场边界（与 arena_half_extents 同口径，半宽高）
const HALF := Vector2(600.0, 350.0)
## 边界内缩（BossBase.arena_margin）→ boss 可站到的极限位置
const EDGE := Vector2(544.0, 294.0)

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


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _count_projectiles() -> int:
	return get_tree().get_nodes_in_group("boss_projectile").size()


func _clear_projectiles() -> void:
	for p in get_tree().get_nodes_in_group("boss_projectile"):
		p.queue_free()


## 摆现场：重置状态机与位置，等两帧让 _clamp_to_arena 生效
func _reset(boss: Node2D, player: Node2D, boss_pos: Vector2, player_pos: Vector2) -> void:
	_clear_projectiles()
	boss.set("target", player)
	boss.set("state", 0)            # BossState.IDLE
	boss.set("state_timer", 99.0)   # 别让 IDLE 到点自己选招，干扰后撤触发
	boss.set("velocity", Vector2.ZERO)
	boss.set("_knock_vel", Vector2.ZERO)
	boss.set("_dash_back_ready", false)
	boss.set("dash_back_dir", Vector2.ZERO)
	boss.set("melee_attack_count", 0)
	boss.set("current_hp", float(boss.get("max_hp")))
	boss.global_position = boss_pos
	player.global_position = player_pos
	await _wait_physics(3)


## 起手：置「连击已满」标记 → 由真实状态机（_should_trigger_special）决定走不走后撤
func _arm_dash_back(boss: Node2D) -> void:
	boss.set("_dash_back_ready", true)
	await _wait_physics(3)


func _run() -> void:
	print("\n########## 虎妖 · 墙边后撤不出远程 ##########")
	await get_tree().process_frame
	# ⚠ 不设来源时 current_source() 默认 "arena" → 场景 Boss 被换成训练木桩。
	#   按「秘境凡界虎妖」摆现场：boss_id=boss_huyao 走 boss.tscn（prototype_boss），
	#   这是塔第 1 层 / 秘境凡界同一只。
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN, "boss_id": "boss_huyao"}
	# ⚠ BOSS 入场卡会 get_tree().paused = true（直到点掉卡片）→ boss 的 _physics_process
	#   整段不跑，探针表现是「置了 _dash_back_ready 却毫无反应」（本次踩过）。
	#   走官方的一次性跳卡标志；它是读取即复位的，所以每次建 arena 前都要重新置位。
	BattleResolver.skip_next_intro = true
	var arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.get("player")
	var boss: Node2D = arena.get_node_or_null("Boss")
	if player == null or boss == null or not boss.has_method("_start_dash_back"):
		_check(false, "战斗场景创建失败（或 Boss 不是虎妖）",
			"player=%s boss=%s script=%s" % [str(player), str(boss),
				"" if boss == null else String(boss.get_script().resource_path)])
		return
	player.set("invincible_timer", 99999.0)
	player.set("is_teleporting", false)
	boss.set("target", player)
	boss.call("set_arena_bounds", HALF, Vector2.ZERO)
	await _wait_ms(100)

	# ===== ① 角落 P2：后撤方向被两面墙卡成 ZERO =====
	boss.set("phase", 2)
	await _reset(boss, player, EDGE, EDGE - Vector2(80.0, 80.0))
	await _arm_dash_back(boss)
	# 起手就已分流：走后撤 = DASH_BACK(100)，被墙卡死改招 = WINDUP(2)
	_check(int(boss.get("state")) == 2,
		"① 角落 P2：后撤被墙卡死 → 起手直接改爪击前摇（不走后撤）",
		"state=%d" % int(boss.get("state")))
	await _wait_ms(500)
	_check(int(boss.get("current_attack_kind")) == 0,
		"① 角落 P2：改爪击（current_attack_kind=PHYSICAL_MELEE）",
		"kind=%d" % int(boss.get("current_attack_kind")))
	_check(_count_projectiles() == 0, "① 角落 P2：不出砂石乱舞（0 发弹幕）",
		str(_count_projectiles()))

	# ===== ② 中央 P2：正常后撤 + 5 发砂石乱舞 =====
	boss.set("phase", 2)
	await _reset(boss, player, Vector2.ZERO, Vector2(0.0, -200.0))
	await _arm_dash_back(boss)
	_check(int(boss.get("state")) == 100, "② 中央 P2：确实进入后撤（对照组有效）",
		"state=%d" % int(boss.get("state")))
	await _wait_ms(500)
	_check(_count_projectiles() == 5, "② 中央 P2：后撤结束照放 5 发砂石乱舞",
		str(_count_projectiles()))

	# ===== ③ 中央后撤途中玩家追到落点：结束仍贴身 → 兜底爪击 =====
	boss.set("phase", 2)
	await _reset(boss, player, Vector2.ZERO, Vector2(0.0, -200.0))
	await _arm_dash_back(boss)
	# 后撤方向 (0,1)、落点 (0,288)：0.12s 后把玩家瞬移到落点旁，模拟「追着打」
	await _wait_ms(120)
	player.global_position = Vector2(0.0, 328.0)
	await _wait_ms(400)
	_check(_count_projectiles() == 0, "③ 后撤完仍贴身：兜底不出砂石乱舞",
		str(_count_projectiles()))
	_check(int(boss.get("current_attack_kind")) == 0, "③ 后撤完仍贴身：改爪击",
		"kind=%d" % int(boss.get("current_attack_kind")))

	# ===== ④ 角落 P1：同口径，不出碎岩飞砂 =====
	# ⚠ P1 后撤 0.18s 结束走 _begin_attack(PROJECTILE) → 还要等前摇 0.8s 才发射，
	#   只等 400ms 会看到「0 发弹幕」的假绿（本次踩过）→ 等 1100ms。
	boss.set("phase", 1)
	await _reset(boss, player, EDGE, EDGE - Vector2(80.0, 80.0))
	await _arm_dash_back(boss)
	_check(int(boss.get("state")) == 2, "④ 角落 P1：起手直接改爪击前摇",
		"state=%d" % int(boss.get("state")))
	await _wait_ms(1100)
	_check(_count_projectiles() == 0, "④ 角落 P1：不出碎岩飞砂", str(_count_projectiles()))
	_check(int(boss.get("current_attack_kind")) == 0, "④ 角落 P1：改爪击",
		"kind=%d" % int(boss.get("current_attack_kind")))

	# ===== ⑤ 中央 P1：正常后撤 + 1 发碎岩飞砂 =====
	boss.set("phase", 1)
	await _reset(boss, player, Vector2.ZERO, Vector2(0.0, -200.0))
	await _arm_dash_back(boss)
	await _wait_ms(1100)
	_check(_count_projectiles() == 1, "⑤ 中央 P1：后撤结束照放 1 发碎岩飞砂",
		str(_count_projectiles()))

	arena.queue_free()
	await get_tree().process_frame
