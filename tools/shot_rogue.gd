extends Node
## 试炼之路视觉验收截图（2026-11-08）
## 出三张：局内 HUD + 小怪占位 / 玉简三选一 / 结算卷轴
## 用法（⚠ 必须窗口模式，--headless 截不到图）：
##   godot --path . --resolution 1600x900 res://tools/shot_rogue.tscn -- --no-save

const OUT_DIR := "output"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))

	# ---- 铺一局有内容的试炼：带若干增益，第 3 层小关 2，看 HUD 是否压住别的 UI ----
	RogueRun.start_run()
	for id in ["s_wj_cap", "s_yj_dmg", "s_jq_pierce", "g_str", "g_hp", "s_yj_free"]:
		RogueRun.add_buff(id)
	RogueRun.floor_no = 3
	RogueRun.stage_no = 2
	RogueRun.wave_no = 2

	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 3}
	var arena := (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	var rogue: Node = arena.get("_rogue")
	if rogue == null:
		push_error("RogueArena 没建起来，检查 battle_context.source")
		get_tree().quit(1)
		return
	# 让玩家往前景站一点，小怪会绕着他刷
	var player: Node2D = arena.get("player")
	if player != null:
		player.global_position = Vector2(0.0, 80.0)
	# ⚠ 开场公告 / 关卡标题卡要 2 秒才散，等它走完再截，否则满屏大字压住 HUD
	for i in 170:
		await get_tree().process_frame
	await _snap("rogue_01_battle")

	# ---- BOSS 关：看血条 / 休眠解除 / 公告措辞 ----
	RogueRun.stage_no = RogueDB.STAGES_PER_FLOOR
	RogueRun.wave_no = 1
	rogue.set("_phase", 0)
	rogue.call("_start_stage")
	for i in 12:
		await get_tree().process_frame
	await _snap("rogue_02_boss")

	# ---- 玉简三选一 ----
	rogue.call("_open_pick", false)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await _snap("rogue_03_pick")
	var pick: Node = _find_root_panel("rogue_pick_panel")
	if pick != null:
		pick.call("close")
	get_tree().paused = false
	for i in 4:
		await get_tree().process_frame

	# ---- 结算卷轴（喂一份真实结构的结果，不碰角色数据）----
	var settle := RogueSettlePanel.new()
	settle.setup({
		"floor": 7, "boss_kills": 7, "crystals": 28,
		"best": 9, "new_best": false, "unlocked": ["yinyang"], "by_death": true,
	})
	get_tree().root.add_child(settle)
	for i in 4:
		await get_tree().process_frame
	settle.open()
	for i in 6:
		await get_tree().process_frame
	await _snap("rogue_04_settle")
	get_tree().quit()


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	img.save_png(path)
	print("SHOT ", path, "  ", img.get_width(), "x", img.get_height())


func _find_root_panel(cls_name: String) -> Node:
	for c in get_tree().root.get_children():
		if c.get_script() == null:
			continue
		var p := String((c.get_script() as Script).resource_path)
		if p.ends_with(cls_name + ".gd"):
			return c
	return null
