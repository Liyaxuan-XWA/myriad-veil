extends Node
## 试炼局内行囊 / 境界 HUD 验收截图（窗口模式）
## 出两张：output/rogue_realm_hud.png（顶栏境界行）/ output/rogue_gear_panel.png（Tab 面板）
## 用法：godot --path . --resolution 1600x900 res://tools/shot_rogue_gear_panel.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	if rogue == null or player == null:
		get_tree().quit(1)
		return
	rogue.set_process(false)
	for raw in (rogue.get("_alive") as Array):
		if is_instance_valid(raw):
			(raw as Node).free()
	(rogue.get("_alive") as Array).clear()
	player.set("invincible_timer", 999.0)

	# 摆一个「打到一半」的局内状态：3 件 BOSS 装备、穿 1 件、修为接近突破
	for eid in ["eq_qingfengjian", "eq_hupipao", "eq_huyaxianglian"]:
		RogueRun.add_gear(CharacterData.make_equipment_instance(
			ItemDB.get_equipment_template(eid)))
	RogueRun.equip_from_bag(0)
	RogueRun.realm_exp = 72
	rogue.call("_update_hud")
	# 等开波公告淡出，画面才干净
	for i in 150:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_realm_hud.png")
	print("SHOT output/rogue_realm_hud.png")

	# BOSS 遗物落地长什么样（第三张图）：掉在玩家旁边，看光柱 / 图标 / F 提示
	var drop_eq := CharacterData.make_equipment_instance(
		ItemDB.get_equipment_template("eq_qingfengjian"))
	rogue.call("_spawn_gear_drop", drop_eq, player.global_position + Vector2(150.0, 0.0))
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_boss_drop.png")
	print("SHOT output/rogue_boss_drop.png")

	# 真实按 Tab → CharacterPanel._input → RogueGearPanel
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	ev.keycode = KEY_TAB
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 6:
		await get_tree().process_frame
	var ev_up := InputEventKey.new()
	ev_up.physical_keycode = KEY_TAB
	ev_up.keycode = KEY_TAB
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_gear_panel.png")
	print("SHOT output/rogue_gear_panel.png")

	var panel: Node = CharacterPanel.get("_rogue_gear_panel")
	if panel != null and is_instance_valid(panel):
		panel.call("close")
	RogueRun.restore()
	arena.free()
	get_tree().quit(0)
