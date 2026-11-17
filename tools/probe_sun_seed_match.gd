extends Node
## 天火种：两只离照同场时的归属（票 004）
##
## 旧 `_find_seed()` 返回组里**第一只**活着的种子，不看归属。
## 单打场上只有一颗，所以从没露馅；棋局里双方都可能各带一只离照，于是：
##   · 后落的那只把 `_seed` 指到别人的火上 ⇒ 自己那颗永远不补种
##   · `_connect_seed` 把 picked/stolen/consumed 接到两个本体上
##     ⇒ 别人的火被夺，这只也喊「火种被夺！」并把 `_decide_wait` 归零白捡一次出手
## 修法只加归属筛，**不动拾取规则** —— `_can_hold` 仍允许任何离照抢火，
## 「天火种争夺」这条口径保持原样（ADR/记忆里的离照设计）。
##
## 用法：godot --headless --path . res://tools/probe_sun_seed_match.tscn -- --no-save

const LIZHAO := "boss_03_b"

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
	print("\n########## 天火种 · 两只离照同场 ##########")
	await _check_ownership()
	_finish()


func _piece(team: int, cell: Vector2i, boss_id: String = LIZHAO) -> Node2D:
	var p := MatchAdapter.spawn_piece(self, boss_id, team, cell)
	if p != null:
		_spawned.append(p)
	return p


func _check_ownership() -> void:
	await _clear()
	var a := _piece(0, Vector2i(0, 0))
	var b := _piece(1, Vector2i(5, 5))
	await _frames(8)
	if a == null or b == null:
		_check(false, "① 前置：两只离照都装出来了", "")
		return
	_check(a.has_method("uses_sun_seed") and bool(a.call("uses_sun_seed")),
			"① 前置：棋子确实会玩火", "")

	a.call("_spawn_seed")
	b.call("_spawn_seed")
	await _frames(4)
	var sa: Node = a.get("_seed")
	var sb: Node = b.get("_seed")
	_check(sa != null and sb != null, "① 两只离照各自落了一颗火种", "")
	if sa == null or sb == null:
		return
	_check(sa != sb, "① 不是同一颗（旧写法两只都只会拿到第一颗）", "")
	_check(sa.get("source_boss") == a and sb.get("source_boss") == b,
			"① 每颗火种的归属都是落下它的那只", "")

	# ② 各认各的：_find_seed 不许跨主
	_check(a.call("_find_seed") == sa, "② A 只认自己那颗", "")
	_check(b.call("_find_seed") == sb, "② B 只认自己那颗", "")

	# ③ 信号不许跨主：A 的火被抢，B 不该跟着喊「火种被夺」并白捡一次出手
	# ⚠ 本机 4.7.2 没有 Node.method()，要用 Callable(obj, "name")。
	#   写错的那一版让函数中途挂掉，RESULT 却照样打 fails=0 —— 假绿，别信。
	var cb := Callable(b, "_on_seed_picked")
	_check(not sa.picked.is_connected(cb),
			"③ B 没接到 A 的火种信号（旧写法两只都会接）", "")
	_check(sb.picked.is_connected(Callable(b, "_on_seed_picked")),
			"③ B 仍接到自己那颗的信号（归属筛没把正常路径关掉）", "")

	# ④ A 的火种消失后，B 的补种计时不该被 A 的存在压住
	a.get("_seed").set("state", SunSeed.State.GONE)
	await _frames(2)
	_check(b.call("_find_seed") == sb, "④ A 的火灭掉不影响 B 认自己的火", "")
	# 反向判据：抢火规则没动 —— 门槛仍是"会不会玩火"，不是归属
	_check(bool(sb.call("_can_hold", a)), "④ 「争夺」口径没变：对方离照仍能抢火", "")
	# 刀客：同队、有 boss 组身份，但没有 uses_sun_seed() ⇒ 拿不到火。
	# （先想用虎妖，但 scenes/boss/ 下没有 boss_huyao.tscn，spawn_piece 会回 null，
	#   判据就变成"前置没装出来"的假红 —— 换确实存在场景的刀客。）
	var non_fire := _piece(0, Vector2i(2, 4), "boss_01")
	await _frames(6)
	_check(non_fire != null, "④ 前置：不会玩火的那只装出来了", "")
	_check(not bool(sb.call("_can_hold", non_fire)),
			"④ 不会玩火的棋子依然拿不到火（没被改成按归属放行）", "")


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
