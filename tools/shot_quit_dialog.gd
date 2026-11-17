extends Node
## 退出确认框整屏截图（审「保存并退出」那一档是否一眼读得清）。
## 用法：godot --path . --windowed --resolution 1280x720 tools/shot_quit_dialog.tscn -- --no-save
## 不进主城：那个场景首次加载要解一大堆有损贴图，几分钟都出不来图。
## 本工具场景本身就落在 in_game_world() 为真的位面上，够走到「有进度」那档文案。

func _ready() -> void:
	for i in range(6):
		await get_tree().process_frame
	# 截图要走到「有进度 → 保存并退出」那档：只放开 auto_save_enabled，
	# write_enabled 仍被 --no-save 关着，所以这一步不会碰真实存档
	CharacterData.tower_progress = {1: {"unlocked": true, "first_kill": true, "clear_count": 3}}
	SaveManager.auto_save_enabled = true
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	for i in range(14):
		await get_tree().process_frame
	var d: ConfirmDialog = GameState.get("_quit_dialog")
	if d == null:
		print("FAIL 确认框没弹出来")
		get_tree().quit(1)
	print("标题=", d.dlg_title, " 按钮=", d.ok_text, "/", d.cancel_text, " 危险色=", d.danger)
	print("正文=", d.dlg_message)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/quit_dialog.png")
	print("SHOT output/quit_dialog.png")
	SaveManager.auto_save_enabled = false
	get_tree().paused = false
	get_tree().quit(0)
