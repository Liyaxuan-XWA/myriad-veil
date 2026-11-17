extends Node2D
## 玩家侧阵旗对齐自检（2026-10-28）：逐条对照 BOSS 版口径
## 用法：godot --headless --path . tools/probe_player_array.tscn

class WorldHost extends Node2D:
	## 与 secret_world.gd 同口径：半尺寸 + 世界矩形中心
	var arena_half_extents := Vector2(2780.0, 3582.5)
	var arena_center := Vector2(3000.0, 0.0)


class DummyBoss extends Node2D:
	var hits: Array = []
	var debuffs: Array = []
	var stuns: Array = []
	var state: int = 0
	func take_damage(amount: float, _source: Node = null, _kind: String = "physical",
			_element: String = "", _from_projectile: bool = false) -> void:
		hits.append(amount)
	func take_knockback(_impulse: Vector2) -> void:
		pass
	func apply_debuff(id: String, duration: float) -> bool:
		debuffs.append([id, duration])
		return true
	func has_debuff(id: String) -> bool:
		for d in debuffs:
			if String((d as Array)[0]) == id:
				return true
		return false
	func stagger_for(seconds: float) -> void:
		if state == BossBase.BossState.STAGGER:
			return
		state = BossBase.BossState.STAGGER
		stuns.append(seconds)

var _player: Node2D
var _boss: DummyBoss
var _fails: Array = []
var _passes := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 玩家侧阵旗对齐探针 ##########")
	await get_tree().process_frame
	_boss = DummyBoss.new()
	_boss.add_to_group("boss")
	_boss.global_position = Vector2(300, 0)
	add_child(_boss)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector2.ZERO
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.is_teleporting = false
	_player.invincible_timer = 0.0
	_player.auto_parry_timer = 0.0
	for sid in ["skill_array_plant", "skill_array_line", "skill_array_pull",
			"skill_array_seal", "skill_array_sweep", "skill_array_step",
			"skill_array_pile", "skill_array_burst"]:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	_player._refresh_array_unlock()
	await _check_cast_path()
	_run()
	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _count_labels(text: String) -> int:
	var n := 0
	for c in get_children():
		if c is Label and String((c as Label).text) == text:
			n += 1
	return n


func _count_labels_containing(text: String) -> int:
	var n := 0
	for c in get_children():
		if c is Label and String((c as Label).text).contains(text):
			n += 1
	return n


func _count_decal() -> int:
	var n := 0
	for c in get_children():
		if c is Sprite2D:
			var tex := (c as Sprite2D).texture
			if tex != null and String(tex.resource_path).contains("array_decal"):
				n += 1
	return n


## 真实施放入口：前摇里只预告 / 落点绕目标 / 满 5 面被门禁拦下且不扣灵力
func _check_cast_path() -> void:
	var p = _player
	p._clear_array_flags()
	p.mana = p.max_mana
	p.skill_cooldowns.clear()
	var ok: bool = p.try_use_skill("skill_array_plant")
	_check(ok, "try_use_skill 能放出插旗")
	_check(p.array_flags.is_empty() and p._array_pending_pos != Vector2.INF,
		"前摇内只有落点预告、旗还没插下")
	await get_tree().create_timer(0.45, true, false, true).timeout
	_check(p.array_flags.size() == 1, "前摇结束落旗", "flags=%d" % p.array_flags.size())
	if p.array_flags.size() == 1:
		_check(p.array_flags[0].global_position.distance_to(p.global_position) < 5.0,
			"插旗落在玩家脚下", str(p.array_flags[0].global_position))
	p._clear_array_flags()
	for i in 5:
		p._plant_array_flag(Vector2(i * 20.0, 0.0), ArrayFlag.Kind.ATTACK)
	p.mana = p.max_mana
	p.skill_cooldowns.clear()
	var mana_before: float = p.mana
	var ok2: bool = p.try_use_skill("skill_array_plant")
	_check(not ok2 and is_equal_approx(p.mana, mana_before),
		"阵位满 5 时插旗被门禁拦、不扣灵力", "mana=%.1f" % p.mana)
	p._clear_array_flags()

	# 通用重复跳不得再结算封阵（专属 handler 自己排 4 跳）
	for pos in [Vector2(-100, 0), Vector2(0, -100), Vector2(100, 0), Vector2(0, 100)]:
		p._plant_array_flag(pos, ArrayFlag.Kind.ATTACK)
	_boss.global_position = Vector2.ZERO
	_boss.hits.clear()
	p._skill_tick_repeats("skill_array_seal",
		MoveDB.resolve_player("form_array_seal"), Vector2.RIGHT)
	await get_tree().create_timer(0.05, true, false, true).timeout
	_check(_boss.hits.is_empty(), "封阵不再被通用循环重复结算",
		"hits=%d" % _boss.hits.size())
	p._clear_array_flags()


func _run() -> void:
	var p = _player
	print("-- 插旗：5 面上限 / 绕目标 / 报招名 / 三色布面")
	p._clear_array_flags()
	var names_before := _count_labels("插旗·定星")
	p._array_precast("skill_array_plant", Vector2.RIGHT)
	_check(_count_labels("插旗·定星") == names_before + 1, "起手报招名")
	_check(_count_decal() >= 1, "布点同色阵纹预告")
	for i in 6:
		p._array_handle_cast("skill_array_plant", Vector2.RIGHT)
	_check(p.array_flags.size() == 5, "插旗上限 5（第 6 面插不下）", "size=%d" % p.array_flags.size())
	var f0 = p.array_flags[0]
	_check(f0.get("life") == null, "旗不再有自然寿命（永久）")
	var tex_path := String((f0._spr.texture as Texture2D).resource_path)
	_check(tex_path.contains("array_flag_red") or tex_path.contains("array_flag_ink")
			or tex_path.contains("array_flag_blue"), "玩家旗使用三色布面", tex_path)
	_check(p._array_segments().size() == 5, "5 面旗 = 4 段 + 首尾收口", "seg=%d" % p._array_segments().size())
	p._tick_array_flags(0.016)
	_check(p._array_line_visuals.size() == 5, "常驻阵线：5 段 × 单根", "vis=%d" % p._array_line_visuals.size())

	print("-- 引阵：全部旗段 / 半段结算 / 不消耗旗")
	p._clear_array_flags()
	var fa = p._plant_array_flag(Vector2(0, 0), ArrayFlag.Kind.ATTACK)
	p._plant_array_flag(Vector2(200, 0), ArrayFlag.Kind.ATTACK)
	p._tick_array_flags(0.016)
	_boss.global_position = Vector2(100, 0)
	_boss.hits.clear()
	p._array_handle_cast("skill_array_line", Vector2.RIGHT)
	_check(p.array_flags.size() == 2, "引阵不消耗旗", "flags=%d" % p.array_flags.size())
	_check(_boss.hits.size() == 1, "引阵整段命中（单线结算）", "hits=%d" % _boss.hits.size())
	_check(p._array_line_visuals.size() == 1, "两旗一段 → 一根阵线", "vis=%d" % p._array_line_visuals.size())

	print("-- 卷阵：卷到身侧 / 不撤旗")
	_boss.global_position = Vector2(300, 0)
	_boss.hits.clear()
	p._array_handle_cast("skill_array_pull", Vector2.RIGHT)
	_check(p.array_flags.size() == 2, "卷阵不撤旗")
	_check(fa.global_position.distance_to(p.global_position) < 130.0,
		"卷阵把旗卷到身侧", str(fa.global_position))

	print("-- 封阵：四面旗 / 多数色 / 四跳 / 守牢减伤 70%")
	p._clear_array_flags()
	for pos in [Vector2(-100, 0), Vector2(0, -100), Vector2(100, 0), Vector2(0, 100)]:
		p._plant_array_flag(pos, ArrayFlag.Kind.ATTACK)
	_boss.global_position = Vector2(0, 0)
	_boss.hits.clear()
	p._array_handle_cast("skill_array_seal", Vector2.RIGHT)
	_check(p.array_flags.size() == 4, "封阵不撤旗")
	_check(_boss.hits.size() >= 1, "封阵首跳命中（阵心 210 内）", "hits=%d" % _boss.hits.size())
	for f in p.array_flags:
		f.kind = ArrayFlag.Kind.GUARD
	_boss.global_position = Vector2(1000, 0)
	p._array_handle_cast("skill_array_seal", Vector2.RIGHT)
	_check(p._array_seal_guard_left > 2.0, "守牢 2.2 秒减伤窗口", "left=%.2f" % p._array_seal_guard_left)
	p.hp = p.max_hp
	p.invincible_timer = 0.0
	p._array_seal_guard_left = 0.0
	var hp0: float = p.hp
	p.take_damage(10.0, "elemental")
	var d0: float = hp0 - p.hp
	p.hp = p.max_hp
	p.invincible_timer = 0.0
	p._array_seal_guard_left = 2.0
	p._array_seal_guard_pct = 0.70
	var hp1: float = p.hp
	p.take_damage(10.0, "elemental")
	var d1: float = hp1 - p.hp
	_check(d0 > 0.0 and absf(d1 / d0 - 0.30) < 0.05, "守牢减伤 70%", "%.3f → %.3f" % [d0, d1])

	print("-- 封阵·四象：困牢眩晕 5 秒 / 守牢 10 秒且破旗即散")
	p._clear_array_flags()
	for pos in [Vector2(-100, 0), Vector2(0, -100), Vector2(100, 0), Vector2(0, 100)]:
		p._plant_array_flag(pos, ArrayFlag.Kind.BIND)
	_boss.global_position = Vector2.ZERO
	_boss.stuns.clear()
	p._array_seal_tick(ArrayFlag.Kind.BIND, Vector2.ZERO, 0.0, true)
	_check(_boss.stuns.size() == 1 and is_equal_approx(float(_boss.stuns[0]), 5.0),
		"困牢：5 秒眩晕", str(_boss.stuns))
	p._array_seal_tick(ArrayFlag.Kind.BIND, Vector2.ZERO, 0.0, true)
	_check(_boss.stuns.size() == 1, "持续眩晕中不重复刷新")
	p._clear_array_flags()
	for pos in [Vector2(-100, 0), Vector2(0, -100), Vector2(100, 0), Vector2(0, 100)]:
		p._plant_array_flag(pos, ArrayFlag.Kind.GUARD)
	p._array_start_seal(ArrayFlag.Kind.GUARD, Vector2.ZERO)
	_check(is_equal_approx(p._array_seal_guard_left, 10.0), "守牢：10 秒",
		"left=%.1f" % p._array_seal_guard_left)
	var broke = p.array_flags[0]
	broke._dead = true
	p._tick_array_flags(0.016)
	_check(is_equal_approx(p._array_seal_guard_left, 0.0), "破旗瞬间结束守牢",
		"left=%.1f" % p._array_seal_guard_left)
	p._clear_array_flags()

	print("-- 封阵牢型：起手报多数色（困/守牢无伤要说清）")
	p._clear_array_flags()
	for i in 4:
		p._plant_array_flag(Vector2(float(i) * 20.0, 0.0), ArrayFlag.Kind.ATTACK)
	var atk_before := _count_labels_containing("攻牢")
	p._array_precast("skill_array_seal", Vector2.RIGHT)
	_check(_count_labels_containing("攻牢") == atk_before + 1, "攻牢起手报型")
	for f in p.array_flags:
		f.kind = ArrayFlag.Kind.BIND
	var bind_before := _count_labels_containing("困牢")
	p._array_precast("skill_array_seal", Vector2.RIGHT)
	_check(_count_labels_containing("困牢") == bind_before + 1, "困牢起手报型（无伤）")
	for f in p.array_flags:
		f.kind = ArrayFlag.Kind.GUARD
	var guard_before := _count_labels_containing("守牢")
	p._array_precast("skill_array_seal", Vector2.RIGHT)
	_check(_count_labels_containing("守牢") == guard_before + 1, "守牢起手报型（无伤）")

	print("-- 解阵：每面旗 140 内结算 / 清场")
	for f in p.array_flags:
		f.kind = ArrayFlag.Kind.ATTACK
	p._array_seal_guard_left = 0.0
	_boss.global_position = Vector2(0, 0)
	_boss.hits.clear()
	p._array_handle_cast("skill_array_burst", Vector2.RIGHT)
	_check(p.array_flags.is_empty(), "解阵清空全部旗")
	_check(p._array_line_visuals.is_empty(), "解阵清空常驻阵线")
	_check(_boss.hits.size() == 4, "解阵：每面攻旗各命中一次", "hits=%d" % _boss.hits.size())

	print("-- 插旗落点：玩家当前坐标")
	p._clear_array_flags()
	p.global_position = Vector2(321.0, 123.0)
	p._array_handle_cast("skill_array_plant", Vector2.RIGHT)
	_check(p.array_flags.size() == 1, "脚下落旗成功", "flags=%d" % p.array_flags.size())
	if p.array_flags.size() == 1:
		_check(p.array_flags[0].global_position.distance_to(p.global_position) < 1.0,
			"旗坐标 = 玩家当前坐标", str(p.array_flags[0].global_position))
	p.global_position = Vector2.ZERO

	print("-- 大世界：插旗按世界中心钳制，不甩到原点附近")
	var host := WorldHost.new()
	add_child(host)
	p.reparent(host)
	p.global_position = Vector2(5110.0, 3270.0)
	p._clear_array_flags()
	p._array_handle_cast("skill_array_plant", Vector2.RIGHT)
	_check(p.array_flags.size() == 1, "大世界脚下落旗成功", "flags=%d" % p.array_flags.size())
	if p.array_flags.size() == 1:
		var fp: Vector2 = (p.array_flags[0] as Node2D).global_position
		_check(fp.distance_to(p.global_position) < 1.0, "大世界插旗不甩到原点附近", str(fp))
	# 贴边：玩家本体在墙内，插旗不能再被“战场内缩”二次钳制到几十像素外
	p.global_position = Vector2(5760.0, 3560.0)
	p._clear_array_flags()
	p._array_handle_cast("skill_array_plant", Vector2.RIGHT)
	var edge_pos := Vector2.INF
	if not p.array_flags.is_empty():
		edge_pos = (p.array_flags[0] as Node2D).global_position
	_check(p.array_flags.size() == 1 and edge_pos.distance_to(p.global_position) < 1.0,
		"贴边插旗仍落在脚下", str(edge_pos))
	p._clear_array_flags()
	p.reparent(self)
	p.global_position = Vector2.ZERO
	host.queue_free()

	print("-- 规则：旗不自然消失 / BOSS 旗三次打掉")
	p._clear_array_flags()
	var bf := ArrayFlag.new()
	bf.setup(true, true, ArrayFlag.Kind.ATTACK)
	add_child(bf)
	bf.global_position = Vector2(-300, 0)
	bf.take_hit(1.0)
	bf.take_hit(1.0)
	_check(not bf._dead and bf.hits_left == 1, "BOSS 旗两下还在", "left=%d" % bf.hits_left)
	bf.take_hit(1.0)
	_check(bf._dead, "第三次打掉")

	print("-- 功法库文案（阵旗八式）")
	for sid in ["skill_array_plant", "skill_array_line", "skill_array_pull",
			"skill_array_seal", "skill_array_sweep", "skill_array_step",
			"skill_array_pile", "skill_array_burst"]:
		print(sid, " => ", SkillDB._array_texts_for(SkillDB.get_skill(sid)))
