class_name BossRigGuanying
extends BossRig
## 观澜的 2D 骨骼动作集（2026-11-01）。
##
## 分件只有 body 与 mirror：
##   · body 是整身长袍 + 长发，不做肩肘拆分 —— 这一身衣褶又长又碎，按肩拆必露白缝；
##   · mirror 以**握把**为旋转中心挂在 body 下，换镜 / 碎镜 / 镜返时只转镜，不扯袍袖。
##
## 表演语言：躯干前后压 + 镜面翻转。它不挥刀，所有招式都由「镜面朝哪、人压多低」表达。
## 环 / 镜像 / 水镜由 SkillFx 与 MirrorImage 负责，这里只做身体。

const GUANYING_SKILLS := {
	"slash": {"length": 0.95, "windup": 0.78},
	"thrust": {"length": 0.82, "windup": 0.65},
	"bloom": {"length": 0.78, "windup": 0.50},
	"shatter": {"length": 0.82, "windup": 0.55},
	"swap": {"length": 0.62, "windup": 0.35},
	"return": {"length": 0.58, "windup": 0.20},
	"ring": {"length": 0.86, "windup": 0.60},
	"myriad": {"length": 1.32, "windup": 1.10},
}

const G_IDLE_CYCLE := 4.2
const G_WALK_CYCLE := 1.35
const MIRROR_REST_ROT := -0.10


func _skill_table() -> Dictionary:
	return GUANYING_SKILLS


func _skill_ids() -> Array:
	return GUANYING_SKILLS.keys()


func _skill_anim(anim: String) -> Animation:
	var a := Animation.new()
	a.length = float(GUANYING_SKILLS[anim]["length"])
	a.loop_mode = Animation.LOOP_NONE
	return a


func _hit_time(anim: String) -> float:
	var length := float(GUANYING_SKILLS[anim]["length"])
	var windup := float(GUANYING_SKILLS[anim]["windup"])
	return windup * length / (windup + 0.15)


func _make_skill(anim: String) -> Animation:
	match anim:
		"slash":
			return _make_slash()
		"thrust":
			return _make_thrust()
		"bloom":
			return _make_bloom()
		"shatter":
			return _make_shatter()
		"swap":
			return _make_swap()
		"return":
			return _make_return()
		"ring":
			return _make_ring()
		"myriad":
			return _make_myriad()
	return _make_slash()


## 通用出招曲线：慢蓄力 → 判定前到位 → 定格 → 回收
func _pose(a: Animation, anim: String, pull: Vector2, push: Vector2,
		body_back: float, body_hit: float,
		mirror_back: float, mirror_hit: float,
		mirror_off_back: Vector2, mirror_off_hit: Vector2,
		mirror_scale_hit: float = 1.0) -> void:
	var t_hit := _hit_time(anim)
	var t_pull := t_hit * 0.55
	var t_free := minf(t_hit + a.length * 0.10, a.length - 0.01)
	_add_keys(a, "body", "position", [
		[0.0, Vector2.ZERO],
		[t_pull * 0.6, pull * 0.45],
		[t_pull, pull],
		[t_hit, push],
		[t_free, push],
		[a.length, Vector2.ZERO],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [t_pull, body_back], [t_hit, body_hit],
		[t_free, body_hit], [a.length, 0.0],
	])
	# 挤压拉伸：蓄力时压低，出招时拔高
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE],
		[t_pull, Vector2(1.04, 0.94)],
		[t_hit, Vector2(0.96, 1.06)],
		[t_free, Vector2(0.96, 1.06)],
		[a.length, Vector2.ONE],
	])
	_add_keys(a, "mirror", "position", [
		[0.0, Vector2.ZERO],
		[t_pull, mirror_off_back],
		[t_hit, mirror_off_hit],
		[t_free, mirror_off_hit],
		[a.length, Vector2.ZERO],
	])
	_add_keys(a, "mirror", "rotation", [
		[0.0, MIRROR_REST_ROT],
		[t_pull, mirror_back],
		[t_hit, mirror_hit],
		[t_free, mirror_hit],
		[a.length, MIRROR_REST_ROT],
	])
	_add_keys(a, "mirror", "scale", [
		[0.0, Vector2.ONE],
		[t_hit, Vector2.ONE * mirror_scale_hit],
		[t_free, Vector2.ONE * mirror_scale_hit],
		[a.length, Vector2.ONE],
	])


func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = G_IDLE_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 1.8, 1, 0.0)
	_add_sine(a, "body", "rotation", 0.20, 0.008, 1)
	_add_sine(a, "mirror", "rotation", 0.35, 0.028, 1, MIRROR_REST_ROT)
	_add_mirror_sway(a, 1.6, 1)
	_neutral_all(a)
	return a


func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = G_WALK_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 2.6, 2, 0.0)
	_add_sine(a, "body", "rotation", 0.25, 0.014, 1)
	_add_sine(a, "mirror", "rotation", 0.30, 0.055, 1, MIRROR_REST_ROT)
	_add_mirror_sway(a, 2.4, 2)
	_neutral_all(a)
	return a


## 镜器的上下轻摆（position 是 Vector2，不能用 _add_sine 的 float 轨道）
func _add_mirror_sway(a: Animation, amp: float, cycles: int) -> void:
	if not _nodes.has("mirror"):
		return
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath("%s:position" % _node_path_of("mirror")))
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_CUBIC)
	var steps := maxi(12, cycles * 16)
	for k in range(steps + 1):
		var u := float(k) / float(steps)
		var v := Vector2(0.0, amp * sin(TAU * (float(cycles) * u)))
		a.track_insert_key(idx, u * a.length, v)


## 镜水斩：人先向后压，镜面横抹；判定帧镜面正对前方。
func _make_slash() -> Animation:
	var a := _skill_anim("slash")
	_pose(a, "slash", Vector2(-26.0, 11.0), Vector2(38.0, -8.0),
		-0.18, 0.22, -0.55, 0.62,
		Vector2(-16.0, 10.0), Vector2(30.0, -8.0), 1.04)
	return a


## 照影刺：人向前送，镜面竖成一条线，像把倒影递出去。
func _make_thrust() -> Animation:
	var a := _skill_anim("thrust")
	_pose(a, "thrust", Vector2(-18.0, 6.0), Vector2(54.0, -10.0),
		-0.10, 0.26, -0.30, 0.18,
		Vector2(-22.0, 16.0), Vector2(58.0, -18.0), 0.94)
	return a


## 镜花：身体立直，镜面抬到胸前再张开；配合 SkillFx 的镜面开花。
func _make_bloom() -> Animation:
	var a := _skill_anim("bloom")
	_pose(a, "bloom", Vector2(-8.0, -14.0), Vector2(8.0, 8.0),
		0.06, -0.06, 0.15, -0.45,
		Vector2(6.0, 18.0), Vector2(-10.0, -46.0), 1.12)
	return a


## 碎镜：镜面先抖，再向下砸；判定帧整个人压低。
func _make_shatter() -> Animation:
	var a := _skill_anim("shatter")
	_pose(a, "shatter", Vector2(-10.0, 16.0), Vector2(16.0, 24.0),
		-0.08, 0.14, -0.20, 0.86,
		Vector2(4.0, 12.0), Vector2(12.0, 34.0), 1.18)
	return a


## 换镜：镜面翻半圈，身体急转；落地后回到正面。
func _make_swap() -> Animation:
	var a := _skill_anim("swap")
	_pose(a, "swap", Vector2(-14.0, 0.0), Vector2(20.0, -4.0),
		-0.16, 0.18, -0.20, -0.95,
		Vector2(-10.0, 8.0), Vector2(18.0, -16.0), 1.0)
	return a


## 镜返：横镜在身前，整个人后坐；镜面竖成盾。
func _make_return() -> Animation:
	var a := _skill_anim("return")
	_pose(a, "return", Vector2(-8.0, 10.0), Vector2(10.0, -4.0),
		0.08, -0.12, 0.25, -1.32,
		Vector2(0.0, 10.0), Vector2(28.0, -22.0), 1.08)
	return a


## 水镜环：镜面向下压，身体沉；镜面小角度翻转，水环交给 SkillFx。
func _make_ring() -> Animation:
	var a := _skill_anim("ring")
	_pose(a, "ring", Vector2(-12.0, -10.0), Vector2(12.0, 22.0),
		-0.06, 0.12, 0.10, 0.35,
		Vector2(0.0, -18.0), Vector2(6.0, 26.0), 1.06)
	return a


## 万镜归一：大幅后仰，镜面举过头顶；判定帧全身压出，所有镜像同帧补刀。
func _make_myriad() -> Animation:
	var a := _skill_anim("myriad")
	_pose(a, "myriad", Vector2(-30.0, -22.0), Vector2(34.0, 10.0),
		-0.24, 0.30, 0.28, -0.72,
		Vector2(-14.0, 26.0), Vector2(-18.0, -58.0), 1.16)
	return a
