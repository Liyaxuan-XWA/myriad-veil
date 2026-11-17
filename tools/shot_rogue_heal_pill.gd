extends Node
## 试炼回血丹掉落物验收截图（窗口模式）
## 用法：godot --path . --resolution 1600x900 res://tools/shot_rogue_heal_pill.tscn -- --no-save

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
	# 冻住调度器、清掉第一波小怪，只留掉落物做视觉验收
	rogue.set_process(false)
	for raw in (rogue.get("_alive") as Array):
		if is_instance_valid(raw):
			(raw as Node).free()
	player.global_position = Vector2(0.0, 60.0)
	player.set("invincible_timer", 999.0)
	# 丹落在玩家右侧（仍在 42px 拾取范围内，但不压住角色）；
	# 等久一点让开波的「试炼之路 第 1 层」大字公告淡出，画面才干净
	rogue.call("_spawn_heal_pill", player.global_position + Vector2(38.0, -8.0))
	for i in 150:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "output/rogue_heal_pill.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)

	# ===== 真实按 F 验收：必须走 _unhandled_input，才能抓到「试炼分支吞掉 F」 =====
	player.set("hp", 50.0)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var ev_up := InputEventKey.new()
	ev_up.physical_keycode = KEY_F
	ev_up.keycode = KEY_F
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path2 := "output/rogue_heal_pill_picked.png"
	get_viewport().get_texture().get_image().save_png(path2)
	print("SHOT ", path2, " hp=", player.get("hp"))

	RogueRun.restore()
	get_tree().quit(0)
