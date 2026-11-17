extends Node
## 晏无咎 BOSS 入场卡截图（2026-10-29）

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.050, 0.062)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var card := BossIntroCard.new()
	add_child(card)
	card.open(CodexDB.boss_entry("boss_03_c"), {
		"title": "赤霄界 · 晏无咎",
		"source_line": "赤霄界 · 第三关",
	})
	await get_tree().create_timer(4.0, true, false, true).timeout
	await _shot("wujiu_intro_card.png")
	get_tree().quit(0)
