extends Node
## 刀痕：棋局里的归属与结算（票 002）
##
## 2026-11-05 实测：`blade_scar._slash_enemies()` 按组名 `"player"` 取敌，
## 而棋局里没有 player 节点 → **刀客的招牌伤害在棋盘上一刀不劈**，
## 不崩、不报错、探针也不红，只有实机打起来才发现这只卡特别软。
## 现在改成按留痕者本体走 `BossBase.hostile_units()`，并给点燃加归属筛
## （两队刀客的 `side` 都是 SIDE_BOSS，只按 side 筛就会点燃对手的痕再劈到自己人）。
##
## ⚠ 刀痕上限 MAX_NORMAL=4 双方共用**没改**：`scar_field.gd` 头部写明这是设计
##   （"双方共用同一份实例与上限，玩家学会刀客招式后能和 BOSS 打同一套刀痕博弈"），
##   不在本次修复范围里，别把它当 bug 顺手"修"掉。
##
## 用法：godot --headless --path . res://tools/probe_scar_match.tscn -- --no-save

const DAOKE := "boss_01"

var _passes := 0
var _fails: Array = []
var _spawned: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _clear() -> void:
	var f := ScarField.get_active()
	if f != null and is_instance_valid(f):
		f.clear_all()
		(f as Node).queue_free()
	for n in _spawned:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_spawned.clear()
	await _frames(8)


func _ready() -> void:
	print("\n########## 刀痕 · 棋局归属与结算 ##########")
	await _check_hits_enemy_piece()
	await _check_ignite_ownership()
	await _check_single_player_unchanged()
	_finish()


func _hp(u: Node) -> float:
	return float(u.get("current_hp"))


## ① 刀痕在棋盘上真的能劈到对方棋子
func _check_hits_enemy_piece() -> void:
	await _clear()
	var a: Node2D = MatchAdapter.spawn_piece(self, DAOKE, 0, Vector2i(0, 0))
	var b: Node2D = MatchAdapter.spawn_piece(self, DAOKE, 1, Vector2i(0, 1))
	_spawned.append(a)
	_spawned.append(b)
	await _frames(6)
	if a == null or b == null:
		_check(false, "① 前置：两只刀客都装出来了", "")
		return
	var f := ScarField.ensure()
	_check(f != null, "① 前置：刀痕场建起来了", "")
	if f == null:
		return
	# A 在 B 脚下留一道痕（avoid 传 null，免得被推开 40px 掉出 52px 判定圈）
	var scar: Node = f.spawn_scar(b.global_position, BladeScar.SIDE_BOSS, 300.0, 1.0,
			null, "elemental", a)
	_check(scar != null, "① 前置：痕生成了", "")
	if scar == null:
		return
	var a_before := _hp(a)
	var before := _hp(b)
	var hits := int(scar.call("slash", 1))
	await _frames(2)
	# 旧写法这里恒 0：按组名 "player" 取敌，棋盘上没有 player 节点
	_check(hits == 1, "① 刀痕劈到对方棋子（旧写法恒 0 命中）", "%d 次" % hits)
	_check(_hp(b) < before, "① 对方血量真的掉了", "%.0f → %.0f" % [before, _hp(b)])
	_check(_hp(a) == a_before, "① 留痕者自己不掉血", "%.0f → %.0f" % [a_before, _hp(a)])


## ② 点燃按本体认：A 不许点亮 B 的痕
func _check_ignite_ownership() -> void:
	await _clear()
	var a: Node2D = MatchAdapter.spawn_piece(self, DAOKE, 0, Vector2i(0, 0))
	var b: Node2D = MatchAdapter.spawn_piece(self, DAOKE, 1, Vector2i(5, 5))
	_spawned.append(a)
	_spawned.append(b)
	await _frames(6)
	var f := ScarField.ensure()
	if a == null or b == null or f == null:
		_check(false, "② 前置：两只刀客与刀痕场都在", "")
		return
	# ⚠ 一次点燃就把痕变成一次斩击并 queue_free（blade_scar.gd:164），
	#   所以三个判据之间必须重新铺痕 —— 第一版连着量三次，后两次量到的是空场。
	# B 的痕贴着 A（在点燃半径里），A 自己的痕放在远处
	var n_old := 0
	var n_a := 0
	var n_b := 0
	_reset_scars(f, a, b)
	n_old = int(f.ignite_in_radius(a.global_position, 300.0, 4, BladeScar.SIDE_BOSS))
	_reset_scars(f, a, b)
	n_a = int(f.ignite_in_radius(a.global_position, 300.0, 4, BladeScar.SIDE_BOSS, a))
	_reset_scars(f, a, b)
	n_b = int(f.ignite_in_radius(a.global_position, 300.0, 4, BladeScar.SIDE_BOSS, b))
	# 不传 igniter 的旧调用必须照旧按 side 全量点燃
	_check(n_old == 1, "② 没传 igniter 时仍按 side 筛（老调用点行为不变）", "%d 处" % n_old)
	_check(n_a == 0, "② A 点不亮 B 的痕（只按 side 筛会点亮并劈向自己人）", "%d 处" % n_a)
	_check(n_b == 1, "② B 仍点亮自己的痕（归属筛没把正常路径关掉）", "%d 处" % n_b)


## 铺两道痕：B 的在 A 脚下（在点燃半径里）、A 自己的在半径外。
func _reset_scars(f: Node, a: Node2D, b: Node2D) -> void:
	f.clear_all()
	f.spawn_scar(a.global_position, BladeScar.SIDE_BOSS, 300.0, 1.0, null, "elemental", b)
	f.spawn_scar(a.global_position + Vector2(900.0, 0.0), BladeScar.SIDE_BOSS,
			300.0, 1.0, null, "elemental", a)


## ③ 反向判据：单打那条已经跑了几周的路一个字节都不许变
func _check_single_player_unchanged() -> void:
	await _clear()
	var player: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	_spawned.append(player)
	# 直接实例化，不走 MatchAdapter ⇒ team_id 保持 -1，就是单打那套身份
	var boss: Node2D = (load("res://scenes/boss/domain_boss_01.tscn") as PackedScene).instantiate()
	add_child(boss)
	_spawned.append(boss)
	await _frames(8)
	var f := ScarField.ensure()
	if f == null or not is_instance_valid(player):
		_check(false, "③ 前置：玩家与刀客都进树了", "")
		return
	var scar: Node = f.spawn_scar(player.global_position, BladeScar.SIDE_BOSS, 300.0, 1.0,
			null, "elemental", boss)
	if scar == null:
		_check(false, "③ 前置：单打侧痕生成了", "")
		return
	var hits := int(scar.call("slash", 1))
	await _frames(2)
	_check(hits == 1, "③ 单打 BOSS 的痕仍打得到玩家（走 enemy_units 老路径）", "%d 次" % hits)
	_check(BossBase.unit_team(boss) < 0, "③ 前置：单打刀客没有队伍号", str(BossBase.unit_team(boss)))


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
