extends Node
## 试炼之路专属战场 · 接线与模式隔离自检（2026-11-08）
## 验：① 试炼局用 bg_rogue_trial（平铺地面 + 中心阵眼 + 灯光分级）
##     ② 非试炼模式仍走原来的 BOSS→战场映射，一点都没被新模式污染
## 用法：godot --headless --path . res://tools/probe_rogue_trial_scene.tscn -- --no-save

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	print("\n########## 试炼战场接线 ##########")
	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(String(arena.get("ground_visual_id")) == "bg_rogue_trial",
		"试炼局用专属战场美术", String(arena.get("ground_visual_id")))
	var ground: Node = arena.get_node_or_null("Ground")
	var tiled: TextureRect = null if ground == null else ground.get_node_or_null("TiledBG") as TextureRect
	_check(tiled != null and tiled.texture != null,
		"专属地面已平铺（TiledBG）",
		"无" if (tiled == null or tiled.texture == null) else "%dx%d" % [tiled.texture.get_width(), tiled.texture.get_height()])
	var decal: Sprite2D = null if ground == null else ground.get_node_or_null("CenterDecal") as Sprite2D
	_check(decal != null and decal.texture != null and decal.texture.get_width() == 720,
		"中心阵眼只画一次（720² 贴花）",
		"无" if (decal == null or decal.texture == null) else str(decal.texture.get_width()))
	var hud: Node = arena.get_node_or_null("HUD")
	_check(hud != null and hud.get_node_or_null("ArenaGrade") != null,
		"试炼灯光分级已挂上")
	_check(ground != null and ground.get_node_or_null("EdgeFog") != null,
		"边界雾跟随试炼暗角色")

	# ⚠ 同一个场景上关掉肉鸽再重跑一次：验证主模式映射没被污染。
	#   用 free() 而不是 queue_free() 的场合是「测多轮节点」，这里只是重跑函数，
	#   所以不用拆场景；remove_child 是立即生效的，读节点不会拿到旧引用。
	RogueRun.restore()
	GameState.battle_context = {"boss_id": "boss_huyao"}
	arena.call("_setup_ground_bg")
	_check(String(arena.get("ground_visual_id")) == "bg_huyao_arena",
		"关掉肉鸽后回到原来的 BOSS→战场映射", String(arena.get("ground_visual_id")))
	_check(ground.get_node_or_null("CenterDecal") == null,
		"主模式不会多出试炼阵眼")

	arena.free()
