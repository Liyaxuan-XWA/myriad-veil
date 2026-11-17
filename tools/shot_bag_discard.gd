extends Node
## 背包丢弃截图（2026-11-01）：丹药可丢 / 普通材料可丢 / 突破材料不可丢。
## 用法：godot --path . --windowed --resolution 1600x1000 tools/shot_bag_discard.tscn -- --no-save

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


func _ready() -> void:
	var backup: Array = CharacterData.inventory.duplicate(true)
	var pill := {"id": "pill_julidan", "name": "练气巨力丹", "type": "pill", "count": 2}
	var herb := {"id": "mat_ruishoupi", "name": "青岚兽皮", "type": "material", "count": 1}
	var crystal := {"id": "mat_pojing_zhuji", "name": "筑基破境晶", "type": "material", "count": 1}
	CharacterData.inventory = [pill, herb, crystal]
	CharacterPanel.open_panel()
	await get_tree().create_timer(0.6, true, false, true).timeout
	CharacterPanel._on_item_selected(pill, 0)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("bag_discard_pill.png")
	CharacterPanel._on_item_selected(herb, 1)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("bag_discard_material.png")
	CharacterPanel._on_item_selected(crystal, 2)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _shot("bag_discard_breakthrough.png")
	CharacterPanel.close_panel()
	CharacterData.inventory = backup
	get_tree().quit(0)
