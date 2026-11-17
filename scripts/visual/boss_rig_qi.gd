class_name BossRigQi
extends BossRig
## 太虚气君的 2D 骨骼动作集（2026-10-28 改单件身体）。
##
## 部件只有两个：halo（身后气环）/ body（整个人：头 + 躯干 + 手 + 袍摆 + 云尾）。
## **没有手臂拆件** —— 原来那套是拿 T-pose 切出来的双臂 + 长方形袖摆，
## 一转身就变成「张开两只翅膀」，任何角度都救不回来（详见美术资源接入记录 §33）。
## 现在按用户定的口径：**靠气环出手** —— 招式表现全交给
##   身体俯仰 / 前冲回弹 / 整体缩放 + 气环的缩放与自转 + SkillFx 的云烟。
##
## ⚠ 时间轴口径与刀客一致：动画会被 `play_one_shot` 压进 `windup + 0.15` 秒，
##   所以「伤害判定那一帧」= `windup × length / (windup+0.15)` 的位置；
##   这里的招式都把「最前伸 / 最大」摆在 length 的 ~62%，压进去后正好落在出手帧附近。

## 动画名 → 原速时长（= MoveDB 前摇；压帧后与判定对齐）
const Q_SKILLS := {
	"gather": {"length": 0.55},
	"wave": {"length": 0.68},
	"spin": {"length": 0.60},
	"lock": {"length": 0.62},
	"ward": {"length": 0.50},
	"step": {"length": 0.55},
	"burst": {"length": 0.90},
	"breath": {"length": 0.80},
}


func _skill_table() -> Dictionary:
	return Q_SKILLS


func _skill_ids() -> Array:
	return Q_SKILLS.keys()


func _skill_anim(anim: String) -> Animation:
	var a := Animation.new()
	a.length = float(Q_SKILLS[anim]["length"])
	a.loop_mode = Animation.LOOP_NONE
	return a


func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = 3.6
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 2.2, 1, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.010, 1)
	# 气环随呼吸涨落：这是唯一「活着」的部件，幅度压小免得抢戏
	_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [a.length * 0.5, Vector2(1.02, 1.02)],
		[a.length, Vector2.ONE]])
	_add_spin(a, "halo", 1.0)
	_neutral_all(a)
	return a


func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = 2.4
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 3.2, 1, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.012, 1, 0.03)
	_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [a.length * 0.5, Vector2(1.03, 1.03)],
		[a.length, Vector2.ONE]])
	_add_spin(a, "halo", 1.5)
	_neutral_all(a)
	return a


func _make_skill(anim: String) -> Animation:
	var a := _skill_anim(anim)
	var L := a.length
	match anim:
		"gather":
			# 引气：环先收（吸）再涨（凝），身体跟着沉一下再立起来
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.35, Vector2(0.90, 0.90)],
				[L * 0.62, Vector2(1.24, 1.24)], [L, Vector2.ONE]])
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.35, Vector2(0.0, 5.0)],
				[L * 0.62, Vector2(0.0, -4.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.62, 0.018], [L, 0.0]])
		"wave":
			# 冲气：整个人往前送 + 前倾，环在出手帧放大
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.55, Vector2(16.0, 0.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.55, -0.12], [L, 0.0]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.55, Vector2(1.12, 1.12)],
				[L, Vector2.ONE]])
		"spin":
			# 回旋：整张 2D 立绘转 360° 会像纸片翻面，改成「身体下沉 + 左右侧倾回弹」，
			# 旋转交给气环（两圈急转 + 放大）和 SkillFx 的两道反向气旋。
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.28, Vector2(-4.0, 4.0)],
				[L * 0.55, Vector2(6.0, -8.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.30, -0.14],
				[L * 0.62, 0.14], [L, 0.0]])
			_add_keys(a, "body", "scale", [[0.0, Vector2.ONE], [L * 0.55, Vector2(1.04, 0.97)],
				[L, Vector2.ONE]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.45, Vector2(1.20, 1.20)],
				[L, Vector2.ONE]])
			_add_spin(a, "halo", 2.0)
		"lock":
			# 缚脉：环收紧（0.86）—— 读作「气索勒住」，身体只轻推
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.5, Vector2(0.86, 0.86)],
				[L * 0.75, Vector2(1.05, 1.05)], [L, Vector2.ONE]])
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.5, Vector2(7.0, 0.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.5, 0.04], [L, 0.0]])
		"ward":
			# 化劲：身体被压下去（缩），环张开撑住
			_add_keys(a, "body", "scale", [[0.0, Vector2.ONE], [L * 0.5, Vector2(0.95, 0.95)],
				[L, Vector2.ONE]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.5, Vector2(1.30, 1.30)],
				[L, Vector2.ONE]])
		"step":
			# 踏罡：整体平移 + 轻前倾（原地位移由 BOSS 脚本自己走，这里只给视觉）
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.6, Vector2(28.0, -6.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.6, 0.08], [L, 0.0]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.6, Vector2(1.15, 1.15)],
				[L, Vector2.ONE]])
		"burst":
			# 气爆：整身鼓一下 + 上浮，环张到最大
			_add_keys(a, "body", "scale", [[0.0, Vector2.ONE], [L * 0.65, Vector2(1.06, 1.06)],
				[L, Vector2.ONE]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.65, Vector2(1.35, 1.35)],
				[L, Vector2.ONE]])
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.65, Vector2(0.0, -10.0)],
				[L, Vector2.ZERO]])
		"breath":
			# 吐纳：向上飘起并微微拉长，环缓缓扩
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.6, Vector2(0.0, -16.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "scale", [[0.0, Vector2.ONE], [L * 0.6, Vector2(1.0, 1.03)],
				[L, Vector2.ONE]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.6, Vector2(1.10, 1.10)],
				[L, Vector2.ONE]])
		_:
			pass
	return a


## 气环自转：整段线性转到 +TAU，循环点不会跳
func _add_spin(a: Animation, part: String, turns: float) -> void:
	_add_keys(a, part, "rotation", [[0.0, 0.0], [a.length, TAU * turns]])
