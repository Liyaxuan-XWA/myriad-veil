extends Node
## 晏无咎八式骨骼姿态截图（2026-10-29）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_wujiu_poses.tscn

const WINDUP := {
	"form_calamity_step": 0.55,
	"form_calamity_slash": 0.60,
	"form_calamity_fire_seal": 0.70,
	"form_calamity_fire_field": 0.75,
	"form_calamity_thunder_strike": 0.75,
	"form_calamity_thunder_pool": 0.80,
	"form_calamity_turn": 0.70,
	"form_calamity_final": 1.20,
}


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.052, 0.070)
	bg.size = Vector2(1280, 720)
	bg.z_index = -20
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.15, 0.14, 0.17)
	ground.z_index = -10
	ground.position = Vector2(0, 600)
	ground.size = Vector2(1280, 120)
	add_child(ground)

	var boss: Node2D = (load("res://scenes/boss/domain_boss_03_c.tscn") as PackedScene).instantiate()
	boss.position = Vector2(640, 600)
	add_child(boss)
	var cam := Camera2D.new()
	cam.position = Vector2(640, 545)
	cam.zoom = Vector2(2.2, 2.2)
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	# 关掉 BOSS 自带的术法底色，只看 rig 的三段劫环和身体
	var fx := boss.get_node_or_null("CalamityWheelFX")
	if fx != null:
		fx.visible = false
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _shot("wujiu_pose_idle.png")
	for sid in WINDUP.keys():
		var w: float = WINDUP[sid]
		boss._play_form_anim(sid, w + 0.15)
		await get_tree().create_timer(w * 0.93, true, false, true).timeout
		await _shot("wujiu_pose_" + sid.replace("form_calamity_", "") + ".png")
		await get_tree().create_timer(0.4, true, false, true).timeout
	get_tree().quit()
