extends Node
## 赫连霄 碰撞框 × 立绘 对照截图（2026-10-30）
## 红 = 场景里的物理碰撞框；青 = 玩家侧受击球（hit_spheres，y 压到 0）。
## 用法：godot --path . --resolution 1280x720 res://tools/shot_heiliao_hitbox.tscn

const OUT := "output/"
var _overlays: Array = []


class ShapeOverlay extends Node2D:
	var circles: Array = []
	var col: Color = Color(1.0, 0.14, 0.16, 0.95)

	func _draw() -> void:
		for c in circles:
			var v: Vector3 = c
			draw_arc(Vector2(v.x, v.y), v.z, 0.0, TAU, 40, col, 2.0, true)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name)
	print("SHOT ", OUT, name)


func _circles_of(sh: CollisionShape2D) -> Array:
	var out: Array = []
	var pos := sh.position
	if sh.shape is CircleShape2D:
		out.append(Vector3(pos.x, pos.y, (sh.shape as CircleShape2D).radius))
	elif sh.shape is CapsuleShape2D:
		var cap := sh.shape as CapsuleShape2D
		var r := cap.radius
		var seg := maxf(0.0, cap.height * 0.5 - r)
		var steps := maxi(1, int(ceil(seg * 2.0 / maxf(r * 0.6, 1.0))))
		for i in range(steps + 1):
			var t := -seg + seg * 2.0 * float(i) / float(steps)
			out.append(Vector3(pos.x - sin(sh.rotation) * t, pos.y + cos(sh.rotation) * t, r))
	return out


func _clear_overlays() -> void:
	for ov in _overlays:
		if is_instance_valid(ov):
			ov.queue_free()
	_overlays.clear()


## kind: "physics" 画场景碰撞框；"hit" 画 hit_spheres（y=0）
func _add_overlay(boss: Node2D, kind: String) -> void:
	var ov := ShapeOverlay.new()
	ov.z_index = 60
	ov.col = Color(1.0, 0.14, 0.16, 0.95) if kind == "physics" else Color(0.16, 0.86, 1.0, 0.95)
	boss.add_child(ov)
	if kind == "physics":
		for child in boss.get_children():
			if child is CollisionShape2D:
				ov.circles.append_array(_circles_of(child as CollisionShape2D))
	else:
		for sp in boss.call("hit_spheres"):
			var v: Vector3 = sp
			ov.circles.append(v)
	ov.queue_redraw()
	_overlays.append(ov)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09)
	bg.size = Vector2(1280, 720)
	bg.z_index = -20
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.19, 0.15, 0.15)
	ground.z_index = -10
	ground.position = Vector2(0, 470)
	ground.size = Vector2(1280, 250)
	add_child(ground)
	var feetline := ColorRect.new()
	feetline.color = Color(0.86, 0.70, 0.36)
	feetline.z_index = -9
	feetline.position = Vector2(0, 469)
	feetline.size = Vector2(1280, 1)
	add_child(feetline)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_03.tscn") as PackedScene).instantiate()
	boss.position = Vector2(640, 470)
	add_child(boss)
	var cam := Camera2D.new()
	cam.position = Vector2(640, 400)
	cam.zoom = Vector2(1.7, 1.7)
	add_child(cam)
	cam.make_current()
	for i in 3:
		await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	await get_tree().create_timer(0.6, true, false, true).timeout

	_add_overlay(boss, "physics")
	await _shot("heiliao_hitbox_physics.png")
	_clear_overlays()
	await get_tree().process_frame
	_add_overlay(boss, "hit")
	await _shot("heiliao_hitbox_spheres.png")

	# 镜像：翻到左边（_set_facing 会镜像碰撞框），确认和立绘一起翻
	boss._set_facing(Vector2.LEFT)
	boss._update_skin_motion()
	_clear_overlays()
	await get_tree().process_frame
	await get_tree().create_timer(0.25, true, false, true).timeout
	_add_overlay(boss, "physics")
	await _shot("heiliao_hitbox_mirrored.png")
	get_tree().quit()
