extends Node
## 赫连霄 idle 剪影（2026-10-30）：只留身体部件、去掉光环与 UI，纯黑底 1:1
## 用途：按**实际渲染姿态**拟合碰撞框（之前按 T-pose + 拼图公式算，和游戏里对不上）。
## 用法：godot --path . --resolution 1280x720 res://tools/shot_heiliao_silhouette.tscn


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.size = Vector2(1280, 720)
	bg.z_index = -50
	add_child(bg)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_03.tscn") as PackedScene).instantiate()
	boss.position = Vector2(640, 360)
	add_child(boss)
	var cam := Camera2D.new()
	cam.position = Vector2(640, 360)
	cam.zoom = Vector2.ONE
	add_child(cam)
	cam.make_current()
	for i in 3:
		await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	await get_tree().create_timer(0.6, true, false, true).timeout

	# 去掉装饰（光环）与所有 UI（血条 / 招式名 / 日冕读数）
	for node in _all_descendants(boss):
		if node is Control or node is CanvasLayer:
			(node as CanvasItem).visible = false
		elif node is Sprite2D:
			var sp := node as Sprite2D
			var tex := sp.texture.resource_path if sp.texture != null else ""
			if tex.contains("halo"):
				sp.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/heiliao_silhouette.png")
	print("SHOT output/heiliao_silhouette.png")
	get_tree().quit()


func _all_descendants(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		out.append(c)
		out.append_array(_all_descendants(c))
	return out
