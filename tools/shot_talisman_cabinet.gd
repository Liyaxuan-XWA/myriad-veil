extends Node
## 符匣全屏页实景截图（wip）
## 用法：godot --path . --resolution 1280x720 res://tools/shot_talisman_cabinet.tscn -- --no-save

func _ready() -> void:
	CharacterData.current_realm = "筑基"
	CharacterData.realm_exp = 5000.0
	for hide_id in ["mat_ruishoupi", "mat_jianshoupi", "mat_zj_ruishoupi", "mat_zj_jianshoupi",
			"mat_yy_ruishoupi", "mat_yy_jianshoupi"]:
		CharacterData.add_item({
			"id": hide_id, "type": "material", "count": 20,
		})
	for q in ["lianqi", "zhuji", "jiedan", "yuanying"]:
		for base in ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling",
				"tal_shuihui", "tal_fengji", "tal_tushi"]:
			CharacterData.add_item({
				"id": "%s_%s" % [base, q], "name": base, "type": "talisman",
				"count": 3, "icon": "res://assets/ui/icon/tal_element_fire.png",
			})

	var sp = load("res://scripts/ui/panels/skill_panel.gd").new()
	add_child(sp)
	await get_tree().process_frame
	await get_tree().process_frame
	sp.open()
	await get_tree().process_frame
	CharacterData.active_skill_loadout = ["talisman:tal_huoqiu_lianqi", "", "", ""]
	sp._refresh_content()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/skill_panel_talisman.png")
	print("SHOT output/skill_panel_talisman.png")
	sp._open_cabinet(-1)
	await get_tree().process_frame
	await get_tree().process_frame
	if sp._cabinet != null and is_instance_valid(sp._cabinet) \
			and sp._cabinet._card_views.size() > 0:
		var v0 = sp._cabinet._card_views[0]
		v0.picked.emit(v0.item_id)
		print("PICK ", sp._cabinet._selected_id == v0.item_id)
	if sp._cabinet != null and is_instance_valid(sp._cabinet):
		sp._cabinet._set_quality(1)
		sp._cabinet._select("tal_huoqiu_zhuji")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("output/talisman_cabinet.png")
	print("SHOT output/talisman_cabinet.png")
	if sp._cabinet != null and is_instance_valid(sp._cabinet) \
			and sp._cabinet._card_views.size() > 3:
		sp._cabinet._card_views[3]._on_mouse_entered()
		await get_tree().create_timer(0.22).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/talisman_cabinet_hover.png")
		print("SHOT output/talisman_cabinet_hover.png")
		sp._cabinet._card_views[3]._on_mouse_exited()
	if sp._cabinet != null and is_instance_valid(sp._cabinet):
		sp._cabinet._set_quality(3)
		sp._cabinet._select("tal_huoqiu_yuanying")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/talisman_cabinet_yuanying.png")
	print("SHOT output/talisman_cabinet_yuanying.png")
	if sp._cabinet != null and is_instance_valid(sp._cabinet):
		var rec := ItemDB.get_talisman_recipe("recipe_tal_huoqiu_zhuji")
		sp._cabinet._open_brush(rec)
		await get_tree().process_frame
		await get_tree().process_frame
		sp._cabinet._set_brush_batch(5)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/talisman_brush.png")
		print("SHOT output/talisman_brush.png")
		sp._cabinet._finish_brush()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("output/talisman_brush_result.png")
		print("SHOT output/talisman_brush_result.png")
	get_tree().quit()
