class_name BossRigDiezhi
extends BossRig
## 叠纸的 2D 骨骼动作集（2026-11-02）
##
## 分件只有 body 与 rule（青铜镇尺）：
##   · body 是整身月白纸袍，袍面上只有**硬折出来的棱**，没有布褶 —— 按肩肘拆必露白缝，
##     而且一拆就想做「袖摆飘动」，那就变成执烛那套青黑广袖的读法了（刻意不要）；
##   · rule 以握持点为旋转中心挂在 body 下，压纸 / 掀纸 / 撕纸全部由这把尺交付。
##
## 表演语言：**纸的角位移**。躯干不画弧线、只画折角 —— 蓄力时把身体往「对折」的方向压，
## 到位时突然展平（scale 拉一下），像一张纸被掀开又拍下去。镇尺跟着走直线，不走钟摆。
## 折痕本体 / 圆牌由 FoldField + FoldVisual 负责，这里只管身体。

const DIEZHI_SKILLS := {
	"press": {"length": 0.94, "windup": 0.72},
	"trace": {"length": 0.72, "windup": 0.58},
	"stride": {"length": 0.84, "windup": 0.66},
	"pressmark": {"length": 1.02, "windup": 0.80},
	"shroud": {"length": 0.66, "windup": 0.44},
	"tear": {"length": 1.20, "windup": 0.92},
	"twin": {"length": 0.98, "windup": 0.76},
	"triple": {"length": 1.78, "windup": 1.58},
}

const Z_IDLE_CYCLE := 4.2
const Z_WALK_CYCLE := 1.24
## 镇尺静止时斜压在身前（不是提着的，是按着的）
const RULE_REST_ROT := -0.34


## 镇尺握点（rig 数据里的 part_joint，已减掉 body 关节）
## ⚠ 动画的 position 轨道是**绝对值**不是偏移：从 ZERO 起键会把尺拽回躯干原点。
func _rule_home() -> Vector2:
	if _data == null:
		return Vector2.ZERO
	var i := _data.index_of("rule")
	if i < 0:
		return Vector2.ZERO
	var j := _data.index_of("body")
	return _data.part_joint[i] - (_data.part_joint[j] if j >= 0 else Vector2.ZERO)


func _skill_table() -> Dictionary:
	return DIEZHI_SKILLS


func _skill_ids() -> Array:
	return DIEZHI_SKILLS.keys()


func _skill_anim(anim: String) -> Animation:
	var a := Animation.new()
	a.length = float(DIEZHI_SKILLS[anim]["length"])
	a.loop_mode = Animation.LOOP_NONE
	return a


func _hit_time(anim: String) -> float:
	var length := float(DIEZHI_SKILLS[anim]["length"])
	var windup := float(DIEZHI_SKILLS[anim]["windup"])
	return windup * length / (windup + 0.15)


func _make_skill(anim: String) -> Animation:
	match anim:
		"press":
			return _make_press()
		"trace":
			return _make_trace()
		"stride":
			return _make_stride()
		"pressmark":
			return _make_pressmark()
		"shroud":
			return _make_shroud()
		"tear":
			return _make_tear()
		"twin":
			return _make_twin()
		"triple":
			return _make_triple()
	return _make_press()


## 通用出招曲线：对折蓄力 → 猛展平到位 → 定格 → 回收
## 与执烛那套的区别全在 **scale**：这里蓄力压成 (1.10, 0.84) 的硬扁块、
## 到位弹成 (0.92, 1.12) 的硬长条 —— 读出来是「一张纸被折起来又拍开」，不是人弯腰。
func _pose(a: Animation, anim: String, pull: Vector2, push: Vector2,
		body_back: float, body_hit: float,
		rule_back: float, rule_hit: float,
		rule_off_back: Vector2, rule_off_hit: Vector2,
		rule_scale_hit: float = 1.0) -> void:
	var t_hit := _hit_time(anim)
	var t_pull := t_hit * 0.55
	var t_free := minf(t_hit + a.length * 0.10, a.length - 0.01)
	var home := _rule_home()
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
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE],
		[t_pull, Vector2(1.10, 0.84)],
		[t_hit, Vector2(0.92, 1.12)],
		[t_free, Vector2(0.92, 1.12)],
		[a.length, Vector2.ONE],
	])
	_add_keys(a, "rule", "position", [
		[0.0, home],
		[t_pull, home + rule_off_back],
		[t_hit, home + rule_off_hit],
		[t_free, home + rule_off_hit],
		[a.length, home],
	])
	_add_keys(a, "rule", "rotation", [
		[0.0, RULE_REST_ROT],
		[t_pull, rule_back],
		[t_hit, rule_hit],
		[t_free, rule_hit],
		[a.length, RULE_REST_ROT],
	])
	_add_keys(a, "rule", "scale", [
		[0.0, Vector2.ONE],
		[t_hit, Vector2.ONE * rule_scale_hit],
		[t_free, Vector2.ONE * rule_scale_hit],
		[a.length, Vector2.ONE],
	])


func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = Z_IDLE_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 1.2, 1, 0.0)
	## 纸的待机：不是呼吸起伏，是**整张袍面极慢地鼓一下又瘪下去**（scale 走方形）
	_add_keys(a, "body", "scale", [
		[0.0, Vector2(1.0, 1.0)],
		[a.length * 0.28, Vector2(1.018, 0.986)],
		[a.length * 0.52, Vector2(0.994, 1.012)],
		[a.length * 0.78, Vector2(1.012, 0.990)],
		[a.length, Vector2(1.0, 1.0)],
	])
	_add_sine(a, "body", "rotation", 0.30, 0.004, 1)
	_add_sine(a, "rule", "rotation", 0.60, 0.012, 1, RULE_REST_ROT)
	_neutral_all(a)
	return a


func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = Z_WALK_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 2.0, 2, 0.0)
	## 走路时纸面「翻面」两次：整张袍在竖直方向被压扁/拉长，读得出它不是人在迈步
	_add_sine(a, "body", "rotation", 0.26, 0.010, 1)
	_add_sine(a, "rule", "rotation", 0.52, 0.030, 2, RULE_REST_ROT)
	_neutral_all(a)
	return a


## 按纸：整个人往前**折**下去，镇尺平拍在前臂高度 —— 一掌按平一张纸
func _make_press() -> Animation:
	var a := _skill_anim("press")
	_pose(a, "press", Vector2(-20.0, 14.0), Vector2(42.0, -4.0),
		-0.24, 0.30, -0.90, 0.16,
		Vector2(-10.0, -18.0), Vector2(40.0, 26.0), 1.06)
	return a


## 循痕：侧身成一条纸片，沿痕滑出去 —— 判定帧人已经是「薄片」（scale.x 压扁）
func _make_trace() -> Animation:
	var a := _skill_anim("trace")
	_pose(a, "trace", Vector2(-26.0, 0.0), Vector2(52.0, -10.0),
		-0.34, 0.42, -0.60, 0.72,
		Vector2(-22.0, 4.0), Vector2(44.0, -14.0), 0.94)
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE],
		[_hit_time("trace") * 0.5, Vector2(0.80, 1.06)],
		[_hit_time("trace"), Vector2(1.30, 0.74)],
		[a.length - 0.01, Vector2.ONE],
	])
	return a


## 跨缝：双膝一折整身「合」成一半高，再展开 —— 从这头进去、那头出来
func _make_stride() -> Animation:
	var a := _skill_anim("stride")
	_pose(a, "stride", Vector2(0.0, 22.0), Vector2(14.0, -22.0),
		0.10, -0.22, -1.10, 0.86,
		Vector2(0.0, 26.0), Vector2(30.0, -40.0), 1.12)
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE],
		[_hit_time("stride") * 0.55, Vector2(1.22, 0.50)],
		[_hit_time("stride"), Vector2(0.86, 1.20)],
		[a.length - 0.01, Vector2.ONE],
	])
	return a


## 押痕：两手把镇尺横过来往前**压**，身体跟着推 —— 压的是地上那条痕，不是人
func _make_pressmark() -> Animation:
	var a := _skill_anim("pressmark")
	_pose(a, "pressmark", Vector2(-14.0, -10.0), Vector2(34.0, 10.0),
		0.16, -0.26, 0.30, -1.44,
		Vector2(0.0, -34.0), Vector2(26.0, 54.0), 1.20)
	return a


## 叠掩：把袍面前翻盖住自己 —— 三层纸错着叠上来，判定帧全身缩进纸里
func _make_shroud() -> Animation:
	var a := _skill_anim("shroud")
	_pose(a, "shroud", Vector2(0.0, -12.0), Vector2(0.0, 12.0),
		-0.10, 0.14, -0.40, 1.30,
		Vector2(0.0, -22.0), Vector2(0.0, 18.0), 0.78)
	return a


## 碎痕：镇尺举到最高再一路划到底 —— 顺着痕把纸撕开，动作是「划」不是「劈」
func _make_tear() -> Animation:
	var a := _skill_anim("tear")
	_pose(a, "tear", Vector2(-18.0, -34.0), Vector2(28.0, 20.0),
		0.28, -0.36, 1.10, -1.62,
		Vector2(-12.0, -96.0), Vector2(34.0, 92.0), 1.26)
	return a


## 双屏：身体中立，镇尺左右各翻一次 —— 两具纸影从两端圆牌立起来
func _make_twin() -> Animation:
	var a := _skill_anim("twin")
	_pose(a, "twin", Vector2(0.0, -16.0), Vector2(6.0, 8.0),
		0.06, -0.10, 0.80, -0.86,
		Vector2(-24.0, -30.0), Vector2(24.0, -30.0), 1.10)
	return a


## 三重落纸：整张纸立直到最高，再朝三个方向各折一次 —— P2 终局招
func _make_triple() -> Animation:
	var a := _skill_anim("triple")
	_pose(a, "triple", Vector2(0.0, -46.0), Vector2(0.0, 16.0),
		0.0, -0.20, 0.20, 1.02,
		Vector2(0.0, -120.0), Vector2(0.0, 44.0), 1.30)
	var t_hit := _hit_time("triple")
	## 到位后镇尺在 0.34 秒的间隔里连扫三方（对应三区落掌）
	_add_keys(a, "rule", "rotation", [
		[0.0, RULE_REST_ROT],
		[t_hit * 0.5, 0.90],
		[t_hit, -1.10],
		[minf(t_hit + 0.34, a.length - 0.02), 1.42],
		[minf(t_hit + 0.68, a.length - 0.01), -1.42],
	])
	return a
