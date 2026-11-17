extends Node
## 试炼之路 · 虎妖视觉验收截图（2026-11-08）
## 出两张：入口「开局流派」三选一（虎妖选中） / 虎妖局内（踏地 + 增益清单）
## 用法（⚠ 必须窗口模式，--headless 截不到图）：
##   godot --path . --resolution 1600x900 res://tools/shot_rogue_beast.tscn -- --no-save

const OUT_DIR := "output"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	# 工具环境：置「已通关万界秘境·凡界虎妖」，否则试炼入口的前置门禁会挡住本工具。
	# 直接写 domain_progress（不调 mark_boss_killed，避免掺进首杀奖励等无关副作用）。
	CharacterData.domain_progress[RogueDB.TRIAL_UNLOCK_DOMAIN] = {
		"unlocked": true, "cleared_bosses": [RogueDB.TRIAL_UNLOCK_BOSS]}

	# ---- 入口：万界塔面板第二页签，选中虎妖 ----
	var panel: Node = (load("res://scripts/ui/panels/tower_panel.gd") as GDScript).new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	for i in 6:
		await get_tree().process_frame
	panel.call("_switch_tab", 1)
	for i in 4:
		await get_tree().process_frame
	panel.call("_on_pick_family", "beast")
	for i in 8:
		await get_tree().process_frame
	await _snap("rogue_00_entry")
	panel.call("close")
	get_tree().paused = false
	for i in 3:
		await get_tree().process_frame

	# ---- 虎妖局内：走真实施法，截踏地那一记 ----
	RogueRun.start_run("beast")
	for id in ["t_bl_range", "t_bl_break", "t_bl_heavy", "t_sb_count",
			"t_sb_slow", "g_str", "g_hp"]:
		RogueRun.add_buff(id)
	RogueRun.floor_no = 2
	RogueRun.stage_no = 2
	RogueRun.wave_no = 2

	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 2}
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
	# 让玩家面向镜头右侧的怪群再踏地（软锁定会自己转，这里只保证方向不为零）
	player.set("attack_dir", Vector2.RIGHT)
	player.call("try_use_skill", "skill_tiger_stomp")
	for i in 16:
		await get_tree().process_frame
	await _snap("rogue_06_beast")
	get_tree().quit()


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	img.save_png(path)
	print("SHOT ", path, "  ", img.get_width(), "x", img.get_height())
