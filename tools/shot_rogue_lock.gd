extends Node
## 试炼之路「局内禁用背包 / 突破」视觉验收（2026-11-08）
## 出一张：局内按 Tab（= 直接调 CharacterPanel.open_panel）后，面板**不出现**、只有一句提示。
## 用法（⚠ 必须窗口模式，--headless 截不到图）：
##   godot --path . --resolution 1600x900 res://tools/shot_rogue_lock.tscn -- --no-save

const OUT_DIR := "output"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))

	RogueRun.start_run()
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	var player: Node2D = arena.get("player")
	if player != null:
		player.global_position = Vector2(0.0, 80.0)
	# 开场关卡标题卡要 2 秒才散，等它走完再截
	for i in 170:
		await get_tree().process_frame

	# 真实入口走一遍：rogue 局内开面板应当被拒
	CharacterPanel.open_panel()
	print("SHOT-CHECK 面板是否打开=", CharacterPanel.is_open(),
		"  （应为 false）rogue_lock=", CharacterData.rogue_lock)
	for i in 12:
		await get_tree().process_frame
	await _snap("rogue_lock_toast")
	get_tree().quit()


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	img.save_png(path)
	print("SHOT ", path, "  ", img.get_width(), "x", img.get_height())
