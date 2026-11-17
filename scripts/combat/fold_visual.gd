class_name FoldVisual
extends Node2D
## 折痕的渲染件（2026-11-02）
##
## 一条折痕在屏幕上是**纸被折起来时吃光的那道棱**：
##   芯 = 极窄的月白亮线；两侧 = 迅速衰减的柔光（不是激光线，也不是硬边描边）；
##   棱下偏一侧挂一条**墨影**，那是折起来那半张纸压在下面半张纸上的影子 —— 有了它才读得出「立体」。
##
## 与影族（泼墨）、镜族（水面反光）在身份上分开：折族 = 纸的硬折 + 光走棱线。
## 伤害范围一律不画在这儿；范围预警在 SkillFx 的柔边圆上。

const RIDGE_BASE := SkillFx.FOLD_RIDGE_BASE   ## 贴图原生尺寸：x=沿痕方向，y=羽化宽度

## 压痕预告态：同一条形，只是更淡、更窄、带虚口
var preview: bool = false
## 二阶段那条痕（配色与编号跟着走）
var tag: int = 1
## 作废（碎痕之后）：整条痕淡出，不再参与判定
var dimmed: bool = false

var _core: Sprite2D = null
var _glow: Sprite2D = null
var _lip: Sprite2D = null
var _alpha: float = 0.0


func _ready() -> void:
	z_index = 3
	z_as_relative = false
	_core = Sprite2D.new()
	_core.texture = SkillFx.fold_ridge_texture()
	_core.centered = true
	_glow = Sprite2D.new()
	_glow.texture = SkillFx.fold_ridge_texture()
	_glow.centered = true
	_glow.material = SkillFx.additive_material()
	_lip = Sprite2D.new()
	_lip.texture = SkillFx.fold_ridge_texture()
	_lip.centered = true
	add_child(_glow)
	add_child(_lip)
	add_child(_core)
	_apply()


## a→b 世界坐标两端点落好，本节点在原点；由 FoldField 摆位置
func set_span(a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	global_position = mid
	rotation = (b - a).angle()
	var length := a.distance_to(b) + FoldLaw.CREASE_MARGIN * 2.0
	var s := Vector2(length / RIDGE_BASE.x, 1.0)
	_core.scale = s
	_glow.scale = s
	_lip.scale = s
	_apply()


func set_preview(v: bool) -> void:
	if preview == v:
		return
	preview = v
	_apply()


func set_dimmed(v: bool) -> void:
	if dimmed == v:
		return
	dimmed = v
	_apply()


func fade(delta: float, rate: float) -> void:
	_alpha = clampf(_alpha + (1.0 if not dimmed else -1.0) * delta * rate, 0.0, 1.0)
	_apply()


func _apply() -> void:
	var c := _tone(tag)
	var p := 0.42 if preview else 1.0
	## 0.86/0.30 是激光，0.52/0.13 又淡到看不见 —— 而折痕是这套机制唯一的读数，
	## 读不出来等于机制不存在。落在 0.72/0.20：芯仍然细，靠外圈那层宽羽化撑出「吃光的棱」。
	_core.modulate = Color(c.lerp(Color.WHITE, 0.55), (0.72 if not preview else 0.30) * p * _alpha * (0.25 if dimmed else 1.0))
	_glow.modulate = Color(c, (0.20 if not preview else 0.10) * p * _alpha * (0.2 if dimmed else 1.0))
	_lip.modulate = Color(0.06, 0.07, 0.09, (0.40 if not preview else 0.52) * _alpha * (0.15 if dimmed else 1.0))
	# 墨影挂在「被折起来」那一侧：沿痕法向偏移半个羽化宽
	_lip.position = Vector2(0.0, 15.0)
	_lip.scale = _core.scale * Vector2(0.94, 0.62)
	_glow.scale = _core.scale * Vector2(1.0, 1.55)
	visible = _alpha > 0.01


## 一条痕一个月白，二条痕淡金：编号与配色一起给玩家配对
static func _tone(tag_no: int) -> Color:
	if tag_no >= 2:
		return Color(0.94, 0.86, 0.66)
	return Color(0.86, 0.92, 0.98)
