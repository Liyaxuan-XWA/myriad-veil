extends Node
## 棋局战报台账（票 001/002）——逐招输出到底记没记对
##
## 台账只有三个可信度问题，这一个探针全部对着它们：
##   ① **记的是减免后的实际掉血**（不是名义伤害）—— 把受击方抗性拉高，钱必须跟着变小
##   ② **归到"打出来的那只棋子"名下**，行名 = 玩家看得懂的招式名（走招名飘字那条公开入口，
##      不去戳私有字段：这样"前摇没报名字 ⇒ 台账也没有"这条因果是真的被测到的）
##   ③ **PvE 一个字都不记**（team_id < 0 ⇒ 不写），大世界/塔/演武场行为零变化
## 外加卫星归属（自带 report_owner / report_tag）与「普通攻击」「其余」两条兜底行。
##
## 用法：godot --headless --path . res://tools/probe_match_report.tscn -- --no-save

const A_ID := "boss_01"        # 刀客：走自己的招名入口，不碰并行会话在改的 01_c
const B_ID := "boss_huyao"

var _passes := 0
var _fails: Array = []
var _planned := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _plan(n: int) -> void:
	_planned += n


func _ready() -> void:
	print("\n########## 战报台账 · 票 001/002 ##########")
	await _check_stamp_and_actual_damage()
	await _check_pve_stays_clean()
	await _check_satellite_owner()
	await _check_fallback_rows()
	_check(_passes + _fails.size() >= _planned, "⑤ 判据全部跑到（没有半途中止）",
			"%d/%d" % [_passes + _fails.size(), _planned])
	_finish()


func _piece(boss_id: String, team: int, cell: Vector2i) -> Node2D:
	return MatchAdapter.spawn_piece(self, boss_id, team, cell) as Node2D


## ① 招名戳记 + 减免后口径
func _check_stamp_and_actual_damage() -> void:
	_plan(8)
	await _clear()
	var a := _piece(A_ID, 0, Vector2i(0, 0))
	var b := _piece(B_ID, 1, Vector2i(0, 1))
	await _frames(6)
	if a == null or b == null:
		_check(false, "① 前置：两只棋子都装出来了", "")
		return
	# 走公开入口报名字：探针不去碰 _report_form_name，否则测的是"我写了个字段"
	a.call("show_skill_name_at_windup", "横斩", 0.3)
	b.set("physical_resist", 0.0)
	b.set("current_hp", float(b.get("max_hp")))
	var hp0 := float(b.get("current_hp"))
	for _i in 3:
		b.call("take_damage", 100.0, a, "physical", "")
	var dealt := hp0 - float(b.get("current_hp"))
	var rows: Dictionary = a.get("report_rows")
	var total := float(a.call("report_total"))
	_check(rows.has("横斩"), "① 行名用的是前摇报名的那三个字", str(rows.keys()))
	_check(absf(float(rows.get("横斩", 0.0)) - dealt) < 0.01,
			"① 记的是**实际掉血**（300 名义 ⇒ 血条真掉了多少就记多少）",
			"行=%.1f 掉=%.1f" % [float(rows.get("横斩", 0.0)), dealt])
	_check(absf(total - dealt) < 0.01, "① 行合计 == report_total", "%.1f/%.1f" % [total, dealt])

	# 同一招再打 ⇒ 并到同一行（不是每次出手一行）
	b.call("take_damage", 100.0, a, "physical", "")
	_check(int(rows.size()) == 1, "① 同一招多次出手并成一行", str(rows.keys()))
	# 承受账：同一笔钱要在这只**挨打的**身上记成「来源棋子 → 招式」两层
	var taken: Dictionary = b.get("report_taken")
	var src_name := WorldDB.get_boss_name(A_ID)
	var taken_amt := 0.0
	if taken.has(src_name):
		taken_amt = float((taken[src_name] as Dictionary).get("横斩", 0.0))
	_check(absf(taken_amt - 400.0) < 0.01,
			"① 受击侧按来源棋子分组记了承受账（组里是招式行）", str(taken))
	_check(absf(float(rows.get("横斩", 0.0)) - 400.0) < 0.01
			and absf(taken_amt - float(rows.get("横斩", 0.0))) < 0.01,
			"① 同一笔钱在输出侧与承受侧完全相等",
			"打出=%.1f 承受=%.1f" % [float(rows.get("横斩", 0.0)), taken_amt])

	# 减免后口径的反向判据：把受击方物抗拉高，钱必须跟着变小
	var c := _piece(B_ID, 1, Vector2i(0, 2))
	await _frames(4)
	if c != null:
		c.set("physical_resist", 300.0)
		var hp1 := float(c.get("current_hp"))
		a.call("show_skill_name_at_windup", "竖斩", 0.3)
		c.call("take_damage", 200.0, a, "physical", "")
		var mitigated := hp1 - float(c.get("current_hp"))
		_check(mitigated > 0.0 and mitigated < 200.0,
				"① 高抗下记的是减免后的数（不是名义 200）", "掉=%.1f" % mitigated)
		var r2: Dictionary = a.get("report_rows")
		_check(absf(float(r2.get("竖斩", 0.0)) - mitigated) < 0.01,
				"① 「竖斩」行 = 这一笔的减免后值", "%.1f" % float(r2.get("竖斩", 0.0)))
	await _free(a, b, c)


## ③ PvE（没有队伍号）一个字都不记
func _check_pve_stays_clean() -> void:
	_plan(4)
	await _clear()
	var p := _piece(A_ID, -1, Vector2i(0, 0))
	var q := _piece(B_ID, -1, Vector2i(0, 1))
	await _frames(6)
	if p == null or q == null:
		_check(false, "② 前置：两只 PvE 单位装出来了", "")
		return
	p.call("show_skill_name_at_windup", "横斩", 0.3)
	q.call("take_damage", 100.0, p, "physical", "")
	_check((p.get("report_taken") as Dictionary).is_empty(),
			"② 承受账同样不记（PvE 两只都留白）", str(p.get("report_taken")))
	_check((p.get("report_rows") as Dictionary).is_empty(),
			"② team_id<0 ⇒ 不记（大世界/塔/演武场零变化）", str(p.get("report_rows")))
	_check(absf(float(p.call("report_total"))) < 0.0001, "② 合计恒为 0", str(p.call("report_total")))
	# 反向：给它挂上队伍号，同一笔就必须记账 —— 证明上面那条红不是因为压根没走到这里
	p.set("team_id", 0)
	q.call("take_damage", 100.0, p, "physical", "")
	_check(not (p.get("report_rows") as Dictionary).is_empty(),
			"② 反向：挂上队伍号后同一条路确实会记", str(p.get("report_rows")))
	await _free(p, q)


## ④ 卫星实体：自带行名 + 并入主人
func _check_satellite_owner() -> void:
	_plan(3)
	await _clear()
	var a := _piece(A_ID, 0, Vector2i(0, 0))
	var b := _piece(B_ID, 1, Vector2i(0, 1))
	await _frames(6)
	if a == null or b == null:
		_check(false, "③ 前置：两只棋子都装出来了", "")
		return
	var sat := (load("res://tools/probe_report_sat.gd") as GDScript).new() as Node2D
	sat.set("report_owner", a)
	sat.set("report_tag", "刀痕")
	add_child(sat)
	await _frames(2)
	var hp0 := float(b.get("current_hp"))
	b.call("take_damage", 60.0, sat, "physical", "")
	var dealt := hp0 - float(b.get("current_hp"))
	var rows: Dictionary = a.get("report_rows")
	_check(rows.has("刀痕"), "③ 卫星自己的行名进表（不是并进主人的招式行）", str(rows.keys()))
	_check(absf(float(rows.get("刀痕", 0.0)) - dealt) < 0.01,
			"③ 卫星的钱并到**主人**名下", "行=%.1f 掉=%.1f" % [float(rows.get("刀痕", 0.0)), dealt])
	_check(rows.size() == 1, "③ 只开主人这一户（卫星不另立台账）", str(rows.keys()))
	sat.free()
	await _free(a, b)


## ⑤ 兜底行：没报名字的出手 ⇒ 「普通攻击」；归属不明 ⇒ 不吞钱
func _check_fallback_rows() -> void:
	_plan(3)
	await _clear()
	var a := _piece(A_ID, 0, Vector2i(0, 0))
	var b := _piece(B_ID, 1, Vector2i(0, 1))
	await _frames(6)
	if a == null or b == null:
		_check(false, "④ 前置：两只棋子都装出来了", "")
		return
	# 新装的一只从没飘过招名（boss_01 的 _report_form_name 起始为空）
	var fresh := _piece(A_ID, 0, Vector2i(0, 3))
	await _frames(4)
	if fresh == null:
		_check(false, "④ 前置：第三只也装出来了", "")
		return
	#  precondition 自己控：把戳记清空，测的就是"这一笔没有招式名"而不是"它恰好还没出招"
	fresh.set("_report_form_name", "")
	fresh.set("report_tag", "")
	b.call("take_damage", 50.0, fresh, "physical", "")
	var r: Dictionary = fresh.get("report_rows")
	_check(r.has("普通攻击"), "④ 没报名字的出手归「普通攻击」", str(r.keys()))
	# 归属不明的来源（不是棋子、也没有主人）⇒ 不该凭空塞给谁
	var stranger := Node2D.new()
	add_child(stranger)
	var before := float(a.call("report_total"))
	b.call("take_damage", 80.0, stranger, "physical", "")
	_check(absf(float(a.call("report_total")) - before) < 0.01,
			"④ 归属不明的来源不硬塞给某只棋子（宁可少记，不许串台）",
			"%.1f→%.1f" % [before, float(a.call("report_total"))])
	# ⚠ 实机崩溃的形状：来源**有主人但没有那两个字段**（观澜的镜像不是 BossBase，
	#   压根没有 `_report_form_name` 属性）。读回来是 null，而 `String(null)`
	#   在本机是「Nonexistent 'String' constructor」—— 整局直接崩。
	var half := Node2D.new()
	half.set_meta("report_owner", a)
	add_child(half)
	await _frames(2)
	var hp1 := float(b.get("current_hp"))
	b.call("take_damage", 70.0, half, "physical", "")
	var rows4: Dictionary = a.get("report_rows")
	# 行名取决于主人当时飘的是哪一招（这里那只刀客自己已经出了「破步突进斩」），
	# 判据只咬两件事：**不崩**、钱一分不差地记到主人名下且只开一行。
	_check(rows4.size() == 1 and absf(float(a.call("report_total")) - 70.0) < 0.01,
			"④ 有主人但没字段的来源不崩，钱一分不差落到主人名下", str(rows4))
	stranger.free()
	await _free(a, b, fresh)


func _clear() -> void:
	for ch in get_children():
		ch.free()
	await get_tree().process_frame


func _free(a: Node2D, b: Node2D = null, c: Node2D = null) -> void:
	for n in [a, b, c]:
		if n != null and is_instance_valid(n):
			n.free()
	await get_tree().process_frame


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _finish() -> void:
	print("RESULT passes=%d fails=%d" % [_passes, _fails.size()])
	if not _fails.is_empty():
		print("FAILED: ", str(_fails))
	get_tree().quit(0 if _fails.is_empty() else 1)
