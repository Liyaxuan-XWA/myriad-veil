extends Node
## 时间流恢复基准回归（2026-11-02 卡片自走棋地基第①项）
##
## 改之前：顿帧/慢动作结束一律恢复成写死的 `Engine.time_scale = 1.0`。
## 单人玩法没问题，但卡片自走棋要把对局倍率推到 1.0→2.0 做「时间加速」，
## 那时 BOSS 转阶段只要触发一次慢动作，就会把加速值**静默冲回 1.0** ——
## 表现为「越打越慢回去」，而且没有任何报错，是最难查的那类 bug。
##
## 本探针要求：加速中插入顿帧/慢动作，结束后必须回到**当前倍率**而不是 1.0；
## 同时基准为 1.0 时（现有全部玩法）行为与改动前逐帧一致。
## 用法：godot --headless --path . tools/probe_time_flow_base.tscn -- --no-save

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 真实时间等待。⚠ 不能用 create_timer(ignore_time_scale=true)：
##   本机 4.7.2 上它首次会当帧触发（见 godot-timer-ignore-timescale 那条踩坑），
##   而本探针全程都在操纵 time_scale，正好是最容易中招的场合。
func _wait_real(sec: float) -> void:
	var until := Time.get_ticks_usec() + int(sec * 1_000_000)
	var guard := 0
	while Time.get_ticks_usec() < until and guard < 2000:
		await get_tree().process_frame
		guard += 1


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.02


func _ready() -> void:
	print("\n########## 时间流恢复基准 ##########")

	# ---- 1. 默认基准 = 1.0，现有玩法行为不变 ----
	GameState.reset_time_flow()
	_check(_near(GameState.time_flow_base, 1.0), "默认基准为 1.0", "base=%.2f" % GameState.time_flow_base)
	GameState.trigger_hit_stop(0.06, true)
	_check(_near(Engine.time_scale, GameState.HIT_STOP_TIME_SCALE), "顿帧立即生效",
			"scale=%.2f" % Engine.time_scale)
	await _wait_real(0.14)
	_check(_near(Engine.time_scale, 1.0), "基准 1.0 时顿帧恢复回 1.0（回归保护）",
			"scale=%.2f" % Engine.time_scale)

	# ---- 2. 核心断言：加速中顿帧，必须回到加速值 ----
	GameState.set_time_flow_base(1.6)
	_check(_near(Engine.time_scale, 1.6), "设定基准后立即生效", "scale=%.2f" % Engine.time_scale)
	GameState.trigger_hit_stop(0.06, true)
	_check(_near(Engine.time_scale, GameState.HIT_STOP_TIME_SCALE), "加速中仍能顿帧",
			"scale=%.2f" % Engine.time_scale)
	await _wait_real(0.14)
	_check(_near(Engine.time_scale, 1.6), "加速中顿帧结束回到 1.6 而不是 1.0",
			"scale=%.2f" % Engine.time_scale)

	# ---- 3. 慢动作同样回到基准 ----
	GameState.trigger_slow_mo(0.08, 0.4)
	_check(_near(Engine.time_scale, 0.4), "慢动作生效", "scale=%.2f" % Engine.time_scale)
	await _wait_real(0.16)
	_check(_near(Engine.time_scale, 1.6), "慢动作结束回到基准", "scale=%.2f" % Engine.time_scale)

	# ---- 4. 基准可连续推高（对局加速是每帧重设的） ----
	GameState.set_time_flow_base(2.0)
	GameState.trigger_hit_stop(0.06, true)
	await _wait_real(0.14)
	_check(_near(Engine.time_scale, 2.0), "推到 2.0 后顿帧仍回到 2.0", "scale=%.2f" % Engine.time_scale)

	# ---- 5. 基准下限：0 会把整局冻死，必须被夹住 ----
	GameState.set_time_flow_base(0.0)
	_check(GameState.time_flow_base > 0.0, "基准被夹到下限、不会归零冻死",
			"base=%.2f" % GameState.time_flow_base)

	# ---- 6. 换场景必须清干净，不得把上一局倍率带过去 ----
	GameState.reset_time_flow()
	_check(_near(GameState.time_flow_base, 1.0) and _near(Engine.time_scale, 1.0),
			"reset 连基准一起清", "base=%.2f scale=%.2f" % [GameState.time_flow_base, Engine.time_scale])

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for s in _fails:
		print("  ! ", s)
	get_tree().quit(1 if not _fails.is_empty() else 0)
