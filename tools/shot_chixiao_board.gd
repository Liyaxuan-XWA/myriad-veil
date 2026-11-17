extends Node
## 赤霄界守关者卡面截图
## 用法：godot --path . --resolution 1280x720 res://tools/shot_chixiao_board.tscn -- --no-save

func _ready() -> void:
	CharacterData.current_realm = "结丹"
	CharacterData.domain_progress = {
		"domain_03": {
			"unlocked": true,
			"cleared_bosses": ["boss_03", "boss_03_b", "boss_03_c"],
		},
	}
	CharacterData.boss_death_count = {}
	CharacterData.boss_first_clear_deaths = {}
	var dp = load("res://scripts/ui/panels/domain_panel.gd").new()
	add_child(dp)
	await get_tree().process_frame
	await get_tree().process_frame
	dp.open()
	await get_tree().process_frame
	dp._on_gate_entered("domain_03")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/chixiao_boss_board.png")
	print("SHOT output/chixiao_boss_board.png")

	# 混编状态：第一关已斩、后两关可挑战，检查挑战按钮和未击杀排版
	CharacterData.domain_progress["domain_03"]["cleared_bosses"] = ["boss_03"]
	dp._on_gate_entered("domain_03")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/chixiao_boss_board_alive.png")
	print("SHOT output/chixiao_boss_board_alive.png")
	get_tree().quit()
