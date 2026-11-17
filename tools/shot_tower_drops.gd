extends Node
## 万界塔右侧「本层掉落」截图：普通场次 + 双倍血量场次（2026-11-13）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_tower_drops.tscn -- --no-save

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot_panel(panel: Node, path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path + "_full.png")
	var detail: Control = panel.get("_detail_panel")
	var r := detail.get_global_rect()
	img.get_region(Rect2i(int(r.position.x) - 4, int(r.position.y) - 4,
		int(r.size.x) + 8, int(r.size.y) + 8)).save_png(path + ".png")
	print("SHOT ", path, "_full.png / ", path, ".png  detail=", r)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.tower_progress[1] = {"unlocked": true, "first_kill": true,
		"clear_count": 1}
	var p: Node = (load("res://scripts/ui/panels/tower_panel.gd") as GDScript).new()
	add_child(p)
	await _frames(3)
	p.call("open")
	await _frames(8)
	p.call("_select_floor", 1)
	await _frames(6)
	await _shot_panel(p, "output/tower_drops_clear")

	# 双倍血量场次：第 11 次挑战多一行元魂
	CharacterData.tower_progress[1]["clear_count"] = 10
	p.call("_refresh_detail")
	await _frames(4)
	await _shot_panel(p, "output/tower_drops_double")
	p.call("close")
	await _frames(2)
	get_tree().quit(0)
