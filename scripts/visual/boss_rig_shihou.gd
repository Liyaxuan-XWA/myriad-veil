class_name BossRigShihou
extends BossRig
## 镇墟石犼的 3/4 侧视骨骼动画集（2026-10-31）。
##
## 分件：body（躯干+胸口鬼火）├ head（头+碑石鬃+封眼石带）
##       ├ tail（石槌尾）
##       ├ leg_front_near / leg_front_far（近前 / 远前）
##       └ leg_rear_near / leg_rear_far（近后 / 远后）
##
## 侧视四足：躯干的前后位移读作「扑/退」，俯仰读作「抬头/低头」，
## 招式名与 SecretWorldDB.CORE_SKILLS_YUANYING 的 `anim` 字段一一对应。

const S_IDLE_CYCLE := 3.8
const S_WALK_CYCLE := 1.15
const S_BODY_MOTION := 2.4
const S_BODY_ROT := 2.0
const S_SCALE_MOTION := 1.4
const S_LIMB_MOTION := 1.2

const S_SKILLS := {
	"pounce": 0.82,
	"claw": 0.62,
	"slam": 0.86,
	"breath": 0.95,
	"tail_sweep": 0.72,
	"phase2": 1.35,
	"echo": 1.10,
	"charge": 1.05,
	"swipe": 0.55,
	"attack": 0.58,
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


func _body_keys(a: Animation, b: Vector2, keys: Array, scale_keys: Array,
		rot_keys: Array) -> void:
	var pos: Array = []
	for k in keys:
		pos.append([float(k[0]) * a.length, b + (k[1] as Vector2) * S_BODY_MOTION])
	var scl: Array = []
	for k in scale_keys:
		scl.append([float(k[0]) * a.length,
			Vector2.ONE + ((k[1] as Vector2) - Vector2.ONE) * S_SCALE_MOTION])
	var rot: Array = []
	for k in rot_keys:
		rot.append([float(k[0]) * a.length, float(k[1]) * S_BODY_ROT])
	_add_keys(a, "body", "position", pos)
	_add_keys(a, "body", "scale", scl)
	_add_keys(a, "body", "rotation", rot)


func _leg_keys(a: Animation, part: String, keys: Array) -> void:
	var out: Array = []
	for k in keys:
		out.append([float(k[0]) * a.length, float(k[1]) * S_LIMB_MOTION])
	_add_keys(a, part, "rotation", out)


func _make_idle() -> Animation:
	var a := _make_loop(S_IDLE_CYCLE)
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b], [1.9, b + Vector2(0.0, 2.0)], [3.8, b],
	])
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE], [1.9, Vector2(1.003, 0.997)], [3.8, Vector2.ONE],
	])
	# 耳朵/头始终在听：小幅左右扫
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.9, -0.010], [1.9, 0.006], [2.9, 0.012], [3.8, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [1.3, 0.035], [2.6, -0.030], [3.8, 0.0],
	])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [1.9, 0.004], [3.8, 0.0]])
	return a


func _make_walk() -> Animation:
	var a := _make_loop(S_WALK_CYCLE)
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b], [0.28, b + Vector2(1.5, 5.5)], [0.56, b],
		[0.84, b + Vector2(-1.5, 5.5)], [1.15, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [0.28, 0.014], [0.56, 0.0], [0.84, -0.014], [1.15, 0.0],
	])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.28, -0.010], [0.56, 0.0], [0.84, 0.010], [1.15, 0.0],
	])
	_leg_keys(a, "leg_front_near", [
		[0.0, 0.0], [0.28, 0.055], [0.56, 0.0], [0.84, -0.048], [1.15, 0.0]])
	_leg_keys(a, "leg_front_far", [
		[0.0, 0.0], [0.28, -0.045], [0.56, 0.0], [0.84, 0.052], [1.15, 0.0]])
	_leg_keys(a, "leg_rear_near", [
		[0.0, 0.0], [0.28, -0.048], [0.56, 0.0], [0.84, 0.055], [1.15, 0.0]])
	_leg_keys(a, "leg_rear_far", [
		[0.0, 0.0], [0.28, 0.038], [0.56, 0.0], [0.84, -0.040], [1.15, 0.0]])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.3, 0.045], [0.6, 0.0], [0.9, -0.045], [1.15, 0.0],
	])
	return a


func _make_skill(anim: String) -> Animation:
	var a := _make_one(float(S_SKILLS.get(anim, 0.7)))
	match anim:
		"pounce":
			_shihou_pounce(a)
		"claw":
			_shihou_claw(a)
		"slam":
			_shihou_slam(a)
		"breath":
			_shihou_breath(a)
		"tail_sweep":
			_shihou_tail_sweep(a)
		"phase2":
			_shihou_phase2(a)
		"echo":
			_shihou_echo(a)
		"charge":
			_shihou_charge(a)
		"swipe":
			_shihou_swipe(a)
		_:
			_shihou_attack(a)
	return a


## 盲扑：伏低 → 前扑 → 落地定住 → 回收
func _shihou_pounce(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.26, Vector2(-16, 8)], [0.40, Vector2(-20, 10)],
		 [0.53, Vector2(26, -4)], [0.62, Vector2(26, -4)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.40, Vector2(1.04, 0.94)], [0.53, Vector2(0.95, 1.06)],
		 [0.62, Vector2(0.95, 1.06)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.26, -0.020], [0.40, -0.030], [0.53, 0.050],
		 [0.62, 0.050], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.26, -0.040], [0.40, -0.055], [0.53, 0.065],
		[0.62, 0.065], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [0.26, 0.12], [0.40, 0.16],
		[0.53, -0.22], [0.62, -0.22], [1.0, 0.0]])
	_leg_keys(a, "leg_front_far", [[0.0, 0.0], [0.40, 0.10],
		[0.53, -0.16], [1.0, 0.0]])
	_leg_keys(a, "leg_rear_near", [[0.0, 0.0], [0.40, -0.14],
		[0.53, 0.12], [1.0, 0.0]])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.26, -0.06], [0.53, 0.12], [0.62, 0.10], [1.0, 0.0],
	])


## 裂石爪：三次前爪横抓，身体每次前顶
func _shihou_claw(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.15, Vector2(-7, 2)], [0.25, Vector2(15, -2)],
		 [0.31, Vector2(15, -2)], [0.40, Vector2(-5, 1)], [0.50, Vector2(19, -3)],
		 [0.56, Vector2(19, -3)], [0.65, Vector2(-5, 1)], [0.75, Vector2(23, -4)],
		 [0.82, Vector2(23, -4)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.25, Vector2(0.98, 1.03)], [0.50, Vector2(0.98, 1.03)],
		 [0.75, Vector2(0.97, 1.04)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.15, -0.020], [0.25, 0.036], [0.31, 0.036],
		 [0.40, -0.016], [0.50, 0.040], [0.56, 0.040], [0.65, -0.016],
		 [0.75, 0.046], [0.82, 0.046], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.15, -0.045], [0.25, 0.055], [0.31, 0.055],
		[0.40, -0.040], [0.50, 0.060], [0.56, 0.060], [0.65, -0.040],
		[0.75, 0.065], [0.82, 0.065], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [0.25, -0.11], [0.50, -0.13],
		[0.75, -0.15], [0.82, -0.15], [1.0, 0.0]])
	_leg_keys(a, "leg_front_far", [[0.0, 0.0], [0.25, -0.07], [0.50, -0.09],
		[0.75, -0.11], [1.0, 0.0]])


## 震地：抬身 → 前爪悬空 → 砸地（躯干下压 + 纵向挤压）
func _shihou_slam(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(0, -16)], [0.45, Vector2(2, -19)],
		 [0.54, Vector2(0, 12)], [0.62, Vector2(0, 12)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.30, Vector2(0.98, 1.04)], [0.45, Vector2(0.96, 1.06)],
		 [0.54, Vector2(1.07, 0.91)], [0.62, Vector2(1.07, 0.91)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, -0.038], [0.45, -0.050], [0.54, 0.034],
		 [0.62, 0.034], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, -0.045], [0.45, -0.058], [0.54, 0.045],
		[0.62, 0.045], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [0.30, -0.20], [0.45, -0.25],
		[0.54, 0.12], [0.62, 0.12], [1.0, 0.0]])
	_leg_keys(a, "leg_front_far", [[0.0, 0.0], [0.30, -0.12], [0.45, -0.16],
		[0.54, 0.08], [1.0, 0.0]])
	_leg_keys(a, "leg_rear_near", [[0.0, 0.0], [0.45, 0.07], [0.54, -0.05], [1.0, 0.0]])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, -0.05], [0.54, 0.10], [1.0, 0.0],
	])


## 闻声吐息：仰头听 → 鬃毛张开 → 向前吐尘
func _shihou_breath(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.28, Vector2(-8, -10)], [0.48, Vector2(-10, -14)],
		 [0.66, Vector2(6, -4)], [0.76, Vector2(6, -4)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.28, Vector2(1.02, 1.01)], [0.48, Vector2(1.055, 1.02)],
		 [0.66, Vector2(1.02, 1.01)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.28, -0.034], [0.48, -0.050], [0.66, 0.020], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.28, -0.095], [0.48, -0.140], [0.60, -0.105],
		[0.66, -0.020], [0.76, 0.015], [1.0, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, 0.05], [0.55, -0.04], [0.80, 0.05], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [0.28, -0.06], [0.48, -0.09],
		[0.66, -0.04], [1.0, 0.0]])


## 石尾扫：身体先向一侧拧，尾巴横扫；后腿撑住
func _shihou_tail_sweep(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.32, Vector2(8, 4)], [0.48, Vector2(10, 5)],
		 [0.62, Vector2(-6, 2)], [0.78, Vector2(-4, 1)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.32, Vector2(1.02, 0.98)], [0.48, Vector2(1.03, 0.97)],
		 [0.62, Vector2(0.99, 1.01)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.32, 0.030], [0.48, 0.040], [0.62, -0.045], [1.0, 0.0]])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, -0.12], [0.46, -0.18], [0.56, 0.20],
		[0.70, 0.24], [1.0, 0.0],
	])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.32, 0.045], [0.56, -0.060], [1.0, 0.0],
	])
	_leg_keys(a, "leg_rear_near", [[0.0, 0.0], [0.32, -0.10], [0.56, 0.12], [1.0, 0.0]])
	_leg_keys(a, "leg_rear_far", [[0.0, 0.0], [0.32, 0.08], [0.56, -0.09], [1.0, 0.0]])


## 二阶段破封：仰头长吼，鬃毛整体张开；封眼石带的裂缝由 FX 叠
func _shihou_phase2(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(-10, -12)], [0.55, Vector2(-12, -16)],
		 [0.78, Vector2(-12, -16)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.30, Vector2(1.02, 1.02)], [0.55, Vector2(1.06, 1.04)],
		 [0.78, Vector2(1.06, 1.04)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, -0.040], [0.55, -0.060], [0.78, -0.060], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, -0.12], [0.55, -0.18], [0.72, -0.11],
		[0.82, -0.18], [1.0, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, 0.06], [0.62, -0.05], [0.82, 0.08], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [0.30, -0.10], [0.55, -0.15],
		[0.78, -0.08], [1.0, 0.0]])


## 回声定位：站定、头低下来听，鬃毛细颤
func _shihou_echo(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.20, Vector2(0, 3)], [0.40, Vector2(0, 4)],
		 [0.60, Vector2(0, 3)], [0.80, Vector2(0, 5)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.20, Vector2(1.008, 0.996)], [0.40, Vector2(1.012, 0.992)],
		 [0.60, Vector2(1.008, 0.996)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.20, 0.010], [0.40, -0.008], [0.60, 0.010], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.16, 0.040], [0.28, -0.020], [0.42, 0.050],
		[0.56, -0.020], [0.70, 0.040], [1.0, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, 0.020], [0.60, -0.020], [1.0, 0.0],
	])


## 崩山撞：深蹲蓄力 → 身压得极低 → 长冲 → 收
func _shihou_charge(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(-20, 9)], [0.46, Vector2(-24, 11)],
		 [0.62, Vector2(38, -3)], [0.72, Vector2(38, -3)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.46, Vector2(1.05, 0.93)], [0.62, Vector2(0.93, 1.08)],
		 [0.72, Vector2(0.93, 1.08)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, -0.026], [0.46, -0.040], [0.62, 0.060],
		 [0.72, 0.060], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, -0.055], [0.46, -0.080], [0.62, 0.075],
		[0.72, 0.075], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [0.30, 0.16], [0.46, 0.20],
		[0.62, -0.26], [0.72, -0.26], [1.0, 0.0]])
	_leg_keys(a, "leg_front_far", [[0.0, 0.0], [0.46, 0.14],
		[0.62, -0.18], [1.0, 0.0]])
	_leg_keys(a, "leg_rear_near", [[0.0, 0.0], [0.46, -0.18],
		[0.62, 0.14], [1.0, 0.0]])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, -0.08], [0.62, 0.14], [0.72, 0.10], [1.0, 0.0],
	])


func _shihou_swipe(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(-8, 1)], [0.44, Vector2(-8, 1)],
		 [0.52, Vector2(12, -1)], [0.60, Vector2(12, -1)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.44, Vector2(1.01, 0.99)], [0.52, Vector2(0.99, 1.02)],
		 [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, 0.012], [0.44, 0.012], [0.52, -0.014], [1.0, 0.0]])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [0.30, -0.16], [0.44, -0.18],
		[0.52, 0.14], [0.60, 0.14], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, -0.020], [0.52, 0.026], [1.0, 0.0],
	])


func _shihou_attack(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.28, Vector2(-10, 2)], [0.42, Vector2(-10, 2)],
		 [0.52, Vector2(16, -2)], [0.62, Vector2(16, -2)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.42, Vector2(1.02, 0.98)], [0.52, Vector2(0.98, 1.02)],
		 [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.28, -0.018], [0.42, -0.018], [0.52, 0.030], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.28, -0.035], [0.42, -0.035], [0.52, 0.045], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front_near", [[0.0, 0.0], [0.42, 0.10], [0.52, -0.16], [1.0, 0.0]])
