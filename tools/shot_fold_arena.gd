extends Node
## 叠纸 · 素纸战场真实箱庭截图（2026-11-02）
## 看的是「玩家可见面」：
##   1) 地面亮度与袍体反差（这条是执烛场地重做的教训：地面中位 19 时影子和剪影同时看不见）
##   2) 折痕本体读不读得出「纸吃光的棱」，而不是激光线
##   3) 两端圆牌的配对（同色 + 同点数 + 朝内的箭头）在屏幕上认不认得出是一对
##   4) 八式特效彼此分不分得开、和影族/镜族分不分得开
##   5) 二阶段两条痕（三个互通区）在场上一眼能不能数清
##   6) 玩家侧裁痕：自己那道痕与 BOSS 那条痕在画面上分得开吗
## 用法：godot --path . --resolution 1280x720 res://tools/shot_fold_arena.tscn -- --no-save

const FORMS := [
	["form_fold_press", 0.20],
	["form_fold_trace", 0.20],
	["form_fold_stride", 0.22],
	["form_fold_pressmark", 0.24],
	["form_fold_shroud", 0.20],
	["form_fold_tear", 0.26],
	["form_fold_twin", 0.22],
	["form_fold_triple", 0.30],
]

var _player: Node2D
var _boss: Node2D


## 折痕场状态转储：痕有几条、视觉节点在不在树里、alpha 多少、两端在哪
func _dump_field(tag: String) -> void:
	var fld = _boss._field
	if fld == null:
		print("  DUMP %s: field=null" % tag)
		return
	print("  DUMP %s phase=%d spans=%d seams=%d visual=%d down=%.2f preview=%.2f" % [
		tag, int(fld.phase), (fld.spans as Array).size(), fld._seams.size(),
		fld._visuals.size(), float(fld._down_left), float(fld._preview_left)])
	for i in fld._visuals.size():
		var vv = fld._visuals[i]
		print("     vis[%d] in_tree=%s visible=%s pos=%s alpha=%s span=%s" % [
			i, vv.is_inside_tree(), str((vv as CanvasItem).visible),
			str((vv as Node2D).global_position), str(vv.get("_alpha")),
			str(vv.get("span_dbg") if vv.has_method("get") else "")])
		var core = vv.get("_core")
		if core != null:
			print("        core a=%.2f scale=%s tex=%s" % [
				(core as Sprite2D).modulate.a, str((core as Sprite2D).scale),
				str((core as Sprite2D).texture)])


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/" + name)
	print("SHOT output/", name)


## 亮度体检：地面 / 袍体 / 折痕三档必须拉得开，否则等于没做区分
func _grade_report(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var floor_sum := 0.0
	var floor_n := 0
	var floor_dark := 0
	for y in range(int(h * 0.55), h - 20, 7):
		for x in range(20, w - 20, 7):
			var c := img.get_pixel(x, y)
			var l := (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * 255.0
			floor_sum += l
			floor_n += 1
			if l < 24.0:
				floor_dark += 1
	var avg := floor_sum / maxf(float(floor_n), 1.0)
	print("  %s 地面平均 %.0f · 近黑 %.1f%%" % [tag, avg,
			100.0 * float(floor_dark) / maxf(float(floor_n), 1.0)])


func _ready() -> void:
	CharacterData.current_realm = "元婴"
	CharacterData.realm_stage = 3
	for sid in ["skill_fold_press", "skill_fold_trace", "skill_fold_stride",
			"skill_fold_seam", "skill_fold_shroud", "skill_fold_tear",
			"skill_fold_twin", "skill_fold_triple", "skill_fold_measure"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
	CharacterData.active_skill_loadout = ["skill_fold_press", "skill_fold_seam",
		"skill_fold_trace", "skill_fold_stride"]
	CharacterData.passive_skill_loadout = ["skill_fold_measure"]
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_04",
		"boss_id": "boss_04_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 8:
		await get_tree().process_frame
	_player = arena.player
	_boss = arena.boss
	if _player == null or _boss == null:
		print("FAIL 玩家或 BOSS 未生成")
		get_tree().quit(1)
		return
	_player.invincible_timer = 1.0e9
	_boss.current_hp = _boss.max_hp * 0.9

	# ---- 1. 静帧：地面 + 折痕 + 两端圆牌 + 剪影 ----
	await _settle(0.4)
	_dump_field("静帧")
	await _shot("z3_idle.png")
	_grade_report("静帧")

	# ---- 2. 八式逐招 ----
	for row in FORMS:
		await _cast_and_shoot(String(row[0]), float(row[1]))

	# ---- 3. 二阶段：两条痕、三个互通区 ----
	_boss.current_hp = _boss.max_hp * 0.45
	_boss.take_damage(1.0, _player, "physical", "water")
	await _settle(2.0)
	_dump_field("二阶段")
	await _shot("z3_phase2_two_creases.png")
	_grade_report("二阶段")

	# ---- 4. 押痕：痕压到两者正中，玩家的对位落点就在 BOSS 脚下 ----
	_boss._field.set_phase(1)
	_boss._field.rebuild_near(_player.global_position)
	_player.global_position = _boss.global_position + Vector2(300.0, 120.0)
	await _settle(0.3)
	_boss._begin(FORMS[3][0])
	await _settle(0.9)
	await _shot("z3_pressmark_bisect.png")

	# ---- 5. 玩家侧裁痕：自己的那道痕 + 双落点 ----
	_player._fold_reset()
	_player.skill_cooldowns.clear()
	_player.mana = _player.max_mana
	_player.attack_dir = (_boss.global_position - _player.global_position).normalized()
	_player.try_use_skill("skill_fold_seam")
	await _settle(0.4)
	await _shot("z3_player_seam.png")

	# ---- 6. 穿缝反馈：把玩家放到圆牌上，等它被送到对侧 ----
	var fld = _boss._field
	if fld != null and fld._seams.size() > 0:
		fld._exit_guard.clear()
		fld._re_cd.clear()
		_player.global_position = (fld._seams[0] as Node2D).global_position
		await _settle(0.16)
		await _shot("z3_seam_cross.png")
	print("DONE")
	get_tree().quit(0)


func _settle(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().create_timer(0.05).timeout
		t += 0.05
		if _player != null and is_instance_valid(_player):
			_player.invincible_timer = 1.0e9
			_player.hp = _player.max_hp


## 强制出一招并在特效 lifetime 内抓帧
func _cast_and_shoot(form_id: String, delay: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_player.global_position = _boss.global_position + Vector2(230.0, 60.0)
	await _settle(0.35)
	_boss._cools.clear()
	_boss.state = BossBase.BossState.IDLE
	_boss._current_skill = ""
	_boss._begin(form_id)
	await _settle(delay)
	var short := form_id.replace("form_fold_", "")
	await _shot("z3_%s.png" % short)
	await _settle(0.7)
