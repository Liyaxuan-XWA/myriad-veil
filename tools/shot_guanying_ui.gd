extends Node
## 观澜 · 星图 / 守关者 / 万界塔 / 图鉴 UI 截图（2026-11-01）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_guanying_ui.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 0
	CharacterData.domain_progress = {
		"domain_04": {"unlocked": true, "cleared_bosses": []},
	}
	CharacterData.boss_progress["boss_04"] = {"killed": false, "first_kill": false}
	CharacterData.tower_progress[10] = {"unlocked": true, "first_kill": false, "clear_count": 0}
	CharacterData.boss_death_count = {}
	CharacterData.boss_first_clear_deaths = {}

	var dp := DomainPanel.new()
	add_child(dp)
	await get_tree().process_frame
	await get_tree().process_frame
	dp.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("guanying_star_map.png")
	dp._on_gate_entered("domain_04")
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("guanying_boss_board.png")

	var tp := TowerPanel.new()
	add_child(tp)
	await get_tree().process_frame
	tp.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("guanying_tower_panel.png")

	var cp := CodexPanel.new()
	add_child(cp)
	await get_tree().process_frame
	cp.open()
	await get_tree().process_frame
	var view: CodexView = cp._view
	view._category_index = 0
	view._boss_detail_id = "boss_04"
	view._render_list()
	await get_tree().create_timer(0.4).timeout
	await _shot("guanying_codex_detail.png")
	var info_scroll := view.find_child("BossInfoScroll", true, false) as ScrollContainer
	if info_scroll != null:
		info_scroll.scroll_vertical = 420
		await get_tree().create_timer(0.2).timeout
		await _shot("guanying_codex_mid.png")
		info_scroll.scroll_vertical = 100000
		await get_tree().create_timer(0.2).timeout
		await _shot("guanying_codex_bottom.png")
	get_tree().quit(0)
