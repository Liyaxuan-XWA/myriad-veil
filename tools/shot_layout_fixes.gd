extends Node
## 2026-11-02 五条修改的出图工具：主城设施站位 / 记忆幻像碑封锁 / 农田与掉落物层序
## 用法：godot --path . --resolution 1280x720 tools/shot_layout_fixes.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _mat_shot(id: String, n: String, c: int) -> Dictionary:
	var def := ItemDB.get_material(id)
	return {"id": id, "name": n, "type": "material", "count": c,
		"icon": String(def.get("icon", ""))}


func _ready() -> void:
	print("\n########## 布局修图 ##########")

	# ===== 四区材料品质档：白 / 蓝 / 紫 / 橙 一眼对比 =====
	CharacterData.inventory = [
		_mat_shot("mat_xuecao", "青岚血参", 1),
		_mat_shot("mat_zj_xuecao", "云隐血参", 1),
		_mat_shot("mat_jd_xuecao", "赤金血参", 1),
		_mat_shot("mat_yy_xuecao", "幽冥血参", 1),
		_mat_shot("mat_yy_ruishoupi", "幽冥锐兽皮", 1),
		_mat_shot("mat_pojing_di_zhuji", "筑基底髓", 1),
		_mat_shot("mat_pojing_zhuji", "筑基破境晶", 1),
		_mat_shot("mat_pojing_jiedan", "结丹破境晶", 1),
		_mat_shot("mat_pojing_yuanying", "元婴破境晶", 1),
		_mat_shot("mat_pojing_huashen", "化神破境晶", 1),
	]
	CharacterPanel._on_filter_pressed(CharacterData.ITEM_MATERIAL, null)
	CharacterPanel.open_panel()
	await _settle(0.8)
	await _shot("material_rarity_ladder.png")
	CharacterPanel.close_panel()
	await _settle(0.3)

	# ===== 主城：设施站位 + 封锁 =====
	var city = (load("res://scenes/main/primordial_realm.tscn") as PackedScene).instantiate()
	add_child(city)
	await _settle(1.2)
	await _shot("city_spawn_view.png")

	var player := city.get_node("Player") as Node2D
	# 走到被封锁的记忆幻像碑旁边（设施在 (0,420)）
	player.position = Vector2(0, 300)
	await _settle(1.4)
	await _shot("city_memory_locked.png")
	city.queue_free()
	await _settle(0.3)

	# ===== 大世界：农田上掉东西 + 怪站在田里 =====
	CharacterData.secret_world["core_kills"] = {}
	CharacterData.tilled_plots.clear()
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await _settle(0.6)
	CharacterData.secret_world["core_kills"][SecretWorldDB.REGION_ZHUJI] = true
	w._spawn_due_content()
	var plot: FarmPlot = null
	for raw in w._resources.values():
		if raw is FarmPlot and String((raw as FarmPlot).region_id) == SecretWorldDB.REGION_ZHUJI:
			plot = raw as FarmPlot
			break
	if plot == null:
		print("NOFARM")
		get_tree().quit(1)
		return
	CharacterData.till_plot(plot.state_index())
	CharacterData.plant_plot(plot.state_index(), "mat_zj_xuecao", 60)

	# 旁边那块田里站一只怪：验证田不再盖住单位
	var beasts: Array = []
	for raw in w._enemies.values():
		if raw is Node2D:
			beasts.append(raw)
	if not beasts.is_empty():
		(beasts[0] as Node2D).position = plot.global_position + Vector2(0, -6)
		(beasts[0] as Node2D).set_physics_process(false)

	# 玩家先站到田上并等物理落位，再把掉落物放到玩家脚下
	# （世界会在头几帧自己挪一次出生点，反过来做会差出拾取半径那几像素）
	w.player.global_position = plot.global_position + Vector2(0, 6)
	await _settle(0.8)
	var def := ItemDB.get_material("mat_zj_lanyingcao")
	w._spawn_drop_item({"id": "mat_zj_lanyingcao", "name": String(def.get("name", "")),
		"type": "material", "count": 2, "icon": String(def.get("icon", ""))},
		w.player.global_position)
	await _settle(1.0)
	await _shot("farm_drop_and_beast.png")

	print("PLOT z=", plot.z_index, " beast z=",
		"" if beasts.is_empty() else str((beasts[0] as Node2D).z_index),
		" drop z=", (w._drops.back() as Node2D).z_index,
		" prompt visible=", w._prompt_bg.visible if w._prompt_bg != null else "n/a")
	var dp: Area2D = w._drops.back()
	print("DIAG inside=", dp.call("has_player_inside"),
		" drop=", dp.global_position, " player=", w.player.global_position,
		" d=", dp.global_position.distance_to(w.player.global_position),
		" monitoring=", dp.monitoring, " mask=", dp.collision_mask,
		" player_layer=", w.player.collision_layer)
	get_tree().quit(0)
