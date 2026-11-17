extends Node
## 完美弹反 → 追击 回归（2026-10-30）
## 用户报：完美弹反赫连霄后，追击普攻打不到他。
## 根因两条：
##   1) BossBase.on_parried 会把 BOSS 沿「来源→自己」方向击退 120（0.18 秒），
##      而玩家追击位移用的是**开打瞬间**的落点 → 落地时 BOSS 已经滑走；
##   2) 站位按 hit_radius（外接半径，含头顶球）算 → 赫连霄站到 111，
##      普攻容差（剑尖 70 + 球半径）只剩 2~3 像素，稍一漂就空。
## 用法：godot --headless --path . res://tools/probe_parry_followup.tscn

const BOSSES := ["domain_boss_01", "domain_boss_01_c", "domain_boss_02",
	"domain_boss_02_b", "domain_boss_02_c", "domain_boss_03", "domain_boss_03_b",
	"domain_boss_03_c"]

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
	print("\n########## 完美弹反 → 追击 回归 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.set_physics_process(false)
	for scene in BOSSES:
		await _one(p, String(scene))


func _one(p, scene: String) -> void:
	var boss = (load("res://scenes/boss/%s.tscn" % scene) as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	boss.global_position = Vector2.ZERO
	boss.set_physics_process(false)
	await get_tree().process_frame
	var feet0: Vector2 = boss.feet_position()
	var ys := ""
	for sp in boss.hit_spheres():
		ys += "%.0f," % (sp as Vector3).y
	print("   ", scene, " feet_offset=", feet0 - boss.global_position,
		" body_r=", boss.body_radius(), " hit_r=", boss.hit_radius(), " sphere_y=[", ys, "]")
	p.global_position = boss.global_position + Vector2(-120.0, 0.0)
	p.parry_followup_can_dash = true
	p.apply_buff("parry_followup", 2.0)
	var hp0: float = boss.current_hp
	boss.on_parried(p)
	var dashed: bool = p._parry_followup_dash()
	await get_tree().create_timer(0.30, true, false, true).timeout
	var live_feet: Vector2 = boss.feet_position()
	var gap: float = p.global_position.distance_to(live_feet)
	# 落点只要在「这一刀真的能打中」的范围里：下面直接按真实普攻结算验证，
	# 这里只留「别钻进身体」的负向约束（余量仅作参考，reach 由武器段位决定）。
	var margin := 1.0e9
	var surface := 1.0e9
	for sp in boss.hit_spheres():
		var sv: Vector3 = sp
		var c: Vector2 = boss.global_position + Vector2(sv.x, sv.y)
		var d: float = p.global_position.distance_to(c)
		margin = minf(margin, 70.0 + sv.z - d)
		surface = minf(surface, d - sv.z)
	_check(dashed, "%s：追击位移已触发" % scene,
		"余量=%.0f 脚底距=%.0f 击退=%.0f" % [margin, gap, feet0.distance_to(live_feet)])
	_check(surface >= -4.0, "%s：追击没有钻进受击球" % scene, "最近球面=%.0f" % surface)
	p.attack_dir = ((boss.global_position + Vector2(0.0, -10.0)) - p.global_position).normalized()
	p._perform_attack_hit()
	_check(boss.current_hp < hp0, "%s：追击普攻命中" % scene,
		"%.0f -> %.0f" % [hp0, boss.current_hp])
	boss.queue_free()
	await get_tree().process_frame
