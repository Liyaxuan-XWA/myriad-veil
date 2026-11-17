extends Node

func _ready() -> void:
	var L := []
	L.append("SCRIPTS gd=%d lines=%d tscn=%d" % [
		_count("res://scripts", ".gd"), _lines("res://scripts"), _count("res://scenes", ".tscn")])
	L.append("TOOLS probe_tscn=%d py=%d" % [_count("res://tools", "probe_", ".tscn"), _count("res://tools", ".py")])
	L.append("SHADERS gdshader=%d icon_png=%d docs_md=%d" % [
		_count("res://assets/shaders", ".gdshader"), _count("res://assets/ui/icon", ".png"),
		_count("res://docs", ".md")])
	L.append("RIGS boss_rig_*.gd=%d rig.tres=%d" % [
		_count("res://scripts/visual", "boss_rig_", ".gd"), _count("res://assets", "rig.tres")])
	L.append("ASSETS 正式资源=%d（不含 .import/.uid）" % _count_assets("res://assets"))

	L.append("WorldDB DOMAINS=%d floors=%d BOSS_SCENES=%d BOSS_NAMES=%d BOSS_MOVES=%d" % [
		WorldDB.DOMAINS.size(), WorldDB.get_floors().size(),
		WorldDB.BOSS_SCENES.size(), WorldDB.BOSS_NAMES.size(), WorldDB.BOSS_MOVES.size()])

	var act := 0
	var pas := 0
	var no_icon := 0
	for s in SkillDB.SKILLS:
		if String(s.get("skill_type", "")) == "passive":
			pas += 1
		else:
			act += 1
		if String(s.get("icon", "")) == "":
			no_icon += 1
	L.append("SkillDB SKILLS=%d (主动%d/被动%d) 无图标=%d" % [SkillDB.SKILLS.size(), act, pas, no_icon])
	L.append("MoveDB FORMS=%d" % MoveDB.FORMS.size())
	L.append("ItemDB 材料=%d 装备=%d 法宝=%d 丹方=%d 掉落表=%d 突破=%d 元魂合成=%d 位面法宝=%d" % [
		ItemDB.MATERIALS.size(), ItemDB.EQUIPMENT_TEMPLATES.size(), ItemDB.TREASURE_TEMPLATES.size(),
		ItemDB.PILL_RECIPES.size(), ItemDB.DROP_TEMPLATES.size(),
		ItemDB.BREAKTHROUGH_REQUIREMENTS.size(), ItemDB.SYNTH_RECIPES.size(),
		ItemDB.PLANE_TREASURE_RECIPES.size()])
	L.append("TalismanDB BASES=%d VARIANTS=%d" % [TalismanDB.BASES.size(), TalismanDB.VARIANTS.size()])
	L.append("AttributeDB ATTRS=%d ELEMENTS=%d" % [AttributeDB.ATTRS.size(), AttributeDB.ELEMENTS.size()])
	L.append("BuffDB BUFFS=%d DebuffDB DEBUFFS=%d" % [BuffDB.BUFFS.size(), DebuffDB.DEBUFFS.size()])
	L.append("SecretWorldDB REGIONS=%d BEASTS=%d CORE_BOSS=%d" % [
		SecretWorldDB.REGIONS.size(), SecretWorldDB.BEASTS.size(), SecretWorldDB.CORE_BOSS.size()])
	L.append("CodexDB BOSS_CODEX=%d HOLO_CARDS=%d SOURCES=%d" % [
		CodexDB.BOSS_CODEX.size(), CodexDB.HOLO_CARDS.size(), CodexDB.SOURCES.size()])
	L.append("MatchDB CARD_POOL=%d" % MatchDB.CARD_POOL.size())
	var pool_total := 0
	for k in RogueDB.POOLS:
		pool_total += (RogueDB.POOLS[k] as Array).size()
	L.append("RogueDB 流派池=%d 张 / %d 套 FAMILY_START=%d BOSS_POOL=%d" % [
		pool_total, RogueDB.POOLS.size(), RogueDB.START_FAMILIES.size(), RogueDB.BOSS_POOL.size()])
	L.append("ArtDB VISUALS=%d EFFECTS=%d SKILL_FX=%d BOSS_MOVE_ANIMS=%d" % [
		ArtDB.VISUALS.size(), ArtDB.EFFECTS.size(), ArtDB.SKILL_FX.size(), ArtDB.BOSS_MOVE_ANIMS.size()])
	L.append("Save SAVE_VERSION=%d SLOT_COUNT=%d AUTO=%d" % [
		SaveManager.SAVE_VERSION, SaveManager.SLOT_COUNT, SaveManager.AUTO_SLOT_COUNT])
	L.append("CharacterData REALM_ORDER=%d 装备槽=%d 主动槽=%d 被动槽=%d" % [
		CharacterData.REALM_ORDER.size(), CharacterData.equipment_slots.size(),
		CharacterData.MAX_ACTIVE_SKILLS, CharacterData.MAX_PASSIVE_SKILLS])
	L.append("QuestDB QUESTS=%d TutorialDB 章=%d GuideDB 章=%d" % [
		QuestDB.QUESTS.size(), TutorialDB.CHAPTERS.size(), GuideDB.CHAPTERS.size()])

	for line in L:
		print(line)
	get_tree().quit(0)

func _count(dir_path: String, a: String, b := "") -> int:
	var n := 0
	var da := DirAccess.open(dir_path)
	if da == null:
		return -1
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if da.current_is_dir():
			if not f.begins_with("."):
				n += _count(dir_path.path_join(f), a, b)
		else:
			var hit := f.ends_with(b) if b != "" else f.ends_with(a)
			if hit and (b == "" or f.contains(a)):
				n += 1
		f = da.get_next()
	da.list_dir_end()
	return n

func _count_assets(dir_path: String) -> int:
	var n := 0
	var da := DirAccess.open(dir_path)
	if da == null:
		return -1
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if da.current_is_dir():
			if not f.begins_with("."):
				n += _count_assets(dir_path.path_join(f))
		elif not f.ends_with(".import") and not f.ends_with(".uid"):
			n += 1
		f = da.get_next()
	da.list_dir_end()
	return n

func _lines(dir_path: String) -> int:
	var total := 0
	var da := DirAccess.open(dir_path)
	if da == null:
		return -1
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if da.current_is_dir():
			if not f.begins_with("."):
				total += _lines(dir_path.path_join(f))
		elif f.ends_with(".gd"):
			var fhl := FileAccess.open(dir_path.path_join(f), FileAccess.READ)
			if fhl != null:
				# 只数换行符，口径与 `wc -l` 一致（eof_reached + get_line 每文件会多数 1 行）
				total += fhl.get_as_text().count("\n")
				fhl.close()
		f = da.get_next()
	da.list_dir_end()
	return total
