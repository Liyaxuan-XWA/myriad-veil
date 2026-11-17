class_name BossRigSun
extends BossRig
## 离照的 2D 骨骼动作集（2026-10-29）。
##
## 分件：body（祭袍 / 头 / 左臂 / 长绦）/ fan（日轮扇 + 扇柄 + 持扇手）。
## 扇件绕手腕转，宽袖留在 body 上 —— 这样扇舞不会把袖子从袍子上扯开。
##
## 时间轴口径与赫连霄一致：动画被 `play_one_shot` 压进 `windup + 0.15` 秒，
## 伤害帧落在 `windup × length / (windup + 0.15)` 附近。

const SUN_SKILLS := {
	"step": {"length": 0.55, "windup": 0.55},
	"slash": {"length": 0.65, "windup": 0.65},
	"throw": {"length": 0.55, "windup": 0.55},
	"pull": {"length": 0.80, "windup": 0.80},
	"wind": {"length": 0.60, "windup": 0.60},
	"eclipse": {"length": 0.75, "windup": 0.75},
	"wheel": {"length": 0.80, "windup": 0.80},
	"meteor": {"length": 1.10, "windup": 1.10},
}


func _skill_table() -> Dictionary:
	return SUN_SKILLS


func _skill_ids() -> Array:
	return SUN_SKILLS.keys()


func _skill_anim(anim: String) -> Animation:
	var a := Animation.new()
	a.length = float(SUN_SKILLS[anim]["length"])
	a.loop_mode = Animation.LOOP_NONE
	return a


func _hit_time(anim: String) -> float:
	var length := float(SUN_SKILLS[anim]["length"])
	var windup := float(SUN_SKILLS[anim]["windup"])
	return windup * length / (windup + 0.15)


func _add_spin(a: Animation, part: String, turns: float) -> void:
	if not _nodes.has(part):
		return
	_add_keys(a, part, "rotation", [[0.0, 0.0], [a.length, TAU * turns]])


func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = 3.4
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 1.5, 1, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.008, 1)
	# 扇面慢慢摇：0.018 rad 约 1°，静止时像被热风托着
	_add_sine(a, "fan", "rotation", 0.25, 0.018, 1, 0.0)
	_add_keys(a, "fan", "scale", [[0.0, Vector2.ONE],
		[a.length * 0.5, Vector2(1.02, 1.02)], [a.length, Vector2.ONE]])
	_neutral_all(a)
	return a


func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = 2.2
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 2.6, 2, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.012, 1, 0.015)
	_add_sine(a, "fan", "rotation", 0.25, 0.045, 1, 0.0)
	_neutral_all(a)
	return a


func _make_skill(anim: String) -> Animation:
	var a := _skill_anim(anim)
	var L := a.length
	match anim:
		"step":
			# 逐日步：身体前探，扇面后掠再前指
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO],
				[L * 0.35, Vector2(-4.0, 3.0)], [L * 0.62, Vector2(10.0, -2.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.35, -0.03],
				[L * 0.62, 0.08], [L, 0.0]])
			_add_keys(a, "fan", "rotation", [[0.0, 0.0], [L * 0.35, -0.55],
				[L * 0.62, 0.35], [L, 0.0]])
		"slash":
			# 日冕斩：扇从后上方扫到前下方
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO],
				[L * 0.38, Vector2(-5.0, 2.0)], [L * 0.62, Vector2(8.0, 0.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.38, -0.05],
				[L * 0.62, 0.07], [L, 0.0]])
			_add_keys(a, "fan", "rotation", [[0.0, 0.0], [L * 0.38, -1.25],
				[L * 0.62, 0.55], [L * 0.72, 0.45], [L, 0.0]])
		"throw":
			# 投日：扇后引，随后向前甩出
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO],
				[L * 0.35, Vector2(-5.0, 1.0)], [L * 0.62, Vector2(9.0, 0.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.35, -0.06],
				[L * 0.62, 0.08], [L, 0.0]])
			_add_keys(a, "fan", "rotation", [[0.0, 0.0], [L * 0.35, -1.55],
				[L * 0.62, 0.55], [L * 0.74, 0.40], [L, 0.0]])
		"pull":
			# 牵日：扇面朝前下方压，身体后坐
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO],
				[L * 0.40, Vector2(-6.0, 3.0)], [L * 0.68, Vector2(-2.0, 2.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.40, -0.05],
				[L * 0.68, -0.02], [L, 0.0]])
			_add_keys(a, "fan", "rotation", [[0.0, 0.0], [L * 0.40, -0.65],
				[L * 0.62, 0.40], [L, 0.0]])
		"wind":
			# 焚风：大横扇，身体反向拧
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO],
				[L * 0.38, Vector2(-4.0, 2.0)], [L * 0.62, Vector2(5.0, 0.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.38, -0.08],
				[L * 0.62, 0.10], [L, 0.0]])
			_add_keys(a, "fan", "rotation", [[0.0, 0.0], [L * 0.38, 1.15],
				[L * 0.62, -0.85], [L, 0.0]])
		"eclipse":
			# 日蚀：扇举过头顶，仰身蓄势，落点由脚本另行预警
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO],
				[L * 0.40, Vector2(0.0, -6.0)], [L * 0.62, Vector2(5.0, 3.0)],
				[L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.40, -0.07],
				[L * 0.62, 0.05], [L, 0.0]])
			_add_keys(a, "fan", "rotation", [[0.0, 0.0], [L * 0.40, -1.85],
				[L * 0.62, -0.25], [L, 0.0]])
		"wheel":
			# 日轮：扇面立起旋转两圈
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO],
				[L * 0.45, Vector2(0.0, -3.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.45, 0.03],
				[L, 0.0]])
			_add_spin(a, "fan", 2.0)
			_add_keys(a, "fan", "scale", [[0.0, Vector2.ONE],
				[L * 0.45, Vector2(1.06, 1.06)], [L, Vector2.ONE]])
		"meteor":
			# 天火坠：扇举天、身体后仰 → 猛然下压
			_add_keys(a, "body", "position", [[0.0, Vector2.ZERO],
				[L * 0.38, Vector2(-3.0, -7.0)], [L * 0.62, Vector2(6.0, 5.0)],
				[L * 0.78, Vector2(4.0, 4.0)], [L, Vector2.ZERO]])
			_add_keys(a, "body", "rotation", [[0.0, 0.0], [L * 0.38, -0.09],
				[L * 0.62, 0.10], [L, 0.0]])
			_add_keys(a, "fan", "rotation", [[0.0, 0.0], [L * 0.38, -1.95],
				[L * 0.62, 1.10], [L * 0.80, 0.85], [L, 0.0]])
			_add_keys(a, "fan", "scale", [[0.0, Vector2.ONE],
				[L * 0.62, Vector2(1.10, 1.10)], [L, Vector2.ONE]])
	_neutral_all(a)
	return a
