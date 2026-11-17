extends Node
## 「周身一环」这条指引卡的预览截图（**必须窗口化跑**，headless 抓不到已绘制帧）。
##
## 跑法：godot --path . res://tools/shot_tutorial_blood.tscn -- --no-save
## 出图：output/tutorial_c2_blood.png
##
## 为什么要拍：文案从 51 字改到 70 字，说明卡的 Label 会不会多绕一行、
## 把「知道了」按钮挤到哪去，光看字符串长度判断不了。
## ⚠ Tutorial 是 autoload，卡片由它自己建的 overlay 画 —— 这里只设 active_step，
##   不要手动 new 一个 overlay（文件头写了「不要手动挂到场景里」）。

func _ready() -> void:
	await get_tree().process_frame
	var step: Dictionary = TutorialDB.get_step("c2_blood")
	if step.is_empty():
		print("[!] 找不到 c2_blood，指引表结构变了")
		get_tree().quit(1)
		return
	Tutorial.active_step = step
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://output/tutorial_c2_blood.png")
	print("saved tutorial_c2_blood ", img.get_width(), "x", img.get_height())
	Tutorial.active_step = {}
	get_tree().quit(0)
