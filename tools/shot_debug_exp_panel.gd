extends Node
## F2 面板「修为」那一段的预览截图（**必须窗口化跑**，headless 抓不到已绘制帧）。
##
## 跑法：godot --path . res://tools/shot_debug_exp_panel.tscn -- --no-save
## 出图：output/f2_exp_mid.png（加到一半）/ output/f2_exp_full.png（补满后再点一次）
##
## 只为了交付前眼过一遍排版：回执 Label 带了 autowrap 和换行，光靠断言看不出会不会撑坏面板。

const OUT_DIR := "res://output"

var _panel: DebugItemPanel


func _ready() -> void:
	await get_tree().process_frame
	_panel = DebugItemPanel.new()
	add_child(_panel)
	await get_tree().process_frame
	_panel.visible = true
	await get_tree().process_frame
	# ⚠ 不能用 find_child("TabContainer")：代码里 new() 出来的节点名是 @TabContainer@791
	#   这种自动名（和今天 SkillBarRow 撞名是同一个坑），按类名找才有。
	var found: Array = _panel.find_children("*", "TabContainer", true, false)
	if found.is_empty():
		print("[!] 面板里没找到 TabContainer，结构变了")
		get_tree().quit(1)
		return
	var tabs := found[0] as TabContainer
	tabs.current_tab = 3          # 装备 0 / 材料元魂 1 / 法宝 2 / 快捷 3
	await get_tree().process_frame

	# ① 加到一半：看「实际 300」这行
	CharacterData.realm_exp = 0
	_panel._grant_exp(300)
	await _shot("f2_exp_mid")

	# ② 补满之后再点一次：看「本阶段已满，需突破」+ 两行回执会不会把面板撑坏
	_panel._fill_exp()
	_panel._grant_exp(100)
	await _shot("f2_exp_full")

	CharacterData.realm_exp = 0
	get_tree().quit(0)


func _shot(tag: String) -> void:
	# ⚠ 必须先等布局/文本真的过一遍帧，再去等 frame_post_draw：
	#   只 frame_post_draw 的话两张图会**逐字节相同**（实测过），改完状态根本没画出来。
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, tag])
	print("saved ", tag, " ", img.get_width(), "x", img.get_height())

