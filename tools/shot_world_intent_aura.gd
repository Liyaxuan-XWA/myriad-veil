extends Node
## 大世界技能栏「剑意就绪光环」截图（窗口化）：同一位置连拍两帧，看环是否在转
## godot --path . --resolution 1280x720 res://tools/shot_world_intent_aura.tscn -- --no-save

const WORLD := "res://scenes/world/secret_world.tscn"

func _ready() -> void:
	CharacterData.active_skill_loadout = ["skill_sword_heaven", "skill_sword_myriad",
		"skill_sword_stab", "skill_sword_chop"]
	var w: Node = (load(WORLD) as PackedScene).instantiate()
	add_child(w)
	for i in 8:
		await get_tree().process_frame
	var p: Node2D = w.get("player")
	p.set_physics_process(false)
	p.set("sword_intent", int(p.call("_sword_intent_max")))
	w.call("_update_skill_bar")
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/world_intent_aura_a.png")
	# 只看技能栏那一块（1440×160 居中底部），放大两倍看清环
	var c := img.get_region(Rect2i(440, 600, 420, 120))
	var big := Image.create(c.get_width() * 2, c.get_height() * 2, false, c.get_format())
	for y in c.get_height():
		for x in c.get_width():
			var col := c.get_pixel(x, y)
			for dy in 2:
				for dx in 2:
					big.set_pixel(x * 2 + dx, y * 2 + dy, col)
	big.save_png("output/world_intent_aura_zoom.png")
	print("SHOT output/world_intent_aura_a.png / _zoom.png")
	get_tree().quit(0)
