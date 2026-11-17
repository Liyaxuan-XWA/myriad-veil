extends Node
## 试炼之路 · 刀修视觉验收截图（2026-11-08）
## 出两张：入口「本局流派」选择 / 刀修局内（刀痕铺场 + 增益清单）
## 用法（⚠ 必须窗口模式，--headless 截不到图）：
##   godot --path . --resolution 1600x900 res://tools/shot_rogue_scar.tscn -- --no-save

const OUT_DIR := "output"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	# 工具环境：置「已通关万界秘境·凡界虎妖」，否则试炼入口的前置门禁会挡住本工具。
	# 直接写 domain_progress（不调 mark_boss_killed，避免掺进首杀奖励等无关副作用）。
	CharacterData.domain_progress[RogueDB.TRIAL_UNLOCK_DOMAIN] = {
		"unlocked": true, "cleared_bosses": [RogueDB.TRIAL_UNLOCK_BOSS]}

	# ---- 入口：万界塔面板第二页签（本局流派选择）----
	var panel: Node = (load("res://scripts/ui/panels/tower_panel.gd") as GDScript).new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	for i in 6:
		await get_tree().process_frame
	panel.call("_switch_tab", 1)
	for i in 6:
		await get_tree().process_frame
	await _snap("rogue_00_entry")
	panel.call("close")
	get_tree().paused = false
	for i in 3:
		await get_tree().process_frame

	# ---- 刀修局内：铺三处刀痕，看 HUD 清单与地面刀痕 ----
	RogueRun.start_run("scar")
	for id in ["b_sp_cap", "b_sp_mult", "b_pk_charge", "b_pk_block", "b_bd_low", "g_speed"]:
		RogueRun.add_buff(id)
	RogueRun.floor_no = 3
	RogueRun.stage_no = 2
	RogueRun.wave_no = 2

	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 3}
	var arena := (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	var player: Node2D = arena.get("player")
	if player == null:
		push_error("战斗场景没建起来")
		get_tree().quit(1)
		return
	player.global_position = Vector2(0.0, 80.0)
	# ⚠ 开场公告 2 秒后才散，等它走完再截
	for i in 170:
		await get_tree().process_frame

	var field := ScarField.ensure()
	if field != null:
		for off in [Vector2(-170.0, 150.0), Vector2(0.0, 230.0), Vector2(170.0, 150.0)]:
			field.spawn_scar(player.global_position + (off as Vector2),
				BladeScar.SIDE_PLAYER, 40.0, 1.0, null, "physical", player)
	for i in 6:
		await get_tree().process_frame
	await _snap("rogue_05_scar")
	get_tree().quit()


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	img.save_png(path)
	print("SHOT ", path, "  ", img.get_width(), "x", img.get_height())
