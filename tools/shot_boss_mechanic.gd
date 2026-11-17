extends Node
## 图鉴「专属机制」模块截图，用来审文案排版（2026-11-02）。
## 用法：godot --path . --windowed --resolution 1600x1000 \
##        tools/shot_boss_mechanic.tscn -- --boss=boss_04_b
## 不给 --boss 就依次拍几张代表性的卡。

const DEFAULTS := ["boss_04_b", "boss_03_c", "world_core_shihou"]


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _wanted() -> Array:
	var out: Array = []
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--boss="):
			out.append(s.trim_prefix("--boss="))
	return out if not out.is_empty() else DEFAULTS


func _ready() -> void:
	var panel := CodexPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	var view: CodexView = panel._view
	view._category_index = 0
	for bid in _wanted():
		view._boss_detail_id = String(bid)
		view._render_list()
		await get_tree().create_timer(0.45, true, false, true).timeout
		var scroll := view.find_child("BossInfoScroll", true, false) as ScrollContainer
		if scroll != null:
			scroll.scroll_vertical = 0
		await get_tree().create_timer(0.15, true, false, true).timeout
		await _shot("mechanic_%s.png" % String(bid))
		var lines := _mechanic_lines(view, String(bid))
		print("   %s  正文 %d 字 / 要点 %d 条 / 最长要点 %d 字" % [
			String(bid), lines[0], lines[1], lines[2]])
	print("SHOT boss mechanic done")
	get_tree().quit(0)


## 顺带把字数统计打出来，方便横向比较哪张卡又写长了
func _mechanic_lines(view: Node, boss_id: String) -> Array:
	var e: Dictionary = CodexDB.boss_entry(boss_id)
	var mech := String(e.get("mechanic", ""))
	var pts: Array = e.get("mechanic_points", [])
	var longest := 0
	for x in pts:
		longest = maxi(longest, String(x).length())
	return [mech.length(), pts.size(), longest]
