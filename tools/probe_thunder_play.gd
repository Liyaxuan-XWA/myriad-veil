extends Node
## 判词玩家侧 · 真实 CombatArena + 真实 Player + 赫连霄 AI 联调
## 目的：复现「玩家使用判词技能就崩溃」；走真实 try_use_skill 入口而不是内部 _cast_*。
## 用法：godot --headless --path . tools/probe_thunder_play.tscn -- --no-save

var _casts := {}
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
	print("\n########## 判词 · 真实箱庭施放探针 ##########")
	await _run()
	print("\n########## 结果：%d 项通过，%d 次施放，%d 项失败 ##########"
		% [_passes, _casts.size(), _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	var ids := ["skill_thunder_verdict", "skill_thunder_execute", "skill_thunder_drum",
		"skill_thunder_lock", "skill_thunder_step", "skill_thunder_gather",
		"skill_thunder_nine", "skill_thunder_prison"]
	CharacterData.learned_skills.clear()
	CharacterData.active_skill_loadout.clear()
	CharacterData.passive_skill_loadout.clear()
	for sid in ids:
		CharacterData.learned_skills.append(sid)
		CharacterData.active_skill_loadout.append(sid)
	CharacterData.current_realm = "结丹"
	CharacterData.realm_stage = 2
	GameState.battle_context = {
		"source": BattleResolver.SOURCE_DOMAIN,
		"domain_id": "domain_03",
		"boss_id": "boss_03",
	}
	BattleResolver.skip_next_intro = true
	var arena: Node = (load("res://scenes/combat/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	for i in 4:
		await get_tree().process_frame
	var player: Node2D = arena.player
	var boss: Node2D = arena.boss
	if player == null or boss == null:
		_fails.append("player/boss 未生成")
		return
	player.invincible_timer = 999.0
	player.hp = player.max_hp
	player.mana = player.max_mana
	player.stamina = maxi(player.stamina, 8)
	player.global_position = boss.global_position + Vector2(-180.0, 0.0)
	player.attack_dir = Vector2.RIGHT
	# 每门技能都从真实入口放一次；BOSS 锁血，不打断施放
	for sid in ids:
		if not is_instance_valid(player) or not is_instance_valid(boss):
			break
		boss.current_hp = boss.max_hp
		player.invincible_timer = 999.0
		player.hp = player.max_hp
		player.mana = player.max_mana
		player.stamina = maxi(player.stamina, 8)
		player.skill_cooldowns.clear()
		player.global_position = boss.global_position + Vector2(-180.0, 0.0)
		var ok = player.try_use_skill(String(sid))
		_casts[String(sid)] = int(_casts.get(String(sid), 0)) + 1
		print("CAST ", sid, " ok=", ok, " lei=", player.lei_shi)
		_check(ok, "真实入口施放 %s" % String(sid))
		await get_tree().create_timer(0.7, true, false, true).timeout
		if String(sid) == "skill_thunder_verdict":
			# 崩溃回归点：以前 _tick_thunder_law 每帧抛 bool 构造错误，
			# 判词会停在 5.0 秒不再前进；这里确认它真的在倒计时。
			_check(player._law_id != "", "判词已落到目标身上", player._law_id)
			_check(player._law2_id != "" and player._law2_id != player._law_id,
				"两条不同的判词同时生效", "%s / %s" % [player._law_id, player._law2_id])
			_check(player._law_left < player.THUNDER_LAW_TIME - 0.1,
				"判词逐帧推进（没有卡死）", "left=%.2f" % player._law_left)
		if not is_instance_valid(player):
			_fails.append("玩家在 %s 后失效" % String(sid))
			break
		if not is_instance_valid(boss):
			_fails.append("BOSS 在 %s 后失效" % String(sid))
			break
	_check(is_instance_valid(player) and not player.is_dead, "八式放完玩家仍存活")
	_check(is_instance_valid(boss), "八式放完 BOSS 仍存在")
	GameState.battle_context = {}
