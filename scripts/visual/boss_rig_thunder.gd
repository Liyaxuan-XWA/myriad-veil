class_name BossRigThunder
extends BossRig
## 赫连霄的 2D 骨骼动作集（2026-10-29）。
##
## 分件：halo（背后雷环）/ drum（雷鼓）/ arm_free（远侧手臂）/
##       body（甲胄躯干 + 官袍下摆 + 头）/ arm_pen（近侧手臂 + 铁笔）。
## 肩关节藏在圆形肩甲下：身体保留肩甲，手臂从肩甲下缘整块转动，关节处不会露白缝。
##
## ⚠ 时间轴口径与刀客 / 气君一致：动画会被 `play_one_shot` 压进 `windup + 0.15` 秒，
##   所以「伤害判定那一帧」= `windup × length / (windup+0.15)` 的位置（见 _hit_time）；
##   这里的招式都把「最前伸 / 最大」摆在 length 的 ~62%，压进去后正好落在出手帧附近。

const TD_SKILLS := {
	"verdict": {"length": 0.85, "windup": 0.85},
	"execute": {"length": 0.65, "windup": 0.65},
	"drum": {"length": 0.60, "windup": 0.60},
	"lock": {"length": 0.65, "windup": 0.65},
	"step": {"length": 0.50, "windup": 0.50},
	"gather": {"length": 0.70, "windup": 0.70},
	"nine": {"length": 1.20, "windup": 1.20},
	"prison": {"length": 0.80, "windup": 0.80},
}


func _skill_table() -> Dictionary:
	return TD_SKILLS


func _skill_ids() -> Array:
	return TD_SKILLS.keys()


func _skill_anim(anim: String) -> Animation:
	var a := Animation.new()
	a.length = float(TD_SKILLS[anim]["length"])
	a.loop_mode = Animation.LOOP_NONE
	return a


func _hit_time(anim: String) -> float:
	var length := float(TD_SKILLS[anim]["length"])
	var windup := float(TD_SKILLS[anim]["windup"])
	return windup * length / (windup + 0.15)


func _add_spin(a: Animation, part: String, turns: float) -> void:
	if not _nodes.has(part):
		return
	_add_keys(a, part, "rotation", [[0.0, 0.0], [a.length, TAU * turns]])


func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = 3.4
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 1.6, 1, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.008, 1)
	_add_sine(a, "arm_pen", "rotation", 0.25, 0.018, 1, 0.92)
	_add_sine(a, "arm_free", "rotation", 0.30, 0.014, 1, 0.0)
	_add_keys(a, "drum", "scale", [[0.0, Vector2.ONE], [a.length * 0.5, Vector2(1.02, 1.02)],
		[a.length, Vector2.ONE]])
	_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [a.length * 0.5, Vector2(1.03, 1.03)],
		[a.length, Vector2.ONE]])
	_add_spin(a, "halo", 1.0)
	_neutral_all(a)
	return a


func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = 2.2
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 2.6, 2, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.012, 1, 0.02)
	_add_sine(a, "arm_pen", "rotation", 0.25, 0.045, 1, 0.92)
	_add_sine(a, "arm_free", "rotation", 0.75, 0.050, 1, 0.0)
	_add_sine(a, "drum", "rotation", 0.25, 0.018, 1, 0.0)
	_add_spin(a, "halo", 1.6)
	_neutral_all(a)
	return a


func _make_skill(anim: String) -> Animation:
	var a := _skill_anim(anim)
	var L := a.length
	match anim:
		"verdict":
			# 宣读 → 落笔：身体前压，持笔臂从后上方扫到前下方，远侧手向后撑
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.45, Vector2(-4.0, 3.0)],
				[L * 0.62, Vector2(9.0, -2.0)], [L * 0.70, Vector2(10.0, -2.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.45, -0.035],
				[L * 0.62, 0.055], [L * 0.70, 0.055], [L, 0.0]])
			_add_keys(a, "arm_pen", "rotation", [[0.0, 0.92], [L * 0.45, -0.72],
				[L * 0.62, 0.30], [L * 0.70, 0.30], [L, 0.92]])
			_add_keys(a, "arm_free", "rotation", [[0.0, 0.0], [L * 0.45, 0.28],
				[L * 0.62, -0.22], [L, 0.0]])
			_add_keys(a, "drum", "scale", [[0.0, Vector2.ONE], [L * 0.62, Vector2(1.06, 1.06)],
				[L, Vector2.ONE]])
			_add_spin(a, "halo", 1.4)
		"execute":
			# 定刑：举笔 → 向下一点；身体先仰后压
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.40, Vector2(0.0, -4.0)],
				[L * 0.62, Vector2(4.0, 4.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.40, -0.05],
				[L * 0.62, 0.04], [L, 0.0]])
			_add_keys(a, "arm_pen", "rotation", [[0.0, 0.92], [L * 0.40, -1.25],
				[L * 0.62, 0.55], [L * 0.70, 0.55], [L, 0.92]])
			_add_keys(a, "arm_free", "rotation", [[0.0, 0.0], [L * 0.40, -0.35],
				[L * 0.62, 0.12], [L, 0.0]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.62, Vector2(1.20, 1.20)],
				[L, Vector2.ONE]])
		"drum":
			# 雷鼓：双臂后拉 → 砸向鼓面；鼓面在击中帧胀大
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.38, Vector2(-5.0, 2.0)],
				[L * 0.60, Vector2(3.0, 0.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.38, -0.03],
				[L * 0.60, 0.05], [L, 0.0]])
			_add_keys(a, "arm_pen", "rotation", [[0.0, 0.92], [L * 0.38, -0.95],
				[L * 0.60, 0.65], [L, 0.92]])
			_add_keys(a, "arm_free", "rotation", [[0.0, 0.0], [L * 0.38, -0.95],
				[L * 0.60, 0.65], [L, 0.0]])
			_add_keys(a, "drum", "scale", [[0.0, Vector2.ONE], [L * 0.38, Vector2(0.96, 0.96)],
				[L * 0.60, Vector2(1.20, 1.20)], [L * 0.72, Vector2(1.10, 1.10)],
				[L, Vector2.ONE]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.60, Vector2(1.18, 1.18)],
				[L, Vector2.ONE]])
			_add_spin(a, "halo", 1.8)
		"lock":
			# 锁雷：笔尖前指，身体前送
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.50, Vector2(10.0, 0.0)],
				[L * 0.62, Vector2(12.0, 0.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.62, 0.03], [L, 0.0]])
			_add_keys(a, "arm_pen", "rotation", [[0.0, 0.92], [L * 0.50, -0.10],
				[L * 0.62, 0.08], [L, 0.92]])
			_add_keys(a, "arm_free", "rotation", [[0.0, 0.0], [L * 0.50, 0.18],
				[L * 0.62, -0.08], [L, 0.0]])
			_add_spin(a, "halo", 1.2)
		"step":
			# 雷遁：压低前倾，双臂后掠（消失/出现由脚本控制透明度）
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.40, Vector2(-6.0, 6.0)],
				[L * 0.62, Vector2(14.0, -2.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.40, -0.02],
				[L * 0.62, 0.09], [L, 0.0]])
			_add_keys(a, "arm_pen", "rotation", [[0.0, 0.92], [L * 0.40, 0.35],
				[L * 0.62, -0.35], [L, 0.92]])
			_add_keys(a, "arm_free", "rotation", [[0.0, 0.0], [L * 0.40, -0.30],
				[L * 0.62, 0.35], [L, 0.0]])
			_add_spin(a, "halo", 2.6)
		"gather":
			# 聚雷：双臂张开仰天，雷环暴涨；身体上浮
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.40, Vector2(0.0, -8.0)],
				[L * 0.62, Vector2(0.0, -10.0)], [L * 0.80, Vector2(0.0, -3.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.40, -0.06],
				[L * 0.62, -0.08], [L, 0.0]])
			_add_keys(a, "arm_pen", "rotation", [[0.0, 0.92], [L * 0.40, -0.95],
				[L * 0.62, -1.10], [L, 0.92]])
			_add_keys(a, "arm_free", "rotation", [[0.0, 0.0], [L * 0.40, 0.95],
				[L * 0.62, 1.10], [L, 0.0]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.40, Vector2(1.30, 1.30)],
				[L * 0.62, Vector2(1.38, 1.38)], [L, Vector2.ONE]])
			_add_keys(a, "drum", "scale", [[0.0, Vector2.ONE], [L * 0.62, Vector2(1.12, 1.12)],
				[L, Vector2.ONE]])
			_add_spin(a, "halo", 2.2)
		"nine":
			# 九霄：双臂高举 → 猛然下压；雷环先缩后炸
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.45, Vector2(0.0, -6.0)],
				[L * 0.62, Vector2(6.0, 2.0)], [L * 0.72, Vector2(6.0, 2.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.45, -0.08],
				[L * 0.62, 0.06], [L, 0.0]])
			_add_keys(a, "arm_pen", "rotation", [[0.0, 0.92], [L * 0.45, -1.45],
				[L * 0.62, 0.50], [L * 0.72, 0.50], [L, 0.92]])
			_add_keys(a, "arm_free", "rotation", [[0.0, 0.0], [L * 0.45, -1.45],
				[L * 0.62, 0.50], [L * 0.72, 0.50], [L, 0.0]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.45, Vector2(0.86, 0.86)],
				[L * 0.62, Vector2(1.42, 1.42)], [L, Vector2.ONE]])
			_add_spin(a, "halo", 2.8)
		"prison":
			# 雷牢：远侧手划出一个收拢的圈，持笔手向下压
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO], [L * 0.40, Vector2(2.0, -3.0)],
				[L * 0.62, Vector2(5.0, 2.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.40, 0.04],
				[L * 0.62, -0.04], [L, 0.0]])
			_add_keys(a, "arm_pen", "rotation", [[0.0, 0.92], [L * 0.40, 0.28],
				[L * 0.62, 0.58], [L, 0.92]])
			_add_keys(a, "arm_free", "rotation", [[0.0, 0.0], [L * 0.30, -0.55],
				[L * 0.55, 0.95], [L * 0.70, 0.55], [L, 0.0]])
			_add_keys(a, "halo", "scale", [[0.0, Vector2.ONE], [L * 0.62, Vector2(1.16, 1.16)],
				[L, Vector2.ONE]])
			_add_spin(a, "halo", -1.8)
		_:
			_neutral_all(a)
	_neutral_all(a)
	return a
