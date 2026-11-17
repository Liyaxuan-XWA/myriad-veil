extends Node
## 试炼强化卡「数值有没有真的落到读数上」实时 harness。
##
## 跑法：godot --headless --path . --quit-after 900 res://tools/probe_rogue_effects.tscn -- --no-save
##
## 和 audit_rogue_cards 的分工：
##   audit  = 静态查「有没有人读这个 key」→ 抓**完全没有消费者**的死卡；
##   本文件 = 实时读一遍「加了这张卡之后，可观测的派生状态动没动」→ 抓
##            **有人读、但那个数根本没落到读数上**的卡（属性 id 拼错、走错通道、
##            cap 没进 CAP_BASE 被 clamp 回原值、form 乘到不存在的字段……）。
##   两条都过才算「生效」。静态过不了 = 死卡；实时过不了 = 接线了但空转。
##
## ⚠ 只覆盖**声明式通道**（attr / cap / form / recipe / variant）。
##   stat / flag 的最终效果发生在战斗结算里，静态检查已证明有读取点，
##   幅度对不对要靠各流派的行为探针（符箓已有：probe_talisman_family）。

var _fails: Array = []
var _passes := 0
var _skipped := 0
var _attr_ids: Array[String] = []


func _ready() -> void:
	print("\n########## 试炼强化卡 · 实时落值 harness ##########")
	_attr_ids = _load_attr_ids()
	print("观测属性 %d 个" % _attr_ids.size())
	# form 通道只有在「局内」才生效（apply_form_mods / resolve_player 都 gate 在 active）。
	# 这里只借这个开关，不跑整局：不建战斗场景、不碰存档。
	RogueRun.active = true
	for raw_fam in RogueDB.POOLS.keys():
		var fam := String(raw_fam)
		var pool: Array = RogueDB.POOLS[raw_fam]
		var fam_bad := 0
		for raw_card in pool:
			var card: Dictionary = raw_card
			var note := _check_card(card)
			if note == "":
				_passes += 1
			elif note == "skip":
				_skipped += 1
			else:
				_fails.append("%s · %s「%s」 %s" % [
					fam, String(card.get("id", "")), String(card.get("name", "")), note])
				fam_bad += 1
		print("  %-10s %3d 张，落值异常 %d" % [fam, pool.size(), fam_bad])
	_clean()
	print("\n########## 结果 %d 通过 / %d 异常 / %d 张由静态审计负责（stat/flag）##########" % [
		_passes, _fails.size(), _skipped])
	for f in _fails:
		print("  ✗ ", f)
	print("")
	get_tree().quit(_fails.size())


## 返回 "" = 落值正常；"skip" = 这张卡不属于本 harness 的观测面
func _check_card(card: Dictionary) -> String:
	var buffs_before: Dictionary = RogueRun.buffs.duplicate(true)
	var id := String(card.get("id", ""))
	var has_decl := not (card.get("attr", {}) as Dictionary).is_empty() \
			or not (card.get("cap", {}) as Dictionary).is_empty() \
			or not (card.get("form", []) as Array).is_empty() \
			or String(card.get("recipe", "")) != "" \
			or String(card.get("variant", "")) != ""
	if not has_decl:
		return "skip"

	var snap0 := _snapshot()
	RogueRun.buffs.clear()
	RogueRun.add_buff(id)
	# ⚠ 所有「加完之后」的观测必须在**还没还原**的时候做完：第一版把还原写在判据前面，
	#   form_mods 已经被 rebuild 清空，于是 32 张 form 卡全被误判成「乘了个寂寞」。
	var snap1 := _snapshot()
	var note := _judge(card, snap0, snap1)
	RogueRun.buffs = buffs_before
	RogueRun.rebuild()
	return note


## 返回 "" = 落值正常
func _judge(card: Dictionary, snap0: Dictionary, snap1: Dictionary) -> String:
	# 1) attr 卡：至少一个属性读数必须动
	var attr: Dictionary = card.get("attr", {})
	if not attr.is_empty():
		var moved := _changed_attrs(snap0, snap1)
		if moved.is_empty():
			return "attr 声明了 %s，但所有属性读数一模一样（这条加成没落到人身上）" \
					% str(attr.keys())

	# 2) cap 卡：RogueRun.cap(key) 必须变大
	var cap: Dictionary = card.get("cap", {})
	for raw_c in cap.keys():
		var c := String(raw_c)
		if int(snap0["cap"].get(c, 0)) == int(snap1["cap"].get(c, 0)):
			return "cap「%s」加完之后 RogueRun.cap() 读数没变（没进 CAP_BASE 或被 clamp）" % c

	# 3) form 卡：不能只看它进了 form_mods 表 —— 要证明**乘进结算结果之后，那个字段真的变了**。
	#    ⚠ apply_form_mods 第一行就 `if not active: return`，所以这里必须假装在局内。
	var forms: Array = card.get("form", [])
	for raw_fm in forms:
		var fm: Dictionary = raw_fm
		var form_id := String(fm.get("form_id", ""))
		var field := String(fm.get("field", ""))
		var out := MoveDB.resolve(form_id, MoveDB.CASTER_PLAYER)
		if out.is_empty():
			return "招式「%s」在 MoveDB 里不存在（form 乘给谁？）" % form_id
		if not out.has(field):
			return "招式「%s」的结算结果里没有字段「%s」→ 乘了个寂寞" % [form_id, field]
		var after: Dictionary = out.duplicate(true)
		RogueRun.apply_form_mods(form_id, after)
		if is_equal_approx(float(out[field]), float(after[field])):
			return "字段「%s」存在但乘完没变（倍率算出来是 1.0 / 加出来是 0）" % field

	# 4) 改符 / 符方：符匣必须真的多一张或多一条变体
	if String(card.get("recipe", "")) != "":
		if not RogueRun.talisman_owned(String(card["recipe"])):
			return "recipe「%s」加完卡符匣里还是没有这张符" % String(card["recipe"])
	if String(card.get("variant", "")) != "":
		if String(card.get("base", "")) != "" \
				and RogueRun.talisman_variant_of(String(card["base"])) == "":
			return "变体「%s」加完没写进 tal_variant" % String(card["variant"])
	return ""


func _snapshot() -> Dictionary:
	var a: Dictionary = {}
	for id in _attr_ids:
		a[id] = CharacterData.attribute(id)
	var c: Dictionary = {}
	for raw_k in RogueDB.CAP_BASE.keys():
		c[String(raw_k)] = RogueRun.cap(String(raw_k))
	return {"attr": a, "cap": c, "form": RogueRun.form_mods.duplicate(true)}


func _changed_attrs(s0: Dictionary, s1: Dictionary) -> Array:
	var out: Array = []
	for id in _attr_ids:
		if not is_equal_approx(float(s0["attr"][id]), float(s1["attr"][id])):
			out.append("%s %.3f→%.3f" % [id, float(s0["attr"][id]), float(s1["attr"][id])])
	return out


func _clean() -> void:
	RogueRun.buffs.clear()
	RogueRun.rebuild()
	RogueRun.active = false


func _load_attr_ids() -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string("res://scripts/data/attribute_db.gd")
	for raw_line in text.split("\n"):
		var s := String(raw_line).strip_edges()
		if not s.begins_with("const ATTR_"):
			continue
		var q0 := s.find("\"")
		var q1 := s.find("\"", q0 + 1)
		if q0 >= 0 and q1 > q0:
			out.append(s.substr(q0 + 1, q1 - q0 - 1))
	return out
