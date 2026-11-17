class_name BossRigZhizhu
extends BossRig
## 执烛的 2D 骨骼动作集（2026-11-02）
##
## 分件只有 body 与 lantern：
##   · body 是整身青黑广袖 + 垂到地的墨色披影，不做肩肘拆分 —— 衣褶长而碎，按肩拆必露白缝；
##   · lantern 以**提手**为旋转中心挂在 body 下，捻灯 / 挑灯 / 夺灯时只转灯，不扯袖子。
##
## 表演语言：躯干前压 + 灯笼的 pendulum。它不挥兵刃 —— 招式都交给地上那条影子，
## 所以身体只做「压得多低、灯举得多高、线放得多长」这三件事。
## 影身走廊 / 锚定带 / 脱手影兽由 ShadowVisual 与 SkillFx 负责，这里只管身体。

const ZHIZHU_SKILLS := {
	"cut": {"length": 0.92, "windup": 0.74},
	"reach": {"length": 1.08, "windup": 0.86},
	"bind": {"length": 1.05, "windup": 0.80},
	"step": {"length": 0.80, "windup": 0.55},
	"dim": {"length": 0.72, "windup": 0.42},
	"beam": {"length": 1.00, "windup": 0.78},
	"split": {"length": 0.95, "windup": 0.62},
	"longnight": {"length": 1.85, "windup": 1.50},
}

const Z_IDLE_CYCLE := 4.6
const Z_WALK_CYCLE := 1.30
const LANTERN_REST_ROT := 0.14


## 灯笼挂点（rig 数据里的 part_joint，已减掉 body 关节）
## ⚠ 动画的 position 轨道写的是**绝对值**，不是偏移量：
##   第一版这里从 Vector2.ZERO 起键，一播动画灯笼就被从手里拽回躯干原点 ——
##   实机看到的是「灯浮在肚子前面」。所有灯笼位移键都必须自己加回 home。
func _lamp_home() -> Vector2:
	if _data == null:
		return Vector2.ZERO
	var i := _data.index_of("lantern")
	if i < 0:
		return Vector2.ZERO
	var j := _data.index_of("body")
	return _data.part_joint[i] - (_data.part_joint[j] if j >= 0 else Vector2.ZERO)


func _skill_table() -> Dictionary:
	return ZHIZHU_SKILLS


func _skill_ids() -> Array:
	return ZHIZHU_SKILLS.keys()


func _skill_anim(anim: String) -> Animation:
	var a := Animation.new()
	a.length = float(ZHIZHU_SKILLS[anim]["length"])
	a.loop_mode = Animation.LOOP_NONE
	return a


func _hit_time(anim: String) -> float:
	var length := float(ZHIZHU_SKILLS[anim]["length"])
	var windup := float(ZHIZHU_SKILLS[anim]["windup"])
	return windup * length / (windup + 0.15)


func _make_skill(anim: String) -> Animation:
	match anim:
		"cut":
			return _make_cut()
		"reach":
			return _make_reach()
		"bind":
			return _make_bind()
		"step":
			return _make_step()
		"dim":
			return _make_dim()
		"beam":
			return _make_beam()
		"split":
			return _make_split()
		"longnight":
			return _make_longnight()
	return _make_cut()


## 通用出招曲线：慢蓄力 → 判定前到位 → 定格 → 回收
func _pose(a: Animation, anim: String, pull: Vector2, push: Vector2,
		body_back: float, body_hit: float,
		lamp_back: float, lamp_hit: float,
		lamp_off_back: Vector2, lamp_off_hit: Vector2,
		lamp_scale_hit: float = 1.0) -> void:
	var t_hit := _hit_time(anim)
	var t_pull := t_hit * 0.55
	var t_free := minf(t_hit + a.length * 0.10, a.length - 0.01)
	var home := _lamp_home()
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
		[t_pull, Vector2(1.05, 0.93)],
		[t_hit, Vector2(0.95, 1.07)],
		[t_free, Vector2(0.95, 1.07)],
		[a.length, Vector2.ONE],
	])
	_add_keys(a, "lantern", "position", [
		[0.0, home],
		[t_pull, home + lamp_off_back],
		[t_hit, home + lamp_off_hit],
		[t_free, home + lamp_off_hit],
		[a.length, home],
	])
	_add_keys(a, "lantern", "rotation", [
		[0.0, LANTERN_REST_ROT],
		[t_pull, lamp_back],
		[t_hit, lamp_hit],
		[t_free, lamp_hit],
		[a.length, LANTERN_REST_ROT],
	])
	_add_keys(a, "lantern", "scale", [
		[0.0, Vector2.ONE],
		[t_hit, Vector2.ONE * lamp_scale_hit],
		[t_free, Vector2.ONE * lamp_scale_hit],
		[a.length, Vector2.ONE],
	])


func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = Z_IDLE_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 1.6, 1, 0.0)
	_add_sine(a, "body", "rotation", 0.20, 0.006, 1)
	_add_sine(a, "lantern", "rotation", 0.35, 0.030, 1, LANTERN_REST_ROT)
	_add_lamp_sway(a, 2.2, 1)
	_neutral_all(a)
	return a


func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = Z_WALK_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, 2.4, 2, 0.0)
	_add_sine(a, "body", "rotation", 0.22, 0.012, 1)
	## 走路时灯笼钟摆最明显：它是「光源在哪」的唯一读数
	_add_sine(a, "lantern", "rotation", 0.30, 0.085, 2, LANTERN_REST_ROT)
	_add_lamp_sway(a, 3.2, 2)
	_neutral_all(a)
	return a


## 灯笼的上下轻摆（position 是 Vector2，不能用 _add_sine 的 float 轨道）
func _add_lamp_sway(a: Animation, amp: float, cycles: int) -> void:
	if not _nodes.has("lantern"):
		return
	var home := _lamp_home()
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath("%s:position" % _node_path_of("lantern")))
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_CUBIC)
	var steps := maxi(12, cycles * 16)
	for k in range(steps + 1):
		var u := float(k) / float(steps)
		var v := home + Vector2(0.0, amp * sin(TAU * (float(cycles) * u)))
		a.track_insert_key(idx, u * a.length, v)


## ⚠ 下面每一对 `lamp_off_*` 都是**相对挂点**的位移（画布口径）。
##   第二轮换图后灯笼从「抬手平举」变成「垂手低提」（身体件 v2 的姿势），
##   挂点由 (207,-258) 掉到 (-40,19)，所以「举灯」类招式的幅度全部按新高度重排：
##   头顶在局部 y≈-339，要举过头就得给到 -330 左右，照旧给 -30 等于灯没动。

## 削影：整个人前压、灯往前送 —— 影子是从灯的反方向铺出去的，所以它往前倾就等于往后拉影
func _make_cut() -> Animation:
	var a := _skill_anim("cut")
	_pose(a, "cut", Vector2(-24.0, 12.0), Vector2(40.0, -6.0),
		-0.20, 0.26, -0.42, 0.58,
		Vector2(-12.0, 8.0), Vector2(26.0, -8.0), 1.05)
	return a


## 投晷：灯挑高、身体后坐 —— 光源抬高，地面那条影子被拉到最长
func _make_reach() -> Animation:
	var a := _skill_anim("reach")
	_pose(a, "reach", Vector2(-16.0, -18.0), Vector2(26.0, 6.0),
		0.14, -0.20, 0.30, -0.86,
		Vector2(0.0, -44.0), Vector2(-8.0, -104.0), 1.14)
	return a


## 缚影：蹲低压灯，指尖往地上按 —— 影身中段落印
func _make_bind() -> Animation:
	var a := _skill_anim("bind")
	_pose(a, "bind", Vector2(-10.0, 16.0), Vector2(14.0, 26.0),
		-0.10, 0.30, -0.16, 0.80,
		Vector2(6.0, 16.0), Vector2(16.0, 72.0), 1.08)
	return a


## 踏灯：整个人侧倾、灯甩向外侧 —— 位移招，判定帧人已经在半空
func _make_step() -> Animation:
	var a := _skill_anim("step")
	_pose(a, "step", Vector2(-20.0, 4.0), Vector2(46.0, -12.0),
		-0.26, 0.34, -0.55, 0.72,
		Vector2(-18.0, 6.0), Vector2(38.0, -16.0), 0.96)
	return a


## 明灭：手拢住灯芯，身体缩成一团 —— 全场唯一的光源在它手里变小
func _make_dim() -> Animation:
	var a := _skill_anim("dim")
	_pose(a, "dim", Vector2(0.0, -10.0), Vector2(0.0, 14.0),
		0.10, -0.14, 0.20, -0.30,
		Vector2(0.0, -10.0), Vector2(0.0, 12.0), 0.80)
	return a


## 照骨：把灯举到眉线、直直照出去（术法招，与影子无关）
func _make_beam() -> Animation:
	var a := _skill_anim("beam")
	_pose(a, "beam", Vector2(-12.0, -14.0), Vector2(20.0, -4.0),
		-0.06, 0.18, -0.30, 0.24,
		Vector2(-6.0, -60.0), Vector2(22.0, -156.0), 1.20)
	return a


## 分影：整个人往后仰，像把影子从脚底撕下来
func _make_split() -> Animation:
	var a := _skill_anim("split")
	_pose(a, "split", Vector2(-26.0, -8.0), Vector2(10.0, 18.0),
		0.24, -0.30, 0.42, -0.66,
		Vector2(-10.0, -8.0), Vector2(-18.0, 26.0), 1.10)
	return a


## 长夜 · 一灯：把灯一路举过头顶，全身拉直 —— 夺灯后第一次反照的终局招
func _make_longnight() -> Animation:
	var a := _skill_anim("longnight")
	_pose(a, "longnight", Vector2(-30.0, -26.0), Vector2(22.0, 12.0),
		0.30, -0.34, 0.55, -1.05,
		Vector2(-14.0, -120.0), Vector2(-10.0, -330.0), 1.26)
	return a
