extends Node
## 万界秘境位面 BOSS 死亡记录自检（2026-10-31）
## 累计次数按「位面/首领」分开；首通快照只写一次；存档快照带这两个字段。
## 用法：godot --headless --path . res://tools/probe_boss_deaths.tscn

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
	print("\n########## BOSS 死亡记录探针 ##########")
	var saved_count: Dictionary = CharacterData.boss_death_count
	var saved_first: Dictionary = CharacterData.boss_first_clear_deaths
	CharacterData.boss_death_count = {}
	CharacterData.boss_first_clear_deaths = {}

	_check(CharacterData.boss_death_key("domain_01", "boss_huyao") == "domain_01/boss_huyao",
		"死亡记录键 = 位面/首领")
	_check(CharacterData.boss_death_key("", "boss_huyao") == "", "空位面不生成键")

	_check(CharacterData.add_boss_death("domain_01", "boss_huyao") == 1, "首次死亡 +1")
	_check(CharacterData.add_boss_death("domain_01", "boss_huyao") == 2, "累计死亡 +1")
	_check(CharacterData.get_boss_death("domain_01", "boss_huyao") == 2, "读到累计 2 次")
	_check(CharacterData.get_boss_death("domain_01", "boss_01") == 0, "同界另一只不串号")
	_check(CharacterData.get_boss_death("domain_02", "boss_huyao") == 0, "异界同名不串号")

	_check(CharacterData.record_boss_first_clear_deaths("domain_01", "boss_huyao") == 2,
		"首通快照 = 通关前死亡 2 次")
	_check(CharacterData.add_boss_death("domain_01", "boss_huyao") == 3, "通关后重战继续累计")
	_check(CharacterData.get_boss_first_clear_deaths("domain_01", "boss_huyao") == 2,
		"首通快照不被重战覆盖")
	_check(CharacterData.record_boss_first_clear_deaths("domain_01", "boss_huyao") == 2,
		"重复首通快照仍返回 2")
	_check(CharacterData.get_boss_death("domain_01", "boss_huyao") == 3, "累计 3 次保留")

	_check(CharacterData.get_boss_death("", "") == 0, "空键读 0")
	_check(CharacterData.add_boss_death("", "") == 0, "空键不统计")

	var snap := SaveManager.capture()
	_check(int((snap.get("boss_death_count", {}) as Dictionary).get("domain_01/boss_huyao", 0)) == 3,
		"存档快照带累计死亡")
	_check(int((snap.get("boss_first_clear_deaths", {}) as Dictionary).get(
		"domain_01/boss_huyao", 0)) == 2, "存档快照带首通死亡")

	CharacterData.boss_death_count = saved_count
	CharacterData.boss_first_clear_deaths = saved_first
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
