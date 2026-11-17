class_name FoldSeam
extends Node2D
## 折痕两端的对位圆牌（2026-11-02）
##
## 空间穿缝最容易让人迷路，所以这块牌把配对关系**全画在图形上**：
##   ① 同色 = 同一对（第一条痕月白、第二条痕淡金）
##   ② 同点数 = 同一对（牌心点 1 个点是①、2 个点是②）
##   ③ 一枚朝内的箭头，指向它的另一半在哪个方向
## 踩进去就从对侧那枚出来；出牌后有短暂无敌，防止两端互为输入来回抖。
## 读数是图形不是条：这里没有任何百分比数字。

const DISC_BASE := SkillFx.FOLD_DISC_BASE        ## 贴图原生直径

var tag: int = 1                ## 属于哪条痕（配色 + 点数）
var partner: Vector2 = Vector2.INF   ## 未配对前不许参与穿缝结算

var _disc: Sprite2D = null
var _pips: Node2D = null
var _arrow: Sprite2D = null
var _pulse := 0.0


func _ready() -> void:
	z_index = 4
	z_as_relative = false
	_disc = Sprite2D.new()
	_disc.texture = SkillFx.fold_disc_texture()
	_disc.centered = true
	_disc.scale = Vector2.ONE * (FoldLaw.SEAM_R * 2.0 * 1.35 / DISC_BASE)
	_disc.modulate = Color(_tone(tag), 0.68)
	_arrow = Sprite2D.new()
	_arrow.texture = SkillFx.streak_texture()
	_arrow.centered = false
	_arrow.scale = Vector2(0.62, 0.5)
	_arrow.modulate = Color(_tone(tag), 0.72)
	_pips = Node2D.new()
	add_child(_disc)
	add_child(_pips)
	add_child(_arrow)
	_build_pips()


func set_tag(v: int) -> void:
	if tag == v:
		return
	tag = v
	_disc.modulate = Color(_tone(tag), 0.68)
	_arrow.modulate = Color(_tone(tag), 0.72)
	_build_pips()


func set_partner(p: Vector2) -> void:
	partner = p
	var away := p - global_position
	if away.length_squared() > 1.0:
		_arrow.rotation = away.angle()
		_arrow.position = away.normalized() * FoldLaw.SEAM_R * 0.72


func _build_pips() -> void:
	for c in _pips.get_children():
		c.queue_free()
	var n := clampi(tag, 1, 3)
	for i in n:
		var pip := Sprite2D.new()
		pip.texture = SkillFx.dot_texture()
		pip.centered = true
		pip.scale = Vector2.ONE * (FoldLaw.SEAM_R * 2.0 / 64.0 * 0.17)
		pip.modulate = Color(0.10, 0.11, 0.14, 0.92)
		# 点数横向排在牌心，一眼数得清
		pip.position = Vector2((float(i) - float(n - 1) * 0.5) * FoldLaw.SEAM_R * 0.44, 0.0)
		_pips.add_child(pip)


func _process(delta: float) -> void:
	_pulse += delta
	var breathe := 1.0 + 0.055 * sin(_pulse * 2.6)
	_disc.scale = Vector2.ONE * (FoldLaw.SEAM_R * 2.0 * 1.35 / DISC_BASE) * breathe
	_disc.modulate = Color(_tone(tag), 0.62 + 0.16 * sin(_pulse * 2.6))


static func _tone(tag_no: int) -> Color:
	if tag_no >= 3:
		return Color(0.74, 0.90, 0.86)
	if tag_no == 2:
		return Color(0.94, 0.86, 0.66)
	return Color(0.86, 0.92, 0.98)
