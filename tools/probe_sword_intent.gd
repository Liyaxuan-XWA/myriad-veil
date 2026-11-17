extends Node2D
## 剑心通明探针（2026-11-01）：
## 被动登记 / 塔池 / 图标 / 文案；每层剑意增伤只作用于物理功法；
## 所有物理近战功法可积攒剑意（非剑客四式也吃），投射物 / 法术 / 大招不积攒；
## 大招照常清空；普攻与法术不吃增伤；唯一被动槽不变。
## 用法：godot --headless --path . tools/probe_sword_intent.tscn -- --no-save

var _passes := 0
var _fails: Array = []
var _p: Node2D
var _dummy: Node2D


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _set_intent(p: Node2D, n: int) -> void:
	p.sword_intent = n
	p._sync_sword_intent_skill_mult()


func _cast_intent(p: Node2D, sid: String, start: int) -> int:
	_set_intent(p, start)
	p.skill_cooldowns.clear()
	p.stamina = 99
	p.mana = 999.0
	p._cast_skill(sid)
	return int(p.sword_intent)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("\n########## 剑心通明探针 ##########")
	var saved_learned: Array = CharacterData.learned_skills.duplicate()
	var saved_active: Array = CharacterData.active_skill_loadout.duplicate()
	var saved_passive: Array = CharacterData.passive_skill_loadout.duplicate()
	var saved_mult: float = CharacterData.sword_intent_skill_mult

	var ids := [
		"skill_sword_intent", "skill_sword_stab", "skill_sword_chop",
		"skill_sword_cloud", "skill_sword_pierce", "skill_sword_myriad",
		"skill_sword_heaven", "skill_tiger_claw", "skill_tiger_rock",
		"skill_yinyang_finger", "skill_mirror_shatter",
	]
	CharacterData.learned_skills = ids.duplicate()
	CharacterData.active_skill_loadout = ids.duplicate()
	CharacterData.passive_skill_loadout = []

	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_p)
	_p.global_position = Vector2.ZERO
	_p.set_physics_process(false)
	_p.set_process(false)
	_p.is_teleporting = false
	_p.invincible_timer = 0.0
	_dummy = (load("res://scenes/combat/training_dummy.tscn") as PackedScene).instantiate()
	add_child(_dummy)
	_dummy.global_position = Vector2(80.0, 0.0)
	await get_tree().process_frame

	# 1) 数据 / 塔池 / 图标 / 文案
	var sk := SkillDB.get_skill("skill_sword_intent")
	_check(not sk.is_empty() and String(sk.get("skill_name", "")) == "剑心通明",
		"被动已登记")
	_check(String(sk.get("skill_type", "")) == SkillDB.TYPE_PASSIVE
		and String(sk.get("form_id", "")) == "",
		"是被动且没有招式形态")
	_check(String(sk.get("source_boss_id", "")) == "boss_01_c"
		and String(sk.get("tower_projection_id", "")) == "proj_boss_01_c",
		"来源剑客 / 塔第 3 层投影", str(sk.get("source_boss_id", "")))
	_check(String(sk.get("passive_effect", "")) == "sword_intent_physical",
		"passive_effect = sword_intent_physical")
	_check(WorldDB.get_boss_skill_ids("boss_01_c").has("skill_sword_intent"),
		"剑客塔层首杀池包含该被动")
	_check(CharacterData.MAX_PASSIVE_SKILLS == 1, "被动仍只能带 1 门")
	var icon_path := String(sk.get("icon", ""))
	_check(ResourceLoader.exists(icon_path), "图标已落盘", icon_path)
	if ResourceLoader.exists(icon_path):
		var tex := load(icon_path) as Texture2D
		_check(tex != null and tex.get_width() == 256 and tex.get_height() == 256,
			"图标 256×256", "%dx%d" % [tex.get_width(), tex.get_height()] if tex else "null")
	var effect_text := ""
	for e in SkillDB.get_effect_lines("skill_sword_intent"):
		effect_text += String((e as Dictionary).get("text", "")) + "\n"
	var pct := int(round(SkillDB.SWORD_INTENT_PHYS_PER_STACK * 100.0))
	_check(effect_text.contains("每层剑意") and effect_text.contains("物理功法")
		and effect_text.contains("物理近战") and effect_text.contains("唯一被动槽"),
		"被动详情写明每层增伤 / 积攒扩展 / 槽位代价")
	var rules_text := "\n".join(SkillDB.get_intent_rules())
	_check(rules_text.contains("剑心通明") and rules_text.contains("%d%%" % pct)
		and rules_text.contains("物理近战"),
		"剑意总规则卡包含被动与数值")
	var group := SkillDB.get_group_rules("boss_01_c")
	_check(String(group.get("title", "")).contains("剑意")
		and SkillDB.group_rules_text(group).contains("剑心通明"),
		"剑客组规则卡包含被动")

	# 2) 伤害乘区（被动开 / 关）
	CharacterData.passive_skill_loadout = ["skill_sword_intent"]
	_set_intent(_p, 0)
	var base := CharacterData.calc_skill_damage("skill_sword_chop", false, false)
	_set_intent(_p, 5)
	var full := CharacterData.calc_skill_damage("skill_sword_chop", false, false)
	var expected := base * (1.0 + 5.0 * SkillDB.SWORD_INTENT_PHYS_PER_STACK)
	_check(is_equal_approx(full, expected), "满 5 层物理功法 +40%",
		"base=%.1f full=%.1f expect=%.1f" % [base, full, expected])
	_set_intent(_p, 2)
	var two := CharacterData.calc_skill_damage("skill_sword_chop", false, false)
	_check(is_equal_approx(two, base * (1.0 + 2.0 * SkillDB.SWORD_INTENT_PHYS_PER_STACK)),
		"2 层按 2 层结算", "two=%.1f" % two)
	var spell_base := CharacterData.calc_skill_damage("skill_mirror_shatter", false, false)
	_set_intent(_p, 5)
	var spell_full := CharacterData.calc_skill_damage("skill_mirror_shatter", false, false)
	_check(is_equal_approx(spell_base, spell_full), "法术功法不吃增伤",
		"base=%.1f full=%.1f" % [spell_base, spell_full])
	_set_intent(_p, 0)
	var atk_base := CharacterData.calc_physical_damage(false, false, false)
	_set_intent(_p, 5)
	var atk_full := CharacterData.calc_physical_damage(false, false, false)
	_check(is_equal_approx(atk_base, atk_full), "普攻不吃增伤",
		"base=%.1f full=%.1f" % [atk_base, atk_full])
	var cloud_base := 0.0
	_set_intent(_p, 0)
	cloud_base = CharacterData.calc_skill_damage("skill_sword_cloud", false, false)
	_set_intent(_p, 5)
	var cloud_full := CharacterData.calc_skill_damage("skill_sword_cloud", false, false)
	_check(is_equal_approx(cloud_full, cloud_base * 1.4), "物理投射功法也吃增伤")

	# 3) 积攒范围
	CharacterData.passive_skill_loadout = ["skill_sword_intent"]
	_set_intent(_p, 0)
	var claw := _cast_intent(_p, "skill_tiger_claw", 0)
	_check(claw == 1, "非剑客物理近战（虎爪）释放 +1", "intent=%d" % claw)
	var stab := _cast_intent(_p, "skill_sword_stab", 1)
	_check(stab == 2, "原有剑招不重复叠加（1 → 2）", "intent=%d" % stab)
	var pierce := _cast_intent(_p, "skill_sword_pierce", 0)
	_check(pierce == 1, "剑客的穿也能被被动带出积攒", "intent=%d" % pierce)
	var rock := _cast_intent(_p, "skill_tiger_rock", 0)
	_check(rock == 0, "物理投射物不积攒", "intent=%d" % rock)
	var finger := _cast_intent(_p, "skill_yinyang_finger", 0)
	_check(finger == 0, "法术近战不积攒", "intent=%d" % finger)
	var myriad := _cast_intent(_p, "skill_sword_myriad", 4)
	_check(myriad == 0, "万剑归宗放完清空且不积攒", "intent=%d" % myriad)
	var heaven := _cast_intent(_p, "skill_sword_heaven", 3)
	_check(heaven == 0, "一剑开天（未满）清空且不积攒", "intent=%d" % heaven)
	var heaven_full := _cast_intent(_p, "skill_sword_heaven", 5)
	_check(heaven_full == 0, "满层一剑开天切换变体后清空", "intent=%d" % heaven_full)

	# 4) 被动关闭：不增伤、不扩展积攒
	CharacterData.passive_skill_loadout = []
	_set_intent(_p, 0)
	var off_base := CharacterData.calc_skill_damage("skill_sword_chop", false, false)
	_set_intent(_p, 5)
	var off_full := CharacterData.calc_skill_damage("skill_sword_chop", false, false)
	_check(is_equal_approx(off_base, off_full), "未佩戴时层数不增伤")
	var off_claw := _cast_intent(_p, "skill_tiger_claw", 0)
	_check(off_claw == 0, "未佩戴时非剑客物理近战不积攒", "intent=%d" % off_claw)
	var off_stab := _cast_intent(_p, "skill_sword_stab", 0)
	_check(off_stab == 1, "未佩戴时剑客四式照常积攒", "intent=%d" % off_stab)
	_check(is_equal_approx(CharacterData.sword_intent_skill_mult, 1.0),
		"未佩戴时全局物理功法乘区归 1", str(CharacterData.sword_intent_skill_mult))

	# 5) 真实命中：木桩总伤害随层数上升（同随机种子）
	CharacterData.passive_skill_loadout = ["skill_sword_intent"]
	var form := SkillDB.get_skill_form("skill_sword_chop")
	_set_intent(_p, 0)
	_dummy.reset_training_stats()
	seed(9001)
	_p._apply_skill_hit("skill_sword_chop", form, Vector2.RIGHT)
	var hit0 := float(_dummy.total_damage)
	_set_intent(_p, 5)
	_dummy.reset_training_stats()
	seed(9001)
	_p._apply_skill_hit("skill_sword_chop", form, Vector2.RIGHT)
	var hit5 := float(_dummy.total_damage)
	_check(hit0 > 0.0 and hit5 > hit0 * 1.25, "真实命中：满层伤害明显提高",
		"0层=%.1f 5层=%.1f" % [hit0, hit5])

	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	CharacterData.learned_skills = saved_learned
	CharacterData.active_skill_loadout = saved_active
	CharacterData.passive_skill_loadout = saved_passive
	CharacterData.sword_intent_skill_mult = saved_mult
	get_tree().quit(0 if _fails.is_empty() else 1)
