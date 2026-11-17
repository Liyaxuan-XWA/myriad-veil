extends Node2D
## 前摇不许因为「目标走开」被取消（2026-11-12 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_windup_commit.tscn -- --no-save
##
## 口径：
##   · 大世界怪与 BOSS 都要**抬手就出完**：目标跑出射程后，状态仍停在 WINDUP 并最终落到 ATTACK/RECOVER；
##   · 控制类打断照旧（封技 apply_skill_lock 仍能把前摇打断）—— 两条不是一回事，别一起删。

const ENEMY_SCENE := "res://scenes/world/world_enemy.tscn"
const BOSS_SCENE := "res://scenes/boss/boss.tscn"

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
	print("\n########## 前摇不因目标走开而取消 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


## 把单位摆成「已经抬手、目标在两千里外」的现场
func _prime(unit: Node2D, target: Node2D) -> void:
	unit.set_physics_process(false)
	unit.set("target", target)
	unit.set("state", BossBase.BossState.WINDUP)
	unit.set("state_timer", 0.25)
	unit.set("current_attack_kind", BossBase.AttackKind.PHYSICAL_MELEE)
	target.global_position = unit.global_position + Vector2(2000.0, 0.0)


func _run() -> void:
	var target := Node2D.new()
	add_child(target)

	# ===== 1. 大世界怪：跑出射程也不再收招 =====
	var enemy = (load(ENEMY_SCENE) as PackedScene).instantiate()
	add_child(enemy)
	await get_tree().process_frame
	# ⚠ 不给它配招式：这里验的是状态机，不是 AI 选招
	enemy.configure({"pos": Vector2.ZERO, "max_hp": 500.0, "attack_power": 10.0,
		"visual_id": "player_liqingyun", "move_speed": 120.0, "aggro_range": 0.0,
		"leash_range": 2000.0, "skills": []}, WorldEnemy.KIND_CULTIVATOR, "试招野修")
	enemy.global_position = Vector2.ZERO
	await get_tree().process_frame
	_prime(enemy, target)
	enemy.call("_tick_state", 0.05)
	_check(int(enemy.get("state")) == BossBase.BossState.WINDUP,
			"目标跑到 2000px 外：前摇**没有**被取消（仍在 WINDUP）",
			"state=%d" % int(enemy.get("state")))
	for i in 6:
		enemy.call("_tick_state", 0.05)
	var st := int(enemy.get("state"))
	_check(st != BossBase.BossState.WINDUP and st != BossBase.BossState.CHASE,
			"前摇走完，照样把招放出去", "state=%d" % st)

	# ===== 2. 封技（控制）仍然能打断：这条没被一起删掉 =====
	_prime(enemy, target)
	enemy.call("apply_skill_lock", 1.0)
	_check(int(enemy.get("state")) == BossBase.BossState.CHASE,
			"封技仍能打断前摇（控制是另一回事）", "state=%d" % int(enemy.get("state")))
	enemy.queue_free()
	await get_tree().process_frame

	# ===== 3. BOSS 同样抬手就出完 =====
	var boss = (load(BOSS_SCENE) as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	_prime(boss, target)
	boss.call("_tick_state", 0.05)
	_check(int(boss.get("state")) == BossBase.BossState.WINDUP,
			"BOSS：目标跑开也不收招", "state=%d" % int(boss.get("state")))
	for i in 6:
		boss.call("_tick_state", 0.05)
	var bst := int(boss.get("state"))
	_check(bst != BossBase.BossState.WINDUP and bst != BossBase.BossState.CHASE,
			"BOSS：前摇走完照样出手", "state=%d" % bst)
	boss.queue_free()
	await get_tree().process_frame
	print("")
