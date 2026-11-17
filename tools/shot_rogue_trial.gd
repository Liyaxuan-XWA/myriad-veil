extends Node
## 试炼之路专属战场验收（2026-11-08）
## 出一张局内实景，并打印 Ground 下的美术节点，确认走的是「无尽试炼台」而不是
## 原初位面星海 / 某一只 BOSS 的战场。
## 用法（⚠ 必须窗口模式）：
##   godot --path . --resolution 1600x900 res://tools/shot_rogue_trial.tscn -- --no-save

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
	var player: Node2D = arena.get("player")
	if player != null:
		player.global_position = Vector2(0.0, 90.0)
	for i in 90:
		await get_tree().process_frame

	var ground: Node = arena.get_node_or_null("Ground")
	if ground != null:
		for c in ground.get_children():
			var tex: Texture2D = null
			if c is TextureRect:
				tex = (c as TextureRect).texture
			elif c is Sprite2D:
				tex = (c as Sprite2D).texture
			print("GROUND-NODE ", c.name, " tex=",
				"无" if tex == null else "%dx%d" % [tex.get_width(), tex.get_height()])
	var hud: Node = arena.get_node_or_null("HUD")
	print("GRADE-NODE ", "有" if (hud != null and hud.get_node_or_null("ArenaGrade") != null) else "无")

	await RenderingServer.frame_post_draw
	var path := "output/rogue_trial_arena.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	RogueRun.restore()
	get_tree().quit(0)
