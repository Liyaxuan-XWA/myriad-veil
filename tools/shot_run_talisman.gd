extends Node
## 试炼符箓（四符连携）实景截图（2026-11-10 重做）
## 出图：结符页 / 换符页 / 战斗（技能栏 + 连携飘字）/ 符阵 · 雷狱 / 符灵 · 青藤
## 用法：godot --path . --resolution 1280x720 res://tools/shot_run_talisman.tscn -- --no-save
##
## ⚠ 必须窗口模式跑：--headless 没有绘制，截出来是空图。
## ⚠ 一律带 `-- --no-save`：本脚本会真的 start_run，不带参数会写进存档。

const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const MINION_SCENE := "res://scenes/world/world_enemy.tscn"

var _arena: Node = null
var _player: Node2D = null


func _shot(name: String) -> void:
	# ⚠ Input.warp_mouse 在这种非交互式运行里不生效（窗口没真焦点），鼠标坐标一直是
	#   屏幕中心偏下 —— 正好压在技能栏上，tooltip 会一直弹着挡住底部。直接关掉 GUI 输入。
	get_viewport().gui_disable_input = true
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	await _run()
	get_tree().quit()


func _run() -> void:
	# ===== ① 结符页 =====
	var page = load("res://scripts/ui/talisman_loadout_page.gd").new()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("run_tal_loadout_empty.png")
	for id in ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"]:
		page.call("_on_card_picked", id)
	await get_tree().process_frame
	await _shot("run_tal_loadout_picked.png")
	page.queue_free()
	await get_tree().process_frame

	# ===== ② 换符页 =====
	RogueRun.start_run("talisman", ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"])
	RogueRun.add_buff("t_recipe_ice")
	RogueRun.add_buff("t_recipe_light")
	await get_tree().process_frame
	var swap = load("res://scripts/ui/talisman_swap_page.gd").new()
	add_child(swap)
	await get_tree().process_frame
	swap.open()
	await get_tree().process_frame
	await _shot("run_tal_swap.png")
	swap.close()
	await get_tree().process_frame

	# ===== ③ 战斗场景 =====
	RogueRun.restore()
	RogueRun.start_run("talisman", ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"])
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	BattleResolver.skip_next_intro = true
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(_arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _arena.get("player") as Node2D
	var rogue: Node = _arena.get("_rogue")
	if _player == null:
		print("!! 战斗场景没建出来")
		return
	# 关掉试炼推进：截图期间不要自动进下一波 / 弹三选一
	rogue.set_process(false)
	rogue.set_physics_process(false)
	# 关掉新手指引（否则第一张图会被「左键攻击，先打三下」挡住）
	# ⚠ 不能 free overlay：runner 后面还会 .call() 它，只能藏起来
	Tutorial.active_chapter = ""
	Tutorial.active_step = {}
	Tutorial.set("_queued_chapter", "")
	# ⚠ overlay 是 CanvasLayer（不是 CanvasItem），用 CanvasItem 判会静默失效
	var ov := Tutorial.get("_overlay") as CanvasLayer
	if ov != null:
		ov.visible = false
	# 截图期间关掉 GUI 输入：否则鼠标「停」在技能栏上会一直弹 tooltip
	get_viewport().gui_disable_input = true
	_player.set("invincible_timer", 99999.0)
	_player.set("mana", 100.0)
	_player.set("max_mana", 100.0)
	for off in [Vector2(-150.0, -40.0), Vector2(150.0, 30.0), Vector2(0.0, -140.0)]:
		_make_dummy(_player.global_position + off)
	# ⚠ 开场横幅（「试炼之路 · 第 1 层 / 第 1 波」）要 2 秒多才淡出，等它走完再截
	await _wait_ms(2600)

	# 2b 实机换符页：⚠ 必须在**战斗场景里**拍。② 那张是干净树截图，
	#   树里没有 Node2D 地面也没有 Camera2D，裸 Control 挂 root 看起来也居中 ——
	#   正是这个差异让用户报的「面板固定在地上」在旧截图里一直看不出来。
	#   这里和 rogue_arena._open_talisman_swap() 用同一挂法（root.add_child）。
	var swap_live = load("res://scripts/ui/talisman_swap_page.gd").new()
	get_tree().root.add_child(swap_live)
	await get_tree().process_frame
	swap_live.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("run_tal_swap_live.png")
	swap_live.close()
	await get_tree().process_frame

	# 3.0 施符瞬间：手里那张符浮起来（0.11 秒后才碎裂，所以要快）
	_clear_cd()
	_player.set("mana", 100.0)
	_player.call("use_run_talisman", "tal_jinfeng")
	await _wait_ms(55)
	await _shot("run_tal_fx_cast.png")
	await _wait_ms(420)

	# 3.1 四符连携：放金锋，飘字 + 随机连携另一张
	# ⚠ 3.0 刚放过金锋，这里必须先清冷却，否则 use_run_talisman 直接 false
	_clear_cd()
	_player.set("mana", 100.0)
	_player.call("use_run_talisman", "tal_jinfeng")
	await _wait_ms(120)
	await _shot("run_tal_cast_chain.png")

	# 3.2 符阵 · 雷狱
	RogueRun.talisman_set_variant("tal_yinlei", "talv_yinlei_prison")
	_clear_cd()
	_player.set("mana", 100.0)
	_player.call("use_run_talisman", "tal_yinlei")
	await _wait_ms(260)
	await _shot("run_tal_zone_prison.png")

	# 3.3 符灵 · 青藤（站到符灵旁边，让符纸在画面里）
	RogueRun.talisman_set_variant("tal_muling", "talv_muling_spirit")
	_clear_cd()
	_player.set("mana", 100.0)
	_player.call("use_run_talisman", "tal_muling")
	await _wait_ms(200)
	await _shot("run_tal_spirit_ivy.png")

	# 3.4 三档品质：技能栏的品阶首字与冷却遮罩
	for id in ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling"]:
		RogueRun.tal_tier[id] = 3
	_clear_cd()
	_player.set("mana", 100.0)
	_player.call("use_run_talisman", "tal_huoqiu")
	await _wait_ms(160)
	await _shot("run_tal_skill_bar_tier3.png")

	# 3.5 自身增益：石甲绕身环（土黄圈贴地）
	# ⚠ 土符不在开局四符里（开局是金/火/雷/木），不换进主槽的话
	#   use_run_talisman 会直接返回 false —— 什么都放不出来，也没有报错。
	await _clear_summons()
	# ⚠ 三条都得写：`use_run_talisman` 认的是 `talisman_owned()`（查 tal_tier），
	#   不是 tal_main。只往主槽塞符、不写品阶表的话它直接返回 false，且不报错。
	RogueRun.tal_tier["tal_tushi"] = 0
	RogueRun.tal_main[3] = "tal_tushi"
	_clear_cd()
	_player.set("mana", 100.0)
	_player.call("use_run_talisman", "tal_tushi")
	await _wait_ms(260)
	await _shot("run_tal_fx_shell.png")
	await _wait_ms(300)

	# 3.6 命中爆散：火球砸在木桩上的冲击环
	await _clear_summons()
	_clear_cd()
	_player.set("mana", 100.0)
	_player.call("use_run_talisman", "tal_huoqiu")
	await _wait_ms(150)
	await _shot("run_tal_fx_impact.png")

	RogueRun.restore()


func _make_dummy(pos: Vector2) -> void:
	var packed := load(MINION_SCENE) as PackedScene
	var e := packed.instantiate() as WorldEnemy
	e.configure({
		"pos": pos, "max_hp": 1000000.0, "attack_power": 1.0, "move_speed": 0.0,
		"visual_id": "rogue_rat", "aggro_range": 1.0, "leash_range": 1.0,
		"melee_range": 1.0, "melee_angle": 1.0, "melee_coeff": 0.0,
		"body_radius": 20.0, "attack_name": "不动", "skills": [], "cast_coeff": 0.0,
	}, WorldEnemy.KIND_BEAST, "木桩")
	if not e.is_in_group("boss"):
		e.add_to_group("boss")
	_arena.add_child(e)
	e.global_position = pos


## 清掉上一轮留下的符阵 / 符灵：它们会活 8 秒，不清就一直叠在后面的图里
func _clear_summons() -> void:
	for n in get_tree().get_nodes_in_group("talisman_zone"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("talisman_spirit"):
		n.queue_free()
	await get_tree().process_frame


func _clear_cd() -> void:
	var ready: Dictionary = _player.get("_run_tal_ready")
	ready.clear()


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
