extends Node2D
## 指引「脚边箭头」实机取证（窗口化）
## godot --path . --resolution 1280x720 res://tools/shot_tutorial_arrow.tscn -- --no-save

const PLAYER_SCENE := "res://scenes/player/player.tscn"

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.12, 0.18, 1.0)
	bg.size = Vector2(1280.0, 720.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Node2D
	add_child(p)
	p.global_position = Vector2(640.0, 420.0)
	var far := Node2D.new()
	far.name = "FarTarget"
	add_child(far)
	far.global_position = Vector2(2600.0, 380.0)   # 屏幕右侧很远
	for i in 6:
		await get_tree().process_frame
	Tutorial.active_step = {"id": "__shot_arrow__", "text": "去右侧的万界塔",
		"anchor": "path:FarTarget", "manual": true}
	Tutorial.changed.emit()
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tutorial_feet_arrow.png")
	print("SHOT output/tutorial_feet_arrow.png")
	get_tree().quit(0)
