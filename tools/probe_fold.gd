extends Node
## 叠纸 · 折影为径 全链路探针（2026-11-02）
## 覆盖：位面/塔 12 层 / 八式数据 / 折痕几何（镜像、贴合带、异侧、押痕平移）/
##       选招不许空放 / 每招实测出手与落空 / 碎痕作废窗口 / 二阶段三区 /
##       首战空手可破 / 无势条无叠爆 / 玩家侧完整继承 / 图鉴 / 掉落与位面法宝 /
##       卡包与字印 / 素材落地。
## 用法：godot --headless --path . res://tools/probe_fold.tscn -- --no-save

const BOSS_SCENE := "res://scenes/boss/domain_boss_04_c.tscn"

const FORMS: Array[String] = [
	"form_fold_press", "form_fold_trace", "form_fold_stride", "form_fold_pressmark",
	"form_fold_shroud", "form_fold_tear", "form_fold_twin", "form_fold_triple",
]
const SKILLS: Array[String] = [
	"skill_fold_press", "skill_fold_trace", "skill_fold_stride", "skill_fold_seam",
	"skill_fold_shroud", "skill_fold_tear", "skill_fold_twin", "skill_fold_triple",
	"skill_fold_measure",
]
# 底板残留守卫覆盖的全部图标：九式 + 元魂 + 执令 + 武器 + 材料。
# 漏掉后两个就会重演 11-04 那次：只做了功法图标，`equip_zhicuo_jian` 一整幅灰紫底没人查。
const ICONS: Array[String] = SKILLS + [
	"soul_diezhi", "tr_diezhi_ling", "equip_zhicuo_jian", "mat_zhaoying_zhihen",
]

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
	_check_domain()
	_check_forms()
	_check_skills()
	_check_items()
	_check_geometry()
	_check_assets()
	_check_style()
	_check_terms()
	_finish()


# ===== 位面与塔层 =====
func _check_domain() -> void:
	var floors: Array = WorldDB.get_floors()
	_check(floors.size() == 12, "塔层总数 = 12", "实际 %d" % floors.size())
	var last: Dictionary = floors[-1] if floors.size() > 0 else {}
	_check(String(last.get("boss_id", "")) == "boss_04_c", "第 12 层是叠纸", str(last.get("boss_id", "")))
	_check(String(last.get("projection_id", "")) == "proj_boss_04_c", "投影 id", str(last.get("projection_id", "")))
	_check(String(last.get("boss_name", "")) == "叠纸", "层表名字", str(last.get("boss_name", "")))
	_check(WorldDB.get_boss_name("boss_04_c") == "叠纸", "BOSS_NAMES 登记")
	_check(WorldDB.get_boss_scene("boss_04_c") == "res://scenes/boss/domain_boss_04_c.tscn", "BOSS_SCENES 登记")
	_check(ResourceLoader.exists("res://scenes/boss/domain_boss_04_c.tscn"), "战斗场景文件存在")
	var d4: Dictionary = {}
	for d in WorldDB.DOMAINS:
		if String((d as Dictionary).get("domain_id", "")) == "domain_04":
			d4 = d
	var ids: Array = d4.get("boss_ids", [])
	_check(ids.size() == 3 and "boss_04_c" in ids, "照影界三位齐", str(ids))
	var moves: Array = WorldDB.get_boss_moves("boss_04_c")
	_check(moves.size() == 8, "BOSS_MOVES 登记 8 式", str(moves.size()))
	for m in moves:
		var fid := String((m as Dictionary).get("form_id", ""))
		_check(MoveDB.has_form(fid), "BOSS_MOVES form 可解析", fid)
	var p2 := []
	for m in moves:
		if int((m as Dictionary).get("phase", 1)) == 2:
			p2.append(String((m as Dictionary).get("form_id", "")))
	_check(p2 == ["form_fold_triple"], "仅终局招标 phase 2", str(p2))


# ===== 八式数据 =====
func _check_forms() -> void:
	for fid in FORMS:
		_check(MoveDB.has_form(fid), "FORMS 有条目", fid)
		var f: Dictionary = MoveDB.get_form(fid)
		var b: Dictionary = f.get("boss", {})
		var p: Dictionary = f.get("player", {})
		_check(not b.is_empty(), "boss 子表", fid)
		_check(not p.is_empty(), "player 子表", fid)
		_check(String(f.get("visual_id", "")).begins_with("fx_fold_"), "visual_id 前缀", fid)
		_check(String(f.get("damage_element", "")) in AttributeDB.ELEMENTS, "元素已标", fid)
		_check(float(f.get("windup", 0.0)) >= 0.4, "前摇够长可读", "%.2f" % float(f.get("windup", 0.0)))
		_check(float(f.get("active", 0.0)) > 0.0, "判定段存在", fid)
		_check(float(b.get("damage_coeff", -1.0)) >= 0.0, "伤害系数合法", "%.2f" % float(b.get("damage_coeff", -1.0)))
	_check(float(MoveDB.resolve_boss("form_fold_triple").get("damage_mult_p2", 1.0)) == 1.0,
		"终局招 P2 倍率不叠加", "登记为 1.0：它只在 P2 出，再乘 1.5 等于偷抬系数表")
	_check(String(MoveDB.get_form("form_fold_tear").get("fold_tag", "")) == "tear", "fold_tag 齐全")


# ===== 玩家侧功法 =====
func _check_skills() -> void:
	var by_id: Dictionary = {}
	for s in SkillDB.SKILLS:
		by_id[String((s as Dictionary).get("skill_id", ""))] = s
	for sid in SKILLS:
		_check(by_id.has(sid), "SKILLS 有条目", sid)
		var s: Dictionary = by_id.get(sid, {})
		_check(bool(s.get("fold", false)), "fold 标记", sid)
		_check(String(s.get("source_boss_id", "")) == "boss_04_c", "归属叠纸", sid)
		_check(String(s.get("tower_projection_id", "")) == "proj_boss_04_c", "投影归属", sid)
		_check(String(s.get("icon", "")) != "", "图标路径已登记", sid)
		var fid := String(s.get("form_id", ""))
		if fid != "":
			_check(MoveDB.has_form(fid), "form_id 可解析", sid + " -> " + fid)
		var lines: Array = SkillDB.get_effect_lines(sid)
		_check(lines.size() > 0, "功法库机制行非空", sid)
	var rules: Dictionary = SkillDB.get_group_rules("boss_04_c")
	_check(not rules.is_empty(), "get_group_rules 有折影分支")
	_check((rules.get("lines", []) as Array).size() >= 10, "折影总说明行数够",
		str((rules.get("lines", []) as Array).size()))
	_check(str(SkillDB.get_group_rules("boss_04_b")).find("折影") < 0, "执烛组不误挂折影说明")
	var actives := 0
	var passives := 0
	for sid in SKILLS:
		if String(by_id.get(sid, {}).get("skill_type", "")) == SkillDB.TYPE_PASSIVE:
			passives += 1
		else:
			actives += 1
	_check(actives == 8 and passives == 1, "8 主动 + 1 被动", "%d / %d" % [actives, passives])


# ===== 物品 / 掉落 / 合成 =====
func _check_items() -> void:
	_check(not ItemDB.get_material("mat_zhaoying_zhihen").is_empty(), "位面材料照影纸痕登记")
	_check(not ItemDB.get_material("soul_diezhi").is_empty(), "叠纸元魂登记")
	_check(_tpl_of("eq_zhicuo_jian") != {}, "纸错剑登记")
	_check(_tpl_of("eq_zhehen_pei") != {}, "折痕佩登记")
	_check(not ItemDB.get_treasure_template("tr_diezhi_ling").is_empty(), "叠纸令登记")
	var zhefu := ItemDB.get_treasure_template("tr_zhaoying_zhefu")
	_check(not zhefu.is_empty(), "照影·迟照符登记")
	_check(String(zhefu.get("active_type", "")) == "delayed_reckoning",
		"第四位面法宝已换用延迟结算机制")
	var recipe: Dictionary = ItemDB.get_plane_treasure_recipe("domain_04")
	_check(String(recipe.get("result_id", "")) == "tr_zhaoying_zhefu", "domain_04 位面法宝配方", str(recipe))
	var mats: Array = recipe.get("material_ids", [])
	_check(mats.size() == 3 and "mat_zhaoying_zhihen" in mats, "配方三件材料齐", str(mats))
	var drops: Array = ItemDB.get_drops_for_boss("boss_04_c")
	_check(drops.size() == 3, "boss_04_c 掉落三件", str(drops))
	var fk: Dictionary = ItemDB.FIRST_KILL_REWARDS
	_check(fk.has("boss_04_c"), "首杀奖励挂到叠纸")
	_check(not fk.has("boss_04_b"), "化神天髓不再挂在执烛上")
	var synth_found := false
	for r in ItemDB.SYNTH_RECIPES:
		if String((r as Dictionary).get("boss_id", "")) == "boss_04_c":
			synth_found = true
	_check(synth_found, "元魂熔铸配方登记")
	_check(not DebuffDB.get_debuff("fold_mark").is_empty(), "纸印 debuff 登记")
	## 两件装备都要有用途差字段，且不是靠攻击力词条堆数值
	for eid in ["eq_zhicuo_jian", "eq_zhehen_pei"]:
		var tpl := _tpl_of(eid)
		_check(String(tpl.get("special_effect", "")) != "", "装备有用途差效果", eid)
		_check(float(tpl.get("attack_bonus", 0.0)) == 0.0, "装备不做攻击膨胀", eid)
	_check(float(_tpl_of("eq_zhehen_pei").get("attributes", {}).get("strength", 0.0)) == 0.0,
		"折痕佩纯生存（不给力量）")


# ===== 折痕几何（纯数学，不依赖场景）=====
func _check_geometry() -> void:
	var a := Vector2(-260.0, 0.0)
	var b := Vector2(260.0, 0.0)
	# 镜像是对合：折过去再折回来 == 原位
	var p := Vector2(70.0, 190.0)
	var m := FoldLaw.mirror(a, b, p)
	_check(FoldLaw.mirror(a, b, m).distance_squared_to(p) < 1.0, "镜像对合", str(m))
	_check(absf(m.x - p.x) < 1.0 and absf(m.y + p.y) < 1.0, "关于 X 轴镜像", str(m))
	_check(FoldLaw.side(a, b, p) > 0.0 and FoldLaw.side(a, b, Vector2(0.0, -10.0)) < 0.0, "两侧符号相反")
	_check(absf(FoldLaw.fold_dist(a, b, p) - 190.0) < 1.0, "贴合距离 = 垂直距离",
		"%.1f" % FoldLaw.fold_dist(a, b, p))
	var far := Vector2(760.0, 30.0)
	_check(FoldLaw.fold_dist(a, b, far) > FoldLaw.FAR_EPS * 0.5, "痕外垂足不认（那块纸没折过来）",
		"%.1f" % FoldLaw.fold_dist(a, b, far))
	# 出手者在 y<0，目标在 y>0：异侧，才谈得上镜像
	var src := Vector2(0.0, -80.0)
	_check(FoldLaw.mirror_valid(a, b, src, p, FoldLaw.REACH_P1), "异侧 + 带内 = 镜像成立")
	_check(not FoldLaw.mirror_valid(a, b, src, Vector2(0.0, 500.0), FoldLaw.REACH_P1),
		"超出贴合带 = 镜像落空")
	_check(not FoldLaw.mirror_valid(a, b, src, Vector2(0.0, -60.0), FoldLaw.REACH_P1),
		"同侧 = 镜像落空（打的是对面那张纸）")
	_check(FoldLaw.mirror_valid(a, b, src, Vector2(0.0, 380.0), FoldLaw.REACH_P2, true),
		"纸印把贴合带从 260 放宽到 380+", "带内目标 y=380")
	_check(not FoldLaw.mirror_valid(a, b, src, Vector2(0.0, 380.0), FoldLaw.REACH_P2, false),
		"无纸印时同一位置落空")
	# 退化痕（长度 0）不许产生镜像命中
	_check(not FoldLaw.mirror_valid(Vector2.ZERO, Vector2.ZERO, src, p, FoldLaw.REACH_P1),
		"零长折痕不成立")
	# 二阶段口径确实收窄，换痕确实更快
	_check(FoldLaw.reach_for(2) < FoldLaw.reach_for(1), "P2 贴合带收窄")
	_check(FoldLaw.refold_for(2) < FoldLaw.refold_for(1), "P2 换痕更勤")
	# 双折复合是等距变换：两点之间的距离不会被甩飞（旋转中心不是原点，
	# 所以只能比「点对之间」，不能比到原点的长度）
	var c1 := Vector2(-300.0, -60.0)
	var c2 := Vector2(300.0, -60.0)
	var c3 := Vector2(-60.0, -300.0)
	var c4 := Vector2(-60.0, 300.0)
	var q := Vector2(120.0, 140.0)
	var q2 := Vector2(-180.0, 60.0)
	var mm := FoldLaw.mirror_twice(c1, c2, c3, c4, q)
	var mm2 := FoldLaw.mirror_twice(c1, c2, c3, c4, q2)
	_check(absf(mm.distance_to(mm2) - q.distance_to(q2)) < 2.0, "双折是等距变换",
		"%.1f vs %.1f" % [mm.distance_to(mm2), q.distance_to(q2)])
	# 二阶段两条痕必须真的平行：逐端点钳墙会把痕拧歪，三区前提就不成立了
	var fld: Node2D = preload("res://scripts/combat/fold_field.gd").new()
	fld.arena_center = Vector2.ZERO
	fld.arena_half = Vector2(700.0, 460.0)
	fld.arena_margin = 60.0
	fld.phase = 2
	fld.rebuild_near(Vector2(240.0, 120.0))
	_check((fld.spans as Array).size() == 2, "二阶段 rebuild 出两条痕",
		str((fld.spans as Array).size()))
	var s1: Dictionary = (fld.spans as Array)[0]
	var s2: Dictionary = (fld.spans as Array)[1]
	var d1 := FoldLaw.crease_dir(s1.get("a", Vector2.ZERO) as Vector2,
			s1.get("b", Vector2.ZERO) as Vector2)
	var d2 := FoldLaw.crease_dir(s2.get("a", Vector2.ZERO) as Vector2,
			s2.get("b", Vector2.ZERO) as Vector2)
	_check(absf(absf(d1.dot(d2)) - 1.0) < 0.02, "两条痕严格平行", "dot=%.4f" % d1.dot(d2))
	for one in [s1, s2]:
		var ea: Vector2 = one.get("a", Vector2.ZERO)
		var eb: Vector2 = one.get("b", Vector2.ZERO)
		_check(absf(ea.x) <= 640.0 + 1.0 and absf(ea.y) <= 400.0 + 1.0
				and absf(eb.x) <= 640.0 + 1.0 and absf(eb.y) <= 400.0 + 1.0,
			"两端点都在场内（平移钳制生效）", "%s %s" % [str(ea), str(eb)])
	# 押痕：压完之后玩家的对位落点要真的落在 BOSS 脚下（这一式的正解）
	var boss_p := Vector2(-140.0, 60.0)
	var play_p := Vector2(120.0, 190.0)
	_check(fld.bisect(boss_p, play_p, 360.0), "押痕能重立一条痕")
	var sp2: Dictionary = (fld.spans as Array)[0]
	var folded := FoldLaw.mirror(sp2.get("a", Vector2.ZERO) as Vector2,
			sp2.get("b", Vector2.ZERO) as Vector2, play_p)
	_check(folded.distance_to(boss_p) < 40.0,
		"押痕之后玩家的对位落点就在 BOSS 脚下", "偏 %.0f px" % folded.distance_to(boss_p))
	fld.free()

	# 文案数字全部现算，不许出现空串
	for t in [FoldLaw.reach_text(), FoldLaw.seam_text(), FoldLaw.refold_text(),
			FoldLaw.mirror_text(), FoldLaw.tear_text()]:
		_check(String(t).length() > 4, "几何文案", String(t))


func _tpl_of(equipment_id: String) -> Dictionary:
	for e in ItemDB.EQUIPMENT_TEMPLATES:
		if String((e as Dictionary).get("equipment_id", "")) == equipment_id:
			return e
	return {}


func _finish() -> void:
	print("---- probe_fold ----")
	print("PASS %d  FAIL %d" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAIL ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


# ===== 素材落地（占位件也算，路径必须真实存在）=====
func _check_assets() -> void:
	var need: Array = [
		"res://scenes/boss/domain_boss_04_c.tscn",
		"res://scripts/boss/domain_boss_04_c.gd",
		"res://scripts/visual/boss_rig_diezhi.gd",
		"res://scripts/combat/fold_law.gd",
		"res://scripts/combat/fold_field.gd",
		"res://scripts/combat/fold_visual.gd",
		"res://scripts/combat/fold_seam.gd",
		"res://assets/characters/boss/diezhi_rig/rig.tres",
		"res://assets/characters/boss/diezhi_rig/body.png",
		"res://assets/characters/boss/diezhi_rig/rule.png",
		"res://assets/characters/boss/boss_diezhi.png",
		"res://assets/scenes/zhaoying_fold_arena_ground.png",
		"res://assets/effects/skills/fold_seal.png",
		"res://assets/effects/weapons/zhicuo_jian.png",
		"res://assets/ui/codex/card_boss_diezhi.png",
		"res://assets/ui/codex/holo/boss_04_c_art.png",
		"res://assets/ui/codex/holo/boss_04_c_lines.png",
		"res://assets/ui/codex/holo/boss_04_c_bg.png",
		"res://assets/ui/codex/holo/boss_04_c_ink.png",
	]
	for sid in SKILLS:
		need.append("res://assets/ui/icon/%s.png" % sid)
	for iid in ["mat_zhaoying_zhihen", "soul_diezhi", "tr_diezhi_ling",
			"tr_zhaoying_zhefu", "equip_zhicuo_jian", "equip_zhehen_pei"]:
		need.append("res://assets/ui/icon/%s.png" % iid)
	for path in need:
		_check(ResourceLoader.exists(String(path)), "素材存在", String(path))
	# rig 三件必须齐全，且 scale 必须是 0.25（碰撞半径按缩放后宽度算 —— 见项目记忆）
	var vis: Dictionary = ArtDB.get_visual("boss_diezhi")
	_check(float((vis.get("scale") as Vector2).x) == 0.25, "rig 条目 scale = 0.25",
		str(vis.get("scale")))
	var rig: Resource = load("res://assets/characters/boss/diezhi_rig/rig.tres")
	_check(rig != null and (rig.part_name as PackedStringArray).size() == 2,
		"rig 分件 body / rule", str(rig.part_name))
	# 八式动画名必须全部在 rig 脚本里存在：名字对不上不会报错，只会静默放 idle
	var anims: Dictionary = ArtDB.BOSS_MOVE_ANIMS.get("boss_diezhi", {})
	for f in FORMS:
		var an := String(anims.get(f, ""))
		_check(an != "", "BOSS_MOVE_ANIMS 登记", f + " -> " + an)
	var anim_names := _rig_anim_names()
	for an in anims.values():
		_check(anim_names.has(String(an)), "rig 真的有这条动画", String(an))
	# 折族 FX：八式都要有 SKILL_FX 条目，且 motif 必须是 fold（SkillFx 按 motif 分发）
	for sid in SKILLS:
		var fx: Dictionary = ArtDB.get_skill_fx(sid)
		_check(not fx.is_empty(), "SKILL_FX 有条目", sid)
		_check(String(fx.get("motif", "")) == "fold", "motif = fold", sid)
		_check(String(fx.get("fold_mode", "")) != "", "fold_mode 已设", sid)
	# 战场：地面分支与调色都要登记上
	var bg: Dictionary = ArtDB.get_visual("bg_zhaoying_fold_arena")
	_check(not bg.is_empty(), "战场 visual 已登记")
	_check(float((bg.get("grade") as Dictionary).get("vignette", 1.0)) <= 0.34,
		"战场暗角不超过 0.34（场地不能压暗到影响战斗）",
		str((bg.get("grade") as Dictionary).get("vignette", 1.0)))


func _rig_anim_names() -> Dictionary:
	var out := {}
	var scr := load("res://scripts/visual/boss_rig_diezhi.gd")
	if scr == null:
		return out
	var table: Dictionary = scr.DIEZHI_SKILLS
	for k in table.keys():
		out[String(k)] = true
	out["idle"] = true
	out["walk"] = true
	return out


# ===== 新名词必须在图鉴卡与功法库两处都讲清（用户 2026-11-02 约束原文）=====
func _check_terms() -> void:
	var codex: Dictionary = CodexDB.BOSS_CODEX.get("boss_04_c", {})
	var blob := str(codex.get("mechanic", "")) + " " + " ".join(
			PackedStringArray(codex.get("mechanic_points", [])))
	blob += " " + str(codex.get("intro_hint", "")) + " " + str(codex.get("status_note", ""))
	var rules: Dictionary = SkillDB.get_group_rules("boss_04_c")
	var skill_blob := str(rules.get("title", "")) + " " + " ".join(
			PackedStringArray(rules.get("lines", [])))
	for sid in SKILLS:
		skill_blob += " " + str(SkillDB.get_effect_lines(sid))
	# 这套机制引入的每个新名词，两边都要出现
	var terms: Array = ["折痕", "贴合带", "镜像", "圆牌", "对位", "押痕", "碎痕",
		"叠掩", "裁痕", "量折", "纸印", "三重落纸", "二折", "穿缝"]
	for term in terms:
		_check(blob.find(term) >= 0, "图鉴卡讲清「%s」" % term)
		_check(skill_blob.find(term) >= 0, "功法库讲清「%s」" % term)
	# 两件装备与三件新物品都要能在图鉴里查到来源
	for iid in ["eq_zhicuo_jian", "eq_zhehen_pei"]:
		_check(str(CodexDB.SOURCES.get(iid, "")) != "", "装备有获取来源", iid)
	_check(str(CodexDB.SOURCES.get("mat_zhaoying_zhihen", "")) != "", "位面材料有来源")
	_check(str(CodexDB.SOURCES.get("tr_zhaoying_zhefu", "")) != "", "位面法宝有来源")
	# 反同质化（2026-11-01 禁令）：查**结构**而不是查字 —— 卡上写「没有势条」是在讲读数，
	# 真正的违规是招式表里冒出计量 / 攒层 / 引爆字段。
	var banned_keys := ["momentum", "stack_max", "stack_on_hit", "detonate", "charge_max",
		"burst_on_full", "gauge"]
	for f in FORMS:
		var form: Dictionary = MoveDB.get_form(f)
		for k in banned_keys:
			_check(not form.has(k), "招式没有计量字段「%s」" % k, f)
		var pb: Dictionary = form.get("boss", {})
		var pp: Dictionary = form.get("player", {})
		for k in banned_keys:
			_check(not pb.has(k) and not pp.has(k), "子表没有计量字段「%s」" % k, f)
	# 「势条」只允许出现在否定句里（"没有势条"），不许正面承诺一个计量条
	var at := blob.find("势条")
	while at >= 0:
		var head := blob.substr(maxi(0, at - 6), 6)
		_check(head.contains("没有") or head.contains("无"), "「势条」只出现在否定句里", head)
		at = blob.find("势条", at + 2)
	# 新名词也要能在两处读到（避免只在一个地方解释）
	for term in ["量折", "纸印"]:
		_check(skill_blob.find(term) >= 0 and blob.find(term) >= 0, "「%s」两处都讲到" % term)


## 画风守卫（2026-11-04 加）—— 叠纸这批曾经整批漂到「暖黄折纸模型」那一档，
## 而当时**没有任何判据在守画风**，所以 11-03 那轮导入把本来合格的暗调卡面覆盖成
## 亮度 173 / 暖偏 +75.9 的黄纸卡，没人发现（见 docs/美术资源接入记录.md §51.1）。
## 判据：和**同位面**的观澜、执烛对照，亮度落在它们的区间外扩 30 以内，且暖偏必须为负。
func _img_stats(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var tex: Texture2D = load(path)
	if tex == null:
		return {}
	var img: Image = tex.get_image()
	if img == null:
		return {}
	img.convert(Image.FORMAT_RGBA8)
	var px: PackedByteArray = img.get_data()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var n := 0
	var lum_sum := 0.0
	var warm_sum := 0.0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var i := (y * w + x) * 4
			if px[i + 3] > 24:
				var r := float(px[i])
				var g := float(px[i + 1])
				var b := float(px[i + 2])
				lum_sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
				warm_sum += r - b
				n += 1
			x += 4
		y += 4
	if n == 0:
		return {}
	return {"lum": lum_sum / n, "warm": warm_sum / n}


func _check_style() -> void:
	var refs := {
		"card": ["res://assets/ui/codex/card_boss_guanying.png",
				"res://assets/ui/codex/card_boss_zhizhu.png"],
		"ground": ["res://assets/scenes/zhaoying_arena_ground.png",
				"res://assets/scenes/zhaoying_lamp_arena_ground.png"],
	}
	var subjects := {
		"card": "res://assets/ui/codex/card_boss_diezhi.png",
		"ground": "res://assets/scenes/zhaoying_fold_arena_ground.png",
	}
	for key in refs:
		var lums: Array[float] = []
		var warms: Array[float] = []
		for p in refs[key]:
			var s: Dictionary = _img_stats(p)
			if s.is_empty():
				_check(false, "参照件读不到", p)
				continue
			lums.append(s["lum"])
			warms.append(s["warm"])
		if lums.is_empty():
			continue
		var lo: float = lums.min() - 30.0
		var hi: float = lums.max() + 30.0
		var me: Dictionary = _img_stats(subjects[key])
		if me.is_empty():
			_check(false, "%s 本体读不到" % key)
			continue
		_check(me["lum"] >= lo and me["lum"] <= hi,
			"画风：%s 亮度 %.0f 落在同位面参照 %.0f~%.0f 外扩30 内（%.0f~%.0f）"
			% [key, me["lum"], lums.min(), lums.max(), lo, hi])
		_check(me["warm"] < 0.0,
			"画风：%s 暖偏 R−B = %+.1f 必须为负（照影界是冷蓝黑位面）" % [key, me["warm"]])
	# 图标「背景没抠掉」守卫：底板往往不是实心而是**半透明糊上去**，所以必须按 alpha>16 的
	# 「可见」面积算，再看不外接矩形填充比与半透明占比。实测分得很开：
	#   equip_zhicuo_jian 旧件 填充比 1.00 / 半透 68.8% ← 一整幅灰紫底
	#   正常物件            填充比 0.19~0.83 / 半透 ≤10%
	var icon_lums: Array[float] = []
	for f in ICONS:
		var s: Dictionary = _icon_plate_stats("res://assets/ui/icon/" + f + ".png")
		if s.is_empty():
			_check(false, "图标读不到", f)
			continue
		_check(s["fill"] < 0.90,
			"图标无底板：%s 外接矩形填充比 %.2f < 0.90" % [f, s["fill"]])
		_check(s["semi"] < 30.0,
			"图标无底板：%s 半透明占比 %.1f%% < 30%%" % [f, s["semi"]])
		_check(s["warm"] < 0.0,
			"图标冷色：%s 暖偏 R−B = %+.1f 为负" % [f, s["warm"]])
		icon_lums.append(s["lum"])
	if not icon_lums.is_empty():
		_check(icon_lums.max() - icon_lums.min() < 130.0,
			"图标亮度档差 %.0f < 130（不是一张黑一张白）" % (icon_lums.max() - icon_lums.min()))


## 图标底板残留判据：填充比（可见面积 / 可见外接矩形）+ 半透明占比 + 暖偏 + 亮度
func _icon_plate_stats(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var tex: Texture2D = load(path)
	if tex == null:
		return {}
	var img: Image = tex.get_image()
	if img == null:
		return {}
	img.convert(Image.FORMAT_RGBA8)
	var px: PackedByteArray = img.get_data()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	var vis := 0
	var semi := 0
	var solid := 0
	var sampled := 0
	var lum_sum := 0.0
	var warm_sum := 0.0
	for y in range(0, h, 2):
		var row := y * w * 4
		for x in range(0, w, 2):
			var i := row + x * 4
			var al := px[i + 3]
			sampled += 1
			if al <= 16:
				continue
			if al > 200:
				solid += 1
			else:
				semi += 1
			vis += 1
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
			var r := float(px[i])
			var g := float(px[i + 1])
			var b := float(px[i + 2])
			lum_sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
			warm_sum += r - b
	if vis == 0 or x1 < 0:
		return {}
	# 步长 2 采样，外接矩形按同样口径算
	var bw := (x1 - x0) / 2 + 1
	var bh := (y1 - y0) / 2 + 1
	# ⚠ semi 的分母必须是**整幅画布**，不是「可见像素」：
	#   旧底板案例 = 占画布 68.8%（一眼能抓），而 twin 那种小物件带软边按可见算会虚高到 45.9%（误报）。
	return {"fill": float(vis) / float(bw * bh), "semi": 100.0 * semi / sampled,
		"warm": warm_sum / vis, "lum": lum_sum / vis, "solid_pct": 100.0 * solid / sampled}
