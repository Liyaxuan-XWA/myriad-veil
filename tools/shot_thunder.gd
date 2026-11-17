extends Node

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09, 1.0)
	bg.size = Vector2(1280, 720)
	bg.position = Vector2(-640, -360)
	add_child(bg)
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	ArrayFx.play_thunder(self, Vector2(0.0, 80.0), Color(1.0, 0.35, 0.25))
	await get_tree().create_timer(0.06, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/thunder.png")
	print("SHOT output/thunder.png")
	get_tree().quit()
