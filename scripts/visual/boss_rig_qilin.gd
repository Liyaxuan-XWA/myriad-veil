class_name BossRigQilin
extends BossRig
## 赤金火麟的 3/4 侧视骨骼动画集（2026-10-29）。
##
## 分件：body（躯干+鬃火）├ head（颈+头+双角）├ tail（火焰尾）
##       └ leg_front / leg_hind / leg_hind_far（近前 / 近后 / 远后）
## 远侧前腿原图整条被近侧挡住，不单独拆。
##
## 侧视与正面鹿的差别：躯干的前后位移读作「扑/退」，俯仰读作「抬头/低头」，
## 所以主力表演放在 x 位移 + rotation，腿只做小摆（关节白缝限制）。
## 招式名与 SecretWorldDB.CORE_SKILLS_JIEDAN 的 `anim` 字段一一对应。

const S_IDLE_CYCLE := 3.6
const S_WALK_CYCLE := 1.05
## 整体动作幅度（画布像素 / 弧度基数；显示时再乘 ArtDB 的 scale 0.25）
const S_BODY_MOTION := 2.2
const S_BODY_ROT := 2.2
const S_SCALE_MOTION := 1.5
const S_LIMB_MOTION := 1.4

const S_SKILLS := {
	"charge": 0.78,
	"stomp": 0.80,
	"rain": 0.95,
	"sunburst": 0.90,
	"combo": 0.62,
	"ring": 0.70,
	"eclipse": 1.30,
	"meteor": 1.50,
	"swipe": 0.55,
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


func _leg_keys(a: Animation, part: String, keys: Array) -> void:
	var out: Array = []
	for k in keys:
		out.append([float(k[0]) * a.length, float(k[1]) * S_LIMB_MOTION])
	_add_keys(a, part, "rotation", out)


func _make_idle() -> Animation:
	var a := _make_loop(S_IDLE_CYCLE)
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b], [1.8, b + Vector2(0.0, 2.4)], [3.6, b],
	])
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE], [1.8, Vector2(1.004, 0.996)], [3.6, Vector2.ONE],
	])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [1.8, -0.008], [2.4, 0.004], [3.6, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [1.2, 0.030], [2.4, -0.026], [3.6, 0.0],
	])
	_add_keys(a, "leg_front", "rotation", [
		[0.0, 0.0], [1.8, 0.006], [3.6, 0.0],
	])
	return a


func _make_walk() -> Animation:
	var a := _make_loop(S_WALK_CYCLE)
	var b := _body_rest()
	# 侧视四足：两次起伏 + 前后重心交替；远近后腿反相
	_add_keys(a, "body", "position", [
		[0.0, b], [0.25, b + Vector2(1.0, 5.0)], [0.50, b],
		[0.75, b + Vector2(-1.0, 5.0)], [1.0, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [0.25, 0.012], [0.50, 0.0], [0.75, -0.012], [1.0, 0.0],
	])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.25, -0.010], [0.50, 0.0], [0.75, 0.010], [1.0, 0.0],
	])
	_add_keys(a, "leg_front", "rotation", [
		[0.0, 0.0], [0.25, 0.060], [0.50, 0.0], [0.75, -0.050], [1.0, 0.0],
	])
	_add_keys(a, "leg_hind", "rotation", [
		[0.0, 0.0], [0.25, -0.050], [0.50, 0.0], [0.75, 0.060], [1.0, 0.0],
	])
	_add_keys(a, "leg_hind_far", "rotation", [
		[0.0, 0.0], [0.25, 0.040], [0.50, 0.0], [0.75, -0.040], [1.0, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.25, 0.040], [0.50, 0.0], [0.75, -0.040], [1.0, 0.0],
	])
	return a


func _make_skill(anim: String) -> Animation:
	var a := _make_one(float(S_SKILLS.get(anim, 0.7)))
	match anim:
		"charge":
			_qilin_charge(a)
		"stomp":
			_qilin_stomp(a)
		"rain":
			_qilin_rain(a)
		"sunburst":
			_qilin_sunburst(a)
		"combo":
			_qilin_combo(a)
		"ring":
			_qilin_ring(a)
		"eclipse":
			_qilin_eclipse(a)
		"meteor":
			_qilin_meteor(a)
		"swipe":
			_qilin_swipe(a)
		_:
			_qilin_attack(a)
	return a


## 裂岩冲：后坐蓄力 → 伏低 → 极速前扑 → 定格 → 回收
func _qilin_charge(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(-14, 4)], [0.44, Vector2(-18, 7)],
		 [0.54, Vector2(24, -3)], [0.61, Vector2(24, -3)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.44, Vector2(1.03, 0.96)], [0.54, Vector2(0.96, 1.05)],
		 [0.61, Vector2(0.96, 1.05)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, -0.020], [0.44, -0.030], [0.54, 0.055],
		 [0.61, 0.055], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, -0.030], [0.44, -0.045], [0.54, 0.060],
		[0.61, 0.060], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front", [[0.0, 0.0], [0.30, 0.10], [0.44, 0.14],
		[0.54, -0.22], [0.61, -0.22], [1.0, 0.0]])
	_leg_keys(a, "leg_hind", [[0.0, 0.0], [0.30, -0.12], [0.44, -0.16],
		[0.54, 0.12], [0.61, 0.12], [1.0, 0.0]])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, -0.06], [0.54, 0.10], [0.61, 0.10], [1.0, 0.0],
	])


## 踏霞·地火：抬身 → 前蹄悬空 → 砸地（躯干下压 + 纵向挤压）
func _qilin_stomp(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(0, -14)], [0.44, Vector2(2, -17)],
		 [0.52, Vector2(0, 10)], [0.60, Vector2(0, 10)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.30, Vector2(0.98, 1.03)], [0.44, Vector2(0.97, 1.05)],
		 [0.52, Vector2(1.06, 0.92)], [0.60, Vector2(1.06, 0.92)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, -0.035], [0.44, -0.045], [0.52, 0.030],
		 [0.60, 0.030], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, -0.040], [0.44, -0.050], [0.52, 0.040],
		[0.60, 0.040], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front", [[0.0, 0.0], [0.30, -0.18], [0.44, -0.22],
		[0.52, 0.10], [0.60, 0.10], [1.0, 0.0]])
	_leg_keys(a, "leg_hind", [[0.0, 0.0], [0.44, 0.06], [0.52, -0.04], [1.0, 0.0]])


## 火雨·焚野：仰头长鸣，鬃火张开（躯干上抬 + 慢慢放大）
func _qilin_rain(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.26, Vector2(-6, -8)], [0.46, Vector2(-8, -12)],
		 [0.72, Vector2(-8, -12)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.26, Vector2(1.02, 1.01)], [0.46, Vector2(1.045, 1.015)],
		 [0.72, Vector2(1.045, 1.015)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.26, -0.028], [0.46, -0.040], [0.72, -0.040], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.26, -0.075], [0.46, -0.105], [0.60, -0.080],
		[0.72, -0.105], [1.0, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, 0.055], [0.55, -0.035], [0.80, 0.045], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front", [[0.0, 0.0], [0.26, -0.06], [0.46, -0.09],
		[0.72, -0.06], [1.0, 0.0]])


## 阳炎·流火：伏低盘身，光球在腹前凝成 → 挺身推出
func _qilin_sunburst(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.32, Vector2(-8, 8)], [0.50, Vector2(-6, 7)],
		 [0.64, Vector2(12, -4)], [0.74, Vector2(10, -3)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.32, Vector2(1.04, 0.96)], [0.50, Vector2(1.05, 0.95)],
		 [0.64, Vector2(0.97, 1.05)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.32, 0.020], [0.50, 0.026], [0.64, -0.030], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.32, 0.030], [0.50, 0.040], [0.64, -0.050], [1.0, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.32, -0.05], [0.64, 0.07], [0.74, 0.05], [1.0, 0.0],
	])


## 赤金·三连：三次前咬，每次一记定格 —— 躯干 x 是三段独立脉冲
func _qilin_combo(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.14, Vector2(-6, 2)], [0.24, Vector2(14, -2)],
		 [0.29, Vector2(14, -2)], [0.38, Vector2(-4, 1)], [0.48, Vector2(18, -3)],
		 [0.53, Vector2(18, -3)], [0.62, Vector2(-4, 1)], [0.72, Vector2(22, -4)],
		 [0.78, Vector2(22, -4)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.24, Vector2(0.98, 1.03)], [0.48, Vector2(0.98, 1.03)],
		 [0.72, Vector2(0.97, 1.04)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.14, -0.020], [0.24, 0.036], [0.29, 0.036],
		 [0.38, -0.016], [0.48, 0.040], [0.53, 0.040], [0.62, -0.016],
		 [0.72, 0.046], [0.78, 0.046], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.14, -0.045], [0.24, 0.055], [0.29, 0.055],
		[0.38, -0.040], [0.48, 0.060], [0.53, 0.060], [0.62, -0.040],
		[0.72, 0.065], [0.78, 0.065], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front", [[0.0, 0.0], [0.24, -0.10], [0.48, -0.12],
		[0.72, -0.14], [0.78, -0.14], [1.0, 0.0]])


## 日冕·环裂：伏身蓄势 → 身体向两侧撑开（光环保向外扩散）
func _qilin_ring(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.34, Vector2(0, 8)], [0.48, Vector2(0, 9)],
		 [0.58, Vector2(0, -4)], [0.74, Vector2(0, -3)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.34, Vector2(1.04, 0.94)], [0.48, Vector2(1.05, 0.93)],
		 [0.58, Vector2(0.95, 1.06)], [0.74, Vector2(0.97, 1.04)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.34, 0.018], [0.48, 0.022], [0.58, -0.014], [1.0, 0.0]])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.34, -0.07], [0.58, 0.12], [0.74, 0.09], [1.0, 0.0],
	])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.34, 0.035], [0.58, -0.030], [1.0, 0.0],
	])


## 日蚀·坠光：长时间仰头蓄能（二阶段长前摇），最后低身送光
func _qilin_eclipse(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.40, Vector2(-10, -10)], [0.66, Vector2(-12, -13)],
		 [0.82, Vector2(10, -2)], [0.90, Vector2(10, -2)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.40, Vector2(1.02, 1.02)], [0.66, Vector2(1.05, 1.03)],
		 [0.82, Vector2(0.98, 1.04)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.40, -0.045], [0.66, -0.060], [0.82, 0.026], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.40, -0.100], [0.66, -0.140], [0.82, 0.030], [1.0, 0.0],
	])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.30, 0.05], [0.55, -0.04], [0.82, 0.07], [1.0, 0.0],
	])


## 金乌·陨日：深蹲 → 腾身 → 前砸落地（最大的一次挤压）
func _qilin_meteor(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.26, Vector2(0, 12)], [0.44, Vector2(-4, 10)],
		 [0.60, Vector2(-8, -22)], [0.74, Vector2(6, -16)], [0.84, Vector2(8, 14)],
		 [0.92, Vector2(8, 14)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.26, Vector2(1.05, 0.93)], [0.60, Vector2(0.96, 1.07)],
		 [0.84, Vector2(1.09, 0.88)], [0.92, Vector2(1.09, 0.88)], [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.26, 0.026], [0.60, -0.060], [0.74, -0.030],
		 [0.84, 0.050], [0.92, 0.050], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.26, 0.045], [0.60, -0.080], [0.84, 0.065],
		[0.92, 0.065], [1.0, 0.0],
	])
	_leg_keys(a, "leg_front", [[0.0, 0.0], [0.26, 0.10], [0.60, -0.26],
		[0.84, 0.12], [0.92, 0.12], [1.0, 0.0]])
	_leg_keys(a, "leg_hind", [[0.0, 0.0], [0.26, -0.12], [0.60, 0.14],
		[0.84, -0.10], [1.0, 0.0]])
	_add_keys(a, "tail", "rotation", [
		[0.0, 0.0], [0.26, -0.06], [0.60, 0.10], [0.84, -0.08], [1.0, 0.0],
	])


## 爪击（普攻）：短促的前爪横抓
func _qilin_swipe(a: Animation) -> void:
	var b := _body_rest()
	_body_keys(a, b,
		[[0.0, Vector2.ZERO], [0.30, Vector2(-8, 1)], [0.44, Vector2(-8, 1)],
		 [0.52, Vector2(12, -1)], [0.60, Vector2(12, -1)], [1.0, Vector2.ZERO]],
		[[0.0, Vector2.ONE], [0.44, Vector2(1.01, 0.99)], [0.52, Vector2(0.99, 1.02)],
		 [1.0, Vector2.ONE]],
		[[0.0, 0.0], [0.30, 0.012], [0.44, 0.012], [0.52, -0.014], [1.0, 0.0]])
	_leg_keys(a, "leg_front", [[0.0, 0.0], [0.30, -0.16], [0.44, -0.18],
		[0.52, 0.14], [0.60, 0.14], [1.0, 0.0]])
	_add_keys(a, "head", "rotation", [
		[0.0, 0.0], [0.30, -0.020], [0.52, 0.026], [1.0, 0.0],
	])


## 普攻统一入口（WorldEnemy 对核心首领播 "attack"）
func _qilin_attack(a: Animation) -> void:
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
	_leg_keys(a, "leg_front", [[0.0, 0.0], [0.42, 0.10], [0.52, -0.16], [1.0, 0.0]])
