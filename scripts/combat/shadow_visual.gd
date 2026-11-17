class_name ShadowVisual
extends Node2D
## 地面「影身」的共用表现（2026-11-02，执烛 / 玩家灯笼 / 脱手影兽都画这一条）
##
## 一条从脚下沿影方向铺出去的柔边墨带 + 影尖一枚冷银亮点。
## 亮点就是射程读数：地上那条黑刃伸到哪儿、亮点在哪儿，这一招就能打到哪儿 ——
## 不用势条、不用数字，读影子本身。
##
## 挂在移动单位下面即可：本节点不旋转，影子朝向由 set_shape 每次给世界方向。

const DOT_RADIUS := 78.0      ## dot_texture 肉眼边缘对应的半径（判定长度 = 视觉长度）
const SQUASH_Y := 0.72        ## 地面透视：垂直于影方向的宽度压一点
## 三张墨迹贴图的**墨迹实际跨度**统一读 SkillFx：走廊（判定本体）与招式特效
## 必须同一套换算，两边各写一份迟早会漂出「看到的影子比挨打的影子短」。
const STROKE_BASE := SkillFx.INK_STROKE_BASE
const BLOB_BASE := SkillFx.INK_BLOB_BASE
const FLAME_BASE := SkillFx.INK_FLAME_BASE
const TIP_H := 62.0                          ## 影尖读数在屏幕上的高度

var ink := Color(0.03, 0.04, 0.07)          ## 墨色
var tip_color := Color(0.72, 0.90, 1.0)     ## 影尖读数色
var root_texture: Texture2D = null          ## 本体剪影（可空）
var root_scale := Vector2(0.25, 0.25)
## 站起来的影子：不随走廊旋转、不压扁，脚底钉在影根。
## 铺在地上的墨带是「射程」，立着的这一具是「它把影子当兵器」——两者要同时读得出来。
var root_upright := false

var _rim: Sprite2D = null      ## 冷银底衬：墨带盖住中段，只在边缘漏一圈光
var _edge_a: Sprite2D = null   ## 走廊两条长边：暗地面上「暗」是看不见的，轮廓必须靠光
var _edge_b: Sprite2D = null
var _halo: Sprite2D = null
var _band: Sprite2D = null
var _core: Sprite2D = null
var _tip: Sprite2D = null
var _root: Sprite2D = null
var _fade: float = 1.0


func _ready() -> void:
	z_index = -1
	var tex := SkillFx.dot_texture()
	var stroke: Texture2D = SkillFx.skill_texture("ink_stroke")
	var blob: Texture2D = SkillFx.skill_texture("ink_blob")
	var flame: Texture2D = SkillFx.skill_texture("lamp_flame")
	# 描边要画在墨之前（同位置稍大一圈），墨带压住中心后剩下就是一圈冷银边
	_rim = _mk(tex, Color(0.62, 0.84, 1.0, 0.0))
	_rim.material = SkillFx.additive_material()
	add_child(_rim)
	_edge_a = _mk(SkillFx.streak_texture(), Color(0.72, 0.90, 1.0, 0.0))
	_edge_a.material = SkillFx.additive_material()
	add_child(_edge_a)
	_edge_b = _mk(SkillFx.streak_texture(), Color(0.72, 0.90, 1.0, 0.0))
	_edge_b.material = SkillFx.additive_material()
	add_child(_edge_b)
	# 晕开的湿墨外缘 → 笔触主体 → 轴上那道浓墨，三层叠出「一笔拖过去」的厚度
	_halo = _mk(blob if blob != null else tex, Color(ink.r, ink.g, ink.b, 0.16))
	add_child(_halo)
	_band = _mk(stroke if stroke != null else tex, Color(ink.r, ink.g, ink.b, 0.34))
	add_child(_band)
	_core = _mk(stroke if stroke != null else tex,
			Color(ink.r * 0.6, ink.g * 0.6, ink.b * 0.7, 0.52))
	add_child(_core)
	## 影尖读数：一簇从地上冒起的冷焰。**不随走廊旋转** ——
	## 横躺的火苗读起来像弹道尾焰，竖着才像「影子的尽头烧着一盏灯」。
	_tip = _mk(flame if flame != null else tex,
			Color(tip_color.r, tip_color.g, tip_color.b, 0.50))
	_tip.material = SkillFx.additive_material()
	_tip.z_index = 1
	add_child(_tip)
	refresh_root()


## 换影根剪影（分影脱手时由外部调用，此时 _ready 已经跑过）
func set_root(tex: Texture2D, upright: bool, s: float) -> void:
	root_texture = tex
	root_upright = upright
	root_scale = Vector2(s, s)
	if is_inside_tree():
		refresh_root()


func refresh_root() -> void:
	if root_texture == null:
		if _root != null and is_instance_valid(_root):
			_root.queue_free()
		_root = null
		return
	var col := (Color(0.60, 0.70, 1.0, 0.62) if root_upright
			else Color(0.02, 0.03, 0.05, 0.58))
	if _root == null:
		_root = _mk(root_texture, col)
		add_child(_root)
	else:
		_root.texture = root_texture
		_root.modulate = col


static func _mk(tex: Texture2D, col: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.modulate = col
	return s


## dir：世界方向（单位 → 背离光源）；length：影长；width：走廊宽度；alpha：整体透明度
func set_shape(dir: Vector2, length: float, width: float, alpha: float = 1.0,
		tip_visible: bool = true) -> void:
	if dir.length_squared() < 0.0001:
		return
	_fade = clampf(alpha, 0.0, 1.0)
	var ang := dir.angle()
	var mid := dir * (length * 0.5)
	var wide := maxf(width * SQUASH_Y, 1.0)
	var sx := maxf(length, 1.0) / DOT_RADIUS
	var sy := wide / DOT_RADIUS
	## ⚠ 亮度配比：墨必须**压得住**底下那圈冷银衬。
	##   第一版 rim 0.42 / band 0.40，等于在黑地上贴一层半透明银 ——
	##   地面亮斑上实测整条走廊是**浅灰实心带**，玩家看到的是光剑不是影子。
	##   现在 rim 只比墨带宽 4%（漏出来就是那条边），墨层自身 0.8 起。
	_place(_rim, mid, ang, sx * 1.04, sy * 1.16, 0.16 * _fade)
	# 晕开的湿墨外缘 → 笔触主体 → 轴上那道浓墨，三层叠出「一笔拖过去」的厚度。
	# 缩放基准用的是**墨迹跨度**而不是画布尺寸，影长才等于判定长度。
	_place(_halo, mid, ang, length * 1.14 / BLOB_BASE.x, wide * 1.42 / BLOB_BASE.y,
		0.22 * _fade)
	_place(_band, mid, ang, length / STROKE_BASE.x, wide / STROKE_BASE.y, 0.80 * _fade)
	_place(_core, mid, ang, length * 0.86 / STROKE_BASE.x, wide * 0.52 / STROKE_BASE.y,
		0.92 * _fade)
	_place_tip(dir, length, tip_visible)
	# 两条长边：streak_texture 是竖长的（64×256），所以旋转要多加 90°
	var perp := dir.orthogonal()
	var off := perp * (width * SQUASH_Y * 0.5)
	var ly := maxf(length, 1.0) / 256.0
	var lx := 16.0 / 64.0
	for pair in [[_edge_a, off], [_edge_b, -off]]:
		var e := pair[0] as Sprite2D
		if e == null:
			continue
		e.position = mid + (pair[1] as Vector2)
		e.rotation = ang + PI * 0.5
		e.scale = Vector2(lx, ly)
		e.modulate.a = (0.26 if tip_visible else 0.14) * _fade
	if _root != null:
		_root.modulate.a = (0.62 if root_upright else 0.58) * _fade
		if root_upright:
			_root.rotation = 0.0
			_root.scale = root_scale
			var h := float(root_texture.get_height()) * root_scale.y
			_root.position = dir * minf(length * 0.22, 46.0) - Vector2(0.0, h * 0.5)
		else:
			_root.scale = root_scale * Vector2(1.0, 0.46)
			_root.rotation = ang
			_root.position = dir * minf(length * 0.22, 46.0)


## 只画脚边那一团（影长归零 / 暗场时仍有「它有影子」的存在感）
func set_stub(alpha: float) -> void:
	set_shape(Vector2.DOWN, ShadowLaw.SHADOW_MIN * 0.7, ShadowLaw.WIDTH_ROOT, alpha, false)


func set_ink(c: Color) -> void:
	ink = c
	if _halo != null:
		_halo.modulate = Color(c.r, c.g, c.b, 0.16)
	if _band != null:
		_band.modulate = Color(c.r, c.g, c.b, 0.34)


func _place(s: Sprite2D, pos: Vector2, ang: float, kx: float, ky: float, a: float) -> void:
	if s == null:
		return
	s.position = pos
	s.rotation = ang
	s.scale = Vector2(kx, ky)
	s.modulate.a = a


## 影尖读数放在走廊尽头，但火苗**永远竖直**：横躺的火苗读起来像弹道尾焰，
## 竖着才像「影子的尽头烧着一盏灯」——这一颗就是射程本身。
func _place_tip(dir: Vector2, length: float, tip_visible: bool) -> void:
	if _tip == null:
		return
	var k := TIP_H / FLAME_BASE.y
	_tip.position = dir * length
	_tip.rotation = 0.0
	_tip.scale = Vector2(k, k)
	_tip.modulate.a = (0.86 if tip_visible else 0.0) * _fade


func fade_out(seconds: float) -> void:
	set_process(false)
	var tw := create_tween()
	tw.set_parallel(true)
	for s in [_rim, _edge_a, _edge_b, _halo, _band, _core, _tip, _root]:
		if s != null:
			tw.tween_property(s, "modulate:a", 0.0, seconds)
	tw.chain().tween_callback(queue_free)
