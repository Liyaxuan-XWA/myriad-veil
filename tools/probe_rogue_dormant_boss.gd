extends Node
## 试炼之路：小怪关里那只「透明的 BOSS」不该能被碰到（2026-11-09 用户报）
##
## 复现前提：试炼开局就要把本层 BOSS 实例化好放在 BossSpawn（血条 / 骨骼 / 阶段
## 要提前接好），但第 1~3 小关它是**不该存在**的，只把它 visible=false + process 关掉。
## 而玩家侧的伤害与索敌全是「扫 boss 组 + 算距离」的纯数学判定，根本不看可见性
## → 走到 BossSpawn 那团空气前照样能砍掉血，弹反追击还会往它身上冲。
##
## 修法：休眠时**同时**退出 "boss" 组 + 关掉全部碰撞形状；唤醒时按记录恢复。
## 用法：godot --headless --path . res://tools/probe_rogue_dormant_boss.tscn -- --no-save

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


## 数一只 BOSS 身上还有几个「启用中」的碰撞形状
func _enabled_shapes(b: Node) -> int:
	var n := 0
	for cs in b.find_children("*", "CollisionShape2D", true, false):
		var c := cs as CollisionShape2D
		if c != null and not c.disabled:
			n += 1
	return n


func _run() -> void:
	print("\n########## 试炼小怪关的透明 BOSS ##########")
	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	for i in 3:
		await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	var boss: Node2D = arena.get("boss")
	if rogue == null or player == null or boss == null:
		_check(false, "试炼战斗场景创建成功")
		RogueRun.restore()
		return
	# 冻住刷怪机、清掉第一波小怪，场上只剩那只休眠 BOSS
	rogue.set_process(false)
	for raw in (rogue.get("_alive") as Array):
		if is_instance_valid(raw):
			(raw as Node).free()
	(rogue.get("_alive") as Array).clear()

	# ---------- 休眠态 ----------
	_check(not boss.visible, "休眠：BOSS 不可见")
	_check(bool(boss.get("dormant")), "休眠：dormant 标记已置位")
	_check(not boss.is_in_group("boss"), "休眠：已退出 boss 组（按组取敌全部失效）")
	_check(_enabled_shapes(boss) == 0, "休眠：所有碰撞形状已关闭",
		"enabled=%d" % _enabled_shapes(boss))

	_check(not BossBase.hostile_units(player).has(boss),
		"统一取敌入口不含休眠 BOSS（对照项）")
	var near: Node = player.call("_nearest_boss", 9999.0)
	_check(near != boss, "软锁定不会选中休眠 BOSS",
		"null" if near == null else String(near.name))

	# ★ 核心复现：走到 BossSpawn 贴脸砍，休眠 BOSS 一滴血都不该掉
	player.global_position = boss.global_position + Vector2(-70.0, 0.0)
	await get_tree().process_frame
	var hp0 := float(boss.get("current_hp"))
	var hit := bool(player.call("_damage_bosses_in_shape",
		Vector2.RIGHT, 160.0, deg_to_rad(75.0), 30.0, "physical"))
	_check(not hit and is_equal_approx(float(boss.get("current_hp")), hp0),
		"贴脸普攻打不到休眠 BOSS（不掉血）",
		"hit=%s  hp %.1f→%.1f" % [str(hit), hp0, float(boss.get("current_hp"))])

	# ★ 弹反追击也不该往那团空气冲（和「索敌死 BOSS」同源）
	player.call("apply_buff", "parry_followup", 1.2)
	player.set("parry_followup_can_dash", true)
	var dashed := bool(player.call("_parry_followup_dash"))
	_check(not dashed, "弹反追击不冲向休眠 BOSS", "dash=%s" % str(dashed))

	# ---------- 唤醒：真的进 BOSS 关 ----------
	rogue.call("_start_boss_stage")
	for i in 3:
		await get_tree().process_frame
	var nb: Node2D = arena.get("boss")
	_check(nb != null and nb != boss, "BOSS 关重新实例化了一只（不复用休眠那只）")
	if nb == null:
		RogueRun.restore()
		arena.free()
		return
	_check(nb.visible, "唤醒：BOSS 可见")
	_check(not bool(nb.get("dormant")), "唤醒：dormant 标记已清")
	_check(nb.is_in_group("boss"), "唤醒：重新进入 boss 组")
	_check(_enabled_shapes(nb) > 0, "唤醒：碰撞形状已恢复",
		"enabled=%d" % _enabled_shapes(nb))

	player.global_position = nb.global_position + Vector2(-70.0, 0.0)
	await get_tree().process_frame
	var hp1 := float(nb.get("current_hp"))
	var hit2 := bool(player.call("_damage_bosses_in_shape",
		Vector2.RIGHT, 160.0, deg_to_rad(75.0), 30.0, "physical"))
	_check(hit2 and float(nb.get("current_hp")) < hp1,
		"唤醒后贴脸普攻正常命中掉血",
		"hit=%s  hp %.1f→%.1f" % [str(hit2), hp1, float(nb.get("current_hp"))])

	# ---------- 休眠 → 唤醒 → 再休眠（同一只）----------
	# ⚠ 这里专门盯「休眠时记形状」的簿记：第二遍休眠如果记不到形状，唤醒后 BOSS 就永远打不到
	rogue.call("_set_boss_dormant", true)
	for i in 2:
		await get_tree().process_frame
	_check(_enabled_shapes(nb) == 0 and not nb.is_in_group("boss"),
		"二次休眠同样收干净",
		"enabled=%d  in_group=%s" % [_enabled_shapes(nb), str(nb.is_in_group("boss"))])
	rogue.call("_set_boss_dormant", false)
	for i in 2:
		await get_tree().process_frame
	_check(_enabled_shapes(nb) > 0 and nb.is_in_group("boss"),
		"二次唤醒后仍可正常索敌/接触",
		"enabled=%d  in_group=%s" % [_enabled_shapes(nb), str(nb.is_in_group("boss"))])

	RogueRun.restore()
	arena.free()
