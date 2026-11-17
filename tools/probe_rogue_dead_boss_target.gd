extends Node
## 试炼之路 BOSS 尸体不该被索敌（2026-11-08 用户报「完美弹刀会索敌死的 boss」）
##
## 复现前提：试炼里 BOSS 死后尸体不销毁（只是 visible=false / process 关掉），
## 仍然留在 "boss" 组、state=DEAD。玩家侧按组取敌的循环若不过滤死亡状态，
## 弹反追击 / 软锁定就会把玩家拉向那具隐形尸体。
## 用法：godot --headless --path . res://tools/probe_rogue_dead_boss_target.tscn -- --no-save

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
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	print("\n########## 试炼 BOSS 尸体索敌 ##########")
	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	var boss: Node2D = arena.get("boss")
	if rogue == null or player == null or boss == null:
		_check(false, "试炼战斗场景创建成功")
		RogueRun.restore()
		return

	# 冻结刷怪机、清掉第一波小怪，场上只留 BOSS
	rogue.set_process(false)
	for raw in (rogue.get("_alive") as Array):
		if is_instance_valid(raw):
			(raw as Node).free()
	(rogue.get("_alive") as Array).clear()

	# 先唤醒：休眠期的 BOSS 会被移出 "boss" 组（2026-11-09 修「透明 BOSS 能打到」），
	# 而本探针要复现的是「BOSS 关打完、尸体留在场上」那一刻 —— 那时它是在组里的。
	# ⚠ 不唤醒就取不到本题的前提，断言会假红。
	rogue.call("_set_boss_dormant", false)
	await get_tree().process_frame

	# 把 BOSS 变成尸体：DEAD + 靠近玩家 + 不销毁（与真实流程一致）
	boss.set("state", BossBase.BossState.DEAD)
	boss.global_position = Vector2(80.0, 0.0)
	player.global_position = Vector2.ZERO
	await get_tree().process_frame

	_check(bool(boss.call("is_dead")), "前提：BOSS 已是尸体")
	_check(boss.is_in_group("boss"), "前提：尸体仍留在 boss 组（试炼不销毁尸体）")
	_check(not BossBase.hostile_units(player).has(boss),
		"统一取敌入口本来就过滤死单位（对照项）")

	var near: Node = player.call("_nearest_boss", 9999.0)
	_check(near != boss, "软锁定不会选中死 BOSS",
		"null" if near == null else String(near.name))
	var arr: Array = player.call("_array_enemy_units")
	_check(not arr.has(boss), "阵旗取敌不含死 BOSS", str(arr.size()))
	var tr: Array = player.call("_treasure_enemy_units", 9999.0)
	_check(not tr.has(boss), "法宝取敌不含死 BOSS", str(tr.size()))

	# ★ 核心复现：只有尸体在场时，完美弹刀的追击位移不该启动
	player.call("apply_buff", "parry_followup", 1.2)
	player.set("parry_followup_can_dash", true)
	var dashed_to_corpse := bool(player.call("_parry_followup_dash"))
	_check(not dashed_to_corpse,
		"只有尸体在场时弹反追击不启动（不会冲向死 BOSS）",
		"dash=%s" % str(dashed_to_corpse))

	# 放一个活目标：应锁活目标，且弹反追击要照常工作（没误伤正常功能）
	var live := Node2D.new()
	live.name = "ProbeLiveTarget"
	live.position = Vector2(300.0, 0.0)
	add_child(live)
	live.add_to_group("boss")
	await get_tree().process_frame
	var near2: Node = player.call("_nearest_boss", 9999.0)
	_check(near2 == live, "尸体 + 活目标同场：软锁定选活目标",
		"null" if near2 == null else String(near2.name))
	var arr2: Array = player.call("_array_enemy_units")
	_check(arr2.has(live) and not arr2.has(boss), "阵旗取敌只留活目标", str(arr2.size()))
	_check(not BossBase.hostile_units(player).has(boss)
		and BossBase.hostile_units(player).has(live),
		"统一取敌：排除尸体、保留活目标")
	# 第一次返回 false 没消耗资格，这里应能正常启动
	_check(bool(player.call("_parry_followup_dash")),
		"有活目标时弹反追击正常启动（没误伤正常索敌）")

	# 等追击 tween 跑完再拆场景，避免回调撞上已释放节点
	for i in 20:
		await get_tree().process_frame
	live.free()
	RogueRun.restore()
	arena.free()
