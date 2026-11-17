extends Node
## 境界突破阈值探针（2026-11-01）：
## 每次突破下一阶段 +1,000；练气 1000/2000/3000，筑基 4000/5000/6000，
## 结丹 7000/8000/9000，元婴 10000/11000/12000；化神单阶段 99,999 封顶、不可再突破。

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _set_state(realm: String, stage: int, exp: int = 0) -> void:
	CharacterData.current_realm = realm
	CharacterData.realm_stage = stage
	CharacterData.realm_exp = exp


func _req(realm: String, stage: int) -> int:
	_set_state(realm, stage)
	return CharacterData.get_stage_exp_required()


func _ready() -> void:
	print("\n########## 境界突破阈值探针 ##########")
	var saved_realm := CharacterData.current_realm
	var saved_stage := CharacterData.realm_stage
	var saved_exp := CharacterData.realm_exp
	var saved_limit := CharacterData.current_world_realm_limit

	var expected := {
		"练气": [1000, 2000, 3000],
		"筑基": [4000, 5000, 6000],
		"结丹": [7000, 8000, 9000],
		"元婴": [10000, 11000, 12000],
	}
	for realm in expected.keys():
		for stage in 3:
			var got := _req(String(realm), stage)
			_check(got == int(expected[realm][stage]), "%s第%d阶段 = %d" % [
				String(realm), stage + 1, int(expected[realm][stage])], str(got))

	_set_state("练气", 0, 1000)
	_check(CharacterData.can_break_stage(), "练气前期满 1000 可小突破")
	CharacterData.break_stage()
	_check(CharacterData.realm_stage == 1 and CharacterData.realm_exp == 0,
		"小突破后到中期、修为清零")
	_check(CharacterData.get_stage_exp_required() == 2000, "中期下一次要求 2000")
	CharacterData.realm_exp = 2000
	CharacterData.break_stage()
	_check(CharacterData.realm_stage == 2 and CharacterData.is_final_stage(),
		"第二次小突破到后期")
	CharacterData.realm_exp = 3000
	_check(not CharacterData.can_break_stage(), "后期满后不能继续小突破")
	CharacterData.break_stage()
	_check(CharacterData.realm_stage == 2 and CharacterData.realm_exp == 3000,
		"后期 break_stage 不生效")

	CharacterData.break_realm("筑基")
	_check(CharacterData.current_realm == "筑基" and CharacterData.realm_stage == 0
		and CharacterData.realm_exp == 0 and CharacterData.get_stage_exp_required() == 4000,
		"大突破后筑基前期 = 4000")
	CharacterData.realm_exp = 4000
	CharacterData.break_stage()
	_check(CharacterData.get_stage_exp_required() == 5000, "筑基中期 = 5000")
	CharacterData.realm_exp = 5000
	CharacterData.break_stage()
	_check(CharacterData.get_stage_exp_required() == 6000, "筑基后期 = 6000")

	_set_state("元婴", 2, 12000)
	_check(CharacterData.is_final_stage() and CharacterData.has_breakthrough_pending(),
		"元婴后期满可大突破化神")
	CharacterData.break_realm("化神")
	_check(CharacterData.current_realm == "化神" and CharacterData.realm_stage == 0,
		"化神单阶段（stage 0）")
	_check(CharacterData.get_stage_exp_required() == 99999, "化神修为上限 99,999")
	_check(CharacterData.get_realm_stage_name() == "" and CharacterData.get_next_stage_name() == "",
		"化神不再显示前/中/后期")
	_check(CharacterData.is_final_stage() and not CharacterData.can_break_stage(),
		"化神不可再突破")
	CharacterData.realm_exp = 50000
	_check(not CharacterData.has_breakthrough_pending(), "化神未满也不提示突破")
	CharacterData.add_realm_exp(99999)
	_check(CharacterData.realm_exp == 99999, "化神修为封顶 99,999")
	CharacterData.break_realm("化神")
	CharacterData.break_stage()
	_check(CharacterData.current_realm == "化神" and CharacterData.realm_stage == 0,
		"化神后 break 调用不改变境界")

	CharacterData.current_realm = saved_realm
	CharacterData.realm_stage = saved_stage
	CharacterData.realm_exp = saved_exp
	CharacterData.current_world_realm_limit = saved_limit
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
