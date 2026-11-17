extends Node
## 任务卡流光「不出卡」的取证图（窗口化）
## godot --path . --resolution 1280x720 res://tools/shot_quest_sheen.tscn -- --no-save
## ⚠ 用真实的卡面装饰层（QuestCardDeco）按卡片实际尺寸(300×160)摆在一块底板上，
##   把 _t 定在「光带扫到右半边」那一拍 —— 修的就是这一拍越出右边缘。

const PANEL_SCRIPT := "res://scripts/tutorial/quest_panel.gd"
const CARD := Vector2(300.0, 160.0)

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.16, 0.22, 1.0)
	bg.size = Vector2(420.0, 260.0)
	bg.position = Vector2(40.0, 40.0)
	add_child(bg)
	var qp = load(PANEL_SCRIPT)
	var deco = qp.QuestCardDeco.new()
	deco.size = CARD
	deco.position = Vector2(60.0, 60.0)
	add_child(deco)
	deco.set("_t", float(qp.SHEEN_SWEEP) * 0.80)
	deco.call("queue_redraw")
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/quest_sheen_full.png")
	# 只裁卡的右边缘 ±30px，放大 3 倍看有没有亮线戳出去
	var r: Rect2 = deco.get_global_rect()
	var x0 := int(r.position.x + r.size.x - 30.0)
	var crop := img.get_region(Rect2i(x0, int(r.position.y), 60, int(r.size.y)))
	var big := Image.create(crop.get_width() * 3, crop.get_height() * 3, false, crop.get_format())
	for y in crop.get_height():
		for x in crop.get_width():
			var col := crop.get_pixel(x, y)
			for dy in 3:
				for dx in 3:
					big.set_pixel(x * 3 + dx, y * 3 + dy, col)
	big.save_png("output/quest_sheen_right_edge.png")
	print("SHOT output/quest_sheen_full.png / quest_sheen_right_edge.png  card=", r)
	get_tree().quit(0)
