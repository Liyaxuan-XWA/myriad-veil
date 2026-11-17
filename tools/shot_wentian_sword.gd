extends Node2D
## 问天剑三件套的验收截图（**必须窗口化跑**，headless 抓不到已绘制帧）
##
## 用法：godot --path . --resolution 1280x720 res://tools/shot_wentian_sword.tscn -- --no-save
## 出图：
##   output/wentian_weapon_orbit.png   局内手持：清风剑（旧）/ 问天剑（新）并排，待机 + 挥击中
##   output/wentian_shrine_world.png   石台在练气区的实景（传送门正上方）
##   output/wentian_icon_panel.png     图标按面板尺寸摆的观感（256 原图 + 64 缩略）
##   output/wentian_pickup_announce.png 真按 F 拔剑那一刻的播报
##   output/wentian_run_bag_empty.png  局内行囊（按 B）里没有这把剑
##   output/wentian_in_main_bag.png    角色面板「装备」页签里有这把剑
##
## ⚠ 为什么一定要拍实景：贴图指标全绿（尺寸/包围盒/能加载）不等于在游戏里能看。
##   石台是 1024² 出图压到 target_length 150，落在 6000×4000 的草地上会不会糊成一团，
##   只有叠到真实地面上才看得出来。

const WORLD_SCENE := "res://scenes/world/secret_world.tscn"


func _ready() -> void:
	await _shot_orbit()
	await _shot_world()
	await _shot_landing()
	await _shot_icon()
	get_tree().quit(0)


## ① 局内手持：新旧并排，各拍一张待机与一张挥到一半
func _shot_orbit() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085, 1.0)
	bg.size = Vector2(1280.0, 720.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var pairs := [["清风剑（基准）", "weapon_qingfeng_jian"], ["问天剑（新）", "weapon_wentian_jian"]]
	var orbits: Array = []
	for i in pairs.size():
		var actor := Node2D.new()
		actor.position = Vector2(360.0 + 520.0 * float(i), 400.0)
		actor.scale = Vector2(2.2, 2.2)
		add_child(actor)
		var body := ColorRect.new()
		body.color = Color(0.22, 0.23, 0.26, 1.0)
		body.size = Vector2(26.0, 42.0)
		body.position = Vector2(-13.0, -38.0)
		actor.add_child(body)
		var orbit := WeaponOrbit.new()
		orbit.weapon_id = String(pairs[i][1])
		actor.add_child(orbit)
		orbit.refresh()
		orbits.append(orbit)
		var label := Label.new()
		label.text = String(pairs[i][0])
		label.position = Vector2(360.0 + 520.0 * float(i) - 140.0, 620.0)
		label.size = Vector2(280.0, 28.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		add_child(label)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/wentian_orbit_idle.png")
	for orbit in orbits:
		orbit.sweep(Vector2.RIGHT, {}, false)
	await get_tree().create_timer(0.10, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/wentian_weapon_orbit.png")
	print("SHOT wentian_orbit_idle / wentian_weapon_orbit")
	for c in get_children():
		remove_child(c)
		c.free()


## ② 大陆实景：把玩家放到石台旁边，让相机跟过去
func _shot_world() -> void:
	var w = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	var shrine = w.get("_resources").get("lq_sword_shrine")
	if shrine == null:
		print("[!] 场上没有石台，内容表或生成链没通")
		return
	var sp: Vector2 = shrine.global_position
	# 站在石台东南侧一点点：第一版偏 210 像素，石台被顶到屏幕最上沿、和顶部 HUD 挤在一起
	# —— 那是取景失误不是游戏问题，收到 140 才拍得下整件设施 + 下方的传送门做尺寸对照
	w.player.global_position = sp + Vector2(120.0, 140.0)
	w.call("_update_interaction")
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/wentian_shrine_world.png")
	print("SHOT wentian_shrine_world  石台世界坐标=", sp)
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## ③ 落点：真按 F 拔剑 → 局内行囊没有 → 角色面板「装备」页签里有
##    用户 2026-11-12 定「拔了直接到主背包，不是临时背包」，这三张就是给这条看的
func _shot_landing() -> void:
	# 现场：从没拔过（清掉 taken 标记）+ 身上干净（背包和穿戴槽都撤掉这把剑）
	var nodes = CharacterData.secret_world.get("nodes", {})
	if nodes is Dictionary:
		(nodes as Dictionary).erase("lq_sword_shrine")
	_strip_sword()
	var w = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	var shrine = w.get("_resources").get("lq_sword_shrine")
	if shrine == null:
		print("[!] 场上没有石台，内容表或生成链没通")
		return
	w.player.global_position = shrine.global_position + Vector2(48.0, 36.0)
	w.call("_update_interaction")
	w.call("_on_interact")
	await get_tree().create_timer(0.35).timeout
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/wentian_pickup_announce.png")
	print("SHOT wentian_pickup_announce  局内行囊 %d 件 / 主背包问天剑 %d 件" % [
		(w.get("_run_items") as Array).size(), _sword_in_bag()])
	# 按 B：局内行囊里不该有它
	w.call("_toggle_run_bag")
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/wentian_run_bag_empty.png")
	w.call("_toggle_run_bag")
	await get_tree().create_timer(0.2).timeout
	# Tab：角色面板 → 点真实的「装备」页签按钮
	CharacterPanel.open_panel()
	await get_tree().create_timer(0.3).timeout
	_press_filter("equipment")
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/wentian_in_main_bag.png")
	print("SHOT wentian_in_main_bag  问天剑在主背包=%d 件" % _sword_in_bag())
	CharacterPanel.close_panel()
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _strip_sword() -> void:
	for i in range(CharacterData.inventory.size() - 1, -1, -1):
		if String((CharacterData.inventory[i] as Dictionary).get("id", "")) == "eq_wentian_jian":
			CharacterData.inventory.remove_at(i)
	for slot in CharacterData.equipment_slots.keys():
		var it = CharacterData.equipment_slots[slot]
		if it is Dictionary and String((it as Dictionary).get("id", "")) == "eq_wentian_jian":
			CharacterData.equipment_slots[slot] = null


func _sword_in_bag() -> int:
	var n := 0
	for raw in CharacterData.inventory:
		if String((raw as Dictionary).get("id", "")) == "eq_wentian_jian":
			n += 1
	return n


## 走页签按钮的 pressed，不直接改 _filter：这样拍出来的是玩家真点出来的那一屏
func _press_filter(filter: String) -> void:
	for entry in CharacterPanel.get("_filter_buttons"):
		if String(entry[1]) == filter:
			(entry[0] as Button).pressed.emit()
			return
	push_warning("没找到页签按钮：%s" % filter)


## ④ 图标：原图 + 面板里实际会用的两种尺寸，合成到深色底上看边缘
func _shot_icon() -> void:
	var src := load("res://assets/ui/icon/equip_wentianjian.png") as Texture2D
	if src == null:
		print("[!] 图标加载失败")
		return
	var canvas := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.09, 0.10, 0.12, 1.0))
	var img := src.get_image()
	img.convert(Image.FORMAT_RGBA8)
	# 256 原样、64 格子里的尺寸、40 详情头图尺寸 —— 三档一起看
	_blit_scaled(canvas, img, 40, 60, 256)
	_blit_scaled(canvas, img, 340, 120, 64)
	_blit_scaled(canvas, img, 700, 220, 40)
	var view := ColorRect.new()
	view.size = Vector2(1280.0, 720.0)
	add_child(view)
	await get_tree().process_frame
	canvas.save_png("output/wentian_icon_panel.png")
	print("SHOT wentian_icon_panel （从左到右：256 / 64 / 40）")
	view.queue_free()


func _blit_scaled(dst: Image, src: Image, x: int, y: int, size: int) -> void:
	var scaled := src.duplicate()
	scaled.resize(size, size, Image.INTERPOLATE_LANCZOS)
	dst.blend_rect(scaled, Rect2i(0, 0, size, size), Vector2i(x, y))
