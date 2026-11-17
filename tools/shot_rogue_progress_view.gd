extends Node
## 试炼之路 · 「三波怪之后到底有没有进下一小关」可视化验收（2026-11-08）
## 出三张图：小怪红血条特写 / 三选一 / 选完卡后的小关 2 开局
## 用法（⚠ 必须窗口模式，--headless 截不到图）：
##   godot --path . --resolution 1600x900 res://tools/shot_rogue_progress_view.tscn -- --no-save

const OUT_DIR := "output"
const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"

var arena: Node = null
var rogue: Node = null
var player: Node2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))

	RogueRun.start_run("sword")
	GameState.battle_context = {"source": BattleResolver.SOURCE_ROGUE, "floor": 1}
	arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	rogue = arena.get("_rogue")
	player = arena.get("player")
	if rogue == null or player == null:
		push_error("战斗场景没起来")
		get_tree().quit(1)
		return

	# 让玩家站定，小怪围过来，先拍一张血条对照（鼠 + 射手同框：以前射手是蓝的）
	player.global_position = Vector2(0.0, 120.0)
	for i in 150:
		await get_tree().process_frame
	await _snap("rogue_hp_bars")

	# 一路秒杀推进到第一次三选一
	for i in 400:
		var phase := int(rogue.get("_phase"))
		if phase == 3:
			break
		for e in (rogue.get("_alive") as Array):
			if is_instance_valid(e):
				(e as Node).call("take_damage", 9999999.0, player, "true", "none")
		await get_tree().process_frame
	print("HUD（三选一前）：", _hud_text())
	await _snap("rogue_stage_pick")

	# 走新版真实链路：等防误触冷却 → 点玉简「选中」→ 再按下方「确认选择」
	var panel: Node = rogue.get("_pick_panel")
	var picked_id := ""
	if panel != null and is_instance_valid(panel):
		await _wait_ms(400)
		var row: HBoxContainer = panel.get("_row")
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		if row != null and row.get_child_count() > 0:
			(row.get_child(0) as Control).emit_signal("gui_input", ev)
		await _wait_ms(340)
		await _snap("rogue_stage_pick_selected")
		var choices: Array = panel.get("choices")
		if not choices.is_empty():
			picked_id = String((choices[0] as Dictionary).get("id", ""))
		var btn: Button = panel.get("_confirm_btn")
		if btn != null and is_instance_valid(btn):
			btn.emit_signal("pressed")
	for i in 130:
		await get_tree().process_frame
	print("HUD（选卡后）：", _hud_text(), "　选了 ", picked_id)
	await _snap("rogue_stage_2")
	get_tree().quit()


func _hud_text() -> String:
	var info: Label = rogue.get("_info_label")
	var wave: Label = rogue.get("_wave_label")
	return "%s ｜ %s" % ["" if info == null else info.text, "" if wave == null else wave.text]


## ⚠ 三选一 open() 会暂停树，create_timer 会被一起冻住 → 用真实时钟轮询
func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	img.save_png(path)
	print("SHOT ", path, "  ", img.get_width(), "x", img.get_height())
