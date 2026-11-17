extends Node2D
## 武器横扫视觉：一个扇形弧光，短暂显示后消失
## 用于BOSS近战攻击的动作表现（非伤害判定，仅视觉）

var sweep_radius: float = 110.0      # 横扫半径
var sweep_angle: float = 120.0       # 横扫张角（度）
var sweep_color: Color = Color(1.0, 0.5, 0.2, 0.5)
var duration: float = 0.25           # 显示时长
var direction: Vector2 = Vector2.RIGHT  # 朝向

var _elapsed: float = 0.0


func _ready() -> void:
	# 朝 facing 方向旋转
	rotation = direction.angle()
	# 渐隐
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_callback(queue_free)


func _draw() -> void:
	# 绘制扇形（由中心向外放射的多边形近似）
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	var half_angle := deg_to_rad(sweep_angle) / 2.0
	var steps := 24
	for i in range(steps + 1):
		var a: float = -half_angle + (deg_to_rad(sweep_angle) * i / steps)
		points.append(Vector2(cos(a), sin(a)) * sweep_radius)
	draw_colored_polygon(points, sweep_color)
