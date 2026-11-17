extends Node
## 试炼入口页 · 切流派视觉对照（2026-11-08）
## 出三张：剑修 / 虎妖 / 两仪（文案最短 / 中等 / 最长），验证面板外形完全一致。
## 用法：godot --path . --resolution 1600x900 res://tools/shot_rogue_family_layout.tscn -- --no-save

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	var old_best := CharacterData.rogue_best_floor
	CharacterData.rogue_best_floor = 50       # 全解锁才能切到两仪
	var p: Node = (load("res://scripts/ui/panels/tower_panel.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(p)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	p.open()
	await get_tree().process_frame
	# 先拍「刚打开面板」的塔层页：用户就是从这一屏找不到试炼入口的
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/tower_entry_tabs.png")
	print("SHOT output/tower_entry_tabs.png")
	p.call("_switch_tab", 1)
	await get_tree().process_frame
	await get_tree().process_frame
	for fam in ["sword", "beast", "yinyang", "talisman"]:
		p.call("_on_pick_family", fam)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "output/rogue_family_%s.png" % fam
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path, "  root=", str((p.get("_root") as Control).size))
	# 0 层解锁面（2026-11-09 符箓改初始开放）：看「符箓」按钮是不是亮的、其余是否压暗
	CharacterData.rogue_best_floor = 0
	p.call("_refresh_family_picker")
	# ⚠ 文字标签（历史最高 / 已解锁 / 未解锁）在 _refresh_rogue_page() 里，
	#   只调 picker 会拍到「按钮已按 0 层算、文字还停在 50 层」的假画面
	p.call("_refresh_rogue_page")
	await get_tree().process_frame
	var open_at_zero: Array[String] = []
	var locked_n := 0
	for b in p.get("_rogue_family_buttons"):
		var bb := b as Button
		if bb == null:
			continue
		if bb.disabled:
			locked_n += 1
		else:
			open_at_zero.append(String(bb.get_meta("family", "")))
	print("0 层开放=", "、".join(open_at_zero), " 锁住=", locked_n, " 套")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_family_floor0.png")
	print("SHOT output/rogue_family_floor0.png")
	CharacterData.rogue_best_floor = old_best
	get_tree().quit(0)
