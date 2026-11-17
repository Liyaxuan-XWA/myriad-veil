class_name BossRigSwordsman
extends BossRigHuman

## 剑客的骨骼动画集：**空手御剑**，九式全是用「剑指」指挥飞剑。
##
## ## 为什么继承 BossRigHuman 而不是 BossRig
##
## 人形的骨架、idle/walk 曲线、`_strike`/`_legs` 那套「慢蓄力—爆发—定格」生成器
## 全都是通用的，只有招式表和披帛摆动是本角色特有的。所以这里**只写差异**：
## 覆写 `_skill_table()` 换招式名，覆写 `_extra_loops()` 给披帛加摆动。
##
## ## 表现手法（没有刀，全靠身体和披帛）
##
## 刀客靠「肩膀大角度甩刀」；剑客手里没有东西，所以**表演主力换成三样**：
##
## 1. **躯干的位移与俯仰**：前送 = 剑指递出，后坐 = 收势，仰 = 引气，俯 = 压剑
## 2. **披帛的滞后摆动**：人影没动，披帛先动 —— 这是「御剑」最像的一点
## 3. **肩角的小幅但极快的变化**：剑指不需要大弧线，需要的是「弹」
##
## ## 时间曲线
##
## 与刀客同一套换算（见 `BossRigHuman._hit_time`）：判定帧在动画时间轴上是
## `windup × length / (windup + 0.15)`。⚠ 剑客的 `刺` 前摇只有 0.30 秒，
## 是全项目最快的招，`t_hit` 落在动画的 67% 处 —— 定格必须够短，否则读成「卡住」。
##
## ## 关节
##
## ```
## body（躯干 + 头 + 长发 + 长袍）
##   ├── arm        肩 ———— 剑指手 + 大袖
##   ├── leg_front  髋 ———— 前脚（长袍遮到脚踝，可见的只有靴子）
##   └── leg_back   髋 ———— 后脚
## shawl1 → shawl2  披帛上段 / 长尾（兄弟节点，画在身后，滞后一拍）
## ```

# ===================== 参数 =====================

## 招式表：动画名 → {length: 按原速设计多长, windup: 玩法里这一招的前摇}
## ⚠ windup 必须与 MoveDB 的 `form_sword_*` 一致 —— 对齐之后「剑指递到最尽头」
##   正好是伤害判定的那一帧（这一招没有红圈、没有 UI 预警，动作就是唯一的预警）。
const SW_SKILLS := {
	"stab": {"length": 0.42, "windup": 0.30},          # 刺：全项目最快，几乎无前摇
	"lift": {"length": 0.60, "windup": 0.45},          # 撩：自下而上挑
	"chop": {"length": 1.05, "windup": 0.95},          # 斩：抬手指天 → 下压
	"cloud": {"length": 0.62, "windup": 0.50},         # 云：以身带指划圆
	"pierce": {"length": 0.68, "windup": 0.55},        # 穿：低身突进、指尖前送
	"myriad": {"length": 1.20, "windup": 1.10},        # 万剑归宗：剑指上引、飞剑升起
	"heaven": {"length": 1.40, "windup": 1.30},        # 一剑开天：长蓄势 → 前劈
	"heaven_full": {"length": 1.55, "windup": 1.30},   # 剑意盈天：同样的蓄势，定格更久
	"triangle": {"length": 1.60, "windup": 2.00},      # 三角封绝：结印，身体几乎不动
}

## 披帛摆角（弧度）。⚠ 披帛是**画在身后**的独立部件，摆大了会从身体轮廓里甩出去，
## 露出「纱飞在半空、人没动」的破绽。0.10 ≈ 5.7°，配合滞后已经够飘。
const SW_SHAWL_SWING := 0.10
## 披帛下段相对上段的相位滞后（周期占比）
const SW_SHAWL_LAG := 0.16


# ===================== 构建 =====================

func _skill_table() -> Dictionary:
	return SW_SKILLS


func _make_skill(anim: String) -> Animation:
	match anim:
		"stab":
			return _make_stab()
		"lift":
			return _make_lift()
		"chop":
			return _make_chop()
		"cloud":
			return _make_cloud()
		"pierce":
			return _make_pierce()
		"myriad":
			return _make_myriad()
		"heaven", "heaven_full":
			return _make_heaven(anim)
		"triangle":
			return _make_triangle()
	return _make_stab()


## 给 idle / walk 补披帛摆动（父类的钩子，在 `_neutral_all` 之前调）
func _extra_loops(a: Animation) -> void:
	_add_sine(a, "shawl1", "rotation", 0.20, SW_SHAWL_SWING * 0.7, 1)
	_add_sine(a, "shawl2", "rotation", 0.20 - SW_SHAWL_LAG, SW_SHAWL_SWING, 1)


# ===================== 招式 =====================

## 剑指直刺：不甩胳膊，靠**整个人前送**把指尖递出去。
## 躯干前扑 20px ≈ 指尖前移 20px，比转肩更符合「一指点出」的观感。
func _make_stab() -> Animation:
	var a := _skill_anim("stab")
	_strike(a, "stab", Vector2(-9.0, 5.0), Vector2(20.0, -3.0), -0.18, 0.14,
		-0.03, 0.04, Vector2(1.03, 0.95))
	_legs(a, "stab", 0.04, -0.06, -0.05, 0.07)
	_shawl(a, "stab", -0.05, 0.04)
	return a


## 撩：指尖自下而上挑开。手臂从下垂位抬到水平偏上，躯干后仰跟上。
func _make_lift() -> Animation:
	var a := _skill_anim("lift")
	_strike(a, "lift", Vector2(-7.0, 8.0), Vector2(11.0, -10.0), 0.42, -0.55,
		-0.04, 0.05, Vector2(1.02, 0.97))
	_legs(a, "lift", 0.05, -0.07, -0.06, 0.08)
	_shawl(a, "lift", 0.05, -0.06)
	return a


## 斩：抬手指天 → 顿一拍 → 指尖直压下来。剑客最重的一招（前摇 0.95 秒）。
func _make_chop() -> Animation:
	var a := _skill_anim("chop")
	_strike(a, "chop", Vector2(-9.0, -12.0), Vector2(13.0, 14.0), -0.80, 0.60,
		-0.07, 0.08, Vector2(0.96, 1.05))
	_legs(a, "chop", 0.05, -0.10, -0.09, 0.12)
	_shawl(a, "chop", -0.09, 0.07)
	return a


## 云：以身带指划圆弧。转的是**躯干**，手臂只是跟着走 —— 这是「云剑」的要点：
## 剑势是圆的，人不能是直的。
func _make_cloud() -> Animation:
	var a := _skill_anim("cloud")
	_strike(a, "cloud", Vector2(-13.0, 3.0), Vector2(15.0, -2.0), -0.34, 0.40,
		-0.10, 0.11, Vector2(1.03, 0.96))
	_legs(a, "cloud", 0.05, -0.06, -0.05, 0.07)
	_shawl(a, "cloud", -0.10, 0.10)
	return a


## 穿：低身突进、指尖贴地前送。躯干整体下沉（scale 压扁）+ 大幅前送。
func _make_pierce() -> Animation:
	var a := _skill_anim("pierce")
	_strike(a, "pierce", Vector2(-8.0, 12.0), Vector2(24.0, 2.0), -0.12, 0.20,
		-0.02, 0.03, Vector2(1.05, 0.90))
	_legs(a, "pierce", 0.12, -0.16, -0.11, 0.15)
	_shawl(a, "pierce", -0.12, 0.14)
	return a


## 万剑归宗：剑指上引 → 身后飞剑升起 → 猛然前指。身体几乎不位移，
## 靠「上引」和「前指」两个方向的手势撑住 —— 真正的杀伤交给特效。
func _make_myriad() -> Animation:
	var a := _skill_anim("myriad")
	_strike(a, "myriad", Vector2(-6.0, -10.0), Vector2(9.0, 3.0), -0.85, 0.10,
		-0.05, 0.06, Vector2(0.97, 1.06))
	_legs(a, "myriad", 0.04, -0.05, -0.04, 0.06)
	_shawl(a, "myriad", -0.13, 0.12)
	return a


## 一剑开天 / 剑意盈天：长蓄势（剑指上引、身体后仰）→ 长定格 → 前劈。
## 两式的差别只在**定格长度**（满层版本多停 0.15 秒），动作共用一套参数。
## ⚠ 肩角上举到 **−0.88 就封顶**（约 50°）。再往上抬（试过 −1.35）手臂会横过脸、
##   而且露出胸口一大片「原画从没画过」的区域 —— 补画的暗色一团，比不抬更难看。
##   要表达「举指冲天」靠躯干后仰 + 披帛后扬 + 特效，不靠手臂本身。
func _make_heaven(anim: String) -> Animation:
	var a := _skill_anim(anim)
	var t := _hit_time(anim)
	var full := anim == "heaven_full"
	# 满层版：判定后多定 0.15 秒，读起来比普通版更重（用 hold_extra，不要另加轨道）
	_strike(a, anim, Vector2(-11.0, -16.0), Vector2(15.0, 13.0), -0.88, 0.52,
		-0.09, 0.10, Vector2(0.95, 1.07), 0.15 if full else 0.0)
	_legs(a, anim, 0.06, -0.12, -0.10, 0.14)
	_shawl(a, anim, -0.16, 0.15)
	return a


## 三角封绝：结印。剑客在这一招里**身体几乎不动**，全部交给飞剑特效，
## 所以只做「双手在胸前合、肩角微开、披帛被气机带起」。
func _make_triangle() -> Animation:
	var a := _skill_anim("triangle")
	var t := _hit_time("triangle")
	var b := _body_rest()
	_add_keys(a, "body", "position", [
		[0.0, b], [a.length * 0.25, b + Vector2(-4.0, 4.0)],
		[t, b + Vector2(2.0, -2.0)], [a.length, b],
	])
	_add_keys(a, "body", "rotation", [[0.0, 0.0], [a.length * 0.3, -0.02], [a.length, 0.0]])
	_add_keys(a, "body", "scale", [
		[0.0, Vector2.ONE], [a.length * 0.3, Vector2(1.02, 0.98)], [a.length, Vector2.ONE],
	])
	_add_keys(a, "arm", "rotation", [
		[0.0, 0.0], [a.length * 0.3, 0.55], [t, 0.62], [a.length, 0.0],
	])
	_shawl(a, "triangle", -0.08, 0.08)
	return a


# ===================== 披帛 =====================

## 披帛的次级摆动：上段先动、下段滞后。
## ⚠ 相位必须错开，两节同步摆就变成「一块硬板在转」，反而更假。
func _shawl(a: Animation, anim: String, back: float, hit: float) -> void:
	## 披帛的次级摆动：上段先动、下段滞后。
	## ⚠ 相位必须错开，两节同步摆就变成「一块硬板在转」，反而更假。
	var windup := float(_skill_table()[anim]["windup"])
	var t_pull := _real_to_anim(anim, windup * 0.50)
	var t_swing := _real_to_anim(anim, windup * 0.85)
	var t_free := minf(_hit_time(anim) + _real_to_anim(anim, 0.08), a.length - 0.005)
	_add_keys(a, "shawl1", "rotation", [
		[0.0, 0.0], [t_pull, back], [t_swing, hit], [t_free, hit], [a.length, 0.0],
	])
	# 下段比上段晚一点点到（相位滞后）
	_add_keys(a, "shawl2", "rotation", [
		[0.0, 0.0], [t_pull * 0.9, back * 0.5], [t_swing, back],
		[minf(t_swing + (t_free - t_swing) * 0.25, a.length - 0.005), hit * 1.2],
		[t_free, hit], [a.length, 0.0],
	])