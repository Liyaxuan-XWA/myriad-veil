extends Node
## 执烛界灯 / 分影扫击 / 观澜镜环场：棋局里的归属（票 006）
##
## 三处同一个根因：卫星实体按 faction / 组名定阵营，
## 而棋局里没有 "player" 组节点、双方又都在 "boss" 组里 ⇒
##   · 分影扫击与镜环场的目标列表恒空 ⇒ 圈不住人也扫不到人
##   · 两只执烛共用一盏界灯，第二只在别人那盏下跑 `_lamp_owned=false` 的全套减益
## 界灯这条要小心：`_ensure_lamp()` 的注释写着「同场只有一盏」是**设计**
## （召唤执烛助战时复用敌方那盏），所以只在带队伍号时才筛，单打一字不变。
##
## 用法：godot --headless --path . res://tools/probe_shadow_match.tscn -- --no-save

const ZHIZHU := "boss_04_b"

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
	for n in _spawned:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_spawned.clear()
	await _frames(8)


func _ready() -> void:
	print("\n########## 界灯 / 分影 / 镜环场 · 棋局归属 ##########")
	await _check_lamp_per_team()
	await _check_lamp_shared_single_player()
	await _check_sweeper_and_ring()
	_finish()


func _hp(u: Node) -> float:
	return float(u.get("current_hp"))


func _piece(team: int, cell: Vector2i) -> Node2D:
	var p := MatchAdapter.spawn_piece(self, ZHIZHU, team, cell)
	if p != null:
		_spawned.append(p)
	return p


## ① 棋局：两队执烛各立一盏灯，谁也不在谁的灯下挨减益
func _check_lamp_per_team() -> void:
	await _clear()
	var a := _piece(0, Vector2i(0, 0))
	var b := _piece(1, Vector2i(5, 5))
	await _frames(8)
	if a == null or b == null:
		_check(false, "① 前置：两只执烛都装出来了", "")
		return
	a.call("_ensure_lamp")
	b.call("_ensure_lamp")
	await _frames(3)
	var la: Node = a.get("_lamp")
	var lb: Node = b.get("_lamp")
	_check(la != null and lb != null, "① 两只执烛各自立起了界灯", "")
	if la == null or lb == null:
		return
	_check(la != lb, "① 不是同一盏（旧写法第二只只会复用第一只的）", "")
	_check(la.get("owner_unit") == a and lb.get("owner_unit") == b,
			"① 每盏灯的归属都是立它的那只", "")
	_check(ShadowLamp.find(a.get_parent(), a) == la,
			"① A 按队伍找回自己那盏", "")
	_check(ShadowLamp.find(b.get_parent(), b) == lb,
			"① B 按队伍找回自己那盏（不会挑到对方那盏）", "")


## ② 反向判据：没有队伍号时「同场只有一盏」的复用设计一字不变
func _check_lamp_shared_single_player() -> void:
	await _clear()
	var one: Node2D = (load("res://scenes/boss/domain_boss_04_b.tscn") as PackedScene).instantiate()
	add_child(one)
	_spawned.append(one)
	var two: Node2D = (load("res://scenes/boss/domain_boss_04_b.tscn") as PackedScene).instantiate()
	add_child(two)
	_spawned.append(two)
	await _frames(8)
	one.call("_ensure_lamp")
	two.call("_ensure_lamp")
	await _frames(3)
	var l1: Node = one.get("_lamp")
	var l2: Node = two.get("_lamp")
	_check(l1 != null and l1 == l2,
			"② 单打两只执烛仍共用同一盏灯（召唤助战的复用设计没被改掉）", "")


## ③ 分影扫击与镜环场：棋局里目标列表不再恒空
func _check_sweeper_and_ring() -> void:
	await _clear()
	var a := _piece(0, Vector2i(0, 0))
	var b := _piece(1, Vector2i(0, 1))
	await _frames(8)
	if a == null or b == null:
		_check(false, "③ 前置：两只棋子都装出来了", "")
		return

	var sweeper := ShadowSweeper.new()
	sweeper.caster = a
	add_child(sweeper)
	_spawned.append(sweeper)
	await _frames(2)
	var sw: Array = sweeper.call("_enemies")
	_check(sw.size() == 1 and sw[0] == b,
			"③ 分影扫击在棋局里扫得到对方（旧写法扫 player/ally_summon 恒空）",
			"%d 个" % sw.size())

	var ring := MirrorRingField.new()
	ring.source_unit = a
	add_child(ring)
	_spawned.append(ring)
	await _frames(2)
	var rt: Array = ring.call("_targets")
	_check(rt.size() == 1 and rt[0] == b,
			"③ 镜环场在棋局里圈得住对方（同上）", "%d 个" % rt.size())

	# 反向：没有队伍号的施法者仍走旧的 faction / 组名分派。
	# ⚠ caster 必须用**真执烛**：`shadow_sweeper.gd:120` 写的是
	#   `bool(caster.get("is_ally"))`，裸 Node2D 桩上没这个属性 → get 回 null →
	#   本机 4.7.2 直接报 "Nonexistent 'bool' constructor"，
	#   量到的是桩缺字段而不是路由（第一版就是这么红的）。
	var solo: Node2D = (load("res://scenes/boss/domain_boss_04_b.tscn") as PackedScene).instantiate()
	add_child(solo)
	_spawned.append(solo)
	var stub := Node2D.new()
	stub.name = "FakePlayer"
	stub.add_to_group("player")
	add_child(stub)
	_spawned.append(stub)
	await _frames(6)
	var sw2 := ShadowSweeper.new()
	sw2.caster = solo            # 敌方执烛（无队伍号）⇒ 该打玩家阵营
	add_child(sw2)
	_spawned.append(sw2)
	await _frames(2)
	var l2: Array = sw2.call("_enemies")
	_check(l2.has(stub), "③ 无队伍号的执烛分影仍按旧组名打玩家阵营", str(l2.size()))
	# ⚠ 同上：列表非空不等于打得到。把 _strike() / _pulse() 真跑一遍看血量。
	# mirror_image:471 就是"取目标改了、伤害签名还按玩家传"漏出去的实机崩溃。
	# 扫击要先有一条声道（_pending 由 _aim_now 填），这里直接摆一条朝下的。
	sweeper.damage = 500.0
	sweeper.global_position = a.global_position
	sweeper.set("_pending", {"dir": Vector2.DOWN, "length": 400.0})
	var hp_b := _hp(b)
	var hp_a := _hp(a)
	sweeper.call("_strike")
	await _frames(2)
	_check(_hp(b) < hp_b, "③ 分影扫击真的掉了对方的血（签名按目标类型分流）",
			"%.0f → %.0f" % [hp_b, _hp(b)])
	_check(_hp(a) == hp_a, "③ 施法者自己不掉血", "%.0f → %.0f" % [hp_a, _hp(a)])
	# 镜环场复用上面那个 ring，把伤害与半径补上再放一次脉冲
	ring.set("damage", 500.0)
	ring.set("radius", 400.0)
	ring.global_position = a.global_position
	var hp2 := _hp(b)
	ring.call("_pulse")
	await _frames(2)
	_check(_hp(b) < hp2, "③ 镜环场真的伤到对方棋子", "%.0f → %.0f" % [hp2, _hp(b)])


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
