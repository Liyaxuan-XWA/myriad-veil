class_name BossRig
extends Node2D

## 四足 BOSS 的「2D 骨骼」形象：一张定妆图拆成若干刚体件，用关节旋转驱动。
##
## ## 为什么不用序列帧
##
## 序列帧的每一格都是模型**独立重画的一只动物**，躯干轮廓帧帧不同（实测 8 帧 walk
## 的上半身 IoU 只有 0.93~0.96，招式更差）。播起来就是用户说的「脚动、身体在抽搐」，
## 而且**加密帧数只会让抽搐更频繁**。这里躯干始终是同一张贴图，只有关节在转，
## 结构上不可能抽搐 —— 这是唯一能真正做到「丝滑」的做法。
##
## ## 与序列帧的关系
##
## 只接管 **idle / walk**（移动时最常看到、也最容易被看出抽搐）。招式继续用序列帧：
## 招式是一次性的、每招 6 帧且姿态差异大，序列帧的「逐格重画」反而不明显，而骨骼化
## 每条招式都要单独 K 帧，投入产出不划算。
##
## ## 数据来源
##
## `BossRigData`（.tres）+ 一组分件 PNG，由 `tools/build_tiger_rig.py` 生成。
## 关节坐标、层级、z 顺序全在数据里，**换美术只要重跑那个脚本，本文件不用改**。
##
## ## 分层
##
## ```
## BossRig
## └── body（躯干，起伏/俯仰都作用在它身上）
##     ├── head
##     ├── tail1 → tail2（两节链，前段摆动后段自动跟随）
##     ├── leg_far_hind / leg_far_front      （远侧腿，z 在后面）
##     └── leg_near_hind / leg_near_front    （近侧腿，z 在前面）
## ```
##
## ⚠ 所有部件都挂在 body 下，不能做成兄弟节点：躯干一起伏，兄弟节点不跟随，
##   腿和身体的连接处会裂开。

# ===================== 动画参数（调手感只动这里）=====================

## 一个完整步态周期的时长。虎的步频本来就慢，0.9 秒接近真实成年虎慢走。
const WALK_CYCLE := 0.92
## 单腿最大摆角（弧度）。约 7°。
## ⚠ 这个值不是被「脚离地」卡住的，是被**关节白缝**卡住的：腿身转走后原位置必然空一块
##   （2D 刚体分块的固有矛盾，见 build_tiger_rig.py 的 body 注释），摆角越大缝越宽。
##   走路是常驻动作，缝不能有，所以只能小角度 + 靠躯干起伏和尾巴摆动撑住「在走」的观感。
##   招式是瞬时的，可以到 0.34（见 _make_slash）。
const WALK_LEG_SWING := 0.12
## 躯干上下起伏幅度（像素，画布口径。scale 0.25 时约 0.8 屏幕像素）
const WALK_BOB := 3.0
## 躯干俯仰幅度（弧度）
const WALK_PITCH := 0.016
## 头部反向补偿系数：动物走路时头是稳的，躯干俯仰要由颈部抵消掉大半
const HEAD_STABILISE := 0.75
## 尾巴摆角幅度（弧度）。约 8°。
## ⚠ 尾巴仍是「中线切」不是圆盘切，尾根接缝比腿敏感 —— 8° 是这个切法的上限。
##   要再大就得把尾巴也改成圆盘关节（见 build_tiger_rig.py 的 tail 分支）。
const TAIL_SWING := 0.14
## 尾末段的相位延迟（周期占比）：让尾巴像鞭子一样跟着走
const TAIL_LAG := 0.14

## 待机呼吸周期（秒）。刻意慢 —— 登录/战斗对峙时它是背景，不能催人。
const IDLE_CYCLE := 3.6
## 待机起伏幅度（像素）
const IDLE_BOB := 1.7
const IDLE_HEAD := 0.013
const IDLE_TAIL := 0.048

# ===================== 内部状态 =====================

var _data: BossRigData = null
var _nodes: Dictionary = {}          # part -> Node2D（关节节点）
var _sprites: Dictionary = {}        # part -> Sprite2D
var _player: AnimationPlayer = null
var _current: String = ""
var _frames: AnimatedSprite2D = null  # 招式序列帧覆盖层（见 attach_frames）
var _one_shot: String = ""
var _one_shot_uses_rig := false   # 这一发是骨骼招式还是序列帧覆盖层


## 用数据构建骨骼。返回是否成功（数据缺失/自检不过都返回 false，由上层回落到占位）。
func setup(data: BossRigData) -> bool:
	if data == null:
		push_warning("BossRig：数据为空")
		return false
	var err := data.validate()
	if err != "":
		push_warning("BossRig 数据自检失败：%s" % err)
		return false
	_data = data
	_build_nodes()
	if _nodes.is_empty():
		return false
	_build_animations()
	return true


## 便捷入口：直接从 .tres 路径加载
func setup_from_path(path: String) -> bool:
	if not ResourceLoader.exists(path):
		push_warning("BossRig：找不到 %s" % path)
		return false
	var res: Resource = load(path)
	var data := res as BossRigData
	if data == null:
		push_warning("BossRig：%s 不是 BossRigData（检查脚本是否 class_name 生效）" % path)
		return false
	return setup(data)


# ===================== 构建 =====================

func _build_nodes() -> void:
	var n := _data.size()
	# 第一遍：只建节点，不挂父子 —— 父节点可能排在自己后面
	for i in range(n):
		var part := String(_data.part_name[i])
		var holder := Node2D.new()
		holder.name = part
		# z 用绝对值：否则 tail2 挂 tail1 下会把 z 累加两次，尾巴跑到躯干前面
		holder.z_as_relative = false
		holder.z_index = int(_data.part_z[i])

		var spr := Sprite2D.new()
		spr.name = "Sprite"
		spr.centered = true
		var tex_path := String(_data.part_tex[i])
		var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
		if tex == null:
			push_warning("BossRig：部件 %s 的贴图缺失 → %s" % [part, tex_path])
			holder.queue_free()
			continue
		spr.texture = tex
		spr.position = _data.part_offset[i]
		holder.add_child(spr)

		_nodes[part] = holder
		_sprites[part] = spr

	# 第二遍：按 order 挂父子。添加顺序决定同 z 时的绘制次序，所以按数据给的顺序来。
	for part in _data.order:
		var holder: Node2D = _nodes.get(part, null)
		if holder == null:
			continue
		var idx := _data.index_of(part)
		var parent_name := String(_data.part_parent[idx])
		var parent_node: Node2D = self
		var pos: Vector2 = _data.part_joint[idx]
		if parent_name != "":
			var p: Node2D = _nodes.get(parent_name, null)
			if p != null:
				parent_node = p
				# 关节坐标是相对 rig 原点的，挂到父节点下要减掉父关节
				pos -= _data.part_joint[_data.index_of(parent_name)]
		parent_node.add_child(holder)
		holder.position = pos

	# 任何漏挂在 order 里的部件兜个底，别让它变成孤儿节点
	for part in _nodes.keys():
		var h: Node2D = _nodes[part]
		if h.get_parent() == null:
			add_child(h)
			h.position = _data.part_joint[_data.index_of(String(part))]


## 要生成哪些招式动画。子类覆写这里就能换整张招式表（见 boss_rig_human.gd）——
## ⚠ 别去覆写 `_build_animations`：那段是「建 AnimationPlayer + 装库 + 起播」的公共流程，
##   复制到子类里以后会两边漂移（例如这里以后加 idle 兜底，子类那份就漏了）。
func _skill_ids() -> Array:
	return SKILLS.keys()


func _build_animations() -> void:
	_player = AnimationPlayer.new()
	_player.name = "Anim"
	add_child(_player)
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _make_idle())
	lib.add_animation("walk", _make_walk())
	if _nodes.has("body"):
		for skill in _skill_ids():
			lib.add_animation(String(skill), _make_skill(String(skill)))
	_player.add_animation_library("", lib)
	_player.play("idle")
	_current = "idle"


# ===================== 招式（骨骼版）=====================
#
# 招式也用骨骼驱动，好处是**零成本、风格天然统一**（序列帧要重画 14 张）。
# 代价是表现力有上限：没有「肌肉隆起 / 毛发炸开 / 张口」，只有关节旋转与躯干缩放。
#
# ⚠ 设计原则：**以 body 为主**。body 是整块刚体，位移 / 旋转 / 缩放怎么动都不会露接缝；
#   腿的摆角受关节接缝限制（>10° 就会在关节处看到缝），只能做辅助动作。
#   力量感靠「躯干压低蓄力 → 突然前冲 + 挤压拉伸」表达，而不是靠腿挥多大。
#
# ⚠ 赛璐璐风格下躯干缩放是加分项（挤压拉伸是动画语言的一部分），写实风格下会露馅。
#
# 数据格式：[部件, 属性, [[秒, 值], ...]]。值为 Vector2 时写 Vector2，数值写 float。
# ⚠ 腿部摆角在招式里也**不能超过约 0.22（12.5°）** —— 超过就在关节处露白（实测 25°
#   时后腿根露出一块 20x15 的白色）。所以招式的主要表演手段是**躯干**：前后位移
#   （蓄力后拉 → 爆发前扑）、俯仰、挤压拉伸。腿只做小幅辅助。
const SKILLS := {
	"slash_single": {"length": 0.80},
	"smash": {"length": 0.85},
	"arrow": {"length": 0.78},
	"element_orb": {"length": 0.92},
	"arrow_volley": {"length": 0.72},
}


func _make_skill(skill: String) -> Animation:
	match skill:
		"slash_single":
			return _make_slash()
		"smash":
			return _make_smash()
		"arrow":
			return _make_arrow()
		"element_orb":
			return _make_orb()
		"arrow_volley":
			return _make_volley()
	return _make_slash()


## 把一串关键帧写进轨道。值类型由第一帧决定（Vector2 / float）。
func _add_keys(a: Animation, node: String, prop: String, keys: Array) -> void:
	if not _nodes.has(node):
		return
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath("%s:%s" % [_node_path_of(node), prop]))
	# ⚠ 旋转一律用 LINEAR，不能用 CUBIC。
	#   CUBIC 在「0.04 秒内从 +0.27 甩到 -0.68」这种急变上会严重过冲：实测腿冲到
	#   **-1.02 弧度**（超出设定 50%），而且过冲会拖进后面的定格段 → 定格时腿在抖，
	#   正好毁掉 hit-stop。LINEAR 没有过冲，关节动画也不缺那点平滑度。
	#   位移 / 缩放仍用 CUBIC：它们的过冲是「更有力」，不影响结构。
	a.track_set_interpolation_type(idx,
			Animation.INTERPOLATION_LINEAR if prop == "rotation" else Animation.INTERPOLATION_CUBIC)
	for k in keys:
		a.track_insert_key(idx, float(k[0]), k[1])


## 躯干基准位置（关节坐标里的 (0,0)，即 rig 原点）
func _body_rest() -> Vector2:
	return _data.part_joint[_data.index_of("body")]


## 虎爪横扫：慢蓄力 → 蓄满定住 → 极速爆发 → 打击定格 → 缓慢回收
##
## ⚠ 招式好不好看**几乎全在时间曲线**，不在幅度。第一版把关键帧均匀排开，结果是
##   匀速滑过去 —— 视觉上像「挪」不像「打」。真正的打击感来自速度的**极端对比**：
##   · 蓄力：0.225 秒走 28px（慢，让观众看见「在准备」）
##   · 爆发：0.03 秒走 80px（速度是蓄力的 9 倍，快到看不清过程）
##   · 定格：0.05 秒**完全不动**（hit-stop，大脑把它读成「打实了」）
##   这三段的比例是 38% / 6% / 10%，剩下是回收。
##
## ⚠ 「定住」是用**两个相邻且同值的关键帧**做出来的（0.225 与 0.245 同值）。
##   CUBIC 插值在同值 key 之间是平的，所以能停住；只靠「值变化小」停不住。
func _make_slash() -> Animation:
	var a := Animation.new()
	a.length = float(SKILLS["slash_single"]["length"])
	a.loop_mode = Animation.LOOP_NONE
	var b := _body_rest()

	# 时间轴比例是刻意这么分的（总长 0.80 = P1 前摇）：
	#   0.00~0.50  慢蓄力（62%）—— 让玩家看清「它在准备」
	#   0.50~0.53  蓄满顶住
	#   0.53~0.57  极速爆发（0.04 秒走完全程，速度是蓄力的 10 倍）
	#   0.57~0.73  打击定格（0.16 秒完全不动 = hit-stop，大脑读成「打实了」）
	#   0.73~0.80  收招（0.07 秒，收得干脆）
	# ⚠ 定格必须在**伤害判定那一帧之后**才结束：前摇结束即判定，也就是 0.80。
	#   所以定格一直保持到 0.73，绝不能提前回弹 —— 提前回弹就是「软」。
	_add_keys(a, "body", "position", [
		[0.000, b],
		[0.140, b + Vector2(0.0, 5.0)],
		[0.420, b + Vector2(-22.0, 13.0)],
		[0.500, b + Vector2(-32.0, 19.0)],   # 蓄满
		[0.530, b + Vector2(-32.0, 19.0)],   # 顶住
		[0.570, b + Vector2(52.0, -14.0)],   # 爆发：0.04 秒冲 90px
		[0.730, b + Vector2(52.0, -14.0)],   # 锁定在挥到底
		[0.800, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.000, 0.0], [0.420, -0.105], [0.500, -0.148], [0.530, -0.148],
		[0.570, 0.198], [0.730, 0.198], [0.800, 0.0],
	])
	# 挤压拉伸：蓄力压扁 → 爆发瞬间拉长 → 定格保持拉伸（别回弹，回弹就软了）
	_add_keys(a, "body", "scale", [
		[0.000, Vector2.ONE],
		[0.420, Vector2(1.05, 0.940)],
		[0.500, Vector2(1.07, 0.920)],
		[0.530, Vector2(1.07, 0.920)],
		[0.570, Vector2(0.90, 1.145)],
		[0.730, Vector2(0.91, 1.130)],
		[0.800, Vector2.ONE],
	])
	# 近侧前腿 = 「挥爪」本体。
	# 正角度 = 顺时针 = 爪子往后拉；负角度 = 逆时针 = 爪子往前挥。
	# 0.34 弧度 ≈ 19.5°：肩关节到爪尖约 340px（原图口径）→ 爪尖抬起约 114px，
	# 换算到游戏显示尺寸约 19 屏幕像素。
	#
	# ⚠ 这是「动作幅度」与「关节裂隙」的平衡点，两边都不能再让：
	#   · 小于 0.3（17°）→ 爪尖位移不到 16 屏幕像素，玩家又会说「腿不动」
	#   · 大于 0.5（29°）→ 腿身转走后留下的空洞在 1:1 下超过 15px，
	#     缩到游戏尺寸也有 4px，能看出「关节裂了」（实测 0.95 时洞 30px）
	#   2D 刚体分块的固有矛盾：腿身转走，原位置必然空一块。唯一的解是控制摆角。
	_add_keys(a, "leg_near_front", "rotation", [
		[0.000, 0.0], [0.140, 0.08], [0.420, 0.14], [0.500, 0.16],
		[0.530, 0.16],
		[0.570, -0.34], [0.730, -0.34],
		[0.800, 0.0],
	])
	# 腿同时拉长一点：旋转只能「摆」，沿腿轴拉长才是「蹬出去 / 抓到东西」的观感。
	# ⚠ 只能放大不能缩小：缩小会让圆盘小于 body 的洞，露出背景。
	_add_keys(a, "leg_near_front", "scale", [
		[0.000, Vector2.ONE], [0.500, Vector2(1.00, 0.97)], [0.530, Vector2(1.00, 0.97)],
		[0.570, Vector2(1.10, 1.09)], [0.730, Vector2(1.10, 1.09)], [0.800, Vector2.ONE],
	])
	# 远侧前腿跟着摆但幅度小、相位晚 —— 两条前腿同步会像「跳」
	_add_keys(a, "leg_far_front", "rotation", [
		[0.000, 0.0], [0.420, 0.08], [0.530, 0.08], [0.590, -0.26],
		[0.730, -0.26], [0.800, 0.0],
	])
	# 后腿：前挥瞬间往后蹬，是「发力」的支点
	_add_keys(a, "leg_near_hind", "rotation", [
		[0.000, 0.0], [0.500, -0.10], [0.530, -0.10], [0.570, 0.18],
		[0.730, 0.18], [0.800, 0.0],
	])
	_add_keys(a, "leg_far_hind", "rotation", [
		[0.000, 0.0], [0.530, 0.06], [0.570, -0.10], [0.730, -0.10], [0.800, 0.0],
	])
	# 头只做 1° 级微动（头的 mask 是多边形，转大了脖子会露白）
	_add_keys(a, "head", "rotation", [
		[0.000, 0.0], [0.500, 0.014], [0.570, -0.018], [0.730, -0.018], [0.800, 0.0],
	])
	# 尾巴滞后一拍甩出去 —— 次级运动是「活物感」的关键
	_add_keys(a, "tail1", "rotation", [
		[0.000, 0.0], [0.450, 0.100], [0.530, 0.100], [0.590, -0.160],
		[0.710, -0.060], [0.800, 0.0],
	])
	_add_keys(a, "tail2", "rotation", [
		[0.000, 0.0], [0.480, 0.120], [0.560, 0.120], [0.630, -0.180],
		[0.730, -0.060], [0.800, 0.0],
	])
	return a


## 碎岩下砸：前身抬起（后腿撑地）→ 双前爪高举 → 猛砸 + 躯干压扁 → 余震 → 缓起
func _make_smash() -> Animation:
	var a := Animation.new()
	a.length = float(SKILLS["smash"]["length"])
	a.loop_mode = Animation.LOOP_NONE
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.00, b],
		[0.22, b + Vector2(-6.0, -16.0)],
		[0.50, b + Vector2(-4.0, -26.0)],
		[0.53, b + Vector2(-4.0, -26.0)],
		[0.57, b + Vector2(8.0, 18.0)],
		[0.75, b + Vector2(6.0, 13.0)],
		[0.85, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.00, 0.0], [0.32, -0.10], [0.44, 0.06], [0.52, 0.02], [0.85, 0.0],
	])
	# 高举时拉长，砸下时压扁 —— 冲击力全靠这一下
	_add_keys(a, "body", "scale", [
		[0.00, Vector2.ONE],
		[0.32, Vector2(0.95, 1.07)],
		[0.44, Vector2(1.07, 0.93)],
		[0.52, Vector2(1.02, 0.98)],
		[0.85, Vector2.ONE],
	])
	# 两条前腿一起高举再砸下。蓄力段占 59%（慢慢抬起来让玩家看见），
	# 砸下只有 0.04 秒，然后定格 0.18 秒 —— 与横扫同一套「慢-爆-停」。
	_add_keys(a, "leg_near_front", "rotation", [
		[0.00, 0.0], [0.22, 0.14], [0.50, 0.34], [0.53, 0.34],
		[0.57, -0.10], [0.75, -0.10], [0.85, 0.0],
	])
	_add_keys(a, "leg_far_front", "rotation", [
		[0.00, 0.0], [0.24, 0.12], [0.52, 0.28], [0.55, 0.28],
		[0.59, -0.08], [0.75, -0.08], [0.85, 0.0],
	])
	# 后腿撑住、躯干抬起时略微前蹬
	_add_keys(a, "leg_near_hind", "rotation", [
		[0.00, 0.0], [0.32, -0.06], [0.44, 0.04], [0.85, 0.0],
	])
	_add_keys(a, "head", "rotation", [
		[0.00, 0.0], [0.32, 0.016], [0.44, -0.020], [0.56, -0.008], [0.85, 0.0],
	])
	_add_keys(a, "tail1", "rotation", [
		[0.00, 0.0], [0.32, -0.16], [0.46, 0.14], [0.60, -0.05], [0.85, 0.0],
	])
	_add_keys(a, "tail2", "rotation", [
		[0.00, 0.0], [0.36, -0.18], [0.50, 0.16], [0.64, -0.06], [0.85, 0.0],
	])
	return a


## 掷石：拱背蓄力 → 前爪拍地铲起 → 前身发力前送 → 重心前倾回稳
func _make_arrow() -> Animation:
	var a := Animation.new()
	a.length = float(SKILLS["arrow"]["length"])
	a.loop_mode = Animation.LOOP_NONE
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.00, b],
		[0.18, b + Vector2(-9.0, 6.0)],
		[0.30, b + Vector2(-12.0, 10.0)],
		[0.44, b + Vector2(10.0, -8.0)],
		[0.54, b + Vector2(20.0, -3.0)],
		[0.66, b + Vector2(12.0, 2.0)],
		[0.78, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.00, 0.0], [0.30, -0.06], [0.44, 0.05], [0.54, 0.03], [0.78, 0.0],
	])
	_add_keys(a, "body", "scale", [
		[0.00, Vector2.ONE],
		[0.30, Vector2(1.03, 0.96)],
		[0.44, Vector2(0.96, 1.05)],
		[0.60, Vector2.ONE],
	])
	# 拍地（后拉蓄力）→ 前挥甩出。与横扫同一套幅度，爪尖才看得见。
	_add_keys(a, "leg_near_front", "rotation", [
		[0.00, 0.0], [0.16, 0.12], [0.46, 0.24], [0.49, 0.24],
		[0.53, -0.32], [0.70, -0.32], [0.78, 0.0],
	])
	_add_keys(a, "leg_far_front", "rotation", [
		[0.00, 0.0], [0.30, 0.10], [0.48, 0.16], [0.52, 0.16],
		[0.58, -0.20], [0.70, -0.20], [0.78, 0.0],
	])
	_add_keys(a, "head", "rotation", [
		[0.00, 0.0], [0.30, 0.014], [0.48, -0.010], [0.78, 0.0],
	])
	_add_keys(a, "tail1", "rotation", [
		[0.00, 0.0], [0.30, 0.12], [0.50, -0.10], [0.78, 0.0],
	])
	_add_keys(a, "tail2", "rotation", [
		[0.00, 0.0], [0.34, 0.14], [0.54, -0.12], [0.78, 0.0],
	])
	return a


## 吐妖丹：伏身收颈 → 凝聚（躯干压紧、静止一拍）→ 前探喷出 → 头颈回落
## ⚠ 这招最吃亏：头是一整块贴图，**没有下颌关节**，做不出「张口」。
##   只能靠「收颈 → 猛地前探」+ 妖丹特效（SkillFx）表达，身体动作用来打拍子。
func _make_orb() -> Animation:
	var a := Animation.new()
	a.length = float(SKILLS["element_orb"]["length"])
	a.loop_mode = Animation.LOOP_NONE
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.00, b],
		[0.22, b + Vector2(-10.0, 8.0)],
		[0.42, b + Vector2(-14.0, 11.0)],
		[0.52, b + Vector2(-13.0, 10.0)],
		[0.64, b + Vector2(16.0, -6.0)],
		[0.74, b + Vector2(20.0, -2.0)],
		[0.86, b + Vector2(6.0, 2.0)],
		[0.92, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.00, 0.0], [0.42, -0.05], [0.64, 0.06], [0.74, 0.04], [0.92, 0.0],
	])
	# 蓄力时压紧（比 smash 更紧、更久），喷出时猛地拉长
	_add_keys(a, "body", "scale", [
		[0.00, Vector2.ONE],
		[0.22, Vector2(1.02, 0.97)],
		[0.42, Vector2(1.04, 0.95)],
		[0.52, Vector2(1.03, 0.96)],
		[0.64, Vector2(0.94, 1.08)],
		[0.78, Vector2(0.98, 1.02)],
		[0.92, Vector2.ONE],
	])
	# 前腿：伏身时下沉撑住，喷出瞬间前蹬一下（这招的表演主力是躯干前后，腿只打拍子）
	_add_keys(a, "leg_near_front", "rotation", [
		[0.00, 0.0], [0.42, 0.14], [0.55, 0.14], [0.64, -0.26],
		[0.78, -0.26], [0.92, 0.0],
	])
	_add_keys(a, "leg_far_front", "rotation", [
		[0.00, 0.0], [0.44, 0.12], [0.58, 0.12], [0.68, -0.18],
		[0.80, -0.18], [0.92, 0.0],
	])
	# 头：只做 1° 级的微动。「收颈低头 → 前探」这组动作本来该由头承担，但头的
	# 多边形切边转大了会露白，所以改由躯干的前后移动 + 俯仰代替，头只跟着颤一下。
	_add_keys(a, "head", "rotation", [
		[0.00, 0.0], [0.42, 0.018], [0.52, 0.016], [0.64, -0.022], [0.74, -0.015], [0.92, 0.0],
	])
	_add_keys(a, "tail1", "rotation", [
		[0.00, 0.0], [0.42, 0.08], [0.68, -0.09], [0.92, 0.0],
	])
	_add_keys(a, "tail2", "rotation", [
		[0.00, 0.0], [0.46, 0.10], [0.72, -0.11], [0.92, 0.0],
	])
	return a


## 砂石乱舞：上身左甩 → 甩出 → 反向右甩 → 再甩 → 回正
## 靠躯干的横向位移 + 偏转做出「急甩」，四条腿压住重心（只做小幅抵消）
func _make_volley() -> Animation:
	var a := Animation.new()
	a.length = float(SKILLS["arrow_volley"]["length"])
	a.loop_mode = Animation.LOOP_NONE
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.00, b],
		[0.14, b + Vector2(-14.0, 3.0)],
		[0.24, b + Vector2(-17.0, 4.0)],
		[0.36, b + Vector2(15.0, 2.0)],
		[0.46, b + Vector2(18.0, 3.0)],
		[0.58, b + Vector2(-6.0, 1.0)],
		[0.72, b],
	])
	# 甩的方向由躯干旋转表达 —— 左右急摆是这招的主体
	_add_keys(a, "body", "rotation", [
		[0.00, 0.0], [0.14, -0.07], [0.24, -0.09], [0.36, 0.08], [0.46, 0.10],
		[0.58, -0.03], [0.72, 0.0],
	])
	_add_keys(a, "head", "rotation", [
		[0.00, 0.0], [0.14, -0.012], [0.36, 0.014], [0.46, 0.016], [0.72, 0.0],
	])
	# 四条腿小幅反向抵消，看起来像「站住了在甩上身」
	_add_keys(a, "leg_near_front", "rotation", [
		[0.00, 0.0], [0.24, 0.10], [0.46, -0.08], [0.72, 0.0],
	])
	# 乱舞是「上身左右急甩」，前腿跟着重心左右挪一点 —— 幅度不用大，但不能是死的
	_add_keys(a, "leg_near_front", "rotation", [
		[0.00, 0.0], [0.14, 0.20], [0.30, -0.16], [0.48, 0.22],
		[0.60, -0.14], [0.72, 0.0],
	])
	_add_keys(a, "leg_far_front", "rotation", [
		[0.00, 0.0], [0.18, 0.14], [0.34, -0.11], [0.52, 0.15],
		[0.64, -0.09], [0.72, 0.0],
	])
	_add_keys(a, "tail1", "rotation", [
		[0.00, 0.0], [0.16, 0.14], [0.32, -0.14], [0.48, 0.10], [0.60, -0.05], [0.72, 0.0],
	])
	_add_keys(a, "tail2", "rotation", [
		[0.00, 0.0], [0.20, 0.16], [0.36, -0.16], [0.52, 0.12], [0.64, -0.06], [0.72, 0.0],
	])
	return a


## 部件在 rig 内的相对节点路径（"body/head"、"body/tail1/tail2"）。
## ⚠ 不能直接用部件名当 track path：所有部件都挂在 body 下（躯干起伏要带着它们走），
##   扁平写 "head:rotation" 会让 AnimationPlayer 在 rig 根下找不到节点，
##   运行期只报一句 "couldn't resolve track" 然后**整条轨道静默失效** ——
##   表现就是「骨骼搭好了但一动不动」，很难查。
func _node_path_of(part: String) -> String:
	var segs: Array[String] = [part]
	var cur := part
	var guard := 0
	while guard < 8:
		guard += 1
		var idx := _data.index_of(cur)
		if idx < 0:
			break
		var parent := String(_data.part_parent[idx])
		if parent == "":
			break
		segs.push_front(parent)
		cur = parent
	return "/".join(segs)


## 往动画里加一条正弦循环轨道。
## ⚠ 结束键必须与起始键同值，否则循环点会跳一下 —— 这里用「整数倍频程」保证：
##   u 从 0 到 1，cycles 为整数时 sin(TAU*cycles) == sin(0)。
func _add_sine(a: Animation, node: String, prop: String, phase: float,
		amp: float, cycles: int, base_v: float = 0.0, samples: int = 0) -> void:
	if not _nodes.has(node):
		return
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath("%s:%s" % [_node_path_of(node), prop]))
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_CUBIC)
	var steps: int = samples if samples > 0 else maxi(8, cycles * 12)
	for k in range(steps + 1):
		var u := float(k) / float(steps)
		var v := base_v + amp * sin(TAU * (float(cycles) * u + phase))
		a.track_insert_key(idx, u * a.length, v)


## 躯干起伏（Vector2 轨道）：走路时每落一次脚起伏一次 → 2 倍频；待机只做呼吸。
func _add_body_bob(a: Animation, amp: float, cycles: int, phase: float) -> void:
	if not _nodes.has("body"):
		return
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath("%s:position" % _node_path_of("body")))
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_CUBIC)
	var steps := maxi(12, cycles * 16)
	# body 的静止位置就是 rig 原点（关节坐标里的 (0,0)）
	var base_pos: Vector2 = _data.part_joint[_data.index_of("body")]
	for k in range(steps + 1):
		var u := float(k) / float(steps)
		var v := base_pos + Vector2(0.0, amp * sin(TAU * (float(cycles) * u + phase)))
		a.track_insert_key(idx, u * a.length, v)


## 走路：真实四足侧序步态 左后 → 左前 → 右后 → 右前，各差 1/4 周期。
## 侧视图里「近侧」= 面对镜头那一侧的腿（本项目美术朝右，所以近侧是虎的左侧）。
func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = WALK_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	var legs := {
		"leg_near_hind": 0.00,
		"leg_near_front": 0.25,
		"leg_far_hind": 0.50,
		"leg_far_front": 0.75,
	}
	for part in legs.keys():
		_add_sine(a, String(part), "rotation", float(legs[part]), WALK_LEG_SWING, 1)
	# 躯干：2 倍频上下起伏 + 1 倍频俯仰
	_add_body_bob(a, WALK_BOB, 2, 0.0)
	_add_sine(a, "body", "rotation", 0.25, WALK_PITCH, 1)
	# 头反向抵消躯干俯仰，避免走路时头跟着点
	_add_sine(a, "head", "rotation", 0.75, -WALK_PITCH * HEAD_STABILISE, 1)
	# 尾巴：前段慢摆，末段滞后一点 —— 鞭子感全靠这个相位差
	_add_sine(a, "tail1", "rotation", 0.10, TAIL_SWING, 1)
	_add_sine(a, "tail2", "rotation", 0.10 - TAIL_LAG, TAIL_SWING * 1.25, 1)
	_neutral_all(a)
	return a


## 待机：只有呼吸、头微动、尾慢摆，四条腿完全不动 —— 站桩时腿动才是假的。
func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = IDLE_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, IDLE_BOB, 1, 0.0)
	_add_sine(a, "head", "rotation", 0.32, IDLE_HEAD, 1)
	_add_sine(a, "tail1", "rotation", 0.12, IDLE_TAIL, 1)
	_add_sine(a, "tail2", "rotation", 0.12 - TAIL_LAG, IDLE_TAIL * 1.3, 1)
	_neutral_all(a)
	return a


## 给循环动画补齐「归零轨道」：任何被某条一次性动画写过的属性，
## 在 idle / walk 里也必须有轨道，否则播完一次性动画后会永久停在最后一帧的值上。
##
## ⚠ 这条坑踩过两次，代价都是「功能看起来坏了」：
##   第一次是 body 的 rotation / scale——招式播完躯干永久歪着，玩家看到「只有变形没动作」；
##   第二次是 leg_near_front 的 rotation——收招后那条前腿永远卡在 -0.36 弧度。
## ⚠ 用 find_track 查重，只在缺的时候补：同一属性加两条轨道，后加的会盖掉正弦摆动。
func _neutral_all(a: Animation) -> void:
	for part in _nodes.keys():
		var key := String(part)
		var path := _node_path_of(key)
		if a.find_track(NodePath("%s:rotation" % path), Animation.TYPE_VALUE) < 0:
			_add_keys(a, key, "rotation", [[0.0, 0.0], [a.length, 0.0]])
		if a.find_track(NodePath("%s:scale" % path), Animation.TYPE_VALUE) < 0:
			_add_keys(a, key, "scale", [[0.0, Vector2.ONE], [a.length, Vector2.ONE]])


# ===================== 对外接口 =====================

## 一次性动作是否**真的播到底**了。
##
## ⚠ 为什么不能只信计时器：`SkinVisual` 用 `_process(delta)` 倒计时结束动作，
##   delta 是**引擎帧时长**；而招式动画是按 `speed_scale` 推进的。首帧（进场 / 卡顿 /
##   从主城切进战斗）delta 可能高达 0.18 秒，计时器一下少掉 18%，动画却只走了 15%，
##   两者错位 —— 实测横斩「挥到一半就回待机」，命中定格整段被吞掉，
##   玩家看到的就是「抬手然后站着，没有砍下去那一下」。
##   所以骨骼招式以动画播放头为准，计时器只做兜底（见 SkinVisual._process）。
func one_shot_finished() -> bool:
	if _one_shot == "":
		return true
	if _player == null or not _one_shot_uses_rig:
		return true
	if _player.current_animation != _one_shot:
		return true
	if not _player.is_playing():
		return true
	var total := _player.get_animation(_one_shot).length
	return _player.current_animation_position >= total - 0.005


## 切换循环动画（"walk" / "idle"）。名字不认识时退回 idle，不报错。
func play_loop(anim: String) -> void:
	if _player == null:
		return
	var target := anim if _player.has_animation(anim) else "idle"
	if target == _current:
		return
	_current = target
	_player.play(target)


## 部位是否齐全（外部做自检用）
func has_part(part: String) -> bool:
	return _nodes.has(part)


func part_names() -> Array:
	return _nodes.keys()


## 把所有关节归位到静态造型（动画停掉、rotation 清零）。
## 用途：① 诊断「拆件是否完整」的基准 —— 归位后必须和定妆图逐像素一致；
##       ② BOSS 死亡 / 出场定格时让它站定不抽。
func reset_pose() -> void:
	if _player != null:
		_player.stop()
	_current = ""
	for part in _nodes.keys():
		var n: Node2D = _nodes[part]
		if is_instance_valid(n):
			n.rotation = 0.0
	var body: Node2D = _nodes.get("body", null)
	if body != null and _data != null:
		body.position = _data.part_joint[_data.index_of("body")]
		body.scale = Vector2.ONE


## 画布尺寸的一半 —— 与序列帧的 `_raw_half_size()` 同口径，两套素材可以直接互换
func half_size() -> Vector2:
	if _data == null:
		return Vector2.ZERO
	return Vector2(float(_data.canvas.x), float(_data.canvas.y)) * 0.5


## 供 SkinVisual 的残影快照用：返回躯干贴图（残影只需要一个近似轮廓）
func body_texture() -> Texture2D:
	var spr: Sprite2D = _sprites.get("body", null)
	return spr.texture if spr != null else null


## 关节世界坐标（调试 / 特效定位用）
func joint_position(part: String) -> Vector2:
	var n: Node2D = _nodes.get(part, null)
	return n.global_position if n != null else global_position


## 部件的挂点节点：外部要往手上 / 角上挂东西时走这里，别自己拼节点路径
func part_node(part: String) -> Node2D:
	return _nodes.get(part, null)


## 出招原点（世界坐标）：嘴 / 爪尖 / 刀尖。
##
## 按**动作名**查数据里的锚点表，取该部件的当前世界变换 + 部件本地偏移 ——
## 所以甩爪到一半时原点在挥出去的爪尖上，静止时在原来的位置，不需要逐帧算。
## ⚠ 返回 Variant：该动作没登记（或没有骨骼）返回 null，由调用方回落到默认口径。
##   写死 global_position 当兜底是不行的 —— 那正是「妖丹从胸口冒出来」的原因。
## ⚠ 招式是用 `play_one_shot` 压时间播的，伤害判定那一帧的关节角度就是这个时刻的角度，
##   所以「锚点跟着动作走」天然与实际出手姿态一致。
func muzzle_position(anim: String) -> Variant:
	if _data == null:
		return null
	var idx := _data.muzzle_index(anim)
	if idx < 0:
		return null
	var node: Node2D = _nodes.get(String(_data.muzzle_part[idx]), null)
	if node == null:
		return null
	return node.to_global(_data.muzzle_offset[idx])


# ===================== 招式：序列帧覆盖层 =====================
#
# 骨骼只接管 idle / walk。招式继续用原来的 6 帧序列帧 —— 招式是一次性的、每招姿态
# 差异大，「逐格重画」的毛病反而不明显；而骨骼化每条招式都要单独 K 帧，投入产出不
# 划算。两套素材的画布完全相同（1100×820、脚底同一基线），所以可以直接叠在一起，
# 出招时隐藏骨骼、显示序列帧，两者不会错位。

## 挂上序列帧（招式用）。sf 为空/无动画时返回 false，骨骼照常工作。
func attach_frames(sf: SpriteFrames) -> bool:
	if sf == null or sf.get_animation_names().is_empty():
		return false
	if _frames != null and is_instance_valid(_frames):
		_frames.queue_free()
	_frames = AnimatedSprite2D.new()
	_frames.name = "Frames"
	_frames.sprite_frames = sf
	_frames.centered = true
	_frames.visible = false
	add_child(_frames)
	return true


## 是否有这个动作。**骨骼招式优先** —— 招式已全部改成骨骼驱动（零成本、风格统一），
## 序列帧只在骨骼没有该动画时兜底（兼容旧素材 / 未迁移的招式）。
func has_animation(anim: String) -> bool:
	if _player != null and _player.has_animation(anim):
		return true
	return _frames != null and _frames.sprite_frames != null \
			and _frames.sprite_frames.has_animation(anim)


## 该动画按资源原速播一遍需要多久（秒）。没有这个动画返回 0。
## SkinVisual 用它把整段压进后摇时长（speed_scale），与序列帧路径同一套换算。
func animation_length(anim: String) -> float:
	if _player != null and _player.has_animation(anim):
		return _player.get_animation(anim).length
	if _frames == null or _frames.sprite_frames == null \
			or not _frames.sprite_frames.has_animation(anim):
		return 0.0
	var sf := _frames.sprite_frames
	var fps := maxf(sf.get_animation_speed(anim), 1.0)
	return float(sf.get_frame_count(anim)) / fps


## 播一次招式：隐藏骨骼、显示序列帧。duration <= 0 时按资源原速。
## ⚠ 同一个动作重复调用会直接返回 —— SkinVisual 在状态刷新时可能连续调它，
##   每次重设 speed_scale 会让动画重启、卡在第 0 帧。
func play_one_shot(anim: String, duration: float = -1.0) -> bool:
	# ⚠ 只在「同一招正在播」时才跳过重入。写成 `if _one_shot == anim: return true`
	#   会让同一招的**第二次**释放完全不播 —— 上一发播完后 _one_shot 没有清（清它的是
	#   SkinVisual 的倒计时，而那个倒计时只处理序列帧），于是第二次起永远被挡住。
	if _one_shot == anim and _player != null and _one_shot_uses_rig \
			and _player.current_animation == anim and _player.is_playing():
		return true
	var use_rig := _player != null and _player.has_animation(anim)
	if not use_rig and not has_animation(anim):
		return false
	var natural := animation_length(anim)
	var target := (maxf(duration, 0.02) if duration > 0.0 else natural)
	_one_shot = anim
	_one_shot_uses_rig = use_rig
	if use_rig:
		# 骨骼招式：**不隐藏骨骼**，直接把整段动画压进目标时长
		_player.speed_scale = natural / maxf(target, 0.02)
		_player.play(anim)
		_show_frames(false)
	else:
		_frames.speed_scale = natural / maxf(target, 0.02)
		_frames.animation = anim
		_frames.frame = 0
		_frames.play(anim)
		_show_frames(true)
	return true


## 收起招式，回到骨骼（idle / walk）
func stop_one_shot() -> void:
	if _one_shot == "":
		return
	var was_rig := _one_shot_uses_rig
	_one_shot = ""
	_one_shot_uses_rig = false
	if was_rig:
		if _player != null:
			_player.speed_scale = 1.0
		# 双保险：循环动画的归零轨道要等下一帧才生效，这里先手动按回中性，
		# 避免看到一帧的残留变形
		var body_node: Node2D = _nodes.get("body", null)
		if body_node != null:
			body_node.rotation = 0.0
			body_node.scale = Vector2.ONE
		# 清掉 _current，让紧随其后的 play_loop 真正重新播 idle/walk
		# （play_loop 有「同名就跳过」的防重，不清会把刚播完的招式当成正在播的循环）
		_current = ""
	else:
		if _frames != null and is_instance_valid(_frames):
			_frames.stop()
			_frames.speed_scale = 1.0
		_show_frames(false)


func _show_frames(on: bool) -> void:
	if _frames != null and is_instance_valid(_frames):
		_frames.visible = on
	for part in _nodes.keys():
		var n: Node2D = _nodes[part]
		if is_instance_valid(n):
			n.visible = not on


## 当前正在显示的贴图（残影快照用）：招式期间给当前帧，否则给躯干
func current_texture() -> Texture2D:
	if _frames != null and is_instance_valid(_frames) and _frames.visible:
		var sf := _frames.sprite_frames
		if sf != null and sf.has_animation(_frames.animation):
			var count := sf.get_frame_count(_frames.animation)
			if count > 0:
				return sf.get_frame_texture(_frames.animation,
						clampi(_frames.frame, 0, count - 1))
	return body_texture()
