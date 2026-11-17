extends Node
## 万界塔面板整屏截图（审「挑战此层」是否一屏可见）。
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_tower_panel.tscn -- --no-save

func _ready() -> void:
	var p: Node = (load("res://scripts/ui/panels/tower_panel.gd") as GDScript).new()
	add_child(p)
	await get_tree().process_frame
	p.open()
	for i in range(8):
		await get_tree().process_frame
	var btn: Control = p.get("_challenge_btn")
	var root: Control = p.get("_root")
	var vp := get_viewport().get_visible_rect().size
	var r := btn.get_global_rect()
	print("视口=", vp, " 面板=", root.position, "x", root.size)
	print("按钮 rect=", r, "  在可视区内=", r.end.y <= vp.y and r.position.y >= 0.0)
	p.call("_select_floor", 1)
	for i in range(4):
		await get_tree().process_frame
	var ms: Control = p.get("_map_scroll")
	print("地图 scroll_v=", ms.get("scroll_vertical"), " 第1层按钮在=", (p.get("_floor_by_no")[1] as Dictionary)["button"].get_global_position())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tower_floor1.png")
	print("SHOT output/tower_floor1.png")

	# 滚到最顶：最高几层必须能看到（2026-11-02 用户报「无法滑动到上面」）
	var map: Control = p.get("_map")
	var sc := ms as ScrollContainer
	var bar := sc.get_v_scroll_bar()
	print("地图高=", map.size.y, " 滚动视口高=", ms.size.y,
		" scroll 范围=[%.0f, %.0f]" % [bar.min_value, bar.max_value])
	var floors: Array = WorldDB.get_floors()
	var top_no := int((floors[floors.size() - 1] as Dictionary).get("floor", 0))
	sc.scroll_vertical = 0
	for i in range(4):
		await get_tree().process_frame
	var top_row: Dictionary = (p.get("_floor_by_no") as Dictionary).get(top_no, {})
	var top_btn: Control = top_row.get("button")
	var top_rect := top_btn.get_global_rect()
	var view_rect := ms.get_global_rect()
	print("最高层 ", top_no, " rect=", top_rect,
		" 在滚动视口内=", view_rect.encloses(top_rect))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tower_top.png")
	print("SHOT output/tower_top.png")
	get_tree().quit(0)
