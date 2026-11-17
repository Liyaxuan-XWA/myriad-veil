class_name BossRigStag
extends BossRig
## 云隐苍角的正面骨骼动画集（2026-10-29）。
##
## 分件：body（躯干+苔披）├ head（颈+头+巨角）└ leg_bl / leg_br / leg_fl / leg_fr。
## 四足正面视角：idle/walk 用躯干起伏 + 左右重心的轻微交替 + 前腿小摆；
## 招式以**躯干俯仰/前后位移**为主，头角只做小角度（巨角放大 1° 已经很显眼）。
##
## 招式名与 SecretWorldDB.CORE_SKILLS_ZHUJI 的 `anim` 字段一一对应。

const S_IDLE_CYCLE := 3.8
const S_WALK_CYCLE := 1.0
## 整体动作幅度（2D 刚体件：先保证看得见，再按实机收）
const S_BODY_MOTION := 2.0
const S_BODY_ROT := 2.0
const S_SCALE_MOTION := 1.4
const S_LIMB_MOTION := 1.5

const S_SKILLS := {
	"gore": 0.78,
	"stomp": 0.80,
	"mist": 0.90,
	"roots": 0.90,
	"rocks": 0.80,
	"sweep": 0.62,
	"miststep": 0.55,
	"roar": 1.00,
	"attack": 0.55,
}


func _skill_ids() -> Array:
	return S_SKILLS.keys()


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
	var a := _make_loop(S_IDLE_CYCLE)
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b], [1.9, b + Vector2(0.0, 2.0)], [3.8, b],
	])
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE], [1.9, Vector2(1.005, 0.995)], [3.8, Vector2.ONE],
	])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [1.9, -0.007], [3.8, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [1.9, 0.006], [3.8, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [1.9, -0.006], [3.8, 0.0],
	])
	return a


func _make_walk() -> Animation:
	var a := _make_loop(S_WALK_CYCLE)
	var b := _body_rest()
	# 正面四足：两次起伏 + 左右重心交替；前腿小摆、后腿反向支撑
	_add_keys(a, "body", "position", [
		[0.0, b], [0.25, b + Vector2(2.0, 6.0)], [0.50, b],
		[0.75, b + Vector2(-2.0, 6.0)], [1.0, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [0.25, 0.018], [0.50, 0.0], [0.75, -0.018], [1.0, 0.0],
	])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.25, -0.012], [0.50, 0.0], [0.75, 0.012], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.25, 0.080], [0.50, 0.0], [0.75, -0.060], [1.0, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [0.25, -0.060], [0.50, 0.0], [0.75, 0.080], [1.0, 0.0],
	])
	_add_keys(a, "leg_bl", "rotation", [
		[0.0, 0.0], [0.25, -0.050], [0.50, 0.0], [0.75, 0.050], [1.0, 0.0],
	])
	_add_keys(a, "leg_br", "rotation", [
		[0.0, 0.0], [0.25, 0.050], [0.50, 0.0], [0.75, -0.050], [1.0, 0.0],
	])
	return a


func _make_skill(anim: String) -> Animation:
	var a := _make_one(float(S_SKILLS.get(anim, 0.8)))
	match anim:
		"gore":
			_stag_gore(a)
		"stomp":
			_stag_stomp(a)
		"mist":
			_stag_mist(a)
		"roots":
			_stag_roots(a)
		"rocks":
			_stag_rocks(a)
		"sweep":
			_stag_sweep(a)
		"miststep":
			_stag_miststep(a)
		"roar":
			_stag_roar(a)
		_:
			_stag_attack(a)
	match anim:
		"gore", "stomp", "mist", "sweep", "miststep":
			_retime_impact(a,
				0.66 if anim == "gore" or anim == "stomp" else
				(0.62 if anim == "mist" else (0.58 if anim == "sweep" else 0.52)), 0.84)
		"attack":
			_retime_impact(a, 0.46, 0.85)
	return a


## 非躯干部件的旋转统一放大：分件是正面视角，小角度在 0.25 显示下几乎看不见
func _add_keys(a: Animation, node: String, prop: String, keys: Array) -> void:
	if prop == "rotation" and node != "body":
		var out: Array = []
		for k in keys:
			out.append([k[0], float(k[1]) * S_LIMB_MOTION])
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
		pos.append([float(k[0]) * a.length, b + (k[1] as Vector2) * S_BODY_MOTION])
	var scl: Array = []
	for k in scale_keys:
		scl.append([float(k[0]) * a.length, Vector2.ONE + ((k[1] as Vector2) - Vector2.ONE) * S_SCALE_MOTION])
	var rot: Array = []
	for k in rot_keys:
		rot.append([float(k[0]) * a.length, float(k[1]) * S_BODY_ROT])
	_add_keys(a, "body", "position", pos)
	_add_keys(a, "body", "scale", scl)
	_add_keys(a, "body", "rotation", rot)


## 角撞：后坐蓄力 → 前冲低头 → 定格 → 回正
func _stag_gore(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.32, Vector2(-10, 3)], [0.50, Vector2(-14, 4)],
		 [0.56, Vector2(-14, 4)], [0.66, Vector2(24, -4)], [0.82, Vector2(22, -3)],
		 [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.50, Vector2(1.03, 0.97)], [0.66, Vector2(0.96, 1.05)],
		 [0.82, Vector2(0.98, 1.02)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.32, -0.018], [0.50, -0.024], [0.66, 0.030],
		 [0.82, 0.024], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.32, -0.012], [0.50, -0.020], [0.66, 0.040],
		[0.82, 0.032], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.50, -0.030], [0.66, 0.030], [0.82, 0.020], [1.0, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [0.50, -0.030], [0.66, 0.030], [0.82, 0.020], [1.0, 0.0],
	])


## 踏地：前身抬起 → 前蹄下砸 + 躯干压扁
func _stag_stomp(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.32, Vector2(0, -8)], [0.52, Vector2(0, -12)],
		 [0.58, Vector2(0, -12)], [0.66, Vector2(0, 12)], [0.84, Vector2(0, 9)],
		 [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.32, Vector2(0.99, 1.03)], [0.58, Vector2(1.02, 0.97)],
		 [0.66, Vector2(1.07, 0.91)], [0.84, Vector2(1.04, 0.95)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.32, -0.012], [0.58, -0.018], [0.66, 0.024],
		 [0.84, 0.018], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.32, 0.010], [0.58, 0.016], [0.66, -0.026],
		[0.84, -0.018], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.32, -0.055], [0.58, -0.075], [0.66, 0.030],
		[0.84, 0.020], [1.0, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [0.32, -0.055], [0.58, -0.075], [0.66, 0.030],
		[0.84, 0.020], [1.0, 0.0],
	])


## 雾吐：后仰抬头 → 前探吐雾
func _stag_mist(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.34, Vector2(-6, -6)], [0.54, Vector2(-8, -8)],
		 [0.62, Vector2(14, 2)], [0.80, Vector2(12, 1)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.34, Vector2(1.02, 0.98)], [0.62, Vector2(0.97, 1.04)],
		 [0.80, Vector2(0.99, 1.02)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.34, -0.016], [0.54, -0.022], [0.62, 0.020],
		 [0.80, 0.014], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.34, -0.024], [0.54, -0.032], [0.62, 0.026],
		[0.80, 0.018], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.34, 0.025], [0.62, -0.020], [1.0, 0.0],
	])


## 古根：低头压地，前蹄按住地面
func _stag_roots(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(0, 6)], [0.52, Vector2(0, 10)],
		 [0.70, Vector2(0, 8)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.30, Vector2(1.03, 0.97)], [0.52, Vector2(1.05, 0.95)],
		 [0.70, Vector2(1.02, 0.98)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, 0.018], [0.52, 0.026], [0.70, 0.020], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, 0.020], [0.52, 0.030], [0.70, 0.024], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.30, -0.020], [0.52, -0.030], [0.70, -0.020], [1.0, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [0.30, -0.020], [0.52, -0.030], [0.70, -0.020], [1.0, 0.0],
	])


## 落石：抖角，左右急甩后前送
func _stag_rocks(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.18, Vector2(-7, 1)], [0.30, Vector2(7, 1)],
		 [0.42, Vector2(-5, 0)], [0.54, Vector2(9, -1)], [0.70, Vector2.ZERO],
		 [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.30, Vector2(1.01, 0.99)], [0.54, Vector2(1.02, 0.98)],
		 [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.18, -0.030], [0.30, 0.030], [0.42, -0.024],
		 [0.54, 0.034], [0.70, 0.0], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.18, 0.035], [0.30, -0.035], [0.42, 0.028],
		[0.54, -0.040], [0.70, 0.0], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.30, -0.018], [0.54, 0.018], [1.0, 0.0],
	])


## 角扫：躯干横向急转，巨角跟着扫
func _stag_sweep(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.24, Vector2(-12, 0)], [0.42, Vector2(-16, 0)],
		 [0.48, Vector2(-16, 0)], [0.58, Vector2(18, -2)], [0.74, Vector2(14, -1)],
		 [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.42, Vector2(1.02, 0.98)], [0.58, Vector2(0.97, 1.04)],
		 [0.74, Vector2(0.99, 1.02)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.24, -0.040], [0.42, -0.060], [0.48, -0.060],
		 [0.58, 0.080], [0.74, 0.055], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.24, 0.030], [0.42, 0.045], [0.48, 0.045],
		[0.58, -0.060], [0.74, -0.042], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.42, -0.030], [0.58, 0.030], [1.0, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [0.42, 0.030], [0.58, -0.030], [1.0, 0.0],
	])


## 雾步：侧身压步 → 从侧后撞出
func _stag_miststep(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.26, Vector2(-8, 3)], [0.44, Vector2(-10, 5)],
		 [0.52, Vector2(18, -3)], [0.70, Vector2(15, -2)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.44, Vector2(1.03, 0.97)], [0.52, Vector2(0.96, 1.05)],
		 [0.70, Vector2(0.98, 1.02)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.26, -0.030], [0.44, -0.042], [0.52, 0.040],
		 [0.70, 0.030], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.26, -0.020], [0.44, -0.030], [0.52, 0.035],
		[0.70, 0.025], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.44, -0.025], [0.52, 0.030], [1.0, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [0.44, -0.025], [0.52, 0.030], [1.0, 0.0],
	])


## 鹿鸣：仰首，躯干后拉并拉长，四腿撑住
func _stag_roar(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(0, -8)], [0.52, Vector2(0, -14)],
		 [0.74, Vector2(0, -12)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.30, Vector2(1.02, 0.98)], [0.52, Vector2(0.95, 1.07)],
		 [0.74, Vector2(0.98, 1.03)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, -0.018], [0.52, -0.028], [0.74, -0.022], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, -0.040], [0.52, -0.075], [0.74, -0.060], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.30, -0.022], [0.52, -0.030], [1.0, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [0.30, -0.022], [0.52, -0.030], [1.0, 0.0],
	])
	_add_keys(a, "leg_bl", "rotation", [
		[0.0, 0.0], [0.30, 0.015], [0.52, 0.022], [1.0, 0.0],
	])
	_add_keys(a, "leg_br", "rotation", [
		[0.0, 0.0], [0.30, 0.015], [0.52, 0.022], [1.0, 0.0],
	])


## 平A：短促低头前压
func _stag_attack(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.26, Vector2(-6, 2)], [0.46, Vector2(14, -2)],
		 [0.62, Vector2(12, -1)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.26, Vector2(1.02, 0.98)], [0.46, Vector2(0.98, 1.03)],
		 [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.26, -0.014], [0.46, 0.020], [0.62, 0.014], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.26, -0.014], [0.46, 0.034], [0.62, 0.024], [1.0, 0.0],
	])
	_add_keys(a, "leg_fl", "rotation", [
		[0.0, 0.0], [0.26, -0.018], [0.46, 0.018], [1.0, 0.0],
	])
	_add_keys(a, "leg_fr", "rotation", [
		[0.0, 0.0], [0.26, -0.018], [0.46, 0.018], [1.0, 0.0],
	])
