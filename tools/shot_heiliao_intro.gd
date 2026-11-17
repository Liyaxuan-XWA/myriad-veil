extends Node
## 赫连霄 BOSS 入场卡截图
## 用法：godot --path . --windowed --resolution 1280x720 res://tools/shot_heiliao_intro.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.045, 0.065)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var card := BossIntroCard.new()
	add_child(card)
	card.open(CodexDB.boss_entry("boss_03"), {
		"title": "赤霄界 · 赫连霄",
		"source_line": "赤霄界 · 第一关",
	})
	await get_tree().create_timer(4.0, true, false, true).timeout
	await _shot("heiliao_intro_card.png")
	get_tree().quit(0)
