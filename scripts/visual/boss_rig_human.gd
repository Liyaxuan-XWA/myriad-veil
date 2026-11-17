class_name BossRigHuman
extends BossRig

## 人形持械 BOSS 的骨骼动画集（刀客）。继承 `BossRig`，只换掉动画内容。
##
## ## 为什么单独一个类
##
## `BossRig` 里的招式表是**四足**的（爪 / 尾 / 四条腿的相位），人形是另一套关节
## （肩 / 髋 / 刀）。硬塞进同一个类会变成两套 `match` 互相干扰；
## 而拆开之后，换一只人形 BOSS 只要重跑拆件脚本、换 `rig.tres`，本文件不动。
##
## ## 关节与自由度
##
## ```
## body（躯干 + 头，负重/位移/缩放/俯仰都作用在它身上）
##   ├── arm         肩 ———— 持刀上臂（挥砍的鞭打发力全靠它 + 前臂）
##   │   └── arm_fore 肘 ———— 前臂 + 拳 + 刀
##   ├── pauldron    肩甲 —— ⚠ 静态件，只挂不转（见下）
##   ├── leg_front   髋 ———— 朝向前方那条腿（美术朝右 → 画布右侧）
##   └── leg_back    髋 ———— 后腿
##
## ⚠ **肩甲单独一件**：它原本画在上臂贴图里，于是「抬臂」= 整块肩甲滑到肘部，
##   肩头同时留下一坨重涂糊。拆成 `pauldron` 挂 body、z 排在 arm 与 arm_fore
##   之间（盖住上臂根、被前臂压过），`--fan arm` 七格里肩甲全部原位。
## ```
##
## ⚠ **没有独立的头**：第一版按虎妖的思路拆了 `head`，结果 `HEAD_POLY` 只圈住
##   一小块，剩下大半个头留在 body 里 —— 头一转画面上就有**两个头**。
##   人形 BOSS 的头本来也只做 1° 级微动，收益抵不上风险，所以头并入躯干：
##   躯干的旋转/俯仰/挤压带着头一起动，已经够「活」。
##
## ⚠ **肘关节**（2026-10-26 推倒重来）：挥刀的角度设计在 `_strike` 头注释里，
##   核心 = **先定刀尖朝向再反解肩肘**；前臂轨道「中段走 55%、肩只走 25%」
##   做出手领先于肩的鞭打感。⚠ 拆件脚本曾把 arm_fore 的 part_joint 写成
##   「相对父关节」口径，引擎把肘放到腰部、整条挥刀全错 —— 详见
##   `tools/build_daoke_rig.py` 的注释，换定妆图重跑时别再犯。
##
## ## 时间曲线
##
## 与虎妖同一套手法（详见 boss_rig.gd 的 `_make_slash` 注释）：
## **慢蓄力（~60%）→ 蓄满定住 → 0.04 秒极速爆发 → 打击定格 → 干脆回收**。
## 定格用「两个相邻同值关键帧」做，靠 CUBIC 插值在同值间是平的。
## 旋转轨道一律 LINEAR（CUBIC 在急变上会过冲 50%，见 `_add_keys`）。
##
## ⚠ **打击时刻必须换算**：动画会被 `play_one_shot` 压进 `windup + 0.15` 秒，
##   所以「伤害判定那一帧」在动画时间轴上不是 windup，而是 windup×length/(windup+0.15)。
##   见 `_hit_time`。第一版直接把 windup 当秒数用，爆发帧排到了动画长度之外 ——
##   表现是「挥到一半就收刀，刀从没砍到人」。

# ===================== 动画参数 =====================
#
# ⚠ 常量名统一带 `H_` 前缀。GDScript **不允许子类重定义父类已有的成员**
#   （报 "The member IDLE_CYCLE already exists in parent class BossRig"，整脚本 parse error
#   → SkinVisual 静默回落四足骨骼 → 人形 BOSS 用虎的招式表，表现是「人不动、只有飘字」）。
#   父类那些值是**四足**的手感（步频 0.92、腿摆 0.12），人形完全是另一套，不能复用。

## 待机呼吸周期（秒）。慢一点 —— 对峙时它是背景
const H_IDLE_CYCLE := 3.2
const H_IDLE_BOB := 1.4
const H_IDLE_BODY_ROT := 0.006
const H_IDLE_ARM := 0.014

## 走路周期（秒）。人比虎快，0.78 接近正常的慢走
const H_WALK_CYCLE := 0.78
## 单腿摆角（弧度）。⚠ 刀客的腿是从**裙摆下方**切出来的，摆大了裙摆边缘会露缝，
## 0.20（11.4°）是实测能接受的上限；再大就要把髋关节往上挪、让裙摆跟着腿走。
const H_WALK_LEG_SWING := 0.20
const H_WALK_BOB := 2.2
const H_WALK_BODY_ROT := 0.012
## 走路时持刀臂的反向摆动（很轻 —— 刀垂在身侧、离肘 400px，肩角一晃刀尖就划一大片）
const H_WALK_ARM_SWING := 0.035

## 招式表：动画名 → {length: 按原速设计多长, windup: 玩法里这一招的前摇}
## ⚠ windup 必须与 MoveDB 的 `form_blade_*` 对齐 —— 对齐之后「刀落到最低点」
##   正好是判定发生的那一帧，玩家看刀就知道打到哪（这一招没有红圈 / 没有 UI 预警）。
const H_SKILLS := {
	"slash_h": {"length": 0.85, "windup": 0.85},
	"smash_v": {"length": 1.25, "windup": 1.25},
	"dash_slash": {"length": 0.70, "windup": 0.70},
	"stomp_aoe": {"length": 0.75, "windup": 0.75},
	"palm_project": {"length": 0.65, "windup": 0.65},
	## 纳势反击：前摇 3 秒（架着等你打），动画按 1.8 秒设计 → 放慢播，
	## 观感是「稳稳架住」，而不是「挥得飞快然后站着不动」
	"guard_charge": {"length": 1.80, "windup": 3.00},
	"ult_windup": {"length": 1.20, "windup": 1.10},
}


# ===================== 构建 =====================

## 招式表。子类覆写这里就能换整张表（见 boss_rig_swordsman.gd）——
## ⚠ 不要再各自覆写 `_skill_anim` / `_hit_time`：那两处只是查表的机械换算，
##   复制一份到子类，以后改公式就会两边漂移。
func _skill_table() -> Dictionary:
	return H_SKILLS


## 要生成哪些招式动画
func _skill_ids() -> Array:
	return _skill_table().keys()


func _make_skill(anim: String) -> Animation:
	match anim:
		"slash_h":
			return _make_slash_h()
		"smash_v":
			return _make_smash_v()
		"dash_slash":
			return _make_dash()
		"stomp_aoe":
			return _make_stomp()
		"palm_project":
			return _make_qi()
		"guard_charge":
			return _make_guard()
		"ult_windup":
			return _make_ult()
	return _make_slash_h()


## 新建一条一次性动画，长度按 H_SKILLS
func _skill_anim(anim: String) -> Animation:
	var a := Animation.new()
	a.length = float(_skill_table()[anim]["length"])
	a.loop_mode = Animation.LOOP_NONE
	return a


## 「伤害判定那一帧」在**动画时间轴**上的位置（秒）。
##
## `play_one_shot` 会把整段压进 `windup + 0.15`（speed_scale = length / (windup+0.15)），
## 即动画时间 t 对应真实时间 `t × (windup+0.15) / length`；
## 令真实时间 = windup 反解，得 t_hit = windup × length / (windup + 0.15)。
##
## ⚠ 直接把 windup 当秒数写进关键帧是错的（第一版就错在这）：两者的关系随
##   windup/length 变化，短招差 15%，guard_charge 这种 3 秒前摇差 30% ——
##   结果是爆发帧被排到动画长度之外，永远播不到，看起来就是「挥到一半收刀」。
func _hit_time(anim: String) -> float:
	var length := float(_skill_table()[anim]["length"])
	var windup := float(_skill_table()[anim]["windup"])
	return windup * length / (windup + 0.15)


## 真实秒 → 动画秒。动画被压进 `windup + 0.15` 播放，所以动画里的 1 秒
## 等于真实世界的 `length / (windup + 0.15)` 秒。**编排动作要按真实秒算**，
## 否则「挥刀 0.04 秒」这种数字看着小、实际可能只有 2 帧。
func _real_to_anim(anim: String, real_sec: float) -> float:
	var length := float(_skill_table()[anim]["length"])
	var windup := float(_skill_table()[anim]["windup"])
	return real_sec * length / (windup + 0.15)


## 通用「慢蓄力 → 蓄满顶住 → 极速爆发 → 打击定格 → 回收」曲线（躯干 + 肩 + 肘）
##
## pull     蓄力时的躯干位移（相对静止位）
## push     爆发时的躯干位移
## arm_back 蓄力时的肩角（⚠ 负 = 往上/前抬，见下面的口径）
## arm_hit  爆发时的肩角
## t_hit    判定时刻（动画时间轴，见 _hit_time）
## elbow_back 蓄力时前臂相对上臂的角（负 = 反折、把刀收向脑后；正 = 顺折、把刀压向地面）
## elbow_hit  命中时的肘角（展开=接近 0 的小弯；插地那招故意留大正折）
##
## ⚠ 挥刀角度设计（2026-10-26 换「垂刀式」定妆图后重做）
##
##   口径：**静止指向 +70.0°** —— 新 rig 是正常垂刀（刀尖朝前下、几乎垂直挂在身侧），
##   不是旧版「刀横扛在肩上」。肘→刀尖 (137,377)，刀长 400px。
##   任意时刻  刀尖朝向 = +70° + 躯干俯仰 + 肩角 + 肘角
##   （画布口径、y 向下，0° = 正前方，+90° = 正下方，负 = 上方；
##   刚体链上角度能直接相加，所以三个量随便怎么分配都不改变刀尖朝向。）
##
##   ⚠ **符号与旧版相反**：现在负角 = 把刀往上/前抬，正角 = 往下/后压。
##   旧扛刀 rig 静止指向 −37.5°、抬手是正角 —— 照抄旧数字会得到反向的挥刀。
##   （更早那版「arm_fore 的 part_joint 写成相对父关节、整条挥刀绕着腰转」的坑
##   见本文件头与 tools/build_daoke_rig.py 的注释，重跑拆件时别再犯。）
##
##   方法：**先定刀尖朝向，再反解肩肘**，不要先拍肩角再看刀尖去哪：
##     肩角 = 目标朝向 − 70° − 躯干俯仰 − 肘角
##   肩肘怎么分不影响刀尖朝向，只决定**手肘摆在哪、刀尖落在哪**：
##   过顶劈 = 肩多转 + 肘反折（刀收到脑后）；低扫 = 肩多转 + 肘正折（刀贴地走）；
##   插地 = 肩少转 + 肘大正折（手抬到腰前、刀垂直扎下去）。
##
##   | 招式 | 蓄力时刀指向 | 命中时刀指向 | 弧线 |
##   |---|---|---|---|
##   | 横斩 | 后下 +115° | **前上 −15°** | 低拔高撩，收在头部高度 |
##   | 沉步竖斩 | 过顶 −100° | 前下 +65° | 过顶下劈 |
##   | 破步突进斩 | 后下 +125° | 前下 +25° | 贴地低平前扫 |
##   | 封路刀域 | 前上 −70° | 垂直 +88° | 高举插进脚下地面 |
##   | 刀气追击 | 后下 +110° | 前平 +10° | 身前平扫推出去 |
##   | 满势断岳 | 过顶 −105° | 下 +75° | 最高举、最沉的一记下劈 |
##
##   ⚠ 六招的命中角**必须彼此拉开**：换 rig 后第一版把突进斩和横斩都收到
##   −5°/−15°，两招在画面上是同一刀。现在按命中刀尖的高度分层：
##   横斩 174 / 刀气 371 / 突进 481 / 竖斩 675 / 断岳 695 / 刀域 716。
##   改完务必出表看一遍（一张格子里 蓄/中/命 三帧，标题带刀尖角度和落点）：
##     python tools/render_rig_pose.py --rig <rig.tres> --keys <招式表.json> --cols 3
##
##   中段（t_mid）：肩只走 25%、前臂走 55% —— **手领先于肩**，这是「鞭打」的
##   最小表达。不用「肘冲过命中角再回摆」的花活（在错几何上叠花活只会更乱）。
##
## ⚠ 时间比例是刻意的：爆发只用 0.04 秒（速度是蓄力的十倍以上），
##   之后 **定格** 到 t_free 完全不动 —— 大脑把「突然停住」读成「打实了」。
##   提前回弹就软，所以定格必须一直盖到判定之后。

func _strike(a: Animation, anim: String, pull: Vector2, push: Vector2,
		arm_back: float, arm_hit: float, rot_back: float, rot_hit: float,
		squash: Vector2, hold_extra: float = 0.0,
		elbow_back: float = 0.0, elbow_hit: float = 0.0) -> void:
	## ⚠ 全部时间按**真实秒**编排，再换算成动画秒。玩家看到的是真实时间。
	##
	## 阶段划分（windup = 这一招的前摇时长 W）：
	##   0    → 0.50W   蓄力：刀慢慢拉到身后（这段本来就该慢，要让玩家看清"在准备"）
	##   0.50W → 0.85W  挥砍：**0.35W 秒的可见挥击**（W=0.85 时约 0.30 秒 ≈ 18 帧）
	##   0.85W → W      定格：刀压在最低点，正好盖住伤害判定那一帧（hit-stop）
	##   W    → W+0.15  收招（剩余时间由 D = W+0.15 决定）
	##
	## ⚠ 2026-10-26 用户反馈「释放技能时需要大幅的挥刀动作」时改的：
	##   旧版把爆发压到 0.04 秒 —— 60 帧下只有 2~3 帧，眼睛只看到一闪，
	##   根本读不出"挥"。实测帧序列：38 帧举刀 + 2 帧挥砍。
	##   现在挥击占整段前摇的 35%，**看得见**才算"大幅"。
	##
	## ⚠ 挥击**早于**判定结束（0.85W < W）：刀先到位、然后停住，伤害在停顿里落下。
	##   这样既有打击感，又不会「刀还在飞、伤害先到」。
	var windup := float(_skill_table()[anim]["windup"])
	var t_hit := _hit_time(anim)
	var t_pull := _real_to_anim(anim, windup * 0.50)
	var t_swing := _real_to_anim(anim, windup * 0.85)
	var t_mid := t_pull + (t_swing - t_pull) * 0.42
	var t_free := minf(t_hit + _real_to_anim(anim, 0.08 + hold_extra), a.length - 0.005)
	var b := _body_rest()
	# 躯干先动、肩臂后到（鞭子感）：身体的前冲比手臂早一点点到位
	_add_keys(a, "body", "position", [
		[0.0, b],
		[t_pull * 0.55, b + pull * 0.45],
		[t_pull, b + pull],
		[t_swing, b + push],
		[t_free, b + push],
		[a.length, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [t_pull, rot_back], [t_swing, rot_hit],
		[t_free, rot_hit], [a.length, 0.0],
	])
	# 挤压拉伸：蓄力压紧 → 挥到位时拉长 → 定格保持（回弹就软了）
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE],
		[t_pull, squash],
		[t_swing, Vector2(2.0 - squash.x, 2.0 - squash.y)],
		[t_free, Vector2(2.0 - squash.x, 2.0 - squash.y)],
		[a.length, Vector2.ONE],
	])
	# 肩臂：慢起 → 中段最快 → 到顶急停（中间那对关键帧把加速曲线做出来）
	_add_keys(a, "arm", "rotation", [
		[0.0, 0.0],
		[t_pull, arm_back],
		[t_mid, arm_back + (arm_hit - arm_back) * 0.25],
		[t_swing, arm_hit],
		[t_free, arm_hit],
		[a.length, 0.0],
	])
	# 前臂（含手和刀，绕肘）：蓄力折肘收刀 → 中段手领先甩出 → 命中展开。
	# ⚠ t_mid 前臂走 55% 而肩只走 25% —— 手领先于肩（鞭打的最小表达）。
	#   没有 arm_fore 部件的 rig（剑客）由 _add_keys 自动跳过，零影响。
	_add_keys(a, "arm_fore", "rotation", [
		[0.0, 0.0],
		[t_pull, elbow_back],
		[t_mid, elbow_back + (elbow_hit - elbow_back) * 0.55],
		[t_swing, elbow_hit],
		[t_free, elbow_hit],
		[a.length, 0.0],
	])


## 两条腿的发力支点：蓄力时重心后坐，判定时前腿顶住、后腿蹬直。
## ⚠ 符号口径：**正角度 = 脚往后**（节点在髋上、腿朝下，顺时针转就是把脚带向 −x）。
##   所以「前腿迈出去」是**负**角度。虎妖那版坐标不同，别照抄正负号。
func _legs(a: Animation, anim: String, front_back: float, front_hit: float,
		back_back: float, back_hit: float) -> void:
	## ⚠ 符号口径：**正角度 = 脚往后**（节点在髋上、腿朝下，顺时针转就是把脚带向 −x）。
	##   所以「前腿迈出去」是**负**角度。虎妖那版坐标不同，别照抄正负号。
	var windup := float(_skill_table()[anim]["windup"])
	var t_hit := _hit_time(anim)
	var t_pull := _real_to_anim(anim, windup * 0.50)
	var t_swing := _real_to_anim(anim, windup * 0.85)
	var t_free := minf(t_hit + _real_to_anim(anim, 0.08), a.length - 0.005)
	_add_keys(a, "leg_front", "rotation", [
		[0.0, 0.0], [t_pull, front_back], [t_swing, front_hit],
		[t_free, front_hit], [a.length, 0.0],
	])
	_add_keys(a, "leg_back", "rotation", [
		[0.0, 0.0], [t_pull, back_back], [t_swing, back_hit],
		[t_free, back_hit], [a.length, 0.0],
	])


## 子类给 idle / walk 补额外轨道的钩子（例如剑客的披帛次级摆动）。
## ⚠ 必须在 `_neutral_all` **之前**调：那条函数会给所有没被写过的部件补「归零轨道」，
##   先补了归零轨道，再加摆动轨道就变成两条同属性轨道，后加的那条会盖掉归零。
func _extra_loops(_a: Animation) -> void:
	pass


# ===================== 循环动画 =====================

## 待机：只有呼吸与刀微晃 —— 站桩时腿动才是假的
func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = H_IDLE_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_body_bob(a, H_IDLE_BOB, 1, 0.0)
	_add_sine(a, "body", "rotation", 0.25, H_IDLE_BODY_ROT, 1)
	_add_sine(a, "arm", "rotation", 0.55, H_IDLE_ARM, 1)
	# 前臂跟随肩做一点相位差的微折 —— 肘关节是「活」的关键
	_add_sine(a, "arm_fore", "rotation", 0.40, H_IDLE_ARM * 1.6, 1)
	_extra_loops(a)
	_neutral_all(a)
	return a


## 走路：两条腿反相摆 + 躯干 2 倍频起伏 + 持刀臂轻摆
func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = H_WALK_CYCLE
	a.loop_mode = Animation.LOOP_LINEAR
	_add_sine(a, "leg_front", "rotation", 0.00, H_WALK_LEG_SWING, 1)
	_add_sine(a, "leg_back", "rotation", 0.50, H_WALK_LEG_SWING, 1)
	_add_body_bob(a, H_WALK_BOB, 2, 0.0)
	_add_sine(a, "body", "rotation", 0.25, H_WALK_BODY_ROT, 1)
	_add_sine(a, "arm", "rotation", 0.60, H_WALK_ARM_SWING, 1)
	# 前臂与肩反相微摆：肘比肩多一层小起伏，垂着的刀才有「挂在手上」的重量感
	_add_sine(a, "arm_fore", "rotation", 0.10, H_WALK_ARM_SWING * 0.9, 1)
	_extra_loops(a)
	_neutral_all(a)
	return a


# ===================== 招式 =====================

## 横斩：刀先沉到身后低处（+115°）→ 由下往上撩到前上（−15°，头部高度）。
## 垂刀式的横斩天然是一条**低→高的斜撩**：起手刀本来就在下，抬臂就是出刀。
## 命中收在 −15°（不是 +15°）—— 刀尖往上走才读得出「撩」，往下走是竖劈。
func _make_slash_h() -> Animation:
	var a := _skill_anim("slash_h")
	_strike(a, "slash_h", Vector2(-20.0, 11.0), Vector2(30.0, -7.0), 0.63, -1.37,
		-0.14, 0.19, Vector2(1.06, 0.93), 0.0,
		0.30, -0.30)
	_legs(a, "slash_h", 0.06, -0.10, -0.08, 0.12)
	return a


## 沉步竖斩：先举过头顶（刀指 −100°），顿一拍，然后砸到前下 +65°。
## 竖劈的辨识度全在「举得高 + 砸得狠」这个落差上；肘反折 −0.85 把刀收到脑后，
## 命中时前臂几乎展开（−0.15）= 刀完全送出去。
func _make_smash_v() -> Animation:
	var a := _skill_anim("smash_v")
	_strike(a, "smash_v", Vector2(-12.0, -16.0), Vector2(15.0, 21.0), -1.99, -0.11,
		-0.13, 0.17, Vector2(0.95, 1.06), 0.0,
		-0.85, -0.15)
	_legs(a, "smash_v", 0.05, -0.12, -0.10, 0.14)
	return a


## 破步突进斩：压低身子 → 整个人往前送 + 刀从身后低扫到前下 +25°（膝腰高度）。
## ⚠ 命中角刻意比横斩（−15°）低 40°：两招都收到水平线的话画面上是同一刀。
## BOSS 侧的位移是玩法代码做的（dash），这里只做「起步压低 + 挥刀」，
## 躯干前后位移控制在 ±20 以免和位移叠起来像瞬移。
func _make_dash() -> Animation:
	var a := _skill_anim("dash_slash")
	_strike(a, "dash_slash", Vector2(-14.0, 13.0), Vector2(26.0, -4.0), 0.73, -0.635,
		-0.12, 0.15, Vector2(1.05, 0.91), 0.0,
		0.35, -0.30)
	# 突进的第一步：前腿大幅迈出（负角 = 脚往前），后腿蹬直（正角 = 脚往后）
	_legs(a, "dash_slash", 0.10, -0.26, -0.14, 0.22)
	return a


## 封路刀域：把刀**插进地面**（圆域是从脚下炸开的，动作必须朝下）。
## 身前高举（−70°）后垂直下扎，命中时刀尖 +88° 扎进脚前地面（y≈716，略没入土）。
## 肩只转 −0.35、肘正折 +0.55 —— 手停在腰前、刀垂直向下，比直臂下压更像「插」。
func _make_stomp() -> Animation:
	var a := _skill_anim("stomp_aoe")
	_strike(a, "stomp_aoe", Vector2(-7.0, -14.0), Vector2(4.0, 19.0), -1.65, -0.35,
		-0.09, 0.12, Vector2(0.96, 1.05), 0.0,
		-0.70, 0.55)
	_legs(a, "stomp_aoe", 0.04, -0.08, -0.08, 0.10)
	return a


## 刀气追击：平抡一刀把刀气甩出去（判定是直线投射物，动作是横向大扫）。
## 命中 +10° = 刀身几乎水平、停在胸口高度（y≈371），正好是投射物的出手线；
## 与横斩（−15° 撩到头顶）差 25°，两招一眼能分开。
func _make_qi() -> Animation:
	var a := _skill_anim("palm_project")
	_strike(a, "palm_project", Vector2(-20.0, 6.0), Vector2(22.0, -1.0), 0.50, -0.93,
		-0.10, 0.13, Vector2(1.05, 0.94), 0.0,
		0.30, -0.25)
	_legs(a, "palm_project", 0.05, -0.06, -0.06, 0.08)
	return a


## 纳势反击：架刀格挡（刀横在身前）→ 顶住 → 反手推出去。
## 前摇 3 秒、动画按 1.8 秒设计后放慢播 —— 看上去是「稳稳架着等你打」。
## ⚠ 这一招不能套 `_strike`：它不是「蓄力→爆发」，而是「早早架住→一直架着→最后推」。
func _make_guard() -> Animation:
	var a := _skill_anim("guard_charge")
	var t := _hit_time("guard_charge")
	var t_guard := a.length * 0.22          # 架起来
	var t_hold := t * 0.97                  # 一直架到判定前
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b],
		[t_guard, b + Vector2(-8.0, 6.0)],
		[t_hold, b + Vector2(-6.0, 5.0)],
		[t * 0.99, b + Vector2(10.0, -1.0)],
		[a.length, b],
	])
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [t_guard, -0.05], [t_hold, -0.045],
		[t * 0.99, 0.04], [a.length, 0.0],
	])
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE], [t_guard, Vector2(1.03, 0.96)],
		[t_hold, Vector2(1.03, 0.96)],
		[t * 0.99, Vector2(0.97, 1.03)], [a.length, Vector2.ONE],
	])
	# 刀横在身前：肩 −0.70 + 肘 −0.30（反解 → 刀指前方 +10°，腰胸高度的横架），
	# 顶住，最后反推出去（推到 +40°，把刀压向对方）
	# ⚠ 肩角是**负**的：新 rig 静止垂刀 +70°，抬腕往前才是横架（旧扛刀 rig 相反）
	_add_keys(a, "arm", "rotation", [
		[0.0, 0.0], [t_guard, -0.70], [t_hold, -0.70],
		[t * 0.99, -0.41], [a.length, 0.0],
	])
	# 前臂：架刀时往前送一点，推出时顺势压腕 —— 与肩同拍
	_add_keys(a, "arm_fore", "rotation", [
		[0.0, 0.0], [t_guard, -0.30], [t_hold, -0.30],
		[t * 0.99, -0.15], [a.length, 0.0],
	])
	_add_keys(a, "leg_front", "rotation", [
		[0.0, 0.0], [t_guard, -0.08], [t_hold, -0.08], [a.length, 0.0],
	])
	_add_keys(a, "leg_back", "rotation", [
		[0.0, 0.0], [t_guard, 0.10], [t_hold, 0.10], [a.length, 0.0],
	])
	return a


## 满势断岳：蓄势（刀举到最高最后 −105°、身体拉开）→ 长定格 → 全力砸到前下 +75°。
## 与沉步竖斩的区别是**幅度更大（肩走 115°）、定格更长、回收更慢**，
## 读起来像「压箱底的一招」。命中角比竖斩陡 10°、刀尖落点更靠近脚下（505 vs 578）。
func _make_ult() -> Animation:
	var a := _skill_anim("ult_windup")
	_strike(a, "ult_windup", Vector2(-13.0, -20.0), Vector2(18.0, 22.0), -2.00, 0.0,
		-0.15, 0.19, Vector2(0.93, 1.08), 0.0,
		-0.90, -0.10)
	_legs(a, "ult_windup", 0.06, -0.14, -0.12, 0.16)
	return a
