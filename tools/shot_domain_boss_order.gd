extends Node2D
## 守关者按序挑战的卡面验收截图（**必须窗口化跑**，headless 抓不到已绘制帧）
##
## 用法：godot --path . --resolution 1280x720 res://tools/shot_domain_boss_order.tscn -- --no-save
## 出图：
##   output/domain_order_0_fresh.png      凡界空档：只有虎妖那张能点，另两张写「需先击败 虎妖」
##   output/domain_order_1_huyao.png      斩虎妖后：虎妖盖「已 斩」，刀客可点，剑客改口点刀客
##   output/domain_order_2_daoke.png      斩刀客后：只剩剑客可点
##
## ⚠ 进度是直接摆 domain_progress（截图脚本要的是三种状态的画面，不是验写入链）；
##   门槛判定、按钮置灰、回执文案全部由真实 board 自己算，这里不重画一遍。

const BOARD := preload("res://scripts/ui/facility/domain_boss_board.gd")
const D1 := "domain_01"


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.05, 0.07, 1.0)
	bg.size = Vector2(1280.0, 720.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var board: Control = BOARD.new()
	board.position = Vector2(90.0, 94.0)
	board.size = Vector2(1100.0, 532.0)
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	await _capture(board, [], "domain_order_0_fresh")
	await _capture(board, ["boss_huyao"], "domain_order_1_huyao")
	await _capture(board, ["boss_huyao", "boss_01"], "domain_order_2_daoke")
	print("SHOT domain_order_0/1/2")
	get_tree().quit(0)


func _capture(board: Control, cleared: Array, tag: String) -> void:
	CharacterData.domain_progress[D1] = {"unlocked": false, "cleared_bosses": cleared}
	board.setup(WorldDB.get_domain(D1))
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/%s.png" % tag)
