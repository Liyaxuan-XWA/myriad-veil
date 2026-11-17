extends Node2D
## 攻速 → 平A出伤回归（2026-11-01 用户报「攻速增快后，平a伤害会丢失」）
##
## 根因：出伤帧挂在 `is_attacking` 里等 `_attack_hit_timer`，而武器那 0.18 秒左右的
## 刀锋时刻是按慢速标定的。攻速一快（装备攻速 / 满雷势），挥刀窗口比刀锋时刻还短，
## `attack_timer` 先走完 → `_end_attack()` 把 `_attack_hit_timer` 清成 -1 → 这一刀不掉血。
## 本探针把攻速拉到窗口短于刀锋时刻，要求**每一记平A都必须落地一次命中**。
## 用法：godot --headless --path . tools/probe_attack_speed_hits.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _p: Node2D
var _dummy: Node2D


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 连打 n 记平A，返回实际落地了多少次命中
func _swings(n: int) -> int:
	var hits := 0
	for i in range(n):
		var before := int(_dummy.hit_count)
		_p.attack_combo = i % 3
		_p._start_attack()
		var guard := 0
		while _p.is_attacking and guard < 240:
			await get_tree().physics_frame
			guard += 1
		# 窗口走完之后的兜底结算可能落在下一帧
		await get_tree().physics_frame
		await get_tree().physics_frame
		hits += int(_dummy.hit_count) - before
	return hits


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 攻速与平A出伤探针 ##########")
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	_p.global_position = Vector2.ZERO
	_p.is_teleporting = false
	_p.invincible_timer = 999.0
	_dummy = (load("res://scenes/combat/training_dummy.tscn") as PackedScene).instantiate()
	add_child(_dummy)
	_dummy.global_position = Vector2(70.0, 0.0)
	await get_tree().process_frame
	_p.global_position = _dummy.global_position + Vector2(-70.0, 0.0)
	_p.attack_dir = Vector2.RIGHT

	# 1) 基准：未加攻速时，三记平A 每记都要有伤害
	_p.stamina = 99
	var base_time := CharacterData.attack_interval()
	var base_hits := await _swings(3)
	_check(base_hits == 3, "基准攻速：3 记平A 全部出伤", "hits=%d" % base_hits)

	# 2) 把攻速拉到「挥刀窗口 < 刀锋时刻」，这才是用户遇到的区间
	for haste in [200.0, 500.0]:
		CharacterData.set_attribute_mod("probe_speed",
			{AttributeDB.ATTR_ATTACK_SPEED: {"flat": float(haste)}})
		_p._apply_attributes_to_runtime(false)
		var win := CharacterData.attack_interval()
		_check(win < 0.184, "前提：窗口已短于武器标定的刀锋时刻 %.3fs" % win,
			"攻速 +%d%%" % int(haste))
		_p.stamina = 99
		var n := 6
		var got := await _swings(n)
		_check(got == n, "攻速 +%d%%：%d 记平A 全部出伤" % [int(haste), n],
			"hits=%d window=%.3f" % [got, win])
		_dummy.reset_training_stats()
		_p.stamina = 99
		_p._start_attack()
		await get_tree().physics_frame
		await get_tree().create_timer(0.35).timeout
		_check(float(_dummy.total_damage) > 0.0, "攻速 +%d%%：伤害数值正常" % int(haste),
			"dmg=%.1f" % float(_dummy.total_damage))
	CharacterData.clear_attribute_mod("probe_speed")
	_p._apply_attributes_to_runtime(false)
	_check(is_equal_approx(CharacterData.attack_interval(), base_time),
		"探针收尾：攻速修正已清除")

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
