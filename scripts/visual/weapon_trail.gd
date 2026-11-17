class_name WeaponTrail
extends Node2D
## 御剑普攻的连续刀光拖尾：记录剑尖扫过的角度采样，画一条细弧带。
## 由 WeaponOrbit 在「出击段」逐帧 push_sample()；节点挂在角色身上（不跟着武器旋转），
## 所以历史角度不会被二次旋转，画出来是连续的一条弧，而不是多把剑的分身。
##
## 加法混合 + 低透明度：颜色由武器条目 trail_color 决定，不再用冷白提亮。

var trail_color := Color(0.74, 0.85, 0.98, 1.0)
var peak_alpha := 0.18
var trail_life := 0.10
var trail_width := 16.0

## 采样：{a: 极角(rad), r: 剑尖半径, t: 秒}
var _samples: Array = []
var _center := Vector2.ZERO
## 用游戏内时间推进：顿帧期间拖尾跟武器一起冻住，不会凭空消失
var _clock := 0.0


func _ready() -> void:
	z_index = -1
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	set_process(false)


func configure(color: Color, alpha: float, life: float, width: float) -> void:
	trail_color = color
	peak_alpha = maxf(alpha, 0.0)
	trail_life = maxf(life, 0.03)
	trail_width = maxf(width, 6.0)


func clear() -> void:
	_samples.clear()
	_clock = 0.0
	queue_redraw()


## 武器每帧落位时调用：center = 旋转轴心（角色局部坐标），angle = 剑当前极角，
## outer_radius = 剑尖到轴心的距离
func push_sample(center: Vector2, angle: float, outer_radius: float) -> void:
	_center = center
	if not _samples.is_empty():
		var last: Dictionary = _samples[_samples.size() - 1]
		# 角度几乎没动：只刷新半径/时间，避免原地堆一串重复采样
		if absf(wrapf(angle - float(last["a"]), -PI, PI)) < 0.005:
			last["r"] = outer_radius
			last["t"] = _clock
			queue_redraw()
			return
	_samples.append({"a": angle, "r": outer_radius, "t": _clock})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	while not _samples.is_empty():
		var first: Dictionary = _samples[0]
		if _clock - float(first["t"]) <= trail_life:
			break
		_samples.pop_front()
	queue_redraw()
	if _samples.size() < 2:
		set_process(false)


func _draw() -> void:
	if _samples.size() < 2:
		return
	for i in range(_samples.size() - 1):
		var k0 := _age_k(_samples[i])
		var k1 := _age_k(_samples[i + 1])
		if k0 <= 0.0 and k1 <= 0.0:
			continue
		_draw_seg(_samples[i], _samples[i + 1], k0, k1)


func _age_k(s: Dictionary) -> float:
	var k := 1.0 - (_clock - float(s["t"])) / trail_life
	return pow(clampf(k, 0.0, 1.0), 0.9)


## 一段 = 内外两片四边形，径向透明度 0 → 峰值 → 0，所以弧带没有硬边
func _draw_seg(s0: Dictionary, s1: Dictionary, k0: float, k1: float) -> void:
	var a0 := float(s0["a"])
	var a1 := float(s1["a"])
	var r0 := float(s0["r"])
	var r1 := float(s1["r"])
	var d0 := Vector2(cos(a0), sin(a0))
	var d1 := Vector2(cos(a1), sin(a1))
	var w := trail_width
	var r_in0 := r0 - w * 1.05
	var r_c0 := r0 - w * 0.10
	var r_out0 := r0 + w * 0.40
	var r_in1 := r1 - w * 1.05
	var r_c1 := r1 - w * 0.10
	var r_out1 := r1 + w * 0.40
	var a_c0 := peak_alpha * k0
	var a_c1 := peak_alpha * k1
	_quad(_center + d0 * r_in0, _center + d0 * r_c0,
		_center + d1 * r_c1, _center + d1 * r_in1, 0.0, a_c0, a_c1, 0.0)
	_quad(_center + d0 * r_c0, _center + d0 * r_out0,
		_center + d1 * r_out1, _center + d1 * r_c1, a_c0, 0.0, 0.0, a_c1)


func _quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		a0: float, a1: float, a2: float, a3: float) -> void:
	var c := trail_color
	draw_polygon(PackedVector2Array([p0, p1, p2, p3]), PackedColorArray([
		Color(c.r, c.g, c.b, a0), Color(c.r, c.g, c.b, a1),
		Color(c.r, c.g, c.b, a2), Color(c.r, c.g, c.b, a3),
	]))
