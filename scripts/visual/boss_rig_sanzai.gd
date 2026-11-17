class_name BossRigSanzai
extends BossRig
## 晏无咎的 2D 骨骼动作集（2026-10-29）。
##
## 分件：body（整身长袍）/ hand_cast（举起的右手，绕腕转）/ 三段劫环
## （wheel_outer / wheel_mid / wheel_inner，各自独立旋转）。
##
## ## 为什么只拆一只手
##
## 这张定妆图的袖子又宽又碎，按肩肘拆上臂会把袖口从袍子上扯开 —— 2D 刚体一转，
## 原位置必空一块，白缝遮不住。所以宽袖全留在 body 上，只把「举到头顶的右手」
## 从腕口切下来：手转开时下面永远有前臂垫着，不会露缝。手的摆幅因此控制在
## ±0.25 rad（约 14°），手腕的「捏诀 / 翻掌」够用了。
##
## ## 劫环是主表演
##
## 三灾轮转的视觉锚点就是背后三段环：待机时慢速差速转，出招时同向/反向急转；
## 雷池那一招把环「拽偏再卡死」，对应玩法里的锁灾。环只做视觉，不参与判定。
##
## ⚠ 一次性动画的末尾要转回 0（或 TAU 的整数倍）。`stop_one_shot` 只把 body 的
##   rotation/scale 按回中性，环的 rotation 会留到 idle 的轨道接管为止 ——
##   停在半圈会在收招瞬间跳一下。

const SANZAI_SKILLS := {
	"step": {"length": 0.55, "windup": 0.55},
	"slash": {"length": 0.60, "windup": 0.60},
	"fire_seal": {"length": 0.70, "windup": 0.70},
	"fire_field": {"length": 0.75, "windup": 0.75},
	"thunder_strike": {"length": 0.75, "windup": 0.75},
	"thunder_pool": {"length": 0.80, "windup": 0.80},
	"turn": {"length": 0.70, "windup": 0.70},
	"final": {"length": 1.20, "windup": 1.20},
}

const S_IDLE_CYCLE := 4.0
const S_WALK_CYCLE := 1.30


func _skill_table() -> Dictionary:
	return SANZAI_SKILLS


func _skill_ids() -> Array:
	return SANZAI_SKILLS.keys()


func _skill_anim(anim: String) -> Animation:
	var a := Animation.new()
	a.length = float(SANZAI_SKILLS[anim]["length"])
	a.loop_mode = Animation.LOOP_NONE
	return a


func _hit_time(anim: String) -> float:
	var length := float(SANZAI_SKILLS[anim]["length"])
	var windup := float(SANZAI_SKILLS[anim]["windup"])
	return windup * length / (windup + 0.15)


func _make_skill(anim: String) -> Animation:
	match anim:
		"step":
			return _make_step()
		"slash":
			return _make_slash()
		"fire_seal":
			return _make_fire_seal()
		"fire_field":
			return _make_fire_field()
		"thunder_strike":
			return _make_thunder_strike()
		"thunder_pool":
			return _make_thunder_pool()
		"turn":
			return _make_turn()
		"final":
			return _make_final()
	return _make_slash()


# ===================== 通用出招曲线 =====================
#
# 与刀客/离照同一套「慢蓄力 → 判定前到位 → 定格 → 回收」：
# 判定那一帧在动画时间轴上是 `_hit_time()`，所以所有关键帧都围绕它排，
# 不能把 windup 直接当秒用（动画会被 play_one_shot 压进 windup+0.15 秒）。

func _pose(a: Animation, anim: String, pull: Vector2, push: Vector2,
		rot_back: float, rot_hit: float, hand_back: float, hand_hit: float,
		squash: Vector2, spins: Vector3, hand_hold: float = 0.0) -> void:
	var t_hit := _hit_time(anim)
	var t_pull := t_hit * 0.55
	var t_free := minf(t_hit + a.length * 0.10, a.length - 0.01)
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b],
		[t_pull * 0.6, b + pull * 0.45],
		[t_pull, b + pull],
		[t_hit, b + push],
		[t_free, b + push],
		[a.length, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [t_pull, rot_back], [t_hit, rot_hit],
		[t_free, rot_hit], [a.length, 0.0],
	])
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE],
		[t_pull, squash],
		[t_hit, Vector2(2.0 - squash.x, 2.0 - squash.y)],
		[t_free, Vector2(2.0 - squash.x, 2.0 - squash.y)],
		[a.length, Vector2.ONE],
	])
	var hold: float = hand_hold if hand_hold > 0.0 else t_free
	_add_keys(a, "hand_cast", "rotation", [
		[0.0, 0.0], [t_pull, hand_back], [t_hit, hand_hit],
		[hold, hand_hit], [a.length, 0.0],
	])
	_wheel_spin(a, t_hit, t_free, spins)


## 三段环按 (外, 中, 内) 的圈数转。整数圈 → 结束值回到 0（TAU 的整数倍），
## 收招回 idle 时不会跳。
func _wheel_spin(a: Animation, t_hit: float, t_free: float, spins: Vector3) -> void:
	var parts := ["wheel_outer", "wheel_mid", "wheel_inner"]
	for i in range(3):
		var turns := float(spins[i])
		if absf(turns) < 0.01:
			_add_keys(a, parts[i], "rotation", [[0.0, 0.0], [a.length, 0.0]])
			continue
		# 前 70% 的时间走完 85% 的圈，判定后减速收完 —— 急转后收势，不是匀速转盘
		_add_keys(a, parts[i], "rotation", [
			[0.0, 0.0],
			[t_hit * 0.70, TAU * turns * 0.85],
			[t_hit, TAU * turns],
			[t_free, TAU * turns],
			[a.length, TAU * turns],
		])


# ===================== 循环 =====================

func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = S_IDLE_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 1.6, 1, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.006, 1)
	_add_sine(a, "hand_cast", "rotation", 0.55, 0.016, 1)
	# 三环差速微摆：外环慢、内环快，像三套不同重量的轮子挂在同一根轴上
	_add_sine(a, "wheel_outer", "rotation", 0.12, 0.075, 1)
	_add_sine(a, "wheel_mid", "rotation", 0.62, -0.055, 1)
	_add_sine(a, "wheel_inner", "rotation", 0.38, 0.10, 1)
	_neutral_all(a)
	return a


func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = S_WALK_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 2.4, 2, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.010, 1)
	_add_sine(a, "hand_cast", "rotation", 0.60, 0.030, 1)
	_add_sine(a, "wheel_outer", "rotation", 0.10, 0.16, 1)
	_add_sine(a, "wheel_mid", "rotation", 0.58, -0.13, 1)
	_add_sine(a, "wheel_inner", "rotation", 0.34, 0.21, 1)
	_neutral_all(a)
	return a


# ===================== 八式 =====================

## 风灾·裂云步：整个人向前压，手诀向后收再前指，风环顺转一圈。
func _make_step() -> Animation:
	var a := _skill_anim("step")
	_pose(a, "step", Vector2(-24.0, 14.0), Vector2(52.0, -16.0), -0.14, 0.22,
		-0.18, 0.12, Vector2(1.06, 0.92), Vector3(1.2, -0.8, 0.9))
	return a


## 风灾·断空斩：躯干大幅反拧，手从内向外横抹；三环反向错开。
func _make_slash() -> Animation:
	var a := _skill_anim("slash")
	_pose(a, "slash", Vector2(-34.0, 9.0), Vector2(46.0, -10.0), -0.26, 0.30,
		0.20, -0.24, Vector2(1.08, 0.90), Vector3(-1.2, 0.9, -1.0))
	return a


## 火灾·焚天印：手印向前推，身体后坐；火环正转，像把印按进空气里。
func _make_fire_seal() -> Animation:
	var a := _skill_anim("fire_seal")
	_pose(a, "fire_seal", Vector2(-16.0, 12.0), Vector2(30.0, -8.0), -0.10, 0.16,
		-0.22, 0.20, Vector2(1.05, 0.94), Vector3(1.2, 0.9, -0.8), a.length)
	return a


## 火灾·燎原：手向下压，身体下沉；环先慢后快，火从脚下铺开。
func _make_fire_field() -> Animation:
	var a := _skill_anim("fire_field")
	_pose(a, "fire_field", Vector2(-12.0, -16.0), Vector2(14.0, 26.0), -0.06, 0.10,
		-0.12, 0.22, Vector2(0.95, 1.08), Vector3(0.9, 1.2, -0.7), a.length)
	return a


## 雷灾·引雷诀：手指天，身体拔高；雷环反向急转，像把天上的雷拧下来。
func _make_thunder_strike() -> Animation:
	var a := _skill_anim("thunder_strike")
	_pose(a, "thunder_strike", Vector2(0.0, -26.0), Vector2(10.0, 14.0), 0.05, -0.10,
		0.12, -0.25, Vector2(0.94, 1.09), Vector3(-1.2, 1.0, -1.2), a.length)
	return a


## 雷灾·雷池：环被猛地拽偏，然后在判定帧卡死 —— 对应「锁灾」，环不转了。
func _make_thunder_pool() -> Animation:
	var a := _skill_anim("thunder_pool")
	var t_hit := _hit_time("thunder_pool")
	var t_free := minf(t_hit + a.length * 0.12, a.length - 0.01)
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b], [t_hit * 0.55, b + Vector2(-12.0, -14.0)], [t_hit, b + Vector2(18.0, 26.0)],
		[t_free, b + Vector2(18.0, 26.0)], [a.length, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [t_hit * 0.55, -0.12], [t_hit, 0.16],
		[t_free, 0.16], [a.length, 0.0],
	])
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE], [t_hit * 0.55, Vector2(1.04, 0.95)],
		[t_hit, Vector2(0.96, 1.05)], [t_free, Vector2(0.96, 1.05)],
		[a.length, Vector2.ONE],
	])
	_add_keys(a, "hand_cast", "rotation", [
		[0.0, 0.0], [t_hit * 0.55, -0.20], [t_hit, 0.22],
		[t_free, 0.22], [a.length, 0.0],
	])
	for part in ["wheel_outer", "wheel_mid", "wheel_inner"]:
		_add_keys(a, part, "rotation", [
			[0.0, 0.0], [t_hit * 0.62, 0.42], [t_hit, 0.0],
			[t_free, 0.0], [a.length, 0.0],
		])
	return a


## 三灾轮转：三环一快一慢一反向地转，身体跟着拧半圈再回正 —— 这一招的辨识度全在轮上。
func _make_turn() -> Animation:
	var a := _skill_anim("turn")
	_pose(a, "turn", Vector2(-30.0, -12.0), Vector2(42.0, 8.0), -0.30, 0.32,
		0.18, -0.22, Vector2(1.08, 0.92), Vector3(1.2, -1.1, 2.0), a.length)
	return a


## 万劫归一：双手举天、三环同向急转 → 判定帧猛砸，环全部收力。
func _make_final() -> Animation:
	var a := _skill_anim("final")
	_pose(a, "final", Vector2(-18.0, -30.0), Vector2(26.0, 24.0), -0.22, 0.26,
		0.08, -0.25, Vector2(0.92, 1.10), Vector3(2.0, 2.0, 2.0), a.length)
	# 环在最后同时涨一圈，把「三灾一起落下」的重量压出来
	for part in ["wheel_outer", "wheel_mid", "wheel_inner"]:
		_add_keys(a, part, "scale", [
			[0.0, Vector2.ONE],
			[a.length * 0.72, Vector2(1.12, 1.12)],
			[a.length, Vector2.ONE],
		])
	return a
