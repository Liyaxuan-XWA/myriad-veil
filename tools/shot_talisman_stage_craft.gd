extends Node
## 符台 → 元素符制符页截图
## 用法：godot --path . --resolution 1280x720 res://tools/shot_talisman_stage_craft.tscn -- --no-save

func _ready() -> void:
	for base in ["tal_jinfeng", "tal_huoqiu", "tal_yinlei", "tal_muling",
			"tal_shuihui", "tal_fengji", "tal_tushi"]:
		CharacterData.add_item({
			"id": "%s_lianqi" % base, "name": base, "type": "talisman",
			"count": 3, "icon": "res://assets/ui/icon/tal_element_fire.png",
		})
	var tp = load("res://scripts/ui/panels/talisman_panel.gd").new()
	add_child(tp)
	await get_tree().process_frame
	await get_tree().process_frame
	tp.open()
	await get_tree().process_frame
	if tp._elem_cabinet != null and is_instance_valid(tp._elem_cabinet):
		tp._elem_cabinet._select("tal_huoqiu_lianqi")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/talisman_stage_craft.png")
	print("SHOT output/talisman_stage_craft.png")
	get_tree().quit()
