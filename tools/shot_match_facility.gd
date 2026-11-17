extends Node
## 万界棋坛地标实机尺寸截图（2026-11-04）
## 把玩家摆到棋坛旁边，让相机自然取景，和相邻的记忆幻像碑 / 演武场同框比大小。
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_match_facility.tscn -- --no-save

const SPOTS := {
	"near_match": Vector2(150, 380),     # 棋坛(260,420) + 记忆碑(0,420) + 演武场(520,320) 同框
	"match_alone": Vector2(250, 430),    # 只框棋坛，看细节撑不撑得住
}


func _ready() -> void:
	var win := get_window()
	win.always_on_top = true
	win.title = "万界棋坛地标截图"
	var scene: Node = load("res://scenes/main/primordial_realm.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = scene.get_node_or_null("Player")
	if player == null:
		push_error("场景里没有 Player")
		get_tree().quit(1)
		return
	for key in SPOTS:
		player.set("global_position", SPOTS[key])
		await get_tree().create_timer(0.45, true, false, true).timeout
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var full := "output/match_facility_%s.png" % String(key)
		img.save_png(full)
		print("SHOT ", full, "  ", img.get_size())
		if String(key) == "match_alone":
			# 相机中心 ≈ 玩家位置；裁 460x300 出来看像素级细节
			var c := img.get_used_rect()
			var cx: int = img.get_width() / 2
			var cy: int = img.get_height() / 2
			var rect := Rect2i(maxi(cx - 230, 0), maxi(cy - 150, 0),
				mini(460, c.size.x), mini(300, c.size.y))
			var crop := img.get_region(rect)
			crop.save_png("output/match_facility_zoom.png")
			print("SHOT output/match_facility_zoom.png  ", crop.get_size())
	get_tree().quit(0)
