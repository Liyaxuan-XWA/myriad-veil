extends Node
## 试炼之路四种小怪立绘验收（2026-11-08）
## 出一张：四只并排站在战斗场景地面上 + 玩家做高度参照。
## 用法（⚠ 必须窗口模式，--headless 截不到图）：
##   godot --path . --resolution 1600x900 res://tools/shot_rogue_minions.tscn -- --no-save

const OUT_DIR := "output"
const MINION_SCENE := "res://scenes/world/world_enemy.tscn"
const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

## 按 target_length 从矮到高排，方便一眼看出四只的体型差
const LINEUP: Array[String] = ["rogue_rat", "rogue_archer", "rogue_golem", "rogue_elite"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT_DIR))

	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	var rogue: Node = arena.get("_rogue")
	# 关掉刷怪机，场上只留我们摆的四只
	if rogue != null:
		rogue.set_process(false)
		rogue.set_physics_process(false)
		for raw in (rogue.get("_alive") as Array).duplicate():
			if is_instance_valid(raw):
				(raw as Node).queue_free()
	await get_tree().process_frame

	var packed := load(MINION_SCENE) as PackedScene
	var x := -320.0
	for id in LINEUP:
		var def: Dictionary = RogueDB.MINIONS.get(id, {})
		var e := packed.instantiate() as WorldEnemy
		var cfg := {
			"pos": Vector2.ZERO, "max_hp": 9999.0, "attack_power": 1.0,
			"move_speed": 0.0, "visual_id": id,
			"aggro_range": 0.0, "leash_range": 0.0,
			"melee_range": 10.0, "melee_angle": 10.0, "melee_coeff": 0.0,
			"body_radius": float(def.get("body_radius", 20.0)),
			"attack_name": "待机", "skills": [], "cast_coeff": 0.0,
		}
		e.name = "Lineup_" + id
		e.position = Vector2(x, 40.0)
		e.configure(cfg, String(def.get("kind", WorldEnemy.KIND_BEAST)),
			String(def.get("name", id)))
		# ⚠ 体型倍率在 _spawn_wave 里才乘，这里手动摆的要自己乘一次，否则对照组是错的
		var scale_v := float(def.get("scale", 1.0))
		if not is_equal_approx(scale_v, 1.0):
			e.scale = Vector2(scale_v, scale_v)
		arena.add_child(e)
		# 罚站：不追不打，只用来对照体型
		e.set_physics_process(false)
		e.set_process(false)
		x += 160.0

	# 玩家站最右做参照
	var player: Node2D = arena.get("player")
	if player != null:
		player.global_position = Vector2(320.0, 40.0)

	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://%s/rogue_minions_lineup.png" % OUT_DIR))
	print("SHOT %s/rogue_minions_lineup.png  %dx%d" % [OUT_DIR, img.get_width(), img.get_height()])
	get_tree().quit(0)
