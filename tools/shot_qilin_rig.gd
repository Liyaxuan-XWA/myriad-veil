extends Node2D
## 赤金火麟骨骼/招式/二阶段截图（2026-10-29）
## 用法：godot --path . res://tools/shot_qilin_rig.tscn
## ⚠ 不能加 --headless：dummy 渲染驱动拿不到视口图像。

var _boss: Node2D


func _ready() -> void:
	get_tree().create_timer(45.0, true, false, true).timeout.connect(func() -> void:
		print("SHOT QILIN TIMEOUT")
		get_tree().quit(2))
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.07, 0.04, 1.0)
	bg.size = Vector2(1280, 720)
	layer.add_child(bg)
	var cam := Camera2D.new()
	cam.position = Vector2(0, -150)
	cam.zoom = Vector2(1.15, 1.15)
	add_child(cam)
	cam.make_current()

	_boss = (load("res://scenes/world/jiedan_core_qilin.tscn") as PackedScene).instantiate()
	var cfg: Dictionary = SecretWorldDB.CORE_BOSS_JIEDAN.duplicate(true)
	cfg["pos"] = Vector2.ZERO
	_boss.configure(cfg, WorldEnemy.KIND_CORE, "赤金火麟")
	_boss.position = Vector2.ZERO
	add_child(_boss)
	await get_tree().process_frame
	await get_tree().process_frame
	_boss.set_physics_process(false)
	await get_tree().create_timer(0.8, true, false, true).timeout
	await _shoot("output/qilin_idle.png")

	_boss.skin.play_one_shot("charge", 0.8)
	await get_tree().create_timer(0.45, true, false, true).timeout
	await _shoot("output/qilin_charge.png")

	_boss.skin.play_one_shot("ring", 0.7)
	await get_tree().create_timer(0.32, true, false, true).timeout
	await _shoot("output/qilin_ring.png")

	# 二阶段：日轮 + 三层霞印绕在一个木桩目标上
	var dummy := Node2D.new()
	add_child(dummy)
	dummy.position = Vector2(240, 40)
	_boss.target = dummy
	_boss.phase = 2
	_boss.call("_on_phase_two")
	_boss.call("_add_mark", 2)
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _shoot("output/qilin_phase2.png")
	print("SHOT qilin done")
	get_tree().quit(0)


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
