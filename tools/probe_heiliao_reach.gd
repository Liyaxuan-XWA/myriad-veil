extends Node
## 赫连霄 受击框可达性实测（2026-10-30）
## 玩家站在 BOSS **脚底同一水平线**上，从不同横向距离砍一刀，看多近才算命中。
## 用来验证「受击球 y 投影到 0」是否把判定抬到了玩家够不着的高度。
## 用法：godot --headless --path . res://tools/probe_heiliao_reach.tscn

const DX_LIST := [20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 140.0]

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
	print("\n########## 赫连霄 受击框可达性 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	var boss = (load("res://scenes/boss/domain_boss_03.tscn") as PackedScene).instantiate()
	add_child(boss)
	await get_tree().process_frame
	boss.global_position = Vector2.ZERO
	boss.set_physics_process(false)
	await get_tree().process_frame
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.set_physics_process(false)
	var feet: Vector2 = boss.feet_position()
	print("   feet_offset=", feet - boss.global_position, " 受击球 y=",
		(boss.call("hit_spheres")[0] as Vector3).y)
	var landed: Array = []
	for dx in DX_LIST:
		p.global_position = feet + Vector2(-dx, 0.0)
		p.attack_dir = (boss.global_position - p.global_position).normalized()
		var hp0: float = boss.current_hp
		p._perform_attack_hit()
		var hit: bool = boss.current_hp < hp0
		landed.append(hit)
		print("   dx=%.0f  %s" % [dx, "命中" if hit else "打空"])
	_check(landed[0] and landed[1] and landed[2] and landed[3],
		"脚底线上 20~80 距离都砍得到（受击框贴合立绘宽度）", str(landed))
	_check(not landed[5] and not landed[6],
		"120 以外砍不到（框没有无脑放大）", str(landed))
	_check(boss.current_hp <= boss.max_hp, "结算未溢出")
