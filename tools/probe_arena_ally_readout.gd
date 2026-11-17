extends Node2D
## 阵营读数回归（2026-11-01 用户实机报的错）：
## 训练木桩在 "boss" 组里但不是 BossBase，没有 is_ally 属性；
## 旧代码 `bool(node.get("is_ally"))` 会拿到 null 并报
## 「Invalid call. Nonexistent 'bool' constructor」，镜湖每 0.8 秒刷一条。
## 用法：godot --headless --path . tools/probe_arena_ally_readout.tscn -- --no-save

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
	print("\n########## 阵营读数回归探针 ##########")
	var dummy: Node2D = (load("res://scenes/combat/training_dummy.tscn") as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = Vector2(60.0, 0.0)
	await get_tree().process_frame

	_check(dummy.is_in_group("boss"), "木桩确实在 boss 组里")
	_check(dummy.get("is_ally") == null, "木桩没有 is_ally 属性（旧代码在此 bool() 报错）")
	_check(not BossBase.is_ally_unit(dummy), "is_ally_unit：非 BossBase 读作敌方")
	_check(not BossBase.is_ally_unit(null), "is_ally_unit：null 安全")

	var img := MirrorImage.new()
	add_child(img)
	img.setup(dummy, "player", Vector2(0.0, 0.0), null, Vector2(0.25, 0.25),
		Vector2.ZERO, Color.WHITE, MirrorImage.ECHO_RATIO, 5.0)
	await get_tree().process_frame
	_check(BossBase.is_ally_unit(img), "is_ally_unit：玩家镜像读作友军")

	var field := MirrorRingField.new()
	field.setup(Vector2.ZERO, true, 200.0, 5.0, 12.0, null, Color(0.6, 0.86, 1.0, 1.0))
	add_child(field)
	await get_tree().process_frame
	var targets: Array = field._targets()
	_check(targets.size() == 1 and targets[0] == dummy,
		"镜湖把木桩列为敌方目标、把玩家镜像排除在外", "n=%d" % targets.size())
	dummy.reset_training_stats()
	field._pulse()
	await get_tree().process_frame
	_check(dummy.total_damage > 0.0, "镜湖对木桩正常结算一次水伤",
		"dmg=%.1f" % dummy.total_damage)
	_check(dummy.hit_count == 1 and dummy.debuffs.has("mirror_slow"),
		"一次结算一跳并挂镜滞", "hits=%d" % dummy.hit_count)

	img.queue_free()
	field.queue_free()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
