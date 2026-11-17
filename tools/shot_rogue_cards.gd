extends Node
## 图鉴「试炼卡牌」卷截图（2026-11-09）
## 用法：godot --path . res://tools/shot_rogue_cards.tscn -- --no-save
## ⚠ 必须带 --no-save：这里会临时改 rogue_best_floor 让所有流派都显示为已解锁。

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _index_of(cid: String) -> int:
	for i in CodexDB.categories().size():
		if String((CodexDB.categories()[i] as Dictionary).get("id", "")) == cid:
			return i
	return 0


func _ready() -> void:
	# 截图看的是「全部流派已解锁」的完整卡面，不改真实存档（--no-save）
	# ⚠ 要盖过最高解锁层（符箓 = 50），否则最后那族只显示成锁定卡背
	CharacterData.rogue_best_floor = 60
	var panel := CodexPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	var view: CodexView = panel._view

	view._show_category(_index_of(CodexDB.CAT_ROGUE_CARD))
	await get_tree().process_frame
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("codex_rogue_cards.png")

	view._show_sub("legend")
	await get_tree().process_frame
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _shot("codex_rogue_cards_legend.png")

	# 滚到底：确认最后那一族「符箓」的分组标题与卡片都在（列表按 FAMILY_ORDER 排）
	view._show_sub("all")
	await get_tree().process_frame
	await get_tree().create_timer(0.2, true, false, true).timeout
	view._scroll.set_deferred("scroll_vertical", 100000)
	await get_tree().process_frame
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _shot("codex_rogue_cards_bottom.png")

	get_tree().paused = false
	get_tree().quit(0)
