extends Node
## 虎妖纸本水墨卡：单张静态原画、纸本标签、卡包展开与单卡页。
## 用法：godot --path . --windowed --resolution 1600x900 tools/probe_huyao_ink.tscn -- --no-save

var _fails := 0
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails += 1
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var watchdog := get_tree().create_timer(20.0, true, false, true)
	watchdog.timeout.connect(func() -> void:
		print("FAIL watchdog timeout")
		get_tree().quit(2))

	CharacterData.tower_progress[1] = {
		"unlocked": true, "first_kill": true, "clear_count": 12,
	}
	CharacterData.tower_best_time[1] = 9.0
	CharacterData.tower_no_hit_double[1] = true
	CodexDB.set_card_order("boss_huyao", ["scene", "portrait", "plain", "ink"])
	var entry := CodexDB.card_entry("boss_huyao")
	var ids := _variant_ids(entry)
	_check(ids == ["scene", "portrait", "plain", "ink"], "虎妖四张卡齐全", str(ids))

	var ink_style: Dictionary = {}
	for raw in (entry.get("card_variants", []) as Array):
		if String((raw as Dictionary).get("id", "")) == "ink":
			ink_style = raw as Dictionary
			break
	_check(String(ink_style.get("kind", "")) == "still"
		and String(ink_style.get("label", "")) == "水墨 · 纸本"
		and bool(ink_style.get("unlocked", false)),
		"纸本水墨：静态 / 10 秒速通解锁",
		"%s / %s" % [ink_style.get("kind", ""), ink_style.get("label", "")])
	_check(not ink_style.has("flow") and not ink_style.has("guard")
		and String(ink_style.get("fx", "")) == "paper"
		and String(ink_style.get("hint", "")) == "纸本水墨 · 墨迹流动 · 滑动微倾 · 晃动出水痕",
		"纸本交互开启，走新纸本管线", String(ink_style.get("hint", "")))
	var reveal_path := String(ink_style.get("reveal", ""))
	_check(reveal_path.ends_with("boss_huyao_ink_reveal.png")
		and ResourceLoader.exists(reveal_path), "落墨顺序图已接", reveal_path)
	var flow_path := String(ink_style.get("flow_tex", ""))
	var guard_path := String(ink_style.get("guard_tex", ""))
	_check(flow_path.ends_with("boss_huyao_ink_flow.png") and ResourceLoader.exists(flow_path)
		and guard_path.ends_with("boss_huyao_ink_guard.png") and ResourceLoader.exists(guard_path),
		"笔势方向图 / 保护区已接", "%s / %s" % [flow_path, guard_path])
	var tex := load(String(ink_style.get("art", ""))) as Texture2D
	_check(tex != null and tex.get_size() == Vector2(640.0, 960.0),
		"新原画 640×960", str(tex.get_size()) if tex != null else "missing")

	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var view: AchievementView = panel._view
	view.open_boss("boss_huyao")
	await get_tree().create_timer(0.7, true, false, true).timeout
	_check(view.find_children("CardSlot*", "Control", true, false).size() == 4,
		"展开页四张卡")

	view.open_card(3)
	await get_tree().create_timer(0.6, true, false, true).timeout
	var face := view.find_child("CardSingle", true, false) as CardFace
	_check(face != null and face.kind() == "still",
		"单卡页是静态纸本", face.kind() if face != null else "missing")
	if face != null:
		_check(face.holo_view() == null and face.is_paper(), "纸本卡没有旧墨流控件")
		var mat := face.get("_still_mat") as ShaderMaterial
		_check(mat != null and mat.shader != null
			and String(mat.shader.resource_path).ends_with("ink_paper.gdshader"),
			"纸本交互着色器", mat.shader.resource_path if mat != null and mat.shader != null else "null")
		_check(mat != null and mat.get_shader_parameter("flow_tex") != null
			and mat.get_shader_parameter("guard_tex") != null,
			"纸本流转 uniform 已下发",
			"flow=%s guard=%s" % [
				str(mat.get_shader_parameter("flow_tex")) if mat != null else "null",
				str(mat.get_shader_parameter("guard_tex")) if mat != null else "null"])
		face.set_paper_interactive(false)
		for r in [0.30, 0.65, 1.0]:
			face.set_paper_reveal_immediate(r)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"output/huyao_ink_reveal_%03d.png" % int(r * 100))
		face.set_paper_interactive(true)
		await get_tree().process_frame
		var xf := get_viewport().get_final_transform() * face.get_global_transform_with_canvas()
		var screen := xf * (face.size * Vector2(0.80, 0.48))
		var mm := InputEventMouseMotion.new()
		mm.position = screen
		mm.global_position = screen
		mm.relative = Vector2(35.0, 2.0)
		get_viewport().push_input(mm)
		await get_tree().process_frame
		_check(face._paper_tilt_target.x > 0.3 and face._paper_ripple_strength > 0.5,
			"真实鼠标移动触发倾斜与墨环",
			"tilt=%s ripple=%.2f" % [str(face._paper_tilt_target),
				face._paper_ripple_strength])
		var mat2 := face.get("_still_mat") as ShaderMaterial
		_check(mat2 != null and absf(float(mat2.get_shader_parameter("ripple_strength")) - 1.0) < 0.01,
			"墨环 uniform 已下发",
			"str=%s age=%s center=%s" % [str(mat2.get_shader_parameter("ripple_strength")),
				str(mat2.get_shader_parameter("ripple_age")),
				str(mat2.get_shader_parameter("ripple_center"))] if mat2 != null else "null")
		await get_tree().create_timer(0.18, true, false, true).timeout
		_check(absf(face.rotation) > 0.005, "卡面倾斜实际生效",
			"rot=%.3f" % face.rotation)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/huyao_ink_tilt_ripple.png")
		# 冻结三道波前，给验收看墨环本身
		face.set_process(false)
		face.rotation = 0.0
		for age in [0.06, 0.16, 0.30]:
			face._paper_ripple_age = age
			face._paper_ripple_strength = 1.0
			face._sync_paper()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var shot := get_viewport().get_texture().get_image()
			shot.save_png("output/huyao_ink_ripple_%03d.png" % int(age * 100))
			if is_equal_approx(age, 0.16):
				shot.save_png("output/huyao_ink_ripple_only.png")
		face.set_paper_interactive(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_static_probe.png")
	# 常驻水墨流转：交互关掉后仍由 TIME 驱动，隔 1.4s 抓两张给验收
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_flow_a.png")
	await get_tree().create_timer(1.4, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_flow_b.png")
	await get_tree().create_timer(1.4, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_flow_c.png")
	await get_tree().create_timer(1.4, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_flow_d.png")
	# 补四帧，拼 0.7s 间隔的循环 GIF
	await get_tree().create_timer(0.7, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_flow_e.png")
	await get_tree().create_timer(0.7, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_flow_f.png")
	await get_tree().create_timer(0.7, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_flow_g.png")
	await get_tree().create_timer(0.7, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/huyao_ink_flow_h.png")

	# 展开页：纸本卡也要落墨、流转、晃出墨环、能微倾
	view.back()
	await get_tree().create_timer(0.8, true, false, true).timeout
	var spread := view.find_child("CardSpread3", true, false) as CardFace
	var spread_reveal := 1.0
	if spread != null:
		var spread_mat := spread.get("_still_mat") as ShaderMaterial
		if spread_mat != null:
			spread_reveal = float(spread_mat.get_shader_parameter("reveal"))
	_check(spread != null and spread.is_paper() and spread._paper_interactive
		and spread.is_processing() and spread._paper_tilt_enabled and spread_reveal < 0.99,
		"展开页落墨 / 流转 / 微倾 / 墨环全开",
		"reveal=%.2f proc=%s tilt=%s" % [
			spread_reveal,
			str(spread != null and spread.is_processing()),
			str(spread != null and spread._paper_tilt_enabled)])
	if spread != null:
		spread.play_paper_reveal(1.5)
		await get_tree().create_timer(0.5, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/huyao_ink_spread_reveal.png")
		spread.set_paper_reveal_immediate(1.0)
		var sp := _screen_point(spread, Vector2(0.45, 0.55))
		var sm := InputEventMouseMotion.new()
		sm.position = sp
		sm.global_position = sp
		sm.relative = Vector2(32.0, 0.0)
		get_viewport().push_input(sm)
		await get_tree().process_frame
		_check(spread._paper_ripple_strength > 0.5, "展开页真实鼠标晃动出墨环",
			"ripple=%.2f tilt=%s" % [spread._paper_ripple_strength,
				str(spread._paper_tilt_target)])
		await get_tree().create_timer(0.2, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/huyao_ink_spread_ripple.png")
		await get_tree().create_timer(1.4, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/huyao_ink_spread_clean.png")
		# 纸本卡开了输入后，仍要能被真实鼠标拖到别的卡位（点击/拖动走视图级 _input）
		var ink_slot: Control = view._spread_slots.get("ink", null)
		var scene_slot: Control = view._spread_slots.get("scene", null)
		if ink_slot != null and scene_slot != null:
			var p1 := _screen_point(ink_slot, Vector2(0.2, 0.5))
			var p2 := _screen_point(scene_slot, Vector2(0.5, 0.5))
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			down.position = p1
			down.global_position = p1
			get_viewport().push_input(down)
			await get_tree().process_frame
			var move2 := InputEventMouseMotion.new()
			move2.position = p2
			move2.global_position = p2
			move2.relative = p2 - p1
			get_viewport().push_input(move2)
			await get_tree().process_frame
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_LEFT
			up.pressed = false
			up.position = p2
			up.global_position = p2
			get_viewport().push_input(up)
			await get_tree().create_timer(0.5, true, false, true).timeout
			_check(String(view._spread_ids[0]) == "ink",
				"纸本卡可真实拖动换位", str(view._spread_ids))

	# 收藏册封面：水墨排第一才当封面；格子裁切，只吃墨环不倾斜
	CodexDB.set_card_order("boss_huyao", ["ink", "scene", "portrait", "plain"])
	view.back()
	await get_tree().create_timer(0.8, true, false, true).timeout
	var cover: CardFace = null
	for n in view.find_children("*", "CardFace", true, false):
		var cf := n as CardFace
		if cf != null and cf.is_paper():
			cover = cf
			break
	var cover_reveal := 1.0
	var cover_scale := 0.0
	if cover != null:
		cover_scale = cover._paper_tilt_scale
		var cover_mat := cover.get("_still_mat") as ShaderMaterial
		if cover_mat != null:
			cover_reveal = float(cover_mat.get_shader_parameter("reveal"))
	_check(cover != null and cover._paper_interactive and cover._paper_tilt_enabled
		and cover_scale < 0.6 and cover_reveal < 0.99,
		"收藏封面落墨 / 流转 / 微倾 / 墨环全开",
		"reveal=%.2f tilt=%s scale=%.2f" % [cover_reveal,
			str(cover != null and cover._paper_tilt_enabled), cover_scale])
	if cover != null:
		cover.play_paper_reveal(1.4)
		await get_tree().create_timer(0.45, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/huyao_ink_cover_reveal.png")
		cover.set_paper_reveal_immediate(1.0)
		var cp := _screen_point(cover, Vector2(0.55, 0.55))
		var cm := InputEventMouseMotion.new()
		cm.position = cp
		cm.global_position = cp
		cm.relative = Vector2(-32.0, 0.0)
		get_viewport().push_input(cm)
		await get_tree().process_frame
		_check(cover._paper_ripple_strength > 0.5, "收藏封面真实鼠标晃动出墨环",
			"ripple=%.2f" % cover._paper_ripple_strength)
		await get_tree().create_timer(0.2, true, false, true).timeout
		_check(absf(cover.rotation) > 0.001, "收藏封面微倾实际生效",
			"rot=%.4f scale=%.2f" % [cover.rotation, cover._paper_tilt_scale])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/huyao_ink_cover_ripple.png")
		# 靠到封面右上角，确认格子裁切下 0.5 倍倾斜仍不出界
		var ce := _screen_point(cover, Vector2(0.95, 0.10))
		var cm2 := InputEventMouseMotion.new()
		cm2.position = ce
		cm2.global_position = ce
		cm2.relative = Vector2(30.0, 0.0)
		get_viewport().push_input(cm2)
		await get_tree().create_timer(0.25, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/huyao_ink_cover_tilt.png")
		await get_tree().create_timer(1.4, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/huyao_ink_cover_clean.png")

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _variant_ids(entry: Dictionary) -> Array:
	var out: Array = []
	for raw in CodexDB.ordered_variants(entry):
		out.append(String((raw as Dictionary).get("id", "")))
	return out


func _screen_point(ctrl: Control, at: Vector2) -> Vector2:
	var xf := get_viewport().get_final_transform() * ctrl.get_global_transform_with_canvas()
	return xf * (ctrl.size * at)
