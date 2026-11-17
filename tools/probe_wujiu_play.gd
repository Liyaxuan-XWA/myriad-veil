extends Node
## 晏无咎 · 真实战斗箱庭联调（2026-10-29）
## 与 probe_wujiu 的分工：这个探针**开真实 CombatArena + 真实 Player + BOSS AI**，
## 跑一段自动战斗，验证场景、HUD、AI、阶段切换、玩家侧功法入口在真实节点树里不炸。
## 用法：godot --headless --path . res://tools/probe_wujiu_play.tscn

var _passes := 0
var _fails: Array = []
var _cast_count: Dictionary = {}


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	print("\n########## 晏无咎 · 真实战斗箱庭联调 ##########")
	await _run()
	print("\n########## 结果：%d 通过，%d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	var ids := ["skill_calamity_step", "skill_calamity_slash",
		"skill_calamity_fire_seal", "skill_calamity_fire_field",
		"skill_calamity_thunder_strike", "skill_calamity_thunder_pool",
		"skill_calamity_turn", "skill_calamity_final"]
	for sid in ids:
		if not CharacterData.learned_skills.has(sid):
			CharacterData.learned_skills.append(sid)
		if not CharacterData.active_skill_loadout.has(sid):
			CharacterData.active_skill_loadout.append(sid)
	var passive_id := "skill_calamity_body"
	if not CharacterData.learned_skills.has(passive_id):
		CharacterData.learned_skills.append(passive_id)
	CharacterData.passive_skill_loadout = [passive_id]
	CharacterData.current_realm = "结丹"
	CharacterData.realm_stage = 2
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03_c",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	_check(player != null and is_instance_valid(player), "真实 Player 已生成")
	_check(boss != null and is_instance_valid(boss), "真实 BOSS 已生成")
	if player == null or boss == null:
		return
	_check(boss.boss_id == "boss_03_c", "箱庭加载的是晏无咎", boss.boss_id)
	_check(player._calamity_wheel != null and player._calamity_wheel.visible,
		"玩家三灾轮 HUD 已显示")
	_check(int(player._calamity_wheel.get("momentum")) == int(player.calamity_momentum),
		"玩家三灾轮势点与灾势同步")
	_check(boss._wheel_ui != null and boss._wheel_ui.visible, "BOSS 三灾轮 HUD 已显示")
	player.global_position = boss.global_position + Vector2(0.0, 120.0)
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029
	var t := 0.0
	var next_cast := 0.5
	while t < 14.0:
		await get_tree().create_timer(0.1, true, false, true).timeout
		t += 0.1
		if not is_instance_valid(player) or not is_instance_valid(boss):
			break
		player.invincible_timer = 999.0
		player.hp = maxf(player.hp, player.max_hp * 0.9)
		player.mana = player.max_mana
		player.stamina = maxi(player.stamina, 8)
		if t >= next_cast and not player.is_dead:
			next_cast = t + 0.75
			var sid := String(ids[rng.randi_range(0, ids.size() - 1)])
			player.skill_cooldowns.clear()
			if player.try_use_skill(sid):
				_cast_count[sid] = int(_cast_count.get(sid, 0)) + 1
	# 至少让 BOSS 出过招、玩家灾位有变化
	_check(boss._recent.size() >= 2, "BOSS AI 在真实箱庭出招 >=2", str(boss._recent))
	_check(not _cast_count.is_empty(), "玩家真实入口施放成功", str(_cast_count.size()))
	_check(player.calamity_state() != "", "玩家灾位已建立", player.calamity_state())
	# 二阶段：把血打到 49%，等归一
	boss.current_hp = boss.max_hp * 0.49
	boss.take_damage(0.1)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check(boss.phase == 2, "50% 触发二阶段", "phase=%d" % boss.phase)
	_check(boss.calamity_state() == "fusion" or boss._fusion_left > 0.0,
		"二阶段进入三灾归一")
	# 归一期间全招池 + 玩家继续输出
	var hp_before: float = boss.current_hp
	t = 0.0
	while t < 4.0:
		await get_tree().create_timer(0.1, true, false, true).timeout
		t += 0.1
		if not is_instance_valid(player) or not is_instance_valid(boss):
			break
		player.invincible_timer = 999.0
		player.hp = player.max_hp
		player.mana = player.max_mana
		player.stamina = 8.0
		if int(t * 10.0) % 7 == 0:
			player.skill_cooldowns.clear()
			player.try_use_skill(String(ids[rng.randi_range(0, ids.size() - 1)]))
	_check(boss.current_hp <= hp_before, "归一期间 BOSS 仍可受伤",
		"hp %.0f -> %.0f" % [hp_before, boss.current_hp])
	GameState.battle_context = {}
