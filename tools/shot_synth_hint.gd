extends Node
## 法宝合成指引截图（2026-11-09）：在角色面板里逐件看材料的「去哪合成」行。
## 用法：godot --path . --windowed --resolution 1600x1000 tools/shot_synth_hint.tscn -- --no-save
## ⚠ 探针/截图改背包一律 --no-save，并且结束时还原，不能写进玩家存档。

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


## 按材料表造一条背包物品（desc 从 ItemDB 取，不手抄，避免截图里出现和游戏不一致的文案）
func _mat(mid: String) -> Dictionary:
	var def := ItemDB.get_material(mid)
	return {
		"id": mid,
		"name": String(def.get("name", mid)),
		"type": "material",
		"realm": String(def.get("realm", "")),
		"count": 1,
		"desc": String(def.get("desc", "")),
	}


func _ready() -> void:
	var backup: Array = CharacterData.inventory.duplicate(true)
	# 四件对照：位面材料 / 元魂 / 破境残晶 / 一株普通药材（普通药材不该出现指引）
	var mats: Array = [
		_mat("mat_fanjie_duanren"),
		_mat("soul_daoke"),
		_mat("mat_pojing_di_zhuji"),
		_mat("mat_xuecao"),
	]
	CharacterData.inventory = mats
	CharacterPanel.open_panel()
	await get_tree().create_timer(0.6, true, false, true).timeout
	var names := ["hint_plane.png", "hint_soul.png", "hint_pojing.png", "hint_plain.png"]
	for i in range(mats.size()):
		CharacterPanel._on_item_selected(mats[i], i)
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _shot(names[i])
	CharacterPanel.close_panel()
	CharacterData.inventory = backup
	get_tree().quit(0)
