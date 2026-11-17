extends Node2D
## BOSS 伤害统计（2026-11-12 用户定）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_damage_report.tscn -- --no-save
##
## 口径：
##   · 台账只记**减免后掉血**（记账点在 BossBase.take_damage）；
##   · 来源靠出手方 push 标签：功法按功法名、普攻记「平A」、刀痕/符箓各自一行；
##   · 面板在**真实击杀链**（player 打死 BOSS → arena._on_boss_died）里出现，左侧固定大小。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const SKILL := "skill_sword_stab"

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
	print("\n########## BOSS 伤害统计 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	# ===== 1. 台账本身 =====
	DamageMeter.begin()
	DamageMeter.push("甲")
	DamageMeter.record(10.0)
	DamageMeter.push("乙")
	DamageMeter.record(5.0)
	DamageMeter.record(3.0)          # 没 push ⇒ 其他
	_check(is_equal_approx(DamageMeter.total, 18.0), "总计 = 各行之和", "%.0f" % DamageMeter.total)
	var rows := DamageMeter.ranked(8)
	_check(rows.size() == 3 and String(rows[0]["tag"]) == "甲" and is_equal_approx(float(rows[0]["amount"]), 10.0),
			"按伤害降序", str(rows))
	var has_other := false
	for r in rows:
		if String(r["tag"]) == "其他" and is_equal_approx(float(r["amount"]), 3.0):
			has_other = true
	_check(has_other, "没贴标签的算「其他」")
	# 超过 8 行 → 合并（已有的「其他」要并进去，不许出现两行同名）
	for i in 10:
		DamageMeter.push("源%d" % i)
		DamageMeter.record(100.0 - float(i))
	var top := DamageMeter.ranked(8)
	var names := {}
	var merged := 0.0
	for r in top:
		names[String(r["tag"])] = int(names.get(String(r["tag"]), 0)) + 1
		if String(r["tag"]) == "其他":
			merged = float(r["amount"])
	_check(top.size() == 8 and int(names.get("其他", 0)) == 1, "超过 8 行合并成一行「其他」", str(names))
	_check(merged > 3.0, "被合并的那些也计进「其他」", "%.0f" % merged)
	var total_before_finish := DamageMeter.total
	DamageMeter.finish()
	DamageMeter.push("甲")
	DamageMeter.record(99.0)
	_check(is_equal_approx(DamageMeter.total, total_before_finish), "finish 之后不再记账",
			"%.0f" % DamageMeter.total)

	# ===== 2. 真实链：打完 BOSS → 左侧出面板 =====
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN, "domain_id": "domain_01", "boss_id": "boss_01",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	for i in 6:
		await get_tree().process_frame
	var p: Node2D = arena.get("player")
	var boss: Node2D = arena.get("boss")
	_check(p != null and boss != null, "竞技场就绪")
	if p == null or boss == null:
		return
	p.set_physics_process(false)
	boss.set_physics_process(false)
	_check(DamageMeter.active, "开局已开始记账")
	p.global_position = boss.global_position
	# 一刀功法 + 一刀普攻（都走真实伤害函数）
	p.call("_damage_bosses_in_shape", Vector2.RIGHT, 400.0, PI, 50.0, "physical", "", true, SKILL)
	p.call("_damage_bosses_in_shape", Vector2.RIGHT, 400.0, PI, 30.0, "physical", "", true, "")
	var expect_skill := SkillDB.get_skill_name(SKILL)
	_check(float(DamageMeter.rows.get(expect_skill, 0.0)) > 0.0, "功法行记到了", expect_skill)
	_check(float(DamageMeter.rows.get("平A", 0.0)) > 0.0, "普攻记成「平A」")
	# 打死 → 真实死亡链
	boss.set("current_hp", 1.0)
	p.call("_damage_bosses_in_shape", Vector2.RIGHT, 400.0, PI, 999999.0, "physical", "", true, "")
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = null
	for n in (arena.get("$HUD") if false else arena.get_node("HUD")).get_children():
		if n is DamageReportPanel:
			panel = n as DamageReportPanel
	_check(panel != null, "击杀后 HUD 上出现伤害统计面板")
	if panel != null:
		_check(absf(panel.size.x - DamageReportPanel.PANEL_W) < 0.5, "面板是固定宽度",
				"%.0f" % panel.size.x)
		var labels := ""
		for n in panel.find_children("*", "Label", true, false):
			labels += String((n as Label).text)
		_check(labels.contains("伤害统计") and labels.contains("用时"), "抬头有标题与用时", labels.substr(0, 40))
		_check(labels.contains(expect_skill), "功法在面板里单独一行", expect_skill)
		var bars := 0
		for n in panel.find_children("*", "ProgressBar", true, false):
			bars += 1
		_check(bars >= 2, "每行都有条（图形，不只是数字）", "%d 条" % bars)
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("")
