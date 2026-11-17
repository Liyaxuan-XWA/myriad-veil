extends Node
## 试炼之路「遗物到手提示」截图验收（2026-11-11 用户要）
## 出两张：
##   ① 捡到遗物瞬间 —— 底部中央的提示卡（写了装备名 / 按 Tab 打开行囊穿戴）
##   ② 1.2 秒后 —— 提示卡还在（不是一闪就没的飘字），战斗照常进行
## 用法：godot --path . --resolution 1280x720 res://tools/shot_rogue_gear_hint.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	# 教学与顺序任务全静默：截图只要战斗画面，不要别的浮层抢镜
	CharacterData.tutorial_data = {"legacy": true}
	CharacterData.quest_data = {"done": {}}
	Quest.set("_poll_left", 99999.0)

	# ===== 进试炼局内（真实入口：GameState.battle_context + combat_arena）=====
	RogueRun.start_run()
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	BattleResolver.skip_next_intro = true
	var arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = arena
	for i in 10:
		await get_tree().process_frame
	var rogue = arena.get("_rogue")
	var player: Node2D = arena.get("player")
	if rogue == null or player == null:
		push_error("试炼局内没起来")
		get_tree().quit(1)
		return
	# ⚠ 先等开场演出（中央「试炼之路 · 第 1 层」大字 + 淡出）走完再干活，
	#   否则第一张会截到「提示卡上压着一行开场大字」，看不出卡片本身。
	await get_tree().create_timer(2.4).timeout
	await get_tree().process_frame

	# ===== 走真实链路：遗物落地 → F 拾取（combat_arena._try_pickup_nearest）=====
	var eq := RogueDB.roll_boss_gear("boss_huyao")
	rogue.call("_spawn_gear_drop", eq, player.global_position)
	await get_tree().process_frame
	arena.call("_try_pickup_nearest")
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_gear_hint.png")
	print("SHOT output/rogue_gear_hint.png")

	# ===== 1.2 秒后还在（提示停留 12 秒，不是一闪而过）=====
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/rogue_gear_hint_later.png")
	print("SHOT output/rogue_gear_hint_later.png")

	get_tree().quit(0)
