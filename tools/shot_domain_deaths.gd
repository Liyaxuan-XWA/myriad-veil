extends Node
## 万界秘境守关者卡面 · 死亡记录实景截图
## 用法：godot --path . --resolution 1280x720 res://tools/shot_domain_deaths.tscn -- --no-save

func _ready() -> void:
	CharacterData.domain_progress = {
		"domain_01": {"unlocked": true, "cleared_bosses": ["boss_01"]},
	}
	CharacterData.boss_death_count = {
		"domain_01/boss_huyao": 4,
		"domain_01/boss_01": 5,
	}
	CharacterData.boss_first_clear_deaths = {
		"domain_01/boss_01": 2,
	}
	var dp = load("res://scripts/ui/panels/domain_panel.gd").new()
	add_child(dp)
	await get_tree().process_frame
	await get_tree().process_frame
	dp.open()
	await get_tree().process_frame
	dp._on_gate_entered("domain_01")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/domain_boss_deaths.png")
	print("SHOT output/domain_boss_deaths.png")
	get_tree().quit()
