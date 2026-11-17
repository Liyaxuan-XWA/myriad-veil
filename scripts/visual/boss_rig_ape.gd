class_name BossRigApe
extends BossRig
## 青岚古猿的正面骨骼动画集（2026-10-29）。
##
## 分件：body（躯干+头+肩甲）├ arm_l / arm_r（肘下前臂+手）└ lower（髋下双腿+脚）。
## 正面视角没有「左右腿前后走」这回事：idle/walk 用**重心起伏 + 双臂摆动 + 下半身侧摆**
## 表达重量，避免把正面立绘硬掰成侧视步态。
##
## 招式名与 SecretWorldDB.CORE_SKILLS 的 `anim` 字段一一对应；
## 换动作只改这里，玩法代码不认具体招名。

const A_IDLE_CYCLE := 3.6
const A_WALK_CYCLE := 0.95
## 整体动作幅度（2D 刚体件：先保证看得见，再按实机收）
const A_BODY_MOTION := 2.0
const A_BODY_ROT := 2.0
const A_SCALE_MOTION := 1.4
const A_LIMB_MOTION := 1.8

const A_SKILLS := {
	"slam": 0.85,
	"throw": 0.70,
	"volley": 0.85,
	"quake": 0.95,
	"orb": 0.80,
	"attack": 0.55,
}


func _skill_ids() -> Array:
	return A_SKILLS.keys()


func _make_loop(length: float) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR
	return a


func _make_one(length: float) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_NONE
	return a


func _make_idle() -> Animation:
	var a := _make_loop(A_IDLE_CYCLE)
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b], [1.8, b + Vector2(0.0, 1.8)], [3.6, b],
	])
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE], [1.8, Vector2(1.006, 0.994)], [3.6, Vector2.ONE],
	])
	_add_keys(a, "arm_l", "rotation", [
		[0.0, 0.0], [1.8, -0.014], [3.6, 0.0],
	])
	_add_keys(a, "arm_r", "rotation", [
		[0.0, 0.0], [1.8, 0.014], [3.6, 0.0],
	])
	_add_keys(a, "lower", "rotation", [
		[0.0, 0.0], [1.8, 0.002], [3.6, 0.0],
	])
	return a


func _make_walk() -> Animation:
	var a := _make_loop(A_WALK_CYCLE)
	var b := _body_rest()
	# 正面走路：两次起伏 + 左右重心交替；没有「左右腿前后迈」的侧视逻辑
	_add_keys(a, "body", "position", [
		[0.0, b], [0.24, b + Vector2(2.0, 6.0)], [0.48, b],
		[0.72, b + Vector2(-2.0, 6.0)], [0.95, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [0.24, 0.018], [0.50, 0.0], [0.76, -0.018], [0.95, 0.0],
	])
	_add_keys(a, "lower", "rotation", [
		[0.0, 0.0], [0.24, -0.030], [0.50, 0.0], [0.76, 0.030], [0.95, 0.0],
	])
	_add_keys(a, "arm_l", "rotation", [
		[0.0, 0.0], [0.24, 0.080], [0.50, 0.0], [0.76, -0.080], [0.95, 0.0],
	])
	_add_keys(a, "arm_r", "rotation", [
		[0.0, 0.0], [0.24, -0.080], [0.50, 0.0], [0.76, 0.080], [0.95, 0.0],
	])
	return a


func _make_skill(anim: String) -> Animation:
	var a := _make_one(float(A_SKILLS.get(anim, 0.7)))
	match anim:
		"slam":
			_ape_slam(a)
		"throw":
			_ape_throw(a)
		"volley":
			_ape_volley(a)
		"quake":
			_ape_quake(a)
		"orb":
			_ape_orb(a)
		_:
			_ape_attack(a)
	match anim:
		"slam", "throw", "quake", "orb":
			_retime_impact(a, 0.68 if anim == "slam" or anim == "quake" else (0.60 if anim == "throw" else 0.62), 0.84)
		"attack":
			_retime_impact(a, 0.46, 0.85)
	return a


## 非躯干部件的旋转统一放大：分件是正面视角，小角度在 0.25 显示下几乎看不见
func _add_keys(a: Animation, node: String, prop: String, keys: Array) -> void:
	if prop == "rotation" and node != "body":
		var out: Array = []
		for k in keys:
			out.append([k[0], float(k[1]) * A_LIMB_MOTION])
		super._add_keys(a, node, prop, out)
		return
	super._add_keys(a, node, prop, keys)


## 把「设计上的打击帧」对齐到实际判定时刻：
## play_one_shot 把动画压进 windup+0.15，判定在 windup / (windup+0.15) ≈ 0.84。
## 不做这个映射时，骨骼会在判定前 0.1~0.2 秒就打完，像空挥。
func _retime_impact(a: Animation, old_hit_frac: float, new_hit_frac: float) -> void:
	var L := a.length
	var old_t := old_hit_frac * L
	var new_t := new_hit_frac * L
	for ti in range(a.get_track_count()):
		var times: Array = []
		var vals: Array = []
		for ki in range(a.track_get_key_count(ti)):
			times.append(a.track_get_key_time(ti, ki))
			vals.append(a.track_get_key_value(ti, ki))
		for ki in range(a.track_get_key_count(ti) - 1, -1, -1):
			a.track_remove_key(ti, ki)
		for i in range(times.size()):
			var t := float(times[i])
			var nt := 0.0
			if t <= old_t:
				nt = (t / old_t) * new_t
			else:
				nt = new_t + (t - old_t) / maxf(L - old_t, 0.001) * (L - new_t)
			a.track_insert_key(ti, nt, vals[i])


func _body_keys(a: Animation, b: Vector2, keys: Array, scale_keys: Array,
		rot_keys: Array) -> void:
	var pos: Array = []
	for k in keys:
		pos.append([float(k[0]) * a.length, b + (k[1] as Vector2) * A_BODY_MOTION])
	var scl: Array = []
	for k in scale_keys:
		scl.append([float(k[0]) * a.length, Vector2.ONE + ((k[1] as Vector2) - Vector2.ONE) * A_SCALE_MOTION])
	var rot: Array = []
	for k in rot_keys:
		rot.append([float(k[0]) * a.length, float(k[1]) * A_BODY_ROT])
	_add_keys(a, "body", "position", pos)
	_add_keys(a, "body", "scale", scl)
	_add_keys(a, "body", "rotation", rot)


## 双拳砸地：躯干后拉 → 双臂抬起 → 砸下压扁 → 定格 → 回收
func _ape_slam(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.36, Vector2(0, -9)], [0.55, Vector2(0, -12)],
		 [0.60, Vector2(0, -12)], [0.68, Vector2(0, 15)], [0.86, Vector2(0, 12)],
		 [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.36, Vector2(1.02, 0.97)], [0.60, Vector2(1.04, 0.95)],
		 [0.68, Vector2(1.08, 0.89)], [0.86, Vector2(1.06, 0.92)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.36, -0.020], [0.60, -0.024], [0.68, 0.028], [0.86, 0.022], [1.0, 0.0]])
	_add_keys(a, "arm_l", "rotation", [
		[0.0, 0.0], [0.36, -0.10], [0.55, -0.16], [0.60, -0.16],
		[0.68, 0.10], [0.86, 0.08], [1.0, 0.0],
	])
	_add_keys(a, "arm_r", "rotation", [
		[0.0, 0.0], [0.36, 0.10], [0.55, 0.16], [0.60, 0.16],
		[0.68, -0.10], [0.86, -0.08], [1.0, 0.0],
	])
	_add_keys(a, "lower", "rotation", [
		[0.0, 0.0], [0.55, -0.010], [0.68, 0.014], [0.86, 0.010], [1.0, 0.0],
	])


## 掷石：上身拧转 → 右臂后拉 → 前送
func _ape_throw(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(-5, 3)], [0.48, Vector2(-8, 4)],
		 [0.60, Vector2(7, -3)], [0.78, Vector2(10, -1)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.48, Vector2(1.02, 0.98)], [0.60, Vector2(0.98, 1.03)],
		 [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, -0.030], [0.48, -0.045], [0.60, 0.045], [0.78, 0.030], [1.0, 0.0]])
	_add_keys(a, "arm_r", "rotation", [
		[0.0, 0.0], [0.30, 0.10], [0.48, 0.18], [0.60, -0.20],
		[0.78, -0.16], [1.0, 0.0],
	])
	_add_keys(a, "arm_l", "rotation", [
		[0.0, 0.0], [0.48, -0.05], [0.60, 0.06], [1.0, 0.0],
	])
	_add_keys(a, "lower", "rotation", [
		[0.0, 0.0], [0.48, 0.008], [0.60, -0.012], [1.0, 0.0],
	])


## 乱石飞掷：上身左右急甩，双臂交叉抛
func _ape_volley(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.16, Vector2(-9, 2)], [0.30, Vector2(9, 2)],
		 [0.44, Vector2(-7, 1)], [0.58, Vector2(8, 1)], [0.74, Vector2.ZERO],
		 [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.30, Vector2(1.02, 0.98)], [0.58, Vector2(1.02, 0.98)],
		 [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.16, -0.045], [0.30, 0.045], [0.44, -0.035], [0.58, 0.040],
		 [0.74, 0.0], [1.0, 0.0]])
	_add_keys(a, "arm_l", "rotation", [
		[0.0, 0.0], [0.16, 0.10], [0.30, -0.12], [0.44, 0.10], [0.58, -0.10],
		[0.74, 0.0], [1.0, 0.0],
	])
	_add_keys(a, "arm_r", "rotation", [
		[0.0, 0.0], [0.16, -0.10], [0.30, 0.12], [0.44, -0.10], [0.58, 0.10],
		[0.74, 0.0], [1.0, 0.0],
	])
	_add_keys(a, "lower", "rotation", [
		[0.0, 0.0], [0.30, -0.010], [0.58, 0.010], [1.0, 0.0],
	])


## 山崩地裂：比 slam 更大的后拉、更深的压扁、两次余震
func _ape_quake(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.34, Vector2(0, -12)], [0.54, Vector2(0, -16)],
		 [0.60, Vector2(0, -16)], [0.68, Vector2(0, 20)], [0.78, Vector2(0, 16)],
		 [0.86, Vector2(0, 19)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.34, Vector2(1.03, 0.96)], [0.60, Vector2(1.05, 0.94)],
		 [0.68, Vector2(1.10, 0.87)], [0.78, Vector2(1.07, 0.91)],
		 [0.86, Vector2(1.09, 0.89)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.34, -0.028], [0.60, -0.032], [0.68, 0.036],
		 [0.78, 0.026], [0.86, 0.032], [1.0, 0.0]])
	_add_keys(a, "arm_l", "rotation", [
		[0.0, 0.0], [0.34, -0.12], [0.54, -0.20], [0.60, -0.20],
		[0.68, 0.14], [0.86, 0.14], [1.0, 0.0],
	])
	_add_keys(a, "arm_r", "rotation", [
		[0.0, 0.0], [0.34, 0.12], [0.54, 0.20], [0.60, 0.20],
		[0.68, -0.14], [0.86, -0.14], [1.0, 0.0],
	])
	_add_keys(a, "lower", "rotation", [
		[0.0, 0.0], [0.54, -0.012], [0.68, 0.018], [0.86, 0.018], [1.0, 0.0],
	])


## 青岚灵爆：收拢双掌 → 前送；躯干先压紧再拉长
func _ape_orb(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(-4, 3)], [0.50, Vector2(-6, 5)],
		 [0.62, Vector2(9, -4)], [0.78, Vector2(12, -2)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.30, Vector2(1.02, 0.98)], [0.50, Vector2(1.04, 0.95)],
		 [0.62, Vector2(0.96, 1.06)], [0.78, Vector2(0.98, 1.02)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, -0.020], [0.50, -0.026], [0.62, 0.028], [0.78, 0.020], [1.0, 0.0]])
	# 双掌向胸前收 → 向前推出
	_add_keys(a, "arm_l", "rotation", [
		[0.0, 0.0], [0.30, 0.08], [0.50, 0.12], [0.62, -0.12], [0.78, -0.08], [1.0, 0.0],
	])
	_add_keys(a, "arm_r", "rotation", [
		[0.0, 0.0], [0.30, -0.08], [0.50, -0.12], [0.62, 0.12], [0.78, 0.08], [1.0, 0.0],
	])
	_add_keys(a, "lower", "rotation", [
		[0.0, 0.0], [0.50, -0.006], [0.62, 0.010], [1.0, 0.0],
	])


## 平A：短促前压 + 右臂横扫
func _ape_attack(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.28, Vector2(-4, 2)], [0.46, Vector2(9, -2)],
		 [0.62, Vector2(7, 0)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.28, Vector2(1.02, 0.98)], [0.46, Vector2(0.98, 1.03)],
		 [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.28, -0.024], [0.46, 0.026], [0.62, 0.018], [1.0, 0.0]])
	_add_keys(a, "arm_r", "rotation", [
		[0.0, 0.0], [0.28, 0.10], [0.46, -0.18], [0.62, -0.12], [1.0, 0.0],
	])
	_add_keys(a, "arm_l", "rotation", [
		[0.0, 0.0], [0.28, -0.04], [0.46, 0.05], [1.0, 0.0],
	])
