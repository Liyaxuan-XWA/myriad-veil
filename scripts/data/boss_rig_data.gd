class_name BossRigData
extends Resource

## 四足 BOSS 的骨骼分件数据。
##
## ⚠ 由 `tools/build_tiger_rig.py` 生成，**不要手改** —— 换美术请重跑脚本。
##
## 为什么用 .tres 而不是 .json：`res://` 下的 .json 不保证被打进导出包
## （非资源文件默认不导出），而 .tres 是标准资源，导出、依赖追踪都没问题。
## 扁平数组（而不是 Dictionary 嵌套）是为了让 .tres 好读好改、加载也快。

## 画布尺寸（= 序列帧图集的画布，保证两套素材同尺寸互换）
@export var canvas: Vector2i = Vector2i(1100, 820)
## rig 原点相对画布左上角（当前 = 画布中心，与 SkinVisual 的口径一致）
@export var origin: Vector2 = Vector2.ZERO

## 骨骼动画集脚本（可选）。空 = 用 `BossRig`（四足：爪 / 尾 / 四条腿）。
## 人形持械 BOSS 填 `res://scripts/visual/boss_rig_human.gd`（肩 / 髋 / 刀）。
## ⚠ 必须 `extends BossRig`，否则 SkinVisual 会拒收并回落到序列帧。
@export var rig_script: String = ""

## 部件的创建顺序（同时也是默认绘制次序）
@export var order: PackedStringArray = PackedStringArray()

# ---- 以下五个数组按 part_name 的下标一一对应 ----

@export var part_name: PackedStringArray = PackedStringArray()
@export var part_tex: PackedStringArray = PackedStringArray()
## 父部件名；空串 = 挂在 rig 根下（当前只有 body 是空）
@export var part_parent: PackedStringArray = PackedStringArray()
## 关节坐标，相对 rig 原点
@export var part_joint: PackedVector2Array = PackedVector2Array()
## 贴图中心相对关节的偏移
@export var part_offset: PackedVector2Array = PackedVector2Array()
## 绘制层级（绝对 z，节点上设 z_as_relative=false）
@export var part_z: PackedInt32Array = PackedInt32Array()

# ---- 以下三个数组按 muzzle_anim 的下标一一对应（出招原点表）----

## 出招原点：动作名 → 该动作的「嘴 / 爪尖 / 刀尖」挂在哪个部件上。
## 用途：妖丹、掷石、刀气这类**从身体某处喷出来**的东西，出生点要跟着解剖走，
## 而不是一律从身体中心出。没登记的动作由调用方回落到默认口径（身前 20px）。
## ⚠ 锚点偏移是**部件本地坐标（画布像素）**，部件一转它就跟着转 —— 甩爪时原点跟着爪走。
## ⚠ 换定妆图必须重测这三组数（体形一变锚点就落空），由拆件脚本生成，别手改。
@export var muzzle_anim: PackedStringArray = PackedStringArray()
@export var muzzle_part: PackedStringArray = PackedStringArray()
@export var muzzle_offset: PackedVector2Array = PackedVector2Array()


func index_of(part: String) -> int:
	return part_name.find(part)


## 动作名 → 出招原点表的下标，没有返回 -1
func muzzle_index(anim: String) -> int:
	return muzzle_anim.find(anim)


func size() -> int:
	return part_name.size()


## 数据自检：数组长度一致、每个父部件都存在。返回空串表示正常。
## 由 BossRig.setup() 调用 —— 拆件脚本改了字段忘了同步时，这里能第一时间拦住。
func validate() -> String:
	var n := part_name.size()
	if n == 0:
		return "part_name 为空"
	if part_tex.size() != n or part_parent.size() != n or part_joint.size() != n \
			or part_offset.size() != n or part_z.size() != n:
		return "部件数组长度不一致（name=%d tex=%d parent=%d joint=%d offset=%d z=%d）" % [
			n, part_tex.size(), part_parent.size(), part_joint.size(),
			part_offset.size(), part_z.size()]
	for i in range(n):
		var p := String(part_parent[i])
		if p != "" and part_name.find(p) < 0:
			return "%s 的父部件 %s 不存在" % [part_name[i], p]
	for o in order:
		if part_name.find(o) < 0:
			return "order 里的 %s 不是已登记部件" % o
	# 出招原点表：三个数组必须等长、部件必须存在（漏一个 = 该招出生点静默回落到身体中心，
	# 表现是「妖丹从胸口/屁股冒出来」，很难一眼看出是数据问题）
	var m := muzzle_anim.size()
	if muzzle_part.size() != m or muzzle_offset.size() != m:
		return "出招原点数组长度不一致（anim=%d part=%d offset=%d）" % [
			m, muzzle_part.size(), muzzle_offset.size()]
	for i in range(m):
		if part_name.find(muzzle_part[i]) < 0:
			return "出招原点 %s 指向的部件 %s 不存在" % [muzzle_anim[i], muzzle_part[i]]
	return ""
