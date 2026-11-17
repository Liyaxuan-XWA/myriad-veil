extends Node
## 练气区美术截图（2026-10-28）
## 用法（窗口模式，不能用 --headless，否则拿不到画面）：
##   godot --path . --windowed --resolution 1600x900 res://tools/shot_lianqi_art.tscn
## 输出：output/lianqi_world_art.png / lianqi_fx_*.png / lianqi_codex.png

const OUT := "output/"

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name)
	print("SHOT ", OUT + name, "  ", img.get_width(), "x", img.get_height())


func _ready() -> void:
	SecretWorldDB.pending_spawn_region = SecretWorldDB.REGION_LIANQI
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4, true, false, true).timeout

	var core: WorldEnemy = w._enemies.get("lianqi_core_boss")
	var feng: WorldEnemy = w._enemies.get("lq_beast_feng_1")
	var jian: WorldEnemy = w._enemies.get("lq_beast_jian_1")
	if core == null or feng == null or jian == null:
		push_error("缺实体 core/feng/jian")
		get_tree().quit(1)
		return

	# 排一排看比例：玩家在左，灵兽在中，古猿在右。全部停掉 AI，免得摆拍时追人。
	var base: Vector2 = core.global_position
	w.player.global_position = base + Vector2(-300.0, 40.0)
	feng.global_position = base + Vector2(-150.0, 80.0)
	jian.global_position = base + Vector2(-40.0, 130.0)
	core.global_position = base + Vector2(120.0, 0.0)
	for e in [feng, jian, core]:
		var en := e as WorldEnemy
		en.set_physics_process(false)
		en.call("_face_dir", Vector2.LEFT)
		en.velocity = Vector2.ZERO
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _shot("lianqi_world_art.png")

	# 古猿平A（近战扇面）
	core.call("_face_dir", Vector2.LEFT)
	core.call("_do_melee")
	await get_tree().create_timer(0.10, true, false, true).timeout
	await _shot("lianqi_fx_melee.png")
	await get_tree().create_timer(0.8, true, false, true).timeout

	# 山崩地裂（二阶段大砸地）
	var quake: Dictionary = {}
	for raw in SecretWorldDB.CORE_SKILLS:
		if String((raw as Dictionary).get("id", "")) == "ape_quake":
			quake = raw
	if not quake.is_empty():
		var form := MoveDB.resolve_boss(String(quake.get("form_id", "")))
		core._play_form(form, 1.0, String(quake.get("attack_kind", "")),
			String(quake.get("damage_element", "")),
			float(quake.get("range", -1.0)), float(quake.get("angle", -1.0)),
			String(quake.get("fx_id", "")))
		await get_tree().create_timer(0.12, true, false, true).timeout
		await _shot("lianqi_fx_quake.png")
		await get_tree().create_timer(0.8, true, false, true).timeout

	# 崩石投掷（投射物外观）
	var boulder: Dictionary = {}
	for raw in SecretWorldDB.CORE_SKILLS:
		if String((raw as Dictionary).get("id", "")) == "ape_boulder":
			boulder = raw
	if not boulder.is_empty():
		var form2 := MoveDB.resolve_boss(String(boulder.get("form_id", "")))
		core._play_form(form2, 1.0, String(boulder.get("attack_kind", "")),
			String(boulder.get("damage_element", "")),
			float(boulder.get("range", -1.0)), float(boulder.get("angle", -1.0)),
			String(boulder.get("fx_id", "")))
		await get_tree().create_timer(0.22, true, false, true).timeout
		await _shot("lianqi_fx_boulder.png")
		await get_tree().create_timer(0.8, true, false, true).timeout

	# 灵兽的专属近战（玩家站在判定外，只拍 FX）
	for pair in [["feng", feng], ["jian", jian]]:
		var tag := String(pair[0])
		var en := pair[1] as WorldEnemy
		en.call("_face_dir", Vector2.LEFT)
		w.player.global_position = en.global_position + Vector2(-150.0, 40.0)
		await get_tree().create_timer(0.3, true, false, true).timeout
		en.call("_do_melee")
		await get_tree().create_timer(0.10, true, false, true).timeout
		await _shot("lianqi_fx_beast_" + tag + ".png")
		await get_tree().create_timer(0.8, true, false, true).timeout

	w.queue_free()
	await get_tree().process_frame

	# 图鉴详情页：走真实的 CodexPanel（1000×660），不是自搭的大画布
	# 截图时临时当作已击杀，避免卡面被「未击败压暗」挡住看不清
	CharacterData.secret_world["core_kills"]["world_lianqi"] = true
	var panel := CodexPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	var view: CodexView = panel._view
	view._category_index = 0
	view._boss_detail_id = "world_core_lianqi"
	view._render_list()
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("lianqi_codex.png")
	# 列表页也拍一张：7 张卡 + 新卡的卡面裁切
	view._boss_detail_id = ""
	view._render_list()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("lianqi_codex_list.png")
	view._scroll.scroll_vertical = 100000
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("lianqi_codex_list_bottom.png")

	get_tree().paused = false
	get_tree().quit(0)
