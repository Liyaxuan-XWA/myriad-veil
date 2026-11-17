extends Node
## 符匣存档 / 旧档迁移探针（2026-11-01）：
## 1) talisman_stock 能随 capture/apply 往返；
## 2) 旧档没有 talisman_stock、符箓还在 inventory_data 时，读档迁移到符匣；
## 3) 旧烈火 / 磐石符仍被清掉。

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 符匣存档 / 迁移探针 ##########")
	var saved_inv: Array = CharacterData.inventory.duplicate(true)
	var saved_stock: Dictionary = CharacterData.talisman_stock.duplicate(true)

	# 1) 新字段往返
	CharacterData.inventory = []
	CharacterData.talisman_stock = {"tal_huoqiu_lianqi": 4}
	var snap := SaveManager.capture(CharacterData)
	_check(snap.has("talisman_stock"), "存档包含 talisman_stock")
	CharacterData.talisman_stock = {}
	SaveManager.apply(snap)
	_check(CharacterData.talisman_count("tal_huoqiu_lianqi") == 4,
		"符匣数量读档往返", str(CharacterData.talisman_count("tal_huoqiu_lianqi")))

	# 2) 旧档：没有 talisman_stock，背包里还有符箓 → 读档迁入符匣
	var old := SaveManager.capture(CharacterData)
	old.erase("talisman_stock")
	old["inventory_data"] = [
		{"id": "tal_jinfeng_lianqi", "name": "金锋符·练气", "type": "talisman", "count": 2},
		{"id": "mat_ruishoupi", "name": "兽皮", "type": "material", "count": 1},
	]
	SaveManager.apply(old)
	var tal_inv := 0
	for it in CharacterData.inventory:
		if String((it as Dictionary).get("type", "")) == CharacterData.ITEM_TALISMAN:
			tal_inv += 1
	_check(CharacterData.talisman_count("tal_jinfeng_lianqi") == 2, "旧档符箓迁入符匣")
	_check(tal_inv == 0 and CharacterData.inventory.size() == 1, "旧档背包只留材料")

	# 3) 旧烈火符仍会被清掉
	var legacy := SaveManager.capture(CharacterData)
	legacy["talisman_stock"] = {"tal_pofengfu": 2, "tal_huoqiu_lianqi": 1}
	SaveManager.apply(legacy)
	_check(CharacterData.talisman_count("tal_pofengfu") == 0, "旧符从符匣清除")
	_check(CharacterData.talisman_count("tal_huoqiu_lianqi") == 1, "新符保留")

	CharacterData.inventory = saved_inv
	CharacterData.talisman_stock = saved_stock
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
