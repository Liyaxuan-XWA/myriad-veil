extends Node
## 技能栏「资源不足 → 图标变灰」自检（2026-11-09 用户要求）
## 用法：godot --headless --path . tools/probe_skill_bar_gray.tscn -- --no-save
##
## 验四件事：
##   1) 灵力 / 精力不足时，对应功法的图标灰化参数被打开，其它格不受影响
##   2) 资源回满后灰化自动撤销，tooltip 也恢复干净
##   3) 灰着的技能**确实放不出来**（灰化判定必须与 can_use_skill 同口径，不能骗人）
##   4) 符箓格同样按灵力判（它跟功法共用一排格子，逻辑不能只做一半）
##
## ⚠ 资源优先走真实入口清空（spend_mana / _spend_stamina）：
##   直接赋 0 能过、真实游戏里却因为别处拦着放不出来，是这类 UI 探针最容易骗自己的地方。
## ⚠ player 在探针里是 Node 静态类型，一律用 get / set / call，别写 player.mana。

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


## 从技能表里挑一个指定消耗类型的主动功法（避开「抽空整条资源」的大招，口径更干净）
func _pick_skill(kind: String) -> String:
	for raw in SkillDB.SKILLS:
		var s: Dictionary = raw
		if String(s.get("skill_type", "")) != SkillDB.TYPE_ACTIVE:
			continue
		var sid := String(s.get("skill_id", ""))
		var c := SkillDB.get_skill_cost(sid)
		if String(c.get("cost_kind", "")) != kind:
			continue
		if bool(c.get("stamina_all", false)) or bool(c.get("mana_all", false)):
			continue
		if kind == MoveDB.COST_MANA and float(c.get("mana_cost", 0.0)) <= 0.0:
			continue
		if kind == MoveDB.COST_STAMINA and int(c.get("stamina_cost", 0)) <= 0:
			continue
		return sid
	return ""


## 挑一个「不耗灵力也不耗精力」的主动功法：灰化判定的反向锁
## ⚠ 表里没有 COST_COOLDOWN 的主动功法，实际都是 COST_NONE，两种都认
func _pick_free_skill() -> String:
	for raw in SkillDB.SKILLS:
		var s: Dictionary = raw
		if String(s.get("skill_type", "")) != SkillDB.TYPE_ACTIVE:
			continue
		var sid := String(s.get("skill_id", ""))
		var c := SkillDB.get_skill_cost(sid)
		var kind := String(c.get("cost_kind", ""))
		if kind != MoveDB.COST_COOLDOWN and kind != MoveDB.COST_NONE:
			continue
		if bool(c.get("stamina_all", false)) or bool(c.get("mana_all", false)):
			continue
		return sid
	return ""


func _slot(arena: Node, sid: String) -> Dictionary:
	for e in arena.get("_skill_slots"):
		var d: Dictionary = e
		if String(d.get("sid", "")) == sid:
			return d
	return {}


## 返回 (gray_mix, dim)；没挂材质时返回 (-1, -1)
func _gray_params(e: Dictionary) -> Vector2:
	var mat: ShaderMaterial = e.get("icon_mat")
	if mat == null:
		return Vector2(-1.0, -1.0)
	return Vector2(float(mat.get_shader_parameter("gray_mix")),
		float(mat.get_shader_parameter("dim")))


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _finish() -> void:
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 技能栏资源不足灰化探针 ##########")

	var mana_sid := _pick_skill(MoveDB.COST_MANA)
	var stam_sid := _pick_skill(MoveDB.COST_STAMINA)
	var free_sid := _pick_free_skill()
	_check(mana_sid != "" and stam_sid != "" and free_sid != "",
		"数据表里三种消耗类型都有主动功法",
		"%s / %s / %s" % [mana_sid, stam_sid, free_sid])
	if mana_sid == "" or stam_sid == "" or free_sid == "":
		_finish()
		return

	for sid in [mana_sid, stam_sid, free_sid]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = [mana_sid, stam_sid, free_sid, ""]

	GameState.battle_context = {"source": BattleResolver.SOURCE_ARENA}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await _wait_frames(4)

	var player: Node = arena.get("player")
	_check(player != null and is_instance_valid(player), "战斗场景已生成玩家")
	if player == null:
		_finish()
		return

	# ===== ① 满资源：三格都不该灰 =====
	player.set("mana", float(player.get("max_mana")))
	player.set("stamina", int(player.get("max_stamina")))
	await _wait_frames(2)
	_check(not bool(_slot(arena, mana_sid).get("gray_on", false)), "满灵力：耗蓝功法不灰")
	_check(not bool(_slot(arena, stam_sid).get("gray_on", false)), "满精力：耗精力功法不灰")
	_check(_gray_params(_slot(arena, mana_sid)).x <= 0.01, "初始灰化参数为 0（原色）")

	# ===== ② 清空资源（走真实入口）=====
	var mana_need := float(SkillDB.get_skill_cost(mana_sid).get("mana_cost", 0.0))
	player.call("spend_mana", float(player.get("mana")))
	while int(player.get("stamina")) > 0:
		player.call("_spend_stamina")
	await _wait_frames(3)

	_check(float(player.get("mana")) < mana_need, "灵力已压到需求以下",
		"mana=%.1f need=%.1f" % [float(player.get("mana")), mana_need])
	var e_mana := _slot(arena, mana_sid)
	_check(bool(e_mana.get("gray_on", false)), "灵力不足 → 耗蓝功法图标灰化")
	var gp := _gray_params(e_mana)
	_check(gp.x >= 0.99 and gp.y > 0.0, "灰化参数写进了材质", "mix=%.2f dim=%.2f" % [gp.x, gp.y])

	_check(int(player.get("stamina")) <= 0, "精力已扣空",
		"stamina=%d" % int(player.get("stamina")))
	_check(bool(_slot(arena, stam_sid).get("gray_on", false)), "精力不足 → 耗精力功法图标灰化")

	_check(not bool(_slot(arena, free_sid).get("gray_on", false)), "不耗资源的功法不灰")
	_check(_gray_params(_slot(arena, free_sid)).x <= 0.01, "不耗资源的功法保持原色")
	var e_empty := _slot(arena, "")
	_check(e_empty.get("icon_mat") == null, "空槽不挂灰化材质")

	var box_mana: Control = e_mana.get("box")
	_check(box_mana != null and box_mana.tooltip_text.contains("无法释放"),
		"tooltip 写明暂时无法释放",
		box_mana.tooltip_text if box_mana != null else "<null>")
	_check(box_mana != null and box_mana.tooltip_text.contains("灵力不足"),
		"tooltip 指明原因是灵力不足")

	# 灰化必须是真的放不出来（同口径校验，避免「灰着却能放」）
	_check(not bool(player.call("try_use_skill", mana_sid)),
		"灰着的耗蓝功法确实放不出来")

	# ===== ③ 资源回满：灰化撤销、tooltip 复原 =====
	player.set("mana", float(player.get("max_mana")))
	player.set("stamina", int(player.get("max_stamina")))
	player.call("_update_mana_bar")
	player.call("_update_stamina_bar")
	await _wait_frames(3)
	_check(not bool(_slot(arena, mana_sid).get("gray_on", false)), "灵力回满 → 灰化撤销")
	_check(_gray_params(_slot(arena, mana_sid)).x <= 0.01, "灰化参数归零")
	var box_after: Control = _slot(arena, mana_sid).get("box")
	_check(box_after != null and not box_after.tooltip_text.contains("无法释放"),
		"tooltip 恢复干净")

	# ===== ④ 符箓格：同样按灵力判 =====
	var base_id := String((ItemDB.ELEMENT_TALISMAN_BASES[0] as Dictionary).get("base_id", ""))
	var tal_item := ItemDB.element_talisman_item_id(base_id, 0)
	var tal_slot := CharacterData.talisman_slot_value(tal_item)
	_check(tal_item != "" and tal_slot != "", "能拼出一张符箓的槽位值", tal_item)
	CharacterData.active_skill_loadout = [tal_slot, "", "", ""]
	arena.call("_build_skill_bar")
	player.call("spend_mana", float(player.get("mana")))
	await _wait_frames(3)
	var e_tal := _slot(arena, tal_slot)
	_check(not e_tal.is_empty(), "符箓槽已建出来")
	_check(bool(e_tal.get("gray_on", false)), "灵力不足 → 符箓格也灰化")
	var box_tal: Control = e_tal.get("box")
	_check(box_tal != null and box_tal.tooltip_text.contains("灵力不足"),
		"符箓 tooltip 指明灵力不足")
	_check(not bool(player.call("use_talisman_slot", tal_slot)), "灰着的符箓确实放不出来")

	_finish()
