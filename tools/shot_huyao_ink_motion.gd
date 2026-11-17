extends Node
## 虎妖水墨卡动效抽帧：固定视角、只推进墨流相位，输出一组连续帧供拼 GIF。
## 用法：godot --path . --windowed --resolution 900x900 tools/shot_huyao_ink_motion.tscn -- --no-save

const FRAMES := 42


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/ink_motion/" + name)
	print("SHOT output/ink_motion/", name)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://output/ink_motion")
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.03, 0.028, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var entry := CodexDB.card_entry("boss_huyao")
	var style: Dictionary = {}
	for raw in (entry.get("card_variants", []) as Array):
		if String((raw as Dictionary).get("id", "")) == "ink":
			style = (raw as Dictionary).duplicate(true)
			break
	var face := CardFace.new()
	if style.is_empty() or not face.configure(style, Vector2(480.0, 720.0),
			entry.get("card_accent", Color(0.86, 0.66, 0.32))):
		print("FAIL ink card build")
		get_tree().quit(1)
		return
	face.position = Vector2(210.0, 90.0)
	add_child(face)
	var ink := face.holo_view()
	face.set_idle_motion(false)
	ink.set_idle_motion(false)
	ink.set_view_speed_immediate(Vector2.ZERO)
	ink.set_process(false)
	await get_tree().process_frame
	for i in FRAMES:
		ink.set_ink_phase_immediate(TAU * float(i) / float(FRAMES))
		await get_tree().process_frame
		await _shot("ink_motion_%02d.png" % i)
	get_tree().quit(0)
