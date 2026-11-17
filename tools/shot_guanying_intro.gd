extends Node
## 观澜 BOSS 入场卡截图（2026-11-01）

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.050, 0.075)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var card := BossIntroCard.new()
	add_child(card)
	card.open(CodexDB.boss_entry("boss_04"), {
		"title": "照影界 · 观澜",
		"source_line": "照影界 · 第一关",
	})
	await get_tree().create_timer(4.0).timeout
	await _shot("guanying_intro_card.png")
	get_tree().quit(0)
