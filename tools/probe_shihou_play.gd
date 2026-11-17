extends Node
## 镇墟石犼运行时模拟（2026-10-31）：真实 Player + 真实物理，假玩家绕圈+报声，
## 检查它会出招、会打到人、二阶段会破封/塌碣；不替代实机观感。
## 用法：godot --headless --path . tools/probe_shihou_play.tscn -- --no-save

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
	print("\n########## 镇墟石犼运行时模拟 ##########")
	var cfg := SecretWorldDB.get_core_boss(SecretWorldDB.REGION_YUANYING)
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector2(1200.0, 1000.0)
	p.is_teleporting = false
	p.invincible_timer = 0.0
	var boss := (load("res://scenes/world/youming_core_shihou.tscn") as PackedScene).instantiate()
	boss.configure(cfg.duplicate(true).merged({"pos": Vector2(1000.0, 1000.0)}, true),
		WorldEnemy.KIND_CORE, "镇墟石犼")
	boss.position = Vector2(1000.0, 1000.0)
	add_child(boss)
	boss.set_process(true)
	boss.set_physics_process(true)
	await get_tree().process_frame
	_check(boss.get("_prey") == p, "石犼锁定真实玩家")
	_check(is_equal_approx(float(boss.max_hp), 44000.0), "实例血量 44,000", str(boss.max_hp))

	var taken := 0.0
	var next_noise := 0.0
	var t := 0.0
	var p2_triggered := false
	var last_hp: float = float(p.get("hp"))
	while t < 20.0:
		await get_tree().create_timer(0.1, true).timeout
		t += 0.1
		if not is_instance_valid(boss) or boss.state == 6:
			break
		# 假玩家：围着石犼绕圈，每 0.4s 故意报一声
		var a := t * 0.9
		var radius := 190.0 if t < 10.0 else 330.0
		p.global_position = boss.global_position + Vector2(cos(a), sin(a)) * radius
		if t >= next_noise:
			p.emit_noise()
			next_noise = t + 0.4
		# 记录被打到的血量，再补满；清掉无敌帧让模拟继续吃到招
		if p.hp < last_hp:
			taken += last_hp - p.hp
		last_hp = p.hp
		p.hp = p.max_hp
		p.invincible_timer = 0.0
		if not p2_triggered and t >= 8.0:
			p2_triggered = true
			boss.current_hp = boss.max_hp * 0.49
			boss.take_damage(0.1)
			await get_tree().create_timer(0.7, true).timeout
			_check(bool(boss.get("_p2_started")), "8 秒时进入二阶段破封")
			var alive := 0
			for raw in boss.get("_steles"):
				if bool((raw as Dictionary).get("alive", false)):
					alive += 1
			_check(alive <= 4, "二阶段震塌石碣", str(alive))
	_check(taken > 1.0, "20 秒内至少打到玩家一次", "taken=%.1f" % taken)
	var usage: Dictionary = boss.get("skill_usage")
	var used: Array = usage.keys()
	_check(used.size() >= 2, "假玩家节奏下至少放出两种招式", str(used))
	_check((boss.get("_steles") as Array).size() == 6, "石碣数组仍在")
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	p.queue_free()
	boss.queue_free()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if _fails.is_empty() else 1)
