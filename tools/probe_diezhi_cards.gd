extends Node
## 读真存档、走真 CodexDB 口径，确认叠纸（boss_04_c · 塔 12 层）四张卡解锁状态。
## 用法：godot --headless --path . res://tools/probe_diezhi_cards.tscn -- --no-save
## ⚠ 一定带 --no-save：本探针会 SaveManager.load_slot()，不关掉写盘就可能把槽覆盖回去。

const BOSS_ID := "boss_04_c"


func _ready() -> void:
	print("\n########## 叠纸四张卡 · 读档核对 ##########")
	var fails: Array = []
	for slot in [1, 2, 3, 4]:
		if not FileAccess.file_exists(SaveManager.slot_path(slot)):
			print("槽%d 无存档，跳过" % slot)
			continue
		if not SaveManager.load_slot(slot):
			fails.append("槽%d 读档失败（JSON 可能被写坏）" % slot)
			continue
		var e: Dictionary = CodexDB.card_entry(BOSS_ID)
		var vs: Array = e.get("card_variants", []) as Array
		var parts: Array = []
		var locked := 0
		for v in vs:
			var d: Dictionary = v
			var ok := bool(d.get("unlocked", false))
			if not ok:
				locked += 1
			parts.append("%s(%s)=%s" % [String(d.get("id", "?")), String(d.get("kind", "?")),
					"开" if ok else "锁"])
			# 顺带确认这张的图真的在盘上
			var art := String(d.get("art", ""))
			if art != "" and not ResourceLoader.exists(art):
				fails.append("槽%d 缺图 %s" % [slot, art])
		var cover := ""
		if not vs.is_empty():
			cover = String((CodexDB.ordered_variants(e)[0] as Dictionary).get("id", "?"))
		print("槽%d  %s  封面=%s  塔12记录=%s" % [slot, "  ".join(parts), cover,
				str(CharacterData.tower_progress.get("12", CharacterData.tower_progress.get(12, {})))])
		if locked > 0:
			fails.append("槽%d 还有 %d 张锁着" % [slot, locked])
	print("\n########## 结果：%s ##########" % ("四张全开" if fails.is_empty() else " ; ".join(fails)))
	get_tree().quit(1 if not fails.is_empty() else 0)
